import Domain
import Foundation
import GRDB
@testable import Storage
import SyncTesting
import Testing
@testable import Sync

/// The automatic refresh and the notification about new transactions, with a scripted bank and a clock
/// that the tests set (add-account-refresh 1.4 to 1.11 and 1.29, add-notifications-and-menu-bar).
@MainActor
@Suite("Automatic refresh and notifications")
final class AutoRefreshTests {
	let suite = "MonetenTests-\(UUID().uuidString)"
	let settings: RefreshSettings
	/// Starts at the real time, because the coordinator records the end of a refresh with it.
	let start = Date()
	lazy var clock = start
	var runs: [Date] = []
	let center = RecordingCenter()

	init() throws {
		settings = RefreshSettings(defaults: try #require(UserDefaults(suiteName: suite)))
	}

	deinit {
		UserDefaults().removePersistentDomain(forName: suite)
	}

	func autoRefresh() -> AutoRefresh {
		let auto = AutoRefresh(settings: settings, now: { [unowned self] in clock })
		auto.run = { [unowned self] in runs.append($0) }
		return auto
	}

	/// An unlocked app on a Mac that is online and in use.
	func running() -> AutoRefresh {
		let auto = autoRefresh()
		auto.isOnline = true
		auto.isUnlocked = true
		runs = []
		return auto
	}

	// MARK: When the automatic refresh runs

	@Test("The settings start with the automatic refresh and the banner on, and the sound off")
	func defaults() {
		#expect(settings.automaticRefresh)
		#expect(settings.showsBanner)
		#expect(!settings.playsSound)
	}

	@Test("Each tick of the timer runs the automatic refresh with the time of the clock")
	func tick() {
		let auto = running()
		auto.tick()
		clock += 60
		auto.tick()
		#expect(runs == [start, start + 60])
	}

	@Test("With the setting off the timer runs nothing, and with it on again the next tick runs")
	func settingOff() {
		let auto = running()
		settings.defaults.set(false, forKey: RefreshSettings.automaticRefreshKey)
		auto.tick()
		#expect(runs.isEmpty)
		settings.defaults.set(true, forKey: RefreshSettings.automaticRefreshKey)
		auto.tick()
		#expect(runs.count == 1)
	}

	@Test("A locked app runs nothing, and the unlock runs the accounts that became due meanwhile")
	func lock() {
		let auto = running()
		auto.isUnlocked = false
		clock += 30 * 60
		auto.tick()
		#expect(runs.isEmpty)
		clock += 30 * 60
		auto.isUnlocked = true
		#expect(runs == [clock])
	}

	@Test("The launch runs once the app is unlocked and online, in either order")
	func launch() {
		let auto = autoRefresh()
		auto.isUnlocked = true
		#expect(runs.isEmpty)
		auto.isOnline = true
		#expect(runs == [clock])

		let other = autoRefresh()
		other.isOnline = true
		#expect(runs == [clock])
		other.isUnlocked = true
		#expect(runs == [clock, clock])
	}

	@Test("While the display sleeps nothing runs, also in Power Nap, and the wake runs at once")
	func sleep() {
		let auto = running()
		auto.isUserPresent = false
		clock += 3 * 3600
		auto.tick()
		#expect(runs.isEmpty)
		auto.isUserPresent = true
		#expect(runs == [clock])
	}

	@Test("Offline nothing runs and nothing fails, and the connection back runs at once")
	func offline() {
		let auto = running()
		auto.isOnline = false
		auto.tick()
		#expect(runs.isEmpty)
		auto.isOnline = true
		#expect(runs == [clock])
	}

	@Test("A condition that stays true runs nothing more")
	func noEdge() {
		let auto = running()
		auto.isUnlocked = true
		auto.isOnline = true
		auto.isUserPresent = true
		#expect(runs.isEmpty)
	}

	// MARK: One notification for each run

	static func access(_ bank: String) -> Access {
		Access(source: .fints(bankCode: "12030000", url: URL(string: "https://fints.example.com/")!), bankName: bank, loginName: "erika-\(bank)")
	}

	static let tan = UserRequest.secondFactor(SecondFactorRequest(purpose: .download, system: .fintsServer,
		challenge: .enterTAN(prompt: "TAN eingeben", image: nil)))

	@Test("The run ends once, after the last of several accesses, also when a refresh joins it while it runs")
	func runEndsOnce() async {
		let coordinator = SyncCoordinator()
		var ends = 0
		coordinator.runEnded = { ends += 1 }
		let giro = AccountRequest(accountID: UUID(), name: "Giro", remoteID: "1", currency: "EUR")
		let savings = AccountRequest(accountID: UUID(), name: "Savings", remoteID: "2", currency: "EUR")
		coordinator.refresh(RefreshRequest(access: Self.access("Musterbank"), accounts: [giro]),
			with: ScriptedConnector([.wait(.milliseconds(50)), .fetched(giro.accountID)]), attended: false)
		coordinator.refresh(RefreshRequest(access: Self.access("Beispielbank"), accounts: [savings]),
			with: ScriptedConnector([.wait(.milliseconds(100)), .fetched(savings.accountID)]), attended: false)
		await until { !coordinator.isRefreshing }
		#expect(ends == 1)
		coordinator.refresh(RefreshRequest(access: Self.access("Musterbank"), accounts: [giro]),
			with: ScriptedConnector([.fetched(giro.accountID)]), attended: true)
		await until { !coordinator.isRefreshing }
		#expect(ends == 2)
	}

	@Test("Cancel Refresh, as the lock does, ends the run once, after the canceled connector returned")
	func cancelEndsRun() async {
		let coordinator = SyncCoordinator()
		var ends = 0
		coordinator.runEnded = { ends += 1 }
		let giro = AccountRequest(accountID: UUID(), name: "Giro", remoteID: "1", currency: "EUR")
		coordinator.refresh(RefreshRequest(access: Self.access("Musterbank"), accounts: [giro]),
			with: ScriptedConnector([.wait(.seconds(10)), .fetched(giro.accountID)]), attended: false)
		coordinator.cancelAll()
		await until { !coordinator.isRefreshing }
		#expect(ends == 1)
	}

	@Test("New transactions of a run make one notification, with the sound only when the setting is on")
	func announce() throws {
		let account = Account(position: 0, name: "Girokonto", kind: .giro, source: .bank)
		let rows = [row(account, 320_000), row(account, -1_500)].map { var t = $0; t.isNew = true; return t }
		let ledger = Ledger(accounts: [account], transactions: rows)
		let announcer = NewTransactionsAnnouncer(settings: settings, center: center)
		announcer.stored(rows)
		announcer.runEnded(ledger: ledger)
		#expect(center.log == ["post 2 new transactions | Girokonto | silent"])

		settings.defaults.set(true, forKey: RefreshSettings.playsSoundKey)
		announcer.stored(rows)
		announcer.runEnded(ledger: ledger)
		#expect(center.log.last == "post 2 new transactions | Girokonto | positive")

		settings.defaults.set(false, forKey: RefreshSettings.showsBannerKey)
		announcer.stored(rows)
		announcer.runEnded(ledger: ledger)
		#expect(center.log.last == "play positive")

		settings.defaults.set(false, forKey: RefreshSettings.playsSoundKey)
		announcer.stored(rows)
		announcer.runEnded(ledger: ledger)
		announcer.runEnded(ledger: ledger)
		#expect(center.log.count == 3)
	}

	/// The app around the coordinator: the accounts in a database, the merge of fetched rows, and the
	/// status of each account after a refresh, as `AppModel` keeps them.
	@MainActor
	final class Bank {
		let store: Store
		var ledger: Ledger
		let coordinator = SyncCoordinator()
		var connectors: [UUID: ScriptedConnector] = [:]
		private(set) var accesses: [UUID: Access] = [:]

		init(accesses: [Access], accounts: [Account], announcer: NewTransactionsAnnouncer) throws {
			let queue = try DatabaseQueue()
			try Schema.migrator.migrate(queue)
			store = Store(queue: queue)
			for access in accesses {
				try store.add(access, state: nil, accounts: accounts.filter { $0.accessID == access.id })
				self.accesses[access.id] = access
			}
			ledger = try store.loadLedger()
			coordinator.deliver = { [unowned self] id, result in
				let merged = try store.merge(.refresh(result), into: id)
				ledger.apply(merged)
				announcer.stored(merged.added)
			}
			coordinator.ended = { [unowned self] _, _, results, _ in
				for (id, result) in results {
					guard var a = ledger.account(id) else { continue }
					a.record(result)
					ledger.upsert(a)
				}
			}
			coordinator.runEnded = { [unowned self] in announcer.runEnded(ledger: ledger) }
		}

		func refresh(_ plan: [UUID: [AccountRequest]], attended: Bool) {
			for (id, accounts) in plan {
				guard let access = accesses[id], let connector = connectors[id] else { continue }
				coordinator.refresh(RefreshRequest(access: access, accounts: accounts), with: connector, attended: attended)
			}
		}
	}

	@Test("An automatic refresh of three accesses makes one notification, skips and marks the access that needs a TAN, and the next manual refresh asks for it")
	func doneWhen() async throws {
		let musterbank = Self.access("Musterbank"), beispielbank = Self.access("Beispielbank"), kartenbank = Self.access("Kartenbank")
		let giro = Account(position: 0, name: "Girokonto", kind: .giro, source: .bank, accessID: musterbank.id, remoteID: "1")
		let savings = Account(position: 1, name: "Tagesgeld", kind: .savings, source: .bank, accessID: beispielbank.id, remoteID: "2")
		let card = Account(position: 2, name: "Kreditkarte", kind: .creditCard, source: .bank, accessID: kartenbank.id, remoteID: "3")
		let announcer = NewTransactionsAnnouncer(settings: settings, center: center)
		let bank = try Bank(accesses: [musterbank, beispielbank, kartenbank], accounts: [giro, savings, card], announcer: announcer)
		let salary = row(giro, 320_000), rent = row(giro, -95_000), saving = row(savings, 50_000)
		bank.connectors = [
			musterbank.id: ScriptedConnector([.ask(.pin(PINRequest())), .fetched(giro.id, fetched([salary, rent]))]),
			beispielbank.id: ScriptedConnector([.fetched(savings.id, fetched([saving]))]),
			kartenbank.id: ScriptedConnector([.ask(Self.tan), .fetched(card.id, fetched([row(card, -2_000)]))]),
		]
		// The PIN of the Musterbank is in memory, as after a manual refresh earlier in this run of the app.
		try bank.coordinator.broker.remember(Secret("1234"), for: musterbank.id, save: false)
		let auto = AutoRefresh(settings: settings, now: { [unowned self] in clock })
		auto.run = { bank.refresh(bank.ledger.dueAccounts(at: $0), attended: false) }
		auto.isOnline = true
		auto.isUnlocked = true
		await until { !bank.coordinator.isRefreshing }

		#expect(center.log == ["post 3 new transactions | Girokonto, Tagesgeld | silent"])
		#expect(bank.ledger.account(card.id)?.refreshError?.message == "An authorization is needed. Choose “Refresh Account” to give it.")
		#expect(bank.ledger.account(card.id)?.refreshError?.waitsForUser == true)
		#expect(bank.ledger.account(giro.id)?.refreshError == nil)
		#expect(bank.coordinator.states[kartenbank.id] == .failed(.needsUser(.secondFactor)))

		// Two hours later the same rows come again: nothing new, so no second notification, and the access with the TAN stays out.
		clock += 2 * 3600 + 120
		#expect(bank.ledger.dueAccounts(at: clock).keys.sorted() == [musterbank.id, beispielbank.id].sorted())
		let firstRefresh = bank.ledger.account(giro.id)?.refreshedAt
		auto.tick()
		await until { bank.ledger.account(giro.id)?.refreshedAt != firstRefresh && !bank.coordinator.isRefreshing }
		#expect(bank.connectors[musterbank.id]?.answers.all.count == 2)
		#expect(center.log.count == 1)

		bank.refresh(bank.ledger.refreshAccounts(.all), attended: true)
		await until { bank.coordinator.broker.current?.access.id == kartenbank.id }
		bank.coordinator.cancelAll()
		await until { !bank.coordinator.isRefreshing }
	}

	// MARK: Manual and automatic refreshes of one access

	static let giro = AccountRequest(accountID: UUID(), name: "Giro", remoteID: "1", currency: "EUR")
	static let savings = AccountRequest(accountID: UUID(), name: "Savings", remoteID: "2", currency: "EUR")
	static let card = AccountRequest(accountID: UUID(), name: "Card", remoteID: "3", currency: "EUR")

	@Test("A manual refresh during an automatic one of the same account shows the TAN dialog that the bank asks for")
	func manualJoinsAutomatic() async {
		let coordinator = SyncCoordinator()
		let bank = Self.access("Musterbank")
		coordinator.refresh(RefreshRequest(access: bank, accounts: [Self.giro]),
			with: ScriptedConnector([.wait(.milliseconds(200)), .ask(Self.tan), .fetched(Self.giro.accountID)]), attended: false)
		coordinator.refresh(RefreshRequest(access: bank, accounts: [Self.giro]), with: ScriptedConnector([]), attended: true)
		await until { coordinator.broker.current != nil }
		#expect(coordinator.broker.current?.request == Self.tan)
		coordinator.cancelAll()
		await until { !coordinator.isRefreshing }
	}

	@Test("A manual refresh during an automatic one that needs no dialog logs in once")
	func manualJoinsWithoutSecondLogin() async throws {
		let coordinator = SyncCoordinator()
		let bank = Self.access("Musterbank")
		try coordinator.broker.remember(Secret("1234"), for: bank.id, save: false)
		let connector = ScriptedConnector([.wait(.milliseconds(100)), .ask(.pin(PINRequest())), .fetched(Self.giro.accountID)])
		coordinator.refresh(RefreshRequest(access: bank, accounts: [Self.giro]), with: connector, attended: false)
		coordinator.refresh(RefreshRequest(access: bank, accounts: [Self.giro]), with: connector, attended: true)
		await until { !coordinator.isRefreshing }
		#expect(connector.answers.all.count == 1)
		#expect(coordinator.states[bank.id].map { if case .finished = $0 { true } else { false } } == true)
	}

	@Test("A manual refresh of an automatic one that waits for its turn makes it ask the user when it starts")
	func manualUpgradesWaiting() async {
		let coordinator = SyncCoordinator(limit: 1)
		let first = Self.access("Beispielbank"), bank = Self.access("Musterbank")
		coordinator.refresh(RefreshRequest(access: first, accounts: [Self.savings]),
			with: ScriptedConnector([.wait(.milliseconds(100)), .fetched(Self.savings.accountID)]), attended: false)
		coordinator.refresh(RefreshRequest(access: bank, accounts: [Self.giro]),
			with: ScriptedConnector([.ask(Self.tan), .fetched(Self.giro.accountID)]), attended: false)
		coordinator.refresh(RefreshRequest(access: bank, accounts: [Self.giro]), with: ScriptedConnector([]), attended: true)
		await until { coordinator.broker.current != nil }
		#expect(coordinator.broker.current?.access.id == bank.id)
		coordinator.cancelAll()
		await until { !coordinator.isRefreshing }
	}

	@Test("A manual refresh that comes after the automatic one already failed for want of the user runs the access again and asks",
		arguments: [
			UserRequest.secondFactor(SecondFactorRequest(purpose: .download, system: .fintsServer, challenge: .enterTAN(prompt: "TAN eingeben", image: nil))),
			.pin(PINRequest(rejected: BankMessage(code: "9942", text: "PIN falsch"))),
		])
	func manualAfterFailedAsk(request: UserRequest) async {
		let coordinator = SyncCoordinator()
		let bank = Self.access("Musterbank")
		let gate = FailureWithStateTests.Gate()
		let connector = HeldFailure(request: request, account: Self.giro.accountID, gate: gate, holdsCancel: false)
		coordinator.refresh(RefreshRequest(access: bank, accounts: [Self.giro]), with: connector, attended: false)
		await until { gate.isWaiting }
		coordinator.refresh(RefreshRequest(access: bank, accounts: [Self.giro]), with: connector, attended: true)
		gate.open()
		await until { coordinator.broker.current != nil }
		#expect(coordinator.broker.current?.request.kind == request.kind)
		coordinator.cancelAll()
		await until { !coordinator.isRefreshing }
	}

	@Test("A blocked access does not run again after a manual refresh joined the automatic one")
	func blockedAccessRunsOnce() async {
		let coordinator = SyncCoordinator()
		let bank = Self.access("Musterbank")
		let gate = FailureWithStateTests.Gate()
		let connector = HeldFailure(request: Self.tan, account: Self.giro.accountID, gate: gate, holdsCancel: false,
			failure: .accessBlocked(BankMessage(code: "9931", text: "Zugang gesperrt")))
		coordinator.refresh(RefreshRequest(access: bank, accounts: [Self.giro]), with: connector, attended: false)
		await until { gate.isWaiting }
		coordinator.refresh(RefreshRequest(access: bank, accounts: [Self.giro]), with: connector, attended: true)
		gate.open()
		await until { !coordinator.isRefreshing }
		#expect(coordinator.states[bank.id] == .failed(.accessBlocked(BankMessage(code: "9931", text: "Zugang gesperrt"))))
		#expect(coordinator.broker.current == nil)
	}

	@Test("An automatic refresh of another account of an access that the user refreshes never asks the user")
	func automaticBesideManual() async {
		let coordinator = SyncCoordinator()
		let bank = Self.access("Musterbank")
		coordinator.refresh(RefreshRequest(access: bank, accounts: [Self.giro]),
			with: ScriptedConnector([.wait(.milliseconds(100)), .fetched(Self.giro.accountID)]), attended: true)
		coordinator.refresh(RefreshRequest(access: bank, accounts: [Self.savings]),
			with: ScriptedConnector([.ask(Self.tan), .fetched(Self.savings.accountID)]), attended: false)
		await until { !coordinator.isRefreshing }
		#expect(coordinator.broker.current == nil)
		#expect(coordinator.states[bank.id] == .failed(.needsUser(.secondFactor)))
	}

	@Test("An automatic refresh of another account never joins a manual refresh that waits, in the queue or after a run",
		arguments: ["queue", "after a run"])
	func automaticBesideWaitingManual(place: String) async {
		let coordinator = SyncCoordinator(limit: 1)
		let bank = Self.access("Musterbank")
		let gate = FailureWithStateTests.Gate()
		let holder = place == "queue" ? Self.access("Beispielbank") : bank
		coordinator.refresh(RefreshRequest(access: holder, accounts: [Self.card]), with: GatedFetch(gate: gate), attended: false)
		await until { gate.isWaiting }
		let musterbank = AsksForAccount(account: Self.savings.accountID, request: Self.tan)
		coordinator.refresh(RefreshRequest(access: bank, accounts: [Self.giro]), with: musterbank, attended: true)
		coordinator.refresh(RefreshRequest(access: bank, accounts: [Self.savings]), with: musterbank, attended: false)
		gate.open()
		await until { !coordinator.isRefreshing }
		#expect(coordinator.broker.current == nil)
		#expect(coordinator.states[bank.id].map { if case .finished = $0 { true } else { false } } == true)
	}

	@Test("An automatic request that waits after a failed automatic run stays out of the run that the command starts again")
	func automaticStaysOutOfTheRunAgain() async {
		let coordinator = SyncCoordinator()
		let bank = Self.access("Musterbank")
		let gate = FailureWithStateTests.Gate()
		let connector = HeldFailure(request: Self.tan, account: Self.giro.accountID, gate: gate, holdsCancel: false)
		coordinator.refresh(RefreshRequest(access: bank, accounts: [Self.giro]), with: connector, attended: false)
		await until { gate.isWaiting }
		// The automatic run failed for want of the user and ends its dialog with the bank. The user refreshes
		// Giro, and then a tick finds Card due.
		coordinator.refresh(RefreshRequest(access: bank, accounts: [Self.giro]), with: connector, attended: true)
		coordinator.refresh(RefreshRequest(access: bank, accounts: [Self.card]), with: connector, attended: false)
		gate.open()
		await until { coordinator.broker.current != nil }
		#expect(coordinator.broker.current?.accountNames == ["Giro"])
		coordinator.cancelAll()
		await until { !coordinator.isRefreshing }
	}

	@Test("An automatic request that waits after a run stays unattended when a command names only accounts of that run")
	func automaticWaitingStaysUnattended() async {
		let coordinator = SyncCoordinator()
		let bank = Self.access("Musterbank")
		let gate = FailureWithStateTests.Gate()
		coordinator.refresh(RefreshRequest(access: bank, accounts: [Self.giro]), with: GatedFetch(gate: gate), attended: false)
		await until { gate.isWaiting }
		// A tick finds Card due while Giro runs, and then the user refreshes Giro.
		coordinator.refresh(RefreshRequest(access: bank, accounts: [Self.card]), with: AsksForAccount(account: Self.card.accountID, request: Self.tan),
			attended: false)
		coordinator.refresh(RefreshRequest(access: bank, accounts: [Self.giro]), with: GatedFetch(gate: gate), attended: true)
		gate.open()
		await until { !coordinator.isRefreshing }
		#expect(coordinator.broker.current == nil)
		#expect(coordinator.states[bank.id] == .failed(.needsUser(.secondFactor)))
	}

	@Test("A command for an account that waits after a run makes that waiting refresh ask")
	func manualUpgradesWaitingAfterRun() async {
		let coordinator = SyncCoordinator()
		let bank = Self.access("Musterbank")
		let gate = FailureWithStateTests.Gate()
		coordinator.refresh(RefreshRequest(access: bank, accounts: [Self.giro]), with: GatedFetch(gate: gate), attended: false)
		await until { gate.isWaiting }
		let card = AsksForAccount(account: Self.card.accountID, request: Self.tan)
		coordinator.refresh(RefreshRequest(access: bank, accounts: [Self.card]), with: card, attended: false)
		coordinator.refresh(RefreshRequest(access: bank, accounts: [Self.card]), with: card, attended: true)
		gate.open()
		await until { coordinator.broker.current != nil }
		#expect(coordinator.broker.current?.accountNames == ["Card"])
		coordinator.cancelAll()
		await until { !coordinator.isRefreshing }
	}

	@Test("A command for another account leaves a running automatic refresh unattended")
	func runningStaysUnattended() async {
		let coordinator = SyncCoordinator()
		let bank = Self.access("Musterbank")
		let gate = FailureWithStateTests.Gate()
		coordinator.refresh(RefreshRequest(access: bank, accounts: [Self.giro]), with: GatedAsk(gate: gate, request: Self.tan, account: Self.giro.accountID),
			attended: false)
		await until { gate.isWaiting }
		coordinator.refresh(RefreshRequest(access: bank, accounts: [Self.card]), with: AsksForAccount(account: Self.card.accountID, request: Self.tan),
			attended: true)
		gate.open()
		await until { coordinator.broker.current != nil }
		#expect(coordinator.broker.current?.accountNames == ["Card"])
		coordinator.cancelAll()
		await until { !coordinator.isRefreshing }
	}

	@Test("A PIN typed into a refresh that a command made attended is not asked again when the bank rejects it")
	func rejectedTypedPIN() async {
		let coordinator = SyncCoordinator()
		let bank = Self.access("Musterbank")
		let rejected = SyncFailure.pinRejected(BankMessage(code: "9942", text: "PIN falsch"))
		coordinator.refresh(RefreshRequest(access: bank, accounts: [Self.giro]),
			with: ScriptedConnector([.wait(.milliseconds(100)), .ask(.pin(PINRequest())), .fail(rejected)]), attended: false)
		coordinator.refresh(RefreshRequest(access: bank, accounts: [Self.giro]), with: ScriptedConnector([]), attended: true)
		await until { coordinator.broker.current != nil }
		if let id = coordinator.broker.current?.id { coordinator.broker.answer(.pin(Secret("0000")), to: id) }
		await until { !coordinator.isRefreshing }
		#expect(coordinator.broker.current == nil)
		#expect(coordinator.states[bank.id] == .failed(rejected))
	}

	@Test("An automatic refresh that comes while a canceled manual refresh still ends never asks the user")
	func automaticAfterCanceledManual() async {
		let coordinator = SyncCoordinator()
		let bank = Self.access("Musterbank")
		let gate = FailureWithStateTests.Gate()
		coordinator.refresh(RefreshRequest(access: bank, accounts: [Self.giro]),
			with: HeldFailure(request: Self.tan, account: Self.giro.accountID, gate: gate, holdsCancel: true), attended: true)
		await until { coordinator.broker.current != nil }
		coordinator.cancelAll()
		await until { gate.isWaiting }
		coordinator.refresh(RefreshRequest(access: bank, accounts: [Self.giro]),
			with: ScriptedConnector([.ask(Self.tan), .fetched(Self.giro.accountID)]), attended: false)
		gate.open()
		await until { !coordinator.isRefreshing }
		#expect(coordinator.broker.current == nil)
		#expect(coordinator.states[bank.id] == .failed(.needsUser(.secondFactor)))
	}

	@Test("The end of a refresh says whether it could ask the user, and so does a running one", arguments: [false, true])
	func endSaysAttended(attended: Bool) async {
		let coordinator = SyncCoordinator()
		let bank = Self.access("Musterbank")
		var ends: [Bool] = []
		coordinator.ended = { _, _, _, attended in ends.append(attended) }
		coordinator.refresh(RefreshRequest(access: bank, accounts: [Self.giro]),
			with: ScriptedConnector([.wait(.milliseconds(50)), .fetched(Self.giro.accountID)]), attended: attended)
		#expect(coordinator.runsUnattended(bank.id) == !attended)
		await until { !coordinator.isRefreshing }
		#expect(ends == [attended])
		#expect(!coordinator.runsUnattended(bank.id))
	}

	@Test("Cancel in the TAN dialog reports the accounts that the user canceled, and the lock reports none")
	func dialogCancel() async {
		let coordinator = SyncCoordinator()
		var canceled: [Set<UUID>] = []
		coordinator.userCanceled = { canceled.append($0) }
		coordinator.refresh(RefreshRequest(access: Self.access("Musterbank"), accounts: [Self.giro]),
			with: ScriptedConnector([.ask(Self.tan), .fetched(Self.giro.accountID)]), attended: true)
		await until { coordinator.broker.current != nil }
		if let id = coordinator.broker.current?.id { coordinator.broker.cancel(id) }
		await until { !coordinator.isRefreshing }
		#expect(canceled == [[Self.giro.accountID]])

		coordinator.refresh(RefreshRequest(access: Self.access("Beispielbank"), accounts: [Self.savings]),
			with: ScriptedConnector([.wait(.seconds(5)), .fetched(Self.savings.accountID)]), attended: false)
		coordinator.cancelAll()
		await until { !coordinator.isRefreshing }
		#expect(canceled.count == 1)
	}

	// MARK: Blockers for a waiting automatic refresh

	@Test("An automatic refresh that waits for its turn does not start once the Mac is offline, asleep, or the setting is off",
		arguments: ["offline", "asleep", "setting off"])
	func blockedWhileWaiting(blocker: String) async {
		let coordinator = SyncCoordinator(limit: 1)
		let auto = running()
		coordinator.mayStartUnattended = { auto.allowsUnattended }
		var ends = 0
		coordinator.runEnded = { ends += 1 }
		let second = ScriptedConnector([.ask(.pin(PINRequest())), .fetched(Self.savings.accountID)])
		coordinator.refresh(RefreshRequest(access: Self.access("Musterbank"), accounts: [Self.giro]),
			with: ScriptedConnector([.wait(.milliseconds(100)), .fetched(Self.giro.accountID)]), attended: false)
		coordinator.refresh(RefreshRequest(access: Self.access("Beispielbank"), accounts: [Self.savings]), with: second, attended: false)
		switch blocker {
		case "offline": auto.isOnline = false
		case "asleep": auto.isUserPresent = false
		default: settings.defaults.set(false, forKey: RefreshSettings.automaticRefreshKey)
		}
		await until { !coordinator.isRefreshing }
		#expect(coordinator.states.count == 1)
		#expect(!coordinator.refreshingAccounts.contains(Self.savings.accountID))
		#expect(ends == 1)
	}

	@Test("A manual refresh that waits for its turn starts also while the automatic refresh is blocked")
	func manualNotBlocked() async {
		let coordinator = SyncCoordinator(limit: 1)
		let auto = running()
		coordinator.mayStartUnattended = { auto.allowsUnattended }
		let bank = Self.access("Beispielbank")
		coordinator.refresh(RefreshRequest(access: Self.access("Musterbank"), accounts: [Self.giro]),
			with: ScriptedConnector([.wait(.milliseconds(100)), .fetched(Self.giro.accountID)]), attended: false)
		coordinator.refresh(RefreshRequest(access: bank, accounts: [Self.savings]), with: ScriptedConnector([.fetched(Self.savings.accountID)]), attended: true)
		auto.isUserPresent = false
		await until { !coordinator.isRefreshing }
		#expect(coordinator.states[bank.id].map { if case .finished = $0 { true } else { false } } == true)
	}

	// MARK: The lock and the notification

	@Test("A lock that ends a run at once names no account and counts only the rows that are still new")
	func lockEndsRunAtOnce() async throws {
		let coordinator = SyncCoordinator()
		let announcer = NewTransactionsAnnouncer(settings: settings, center: center)
		let account = Account(position: 0, name: "Girokonto", kind: .giro, source: .bank)
		var seen = row(account, -100), fresh = row(account, -200)
		fresh.isNew = true
		seen.isNew = false
		let ledger = Ledger(accounts: [account], transactions: [seen, fresh])
		coordinator.deliver = { _, _ in announcer.stored([seen, fresh]) }
		coordinator.runEnded = { announcer.runEnded(ledger: ledger) }
		let held = Self.access("Musterbank")
		let release = Flag()
		let hold = Task { try await coordinator.exclusively(for: held.id) { while !release.isOn { try await Task.sleep(for: .milliseconds(10)) } } }
		// The hold starts with the first step of its task.
		try await Task.sleep(for: .milliseconds(20))
		coordinator.refresh(RefreshRequest(access: held, accounts: [Self.giro]), with: ScriptedConnector([.fetched(Self.giro.accountID)]), attended: false)
		coordinator.refresh(RefreshRequest(access: Self.access("Beispielbank"), accounts: [Self.savings]),
			with: ScriptedConnector([.fetched(Self.savings.accountID)]), attended: false)
		await until { coordinator.states.count == 1 && !coordinator.refreshingAccounts.contains(Self.savings.accountID) }
		#expect(center.log.isEmpty)

		announcer.lock(keeping: ledger)
		coordinator.cancelAll()
		#expect(center.log == ["post 1 new transaction |  | silent"])
		release.isOn = true
		_ = try? await hold.value
	}

	@Test("A notification that waits for the permission of macOS loses its account names when the app locks meanwhile")
	func lockBeforeShown() throws {
		let account = Account(position: 0, name: "Girokonto", kind: .giro, source: .bank)
		var rows = [row(account, 320_000)]
		rows[0].isNew = true
		let ledger = Ledger(accounts: [account], transactions: rows)
		let announcer = NewTransactionsAnnouncer(settings: settings, center: center)
		center.holds = true
		announcer.stored(rows)
		announcer.runEnded(ledger: ledger)
		announcer.lock(keeping: ledger)
		center.showWaiting()
		#expect(center.log == ["post 1 new transaction |  | silent"])
	}

	func row(_ account: Account, _ amount: Int64) -> Transaction {
		Transaction(accountID: account.id, bookingDate: Day(year: 2026, month: 10, day: 30), amountMinor: amount, name: "Musterfirma GmbH",
			purpose: "Buchung \(amount)", isFetched: true)
	}

	func fetched(_ rows: [Transaction]) -> RefreshResult {
		RefreshResult(balance: nil, transactions: FetchedTransactions(rows: rows, from: Day(year: 2026, month: 10, day: 1)))
	}

	/// Waits until the condition holds, for at most two seconds.
	func until(_ condition: () -> Bool, sourceLocation: SourceLocation = #_sourceLocation) async {
		for _ in 0..<200 where !condition() {
			try? await Task.sleep(for: .milliseconds(10))
		}
		#expect(condition(), sourceLocation: sourceLocation)
	}
}

/// Records what the app would show and play.
@MainActor
final class RecordingCenter: NoticeCenter {
	var log: [String] = []

	/// The notices that wait to be shown, as the app waits for the permission of macOS.
	var waiting: [(sound: Bool, notice: @MainActor @Sendable () -> NewTransactionsNotice)] = []
	var holds = false

	func post(sound: Bool, _ notice: @escaping @MainActor @Sendable () -> NewTransactionsNotice) {
		if holds { waiting.append((sound, notice)) } else { show(sound: sound, notice()) }
	}

	func showWaiting() {
		for (sound, notice) in waiting { show(sound: sound, notice()) }
		waiting = []
	}

	private func show(sound: Bool, _ notice: NewTransactionsNotice) {
		log.append("post \(notice.title) | \(notice.body) | \(sound ? notice.tone.rawValue : "silent")")
	}

	func play(_ tone: NewTransactionsNotice.Tone) {
		log.append("play \(tone.rawValue)")
	}
}

/// Asks once and, after a failure, holds its end until the test opens the gate, as the FinTS helper ends
/// its dialog with the bank. Without `holdsCancel` a cancel ends it at once. `failure` replaces the error
/// of the request, as a bank that blocks the access answers.
struct HeldFailure: BankConnector {
	let request: UserRequest
	let account: UUID
	let gate: FailureWithStateTests.Gate
	let holdsCancel: Bool
	var failure: SyncFailure?

	func refresh(_ refresh: RefreshRequest, _ session: SyncSession) async throws -> ConnectorReport {
		do {
			_ = try await session.ask(request)
		} catch {
			if holdsCancel || !(error is CancellationError) { await gate.wait() }
			throw failure ?? error
		}
		return ConnectorReport(outcomes: [account: .fetched(RefreshResult(balance: nil, transactions: nil))])
	}
}

/// Fetches every requested account after the test opens the gate.
struct GatedFetch: BankConnector {
	let gate: FailureWithStateTests.Gate

	func refresh(_ refresh: RefreshRequest, _ session: SyncSession) async throws -> ConnectorReport {
		await gate.wait()
		return ConnectorReport(outcomes: Dictionary(uniqueKeysWithValues: refresh.accounts.map { ($0.accountID, .fetched(RefreshResult(balance: nil, transactions: nil))) }))
	}
}

/// Asks `request` after the test opens the gate, as a bank that wants a TAN in the middle of a refresh.
struct GatedAsk: BankConnector {
	let gate: FailureWithStateTests.Gate
	let request: UserRequest
	let account: UUID

	func refresh(_ refresh: RefreshRequest, _ session: SyncSession) async throws -> ConnectorReport {
		await gate.wait()
		_ = try await session.ask(request)
		return ConnectorReport(outcomes: [account: .fetched(RefreshResult(balance: nil, transactions: nil))])
	}
}

/// One bank for all accounts of an access, which asks `request` when the refresh includes `account`.
struct AsksForAccount: BankConnector {
	let account: UUID
	let request: UserRequest

	func refresh(_ refresh: RefreshRequest, _ session: SyncSession) async throws -> ConnectorReport {
		if refresh.accounts.contains(where: { $0.accountID == account }) { _ = try await session.ask(request) }
		return ConnectorReport(outcomes: Dictionary(uniqueKeysWithValues: refresh.accounts.map { ($0.accountID, .fetched(RefreshResult(balance: nil, transactions: nil))) }))
	}
}

/// Ends the work that holds an access.
@MainActor
final class Flag {
	var isOn = false
}
