import Domain
import Foundation
import SyncTesting
import Testing
@testable import Sync

/// An automatic refresh that the coordinator holds back while the FinTS login of ING is locked (add-fints-banking,
/// "Pause the automatic refresh while the FinTS login of ING stays locked"). The count lives in the ledger
/// (`Ledger.recorded`); these tests cover the work that waits in the coordinator when the count changes.
@MainActor
@Suite("ING login lock in the coordinator")
struct LockedLoginSyncTests {
	let coordinator = SyncCoordinator()

	static let ing = Access(source: .fints(bankCode: "50010517", url: URL(string: "https://fints.ing.de/fints/")!), bankName: "ING", loginName: "erika77")
	static let giro = AccountRequest(accountID: UUID(), name: "Giro", remoteID: "1234", currency: "EUR")
	static let card = AccountRequest(accountID: UUID(), name: "Card", remoteID: "9012", currency: "EUR")
	static let locked = SyncFailure.websiteLoginNeeded(BankMessage(code: "9942", text: "Bitte erneuern Sie ihre Authentifizierung. Einfach unter ING.de einloggen."))

	/// The accounts of each refresh that ended, in order.
	func logEnds() -> () -> [[UUID]] {
		final class Log { var all: [[UUID]] = [] }
		let log = Log()
		coordinator.ended = { _, accounts, _ in log.all.append(accounts.keys.sorted { $0.uuidString < $1.uuidString }) }
		return { log.all }
	}

	func refresh(_ steps: [ScriptedConnector.Step], _ accounts: [AccountRequest], attended: Bool) {
		coordinator.refresh(RefreshRequest(access: Self.ing, accounts: accounts), with: ScriptedConnector(steps), attended: attended)
	}

	func untilIdle() async {
		for _ in 0..<200 where coordinator.isRefreshing {
			try? await Task.sleep(for: .milliseconds(10))
		}
		#expect(!coordinator.isRefreshing)
	}

	@Test("An automatic refresh that waits for a run of the access that ends with the lock does not start, and its accounts stay due")
	func dropsWaitingAutomaticRefresh() async {
		let ends = logEnds()
		refresh([.wait(.milliseconds(100)), .fail(Self.locked)], [Self.giro], attended: false)
		refresh([.fetched(Self.card.accountID)], [Self.card], attended: false)
		#expect(coordinator.refreshingAccounts == [Self.giro.accountID, Self.card.accountID])
		await untilIdle()
		#expect(ends() == [[Self.giro.accountID]])
		#expect(coordinator.refreshingAccounts.isEmpty)
	}

	@Test("A refresh by hand that waits for a run of the access that ends with the lock still runs")
	func keepsWaitingManualRefresh() async {
		let ends = logEnds()
		refresh([.wait(.milliseconds(100)), .fail(Self.locked)], [Self.giro], attended: false)
		refresh([.fetched(Self.card.accountID)], [Self.card], attended: true)
		await untilIdle()
		#expect(ends() == [[Self.giro.accountID], [Self.card.accountID]])
	}

	@Test("An automatic refresh of an access whose automatic refresh paused does not start when its turn comes, and a refresh by hand does")
	func skipsPausedAccess() async {
		let ends = logEnds()
		coordinator.pausesUnattended = { $0 == Self.ing.id }
		refresh([.fetched(Self.giro.accountID)], [Self.giro], attended: false)
		await untilIdle()
		#expect(ends().isEmpty)
		#expect(coordinator.refreshingAccounts.isEmpty)
		refresh([.fetched(Self.giro.accountID)], [Self.giro], attended: true)
		await untilIdle()
		#expect(ends() == [[Self.giro.accountID]])
	}

	@Test("A run whose report mixes a fetched account with the lock drops the automatic refresh that waits for it")
	func mixedReportDropsWaitingAutomaticRefresh() async {
		let ends = logEnds()
		refresh([.wait(.milliseconds(100)), .fetched(Self.card.accountID), .failAccount(Self.giro.accountID, Self.locked)], [Self.giro, Self.card], attended: false)
		refresh([.fetched(Self.giro.accountID)], [Self.giro], attended: false)
		await untilIdle()
		#expect(ends().count == 1)
	}

	@Test("Until the app recorded a run that ended with the lock, an automatic refresh of the access does not start, whatever the ledger says")
	func waitsForTheRecordOfTheLock() async {
		let ends = logEnds()
		// The app has not recorded the run yet, so its ledger does not pause the access.
		coordinator.pausesUnattended = { _ in false }
		refresh([.fetched(Self.card.accountID), .failAccount(Self.giro.accountID, Self.locked)], [Self.giro, Self.card], attended: false)
		await untilIdle()
		refresh([.fetched(Self.giro.accountID)], [Self.giro], attended: false)
		await untilIdle()
		#expect(ends().count == 1)
		refresh([.fetched(Self.giro.accountID)], [Self.giro], attended: true)
		await untilIdle()
		#expect(ends().count == 2)
		coordinator.recordedRefresh(of: Self.ing.id)
		refresh([.fetched(Self.giro.accountID)], [Self.giro], attended: false)
		await untilIdle()
		#expect(ends().count == 3)
	}
}
