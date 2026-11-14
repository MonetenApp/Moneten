import Domain
import Foundation
import Storage
import Synchronization
import SyncTesting
import Testing
@testable import Sync

/// login-credentials: a PIN is saved only on request and only after the bank accepted it, it answers
/// the refreshes after a restart, and "Remove saved PIN" and a rejection delete it.
@MainActor
@Suite("Saved PINs")
struct SavedPINTests {
	let coordinator = SyncCoordinator()
	var broker: SessionBroker { coordinator.broker }
	let store = MemoryPINStore()
	static let bank = Access(source: .fints(bankCode: "12030000", url: URL(string: "https://fints.example.com/")!), bankName: "Musterbank", loginName: "erika77")
	static let giro = AccountRequest(accountID: UUID(), name: "Giro", remoteID: "1234", currency: "EUR")
	static let pin = UserRequest.pin(PINRequest())
	static let rejected = UserRequest.pin(PINRequest(rejected: BankMessage(code: "9942", text: "PIN falsch")))

	init() throws {
		try broker.open(store)
	}

	func refresh(_ steps: [ScriptedConnector.Step], attended: Bool = true, in coordinator: SyncCoordinator? = nil) -> ScriptedConnector {
		let connector = ScriptedConnector(steps)
		(coordinator ?? self.coordinator).refresh(RefreshRequest(access: Self.bank, accounts: [Self.giro]), with: connector, attended: attended)
		return connector
	}

	func answer(_ answer: UserAnswer) {
		if let id = broker.current?.id { broker.answer(answer, to: id) }
	}

	@Test("A PIN is saved only when the user turns saving on, and only after the refresh with it finished")
	func savedAfterSuccess() async {
		_ = refresh([.ask(Self.pin), .wait(.milliseconds(300)), .fetched(Self.giro.accountID)])
		await until { broker.current != nil }
		answer(.pin(Secret("12345"), save: true))
		try? await Task.sleep(for: .milliseconds(100))
		#expect(store.pins.isEmpty)
		await until { !coordinator.isRefreshing }
		#expect(store.pins == [Self.bank.id: Secret("12345")])
		#expect(broker.savedPINs == [Self.bank.id])
	}

	@Test("A PIN with the option off stays in memory and is never saved")
	func optionOff() async {
		_ = refresh([.ask(Self.pin), .fetched(Self.giro.accountID)])
		await until { broker.current != nil }
		answer(.pin(Secret("12345")))
		await until { !coordinator.isRefreshing }
		#expect(store.pins.isEmpty)
		#expect(broker.savedPINs.isEmpty)
		let second = refresh([.ask(Self.pin)])
		await until { !coordinator.isRefreshing }
		#expect(second.answers.all == [.pin(Secret("12345"))])
	}

	@Test("A PIN with the option on is not saved when the bank rejects it, and the PIN after the typing error is")
	func notSavedOnRejection() async {
		_ = refresh([.ask(Self.pin), .fail(.pinRejected(BankMessage(code: "9942", text: "PIN falsch")))])
		await until { broker.current != nil }
		answer(.pin(Secret("11111"), save: true))
		await until { !coordinator.isRefreshing }
		#expect(store.pins.isEmpty)

		_ = refresh([.ask(Self.pin), .ask(Self.rejected), .fetched(Self.giro.accountID)])
		await until { broker.current?.request == Self.pin }
		answer(.pin(Secret("11111"), save: true))
		await until { broker.current?.request == Self.rejected }
		answer(.pin(Secret("22222"), save: true))
		await until { !coordinator.isRefreshing }
		#expect(store.pins == [Self.bank.id: Secret("22222")])
	}

	@Test("A saved PIN answers the refreshes after a restart without a sheet, also the automatic one")
	func afterRestart() async throws {
		let folder = DataFolder(root: FileManager.default.temporaryDirectory.appendingPathComponent("MonetenTests-\(UUID().uuidString)"))
		let vault = Vault(folder: folder)
		let database = try vault.create(password: "korrekt-pferd-batterie", starterCategories: [])
		try database.add(Self.bank, state: nil, accounts: [])
		try broker.open(database)
		_ = refresh([.ask(Self.pin), .fetched(Self.giro.accountID)])
		await until { broker.current != nil }
		answer(.pin(Secret("48151"), save: true))
		await until { !coordinator.isRefreshing }
		broker.forgetPINs()
		try database.close()

		let restarted = SyncCoordinator()
		try restarted.broker.open(try vault.open(password: "korrekt-pferd-batterie"))
		let automatic = refresh([.ask(Self.pin), .fetched(Self.giro.accountID)], attended: false, in: restarted)
		await until { !restarted.isRefreshing }
		#expect(automatic.answers.all == [.pin(Secret("48151"))])
		guard case .finished = restarted.states[Self.bank.id] else { Issue.record("not finished"); return }
		#expect(restarted.broker.current == nil)
		#expect(restarted.broker.savedPINs == [Self.bank.id])
	}

	@Test("A saved PIN that the bank rejects is deleted and never sent again, and the next manual refresh asks")
	func savedRejected() async throws {
		try store.savePIN(Secret("12345"), for: Self.bank.id)
		try broker.open(store)
		let automatic = refresh([.ask(Self.pin), .ask(Self.rejected), .fetched(Self.giro.accountID)], attended: false)
		await until { !coordinator.isRefreshing }
		#expect(automatic.answers.all == [.pin(Secret("12345"))])
		#expect(coordinator.states[Self.bank.id] == .failed(.pinRejected(BankMessage(code: "9942", text: "PIN falsch"))))
		#expect(store.pins.isEmpty)
		#expect(broker.savedPINs.isEmpty)

		_ = refresh([.ask(Self.pin)])
		await until { broker.current?.request == Self.pin }
		broker.cancel(broker.current!.id)
		await until { !coordinator.isRefreshing }
	}

	@Test("A saved PIN stays after a failure that is not about the PIN")
	func savedAfterOtherFailure() async throws {
		try store.savePIN(Secret("12345"), for: Self.bank.id)
		try broker.open(store)
		_ = refresh([.ask(Self.pin), .fail(.offline)])
		await until { !coordinator.isRefreshing }
		let next = refresh([.ask(Self.pin)])
		await until { !coordinator.isRefreshing }
		#expect(next.answers.all == [.pin(Secret("12345"))])
		#expect(store.pins == [Self.bank.id: Secret("12345")])
	}

	@Test("Remove saved PIN deletes the PIN of the access, and the next refresh asks for it")
	func remove() async throws {
		try store.savePIN(Secret("12345"), for: Self.bank.id)
		try broker.open(store)
		#expect(broker.savedPINs == [Self.bank.id])
		try broker.removeSavedPIN(of: Self.bank.id)
		#expect(store.pins.isEmpty)
		#expect(broker.savedPINs.isEmpty)
		_ = refresh([.ask(Self.pin)])
		await until { broker.current?.request == Self.pin }
		broker.cancel(broker.current!.id)
		await until { !coordinator.isRefreshing }
	}

	@Test("The PIN of the setup is saved at once when the user turned saving on, because the bank accepted it")
	func setup() throws {
		let other = UUID()
		try broker.remember(Secret("12345"), for: Self.bank.id, save: true)
		try broker.remember(Secret("54321"), for: other, save: false)
		#expect(store.pins == [Self.bank.id: Secret("12345")])
		#expect(broker.savedPINs == [Self.bank.id])
	}

	@Test("Adding the login again replaces its saved PIN with the PIN the bank accepted, also with saving off")
	func setupReplacesSavedPIN() throws {
		try store.savePIN(Secret("12345"), for: Self.bank.id)
		try broker.open(store)
		try broker.remember(Secret("67890"), for: Self.bank.id, save: false)
		#expect(store.pins == [Self.bank.id: Secret("67890")])
		#expect(broker.savedPINs == [Self.bank.id])
	}

	@Test("A blocked access loses its saved PIN and the PIN in memory without a new PIN sheet, and the next manual refresh asks")
	func blockedDeletesPIN() async throws {
		try store.savePIN(Secret("12345"), for: Self.bank.id)
		try broker.open(store)
		let blocked = BankMessage(code: "9930", text: "Zugang gesperrt")
		let automatic = refresh([.ask(Self.pin), .fail(.accessBlocked(blocked))], attended: false)
		await until { !coordinator.isRefreshing }
		#expect(automatic.answers.all == [.pin(Secret("12345"))])
		#expect(coordinator.states[Self.bank.id] == .failed(.accessBlocked(blocked)))
		#expect(broker.current == nil)
		#expect(store.pins.isEmpty)
		#expect(broker.savedPINs.isEmpty)

		let manual = refresh([.ask(Self.pin)])
		await until { broker.current?.request == Self.pin }
		broker.cancel(try #require(broker.current).id)
		await until { !coordinator.isRefreshing }
		#expect(manual.answers.all.isEmpty)
	}

	@Test("A PIN in memory that was not saved is forgotten when the access is blocked")
	func blockedForgetsPIN() async {
		_ = refresh([.ask(Self.pin), .fail(.accessBlocked(BankMessage(code: "9930", text: "Zugang gesperrt")))])
		await until { broker.current != nil }
		answer(.pin(Secret("12345")))
		await until { !coordinator.isRefreshing }
		let next = refresh([.ask(Self.pin)], attended: false)
		await until { !coordinator.isRefreshing }
		#expect(next.answers.all.isEmpty)
		#expect(coordinator.states[Self.bank.id] == .failed(.needsUser(.pin)))
	}

	@Test("A block that the bank reports for an account deletes the saved PIN, and the next automatic refresh sends nothing")
	func blockedForAccount() async throws {
		try store.savePIN(Secret("12345"), for: Self.bank.id)
		try broker.open(store)
		let blocked = BankMessage(code: "9930", text: "Zugang gesperrt")
		_ = refresh([.ask(Self.pin), .failAccount(Self.giro.accountID, .accessBlocked(blocked))], attended: false)
		await until { !coordinator.isRefreshing }
		#expect(store.pins.isEmpty)
		#expect(broker.savedPINs.isEmpty)
		let next = refresh([.ask(Self.pin)], attended: false)
		await until { !coordinator.isRefreshing }
		#expect(next.answers.all.isEmpty)
	}

	@Test("A PIN that the bank rejects for an account is not saved, although the refresh finished")
	func rejectedForAccountNotSaved() async {
		_ = refresh([.ask(Self.pin), .failAccount(Self.giro.accountID, .pinRejected(BankMessage(code: "9942", text: "PIN falsch")))])
		await until { broker.current != nil }
		answer(.pin(Secret("12345"), save: true))
		await until { !coordinator.isRefreshing }
		#expect(store.pins.isEmpty)
		let next = refresh([.ask(Self.pin)], attended: false)
		await until { !coordinator.isRefreshing }
		#expect(next.answers.all.isEmpty)
	}

	@Test("A rejected saved PIN whose deletion fails once is deleted by the second try, without an alert")
	func deletionRetried() async throws {
		let failing = FailingRemovalStore(failures: 1)
		try failing.savePIN(Secret("12345"), for: Self.bank.id)
		var failures: [SavedPINFailure.Kind] = []
		broker.onStoreFailure = { failures.append($0.kind) }
		try broker.open(failing)
		_ = refresh([.ask(Self.pin), .ask(Self.rejected)], attended: false)
		await until { !coordinator.isRefreshing }
		#expect(failing.pins.isEmpty)
		#expect(failures.isEmpty)
	}

	@Test("A rejected saved PIN that cannot be deleted is reported, and is not used again, also after a restart, until it is deleted at an unlock")
	func deletionFails() async throws {
		let defaults = try #require(UserDefaults(suiteName: "MonetenTests-\(UUID().uuidString)"))
		let coordinator = SyncCoordinator(broker: SessionBroker(defaults: defaults))
		let failing = FailingRemovalStore(failures: .max)
		try failing.savePIN(Secret("12345"), for: Self.bank.id)
		var failures: [SavedPINFailure.Kind] = []
		coordinator.broker.onStoreFailure = { failures.append($0.kind) }
		try coordinator.broker.open(failing)
		_ = refresh([.ask(Self.pin), .ask(Self.rejected)], attended: false, in: coordinator)
		await until { !coordinator.isRefreshing }
		#expect(failures == [.rejectedNotRemoved])
		#expect(failing.pins == [Self.bank.id: Secret("12345")])
		coordinator.broker.forgetPINs()

		let restarted = SyncCoordinator(broker: SessionBroker(defaults: defaults))
		try restarted.broker.open(failing)
		let automatic = refresh([.ask(Self.pin)], attended: false, in: restarted)
		await until { !restarted.isRefreshing }
		#expect(automatic.answers.all.isEmpty)
		restarted.broker.forgetPINs()

		failing.failures = 0
		try SessionBroker(defaults: defaults).open(failing)
		#expect(failing.pins.isEmpty)
	}

	@Test("A saved PIN that breaks the rules of the bank is not sent: the automatic refresh stops, and the manual one asks")
	func savedBreaksRules() async throws {
		try store.savePIN(Secret("123456"), for: Self.bank.id)
		try broker.open(store)
		let strict = UserRequest.pin(PINRequest(rules: PINRules(maxLength: 5)))
		let automatic = refresh([.ask(strict)], attended: false)
		await until { !coordinator.isRefreshing }
		#expect(automatic.answers.all.isEmpty)
		#expect(coordinator.states[Self.bank.id] == .failed(.needsUser(.pin)))

		let manual = refresh([.ask(strict)])
		await until { broker.current?.request == strict }
		broker.cancel(try #require(broker.current).id)
		await until { !coordinator.isRefreshing }
		#expect(manual.answers.all.isEmpty)
	}

	@Test("A rejection beside a balance that could not be stored still deletes the saved PIN")
	func rejectionBesideStorageFailure() async throws {
		try store.savePIN(Secret("12345"), for: Self.bank.id)
		try broker.open(store)
		coordinator.deliver = { _, _ in throw CocoaError(.fileWriteNoPermission) }
		let result = RefreshResult(balance: Money(minorUnits: 120_000, currency: "EUR"), transactions: nil,
			transactionFailure: .pinRejected(BankMessage(code: "9942", text: "PIN falsch")))
		_ = refresh([.ask(Self.pin), .fetched(Self.giro.accountID, result)], attended: false)
		await until { !coordinator.isRefreshing }
		#expect(store.pins.isEmpty)
		let next = refresh([.ask(Self.pin)], attended: false)
		await until { !coordinator.isRefreshing }
		#expect(next.answers.all.isEmpty)
		#expect(coordinator.states[Self.bank.id] == .failed(.needsUser(.pin)))
	}

	@Test("A rejection that arrived before a cancel deletes the saved PIN, and a cancel alone keeps it", arguments: [true, false])
	func rejectionThenCancel(rejected: Bool) async throws {
		try store.savePIN(Secret("12345"), for: Self.bank.id)
		try broker.open(store)
		let connector = LateEnd(rejection: rejected ? .accessBlocked(BankMessage(code: "9930", text: "Zugang gesperrt")) : nil)
		coordinator.refresh(RefreshRequest(access: Self.bank, accounts: [Self.giro]), with: connector, attended: false)
		await until { connector.reachedEnd }
		coordinator.cancelAll()
		await until { !coordinator.isRefreshing }
		#expect(coordinator.states[Self.bank.id] == .cancelled)
		#expect(store.pins == (rejected ? [:] : [Self.bank.id: Secret("12345")]))
	}

	@Test("A rejection that a connector throws after a cancel deletes the saved PIN")
	func rejectionThrownAfterCancel() async throws {
		try store.savePIN(Secret("12345"), for: Self.bank.id)
		try broker.open(store)
		let connector = LateEnd(rejection: nil, thrown: .pinRejected(BankMessage(code: "9942", text: "PIN falsch")))
		coordinator.refresh(RefreshRequest(access: Self.bank, accounts: [Self.giro]), with: connector, attended: false)
		await until { connector.reachedEnd }
		coordinator.cancelAll()
		await until { !coordinator.isRefreshing }
		#expect(store.pins.isEmpty)
	}

	@Test("A rejection that arrives after the lock deletes the saved PIN at the next unlock, and the PIN is not used")
	func rejectionAfterLock() async throws {
		let defaults = try #require(UserDefaults(suiteName: "MonetenTests-\(UUID().uuidString)"))
		let coordinator = SyncCoordinator(broker: SessionBroker(defaults: defaults, scope: "/A/Moneten.sqlite"))
		try store.savePIN(Secret("12345"), for: Self.bank.id)
		try coordinator.broker.open(store)
		let connector = LateEnd(rejection: nil, lateRejection: .accessBlocked(BankMessage(code: "9930", text: "Zugang gesperrt")))
		coordinator.refresh(RefreshRequest(access: Self.bank, accounts: [Self.giro]), with: connector, attended: false)
		await until { connector.reachedEnd }
		// The lock: every refresh is canceled, and the PINs and the store are forgotten.
		coordinator.cancelAll()
		coordinator.broker.forgetPINs()
		await until { !coordinator.isRefreshing }
		try await Task.sleep(for: .milliseconds(100))

		// The unlock opens the same database.
		try coordinator.broker.open(store)
		#expect(store.pins.isEmpty)
		let automatic = refresh([.ask(Self.pin)], attended: false, in: coordinator)
		await until { !coordinator.isRefreshing }
		#expect(automatic.answers.all.isEmpty)
		#expect(coordinator.states[Self.bank.id] == .failed(.needsUser(.pin)))
	}

	@Test("The mark of a rejected PIN that could not be deleted belongs to its database, and only a real deletion clears it")
	func markPerDatabase() async throws {
		let defaults = try #require(UserDefaults(suiteName: "MonetenTests-\(UUID().uuidString)"))
		let coordinator = SyncCoordinator(broker: SessionBroker(defaults: defaults, scope: "/A/Moneten.sqlite"))
		let failing = FailingRemovalStore(failures: .max)
		try failing.savePIN(Secret("12345"), for: Self.bank.id)
		try coordinator.broker.open(failing)
		_ = refresh([.ask(Self.pin), .ask(Self.rejected)], attended: false, in: coordinator)
		await until { !coordinator.isRefreshing }
		coordinator.broker.forgetPINs()

		// Another data folder, and the same folder with a database that has no such row, delete nothing.
		try SessionBroker(defaults: defaults, scope: "/B/Moneten.sqlite").open(MemoryPINStore())
		try SessionBroker(defaults: defaults, scope: "/A/Moneten.sqlite").open(MemoryPINStore())

		let again = SyncCoordinator(broker: SessionBroker(defaults: defaults, scope: "/A/Moneten.sqlite"))
		try again.broker.open(failing)
		let automatic = refresh([.ask(Self.pin)], attended: false, in: again)
		await until { !again.isRefreshing }
		#expect(automatic.answers.all.isEmpty)
	}

	@Test("A rejected PIN never reaches the error of the account")
	func rejectionRecord() async {
		var refreshes: [UUID: AccountRefresh] = [:]
		coordinator.ended = { _, _, accounts, _ in refreshes = accounts }
		_ = refresh([.ask(Self.pin), .fail(.pinRejected(BankMessage(code: "9942", text: "Die PIN ist falsch.")))])
		await until { broker.current != nil }
		answer(.pin(Secret("48151"), save: true))
		await until { !coordinator.isRefreshing }
		guard case let .failed(error) = refreshes[Self.giro.accountID] else { Issue.record("no error"); return }
		#expect(error.message.contains("Die PIN ist falsch."))
		#expect(!error.message.contains("48151"))
	}

	/// Waits until the condition holds, for at most two seconds.
	func until(_ condition: () -> Bool, sourceLocation: SourceLocation = #_sourceLocation) async {
		for _ in 0..<200 where !condition() {
			try? await Task.sleep(for: .milliseconds(10))
		}
		#expect(condition(), sourceLocation: sourceLocation)
	}
}

/// Saved PINs in memory, in place of the encrypted database.
final class MemoryPINStore: SavedPINStore {
	private let saved = Mutex<[UUID: Secret]>([:])

	var pins: [UUID: Secret] { saved.withLock { $0 } }

	func savedPINs() throws -> [UUID: Secret] { pins }
	func savePIN(_ pin: Secret, for access: UUID) throws { saved.withLock { $0[access] = pin } }
	func removeSavedPIN(of access: UUID) throws -> Bool { saved.withLock { $0.removeValue(forKey: access) } != nil }
}

/// Saved PINs in memory whose deletion fails the next `failures` times, like a database that cannot be written.
final class FailingRemovalStore: SavedPINStore {
	private let memory = MemoryPINStore()
	private let remaining: Mutex<Int>

	init(failures: Int) {
		remaining = Mutex(failures)
	}

	var failures: Int {
		get { remaining.withLock { $0 } }
		set { remaining.withLock { $0 = newValue } }
	}
	var pins: [UUID: Secret] { memory.pins }

	func savedPINs() throws -> [UUID: Secret] { try memory.savedPINs() }
	func savePIN(_ pin: Secret, for access: UUID) throws { try memory.savePIN(pin, for: access) }
	func removeSavedPIN(of access: UUID) throws -> Bool {
		let fails = remaining.withLock { left in
			guard left > 0 else { return false }
			left -= 1
			return true
		}
		if fails { throw CocoaError(.fileWriteNoPermission) }
		return try memory.removeSavedPIN(of: access)
	}
}

/// A connector that logs in with the PIN, may report a rejection at once, and then needs a while to
/// end that no cancel shortens, like a helper that shuts down. It may report `lateRejection` then, and
/// returns, or throws `thrown`.
final class LateEnd: BankConnector {
	let rejection: SyncFailure?
	let lateRejection: SyncFailure?
	let thrown: SyncFailure?
	private let reached = Mutex(false)

	init(rejection: SyncFailure?, lateRejection: SyncFailure? = nil, thrown: SyncFailure? = nil) {
		self.rejection = rejection
		self.lateRejection = lateRejection
		self.thrown = thrown
	}

	var reachedEnd: Bool { reached.withLock { $0 } }

	func refresh(_ request: RefreshRequest, _ session: SyncSession) async throws -> ConnectorReport {
		_ = try await session.ask(.pin(PINRequest()))
		if let rejection { await session.rejected(rejection) }
		reached.withLock { $0 = true }
		await withCheckedContinuation { done in DispatchQueue.global().asyncAfter(deadline: .now() + 0.3) { done.resume() } }
		if let lateRejection { await session.rejected(lateRejection) }
		if let thrown { throw thrown }
		return ConnectorReport(outcomes: [:])
	}
}
