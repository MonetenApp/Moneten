import Foundation
import Testing
@testable import Domain

/// Sums of amounts that an older version stored beyond `Money.maxMinorUnits` (issue #324). Each sum adds up exactly
/// and holds at the largest amount only at the end, instead of stopping the app, which a CSV account would otherwise
/// do at every unlock.
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

	@Test("Rows that cancel out give the same exact sum in every order", arguments: [
		[AmountOverflowTests.huge, AmountOverflowTests.huge, -AmountOverflowTests.huge, -AmountOverflowTests.huge, 100],
		[AmountOverflowTests.huge, -AmountOverflowTests.huge, AmountOverflowTests.huge, -AmountOverflowTests.huge, 100],
		[-AmountOverflowTests.huge, -AmountOverflowTests.huge, AmountOverflowTests.huge, AmountOverflowTests.huge, 100],
	])
	func orderIndependence(amounts: [Int64]) {
		let l = ledger(amounts)
		let euros = [Money(minorUnits: 100, currency: "EUR")]
		#expect(l.balance(of: giro).minorUnits == 100)
		#expect(l.sum(ofGroup: group.id).amounts == euros)
		#expect(MoneySums(of: l.transactions).amounts == euros)
		#expect(l.sidebarAmounts(today: Self.day.adding(days: 5))[food.id]?.minorUnits == 100)
		#expect(l.categoryTotals(of: l.transactions).map(\.minorUnits) == [100])
		#expect(l.dailyBalances(accountIDs: [giro.id]).last?.balance == 100)
		var sums = MoneySums()
		for t in l.transactions { sums.add(t.amount) }
		#expect(sums.amounts == euros)
	}

	@Test("The sum of a group adds the exact balances of its accounts, so balances beyond the range cancel out")
	func groupSumOfExactBalances() {
		let savings = Account(groupID: group.id, position: 1, name: "Tagesgeld", kind: .savings, source: .offline, initialBalanceMinor: -Self.huge)
		let l = Ledger(groups: [group], accounts: [giro, savings], categories: [food], transactions: rows([Self.huge, Self.huge]))
		#expect(l.balance(of: giro).minorUnits == .max)
		#expect(l.sum(ofGroup: group.id).amounts == [Money(minorUnits: Self.huge, currency: "EUR")])
	}

	@Test("The total of a period adds its exact deposits and withdrawals")
	func periodTotal() {
		let h = Self.huge
		let l = ledger([h, h, -h])
		#expect(l.periodSums(of: l.transactions, period: .month).map(\.total) == [h])
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

	@Test("The charts add up exactly and hold at the largest amount")
	func charts() {
		let h = Self.huge
		let l = ledger([h, h, -h, -h, -h, -h])
		let range = DayRange(start: Self.day, end: Self.day.adding(days: 5))
		#expect(l.dailyBalances(accountIDs: [giro.id]).map(\.balance) == [1, 2, 1, 0, -1, -2].map { $0 * Int128(h) })
		#expect(l.balanceBars(accountIDs: [giro.id], range: range).map(\.minorUnits) == [h, .max, h, 0, -h, -.max])
		#expect(l.monthlyAverageBalances(accountIDs: [giro.id], range: range).count == 1)
		let sums = l.periodSums(of: l.transactions, period: .month)
		#expect(sums.map(\.deposits) == [Int128(h) * 2] && sums.map(\.withdrawals) == [Int128(h) * -4] && sums.map(\.total) == [-.max])
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

	@Test("The monthly average adds the exact balances of the days, also where a balance is beyond the range")
	func monthlyAverageOfExactBalances() {
		// 15 days at 100.000.000.000.000.000,00 € and 16 days at 0 average to less than the largest amount.
		let october = DayRange(start: Day(year: 2026, month: 10, day: 1), end: Day(year: 2026, month: 10, day: 31))
		let rows = [(1, Self.huge), (1, Self.huge), (16, -Self.huge), (16, -Self.huge)].map { day, amount in
			Transaction(accountID: Self.giroID, bookingDate: Day(year: 2026, month: 10, day: day), amountMinor: amount, name: "Musterfirma GmbH")
		}
		let l = Ledger(groups: [group], accounts: [giro], transactions: rows)
		let averages = l.monthlyAverageBalances(accountIDs: [giro.id], range: october, calendar: Calendar(identifier: .gregorian))
		#expect(averages.map(\.minorUnits) == [Int64(Int128(Self.huge) * 2 * 15 / 31)])
	}

	@Test("The notice of new transactions keeps the sign of a sum beyond the range")
	func notice() throws {
		let stored = rows([Self.huge, Self.huge], isNew: true)
		let notice = try #require(NewTransactionsNotice(stored: stored, ledger: nil))
		#expect(notice.tone == .positive)
	}

	@Test("The initial balance that meets a bank balance and the calibration add up exactly and hold at the bounds")
	func bankBalance() throws {
		var account = giro
		account.bankBalanceMinor = -Self.huge
		account.bankBalanceDate = Date()
		#expect(account.initialBalanceMeetingBankBalance(of: rows([Self.huge, Self.huge])) == -.max)
		#expect(account.initialBalanceMeetingBankBalance(of: rows([Self.huge, Self.huge, -Self.huge, -Self.huge])) == -Self.huge)
		var set = account
		set.source = .bank
		set.initialBalanceIsSet = true
		set.initialBalanceMinor = Self.huge
		let l = ledger([Self.huge], account: set)
		// Booked rows of 50.000.000.000.000.000,00 € miss the bank balance of -50.000.000.000.000.000,00 € by three times that amount.
		let proposal = try #require(l.proposedCalibration(of: set, today: .today(), refresh: .idle))
		#expect(proposal.difference.minorUnits == -.max)
		#expect(proposal.balanceToday.minorUnits == -Self.huge)
		#expect(l.calibratedInitialBalance(of: set, balanceToday: -Self.huge, today: .today()) == -.max)
		// The initial balance plus the wanted balance is beyond the range, and less the computed balance it is not.
		#expect(ledger([], account: set).calibratedInitialBalance(of: set, balanceToday: Self.huge, today: .today()) == Self.huge)
	}
}

@Suite("Amount limit")
struct AmountLimitTests {
	@Test("One amount holds at most 10.000.000.000.000,00 €, in the decimal places of its currency")
	func limit() throws {
		func money(_ text: String, _ currency: String = "EUR") throws -> Money? { Money(fitting: try #require(Decimal(string: text)), currency: currency) }
		#expect(try money("10000000000000.00")?.minorUnits == 1_000_000_000_000_000)
		#expect(try money("-10000000000000.004")?.minorUnits == -1_000_000_000_000_000)
		#expect(try money("10000000000000.01") == nil)
		#expect(try money("-10000000000000.006") == nil)
		#expect(try money("1000000000000000", "JPY")?.minorUnits == 1_000_000_000_000_000)
		#expect(try money("1000000000000.000", "KWD")?.minorUnits == 1_000_000_000_000_000)
		// A typed amount at the bound of Int64 is refused, as in "Edit Transaction...".
		#expect(try money("92233720368547758.07") == nil)
		#expect(try money("1e40") == nil)
		#expect(Money(fitting: .nan, currency: "EUR") == nil)
	}

	@Test("A position whose quantity times its quote is beyond the limit has no value and no gain, and does not fit")
	func holding() {
		let absurd = Holding(accountID: UUID(), security: Security(name: "Muster AG"), quantity: 10_000_000_000,
			quote: Quote(amount: 10_000_000_000, currency: "EUR"), purchasePrice: Quote(amount: 1, currency: "EUR"))
		#expect(absurd.value(in: "EUR") == nil)
		#expect(absurd.gain(in: "EUR") == nil)
		#expect(!absurd.amountsFit(in: "EUR"))
		var bought = absurd
		bought.quote = Quote(amount: 1, currency: "EUR")
		bought.purchasePrice = Quote(amount: 10_000_000_000, currency: "EUR")
		#expect(bought.value(in: "EUR")?.minorUnits == 1_000_000_000_000)
		#expect(bought.gain(in: "EUR") == nil)
		#expect(!bought.amountsFit(in: "EUR"))
		let normal = Holding(accountID: UUID(), security: Security(name: "Muster AG"), quantity: 12,
			quote: Quote(amount: Decimal(string: "101.50")!, currency: "EUR"), purchasePrice: Quote(amount: 100, currency: "EUR"))
		#expect(normal.value(in: "EUR")?.minorUnits == 121_800)
		#expect(normal.gain(in: "EUR")?.amount.minorUnits == 1_800)
		#expect(normal.amountsFit(in: "EUR"))
	}
}
