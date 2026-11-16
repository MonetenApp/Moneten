import Domain
import Foundation
import SyncTesting
import Testing
@testable import Sync

/// The first login of a new access in the "Add Account" assistant (add-account-setup "Report a failed
/// login without leaving the assistant", "Progress and cancel during setup").
@MainActor
@Suite("Setup session")
struct SetupSessionTests {
	let broker = SessionBroker()
	let coordinator: SyncCoordinator
	static let access = Access(source: .fints(bankCode: "12030000", url: URL(string: "https://fints.example.com/")!), bankName: "Musterbank", loginName: "erika77")
	init() {
		coordinator = SyncCoordinator(broker: broker)
	}

	var session: SetupSession { SetupSession(broker: broker, access: Self.access, pin: Secret("12345")) }

	@Test("The PIN of the login step answers the bank without a PIN sheet")
	func pinFromLoginStep() async throws {
		#expect(try await session.ask(.pin(PINRequest())) == .pin(Secret("12345")))
		#expect(broker.current == nil)
	}

	@Test("A rejected PIN ends the login with the message of the bank and opens no sheet")
	func rejectedPIN() async {
		let rejected = BankMessage(code: "9942", text: "PIN falsch")
		await #expect(throws: SyncFailure.pinRejected(rejected)) { try await session.ask(.pin(PINRequest(rejected: rejected))) }
		#expect(broker.current == nil)
	}

	@Test("A TAN request opens the dialog of the broker for the new access, and its answer reaches the bank")
	func tanThroughBroker() async throws {
		let tan = UserRequest.secondFactor(SecondFactorRequest(purpose: .login, system: .fintsServer, challenge: .enterTAN(prompt: "TAN eingeben", image: nil)))
		let session = session
		let asked = Task { try await session.ask(tan) }
		for _ in 0..<200 where broker.current == nil { try await Task.sleep(for: .milliseconds(10)) }
		let prompt = try #require(broker.current)
		#expect(prompt.access == Self.access)
		#expect(prompt.request == tan)
		broker.answer(.tan(Secret("123456")), to: prompt.id)
		#expect(try await asked.value == .tan(Secret("123456")))
	}

	@Test("Canceling the TAN dialog ends the login")
	func cancelTAN() async throws {
		let tan = UserRequest.secondFactor(SecondFactorRequest(purpose: .login, system: .fintsServer, challenge: .enterTAN(prompt: "TAN eingeben", image: nil)))
		let session = session
		let asked = Task { try await session.ask(tan) }
		for _ in 0..<200 where broker.current == nil { try await Task.sleep(for: .milliseconds(10)) }
		broker.cancel(try #require(broker.current).id)
		await #expect(throws: CancellationError.self) { try await asked.value }
	}

	@Test("A PIN that breaks a rule of the bank ends the login with the rule, and the PIN never reaches the bank")
	func pinBreaksRule() async throws {
		let session = SetupSession(broker: broker, access: Self.access, pin: Secret("1234"))
		let request = UserRequest.pin(PINRequest(rules: PINRules(minLength: 5, maxLength: 6)))
		do {
			let answer = try await session.ask(request)
			Issue.record("the PIN was sent: \(answer)")
		} catch {
			#expect(error.localizedDescription == "The PIN is too short. The minimum is 5 characters.")
		}
		#expect(broker.current == nil)
		#expect(try await session.ask(.pin(PINRequest(rules: PINRules(minLength: 4)))) == .pin(Secret("1234")))
	}

	@Test("A six character PIN for a server that refuses it since it raised the minimum ends the login with that message")
	func refusedPINLength() async throws {
		let session = SetupSession(broker: broker, access: Self.access, pin: Secret("123456"))
		do {
			let answer = try await session.ask(.pin(PINRequest(rules: PINRules(minLength: 8, refusedLength: 6))))
			Issue.record("the PIN was sent: \(answer)")
		} catch {
			#expect(error.localizedDescription
				== "The FinTS server of the bank no longer accepts a PIN of 6 characters. Set a longer PIN in the online banking of the bank first.")
		}
		#expect(broker.current == nil)
	}

	static let chooseMethod = UserRequest.secondFactor(SecondFactorRequest(purpose: .login, system: .fintsServer,
		challenge: .chooseTANMethod([TANMethod(id: "922", name: "pushTAN 2.0", delivery: .pushNotification)], current: nil)))

	@Test("A login that fails after the choice of a TAN method closes the progress of the dialog")
	func failedLoginEndsProgress() async throws {
		let chooseMethod = Self.chooseMethod
		let session = session
		let login = Task {
			try await session.logIn(holding: coordinator) { session in
				_ = try await session.ask(chooseMethod)
				try await Task.sleep(for: .milliseconds(200))
				throw SyncFailure.network("The connection was lost.")
			}
		}
		for _ in 0..<200 where broker.current == nil { try await Task.sleep(for: .milliseconds(10)) }
		broker.answer(.tanMethod("922"), to: try #require(broker.current).id)
		#expect(broker.requesting?.access == Self.access)
		await #expect(throws: SyncFailure.network("The connection was lost.")) { try await login.value }
		#expect(broker.requesting == nil)
	}

	@Test("Canceling the login, as the lock does, closes the progress of the dialog before the connector ends")
	func canceledLoginEndsProgress() async throws {
		let chooseMethod = Self.chooseMethod
		let session = session
		let login = Task {
			try await session.logIn(holding: coordinator) { session in
				_ = try await session.ask(chooseMethod)
				// A connector that needs a second to end, as the helper does.
				await withCheckedContinuation { done in DispatchQueue.global().asyncAfter(deadline: .now() + 1) { done.resume() } }
			}
		}
		for _ in 0..<200 where broker.current == nil { try await Task.sleep(for: .milliseconds(10)) }
		broker.answer(.tanMethod("922"), to: try #require(broker.current).id)
		#expect(broker.requesting != nil)
		login.cancel()
		for _ in 0..<20 where broker.requesting != nil { try await Task.sleep(for: .milliseconds(10)) }
		#expect(broker.requesting == nil)
		_ = try? await login.value
	}

	@Test("Cancel in the progress of the setup login cancels the login")
	func cancelProgressCancelsLogin() async throws {
		let chooseMethod = Self.chooseMethod
		let session = session
		let login = Task {
			try await session.logIn(holding: coordinator) { session -> Int in
				_ = try await session.ask(chooseMethod)
				try await Task.sleep(for: .seconds(5))
				return 1
			}
		}
		for _ in 0..<200 where broker.current == nil { try await Task.sleep(for: .milliseconds(10)) }
		broker.answer(.tanMethod("922"), to: try #require(broker.current).id)
		#expect(broker.requesting != nil)
		let canceled = ContinuousClock.now
		broker.cancelRequest()
		#expect(broker.requesting == nil)
		await #expect(throws: CancellationError.self) { try await login.value }
		#expect(ContinuousClock.now - canceled < .seconds(2))
	}

	static let known = Access(source: .fints(bankCode: "12030000", url: URL(string: "https://fints.example.com/")!), bankName: "Musterbank", loginName: "erika77")

	/// A broker with the saved PIN "12345" of the access that the app has for the login of the setup.
	func knownLogin() throws -> MemoryPINStore {
		let store = MemoryPINStore()
		try store.savePIN(Secret("12345"), for: Self.known.id)
		try broker.open(store)
		return store
	}

	@Test("A PIN that the bank rejects in the setup of a login that the app has deletes the saved PIN of that login")
	func rejectedForKnownLogin() async throws {
		let store = try knownLogin()
		let session = SetupSession(broker: broker, access: Self.access, pin: Secret("54321"), replacing: Self.known.id)
		let rejected = BankMessage(code: "9942", text: "PIN falsch")
		await #expect(throws: SyncFailure.pinRejected(rejected)) {
			try await session.logIn(holding: coordinator) { try await $0.ask(.pin(PINRequest(rejected: rejected))) }
		}
		#expect(store.pins.isEmpty)
		await #expect(throws: SyncFailure.needsUser(.pin)) {
			try await broker.ask(.pin(PINRequest()), for: Self.known, accountNames: [], attended: false)
		}
	}

	@Test("A block in the setup of a login that the app has deletes the saved PIN of that login")
	func blockedForKnownLogin() async throws {
		let store = try knownLogin()
		let session = SetupSession(broker: broker, access: Self.access, pin: Secret("12345"), replacing: Self.known.id)
		let blocked = BankMessage(code: "9930", text: "Zugang gesperrt")
		await #expect(throws: SyncFailure.accessBlocked(blocked)) {
			try await session.logIn(holding: coordinator) { _ -> Int in throw SyncFailure.accessBlocked(blocked) }
		}
		#expect(store.pins.isEmpty)
		await #expect(throws: SyncFailure.needsUser(.pin)) {
			try await broker.ask(.pin(PINRequest()), for: Self.known, accountNames: [], attended: false)
		}
	}

	@Test("A block after a notice of the bank in the setup of a login that the app has deletes the saved PIN of that login")
	func blockWithNoticesForKnownLogin() async throws {
		let store = try knownLogin()
		let session = SetupSession(broker: broker, access: Self.access, pin: Secret("12345"), replacing: Self.known.id)
		let blocked = SyncFailure.accessBlocked(BankMessage(code: "9930", text: "Zugang gesperrt"))
		let error = await #expect(throws: FailureWithNotices.self) {
			try await session.logIn(holding: coordinator) { _ -> Int in throw FailureWithNotices(blocked, notices: [BankMessage(text: "Wartungsarbeiten bis 5 Uhr")]) }
		}
		#expect(error?.failure as? SyncFailure == blocked)
		#expect(store.pins.isEmpty)
	}

	@Test("A block that the connector reports in the setup of a login that the app has deletes its saved PIN at once, also when the login is canceled then")
	func blockReportedForKnownLogin() async throws {
		let store = try knownLogin()
		let session = SetupSession(broker: broker, access: Self.access, pin: Secret("12345"), replacing: Self.known.id)
		let login = Task {
			try await session.logIn(holding: coordinator) { session -> Int in
				await session.rejected(.accessBlocked(BankMessage(code: "9930", text: "Zugang gesperrt")))
				try await Task.sleep(for: .seconds(5))
				return 1
			}
		}
		for _ in 0..<200 where !store.pins.isEmpty { try await Task.sleep(for: .milliseconds(10)) }
		login.cancel()
		_ = try? await login.value
		#expect(store.pins.isEmpty)
	}

	@Test("The PIN of the setup answers the first refresh of the new access from memory")
	func rememberedPIN() async throws {
		try coordinator.broker.remember(Secret("12345"), for: Self.access.id, save: false)
		let connector = ScriptedConnector([.ask(.pin(PINRequest()))])
		coordinator.refresh(RefreshRequest(access: Self.access, accounts: []), with: connector, attended: true)
		for _ in 0..<200 where coordinator.isRefreshing { try? await Task.sleep(for: .milliseconds(10)) }
		#expect(connector.answers.all == [.pin(Secret("12345"))])
		#expect(broker.current == nil)
	}

	@Test("Look for New Accounts logs in with the saved PIN of the access and opens no sheet")
	func savedPINOfAccess() async throws {
		let store = MemoryPINStore()
		try store.savePIN(Secret("54321"), for: Self.access.id)
		try broker.open(store)
		let session = SetupSession(broker: broker, access: Self.access, pin: nil)
		let answer = try await session.logIn(holding: coordinator) { session in try await session.ask(.pin(PINRequest())) }
		#expect(answer == .pin(Secret("54321")))
		#expect(broker.current == nil)
	}

	@Test("Look for New Accounts asks for a missing PIN in the sheet, and saves it on request only after the login succeeded")
	func typedPINOfAccess() async throws {
		let store = MemoryPINStore()
		try broker.open(store)
		let session = SetupSession(broker: broker, access: Self.access, pin: nil)
		func login(failing: Bool) async throws {
			let login = Task {
				try await session.logIn(holding: coordinator) { session in
					_ = try await session.ask(.pin(PINRequest()))
					if failing { throw SyncFailure.offline }
				}
			}
			for _ in 0..<200 where broker.current == nil { try await Task.sleep(for: .milliseconds(10)) }
			broker.answer(.pin(Secret("67890"), save: true), to: try #require(broker.current).id)
			try await login.value
		}
		await #expect(throws: SyncFailure.offline) { try await login(failing: true) }
		#expect(store.pins.isEmpty)
		try await login(failing: false)
		#expect(store.pins == [Self.access.id: Secret("67890")])
		#expect(broker.savedPINs == [Self.access.id])
	}

	/// Starts a refresh of the access, and then Look for New Accounts with the PIN of the access, which waits
	/// for the refresh and is canceled before it gets the access.
	func cancelWaitingLogin(behind steps: [ScriptedConnector.Step], whileRefreshing: () async throws -> Void = {}) async throws {
		coordinator.refresh(RefreshRequest(access: Self.access, accounts: []), with: ScriptedConnector(steps), attended: true)
		try await whileRefreshing()
		let session = SetupSession(broker: broker, access: Self.access, pin: nil)
		let login = Task { try await session.logIn(holding: coordinator) { _ in 1 } }
		try await Task.sleep(for: .milliseconds(50))
		login.cancel()
		try await Task.sleep(for: .milliseconds(50))
	}

	@Test("Canceling Look for New Accounts while it waits for a refresh of the access keeps the TAN progress of the refresh")
	func canceledWaitKeepsProgress() async throws {
		try await cancelWaitingLogin(behind: [.ask(Self.chooseMethod), .wait(.seconds(1))]) {
			for _ in 0..<200 where broker.current == nil { try await Task.sleep(for: .milliseconds(10)) }
			broker.answer(.tanMethod("922"), to: try #require(broker.current).id)
			#expect(broker.requesting?.access == Self.access)
		}
		#expect(broker.requesting?.access == Self.access)
		coordinator.cancelAll()
	}

	@Test("Canceling Look for New Accounts while it waits for a refresh of the access keeps the PIN that the bank accepted")
	func canceledWaitKeepsPIN() async throws {
		try broker.remember(Secret("12345"), for: Self.access.id, save: false)
		try await cancelWaitingLogin(behind: [.ask(.pin(PINRequest())), .wait(.milliseconds(200))])
		for _ in 0..<200 where coordinator.isRefreshing { try await Task.sleep(for: .milliseconds(10)) }
		try await Task.sleep(for: .milliseconds(50))
		#expect(try await broker.ask(.pin(PINRequest()), for: Self.access, accountNames: [], attended: false) == .pin(Secret("12345")))
	}
}
