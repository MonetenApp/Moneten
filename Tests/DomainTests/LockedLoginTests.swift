import Foundation
import Testing
@testable import Domain

/// The safety net for the FinTS login of ING that waits for a login on its website (add-fints-banking, "Pause the
/// automatic refresh while the FinTS login of ING stays locked"). The PIN stays, so the automatic refresh would log in
/// again and again. After three automatic refreshes in a row that end with the lock, it pauses for the access.
@Suite("ING login lock")
struct LockedLoginTests {
	static let access = UUID()
	static let eight = Date(timeIntervalSince1970: 1_793_520_000)  // 2026-11-01 08:00 UTC
	static let locked = SyncFailure.websiteLoginNeeded(BankMessage(code: "9942", text: "Bitte erneuern Sie ihre Authentifizierung. Einfach unter ING.de einloggen."))
	static let pause = "The automatic refresh paused after 3 attempts. After the login on the website, refresh the account by hand."

	static func account(_ name: String) -> Account {
		Account(position: 0, name: name, kind: .giro, source: .bank, accessID: access, remoteID: "R-\(name)", refreshedAt: eight, refreshInterval: .everyTwoHours)
	}

	static func hours(_ h: Double) -> Date { eight.addingTimeInterval(h * 3600) }

	/// The ledger after a refresh of the accounts `only`, or of every account of the access, that ended with `end` at `hour`.
	static func refresh(_ ledger: Ledger, _ end: SyncState, at hour: Double, attended: Bool = false, only: [String]? = nil) -> Ledger {
		var ledger = ledger
		let ids = ledger.accounts.filter { only?.contains($0.name) != false }.map(\.id)
		for a in ledger.recorded(end.accountRefreshes(of: ids, notices: [], at: hours(hour)), of: access, attended: attended) { ledger.upsert(a) }
		return ledger
	}

	static func due(_ ledger: Ledger, at hour: Double) -> [String] {
		(ledger.dueAccounts(at: hours(hour))[access] ?? []).map(\.name)
	}

	@Test("Three automatic refreshes in a row that end with the lock pause the automatic refresh, and the account says why")
	func pausesAfterThree() throws {
		var ledger = Ledger(accounts: [Self.account("Giro")])
		ledger = Self.refresh(ledger, .failed(Self.locked), at: 2)
		ledger = Self.refresh(ledger, .failed(Self.locked), at: 4)
		#expect(Self.due(ledger, at: 6) == ["Giro"])
		#expect(ledger.accounts[0].refreshError?.waitsForUser == false)
		ledger = Self.refresh(ledger, .failed(Self.locked), at: 6)
		let error = try #require(ledger.accounts[0].refreshError)
		#expect(error.waitsForUser)
		#expect(error.code == "9942")
		#expect(error.message == Self.locked.message + "\n" + Self.pause)
		#expect(Self.due(ledger, at: 100).isEmpty)
	}

	@Test("A refresh by hand runs and starts the count again")
	func manualRefreshResets() {
		var ledger = Ledger(accounts: [Self.account("Giro")])
		for hour in [2.0, 4, 6] { ledger = Self.refresh(ledger, .failed(Self.locked), at: hour) }
		#expect(Self.due(ledger, at: 100).isEmpty)
		#expect(ledger.refreshAccounts(.all)[Self.access]?.map(\.name) == ["Giro"])
		ledger = Self.refresh(ledger, .failed(Self.locked), at: 7, attended: true)
		#expect(ledger.accounts[0].refreshError?.waitsForUser == false)
		#expect(ledger.accounts[0].refreshError?.message == Self.locked.message)
		ledger = Self.refresh(ledger, .failed(Self.locked), at: 9)
		ledger = Self.refresh(ledger, .failed(Self.locked), at: 11)
		#expect(Self.due(ledger, at: 13) == ["Giro"])
		ledger = Self.refresh(ledger, .failed(Self.locked), at: 13)
		#expect(Self.due(ledger, at: 100).isEmpty)
	}

	@Test("A successful login clears the count")
	func successResets() {
		var ledger = Ledger(accounts: [Self.account("Giro")])
		ledger = Self.refresh(ledger, .failed(Self.locked), at: 2)
		ledger = Self.refresh(ledger, .failed(Self.locked), at: 4)
		let ids = ledger.accounts.map(\.id)
		ledger = Self.refresh(ledger, .finished(SyncSummary(finishedAt: Self.hours(6), fetched: Set(ids), failures: [:])), at: 6)
		#expect(ledger.accounts[0].refreshError == nil)
		ledger = Self.refresh(ledger, .failed(Self.locked), at: 8)
		ledger = Self.refresh(ledger, .failed(Self.locked), at: 10)
		#expect(Self.due(ledger, at: 12) == ["Giro"])
	}

	@Test("Another failure between two locks breaks the row")
	func otherFailureBreaksTheRow() {
		var ledger = Ledger(accounts: [Self.account("Giro")])
		ledger = Self.refresh(ledger, .failed(Self.locked), at: 2)
		ledger = Self.refresh(ledger, .failed(Self.locked), at: 4)
		ledger = Self.refresh(ledger, .failed(.bank(BankMessage(code: "9800", text: "Dialog abgebrochen"))), at: 6)
		ledger = Self.refresh(ledger, .failed(Self.locked), at: 8)
		ledger = Self.refresh(ledger, .failed(Self.locked), at: 10)
		#expect(Self.due(ledger, at: 12) == ["Giro"])
	}

	@Test("The count belongs to the access: an account that joins a later refresh pauses with the others")
	func countPerAccess() {
		var card = Self.account("Card")
		card.refreshInterval = .onceADay
		var ledger = Ledger(accounts: [Self.account("Giro"), card])
		ledger = Self.refresh(ledger, .failed(Self.locked), at: 2)
		ledger = Self.refresh(ledger, .failed(Self.locked), at: 4, only: ["Giro"])
		ledger = Self.refresh(ledger, .failed(Self.locked), at: 6, only: ["Giro"])
		#expect(ledger.accounts.map { $0.refreshError?.waitsForUser } == [true, false])
		#expect(Self.due(ledger, at: 26) == ["Card"])
		ledger = Self.refresh(ledger, .failed(Self.locked), at: 26, only: ["Card"])
		#expect(ledger.accounts.map { $0.refreshError?.waitsForUser } == [true, true])
		#expect(Self.due(ledger, at: 100).isEmpty)
	}

	@Test("A refresh error stored before the count existed reads without it")
	func decodesOldError() throws {
		let old = #"{"message":"Fehler","date":0,"notices":[],"waitsForUser":false,"suggestsEditLoginData":false}"#
		let error = try JSONDecoder().decode(RefreshError.self, from: Data(old.utf8))
		#expect(error.lockedLogins == nil)
	}
}
