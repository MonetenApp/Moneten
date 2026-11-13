import Domain
@testable import ExtensionConnector
import ExtensionHost
import Foundation
import Synchronization
import Testing

/// The setup of an extension access as a job: what a failed setup keeps for the next one, and what a
/// cancel withholds.
@MainActor
@Suite struct SetupJobTests {
	static let access = Access(source: .extension(id: "Demo"), bankName: "Demo", loginName: "")

	/// A service that registers a device at the login. ListAccounts fails when the run started without
	/// the registration, if `failing`, and EndSession takes `sleep` seconds after it says that it runs.
	static func source(failing: Bool, sleep: Int) -> String {
		ExtensionConnectorTests.calls.replacingOccurrences(of: "function EndSession() print(\"EndSession\") end",
			with: "function EndSession() print(\"ending\") MM.sleep(\(sleep)) print(\"EndSession\") end") + """
			function InitializeSession2(protocol, bankCode, step, credentials)
				print("token " .. tostring(LocalStorage.token))
				seen = LocalStorage.token
				LocalStorage.token = "device of " .. credentials[1]
			end
			function ListAccounts()
				if seen == nil and \(failing) then error("Try again later", 0) end
				return {{accountNumber = "1", name = "Konto"}}
			end
			function RefreshAccount() return {balance = 0, transactions = {}} end
			"""
	}

	final class Added: Sendable {
		let count = Mutex(0)
	}

	func job(_ states: KeptSetupStates, _ session: TestSession, failing: Bool, sleep: Int = 0, added: Added = Added()) -> ExtensionSetupJob {
		ExtensionSetupJob(connector: session.connector(demo(Self.source(failing: failing, sleep: sleep))), states: states) { _ in
			added.count.withLock { $0 += 1 }
		}
	}

	static func until(_ condition: () -> Bool) async {
		for _ in 0..<1000 where !condition() {
			try? await Task.sleep(for: .milliseconds(10))
		}
	}

	func setUp(_ states: KeptSetupStates, login: String, failing: Bool) async -> TestSession {
		let session = TestSession([.login([Secret(login), Secret("geheim")])])
		_ = try? await job(states, session, failing: failing).refresh(RefreshRequest(access: Self.access, accounts: []), session)
		return session
	}

	@Test func cancelDuringEndSessionAddsNoAccountAndKeepsTheState() async throws {
		let states = KeptSetupStates()
		let session = TestSession([.login([Secret("erika"), Secret("geheim")])])
		let added = Added()
		let job = job(states, session, failing: false, sleep: 3, added: added)
		let task = Task { try await job.refresh(RefreshRequest(access: Self.access, accounts: []), session) }
		await Self.until { session.printed.contains("ending") }
		task.cancel()
		await #expect(throws: CancellationError.self) { try await task.value }
		#expect(added.count.withLock { $0 } == 0)
		#expect(await setUp(states, login: "erika", failing: false).printed.contains("token device of erika"))
	}

	@Test func keptStateBelongsToItsLogin() async {
		let states = KeptSetupStates()
		_ = await setUp(states, login: "erika", failing: true)
		#expect(await setUp(states, login: "max", failing: true).printed.contains("token nil"))
		#expect(await setUp(states, login: "erika", failing: true).printed.contains("token device of erika"))
	}

	@Test func loginWithoutAUserNameKeepsNothing() async {
		let states = KeptSetupStates()
		_ = await setUp(states, login: "", failing: true)
		#expect(await setUp(states, login: "", failing: true).printed.contains("token nil"))
	}

	struct DiskFull: Error {}

	/// When the app cannot store the accounts of a setup, the state of the setup stays for the next one.
	@Test func setupWhoseAccountsCannotBeStoredKeepsItsState() async {
		let states = KeptSetupStates()
		let session = TestSession([.login([Secret("erika"), Secret("geheim")])])
		let job = ExtensionSetupJob(connector: session.connector(demo(Self.source(failing: false, sleep: 0))), states: states) { _ in throw DiskFull() }
		await #expect(throws: DiskFull.self) { try await job.refresh(RefreshRequest(access: Self.access, accounts: []), session) }
		#expect(await setUp(states, login: "erika", failing: false).printed.contains("token device of erika"))
	}

	/// A lock clears the states while a failed setup still ends its session. That setup keeps nothing,
	/// also when the app was unlocked in between.
	@Test func setupThatEndsAfterTheLockKeepsNothing() async {
		let states = KeptSetupStates()
		let session = TestSession([.login([Secret("erika"), Secret("geheim")])])
		let job = job(states, session, failing: true, sleep: 2)
		let task = Task { try await job.refresh(RefreshRequest(access: Self.access, accounts: []), session) }
		await Self.until { session.printed.contains("ending") }
		states.clear()
		_ = await task.result
		#expect(await setUp(states, login: "erika", failing: false).printed.contains("token nil"))
	}
}
