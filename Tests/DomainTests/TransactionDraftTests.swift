import Domain
import Foundation
import Testing

@Suite("The window for a manual transaction")
struct TransactionDraftTests {
	let wallet = Account(position: 0, name: "Wallet", kind: .cash, source: .offline)
	let business = Account(position: 1, name: "Business", kind: .giro, source: .offline)
	let groceries = Domain.Category(position: 0, name: "Groceries")
	let leisure = Domain.Category(position: 1, name: "Leisure")
	let germany = Locale(identifier: "de_DE")
	let unitedStates = Locale(identifier: "en_US")

	func draft(amount: String) -> TransactionDraft {
		var d = TransactionDraft()
		d.amount = amount
		return d
	}

	@Test("The amount keeps its sign: a leading minus goes out, a number without a sign comes in")
	func signedAmount() {
		#expect(draft(amount: "-4,80").amountMinor(in: "EUR", region: .comma) == .success(-480))
		#expect(draft(amount: "50,00").amountMinor(in: "EUR", region: .comma) == .success(5_000))
		#expect(draft(amount: "+12").amountMinor(in: "EUR", region: .comma) == .success(1_200))
		#expect(draft(amount: "-1.250,00 €").amountMinor(in: "EUR", region: .comma) == .success(-125_000))
	}

	@Test("An amount of zero, text that is not a number, an empty field, and an amount beyond the limit are refused")
	func refusedAmounts() {
		#expect(draft(amount: "0,00").amountMinor(in: "EUR", region: .comma) == .failure(.zero))
		#expect(draft(amount: "-0,00").amountMinor(in: "EUR", region: .comma) == .failure(.zero))
		#expect(draft(amount: "vier").amountMinor(in: "EUR", region: .comma) == .failure(.notANumber))
		#expect(draft(amount: "1,2,3").amountMinor(in: "EUR", region: .comma) == .failure(.notANumber))
		#expect(draft(amount: "12 $").amountMinor(in: "EUR", region: .comma) == .failure(.notANumber))
		#expect(draft(amount: " ").amountMinor(in: "EUR", region: .comma) == .failure(.missing))
		#expect(draft(amount: "100000000000000000000").amountMinor(in: "EUR", region: .comma) == .failure(.tooLarge))
		#expect(draft(amount: "-92233720368547758,08").amountMinor(in: "EUR", region: .comma) == .failure(.tooLarge))
		// One amount holds at most 10.000.000.000.000,00 € (issue #324), so the sums of the app cannot overflow.
		#expect(draft(amount: "92.233.720.368.547.758,07").amountMinor(in: "EUR", region: .comma) == .failure(.tooLarge))
		#expect(draft(amount: "10000000000000,01").amountMinor(in: "EUR", region: .comma) == .failure(.tooLarge))
		#expect(draft(amount: "-10000000000000,00").amountMinor(in: "EUR", region: .comma) == .success(-1_000_000_000_000_000))
		#expect(draft(amount: "10000000000000000").amountMinor(in: "JPY", region: .comma) == .failure(.tooLarge))
		#expect(AmountProblem.zero.message == "The amount should not be zero.")
	}

	@Test("An amount typed in the format of the region Germany is read, and one that has no reading is refused")
	func germanEntry() {
		let germany = DecimalMark(region: Locale(identifier: "de_DE"))
		#expect(draft(amount: "1.234,5").amountMinor(in: "EUR", region: germany) == .success(123_450))
		#expect(draft(amount: "12,3,4").amountMinor(in: "EUR", region: germany) == .failure(.notANumber))
	}

	@Test("A row from a source keeps an amount of zero when the user edits it, and a manual one refuses it")
	func zeroFromSource() {
		#expect(draft(amount: "0,00").amountMinor(in: "EUR", region: .comma, allowsZero: true) == .success(0))
		#expect(draft(amount: "vier").amountMinor(in: "EUR", region: .comma, allowsZero: true) == .failure(.notANumber))
		#expect(draft(amount: "0,00").amountMinor(in: "EUR", region: .comma, allowsZero: false) == .failure(.zero))
	}

	@Test("A reading with more decimal places than the currency has does not count, and the decimal mark of the region decides a tie", arguments: [
		("1.234", "EUR", DecimalMark.comma, Int64(123_400)), ("1.234", "EUR", .point, 123_400),
		("1,200", "JPY", .comma, 1_200), ("1.200", "JPY", .point, 1_200),
		("12,345", "KWD", .comma, 12_345), ("12,345", "KWD", .point, 12_345_000),
		("1.234", "KWD", .comma, 1_234_000), ("1.234", "KWD", .point, 1_234),
		("0,007", "KWD", .point, 7), ("-1,2340", "KWD", .point, -1_234),
		("12.50 $", "USD", .comma, 1_250), ("USD 12.50", "USD", .comma, 1_250), ("-12,50 €", "EUR", .point, -1_250), ("12,5", "EUR", .point, 1_250),
		("1.234,56", "EUR", .point, 123_456), ("1,234.56", "EUR", .comma, 123_456),
	])
	func amountReadings(text: String, currency: String, region: DecimalMark, minor: Int64) {
		#expect(draft(amount: text).amountMinor(in: currency, region: region) == .success(minor))
	}

	@Test("An amount with more decimal places than its currency has is refused and never rounds", arguments: [
		("4,8051", "EUR"), ("4.8051", "EUR"), ("0,007", "EUR"), ("12,5", "JPY"), ("1,2345", "KWD"),
	])
	func tooManyDecimals(text: String, currency: String) {
		for region in DecimalMark.allCases {
			#expect(draft(amount: text).amountMinor(in: currency, region: region) == .failure(.tooManyDecimals))
		}
		#expect(AmountProblem.tooManyDecimals.message == "The amount has more decimal places than its currency.")
	}

	@Test("The region names the decimal mark that wins a tie")
	func regionMark() {
		#expect(DecimalMark(region: Locale(identifier: "de_DE")) == .comma)
		#expect(DecimalMark(region: Locale(identifier: "en_US")) == .point)
	}

	@Test("A selected transaction fills the name, the amount with its sign in the decimal mark of the region, the purpose, and the category")
	func template() {
		let kiosk = Transaction(accountID: wallet.id, bookingDate: Day(year: 2026, month: 10, day: 2), amountMinor: -1_200, name: "Kiosk am Markt",
			purpose: "Zeitung", comment: "Sonntag", categoryID: leisure.id, categorizedBy: .rule)
		let d = TransactionDraft(template: kiosk, locale: germany)
		#expect(d.name == "Kiosk am Markt")
		#expect(d.amount == "-12,00")
		#expect(TransactionDraft(template: kiosk, locale: unitedStates).amount == "-12.00")
		#expect(d.amountMinor(in: "EUR", region: .comma) == .success(-1_200))
		#expect(d.amountMinor(in: "EUR", region: .point) == .success(-1_200))
		#expect(d.purpose == "Zeitung")
		#expect(d.categoryID == leisure.id)
	}

	@Test("Add Transaction starts from the one selected row of the account, and a row in another currency gives no amount")
	func templateChoice() throws {
		let kiosk = Transaction(accountID: wallet.id, bookingDate: Day(year: 2026, month: 10, day: 2), amountMinor: -1_200, name: "Kiosk am Markt",
			purpose: "Zeitung", categoryID: leisure.id, categorizedBy: .manual)
		var dollars = kiosk
		dollars.id = UUID()
		dollars.currency = "USD"
		let paper = Transaction(accountID: business.id, bookingDate: Day(year: 2026, month: 10, day: 3), amountMinor: -500, name: "Papierhaus Beispiel")
		let split = Transaction(accountID: wallet.id, bookingDate: Day(year: 2026, month: 10, day: 4), amountMinor: -3_000, name: "Markt", purpose: "Einkauf")
		let parts = [SplitPart(transactionID: split.id, position: 0, amountMinor: -1_000, categoryID: groceries.id), SplitPart(transactionID: split.id, position: 1, amountMinor: -2_000)]
		let l = Ledger(accounts: [wallet, business], categories: [groceries, leisure], transactions: [kiosk, dollars, paper, split], parts: parts)

		#expect(l.newTransactionDraft(in: wallet, selection: [kiosk.id], locale: germany) == TransactionDraft(template: kiosk, locale: germany))
		#expect(l.newTransactionDraft(in: wallet, selection: [kiosk.id], locale: unitedStates).amount == "-12.00")
		let foreign = l.newTransactionDraft(in: wallet, selection: [dollars.id], locale: germany)
		#expect(foreign.name == "Kiosk am Markt" && foreign.purpose == "Zeitung" && foreign.categoryID == leisure.id)
		#expect(foreign.amount == "")
		#expect(l.newTransactionDraft(in: wallet, selection: [paper.id], locale: germany) == TransactionDraft())
		#expect(l.newTransactionDraft(in: wallet, selection: [kiosk.id, dollars.id], locale: germany) == TransactionDraft())
		#expect(l.newTransactionDraft(in: wallet, selection: [], locale: germany) == TransactionDraft())
		let part = l.newTransactionDraft(in: wallet, selection: [parts[0].id], locale: germany)
		#expect(part.name == "Markt" && part.amount == "-10,00" && part.categoryID == groceries.id)
	}

	@Test("The window shows an amount with every decimal place of its currency in the decimal mark of the region, and the text reads back to the same amount in both regions")
	func amountText() {
		func shown(_ minor: Int64, _ currency: String, _ locale: Locale) -> String {
			TransactionDraft(template: Transaction(accountID: wallet.id, bookingDate: Day(year: 2026, month: 10, day: 2), amountMinor: minor, currency: currency, name: ""), locale: locale).amount
		}
		#expect(shown(5_000, "EUR", germany) == "50,00")
		#expect(shown(-5, "EUR", germany) == "-0,05")
		#expect(shown(-123_456, "EUR", germany) == "-1234,56")
		#expect(shown(1_200, "JPY", germany) == "1200")
		#expect(shown(-1_234, "KWD", germany) == "-1,2340")
		#expect(shown(5_000, "EUR", unitedStates) == "50.00")
		#expect(shown(-8_900, "EUR", unitedStates) == "-89.00")
		#expect(shown(-123_456, "EUR", unitedStates) == "-1234.56")
		#expect(shown(-1_234, "KWD", unitedStates) == "-1.2340")
		for (minor, currency) in [(5_000, "EUR"), (-5, "EUR"), (-123_456, "EUR"), (1_200, "JPY"), (-1_234, "KWD"), (7, "KWD")] as [(Int64, String)] {
			for locale in [germany, unitedStates] {
				var d = TransactionDraft()
				d.amount = shown(minor, currency, locale)
				for region in DecimalMark.allCases { #expect(d.amountMinor(in: currency, region: region) == .success(minor)) }
			}
		}
	}

	@Test("Suggestions complete the typed start of a name, newest first and each name once, ignoring case and umlauts")
	func suggestions() {
		func row(_ day: Int, _ name: String) -> Transaction {
			Transaction(accountID: wallet.id, bookingDate: Day(year: 2026, month: 10, day: day), amountMinor: -100, name: name)
		}
		let l = Ledger(accounts: [wallet], transactions: [
			row(1, "Bäckerei Gutbrot"), row(2, "Baeckerei Kornfeld"), row(3, "Bäckerei Gutbrot"), row(4, "Bahnhofskiosk"), row(5, "Stadtwerke"), row(6, ""),
		])
		#expect(l.nameSuggestions(for: "Bäck").map(\.name) == ["Bäckerei Gutbrot", "Baeckerei Kornfeld"])
		#expect(l.nameSuggestions(for: "bäck").first?.bookingDate == Day(year: 2026, month: 10, day: 3))
		#expect(l.nameSuggestions(for: "BA").map(\.name) == ["Bahnhofskiosk", "Bäckerei Gutbrot", "Baeckerei Kornfeld"])
		#expect(l.nameSuggestions(for: "kiosk") == [])
		#expect(l.nameSuggestions(for: "") == [])
		#expect(l.nameSuggestions(for: "B", limit: 1).count == 1)
	}

	@Test("Suggestions keep two spaces and a trailing space of the typed text as the search text does")
	func suggestionSpaces() {
		let l = Ledger(accounts: [wallet], transactions: [
			Transaction(accountID: wallet.id, bookingDate: Day(year: 2026, month: 10, day: 1), amountMinor: -100, name: "Bäckerei  Gutbrot"),
		])
		#expect(l.nameSuggestions(for: "Bäckerei  G").map(\.name) == ["Bäckerei  Gutbrot"])
		#expect(l.nameSuggestions(for: "Bäckerei G").map(\.name) == ["Bäckerei  Gutbrot"])
		#expect(l.nameSuggestions(for: "Bäckerei ").map(\.name) == ["Bäckerei  Gutbrot"])
		#expect(l.nameSuggestions(for: "  Bäck").map(\.name) == ["Bäckerei  Gutbrot"])
		#expect(l.nameSuggestions(for: "Bäckereig") == [])
	}

	@Test("Only a chosen suggestion fills the purpose and the category, not a name typed to its end")
	func enterName() {
		let kiosk = Transaction(accountID: wallet.id, bookingDate: Day(year: 2026, month: 10, day: 2), amountMinor: -1_200, name: "Kiosk", purpose: "Zeitung",
			categoryID: leisure.id, categorizedBy: .manual)
		let names = (1...9).map { Transaction(accountID: wallet.id, bookingDate: Day(year: 2026, month: 9, day: $0), amountMinor: -100, name: "Kiosk \($0)", purpose: "Nummer \($0)") }
		let l = Ledger(accounts: [wallet], categories: [groceries, leisure], transactions: [kiosk] + names)

		var typed = TransactionDraft()
		for end in 1..."Kiosk".count {
			let text = String("Kiosk".prefix(end))
			typed.enterName(text, offered: l.nameSuggestions(for: typed.name), for: wallet.id, in: l)
		}
		#expect(typed.name == "Kiosk")
		#expect(typed.purpose == "" && typed.categoryID == nil)

		var chosen = TransactionDraft()
		chosen.enterName("k", offered: [], for: wallet.id, in: l)
		chosen.enterName("Kiosk", offered: l.nameSuggestions(for: "k"), for: wallet.id, in: l)
		#expect(chosen.purpose == "Zeitung" && chosen.categoryID == leisure.id)

		// The eighth suggestion, the last one shown, fills too. A name that the list did not show fills nothing.
		let offered = l.nameSuggestions(for: "kiosk ")
		#expect(offered.count == 8)
		var eighth = TransactionDraft()
		eighth.name = "kiosk "
		eighth.enterName(offered[7].name, offered: offered, for: wallet.id, in: l)
		#expect(eighth.purpose == offered[7].purpose)
		var pasted = TransactionDraft()
		pasted.name = "kiosk "
		pasted.enterName("Kiosk 1", offered: offered, for: wallet.id, in: l)
		#expect(!offered.contains { $0.name == "Kiosk 1" })
		#expect(pasted.purpose == "")
	}

	@Test("A chosen suggestion one character longer than the name counts as typing and fills nothing, a longer one fills")
	func suggestionOneCharacterLonger() {
		let seven = Transaction(accountID: wallet.id, bookingDate: Day(year: 2026, month: 10, day: 7), amountMinor: -700, name: "Kiosk 7", purpose: "Zeitung",
			categoryID: leisure.id, categorizedBy: .manual)
		let l = Ledger(accounts: [wallet], categories: [groceries, leisure], transactions: [seven])
		var oneLonger = TransactionDraft()
		oneLonger.name = "Kiosk "
		oneLonger.enterName("Kiosk 7", offered: l.nameSuggestions(for: "Kiosk "), for: wallet.id, in: l)
		#expect(oneLonger.name == "Kiosk 7")
		#expect(oneLonger.purpose == "" && oneLonger.categoryID == nil)
		var twoLonger = TransactionDraft()
		twoLonger.name = "Kiosk"
		twoLonger.enterName("Kiosk 7", offered: l.nameSuggestions(for: "Kiosk"), for: wallet.id, in: l)
		#expect(twoLonger.purpose == "Zeitung" && twoLonger.categoryID == leisure.id)
	}

	@Test("A chosen suggestion fills the name, and the purpose and the category while they are empty")
	func takeSuggestion() {
		let earlier = Transaction(accountID: wallet.id, bookingDate: Day(year: 2026, month: 10, day: 2), amountMinor: -480, name: "Bäckerei Gutbrot",
			purpose: "Brot", categoryID: groceries.id, categorizedBy: .manual)
		let l = Ledger(accounts: [wallet], categories: [groceries, leisure], transactions: [earlier])
		var empty = TransactionDraft()
		empty.name = "Bäck"
		empty.take(earlier, for: wallet.id, in: l)
		#expect(empty.name == "Bäckerei Gutbrot")
		#expect(empty.purpose == "Brot")
		#expect(empty.categoryID == groceries.id)
		#expect(empty.amount == "")

		var filled = TransactionDraft()
		filled.purpose = "Kuchen"
		filled.categoryID = leisure.id
		filled.take(earlier, for: wallet.id, in: l)
		#expect(filled.name == "Bäckerei Gutbrot")
		#expect(filled.purpose == "Kuchen")
		#expect(filled.categoryID == leisure.id)
	}

	@Test("A suggestion does not fill a category that is restricted to another account")
	func restrictedSuggestion() {
		let office = Domain.Category(position: 2, name: "Office", restrictedToID: business.id)
		let paper = Transaction(accountID: business.id, bookingDate: Day(year: 2026, month: 10, day: 2), amountMinor: -1_999, name: "Papierhaus Beispiel",
			categoryID: office.id, categorizedBy: .manual)
		let l = Ledger(accounts: [wallet, business], categories: [office], transactions: [paper])
		var d = TransactionDraft()
		d.take(paper, for: wallet.id, in: l)
		#expect(d.name == "Papierhaus Beispiel")
		#expect(d.categoryID == nil)
	}
}
