import Foundation
import Testing
@testable import Domain

/// Sums of amounts that an older version stored beyond `Money.maxMinorUnits` (issue #324). Each sum holds at the
/// largest amount instead of stopping the app, which a CSV account would otherwise do at every unlock.
@Suite("Sums beyond the range of amounts")
struct AmountOverflowTests {
	/// 50.000.000.000.000.000,00 €. Two of them add up to more than an `Int64` holds.
	static let huge: Int64 = 5_000_000_000_000_000_000
	static let day = Day(year: 2026, month: 11, day: 2)

	let group = AccountGroup(name: "Private", position: 0)
	let food = Domain.Category(position: 0, name: "Food")
	var giro: Account { Account(id: Self.giroID, groupID: group.id, position: 0, name: "Giro", kind: .giro, source: .offline) }
	static let giroID = UUID()

	func rows(_ amounts: [Int64], isNew: Bool = false) -> [Transaction] {
		amounts.enumerated().map { i, amount in
			Transaction(accountID: Self.giroID, bookingDate: Self.day.adding(days: i), amountMinor: amount, name: "Musterfirma GmbH",
				categoryID: food.id, isNew: isNew)
		}
	}

	func ledger(_ amounts: [Int64], account: Account? = nil) -> Ledger {
		Ledger(groups: [group], accounts: [account ?? giro], categories: [food], transactions: rows(amounts))
	}

	@Test("The balance and the sum of the group hold at the largest amount")
	func sidebarBalance() {
		let l = ledger([Self.huge, Self.huge])
		#expect(l.balance(of: giro) == Money(minorUnits: .max, currency: "EUR"))
		#expect(l.sum(ofGroup: group.id).amounts == [Money(minorUnits: .max, currency: "EUR")])
		#expect(ledger([-Self.huge, -Self.huge]).balance(of: giro) == Money(minorUnits: -.max, currency: "EUR"))
	}

	@Test("A stored amount of Int64.min sums to the negative bound, so its absolute value does not trap")
	func smallestInt64() {
		#expect(ledger([.min]).balance(of: giro).minorUnits == -.max)
		#expect(MoneySums(of: rows([.min])).amounts.map(\.minorUnits) == [-.max])
	}

	@Test("The status line and the sidebar amounts of categories hold at the largest amount")
	func listAndCategorySums() {
		let l = ledger([Self.huge, Self.huge])
		#expect(MoneySums(of: l.transactions).amounts == [Money(minorUnits: .max, currency: "EUR")])
		#expect(l.sidebarAmounts(today: Self.day.adding(days: 5))[food.id] == Money(minorUnits: .max, currency: "EUR"))
	}

	@Test("The charts hold at the largest amount")
	func charts() {
		let h = Self.huge
		let l = ledger([h, h, -h, -h, -h, -h])
		let range = DayRange(start: Self.day, end: Self.day.adding(days: 5))
		#expect(l.dailyBalances(accountIDs: [giro.id]).map(\.minorUnits) == [h, .max, .max - h, .max - h - h, .max - h - h - h, -.max])
		#expect(l.balanceBars(accountIDs: [giro.id], range: range).map(\.minorUnits).last == -.max)
		#expect(l.monthlyAverageBalances(accountIDs: [giro.id], range: range).count == 1)
		let sums = l.periodSums(of: l.transactions, period: .month)
		#expect(sums.map(\.deposits) == [.max] && sums.map(\.withdrawals) == [-.max] && sums.map(\.total) == [0])
		#expect(l.categoryTotals(of: ledger([Self.huge, Self.huge]).transactions).map(\.minorUnits) == [.max])
	}

	@Test("The monthly average of balances near the bound is exact")
	func monthlyAverage() {
		let row = Transaction(accountID: Self.giroID, bookingDate: Day(year: 2026, month: 10, day: 2), amountMinor: Self.huge, name: "Musterfirma GmbH")
		let l = Ledger(groups: [group], accounts: [giro], transactions: [row])
		let october = DayRange(start: Day(year: 2026, month: 10, day: 1), end: Day(year: 2026, month: 10, day: 31))
		let averages = l.monthlyAverageBalances(accountIDs: [giro.id], range: october, calendar: Calendar(identifier: .gregorian))
		// One day at 0 and 30 days at 50.000.000.000.000.000,00 €.
		#expect(averages.map(\.minorUnits) == [Int64(Int128(Self.huge) * 30 / 31)])
	}

	@Test("The notice of new transactions keeps the sign of a sum beyond the range")
	func notice() throws {
		let stored = rows([Self.huge, Self.huge], isNew: true)
		let notice = try #require(NewTransactionsNotice(stored: stored, ledger: nil))
		#expect(notice.tone == .positive)
	}

	@Test("The initial balance that meets a bank balance and the calibration hold at the bounds")
	func bankBalance() {
		var account = giro
		account.bankBalanceMinor = -Self.huge
		account.bankBalanceDate = Date()
		let booked = rows([Self.huge, Self.huge])
		#expect(account.initialBalanceMeetingBankBalance(of: booked) == -.max)
		var set = account
		set.source = .bank
		set.initialBalanceIsSet = true
		set.initialBalanceMinor = Self.huge
		let l = ledger([Self.huge], account: set)
		#expect(l.proposedCalibration(of: set, today: .today(), refresh: .idle) != nil)
		#expect(l.calibratedInitialBalance(of: set, balanceToday: -Self.huge, today: .today()) == -.max)
	}
}

@Suite("Amount limit")
struct AmountLimitTests {
	@Test("One amount holds at most 10.000.000.000,00 €, and nine million such amounts still add up")
	func limit() throws {
		func money(_ text: String, _ currency: String = "EUR") throws -> Money? { Money(limited: try #require(Decimal(string: text)), currency: currency) }
		#expect(try money("10000000000.00")?.minorUnits == 1_000_000_000_000)
		#expect(try money("-10000000000.004")?.minorUnits == -1_000_000_000_000)
		#expect(try money("10000000000.01") == nil)
		#expect(try money("-10000000000.006") == nil)
		#expect(try money("1000000000000", "JPY")?.minorUnits == 1_000_000_000_000)
		#expect(try money("1000000000.000", "KWD")?.minorUnits == 1_000_000_000_000)
		#expect(try money("1e40") == nil)
		#expect(Money(limited: .nan, currency: "EUR") == nil)
		#expect(!Money.maxMinorUnits.multipliedReportingOverflow(by: 9_000_000).overflow)
	}
}
