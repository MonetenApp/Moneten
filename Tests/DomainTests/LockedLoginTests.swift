import Foundation
import Testing
@testable import Domain

/// The safety net for the FinTS login of ING that waits for a login on its website (add-fints-banking, "Pause the
/// automatic refresh while the FinTS login of ING stays locked"). The PIN stays, so the automatic refresh would log in
/// again and again. After `RefreshError.lockedLoginLimit` automatic refreshes in a row that end with the lock, it
/// pauses for the access.
@Suite("ING login lock")
struct LockedLoginTests {
	static let access = UUID()
	static let eight = Date(timeIntervalSince1970: 1_793_520_000)  // 2026-11-01 08:00 UTC
	static let locked = SyncFailure.websiteLoginNeeded(BankMessage(code: "9942", text: "Bitte erneuern Sie ihre Authentifizierung. Einfach unter ING.de einloggen."))
	static let pause = "The automatic refresh paused after 2 attempts. After the login on the website, refresh the account by hand."

	static func account(_ name: String, _ interval: RefreshInterval = .everyTwoHours) -> Account {
		Account(position: 0, name: name, kind: .giro, source: .bank, accessID: access, remoteID: "R-\(name)", refreshedAt: eight, refreshInterval: interval)
	}

	static func hours(_ h: Double) -> Date { eight.addingTimeInterval(h * 3600) }

	/// The ledger after a refresh of the accounts `only`, or of every account of the access, that ended with `end` at `hour`.
	static func refresh(_ ledger: Ledger, _ end: SyncState, at hour: Double, attended: Bool = false, only: [String]? = nil) -> Ledger {
		var ledger = ledger
		let ids = ledger.accounts.filter { only?.contains($0.name) != false }.map(\.id)
		for a in ledger.recorded(end.accountRefreshes(of: ids, notices: [], at: hours(hour)), of: access, attended: attended) { ledger.upsert(a) }
		return ledger
	}

	static func locks(_ ledger: Ledger, at hours: [Double], only: [String]? = nil) -> Ledger {
		hours.reduce(ledger) { refresh($0, .failed(locked), at: $1, only: only) }
	}

	static func due(_ ledger: Ledger, at hour: Double) -> [String] {
		(ledger.dueAccounts(at: hours(hour))[access] ?? []).map(\.name)
	}

	static func paused(_ ledger: Ledger) -> [Bool?] {
		ledger.accounts.map { $0.refreshError?.pausesForLockedLogin }
	}

	@Test("Two automatic refreshes in a row that end with the lock pause the automatic refresh, and the account says why")
	func pausesAfterTwo() throws {
		var ledger = Self.locks(Ledger(accounts: [Self.account("Giro")]), at: [2])
		#expect(Self.due(ledger, at: 4) == ["Giro"])
		#expect(ledger.accounts[0].refreshError?.shownMessage == Self.locked.message)
		ledger = Self.locks(ledger, at: [4])
		let error = try #require(ledger.accounts[0].refreshError)
		#expect(error.waitsForUser)
		#expect(error.code == "9942")
		#expect(error.message == Self.locked.message)
		#expect(error.shownMessage == Self.locked.message + "\n" + Self.pause)
		#expect(ledger.pausesAutomaticRefresh(of: Self.access))
		#expect(Self.due(ledger, at: 100).isEmpty)
	}

	@Test("A refresh by hand runs and starts the count again")
	func manualRefreshResets() {
		var ledger = Self.locks(Ledger(accounts: [Self.account("Giro")]), at: [2, 4])
		#expect(Self.due(ledger, at: 100).isEmpty)
		#expect(ledger.refreshAccounts(.all)[Self.access]?.map(\.name) == ["Giro"])
		ledger = Self.refresh(ledger, .failed(Self.locked), at: 7, attended: true)
		#expect(ledger.accounts[0].refreshError?.waitsForUser == false)
		#expect(ledger.accounts[0].refreshError?.shownMessage == Self.locked.message)
		ledger = Self.locks(ledger, at: [9])
		#expect(Self.due(ledger, at: 11) == ["Giro"])
		ledger = Self.locks(ledger, at: [11])
		#expect(Self.due(ledger, at: 100).isEmpty)
	}

	@Test("A successful login ends the lock")
	func successResets() {
		var ledger = Self.locks(Ledger(accounts: [Self.account("Giro")]), at: [2])
		let ids = ledger.accounts.map(\.id)
		ledger = Self.refresh(ledger, .finished(SyncSummary(finishedAt: Self.hours(4), fetched: Set(ids), failures: [:])), at: 4)
		#expect(ledger.accounts[0].refreshError == nil)
		ledger = Self.locks(ledger, at: [6])
		#expect(Self.due(ledger, at: 8) == ["Giro"])
	}

	@Test("Another failure between two locks breaks the row")
	func otherFailureBreaksTheRow() {
		var ledger = Self.locks(Ledger(accounts: [Self.account("Giro")]), at: [2])
		ledger = Self.refresh(ledger, .failed(.bank(BankMessage(code: "9800", text: "Dialog abgebrochen"))), at: 4)
		ledger = Self.locks(ledger, at: [6])
		#expect(Self.due(ledger, at: 8) == ["Giro"])
	}

	@Test("Every open account of the access takes the lock and its count, also one that the refresh did not fetch")
	func countPerAccess() {
		var ledger = Ledger(accounts: [Self.account("Giro"), Self.account("Card", .onceADay)])
		ledger = Self.locks(ledger, at: [2], only: ["Giro"])
		#expect(ledger.accounts.map { $0.refreshError?.lockedLogins } == [1, 1])
		#expect(ledger.accounts.map { $0.refreshError?.code } == ["9942", "9942"])
		ledger = Self.locks(ledger, at: [4], only: ["Giro"])
		#expect(Self.paused(ledger) == [true, true])
		#expect(Self.due(ledger, at: 100).isEmpty)
	}

	@Test("An account that the user adds to a paused access waits too")
	func newAccountWaits() {
		let ledger = Self.locks(Ledger(accounts: [Self.account("Giro")]), at: [2, 4])
		let added = Ledger(accounts: ledger.accounts + [Self.account("New")])
		#expect(Self.due(added, at: 100).isEmpty)
	}

	@Test("A refresh by hand or a success of one account frees every account of the access")
	func resetPerAccess() {
		var ledger = Self.locks(Ledger(accounts: [Self.account("Giro"), Self.account("Card")]), at: [2, 4])
		ledger = Self.refresh(ledger, .failed(Self.locked), at: 5, attended: true, only: ["Giro"])
		#expect(Self.paused(ledger) == [false, false])
		#expect(Self.due(ledger, at: 7) == ["Giro", "Card"])

		ledger = Self.locks(ledger, at: [7, 9])
		#expect(Self.paused(ledger) == [true, true])
		let card = ledger.accounts[1].id
		ledger = Self.refresh(ledger, .finished(SyncSummary(finishedAt: Self.hours(10), fetched: [card], failures: [:])), at: 10, attended: true, only: ["Card"])
		#expect(ledger.accounts.map(\.refreshError) == [nil, nil])
		#expect(Self.due(ledger, at: 100) == ["Giro", "Card"])
	}

	@Test("The pause stays when the user closes the account that met the lock")
	func closedDuringPause() throws {
		var ledger = Self.locks(Ledger(accounts: [Self.account("Giro"), Self.account("Card", .onceADay)]), at: [2, 4], only: ["Giro"])
		let closed = try ledger.closing(ledger.accounts[0], today: Day(Self.hours(5)))
		ledger.upsert(closed.account)
		#expect(ledger.accounts[0].shownRefreshError == nil)
		#expect(ledger.accounts[0].refreshError?.lockedLogins == 2)
		#expect(Self.due(ledger, at: 100).isEmpty)
	}

	static func close(_ ledger: inout Ledger, _ name: String) throws {
		let account = try #require(ledger.accounts.first { $0.name == name })
		ledger.upsert(try ledger.closing(account, today: Day(hours(5))).account)
	}

	static func reopen(_ ledger: inout Ledger, _ name: String) throws {
		let account = try #require(ledger.accounts.first { $0.name == name })
		ledger.upsert(try ledger.reopening(account).account)
	}

	@Test("Pause both, close Giro, reopen Giro, close Card: Giro stays paused")
	func reopenDuringPause() throws {
		var ledger = Self.locks(Ledger(accounts: [Self.account("Giro"), Self.account("Card", .onceADay)]), at: [2, 4])
		try Self.close(&ledger, "Giro")
		try Self.reopen(&ledger, "Giro")
		try Self.close(&ledger, "Card")
		#expect(ledger.accounts.first { $0.name == "Giro" }?.shownRefreshError?.pausesForLockedLogin == true)
		#expect(Self.due(ledger, at: 100).isEmpty)
	}

	@Test("Closing and reopening the only account of a paused access keeps the pause, and an account reopened after the pause began takes the lock")
	func reopenOnlyAccount() throws {
		var ledger = Self.locks(Ledger(accounts: [Self.account("Giro")]), at: [2, 4])
		try Self.close(&ledger, "Giro")
		try Self.reopen(&ledger, "Giro")
		#expect(Self.due(ledger, at: 100).isEmpty)

		var card = Self.account("Card")
		card.isClosed = true
		ledger = Self.locks(Ledger(accounts: [Self.account("Giro"), card]), at: [2, 4], only: ["Giro"])
		try Self.reopen(&ledger, "Card")
		try Self.close(&ledger, "Giro")
		#expect(ledger.accounts.first { $0.name == "Card" }?.refreshError?.pausesForLockedLogin == true)
		#expect(Self.due(ledger, at: 100).isEmpty)
	}

	@Test("A refresh by hand frees a closed account that carries the lock too")
	func manualRefreshFreesClosedCarrier() throws {
		var ledger = Self.locks(Ledger(accounts: [Self.account("Giro"), Self.account("Card")]), at: [2, 4])
		try Self.close(&ledger, "Card")
		ledger = Self.refresh(ledger, .failed(Self.locked), at: 5, attended: true, only: ["Giro"])
		#expect(!ledger.pausesAutomaticRefresh(of: Self.access))
		#expect(Self.due(ledger, at: 7) == ["Giro"])
	}

	@Test("A report that mixes a fetched account with the lock counts the lock and keeps the success")
	func mixedReport() {
		var ledger = Ledger(accounts: [Self.account("Giro"), Self.account("Card")])
		let giro = ledger.accounts[0].id, card = ledger.accounts[1].id
		let mixed = SyncState.finished(SyncSummary(finishedAt: Self.hours(2), fetched: [card], failures: [giro: Self.locked]))
		ledger = Self.refresh(ledger, mixed, at: 2)
		#expect(ledger.accounts.map { $0.refreshError?.lockedLogins } == [1, nil])
		ledger = Self.refresh(ledger, mixed, at: 4)
		#expect(ledger.accounts[0].refreshError?.pausesForLockedLogin == true)
		#expect(ledger.accounts[1].refreshError == nil)
		#expect(Self.due(ledger, at: 100).isEmpty)
	}

	@Test("Another failure removes the copy of the lock from an account that the refresh did not fetch")
	func otherFailureRemovesCopy() {
		var ledger = Self.locks(Ledger(accounts: [Self.account("Giro"), Self.account("Card", .onceADay)]), at: [2], only: ["Giro"])
		#expect(ledger.accounts[1].refreshError?.lockedLogins == 1)
		ledger = Self.refresh(ledger, .failed(.bank(BankMessage(code: "9800", text: "Dialog abgebrochen"))), at: 4, only: ["Giro"])
		#expect(ledger.accounts[0].refreshError?.code == "9800")
		#expect(ledger.accounts[1].refreshError == nil)
	}

	@Test("The pause stays when the user deletes the account that met the lock")
	func deletedDuringPause() {
		let ledger = Self.locks(Ledger(accounts: [Self.account("Giro"), Self.account("Card", .onceADay)]), at: [2, 4], only: ["Giro"])
		let deleted = Ledger(accounts: ledger.accounts.filter { $0.name != "Giro" })
		#expect(Self.due(deleted, at: 100).isEmpty)
	}

	@Test("A refresh error stored before the count existed reads without it")
	func decodesOldError() throws {
		let old = #"{"message":"Fehler","date":0,"notices":[],"waitsForUser":false,"suggestsEditLoginData":false}"#
		let error = try JSONDecoder().decode(RefreshError.self, from: Data(old.utf8))
		#expect(error.lockedLogins == nil)
	}
}
