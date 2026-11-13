import Foundation
import Testing
@testable import Domain

/// Which accounts the automatic refresh fetches, and which ones a refresh command leaves out
/// (add-account-refresh 1.4 to 1.7 and 1.11).
@Suite("Automatic refresh")
struct AutomaticRefreshTests {
	static let access = UUID()
	static let other = UUID()
	static let eight = Date(timeIntervalSince1970: 1_793_520_000)  // 2026-11-01 08:00 UTC

	static func account(_ name: String, _ interval: RefreshInterval = .everyTwoHours, access: UUID = access, refreshedAt: Date? = eight,
		error: RefreshError? = nil, closed: Bool = false) -> Account {
		Account(position: 0, name: name, kind: .giro, source: .bank, isClosed: closed, accessID: access, remoteID: "R-\(name)", refreshedAt: refreshedAt,
			refreshError: error, refreshInterval: interval)
	}

	static func hours(_ h: Double) -> Date { eight.addingTimeInterval(h * 3600) }

	static func due(_ accounts: [Account], at date: Date) -> [UUID: [String]] {
		Ledger(accounts: accounts).dueAccounts(at: date).mapValues { $0.map(\.name) }
	}

	@Test("A new account starts with the interval every two hours, and the settings offer six intervals")
	func intervals() {
		#expect(Account(position: 0, name: "Giro", kind: .giro, source: .bank).refreshInterval == .everyTwoHours)
		#expect(RefreshInterval.allCases.map(\.title) == ["every two hours", "four times a day", "once a day", "once a week", "only manually", "never"])
	}

	@Test("An account is due when its interval passed since its last refresh", arguments: [
		(RefreshInterval.everyTwoHours, 1.99, false), (.everyTwoHours, 2, true),
		(.fourTimesADay, 5.9, false), (.fourTimesADay, 6, true),
		(.onceADay, 4, false), (.onceADay, 24, true),
		(.onceAWeek, 167, false), (.onceAWeek, 168, true),
		(.onlyManually, 1_000, false), (.never, 1_000, false),
	])
	func due(interval: RefreshInterval, after: Double, due: Bool) {
		let plan = Self.due([Self.account("Giro", interval)], at: Self.hours(after))
		#expect(plan == (due ? [Self.access: ["Giro"]] : [:]))
	}

	@Test("Once a day: refreshed at 08:00, not fetched at 10:00 and 12:00, fetched by the first run after 08:00 on the next day")
	func onceADay() {
		let card = Self.account("Card", .onceADay)
		#expect(Self.due([card], at: Self.hours(2)).isEmpty)
		#expect(Self.due([card], at: Self.hours(4)).isEmpty)
		#expect(Self.due([card], at: Self.hours(24.1)) == [Self.access: ["Card"]])
	}

	@Test("An account that was never refreshed is due at once, and a closed one never is")
	func neverRefreshed() {
		#expect(Self.due([Self.account("Giro", refreshedAt: nil)], at: Self.eight) == [Self.access: ["Giro"]])
		#expect(Self.due([Self.account("Giro", refreshedAt: nil, closed: true)], at: Self.eight).isEmpty)
	}

	@Test("The due accounts of one access go into one request, with the first day of each account")
	func oneRequestPerAccess() {
		let plan = Ledger(accounts: [Self.account("Giro"), Self.account("Savings", .onceADay), Self.account("Card", access: Self.other),
			Self.account("Depot", .onlyManually)]).dueAccounts(at: Self.hours(3))
		#expect(plan.mapValues { $0.map(\.name) } == [Self.access: ["Giro"], Self.other: ["Card"]])
		#expect(plan[Self.access]?.first?.since == Day(Self.eight).adding(days: -14))
	}

	@Test("A failed refresh is tried again one interval after the failure, not at every run")
	func failure() {
		let error = RefreshError(message: "The bank could not be reached: timeout", date: Self.hours(3))
		let giro = Self.account("Giro", error: error)
		#expect(Self.due([giro], at: Self.hours(4)).isEmpty)
		#expect(Self.due([giro], at: Self.hours(5)) == [Self.access: ["Giro"]])
	}

	@Test("An account that waits for the user stays out of the automatic refresh, and every command still fetches it")
	func waitsForUser() {
		let tan = RefreshError(message: SyncFailure.needsUser(.secondFactor).message, date: Self.hours(2), waitsForUser: true)
		let giro = Self.account("Giro", error: tan)
		let ledger = Ledger(accounts: [giro])
		#expect(ledger.dueAccounts(at: Self.hours(100)).isEmpty)
		#expect(ledger.refreshAccounts(.all).mapValues { $0.map(\.name) } == [Self.access: ["Giro"]])
		#expect(ledger.refreshAccounts(.account(giro.id)).mapValues { $0.map(\.name) } == [Self.access: ["Giro"]])
	}

	@Test("Only failures that the user must resolve wait for a manual refresh", arguments: [
		(SyncFailure.needsUser(.pin), true), (.needsUser(.secondFactor), true), (.needsUser(.login), true), (.needsUser(.allowHost), true),
		(.pinRejected(BankMessage(code: "9942", text: "PIN falsch")), true), (.loginRejected, true),
		(.accessBlocked(BankMessage(code: "9931", text: "Zugang gesperrt")), true),
		(.network("timeout"), false), (.bank(BankMessage(code: "9010", text: "Zugang vorübergehend gesperrt")), false), (.notFetched, false),
		(.tanRejected(BankMessage(text: "TAN falsch")), false), (.challengeExpired, false), (.offline, false),
	])
	func failureWaitsForUser(failure: SyncFailure, waits: Bool) {
		let at = Self.eight
		let id = UUID()
		let refreshes = SyncState.failed(failure).accountRefreshes(of: [id], notices: [], at: at)
		#expect(refreshes == [id: .failed(RefreshError(message: failure.message, code: failure.bankMessage?.code, date: at, waitsForUser: waits))])
	}

	@Test("An error stored before the mark existed does not wait for the user")
	func oldError() throws {
		let json = Data(#"{"message":"Zugang vorübergehend gesperrt","code":"9010","date":0,"notices":[]}"#.utf8)
		let error = try JSONDecoder().decode(RefreshError.self, from: json)
		#expect(error == RefreshError(message: "Zugang vorübergehend gesperrt", code: "9010", date: Date(timeIntervalSinceReferenceDate: 0)))
	}

	@Test("Refresh All Accounts and Refresh Accounts leave out an account with the interval never, and Refresh Account fetches it")
	func never() {
		let group = AccountGroup(name: "Private", position: 0)
		var old = Self.account("Old card", .never)
		old.groupID = group.id
		var depot = Self.account("Depot", .onlyManually)
		depot.groupID = group.id
		let ledger = Ledger(groups: [group], accounts: [old, depot])
		#expect(ledger.refreshAccounts(.all).mapValues { $0.map(\.name) } == [Self.access: ["Depot"]])
		#expect(ledger.refreshAccounts(.group(group.id)).mapValues { $0.map(\.name) } == [Self.access: ["Depot"]])
		#expect(ledger.refreshAccounts(.account(old.id)).mapValues { $0.map(\.name) } == [Self.access: ["Old card"]])
	}

	@Test("The account settings change the interval and keep the status of a refresh")
	func settings() {
		var stored = Self.account("Giro", refreshedAt: Self.hours(1))
		var edited = Self.account("Giro", refreshedAt: nil)
		edited.refreshInterval = .onceAWeek
		stored.takeSettings(from: edited)
		#expect(stored.refreshInterval == .onceAWeek)
		#expect(stored.refreshedAt == Self.hours(1))
	}
}
