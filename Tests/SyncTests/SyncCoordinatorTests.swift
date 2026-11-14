import Domain
import Foundation
import SyncTesting
import Testing
@testable import Sync

/// The refresh of accesses with a scripted connector: the dialog queue, cancellation, and failures.
@MainActor
@Suite("Sync coordinator")
struct SyncCoordinatorTests {
	let coordinator = SyncCoordinator()
	var broker: SessionBroker { coordinator.broker }

	static func access(_ bank: String) -> Access {
		Access(source: .fints(bankCode: "12030000", url: URL(string: "https://fints.example.com/")!), bankName: bank, loginName: "erika77")
	}

	static let giro = AccountRequest(accountID: UUID(), name: "Giro", remoteID: "1234")
	static let savings = AccountRequest(accountID: UUID(), name: "Savings", remoteID: "5678")
	static let card = AccountRequest(accountID: UUID(), name: "Card", remoteID: "9012")

	static let pin = UserRequest.pin(PINRequest())
	static let tan = UserRequest.secondFactor(SecondFactorRequest(purpose: .download, system: .fintsServer, challenge: .enterTAN(prompt: "TAN eingeben", image: nil)))
	static func approval(validity: Duration = .seconds(300)) -> UserRequest {
		.secondFactor(SecondFactorRequest(purpose: .login, system: .fintsServer, challenge: .approveInApp(prompt: "Bitte in der App freigeben", app: "pushTAN", image: nil, step: nil),
			validity: validity))
	}

	func refresh(_ access: Access, _ steps: [ScriptedConnector.Step], accounts: [AccountRequest] = [giro], attended: Bool = true) -> ScriptedConnector {
		let connector = ScriptedConnector(steps)
		coordinator.refresh(RefreshRequest(access: access, accounts: accounts), with: connector, attended: attended)
		return connector
	}

	func state(_ access: Access) -> SyncState? { coordinator.states[access.id] }

	/// Answers the dialog on screen, as a click on its button does.
	func answer(_ answer: UserAnswer) {
		if let id = broker.current?.id { broker.answer(answer, to: id) }
	}

	func cancelOnScreen() {
		if let id = broker.current?.id { broker.cancel(id) }
	}

	/// Waits until the condition holds, for at most two seconds.
	func until(_ condition: () -> Bool, sourceLocation: SourceLocation = #_sourceLocation) async {
		for _ in 0..<200 where !condition() {
			try? await Task.sleep(for: .milliseconds(10))
		}
		#expect(condition(), sourceLocation: sourceLocation)
	}

	func finished(_ access: Access) -> SyncSummary? {
		if case let .finished(summary) = state(access) { summary } else { nil }
	}

	@Test("A manual refresh asks for the PIN, fetches, and finishes")
	func pinAndFetch() async {
		let bank = Self.access("Musterbank")
		let connector = refresh(bank, [.ask(Self.pin), .progress(.fetching(done: 0, of: 1)), .fetched(Self.giro.accountID)])
		await until { broker.current != nil }
		#expect(broker.current?.access == bank)
		#expect(broker.current?.accountNames == ["Giro"])
		#expect(state(bank) == .needsUser(.pin, waiting: false, during: .connecting))
		answer(.pin(Secret("12345")))
		await until { finished(bank) != nil }
		#expect(finished(bank)?.fetched == [Self.giro.accountID])
		#expect(connector.answers.all == [.pin(Secret("12345"))])
		#expect(!coordinator.isRefreshing)
	}

	@Test("A PIN in memory is used again, until the app locks")
	func pinInMemory() async {
		let bank = Self.access("Musterbank")
		_ = refresh(bank, [.ask(Self.pin)])
		await until { broker.current != nil }
		answer(.pin(Secret("12345")))
		await until { finished(bank) != nil }

		let second = refresh(bank, [.ask(Self.pin)])
		await until { finished(bank) != nil && !coordinator.isRefreshing }
		#expect(second.answers.all == [.pin(Secret("12345"))])

		broker.forgetPINs()
		_ = refresh(bank, [.ask(Self.pin)])
		await until { broker.current != nil }
		cancelOnScreen()
		await until { state(bank) == .cancelled }
	}

	@Test("A rejected PIN is forgotten")
	func pinRejected() async {
		let bank = Self.access("Musterbank")
		let rejected = SyncFailure.pinRejected(BankMessage(code: "9942", text: "PIN falsch"))
		_ = refresh(bank, [.ask(Self.pin), .fail(rejected)])
		await until { broker.current != nil }
		answer(.pin(Secret("11111")))
		await until { state(bank) == .failed(rejected) }

		_ = refresh(bank, [.ask(Self.pin)])
		await until { broker.current != nil }
		#expect(broker.current?.access == bank)
		cancelOnScreen()
		await until { !coordinator.isRefreshing }
	}

	@Test("After a typing error the PIN sheet opens again, and the new PIN stays in memory")
	func pinTypo() async {
		let bank = Self.access("Musterbank")
		let rejected = UserRequest.pin(PINRequest(rejected: BankMessage(code: "9942", text: "PIN falsch")))
		let connector = refresh(bank, [.ask(Self.pin), .ask(rejected), .fetched(Self.giro.accountID)])
		await until { broker.current?.request == Self.pin }
		answer(.pin(Secret("11111")))
		await until { broker.current?.request == rejected }
		#expect(state(bank) == .needsUser(.pin, waiting: false, during: .connecting))
		answer(.pin(Secret("22222")))
		await until { finished(bank) != nil }
		#expect(connector.answers.all == [.pin(Secret("11111")), .pin(Secret("22222"))])

		let automatic = refresh(bank, [.ask(Self.pin)], attended: false)
		await until { !coordinator.isRefreshing }
		#expect(automatic.answers.all == [.pin(Secret("22222"))])
	}

	@Test("A PIN in memory that the bank rejects is never sent again")
	func pinInMemoryRejected() async {
		let bank = Self.access("Musterbank")
		_ = refresh(bank, [.ask(Self.pin)])
		await until { broker.current != nil }
		answer(.pin(Secret("12345")))
		await until { finished(bank) != nil }

		let rejected = UserRequest.pin(PINRequest(rejected: BankMessage(code: "9942", text: "PIN falsch")))
		let manual = refresh(bank, [.ask(Self.pin), .ask(rejected)])
		await until { broker.current?.request == rejected }
		answer(.pin(Secret("54321")))
		await until { !coordinator.isRefreshing }
		#expect(manual.answers.all == [.pin(Secret("12345")), .pin(Secret("54321"))])
	}

	@Test("An automatic refresh fails with the message of the bank when the bank rejects the PIN in memory")
	func automaticPINRejected() async {
		let bank = Self.access("Musterbank")
		_ = refresh(bank, [.ask(Self.pin)])
		await until { broker.current != nil }
		answer(.pin(Secret("12345")))
		await until { finished(bank) != nil }

		let message = BankMessage(code: "9942", text: "PIN falsch")
		let automatic = refresh(bank, [.ask(Self.pin), .ask(.pin(PINRequest(rejected: message))), .fetched(Self.giro.accountID)], attended: false)
		await until { !coordinator.isRefreshing }
		#expect(state(bank) == .failed(.pinRejected(message)))
		#expect(automatic.answers.all == [.pin(Secret("12345"))])
		#expect(broker.current == nil)

		_ = refresh(bank, [.ask(Self.pin)])
		await until { broker.current?.access == bank }
		cancelOnScreen()
		await until { !coordinator.isRefreshing }
	}

	@Test("An automatic refresh never asks the user")
	func automatic() async {
		let bank = Self.access("Musterbank")
		_ = refresh(bank, [.progress(.fetching(done: 0, of: 1)), .ask(Self.tan), .fetched(Self.giro.accountID)], attended: false)
		await until { state(bank) == .failed(.needsUser(.secondFactor)) }
		#expect(broker.current == nil)
	}

	@Test("Cancel Refresh in every state", arguments: ["connecting", "fetching", "needsUser", "waiting"])
	func cancelInEveryState(_ name: String) async {
		let other = Self.access("Beispielbank")
		let bank = Self.access("Musterbank")
		let long = ScriptedConnector.Step.wait(.seconds(60))
		let steps: [ScriptedConnector.Step] = switch name {
		case "connecting": [long]
		case "fetching": [.progress(.fetching(done: 0, of: 1)), long]
		default: [.ask(Self.pin)]
		}
		if name == "waiting" {
			_ = refresh(other, [.ask(Self.pin)])
			await until { broker.current?.access == other }
		}
		_ = refresh(bank, steps)
		switch name {
		case "connecting": await until { state(bank) == .connecting }
		case "fetching": await until { state(bank) == .fetching(done: 0, of: 1) }
		case "needsUser": await until { state(bank) == .needsUser(.pin, waiting: false, during: .connecting) }
		default: await until { state(bank) == .needsUser(.pin, waiting: true, during: .connecting) }
		}
		coordinator.cancelAll()
		#expect(state(bank) == .cancelled)
		await until { !coordinator.isRefreshing }
		#expect(state(bank) == .cancelled)
		#expect(broker.current == nil)
	}

	@Test("Canceling the dialog stops only its access")
	func cancelDialog() async {
		let first = Self.access("Musterbank")
		let second = Self.access("Beispielbank")
		_ = refresh(first, [.ask(Self.pin), .fetched(Self.giro.accountID)])
		await until { broker.current?.access == first }
		_ = refresh(second, [.ask(Self.pin), .fetched(Self.savings.accountID)], accounts: [Self.savings])
		await until { state(second) == .needsUser(.pin, waiting: true, during: .connecting) }
		cancelOnScreen()
		await until { broker.current?.access == second }
		#expect(state(first) == .cancelled)
		answer(.pin(Secret("54321")))
		await until { finished(second) != nil }
		#expect(finished(second)?.fetched == [Self.savings.accountID])
		#expect(state(first) == .cancelled)
	}

	@Test("Two accesses that ask at the same time get one dialog after the other")
	func oneDialogAtATime() async {
		let first = Self.access("Musterbank")
		let second = Self.access("Beispielbank")
		_ = refresh(first, [.ask(Self.tan)])
		await until { broker.current?.access == first }
		_ = refresh(second, [.ask(Self.tan)], accounts: [Self.savings])
		await until { state(second) == .needsUser(.secondFactor, waiting: true, during: .connecting) }
		#expect(broker.current?.access == first)
		answer(.tan(Secret("482915")))
		await until { broker.current?.access == second }
		#expect(state(second) == .needsUser(.secondFactor, waiting: false, during: .connecting))
		answer(.tan(Secret("123456")))
		await until { !coordinator.isRefreshing }
	}

	@Test("The approval dialog closes when the connector withdraws its request")
	func approvalCloses() async {
		let bank = Self.access("Musterbank")
		_ = refresh(bank, [.approve(Self.approval(), after: .milliseconds(200)), .progress(.fetching(done: 0, of: 1)), .fetched(Self.giro.accountID)])
		await until { broker.current != nil }
		await until { broker.current == nil }
		await until { finished(bank) != nil }
		#expect(finished(bank)?.fetched == [Self.giro.accountID])
	}

	@Test("Canceling a waiting approval stops the refresh")
	func approvalCanceled() async {
		let bank = Self.access("Musterbank")
		_ = refresh(bank, [.approve(Self.approval(), after: .seconds(60)), .fetched(Self.giro.accountID)])
		await until { broker.current != nil }
		cancelOnScreen()
		await until { !coordinator.isRefreshing }
		#expect(state(bank) == .cancelled)
	}

	@Test("A challenge expires after its validity")
	func expired() async {
		let bank = Self.access("Musterbank")
		_ = refresh(bank, [.ask(Self.approval(validity: .milliseconds(100)))])
		await until { state(bank) == .failed(.challengeExpired) }
		#expect(broker.current == nil)
	}

	@Test("The validity starts when the dialog opens")
	func validityStartsWithTheDialog() async {
		let first = Self.access("Musterbank")
		let second = Self.access("Beispielbank")
		_ = refresh(first, [.ask(Self.pin)])
		await until { broker.current != nil }
		_ = refresh(second, [.ask(Self.approval(validity: .milliseconds(300)))])
		try? await Task.sleep(for: .milliseconds(500))
		#expect(state(second) == .needsUser(.secondFactor, waiting: true, during: .connecting))
		answer(.pin(Secret("12345")))
		await until { broker.current?.access == second }
		await until { state(second) == .failed(.challengeExpired) }
	}

	@Test("A failure stays inside its access")
	func failureStaysInside() async {
		let down = Self.access("Musterbank")
		let up = Self.access("Beispielbank")
		_ = refresh(down, [.fail(.network("timeout"))])
		_ = refresh(up, [.fetched(Self.savings.accountID)], accounts: [Self.savings])
		await until { !coordinator.isRefreshing }
		#expect(state(down) == .failed(.network("timeout")))
		#expect(finished(up)?.fetched == [Self.savings.accountID])
	}

	@Test("An error in the middle of a session")
	func errorInTheMiddle() async {
		let bank = Self.access("Musterbank")
		let refused = SyncFailure.bank(BankMessage(code: "9010", text: "Auftrag abgelehnt"))
		_ = refresh(bank, [.fetched(Self.giro.accountID), .failAccount(Self.savings.accountID, refused)], accounts: [Self.giro, Self.savings, Self.card])
		await until { finished(bank) != nil }
		#expect(finished(bank)?.fetched == [Self.giro.accountID])
		#expect(finished(bank)?.failures == [Self.savings.accountID: refused, Self.card.accountID: .notFetched])
	}

	@Test("Up to three accesses run at the same time")
	func threeAtATime() async {
		let banks = (1...4).map { Self.access("Bank \($0)") }
		for bank in banks { _ = refresh(bank, [.wait(.milliseconds(300))]) }
		#expect(banks.map { state($0) == .connecting } == [true, true, true, false])
		await until { state(banks[3]) == .connecting }
		await until { !coordinator.isRefreshing }
		#expect(banks.allSatisfy { finished($0) != nil })
	}

	@Test("An access that runs is not started twice")
	func notTwice() async {
		let bank = Self.access("Musterbank")
		_ = refresh(bank, [.ask(Self.pin)])
		let second = refresh(bank, [.fail(.offline)])
		await until { broker.current != nil }
		answer(.pin(Secret("12345")))
		await until { !coordinator.isRefreshing }
		#expect(finished(bank) != nil)
		#expect(second.answers.all.isEmpty)
	}

	/// Every call of `ended`, in order.
	@MainActor
	final class EndLog {
		var all: [(access: UUID, accounts: [UUID: AccountRefresh])] = []
	}

	func logEnds(of coordinator: SyncCoordinator) -> EndLog {
		let log = EndLog()
		coordinator.ended = { access, _, accounts, _ in log.all.append((access, accounts)) }
		return log
	}

	@Test("A command for an access that runs fetches its other accounts when the run ends")
	func busyAccess() async throws {
		let log = logEnds(of: coordinator)
		let bank = Self.access("Musterbank")
		_ = refresh(bank, [.wait(.milliseconds(200)), .fetched(Self.giro.accountID)], accounts: [Self.giro])
		_ = refresh(bank, [.fetched(Self.giro.accountID), .fetched(Self.savings.accountID)], accounts: [Self.giro, Self.savings])
		#expect(coordinator.refreshingAccounts == [Self.giro.accountID, Self.savings.accountID])
		await until { log.all.count == 2 && !coordinator.isRefreshing }
		let at = try #require(finished(bank)?.finishedAt)
		#expect(log.all.map(\.access) == [bank.id, bank.id])
		#expect(log.all.first?.accounts.keys.sorted() == [Self.giro.accountID])
		#expect(log.all.last?.accounts == [Self.savings.accountID: .refreshed(at)])
		#expect(coordinator.refreshingAccounts.isEmpty)
	}

	@Test("A command right after Cancel Refresh runs when the canceled connector has ended")
	func afterCancel() async throws {
		let log = logEnds(of: coordinator)
		let bank = Self.access("Musterbank")
		_ = refresh(bank, [.ask(Self.tan), .fetched(Self.giro.accountID)], accounts: [Self.giro])
		await until { broker.current != nil }
		coordinator.cancelAll()
		_ = refresh(bank, [.fetched(Self.giro.accountID)], accounts: [Self.giro])
		#expect(coordinator.refreshingAccounts == [Self.giro.accountID])
		await until { log.all.count == 2 && !coordinator.isRefreshing }
		let at = try #require(finished(bank)?.finishedAt)
		#expect(log.all.first?.accounts == [:])
		#expect(log.all.last?.accounts == [Self.giro.accountID: .refreshed(at)])
	}

	@Test("Canceling one access stops its run and drops its waiting refresh, and the other accesses go on")
	func cancelOneAccess() async {
		let coordinator = SyncCoordinator(limit: 1)
		let log = logEnds(of: coordinator)
		let first = Self.access("Musterbank"), second = Self.access("Beispielbank"), third = Self.access("Sparkasse")
		coordinator.refresh(RefreshRequest(access: first, accounts: [Self.card]), with: ScriptedConnector([.wait(.seconds(60))]), attended: true)
		coordinator.refresh(RefreshRequest(access: second, accounts: [Self.giro]), with: ScriptedConnector([.fetched(Self.giro.accountID)]), attended: true)
		coordinator.refresh(RefreshRequest(access: third, accounts: [Self.savings]), with: ScriptedConnector([.fetched(Self.savings.accountID)]), attended: true)
		coordinator.cancelRefresh(of: second.id)
		coordinator.cancelRefresh(of: first.id)
		#expect(coordinator.states[first.id] == .cancelled)
		#expect(!coordinator.refreshingAccounts.contains(Self.giro.accountID))
		await until { !coordinator.isRefreshing }
		#expect(log.all.map(\.access) == [first.id, third.id])
		#expect(log.all.last?.accounts.keys.sorted() == [Self.savings.accountID])
	}

	@Test("Canceling the refreshes of a source closes its login dialog, also of a setup whose access the app does not have yet, and the login never reaches the connector")
	func cancelBySource() async {
		let setup = Access(source: .extension(id: "example"), bankName: "Example Bank", loginName: "")
		let other = Self.access("Musterbank")
		let log = logEnds(of: coordinator)
		let login = UserRequest.login(LoginRequest(service: "Example Bank", fields: LoginRequest.defaultFields, rejected: false))
		let scripted = refresh(setup, [.ask(login), .fetched(Self.giro.accountID)])
		await until { broker.current?.access == setup }
		let dialog = broker.current?.id
		_ = refresh(other, [.fetched(Self.savings.accountID)], accounts: [Self.savings])
		coordinator.cancelRefreshes(of: .extension(id: "example"))
		// The user submits the dialog that is still on screen.
		if let dialog { broker.answer(.login([Secret("erika"), Secret("geheim")]), to: dialog) }
		await until { broker.current?.access != setup && !coordinator.isRefreshing }
		#expect(broker.current?.access != setup)
		#expect(coordinator.states[setup.id] == .cancelled)
		#expect(scripted.answers.all.isEmpty)
		#expect(log.all.first { $0.access == setup.id }?.accounts == [:])
		#expect(log.all.first { $0.access == other.id }?.accounts.keys.sorted() == [Self.savings.accountID])
	}

	@Test("A command for an access that waits for its turn joins the waiting request")
	func waitingAccess() async throws {
		let coordinator = SyncCoordinator(limit: 1)
		let log = logEnds(of: coordinator)
		let first = Self.access("Musterbank"), second = Self.access("Beispielbank")
		coordinator.refresh(RefreshRequest(access: first, accounts: [Self.card]), with: ScriptedConnector([.wait(.milliseconds(100))]), attended: true)
		coordinator.refresh(RefreshRequest(access: second, accounts: [Self.giro]),
			with: ScriptedConnector([.fetched(Self.giro.accountID), .fetched(Self.savings.accountID)]), attended: true)
		coordinator.refresh(RefreshRequest(access: second, accounts: [Self.savings]), with: ScriptedConnector([]), attended: true)
		await until { log.all.count == 2 && !coordinator.isRefreshing }
		#expect(log.all.last?.access == second.id)
		#expect(log.all.last?.accounts.keys.sorted() == [Self.giro.accountID, Self.savings.accountID].sorted())
	}

	@Test("A second click answers nothing, not the next dialog")
	func doubleClick() async {
		let first = Self.access("Musterbank")
		let second = Self.access("Beispielbank")
		let a = refresh(first, [.ask(Self.pin)])
		await until { broker.current?.access == first }
		let b = refresh(second, [.ask(Self.pin)], accounts: [Self.savings])
		await until { state(second) == .needsUser(.pin, waiting: true, during: .connecting) }
		let id = broker.current!.id
		broker.answer(.pin(Secret("11111")), to: id)
		broker.answer(.pin(Secret("11111")), to: id)
		broker.cancel(id)
		await until { broker.current?.access == second }
		#expect(state(second) == .needsUser(.pin, waiting: false, during: .connecting))
		answer(.pin(Secret("22222")))
		await until { !coordinator.isRefreshing }
		#expect(a.answers.all == [.pin(Secret("11111"))])
		#expect(b.answers.all == [.pin(Secret("22222"))])
	}

	@Test("A PIN is kept only after a refresh with it succeeded")
	func pinForgottenAfterFailure() async {
		let bank = Self.access("Musterbank")
		_ = refresh(bank, [.ask(Self.pin), .fail(.offline)])
		await until { broker.current != nil }
		answer(.pin(Secret("1234-typo")))
		await until { state(bank) == .failed(.offline) }

		_ = refresh(bank, [.ask(Self.pin)])
		await until { broker.current?.access == bank }
		cancelOnScreen()
		await until { !coordinator.isRefreshing }
	}

	@Test("An automatic refresh uses the PIN in memory")
	func automaticUsesPIN() async {
		let bank = Self.access("Musterbank")
		_ = refresh(bank, [.ask(Self.pin)])
		await until { broker.current != nil }
		answer(.pin(Secret("12345")))
		await until { finished(bank) != nil }

		let automatic = refresh(bank, [.ask(Self.pin), .fetched(Self.giro.accountID)], attended: false)
		await until { finished(bank) != nil && !coordinator.isRefreshing }
		#expect(automatic.answers.all == [.pin(Secret("12345"))])
	}

	@Test("A connector that goes on after an expired challenge finishes")
	func expiredThenContinue() async {
		struct GoesOn: BankConnector {
			func refresh(_ request: RefreshRequest, _ session: SyncSession) async throws -> ConnectorReport {
				let tan = UserRequest.secondFactor(SecondFactorRequest(purpose: .download, system: .fintsServer,
					challenge: .enterTAN(prompt: "TAN", image: nil), validity: .milliseconds(100)))
				do { _ = try await session.ask(tan) } catch SyncFailure.challengeExpired {}
				await session.report(.fetching(done: 1, of: 1))
				return ConnectorReport(outcomes: [:])
			}
		}
		let bank = Self.access("Musterbank")
		coordinator.refresh(RefreshRequest(access: bank, accounts: [Self.giro]), with: GoesOn(), attended: true)
		await until { finished(bank) != nil }
		#expect(finished(bank)?.failures == [Self.giro.accountID: .notFetched])
	}

	@Test("Each fetched account is delivered once with its result, a failed or missing one never")
	func deliversFetchedAccounts() async {
		var delivered: [UUID: Money?] = [:]
		coordinator.deliver = { delivered[$0] = $1.balance }
		let bank = Self.access("Musterbank")
		let blocked = SyncFailure.bank(BankMessage(text: "Zugang gesperrt"))
		let result = RefreshResult(balance: Money(minorUnits: 501_240, currency: "EUR"), transactions: nil)
		_ = refresh(bank, [.fetched(Self.savings.accountID, result), .failAccount(Self.giro.accountID, blocked)], accounts: [Self.giro, Self.savings, Self.card])
		await until { finished(bank) != nil }
		#expect(delivered == [Self.savings.accountID: Money(minorUnits: 501_240, currency: "EUR")])
		#expect(finished(bank)?.fetched == [Self.savings.accountID])
		#expect(finished(bank)?.failures == [Self.giro.accountID: blocked, Self.card.accountID: .notFetched])
	}

	@Test("A failed transaction request stores the balance and fails the account, so its last refresh time stays")
	func balanceWithoutTransactions() async throws {
		var delivered: [UUID: Money?] = [:]
		coordinator.deliver = { delivered[$0] = $1.balance }
		let ends = recordEnds()
		let bank = Self.access("Musterbank")
		let rejected = SyncFailure.bank(BankMessage(code: "9010", text: "Verarbeitung nicht möglich"))
		let balance = Money(minorUnits: 234_015, currency: "EUR")
		_ = refresh(bank, [.fetched(Self.giro.accountID, RefreshResult(balance: balance, transactions: nil, transactionFailure: rejected))])
		await until { ends.accounts[bank.id] != nil }
		let at = try #require(finished(bank)?.finishedAt)
		#expect(delivered == [Self.giro.accountID: balance])
		#expect(ends.accounts[bank.id] == [Self.giro.accountID: .failed(RefreshError(message: "Verarbeitung nicht möglich", code: "9010", date: at))])
	}

	@Test("An account that could not be stored fails with notSaved, the others finish, and the PIN stays")
	func notSaved() async {
		struct DiskFull: Error {}
		coordinator.deliver = { id, _ in if id == Self.savings.accountID { throw DiskFull() } }
		let bank = Self.access("Musterbank")
		_ = refresh(bank, [.ask(Self.pin), .fetched(Self.giro.accountID), .fetched(Self.savings.accountID)], accounts: [Self.giro, Self.savings])
		await until { broker.current != nil }
		answer(.pin(Secret("12345")))
		await until { finished(bank) != nil }
		#expect(finished(bank)?.fetched == [Self.giro.accountID])
		#expect(finished(bank)?.failures == [Self.savings.accountID: .notSaved("DiskFull()")])

		let second = refresh(bank, [.ask(Self.pin)])
		await until { finished(bank) != nil && !coordinator.isRefreshing }
		#expect(second.answers.all == [.pin(Secret("12345"))])
	}

	@Test("A canceled access delivers nothing, even when its connector returns")
	func canceledDeliversNothing() async {
		var delivered = 0
		let coordinator = SyncCoordinator()
		coordinator.deliver = { _, _ in delivered += 1 }
		let bank = Self.access("Musterbank")
		coordinator.refresh(RefreshRequest(access: bank, accounts: [Self.giro]), with: ScriptedConnector([.fetched(Self.giro.accountID)]), attended: true)
		coordinator.cancelAll()
		await until { !coordinator.isRefreshing }
		#expect(coordinator.states[bank.id] == .cancelled)
		#expect(delivered == 0)
	}

	/// What `ended` reported, by access.
	@MainActor
	final class Ends {
		var states: [UUID: AccessState?] = [:]
		var accounts: [UUID: [UUID: AccountRefresh]] = [:]
	}

	func recordEnds() -> Ends {
		let ends = Ends()
		coordinator.ended = { access, state, accounts, _ in
			ends.states[access] = state
			ends.accounts[access] = accounts
		}
		return ends
	}

	@Test("The end of a refresh brings the new state of the access and the outcome of each account")
	func endReportsStateAndAccounts() async throws {
		let ends = recordEnds()
		let bank = Self.access("Musterbank")
		let blocked = BankMessage(code: "9010", text: "Konto gesperrt")
		_ = refresh(bank, [.state(AccessState(Data([7]))), .fetched(Self.giro.accountID), .failAccount(Self.savings.accountID, .bank(blocked))],
			accounts: [Self.giro, Self.savings, Self.card])
		#expect(coordinator.refreshingAccounts == [Self.giro.accountID, Self.savings.accountID, Self.card.accountID])
		await until { ends.accounts[bank.id] != nil }
		let at = try #require(finished(bank)?.finishedAt)
		#expect(ends.states[bank.id] == AccessState(Data([7])))
		#expect(ends.accounts[bank.id] == [
			Self.giro.accountID: .refreshed(at),
			Self.savings.accountID: .failed(RefreshError(message: "Konto gesperrt", code: "9010", date: at)),
			Self.card.accountID: .failed(RefreshError(message: "Canceled because of the previous error.", date: at)),
		])
		#expect(coordinator.refreshingAccounts.isEmpty)
	}

	@Test("A failed access marks all its requested accounts, and a canceled one marks none and keeps the state")
	func endAfterFailureAndCancel() async {
		let ends = recordEnds()
		let failing = Self.access("Musterbank")
		_ = refresh(failing, [.state(AccessState(Data([1]))), .fail(.network("Zeitüberschreitung"))], accounts: [Self.giro, Self.savings])
		await until { ends.accounts[failing.id] != nil }
		#expect(ends.states[failing.id] == .some(nil))
		#expect(ends.accounts[failing.id]?.mapValues { refresh -> String? in
			if case let .failed(error) = refresh { error.message } else { nil }
		} == [Self.giro.accountID: "The bank could not be reached: Zeitüberschreitung", Self.savings.accountID: "The bank could not be reached: Zeitüberschreitung"])

		let canceled = Self.access("Beispielbank")
		_ = refresh(canceled, [.state(AccessState(Data([2]))), .ask(Self.tan), .fetched(Self.card.accountID)], accounts: [Self.card])
		await until { broker.current != nil }
		#expect(coordinator.refreshingAccounts == [Self.card.accountID])
		coordinator.cancelAll()
		#expect(coordinator.refreshingAccounts.isEmpty)
		await until { ends.accounts[canceled.id] != nil }
		#expect(ends.states[canceled.id] == .some(nil))
		#expect(ends.accounts[canceled.id] == [:])
		#expect(coordinator.refreshingAccounts.isEmpty)
	}

	/// What happened to an access, in order.
	@MainActor
	final class Events {
		var all: [String] = []
	}

	@Test("The login of a setup waits for the refresh of its access, and a refresh asked for meanwhile waits for the login")
	func setupBesideRefresh() async throws {
		let events = Events()
		coordinator.ended = { _, _, _, _ in events.all.append("refresh ended") }
		let bank = Self.access("Musterbank")
		_ = refresh(bank, [.ask(Self.pin), .fetched(Self.giro.accountID)])
		await until { broker.current != nil }
		let login = Task {
			try await coordinator.exclusively(for: bank.id) {
				events.all.append("login started")
				_ = refresh(bank, [.fetched(Self.savings.accountID)], accounts: [Self.savings])
				try await Task.sleep(for: .milliseconds(100))
				events.all.append("login ended")
			}
		}
		try await Task.sleep(for: .milliseconds(50))
		#expect(events.all.isEmpty)
		answer(.pin(Secret("12345")))
		try await login.value
		await until { events.all.count == 4 && !coordinator.isRefreshing }
		#expect(events.all == ["refresh ended", "login started", "login ended", "refresh ended"])
		#expect(coordinator.refreshingAccounts.isEmpty)
	}

	@Test("Cancel Refresh drops a refresh that waits for the login of a setup")
	func cancelBehindSetup() async throws {
		let events = Events()
		coordinator.ended = { _, _, _, _ in events.all.append("refresh ended") }
		let bank = Self.access("Musterbank")
		try await coordinator.exclusively(for: bank.id) {
			_ = refresh(bank, [.fetched(Self.giro.accountID)])
			#expect(coordinator.isRefreshing)
			coordinator.cancelAll()
			#expect(!coordinator.isRefreshing)
			#expect(coordinator.refreshingAccounts.isEmpty)
		}
		try await Task.sleep(for: .milliseconds(50))
		#expect(events.all.isEmpty)
	}
}
