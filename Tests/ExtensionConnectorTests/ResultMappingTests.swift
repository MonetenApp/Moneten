import Domain
@testable import ExtensionConnector
import ExtensionHost
import Foundation
import Testing

/// The account and result tables of a script, read into the types of the app.
@Suite struct ResultMappingTests {
	let giro = ListedAccount(.object(["name": .string("Premium Account"), "accountNumber": .string("111222333444"), "currency": .string("EUR"),
		"type": .string("AccountTypeGiro")]))!
	let depot = ListedAccount(.object(["accountNumber": .string("D-1"), "portfolio": .boolean(true)]))!
	let berlinZone = TimeZone(identifier: "Europe/Berlin")!

	func result(_ fields: [String: LuaValue], of account: ListedAccount? = nil) throws -> RefreshResult {
		try mapped(fields, of: account).result
	}

	func mapped(_ fields: [String: LuaValue], of account: ListedAccount? = nil) throws -> (result: RefreshResult, notices: [String]) {
		try ResultMapping.refreshResult(.object(fields), of: account ?? giro, since: nil, timeZone: berlinZone)
	}

	@Test func oneAccount() {
		let account = ListedAccount(.object(["name": .string("Premium Account"), "owner": .string("Erika Mustermann"), "accountNumber": .string("111222333444"),
			"bankCode": .string("80007777"), "currency": .string("EUR"), "type": .string("AccountTypeGiro")]))
		#expect(account?.name == "Premium Account")
		#expect(account?.kind == .giro)
		#expect(account?.currency == "EUR")
		#expect(account?.remoteID == "111222333444 EUR")
	}

	@Test func missingAccountNumberIsIgnored() {
		#expect(ListedAccount(.object(["name": .string("No number")])) == nil)
	}

	@Test func portfolio() {
		#expect(ListedAccount(.object(["accountNumber": .string("D-1"), "portfolio": .boolean(true), "type": .string("AccountTypePortfolio")]))?.kind == .portfolio)
	}

	/// Only `portfolio` decides whether the results hold securities. A securities account with `portfolio=false`
	/// keeps its type and has a balance and transactions.
	@Test(arguments: [(LuaValue?.some(.boolean(false)), false), (nil, false), (.some(.boolean(true)), true), (.some(.integer(0)), true)])
	func portfolioFieldDecidesAboutSecurities(portfolio: LuaValue?, holdsSecurities: Bool) throws {
		var fields: [String: LuaValue] = ["accountNumber": .string("D-1"), "type": .string("AccountTypePortfolio")]
		fields["portfolio"] = portfolio
		let account = try #require(ListedAccount(.object(fields)))
		#expect(account.kind == .portfolio)
		#expect(account.holdsSecurities == holdsSecurities)
		let transactions = try? result(["balance": .number(100), "transactions": .array([.object(["bookingDate": .integer(1794182400), "amount": .number(100),
			"purpose": .string("Kauf")])])], of: account)
		#expect((transactions?.transactions?.rows.count == 1) == !holdsSecurities)
	}

	/// The number 0 asks for securities, as any value but `false` does, and leaves the kind and the remote ID of a giro account.
	@Test func portfolioZeroKeepsTheKind() throws {
		let account = try #require(ListedAccount(.object(["accountNumber": .string("G-1"), "type": .string("AccountTypeGiro"), "portfolio": .integer(0)])))
		#expect(account.holdsSecurities)
		#expect(account.kind == .giro)
		#expect(account.remoteID == "G-1 EUR")
	}

	@Test func subAccountIsPartOfTheRemoteID() {
		#expect(ListedAccount(.object(["accountNumber": .string("1234"), "subAccount": .string("01")]))?.remoteID == "1234/01 EUR")
	}

	@Test(arguments: [("5232 xxxx xxxx 1234", AccountKind.creditCard), ("5232123412341234", .creditCard), ("DE02120300000000202051", .giro)])
	func typeFromTheNumber(number: String, kind: AccountKind) {
		#expect(ListedAccount(.object(["accountNumber": .string(number)]))?.kind == kind)
	}

	@Test func balanceAndTransactions() throws {
		let result = try result(["balance": .number(42.00), "transactions": .array([.object(["bookingDate": .integer(1325764800), "purpose": .string("Hello World!"),
			"amount": .number(42.00)])])])
		#expect(result.balance == Money(minorUnits: 4200, currency: "EUR"))
		#expect(result.transactions?.rows.map(Row.init) == [Row(Day(year: 2012, month: 1, day: 5), 4200, "", "Hello World!", nil)])
	}

	@Test func fullTransaction() throws {
		let row = try #require(try result(["balance": .integer(0), "transactions": .array([.object([
			"name": .string("Stadtwerke Musterstadt"), "accountNumber": .string("DE02120300000000202051"), "bankCode": .string("BYLADEM1001"), "amount": .number(-89.00),
			"currency": .string("EUR"), "bookingDate": .integer(1794182400), "purpose": .string("Abschlag\nNovember"), "endToEndReference": .string("E2E-1"),
			"transactionId": .string("T-1")])])]).transactions?.rows.first)
		#expect(row.amountMinor == -8900)
		#expect(row.name == "Stadtwerke Musterstadt")
		#expect(row.purpose == "Abschlag\nNovember")
		#expect(row.bookingDate == Day(year: 2026, month: 11, day: 9))
		#expect(row.counterpartyIBAN == "DE02120300000000202051")
		#expect(row.counterpartyBIC == "BYLADEM1001")
		#expect(row.endToEndReference == "E2E-1")
		#expect(row.sourceID == "T-1")
	}

	@Test func missingAmount() {
		#expect(throws: MappingError("Transaction 2 has no amount.")) {
			try result(["balance": .integer(0), "transactions": .array([.object(["bookingDate": .integer(1794182400), "amount": .integer(1)]),
				.object(["bookingDate": .integer(1794182400)])])])
		}
	}

	@Test func noTransactionsField() {
		#expect(throws: MappingError("The transactions could not be fetched.")) { try result(["balance": .number(10.00)]) }
	}

	@Test func noBalance() {
		#expect(throws: MappingError("The balance could not be fetched.")) { try result(["transactions": .array([])]) }
	}

	@Test func balanceOfTheAccountCurrencyFromSeveral() throws {
		#expect(try result(["balances": .array([.array([.number(100.00), .string("USD")]), .array([.number(25.50), .string("EUR")])]),
			"transactions": .array([])]).balance == Money(minorUnits: 2550, currency: "EUR"))
	}

	@Test func cardAuthorizationIsPendingWithoutItsIdentifier() throws {
		let row = try #require(try result(["balance": .integer(0), "transactions": .array([.object(["bookingDate": .integer(1794182400), "amount": .number(-19.99),
			"booked": .boolean(false), "transactionId": .string("P-1")])])]).transactions?.rows.first)
		#expect(row.isPending)
		#expect(row.sourceID == nil)
	}

	@Test func portfolioWithoutSecurities() {
		#expect(throws: MappingError("The securities could not be fetched.")) { try result(["balance": .integer(125)], of: depot) }
	}

	@Test func portfolioValueIsTheSumOfItsSecurities() throws {
		let shares = try result(["securities": .array([.object(["name": .string("Muster AG"), "isin": .string("DE0001234567"), "securityNumber": .string("123456"),
			"quantity": .integer(10), "price": .number(12.50), "purchasePrice": .number(10.00), "amount": .number(125.00), "market": .string("Xetra"),
			"tradeTimestamp": .integer(1794182400)])])], of: depot)
		#expect(shares.balance == Money(minorUnits: 12500, currency: "EUR"))
		#expect(shares.isPortfolio)
		let first = try #require(shares.holdings?.first)
		#expect(shares.holdings == [Holding(id: first.id, accountID: first.accountID,
			security: Security(name: "Muster AG", isin: "DE0001234567", securityNumber: "123456"), quantity: 10,
			quote: Quote(amount: 12.5, currency: "EUR", day: Day(year: 2026, month: 11, day: 9)), marketValue: Money(minorUnits: 12500, currency: "EUR"),
			purchasePrice: Quote(amount: 10, currency: "EUR"))])
	}

	/// Most published crypto and peer-to-peer extensions give the quantity and the price and leave the value to the app.
	@Test func securityWithoutAmountIsWorthItsQuantityTimesItsPrice() throws {
		let coins = try result(["securities": .array([.object(["name": .string("Bitcoin"), "quantity": .string("0.5"), "price": .number(60000)]),
			.object(["name": .string("Fonds"), "quantity": .integer(10), "price": .number(99.99)])])], of: depot)
		#expect(coins.balance == Money(minorUnits: 3_099_990, currency: "EUR"))
		#expect(coins.holdings?.map { $0.value(in: "EUR") } == [Money(minorUnits: 3_000_000, currency: "EUR"), Money(minorUnits: 99_990, currency: "EUR")])
	}

	@Test func priceInAnotherCurrencyConvertsWithTheCurrentRate() throws {
		let shares = try result(["securities": .array([.object(["name": .string("Muster Inc."), "quantity": .integer(10), "price": .number(110),
			"currencyOfPrice": .string("USD"), "exchangeRateOfPrice": .number(1.10)])])], of: depot)
		#expect(shares.balance == Money(minorUnits: 100_000, currency: "EUR"))
		#expect(shares.holdings?.first?.quote == Quote(amount: 110, currency: "USD"))
	}

	/// A script that knows no rate leaves out `amount`; the position keeps its value in the currency of its price.
	/// The account still refreshed, so the message is a notice and no failure.
	@Test func priceInAnotherCurrencyWithoutARateAddsNothingToTheBalance() throws {
		let (tokens, notices) = try mapped(["securities": .array([.object(["name": .string("Token A"), "quantity": .integer(10), "price": .number(2), "amount": .integer(20)]),
			.object(["name": .string("Token B"), "quantity": .integer(10), "price": .number(110), "currencyOfPrice": .string("USDC")])])], of: depot)
		#expect(tokens.balance == Money(minorUnits: 2000, currency: "EUR"))
		#expect(tokens.holdings?.last?.value(in: "EUR") == Money(minorUnits: 110_000, currency: "USDC"))
		#expect(tokens.transactionFailure == nil)
		#expect(notices == ["The balance leaves out Token B, because its price is in USDC and the extension gives no exchange rate."])
	}

	/// The gain compares the value at today's rate with the cost at the rate of the day of the purchase.
	@Test func purchasePriceConvertsWithTheRateOfThePurchase() throws {
		let shares = try result(["securities": .array([.object(["name": .string("Muster Inc."), "quantity": .integer(10), "price": .number(110),
			"currencyOfPrice": .string("USD"), "exchangeRateOfPrice": .number(1.1), "purchasePrice": .integer(100), "currencyOfPurchasePrice": .string("USD"),
			"exchangeRateOfPurchasePrice": .number(1.25)])])], of: depot)
		let holding = try #require(shares.holdings?.first)
		#expect(holding.purchasePrice == Quote(amount: 80, currency: "EUR"))
		#expect(holding.gain(in: "EUR")?.amount == Money(minorUnits: 20_000, currency: "EUR"))
	}

	@Test func purchasePriceOutOfRange() {
		#expect(throws: MappingError("The value of security 1 at its purchase price is out of range.")) {
			try result(["securities": .array([.object(["quantity": .integer(1), "amount": .integer(5), "purchasePrice": .number(1e17)])])], of: depot)
		}
	}

	@Test func nominalAmountIsValuedAtAPercentage() throws {
		let bond = try result(["securities": .array([.object(["name": .string("Anleihe Musterland"), "quantity": .integer(5000),
			"currencyOfQuantity": .string("EUR"), "price": .number(98.5), "purchasePrice": .number(97)])])], of: depot)
		#expect(bond.balance == Money(minorUnits: 492_500, currency: "EUR"))
		#expect(bond.holdings?.first?.isNominal == true)
		#expect(bond.holdings?.first?.quote == Quote(amount: 98.5, currency: nil))
	}

	/// The rate of a nominal amount links the account currency with `currencyOfQuantity`, as the price is a percentage.
	@Test func nominalAmountInAnotherCurrencyConvertsWithTheCurrentRate() throws {
		let bond = try result(["securities": .array([.object(["name": .string("Anleihe Musterstaat"), "quantity": .integer(5000),
			"currencyOfQuantity": .string("USD"), "price": .number(98.5), "exchangeRateOfPrice": .number(1.25)])])], of: depot)
		#expect(bond.balance == Money(minorUnits: 394_000, currency: "EUR"))
		#expect(bond.holdings?.first?.exchangeRate == ExchangeRate(base: "EUR", quoted: "USD", rate: 1.25))
	}

	/// A bond bought at 100 % when 1 USD cost 1 EUR is worth less at 100 % when 1 EUR costs 1.25 USD.
	@Test func nominalPurchaseConvertsWithTheRateOfThePurchase() throws {
		let bond = try result(["securities": .array([.object(["name": .string("Anleihe Musterstaat"), "quantity": .integer(5000),
			"currencyOfQuantity": .string("USD"), "price": .integer(100), "exchangeRateOfPrice": .number(1.25), "purchasePrice": .integer(100),
			"exchangeRateOfPurchasePrice": .integer(1)])])], of: depot)
		let holding = try #require(bond.holdings?.first)
		#expect(holding.value(in: "EUR") == Money(minorUnits: 400_000, currency: "EUR"))
		#expect(holding.gain(in: "EUR")?.amount == Money(minorUnits: -100_000, currency: "EUR"))
	}

	/// Older scripts set `currency = nil` or the account currency on a security, a field that the API no longer
	/// names, so it never makes the quantity a nominal amount.
	@Test func olderCurrencyFieldKeepsUnits() throws {
		let coins = try result(["securities": .array([.object(["quantity": .integer(2), "price": .integer(3), "currency": .string("EUR")])])], of: depot)
		#expect(coins.balance == Money(minorUnits: 600, currency: "EUR"))
		#expect(coins.holdings?.first?.isNominal == false)
	}

	@Test func securityWithoutAmountAndPriceHasNoValue() throws {
		let coins = try result(["securities": .array([.object(["name": .string("Bitcoin"), "quantity": .integer(1)])])], of: depot)
		#expect(coins.balance == Money(minorUnits: 0, currency: "EUR"))
		#expect(coins.holdings?.map(\.security.name) == ["Bitcoin"])
		#expect(coins.holdings?.first?.value(in: "EUR") == nil)
	}

	/// A script may index its securities by name in the same table, and only the numbered ones are the list.
	@Test func securitiesKeptAlsoUnderTheirNames() throws {
		let share = LuaValue.object(["name": .string("Example Corp"), "quantity": .integer(4), "price": .integer(25)])
		let shares = try result(["securities": .object(["Example Corp": share, "1": share])], of: depot)
		#expect(shares.holdings?.count == 1)
		#expect(shares.balance == Money(minorUnits: 10_000, currency: "EUR"))
	}

	@Test func quantityThatIsNotANumber() {
		#expect(throws: MappingError("The quantity of security 1 is not a number.")) {
			try result(["securities": .array([.object(["quantity": .string("1,5"), "price": .integer(3)])])], of: depot)
		}
	}

	@Test func knownTransactionsLeaveOutPendingAndRepeatedIdentifiers() {
		let account = UUID()
		let rows = [
			Transaction(accountID: account, bookingDate: Day(year: 2026, month: 11, day: 3), amountMinor: -8900, name: "Stadtwerke Musterstadt",
				purpose: "Abschlag", counterpartyIBAN: "DE02120300000000202051", sourceID: "T-100"),
			Transaction(accountID: account, bookingDate: Day(year: 2026, month: 11, day: 4), amountMinor: -500, name: "Café", isPending: true, sourceID: "T-200"),
			Transaction(accountID: account, bookingDate: Day(year: 2026, month: 11, day: 5), amountMinor: 100, name: "A", sourceID: "T-300"),
			Transaction(accountID: account, bookingDate: Day(year: 2026, month: 11, day: 6), amountMinor: 100, name: "B", sourceID: "T-300"),
			Transaction(accountID: account, bookingDate: Day(year: 2026, month: 11, day: 7), amountMinor: 100, name: "C", sourceID: ""),
		]
		#expect(ResultMapping.knownTransactions(rows, timeZone: berlinZone) == ["T-100": .object(["name": .string("Stadtwerke Musterstadt"),
			"purpose": .string("Abschlag"), "currency": .string("EUR"), "amount": .number(-89.0), "bookingDate": .integer(1793660400), "booked": .boolean(true),
			"accountNumber": .string("DE02120300000000202051")])])
	}

	@Test(arguments: ["12,50", "1.234,56", "12abc", "-5 EUR", "", "0x10", "nan", "inf"])
	func amountThatIsNotWhollyANumber(text: String) {
		#expect(throws: MappingError("The amount of transaction 1 is not a number.")) {
			try result(["balance": .integer(0), "transactions": .array([.object(["bookingDate": .integer(1794182400), "amount": .string(text)])])])
		}
	}

	@Test(arguments: [("12.50", Int64(1250)), (" -5 ", -500), ("1e3", 100_000), (".5", 50)])
	func amountAsNumericText(text: String, minor: Int64) throws {
		#expect(try result(["balance": .integer(0), "transactions": .array([.object(["bookingDate": .integer(1794182400), "amount": .string(text)])])])
			.transactions?.rows.first?.amountMinor == minor)
	}

	@Test func balanceThatIsNotANumber() {
		#expect(throws: MappingError("The balance is not a number.")) { try result(["balance": .string("1.234,56"), "transactions": .array([])]) }
	}

	@Test(arguments: [LuaValue.number(1e20), .number(-1e20), .integer(Int64.max)])
	func balanceOutOfRange(balance: LuaValue) {
		#expect(throws: MappingError("The balance is out of range.")) { try result(["balance": balance, "transactions": .array([])]) }
	}

	@Test func amountOutOfRange() {
		#expect(throws: MappingError("The amount of transaction 1 is out of range.")) {
			try result(["balance": .integer(0), "transactions": .array([.object(["bookingDate": .integer(1794182400), "amount": .number(9e16)])])])
		}
	}

	@Test func bookingDateOutOfRange() {
		#expect(throws: MappingError("The booking date of transaction 1 is not a date.")) {
			try result(["balance": .integer(0), "transactions": .array([.object(["bookingDate": .number(1e300), "amount": .integer(1)])])])
		}
	}

	@Test func securitiesThatAddUpBeyondTheRange() {
		let big = LuaValue.object(["name": .string("Muster AG"), "amount": .number(9e12)])
		#expect(throws: MappingError("The value of security 1 is out of range.")) {
			try result(["securities": .array([.object(["amount": .number(9e16)])])], of: depot)
		}
		#expect(throws: MappingError("The securities add up to more than Moneten can hold.")) {
			try result(["securities": .array(Array(repeating: big, count: 2_000))], of: depot)
		}
	}
}
