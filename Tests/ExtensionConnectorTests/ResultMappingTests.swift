import Domain
@testable import ExtensionConnector
import ExtensionHost
import Foundation
import Testing

/// The account and result tables of a script, read into the types of the app.
@Suite struct ResultMappingTests {
	let giro = ListedAccount(.object(["name": .string("Premium Account"), "accountNumber": .string("111222333444"), "currency": .string("EUR"),
		"type": .string("AccountTypeGiro")]))!
	let berlinZone = TimeZone(identifier: "Europe/Berlin")!

	func result(_ fields: [String: LuaValue], of account: ListedAccount? = nil) throws -> RefreshResult {
		try ResultMapping.refreshResult(.object(fields), of: account ?? giro, since: nil, timeZone: berlinZone)
	}

	@Test func oneAccount() {
		let account = ListedAccount(.object(["name": .string("Premium Account"), "owner": .string("Erika Mustermann"), "accountNumber": .string("111222333444"),
			"bankCode": .string("80007777"), "currency": .string("EUR"), "type": .string("AccountTypeGiro")]))
		#expect(account?.name == "Premium Account")
		#expect(account?.kind == .giro)
		#expect(account?.currency == "EUR")
		#expect(account?.remoteID == "111222333444")
	}

	@Test func missingAccountNumberIsIgnored() {
		#expect(ListedAccount(.object(["name": .string("No number")])) == nil)
	}

	@Test func portfolio() {
		#expect(ListedAccount(.object(["accountNumber": .string("D-1"), "portfolio": .boolean(true), "type": .string("AccountTypePortfolio")]))?.kind == .portfolio)
	}

	@Test func subAccountIsPartOfTheRemoteID() {
		#expect(ListedAccount(.object(["accountNumber": .string("1234"), "subAccount": .string("01")]))?.remoteID == "1234/01")
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
		let depot = ListedAccount(.object(["accountNumber": .string("D-1"), "portfolio": .boolean(true)]))!
		#expect(throws: MappingError("The securities could not be fetched.")) { try result(["balance": .integer(125)], of: depot) }
	}

	@Test func portfolioValueIsTheSumOfItsSecurities() throws {
		let depot = ListedAccount(.object(["accountNumber": .string("D-1"), "portfolio": .boolean(true)]))!
		#expect(try result(["securities": .array([.object(["name": .string("Muster AG"), "isin": .string("DE0001234567"), "quantity": .integer(10),
			"price": .number(12.50), "amount": .number(125.00)])])], of: depot) .balance == Money(minorUnits: 12500, currency: "EUR"))
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
		let depot = ListedAccount(.object(["accountNumber": .string("D-1"), "portfolio": .boolean(true)]))!
		let big = LuaValue.object(["name": .string("Muster AG"), "amount": .number(9e12)])
		#expect(throws: MappingError("The value of security 1 is out of range.")) {
			try result(["securities": .array([.object(["amount": .number(9e16)])])], of: depot)
		}
		#expect(throws: MappingError("The securities add up to more than Moneten can hold.")) {
			try result(["securities": .array(Array(repeating: big, count: 2_000))], of: depot)
		}
	}
}
