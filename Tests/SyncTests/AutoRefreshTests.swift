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
		let giro = AccountRequest(accountID: UUID(), name: "Giro", remoteID: "1")
		let savings = AccountRequest(accountID: UUID(), name: "Savings", remoteID: "2")
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
		let giro = AccountRequest(accountID: UUID(), name: "Giro", remoteID: "1")
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
			coordinator.ended = { [unowned self] _, _, results in
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
		auto.tick()
		await until { !bank.coordinator.isRefreshing }
		#expect(center.log.count == 1)

		bank.refresh(bank.ledger.refreshAccounts(.all), attended: true)
		await until { bank.coordinator.broker.current?.access.id == kartenbank.id }
		bank.coordinator.cancelAll()
		await until { !bank.coordinator.isRefreshing }
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

	func post(_ notice: NewTransactionsNotice, sound: Bool) {
		log.append("post \(notice.title) | \(notice.body) | \(sound ? notice.tone.rawValue : "silent")")
	}

	func play(_ tone: NewTransactionsNotice.Tone) {
		log.append("play \(tone.rawValue)")
	}
}
