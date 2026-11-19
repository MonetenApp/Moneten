import Foundation
import Testing
import TestSupport
@testable import Domain

@Suite("Search and filters")
struct LedgerTests {
	let giro = Account(position: 0, name: "Giro", kind: .giro, source: .offline, initialBalanceMinor: 100_000)
	let food = Domain.Category(position: 0, name: "Food")

	func ledger() -> Ledger {
		let ts = [
			Transaction(accountID: giro.id, bookingDate: Day(year: 2026, month: 11, day: 3), amountMinor: -8_900, name: "Stadtwerke Musterstadt", purpose: "Abschlag Strom"),
			Transaction(accountID: giro.id, bookingDate: Day(year: 2026, month: 10, day: 2), amountMinor: -2_345, name: "Bäckerei Gutbrot", purpose: "Brötchen", categoryID: food.id, categorizedBy: .manual),
			Transaction(accountID: giro.id, bookingDate: Day(year: 2026, month: 9, day: 28), amountMinor: 320_000, name: "Beispiel GmbH", purpose: "Gehalt", isChecked: true),
			Transaction(accountID: giro.id, bookingDate: Day(year: 2026, month: 11, day: 4), amountMinor: -1_000, name: "Kiosk", isPending: true),
		]
		return Ledger(accounts: [giro], categories: [food, Domain.Category(position: 9, name: "Uncategorized", isDefault: true)], transactions: ts)
	}

	func search(_ text: String) -> [String] {
		var f = TransactionFilter()
		f.searchText = text
		return ledger().rows(in: .account(giro.id), filter: f).rows.map(\.name)
	}

	@Test("Accounts and subgroups of a group share one order")
	func accountTree() {
		let top = AccountGroup(name: "Private", position: 0)
		let sub = AccountGroup(name: "Old banks", parentID: top.id, position: 2)
		let first = Account(groupID: top.id, position: 0, name: "Giro", kind: .giro, source: .offline)
		let second = Account(groupID: top.id, position: 1, name: "Savings", kind: .savings, source: .offline)
		let last = Account(groupID: top.id, position: 3, name: "Card", kind: .creditCard, source: .offline)
		let l = Ledger(groups: [sub, top], accounts: [last, second, first])
		#expect(l.accountTree(in: top.id).map(\.id) == [first.id, second.id, sub.id, last.id])
		#expect(l.nextTreePosition(in: top.id) == 4)
		#expect(l.nextTreePosition(in: sub.id) == 0)
	}

	@Test("The Account menu lists the groups and accounts in sidebar order, each with the number of groups above it")
	func accountMenuOrder() {
		let top = AccountGroup(name: "Private", position: 1)
		let sub = AccountGroup(name: "Old banks", parentID: top.id, position: 1)
		let cash = Account(position: 0, name: "Cash", kind: .cash, source: .offline)
		let first = Account(groupID: top.id, position: 0, name: "Giro", kind: .giro, source: .offline)
		let inSub = Account(groupID: sub.id, position: 0, name: "Savings", kind: .savings, source: .offline)
		let last = Account(groupID: top.id, position: 2, name: "Card", kind: .creditCard, source: .offline)
		let l = Ledger(groups: [sub, top], accounts: [last, inSub, first, cash])
		let entries = l.accountTreeInSidebarOrder
		#expect(entries.map(\.item.id) == [cash.id, top.id, first.id, sub.id, inSub.id, last.id])
		#expect(entries.map(\.depth) == [0, 0, 1, 1, 2, 1])
	}

	@Test("A migrated or offline account follows its transactions, and an account with a bank access shows the bank balance")
	func balanceSource() {
		let wallet = Account(position: 0, name: "Wallet", kind: .other, source: .migrated, bankBalanceMinor: 13_320, initialBalanceMinor: 13_320)
		let cash = Account(position: 1, name: "Cash", kind: .other, source: .offline, initialBalanceMinor: 5_000)
		let fetched = Account(position: 2, name: "Giro", kind: .giro, source: .bank, iban: "DE02120300000000202051", bankBalanceMinor: 50_000,
			initialBalanceMinor: 40_000, accessID: UUID())
		let depot = Account(position: 3, name: "Depot", kind: .portfolio, source: .migrated, bankBalanceMinor: 2_000_000)
		var l = Ledger(accounts: [wallet, cash, fetched, depot])
		#expect(l.balance(of: wallet).minorUnits == 13_320)
		l.update([
			Transaction(accountID: wallet.id, bookingDate: Day(year: 2026, month: 11, day: 12), amountMinor: -480, name: "Bäckerei Gutbrot"),
			Transaction(accountID: cash.id, bookingDate: Day(year: 2026, month: 11, day: 12), amountMinor: -1_200, name: "Kiosk"),
			Transaction(accountID: fetched.id, bookingDate: Day(year: 2026, month: 11, day: 12), amountMinor: -1_000, name: "Kiosk"),
			Transaction(accountID: depot.id, bookingDate: Day(year: 2026, month: 11, day: 12), amountMinor: -3_000, name: "Depotgebühr"),
		])
		#expect(l.balance(of: wallet).minorUnits == 12_840)
		#expect(l.balance(of: cash).minorUnits == 3_800)
		#expect(l.balance(of: fetched).minorUnits == 50_000)
		#expect(l.balance(of: depot).minorUnits == 2_000_000)
	}

	@Test("The sum of a group leaves out closed accounts")
	func groupSumWithoutClosed() {
		let group = AccountGroup(name: "Old banks", position: 0)
		let open = Account(groupID: group.id, position: 0, name: "Giro", kind: .giro, source: .migrated, bankBalanceMinor: 10_000, initialBalanceMinor: 10_000)
		let closed = Account(groupID: group.id, position: 1, name: "Loan", kind: .other, source: .migrated, bankBalanceMinor: -500_000,
			initialBalanceMinor: -500_000, isClosed: true)
		let l = Ledger(groups: [group], accounts: [open, closed])
		#expect(l.sum(ofGroup: group.id).byCurrency == ["EUR": 10_000])
	}

	@Test("Newest first")
	func order() {
		#expect(ledger().transactions.map(\.name) == ["Kiosk", "Stadtwerke Musterstadt", "Bäckerei Gutbrot", "Beispiel GmbH"])
	}

	@Test("The search finds text inside words, ignores case and umlauts, and needs all words")
	func searchText() {
		#expect(search("werke") == ["Stadtwerke Musterstadt"])
		#expect(search("BAECKEREI") == ["Bäckerei Gutbrot"])
		#expect(search("brötchen gutbrot") == ["Bäckerei Gutbrot"])
		#expect(search("strom gehalt").isEmpty)
		let decomposed = "Ba\u{0308}ckerei"
		#expect(search(decomposed) == ["Bäckerei Gutbrot"])
	}

	@Test("The search finds the category name and the IBAN and the account number of the own account, also after a change")
	func searchCategoryAndOwnAccount() {
		var account = Account(position: 0, name: "Giro", kind: .giro, source: .offline, iban: "DE02120300000000202051", accountNumber: "4711")
		var groceries = Domain.Category(position: 0, name: "Groceries")
		var l = Ledger(accounts: [account], categories: [groceries, Domain.Category(position: 9, name: "Uncategorized", isDefault: true)], transactions: [
			Transaction(accountID: account.id, bookingDate: Day(year: 2026, month: 11, day: 3), amountMinor: -2_345, name: "Bäckerei Gutbrot",
				categoryID: groceries.id, categorizedBy: .manual),
			Transaction(accountID: account.id, bookingDate: Day(year: 2026, month: 11, day: 4), amountMinor: -1_000, name: "Kiosk"),
		])
		func found(_ text: String) -> [String] {
			var f = TransactionFilter()
			f.searchText = text
			return l.rows(in: .account(account.id), filter: f).rows.map(\.name)
		}
		#expect(found("groceries") == ["Bäckerei Gutbrot"])
		#expect(found("uncategorized") == ["Kiosk"])
		#expect(found("DE02120300000000202051") == ["Kiosk", "Bäckerei Gutbrot"])
		#expect(found("4711") == ["Kiosk", "Bäckerei Gutbrot"])
		groceries.name = "Food"
		l.upsert(groceries)
		#expect(found("food") == ["Bäckerei Gutbrot"])
		#expect(found("groceries").isEmpty)
		account.iban = "DE89370400440532013000"
		account.accountNumber = "0815"
		l.upsert(account)
		#expect(found("DE89370400440532013000").count == 2)
		#expect(found("0815").count == 2)
		#expect(found("DE02120300000000202051").isEmpty)
	}

	@Test("A row without a category is found by the name of the default category, also after the default changes")
	func searchDefaultCategoryChange() {
		let giro = Account(position: 0, name: "Giro", kind: .giro, source: .offline)
		var groceries = Domain.Category(position: 0, name: "Groceries")
		var other = Domain.Category(position: 9, name: "Uncategorized", isDefault: true)
		var l = Ledger(accounts: [giro], categories: [groceries, other], transactions: [
			Transaction(accountID: giro.id, bookingDate: Day(year: 2026, month: 11, day: 1), amountMinor: -1_000, name: "Kiosk"),
		])
		func found(_ text: String) -> [String] {
			var f = TransactionFilter()
			f.searchText = text
			return l.rows(in: .account(giro.id), filter: f).rows.map(\.name)
		}
		#expect(found("uncategorized") == ["Kiosk"])
		other.isDefault = false
		l.upsert(other)
		#expect(found("uncategorized").isEmpty)
		groceries.isDefault = true
		l.upsert(groceries)
		#expect(found("groceries") == ["Kiosk"])
		l.upsert(Domain.Category(position: 10, name: "Sonstiges"))
		#expect(found("groceries") == ["Kiosk"])
		groceries.name = "Food"
		l.upsert(groceries)
		#expect(found("food") == ["Kiosk"])
		#expect(found("groceries").isEmpty)
	}

	@Test("The search accepts the rule language, and a term without a field name searches every searched field inside words")
	func searchRuleLanguage() {
		let giro = Account(position: 0, name: "Giro", kind: .giro, source: .offline)
		let groceries = Domain.Category(position: 0, name: "Groceries")
		let l = Ledger(accounts: [giro], categories: [groceries], transactions: [
			Transaction(accountID: giro.id, bookingDate: Day(year: 2026, month: 11, day: 6), amountMinor: -12_000, name: "Stadtwerke Musterstadt", purpose: "Abschlag"),
			Transaction(accountID: giro.id, bookingDate: Day(year: 2026, month: 11, day: 5), amountMinor: -5_000, name: "Stadtwerke Musterstadt", purpose: "Abschlag"),
			Transaction(accountID: giro.id, bookingDate: Day(year: 2026, month: 11, day: 4), amountMinor: -15_000, name: "Beispiel GmbH", purpose: "Stadtwerke\n Umlage"),
			Transaction(accountID: giro.id, bookingDate: Day(year: 2026, month: 11, day: 3), amountMinor: 250_000, name: "Beispiel GmbH", purpose: "Gehalt Oktober"),
			Transaction(accountID: giro.id, bookingDate: Day(year: 2026, month: 11, day: 2), amountMinor: 30_000, name: "Erika Mustermann", purpose: "Lohn Aushilfe"),
			Transaction(accountID: giro.id, bookingDate: Day(year: 2026, month: 11, day: 1), amountMinor: -2_345, name: "Bäckerei Gutbrot",
				categoryID: groceries.id, categorizedBy: .manual),
		])
		func found(_ text: String) -> [Int64] {
			var f = TransactionFilter()
			f.searchText = text
			return l.rows(in: .account(giro.id), filter: f).rows.map(\.amountMinor)
		}
		#expect(found(#"name:"Stadtwerke" AND amount<-100"#) == [-12_000])
		#expect(found(#""Lohn" OR "Gehalt""#) == [250_000, 30_000])
		#expect(found(#"werke NOT name:Stadtwerke"#) == [-15_000])
		#expect(found(#""groceries" AND amount<0"#) == [-2_345])
		#expect(found(#""Gehalt Oktober""#) == [250_000])
		#expect(found(#""Oktober Gehalt""#).isEmpty)
		#expect(found(#""Stadtwerke Umlage""#) == [-15_000])
		#expect(found("Stadtw*") == [-12_000, -5_000, -15_000])
		#expect(found("Groc*") == [-2_345])
		#expect(found("*werke Muster*") == [-12_000, -5_000])
		#expect(found(#""Stadtw"#) == [-12_000, -5_000, -15_000])
		#expect(found(#"purpose:/^Lohn/"#) == [30_000])
		#expect(found("amount=-50") == [-5_000])
		#expect(found("amount<=-120") == [-12_000, -15_000])
		#expect(found("amount<-120") == [-15_000])
		#expect(found("amount>-120.0001 AND amount<0") == [-12_000, -5_000, -2_345])
		#expect(found("amount=-120.0001").isEmpty)
		#expect(found("amount!=-120.0001").count == 6)
	}

	@Test("A word without a field name finds text inside words, also with a wildcard, and a rejected text searches its words")
	func searchWordWithoutField() {
		let giro = Account(position: 0, name: "Girokonto", kind: .giro, source: .offline, iban: "DE02 1203 0000 0000 2020 51")
		let groceries = Domain.Category(position: 0, name: "Groceries")
		let l = Ledger(accounts: [giro], categories: [groceries], transactions: [
			Transaction(accountID: giro.id, bookingDate: Day(year: 2026, month: 11, day: 2), amountMinor: -1_250, name: "Markt", purpose: "REWE-Markt 4711",
				categoryID: groceries.id, categorizedBy: .manual),
		])
		var f = TransactionFilter()
		for text in [#"/\AREWE-M/"#, #"/4711\z/"#, #""REWE" AND amount<0"#, "Groc*", "/groceries/", "Girok*", "/^girok/", "DE02120300000000202051", "*0000202051", #""REWE-Mar"#, "(rewe",
			"REWE OR", "name:"] {
			f.searchText = text
			#expect(l.rows(in: .account(giro.id), filter: f).rows.count == 1, "\(text)")
		}
		for text in ["/DE02 1203/", "/DE02120300000000202051/"] {
			f.searchText = text
			#expect(l.rows(in: .account(giro.id), filter: f).rows.isEmpty, "\(text)")
		}
	}

	@Test("An IBAN written with a no-break or a narrow no-break space is found by the plain IBAN, as the rule finds it", arguments: ["\u{00A0}", "\u{202F}"])
	func searchIBANWithOtherSpaces(_ space: String) throws {
		let iban = ["DE02", "1203", "0000", "0000", "2020", "51"].joined(separator: space)
		let giro = Account(position: 0, name: "Girokonto", kind: .giro, source: .offline, iban: try IBAN(parsing: iban))
		let other = Account(position: 1, name: "Tagesgeld", kind: .savings, source: .offline, iban: "DE89370400440532013000")
		let rows = [
			Transaction(accountID: giro.id, bookingDate: Day(year: 2026, month: 11, day: 2), amountMinor: -1_250, name: "Markt", purpose: "REWE"),
			Transaction(accountID: other.id, bookingDate: Day(year: 2026, month: 11, day: 1), amountMinor: -500, name: "Kiosk", purpose: "Zeitung", counterpartyIBAN: iban),
		]
		let l = Ledger(accounts: [giro, other], transactions: rows)
		var f = TransactionFilter()
		for (text, names) in [("DE02120300000000202051", ["Markt", "Kiosk"]), ("local_account:DE0?1203*", ["Markt"]), ("local_account:DE02?1203*", []), ("local_account:DE02120300000000202051", ["Markt"]),
			("remote_account:DE02120300000000202051", ["Kiosk"])] {
			f.searchText = text
			#expect(l.rows(in: .all, filter: f).rows.map(\.name) == names, "\(text)")
			// A rule searches account fields only with a field name.
			guard text.contains(":") else { continue }
			let rule = try Rule(parsing: text)
			let accounts = [giro.id: giro, other.id: other]
			#expect(rows.filter { rule.matches(RuleSubject($0, account: accounts[$0.accountID])) }.map(\.name) == names, "\(text)")
		}
	}

	@Test("A regular expression that does not end counts as no match", .timeLimit(.minutes(1)))
	func searchRegexThatDoesNotEnd() {
		let giro = Account(position: 0, name: "Giro", kind: .giro, source: .offline)
		let l = Ledger(accounts: [giro], transactions: [
			Transaction(accountID: giro.id, bookingDate: Day(year: 2026, month: 11, day: 2), amountMinor: -1_000, name: "Vermieter", purpose: "Tel. +49 170 1234567"),
			Transaction(accountID: giro.id, bookingDate: Day(year: 2026, month: 11, day: 1), amountMinor: -90_000, name: "Vermieter", purpose: "Miete Mai"),
		])
		var f = TransactionFilter()
		for text in ["/^+?49/", #"/\s^+?a/"#, "currency:/^+?49/"] {
			f.searchText = text
			#expect(l.rows(in: .account(giro.id), filter: f).rows.isEmpty, "\(text)")
		}
		f.searchText = "/miete mai/"
		#expect(l.rows(in: .account(giro.id), filter: f).rows.map(\.purpose) == ["Miete Mai"])
	}

	@Test("A stopped regex discards all rows in either order, also with NOT", .timeLimit(.minutes(1)))
	func stoppedSearchHasNoPartialRows() {
		let account = Account(position: 0, name: "Giro", kind: .giro, source: .offline)
		let cases: [(String, [String])] = [
			(#"purpose:/(\w+\s?)*:/"#, ["Kundennummer: 4711", "Abschlag Strom November 2026", "Kundennummer: 4711"]),
			(#"NOT purpose:/(\w+\s?)*:/"#, ["Kundennummer: 4711", "Abschlag Strom November 2026", "Kundennummer: 4711"]),
			("/ok|(a+)+$/", ["ok", "ok", "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa!", "ok", "ok"]),
		]
		for (query, purposes) in cases {
			for offset in purposes.indices {
				let order = Array(purposes[offset...] + purposes[..<offset])
				let rows = order.enumerated().map {
					Transaction(accountID: account.id, bookingDate: Day(year: 2026, month: 11, day: 10 - $0.offset), amountMinor: -100, name: "Row\($0.offset)", purpose: $0.element)
				}
				let ledger = Ledger(accounts: [account], transactions: rows)
				var filter = TransactionFilter()
				filter.searchText = query
				let result = ledger.rows(in: .account(account.id), filter: filter)
				#expect(result.rows.map(\.name) == [])
				#expect(result.gaveUp == true)
			}
		}
	}

	@Test("One search adds the processor time of all regex calls", .timeLimit(.minutes(1)))
	func searchRegexProcessorBudget() {
		let account = Account(position: 0, name: "Giro", kind: .giro, source: .offline)
		let rows = (0..<100).map { _ in
			Transaction(accountID: account.id, bookingDate: Day(year: 2026, month: 11, day: 1), amountMinor: -100, name: "Row", purpose: "aaaaaaaaaaaaaaaaaaaa!")
		}
		let ledger = Ledger(accounts: [account], transactions: rows)
		var filter = TransactionFilter()
		filter.searchText = "purpose:/^(a+)+$/"
		let start = clock_gettime_nsec_np(CLOCK_THREAD_CPUTIME_ID)
		let result = ledger.rows(in: .account(account.id), filter: filter)
		let elapsed = Duration.nanoseconds(clock_gettime_nsec_np(CLOCK_THREAD_CPUTIME_ID) - start)
		print("100 slow rows: \(elapsed) searching-thread processor time, \(result.rows.count) rows, gaveUp=\(result.gaveUp)")
		#expect(result.rows.map(\.name) == [])
		#expect(result.gaveUp == true)
		#expect(elapsed >= .milliseconds(300))
		#expect(elapsed < budget(.milliseconds(400)))
	}

	@Test("Two word boundaries at the end of a value match the rows that the rule matches")
	func searchTwoWordBoundaries() throws {
		let giro = Account(position: 0, name: "Konto b", kind: .giro, source: .offline)
		let rows = [("x a", "x b"), ("Kiosk A", "Zeitung"), ("a", "Zeitung")].enumerated().map {
			Transaction(accountID: giro.id, bookingDate: Day(year: 2026, month: 11, day: 3 - $0.offset), amountMinor: -1_000, name: $0.element.0, purpose: $0.element.1)
		}
		let l = Ledger(accounts: [giro], transactions: rows)
		for query in [#"/a\b\s*?\b/"#, #"/a(\B|\b)/"#, #"/\b$\b/"#, #"/\b\s*\B/"#, #"/miete\b\b/"#] {
			var f = TransactionFilter()
			f.searchText = query
			let rule = try Rule(parsing: query)
			#expect(l.rows(in: .account(giro.id), filter: f).rows.map(\.name) == rows.filter { rule.matches(RuleSubject($0, account: giro)) }.map(\.name), "\(query)")
		}
	}

	@Test("A regular expression that runs long only over the joined values still finds the rows of the rule", .timeLimit(.minutes(1)))
	func searchRegexSlowOnlyWhenJoined() throws {
		let giro = Account(position: 0, name: "Giro", kind: .giro, source: .offline)
		let rows = [
			Transaction(accountID: giro.id, bookingDate: Day(year: 2026, month: 11, day: 4), amountMinor: -1_000, name: "Vermieter", purpose: "Miete Mai"),
			Transaction(accountID: giro.id, bookingDate: Day(year: 2026, month: 11, day: 3), amountMinor: -1_000, name: "Kiosk", purpose: "Mai Zeitung"),
			Transaction(accountID: giro.id, bookingDate: Day(year: 2026, month: 11, day: 2), amountMinor: -1_000, name: "Stadtwerke Muster", purpose: "Abschlag Strom 11"),
			Transaction(accountID: giro.id, bookingDate: Day(year: 2026, month: 11, day: 1), amountMinor: -1_000, name: "Vermieter", purpose: "Kundennummer: 4711"),
		]
		let l = Ledger(accounts: [giro], transactions: rows)
		for query in [#"/mai|\s^+?a/"#, #"/(\w+\s?)*:/"#] {
			var f = TransactionFilter()
			f.searchText = query
			let rule = try Rule(parsing: query)
			let ruled = rows.filter { rule.matches(RuleSubject($0, account: giro)) }.map(\.purpose)
			#expect(!ruled.isEmpty, "\(query)")
			#expect(l.rows(in: .account(giro.id), filter: f).rows.map(\.purpose) == ruled, "\(query)")
		}
	}

	@Test("The search true finds every row, and false finds none")
	func searchConstants() {
		let giro = Account(position: 0, name: "Giro", kind: .giro, source: .offline)
		let l = Ledger(accounts: [giro], transactions: [
			Transaction(accountID: giro.id, bookingDate: Day(year: 2026, month: 11, day: 2), amountMinor: -8_900, name: "Stadtwerke Musterstadt"),
			Transaction(accountID: giro.id, bookingDate: Day(year: 2026, month: 11, day: 1), amountMinor: -2_345, name: "Bäckerei Gutbrot"),
		])
		func found(_ text: String) -> [String] {
			var f = TransactionFilter()
			f.searchText = text
			return l.rows(in: .account(giro.id), filter: f).rows.map(\.name)
		}
		#expect(found("true") == ["Stadtwerke Musterstadt", "Bäckerei Gutbrot"])
		#expect(found("TRUE") == ["Stadtwerke Musterstadt", "Bäckerei Gutbrot"])
		#expect(found("false").isEmpty)
		#expect(found("Stadtwerke AND true") == ["Stadtwerke Musterstadt"])
		#expect(found("Stadtwerke OR true") == ["Stadtwerke Musterstadt", "Bäckerei Gutbrot"])
		#expect(found("Stadtwerke OR false") == ["Stadtwerke Musterstadt"])
		#expect(found("NOT false") == ["Stadtwerke Musterstadt", "Bäckerei Gutbrot"])
		#expect(found(#""true""#).isEmpty)
	}

	@Test("The fallback keeps constants and their negation")
	func unfinishedSearchConstants() {
		let account = Account(position: 0, name: "Giro", kind: .giro, source: .offline)
		let ledger = Ledger(accounts: [account], transactions: [
			Transaction(accountID: account.id, bookingDate: Day(year: 2026, month: 11, day: 1), amountMinor: -100, name: "Stadtwerke Musterstadt"),
		])
		let cases: [(String, [String])] = [
			(#"false "Stadtw"#, []),
			(#"NOT true "Stadtw"#, []),
			(#"true "Stadtw"#, ["Stadtwerke Musterstadt"]),
			(#"NOT false "Stadtw"#, ["Stadtwerke Musterstadt"]),
			(#"true "Kiosk"#, []),
		]
		for (text, expected) in cases {
			var filter = TransactionFilter()
			filter.searchText = text
			let result = ledger.rows(in: .account(account.id), filter: filter)
			#expect(result.rows.map(\.name) == expected)
			#expect(result.gaveUp == false)
		}
	}

	@Test("A phrase finds its words across any white space, and a quoted word finds text inside words, which a rule does not")
	func searchPhraseAcrossWhiteSpace() throws {
		let giro = Account(position: 0, name: "Giro", kind: .giro, source: .offline)
		let l = Ledger(accounts: [giro], transactions: ["Abschlag\nNovember", "Abschlag\tNovember", "Abschlag  November", "Lohnsteuer 10/2026"].enumerated().map {
			Transaction(accountID: giro.id, bookingDate: Day(year: 2026, month: 11, day: 1 + $0.offset), amountMinor: -1_000, name: "Row \($0.offset)", purpose: $0.element)
		})
		func found(_ text: String) -> [String] {
			var f = TransactionFilter()
			f.searchText = text
			return l.rows(in: .account(giro.id), filter: f).rows.map(\.name).sorted()
		}
		#expect(found(#""Abschlag November""#) == ["Row 0", "Row 1", "Row 2"])
		#expect(found(#""Lohn""#) == ["Row 3"])
		let lohn = try #require(l.transactions.first { $0.purpose.hasPrefix("Lohn") })
		#expect(try Rule(parsing: #""Lohn""#).matches(RuleSubject(lohn, account: giro)) == false)
	}

	@Test("Typing a field term, a regular expression, or an amount searches the plain words until the text reads")
	func searchWhileTyping() {
		let giro = Account(position: 0, name: "Giro", kind: .giro, source: .offline)
		let l = Ledger(accounts: [giro], transactions: [
			Transaction(accountID: giro.id, bookingDate: Day(year: 2026, month: 11, day: 1), amountMinor: -8_900, name: "Stadtwerke Musterstadt",
				purpose: "Abschlag\u{202F}November"),
		])
		var f = TransactionFilter()
		for text in [#"name:"Stadtw"#, "name:Stadtwerke OR", "purpose:/^Absch", "Stadtwerke amount<-", "/Stadt", #""Abschlag November""#,
			"Stadtwerke or", "Stadtwerke +", "Name:Stadtwerke OR", #"name:="Stadtw"#, "Stadtwerke amount:=-", "Stadtwerke !", "Stadtwerke -",
			#"Stadtwerke NOT "Gehalt"#, #"Stadtwerke not "Gehalt"#, #"Stadtwerke !"Gehalt"#, #"Stadtwerke -"Gehalt"#, #"Stadtwerke-"Gehalt"#,
			#"name!=Gehalt "Stadtw"#, #"NAME<>Gehalt "Stadtw"#] {
			f.searchText = text
			#expect(l.rows(in: .account(giro.id), filter: f).rows.count == 1, "\(text)")
		}
	}

	@Test("Rejected text reads open quotation marks, regular expressions, and groups to the end, and leaves out the words it excludes")
	func searchWhileTypingExclusions() {
		let giro = Account(position: 0, name: "Giro", kind: .giro, source: .offline)
		let l = Ledger(accounts: [giro], transactions: ["Abschlag November", "Abschlag Oktober", "Lohn"].enumerated().map {
			Transaction(accountID: giro.id, bookingDate: Day(year: 2026, month: 11, day: 3 - $0.offset), amountMinor: -1_000, name: "Stadtwerke Musterstadt", purpose: $0.element)
		})
		func found(_ text: String) -> [String] {
			var f = TransactionFilter()
			f.searchText = text
			return l.rows(in: .account(giro.id), filter: f).rows.map(\.purpose)
		}
		let all = ["Abschlag November", "Abschlag Oktober", "Lohn"]
		#expect(found("Stadtwerke NOT (Gehalt OR Lohn") == all)
		#expect(found(#"Stadtwerke -"Abschlag November"#) == all)
		#expect(found(#"Stadtwerke name!="x Oktober"#) == all)
		#expect(found("Stadtwerke -(Lohn Oktober") == all)
		#expect(found("Stadtwerke - (Lohn Oktober") == all)
		#expect(found("Stadtwerke -(Lohn) Oktober OR") == ["Abschlag Oktober"])
		#expect(found(#"Stadtwerke -"Lohn" Oktober OR"#) == ["Abschlag Oktober"])
		#expect(found("Stadtwerke -/Lohn Oktober") == all)
		#expect(found("Stadtwerke NOT /Lohn Oktober") == all)
		#expect(found(#"Stadtwerke-"Lohn"#) == all)
		#expect(found("Stadtwerke NOT(Lohn") == all)
		#expect(found(#"Stadtwerke -"and Lohn" Abschlag "Nov"#) == ["Abschlag November"])
		#expect(found(#"Stadtwerke "Abschlag -Nov" Lohn (x"#).isEmpty)
		#expect(found(#"Stadtwerke /\d"#) == all)
		#expect(found("Stadtwerke /Absch.*") == all)
		#expect(found("Stadtwerke /Lohn|Absch") == all)
		#expect(found("Stadtwerke /[A-Z") == all)
		#expect(found(#"/\d+ Abschl"#) == ["Abschlag November", "Abschlag Oktober"])
		#expect(found(#"Stadtwerke name:-"Lohn"#) == all)
		#expect(found(#"Stadtwerke name:-"Lohn""#) == all)
		#expect(found("Stadtwerke name:!/Lohn") == all)
		#expect(found("Stadtwerke name:-/Lohn") == all)
		#expect(found("Stadtwerke name:+(Lohn") == ["Lohn"])
	}

	@Test("A field term and a regular expression with a field name match the rows that the same rule matches")
	func fieldTermsMatchRules() throws {
		let giro = Account(position: 0, name: "Giro", kind: .giro, source: .offline, iban: "DE02 1203 0000 0000 2020 51", accountNumber: "4711")
		let rows = [
			Transaction(accountID: giro.id, bookingDate: Day(year: 2026, month: 11, day: 1), amountMinor: -8_900, name: "Stadtwerke  Musterstadt",
				purpose: "Abschlag\nNovember", counterpartyIBAN: "DE89 3704 0044 0532 0130 00", comment: "Strom"),
			Transaction(accountID: giro.id, bookingDate: Day(year: 2026, month: 11, day: 2), amountMinor: -2_345, currency: "USD", name: "Bäckerei Gutbrot",
				purpose: "Kartenzahlung", bookingText: "LASTSCHRIFT", endToEndReference: "E2E-1", mandateReference: "M-1", creditorID: "DE98ZZZ09999999999"),
		]
		let all = rows + [Transaction(accountID: giro.id, bookingDate: Day(year: 2026, month: 11, day: 3), amountMinor: -400, name: "Cafe\u{332}", purpose: "Kaffee\r"),
			Transaction(accountID: giro.id, bookingDate: Day(year: 2026, month: 11, day: 4), amountMinor: -250, name: "Kiosk\u{1}Am Markt", purpose: "Zeitung"),
			Transaction(accountID: giro.id, bookingDate: Day(year: 2026, month: 11, day: 5), amountMinor: -320, name: "Cafe\u{301}", purpose: "Rechnung 12"),
			Transaction(accountID: giro.id, bookingDate: Day(year: 2026, month: 11, day: 6), amountMinor: -180, name: "Imbiss \u{301}Nord", purpose: "Pommes"),
			Transaction(accountID: giro.id, bookingDate: Day(year: 2026, month: 11, day: 7), amountMinor: -190, name: "Grill \u{FE20}Ost", purpose: "Wurst"),
			Transaction(accountID: giro.id, bookingDate: Day(year: 2026, month: 11, day: 8), amountMinor: -60, name: "Bude\u{1}\u{301}", purpose: "Karte ****1234"),
			Transaction(accountID: giro.id, bookingDate: Day(year: 2026, month: 11, day: 9), amountMinor: -70, name: "Automat", purpose: "Code\u{1F}abc"),
			Transaction(accountID: giro.id, bookingDate: Day(year: 2026, month: 11, day: 10), amountMinor: -80, name: "Linie\u{2028}Neun", purpose: "Fahrkarte"),
			Transaction(accountID: giro.id, bookingDate: Day(year: 2026, month: 11, day: 11), amountMinor: -90, name: "Miete.", purpose: "Mai")]
		let l = Ledger(accounts: [giro], transactions: all)
		let queries = [#"name:"Stadtwerke Musterstadt""#, "name:Stadt*", "purpose:November", #"purpose:"Abschlag November""#, "comment:strom",
			"booking_text:lastschrift", "reference:E2E-1", "mandate:M-1", "creditor_id:DE98ZZZ*", "remote_account:DE89370400440532013000", "remote_account:/^DE89 3704/", "remote_account:/^DE893704/", "local_account:/^DE02 1203/", "local_account:/^DE021203/",
			#"local_account:"DE02 1203 0000 0000 2020 51""#, "local_account:4711", "currency:USD", "name:baeckerei", "name:*gutbrot", "name:*ecke*", "name:Stadtwerke*", "purpose:/^Abschlag/", "name:/gutbrot$/", #"local_account:/\A4711/"#, #"booking_text:/\ALAST/"#, #"purpose:/zahlung\z/"#, "name:/(?-m)^b/", #"name:/gutbrot\D*+$/"#, "name:caf*", "name:*e", #"purpose:/kaffee\s$/"#, #"/kaffee\s$/"#, #"/gutbrot\D*+$/"#, "comment:/^$/", "/^$/",
			"purpose:Zeitung", "name:markt", "name:kiosk*", "Name:Stadtwerke*", "NAME:=baeckerei", "name==*gutbrot", "name=caf*", "name!=Stadtwerke*", "name<>*e",
			"true", "NOT false", "comment:strom OR false",
			"/cafe/", "/rechnung 1/", "/RECHNUNG 1/", "purpose:/chnung 1/", "/k[a-z]ffee/", "/kaffe?e/", "/zahl+ung/", #"/e2e-\d/"#, #"mandate:/m\x2d1/"#,
			#"/\p{Lu}utbrot/"#, #"/abschlag\nnov/"#, "/stadtwerke  muster/", "/b.ckerei/", "/^kiosk/", "/zahlungs?/", "/zahlungx*/", "/zahlungx{0,2}/",
			"/zahl[uvwxyzabcdef]ng/", "/zahl[^xyzabcdefgh]ng/", #"/\x7aahlung/"#, #"/zahl\u0075ng/"#, "/zahlung$/", #"/zahl\Bung/"#,
			#"/\QM-1x\E?/"#, #"mandate:/\QM-1x\E{0}/"#, #"/kartenzahlungx\Q\E?/"#, "name:nord", "name:imbiss", "name:ost", #"name:"Grill Ost""#, "purpose:karte", "purpose:*1234", "purpose:**1234", "purpose:*12?4",
			"name:bude??", "/kartenzahlungxyz.|\u{308}?kartenzahlung/", "/(\u{308}.kartenzahlungxyz)?kartenzahlung/", #"/\c_abc/"#, "/^linie/", "/fahrkarte$/", #"/linie\sneun/"#, #"/miete\X\b/"#]
		for query in queries {
			var f = TransactionFilter()
			f.searchText = query
			let rule = try Rule(parsing: query)
			let searched: Set<UUID> = Set(l.rows(in: .account(giro.id), filter: f).rows.map(\.id))
			let ruled: Set<UUID> = Set(all.filter { rule.matches(RuleSubject($0, account: giro)) }.map(\.id))
			#expect(!ruled.isEmpty, "\(query)")
			#expect(searched == ruled, "\(query)")
		}
		for query in ["/^neun/", #"/strom\sgiro/"#, #"/miete\X\B/"#] {
			var f = TransactionFilter()
			f.searchText = query
			let rule = try Rule(parsing: query)
			#expect(l.rows(in: .account(giro.id), filter: f).rows.isEmpty, "\(query)")
			#expect(!all.contains { rule.matches(RuleSubject($0, account: giro)) }, "\(query)")
		}
		// Swift calls "é" and "e" with a combining accent equal, but a regular expression tells them apart, so the
		// search must not take the forms or the outcome of one account text for the other.
		let composed = Account(position: 0, name: "Kasse A", kind: .giro, source: .offline, accountNumber: "\u{E9}4711")
		let decomposed = Account(position: 1, name: "Kasse B", kind: .giro, source: .offline, accountNumber: "e\u{301}4711")
		let accounts = [composed, decomposed]
		let accented = accounts.enumerated().map { i, account in
			Transaction(accountID: account.id, bookingDate: Day(year: 2026, month: 11, day: 12 + i), amountMinor: -100, name: "Kunde \(i)",
				counterpartyIBAN: account.accountNumber)
		}
		let accentedLedger = Ledger(accounts: accounts, transactions: accented)
		for query in ["local_account:/^\u{E9}4711$/", "local_account:/^e\u{301}4711$/", "remote_account:/^\u{E9}4711$/", "remote_account:/^e\u{301}4711$/"] {
			var f = TransactionFilter()
			f.searchText = query
			let rule = try Rule(parsing: query)
			let searched = accentedLedger.rows(in: .all, filter: f).rows.map(\.name).sorted()
			let ruled = accented.filter { t in rule.matches(RuleSubject(t, account: accounts.first { $0.id == t.accountID })) }.map(\.name)
			#expect(ruled.count == 1, "\(query)")
			#expect(searched == ruled, "\(query)")
		}
		// A bridged text with an unpaired UTF-16 surrogate has the UTF-8 bytes of a replacement character in Swift, but
		// a regular expression reads the surrogate. So the search must not share the forms or the outcome of the two.
		let surrogate = NSString(characters: [0xD800, 0x34, 0x37, 0x31, 0x31], length: 5) as String
		for numbers in [[surrogate, "\u{FFFD}4711"], ["\u{FFFD}4711", surrogate]] {
			let kassen = numbers.enumerated().map { i, number in
				Account(position: i, name: "Kasse \(i)", kind: .giro, source: .offline, accountNumber: number)
			}
			let rows = kassen.enumerated().map { i, account in
				Transaction(accountID: account.id, bookingDate: Day(year: 2026, month: 11, day: 12 + i), amountMinor: -100, name: "Kunde \(i)",
					counterpartyIBAN: account.accountNumber)
			}
			let surrogateLedger = Ledger(accounts: kassen, transactions: rows)
			for query in ["local_account:/^\u{FFFD}4711$/", "remote_account:/^\u{FFFD}4711$/"] {
				var f = TransactionFilter()
				f.searchText = query
				let rule = try Rule(parsing: query)
				let searched = surrogateLedger.rows(in: .all, filter: f).rows.map(\.name).sorted()
				let ruled = rows.filter { t in rule.matches(RuleSubject(t, account: kassen.first { $0.id == t.accountID })) }.map(\.name)
				#expect(ruled.count == 1, "\(query)")
				#expect(searched == ruled, "\(query)")
			}
		}
	}

	@Test("A regular expression on the counterparty account finds the same rows as the rule when rows share a counterparty")
	func sharedCounterpartyRegex() throws {
		let giro = Account(position: 0, name: "Giro", kind: .giro, source: .offline)
		let counterparties: [String?] = ["DE02120300000000202051", "4711", "DE02120300000000202051", nil, "DE03120300000000202051", "4711", nil]
		let rows = counterparties.enumerated().map { i, iban in
			Transaction(accountID: giro.id, bookingDate: Day(year: 2026, month: 11, day: 1 + i), amountMinor: -100 * Int64(i + 1), name: "Kunde \(i)",
				counterpartyIBAN: iban)
		}
		let l = Ledger(accounts: [giro], transactions: rows)
		let queries = ["remote_account:/^DE02 1203/", "remote_account:/^DE021203/", "remote_account:/^4711$/", "NOT remote_account:/^DE02/",
			"remote_account:/^DE03/ OR remote_account:/^4711$/", "remote_account:/^$/", "remote_account:/DE02/ AND name:/Kunde [02]/"]
		for query in queries {
			var f = TransactionFilter()
			f.searchText = query
			let rule = try Rule(parsing: query)
			let searched = l.rows(in: .account(giro.id), filter: f).rows.map(\.name).sorted()
			let ruled = rows.filter { rule.matches(RuleSubject($0, account: giro)) }.map(\.name).sorted()
			#expect(searched == ruled, "\(query)")
		}
		var f = TransactionFilter()
		f.searchText = "remote_account:/^DE02 1203/"
		#expect(l.rows(in: .account(giro.id), filter: f).rows.map(\.name).sorted() == ["Kunde 0", "Kunde 2"])
	}

	@Test("Search for finds the row it starts from, also with quotation marks in the name")
	func searchForName() {
		let giro = Account(position: 0, name: "Giro", kind: .giro, source: .offline)
		let names = [#"Restaurant "Zum Hirschen""#, "Verein „Freunde“ e.V.", "Tom OR Jerry GbR", "Stadtwerke Musterstadt"]
		let l = Ledger(accounts: [giro], transactions: names.enumerated().map {
			Transaction(accountID: giro.id, bookingDate: Day(year: 2026, month: 11, day: 1 + $0.offset), amountMinor: -1_000, name: $0.element)
		})
		var f = TransactionFilter()
		for name in names {
			f.searchText = TransactionFilter.searchText(for: name)
			#expect(l.rows(in: .account(giro.id), filter: f).rows.map(\.name) == [name])
		}
	}

	@Test("An amount term beyond the range of an amount compares as a rule does")
	func searchAmountBeyondRange() {
		let giro = Account(position: 0, name: "Giro", kind: .giro, source: .offline)
		let l = Ledger(accounts: [giro], transactions: [
			Transaction(accountID: giro.id, bookingDate: Day(year: 2026, month: 11, day: 1), amountMinor: 0, name: "Zero"),
			Transaction(accountID: giro.id, bookingDate: Day(year: 2026, month: 11, day: 2), amountMinor: 5_000, name: "Fifty"),
		])
		var f = TransactionFilter()
		f.searchText = "amount<100000000000000000"
		#expect(l.rows(in: .account(giro.id), filter: f).rows.count == 2)
		f.searchText = "amount=184467440737095516.16"
		#expect(l.rows(in: .account(giro.id), filter: f).rows.isEmpty)
		f.searchText = "amount>-100000000000000000"
		#expect(l.rows(in: .account(giro.id), filter: f).rows.count == 2)
		f.searchText = "amount<1" + String(repeating: "0", count: 130)
		#expect(l.rows(in: .account(giro.id), filter: f).rows.count == 2)
		f.searchText = "amount>-1" + String(repeating: "0", count: 130)
		#expect(l.rows(in: .account(giro.id), filter: f).rows.count == 2)
	}

	@Test("Amounts outside Int64 have constant truth values at both stored edges")
	func searchAmountAtInt64Edges() throws {
		let account = Account(position: 0, name: "Giro", kind: .giro, source: .offline)
		let rows = [
			Transaction(accountID: account.id, bookingDate: Day(year: 2026, month: 11, day: 3), amountMinor: Int64.max, name: "Maximum"),
			Transaction(accountID: account.id, bookingDate: Day(year: 2026, month: 11, day: 2), amountMinor: Int64.min, name: "Minimum"),
			Transaction(accountID: account.id, bookingDate: Day(year: 2026, month: 11, day: 1), amountMinor: 100_000_000_000_000_000, currency: "JPY", name: "Yen"),
		]
		let ledger = Ledger(accounts: [account], transactions: rows)
		let cases: [(String, [String])] = [
			("amount=100000000000000000", ["Yen"]),
			("amount<99999999999999999999", ["Maximum", "Minimum", "Yen"]),
			("amount<=99999999999999999999", ["Maximum", "Minimum", "Yen"]),
			("amount>99999999999999999999", []),
			("amount>=99999999999999999999", []),
			("amount!=99999999999999999999", ["Maximum", "Minimum", "Yen"]),
			("amount=-100000000000000000", []),
			("amount>-99999999999999999999", ["Maximum", "Minimum", "Yen"]),
			("amount<=-99999999999999999999", []),
			("amount=92233720368547758.07", ["Maximum"]),
			("amount=-92233720368547758.08", ["Minimum"]),
			("amount>92233720368547758.07", ["Yen"]),
			("amount<-92233720368547758.08", []),
		]
		for (text, expected) in cases {
			var filter = TransactionFilter()
			filter.searchText = text
			#expect(ledger.rows(in: .account(account.id), filter: filter).rows.map(\.name) == expected, "\(text)")
			let rule = try Rule(parsing: text)
			#expect(rows.filter { rule.matches(RuleSubject($0, account: account)) }.map(\.name) == expected, "\(text)")
		}
	}

	@Test("An amount term compares the amount in the decimals of its currency")
	func searchAmountInCurrency() {
		let wallet = Account(position: 0, name: "Wallet", kind: .giro, source: .offline, currency: "JPY")
		let l = Ledger(accounts: [wallet], transactions: [
			Transaction(accountID: wallet.id, bookingDate: Day(year: 2026, month: 11, day: 2), amountMinor: -1_500, currency: "JPY", name: "Ramen"),
			Transaction(accountID: wallet.id, bookingDate: Day(year: 2026, month: 11, day: 1), amountMinor: -1_500, currency: "EUR", name: "Café"),
		])
		var f = TransactionFilter()
		f.searchText = "amount=-1500"
		#expect(l.rows(in: .account(wallet.id), filter: f).rows.map(\.name) == ["Ramen"])
		f.searchText = "amount=-15"
		#expect(l.rows(in: .account(wallet.id), filter: f).rows.map(\.name) == ["Café"])
	}

	@Test("The search follows changes: a renamed account, an update, and a removal")
	func searchAfterChanges() {
		var l = ledger()
		var f = TransactionFilter()
		var renamed = giro
		renamed.name = "Haushaltskonto"
		l.upsert(renamed)
		l.replace()
		f.searchText = "haushaltskonto"
		#expect(l.rows(in: .account(giro.id), filter: f).rows.count == 4)
		var kiosk = l.transactions.first { $0.name == "Kiosk" }!
		kiosk.purpose = "Zeitung"
		kiosk.bookingDate = Day(year: 2026, month: 1, day: 1)
		l.update([kiosk, Transaction(accountID: giro.id, bookingDate: Day(year: 2026, month: 11, day: 5), amountMinor: -500, name: "Optiker")])
		f.searchText = "zeitung"
		#expect(l.rows(in: .account(giro.id), filter: f).rows.map(\.name) == ["Kiosk"])
		f.searchText = "optiker"
		#expect(l.rows(in: .account(giro.id), filter: f).rows.map(\.name) == ["Optiker"])
		#expect(l.transactions.first?.name == "Optiker")
		l.remove(transactionIDs: [kiosk.id])
		f.searchText = "zeitung"
		#expect(l.rows(in: .account(giro.id), filter: f).rows.isEmpty)
	}

	@Test("The search finds exact amounts")
	func searchAmount() {
		#expect(search("89,00") == ["Stadtwerke Musterstadt"])
		#expect(search("-23,45") == ["Bäckerei Gutbrot"])
		#expect(search("-23.45") == ["Bäckerei Gutbrot"])
		// The list shows the minus sign U+2212. An amount copied from there matches too.
		#expect(search("\u{2212}23,45") == ["Bäckerei Gutbrot"])
	}

	@Test("An amount word finds the whole amount and not a longer amount that holds it")
	func searchWholeAmount() {
		let l = Ledger(accounts: [giro], transactions: [
			Transaction(accountID: giro.id, bookingDate: Day(year: 2026, month: 11, day: 5), amountMinor: -4_999, name: "Kiosk"),
			Transaction(accountID: giro.id, bookingDate: Day(year: 2026, month: 11, day: 4), amountMinor: -14_999, name: "Elektromarkt"),
			Transaction(accountID: giro.id, bookingDate: Day(year: 2026, month: 11, day: 3), amountMinor: 4_999, name: "Erstattung"),
			Transaction(accountID: giro.id, bookingDate: Day(year: 2026, month: 11, day: 2), amountMinor: -124_999, name: "Möbelhaus"),
			Transaction(accountID: giro.id, bookingDate: Day(year: 2026, month: 11, day: 1), amountMinor: -1_000, name: "Vermieter", purpose: "Rechnung 149,99 Kundennummer 4711"),
		])
		func found(_ text: String) -> [String] {
			var f = TransactionFilter()
			f.searchText = text
			return l.rows(in: .account(giro.id), filter: f).rows.map(\.name)
		}
		// Without a sign the amount finds both signs, with a sign only its own. The purpose "Rechnung 149,99" holds
		// "49,99" as text, which a search word finds inside words.
		#expect(found("49,99") == ["Kiosk", "Erstattung", "Vermieter"])
		#expect(found("49.99") == ["Kiosk", "Erstattung"])
		#expect(found("-49,99") == ["Kiosk"])
		#expect(found("-49.99") == ["Kiosk"])
		#expect(found("+49,99") == ["Erstattung"])
		#expect(found("149,99") == ["Elektromarkt", "Vermieter"])
		#expect(found("-149,99") == ["Elektromarkt"])
		#expect(found("149.99") == ["Elektromarkt"])
		// The list shows thousands separators, so an amount copied from there finds its row.
		#expect(found("1.249,99") == ["Möbelhaus"])
		#expect(found("-1.249,99") == ["Möbelhaus"])
		#expect(found("1,249.99") == ["Möbelhaus"])
		#expect(found("1249,99") == ["Möbelhaus"])
		#expect(found("249,99").isEmpty)
		#expect(found("99") == ["Vermieter"])
		#expect(found("4711") == ["Vermieter"])
		#expect(found("10") == ["Vermieter"])

		// A part of a split transaction is found by its own amount and by the amount of the transaction, each as a whole.
		let split = Transaction(accountID: giro.id, bookingDate: Day(year: 2026, month: 11, day: 1), amountMinor: -14_999, name: "Elektromarkt")
		let parts = [SplitPart(transactionID: split.id, position: 0, amountMinor: -10_000, comment: "Kabel"),
			SplitPart(transactionID: split.id, position: 1, amountMinor: -4_999, comment: "Adapter")]
		let splitLedger = Ledger(accounts: [giro], transactions: [split], parts: parts)
		func foundParts(_ text: String) -> [String?] {
			var f = TransactionFilter()
			f.searchText = text
			return splitLedger.rows(in: .account(giro.id), filter: f).rows.map(\.comment)
		}
		#expect(foundParts("-149,99") == ["Kabel", "Adapter"])
		#expect(foundParts("49,99") == ["Adapter"])
		#expect(foundParts("100") == ["Kabel"])
		#expect(foundParts("1.000,00").isEmpty)
	}

	@Test("An amount word compares the exact value, as amount= in a rule does, also without the integer part or with more zeros")
	func searchExactAmountValue() throws {
		let day = Day(year: 2026, month: 11, day: 5)
		let rows = [
			Transaction(accountID: giro.id, bookingDate: day, amountMinor: 1_230, currency: "KWD", name: "Basar"),
			Transaction(accountID: giro.id, bookingDate: day.adding(days: -1), amountMinor: 1_234, currency: "KWD", name: "Souk"),
			Transaction(accountID: giro.id, bookingDate: day.adding(days: -2), amountMinor: -99, name: "Kiosk"),
			Transaction(accountID: giro.id, bookingDate: day.adding(days: -3), amountMinor: -14_999, name: "Elektromarkt"),
			Transaction(accountID: giro.id, bookingDate: day.adding(days: -4), amountMinor: 0, name: "Nullbuchung"),
		]
		let l = Ledger(accounts: [giro], transactions: rows)
		func found(_ text: String) -> [String] {
			var f = TransactionFilter()
			f.searchText = text
			return l.rows(in: .account(giro.id), filter: f).rows.map(\.name)
		}
		// The search text also holds 1.234 KWD rounded to two decimals, "1.23", which an amount word does not read.
		#expect(found("1.23") == ["Basar"])
		#expect(found("+1.23") == ["Basar"])
		#expect(found("1,23") == ["Basar"])
		#expect(found("1.230") == ["Basar"])
		#expect(found("1.2340") == ["Souk"])
		#expect(found("1,234") == ["Souk"])
		// A word without the integer part reads as 0,99, as the amount of a rule does.
		#expect(found(".99") == ["Kiosk"])
		#expect(found(",99") == ["Kiosk"])
		#expect(found("0,990") == ["Kiosk"])
		#expect(found("149,990") == ["Elektromarkt"])

		// The search with a sign finds the rows of the rule with the same amount.
		// Zero has no sign: -0 and +0 find it under either sign, as amount=-0 does in a rule.
		#expect(found("-0") == ["Nullbuchung"])
		#expect(found("-0,00") == ["Nullbuchung"])
		#expect(found("+0") == ["Nullbuchung"])
		for (word, amount) in [("+1.23", "1.23"), ("+1.2340", "1.2340"), ("-0,99", "-0,99"), ("-149,990", "-149,99"),
				("-0", "-0"), ("-0,00", "-0,00"), ("+0", "0")] {
			let rule = try Rule(parsing: "amount=\(amount)")
			#expect(found(word) == rows.filter { rule.matches(RuleSubject($0, account: giro)) }.map(\.name), "\(word)")
		}
		for amount in [".99", ",99"] {
			let rule = try Rule(parsing: "amount=-\(amount)")
			#expect(found(amount) == rows.filter { rule.matches(RuleSubject($0, account: giro)) }.map(\.name), "\(amount)")
		}
	}

	@Test("The search text holds the amounts from amountPlace on, the exact amount first, and a part the amounts of its transaction after its own")
	func amountPlace() throws {
		let t = Transaction(accountID: giro.id, bookingDate: Day(year: 2026, month: 11, day: 5), amountMinor: -12_344, currency: "KWD",
			name: "Basar", purpose: "Teppich", counterpartyBIC: "TESTDEFFXXX", comment: "Reise")
		let part = SplitPart(transactionID: t.id, position: 0, amountMinor: -10_000, comment: "Kissen")
		let l = Ledger(accounts: [giro], transactions: [t], parts: [part, SplitPart(transactionID: t.id, position: 1, amountMinor: -2_344, comment: "Lampe")])
		let places = try #require(l.searchText[part.id]).split(separator: "\u{1}", omittingEmptySubsequences: false)
		let amountPlace = SearchText.amountPlace, perAmount = SearchText.textsPerAmount
		#expect(places.count == amountPlace + 2 * perAmount)
		#expect(places[amountPlace - 1] == "")
		#expect(places[amountPlace - 3] == "testdeffxxx")
		#expect(places[amountPlace] == "-10")
		#expect(places[amountPlace + perAmount] == "-12.344")
		let transactionAmounts: [String] = places[(amountPlace + perAmount)...].map(String.init)
		let amountTexts: [String] = Ledger.amountTexts(-12_344, decimals: 3)
		#expect(transactionAmounts == amountTexts)
	}

	@Test("The search text holds each amount as typed: plain, with comma or point, and with two decimals")
	func amountSearchText() {
		func text(_ minor: Int64, _ currency: String = "EUR") -> [String] {
			let t = Transaction(accountID: giro.id, bookingDate: Day(year: 2026, month: 1, day: 1), amountMinor: minor, currency: currency, name: "")
			return Ledger.amountTexts(t.amountMinor, decimals: t.amount.decimalPlaces)
		}
		#expect(text(-2_345) == ["-23.45", "-23,45", "-23,45", "-23.45"])
		#expect(text(-2_340) == ["-23.4", "-23,4", "-23,40", "-23.40"])
		#expect(text(100_000) == ["1000", "1000", "1000,00", "1000.00"])
		#expect(text(5) == ["0.05", "0,05", "0,05", "0.05"])
		#expect(text(0) == ["0", "0", "0,00", "0.00"])
		#expect(text(1_234, "JPY") == ["1234", "1234", "1234,00", "1234.00"])
		#expect(text(12_345, "KWD") == ["12.345", "12,345", "12,35", "12.35"])
		#expect(text(-12_344, "KWD") == ["-12.344", "-12,344", "-12,34", "-12.34"])
		// The largest amounts do not overflow.
		#expect(text(.max) == ["92233720368547758.07", "92233720368547758,07", "92233720368547758,07", "92233720368547758.07"])
		#expect(text(.min) == ["-92233720368547758.08", "-92233720368547758,08", "-92233720368547758,08", "-92233720368547758.08"])
		#expect(text(.max, "JPY") == ["9223372036854775807", "9223372036854775807", "9223372036854775807,00", "9223372036854775807.00"])
		#expect(text(.min, "KWD")[3] == "-9223372036854775.81")
	}

	@Test("Status, amount, period, and category filters combine")
	func filters() {
		let l = ledger()
		var f = TransactionFilter()
		f.status = .checked
		#expect(l.rows(in: .account(giro.id), filter: f).rows.map(\.name) == ["Beispiel GmbH"])
		f = TransactionFilter()
		f.amount = .deposits
		#expect(l.rows(in: .account(giro.id), filter: f).rows.count == 1)
		f.amount = .withdrawals
		f.period = DayRange(start: Day(year: 2026, month: 11, day: 1), end: Day(year: 2026, month: 11, day: 30))
		#expect(l.rows(in: .account(giro.id), filter: f).rows.map(\.name) == ["Kiosk", "Stadtwerke Musterstadt"])
		f = TransactionFilter()
		f.categoryID = food.id
		#expect(l.rows(in: .account(giro.id), filter: f).rows.map(\.name) == ["Bäckerei Gutbrot"])
	}

	@Test("The custom amount range compares the amount with its sign, with both ends included")
	func customAmountRange() throws {
		let giro = Account(position: 0, name: "Giro", kind: .giro, source: .offline)
		let l = Ledger(accounts: [giro], transactions: [150_00, -150_00, 500_00, 1_000_00, -1_500_00, -300_00].enumerated().map {
			Transaction(accountID: giro.id, bookingDate: Day(year: 2026, month: 11, day: 1 + $0.offset), amountMinor: $0.element, name: "Row \($0.offset)")
		})
		func shown(_ min: Decimal?, _ max: Decimal?) throws -> [Int64] {
			var f = TransactionFilter()
			f.amount = try #require(TransactionFilter.AmountFilter.custom(min: min, max: max))
			return l.rows(in: .account(giro.id), filter: f).rows.map(\.amountMinor).sorted()
		}
		#expect(try shown(100, 500) == [150_00, 500_00])
		#expect(try shown(-500, -100) == [-300_00, -150_00])
		#expect(try shown(1_000, nil) == [1_000_00])
		#expect(try shown(nil, -1_500) == [-1_500_00])
		#expect(TransactionFilter.AmountFilter.custom(min: -100, max: -500) == nil)
		#expect(TransactionFilter.AmountFilter.custom(min: -100, max: -100) != nil)
		#expect(TransactionFilter.AmountFilter.custom(min: nil, max: nil) == .all)
	}

	@Test("The custom amount range compares each row in its own currency, and its ends before rounding")
	func customAmountRangeCurrencies() throws {
		let group = AccountGroup(name: "All", position: 0)
		let accounts = ["EUR", "USD", "JPY", "KWD"].enumerated().map {
			Account(groupID: group.id, position: $0.offset, name: $0.element, kind: .giro, source: .offline, currency: $0.element)
		}
		let rows: [(Int, Int64)] = [(0, -150_00), (1, -150_00), (2, -150), (3, -150_000), (2, 150), (2, 15_000), (3, -15_000), (0, 100_00), (0, 101_00)]
		let l = Ledger(groups: [group], accounts: accounts, transactions: rows.enumerated().map { i, row in
			Transaction(accountID: accounts[row.0].id, bookingDate: Day(year: 2026, month: 11, day: 1 + i), amountMinor: row.1, currency: accounts[row.0].currency, name: "Row \(i)")
		})
		func shown(_ scope: LedgerScope, _ min: Decimal?, _ max: Decimal?) throws -> [String] {
			var f = TransactionFilter()
			f.amount = try #require(TransactionFilter.AmountFilter.custom(min: min, max: max))
			return l.rows(in: scope, filter: f).rows.map { "\($0.amountMinor) \($0.currency)" }.sorted()
		}
		#expect(try shown(.account(accounts[2].id), 100, 500) == ["150 JPY"])
		#expect(try shown(.account(accounts[3].id), -500, -100) == ["-150000 KWD"])
		#expect(try shown(.accountGroup(group.id), -500, -100) == ["-150 JPY", "-15000 EUR", "-15000 USD", "-150000 KWD"])
		// An end between two minor units lets only the amounts inside the range through.
		#expect(try shown(.account(accounts[0].id), Decimal(string: "100.004"), nil) == ["10100 EUR"])
		#expect(try shown(.account(accounts[0].id), nil, Decimal(string: "-150.004")) == [])
		#expect(try shown(.account(accounts[0].id), Decimal(string: "100.004"), Decimal(string: "100.006")) == [])
		#expect(try shown(.accountGroup(group.id), Decimal(string: "18446744073709551616"), nil) == [])
		#expect(try shown(.accountGroup(group.id), nil, Decimal(string: "-18446744073709551616")) == [])
		#expect(try shown(.account(accounts[2].id), Decimal(string: "-18446744073709551616"), Decimal(string: "18446744073709551616")) == ["-150 JPY", "150 JPY", "15000 JPY"])
		let huge = String(repeating: "9", count: 164)
		#expect(try shown(.accountGroup(group.id), AmountParser.decimal(from: huge), nil) == [])
		#expect(try shown(.accountGroup(group.id), nil, AmountParser.decimal(from: "-" + huge)) == [])
		let min = try #require(AmountParser.decimal(from: "1,2340"))
		let max = try #require(AmountParser.decimal(from: "1,2330"))
		#expect(TransactionFilter.AmountFilter.custom(min: min, max: max) == nil)
	}

	@Test("A filter on a category or an account that the ledger no longer has goes back to Show All")
	func dropMissingFilters() {
		let card = Account(position: 1, name: "Credit card", kind: .creditCard, source: .offline)
		let group = AccountGroup(name: "Private", position: 0)
		var f = TransactionFilter()
		f.categoryID = food.id
		f.account = .account(card.id)
		f.status = .unchecked
		var kept = f
		kept.dropMissing(in: Ledger(accounts: [giro, card], categories: [food]))
		#expect(kept == f)
		f.dropMissing(in: Ledger(accounts: [giro], categories: []))
		#expect(f.categoryID == nil)
		#expect(f.account == nil)
		#expect(f.status == .unchecked)
		f.account = .group(group.id)
		f.dropMissing(in: Ledger(groups: [group], accounts: [giro]))
		#expect(f.account == .group(group.id))
		// A group with the identifier of an account is not that account.
		f.account = .group(giro.id)
		f.dropMissing(in: Ledger(groups: [group], accounts: [giro]))
		#expect(f.account == nil)
	}

	@Test("Uncategorized holds every transaction without a category")
	func uncategorized() throws {
		let l = ledger()
		let d = try #require(l.defaultCategory)
		#expect(l.rows(in: .category(d.id)).rows.count == 3)
	}

	/// A giro with the hidden group "Transfers", whose subcategories "To savings" and "To depot" show in charts and whose
	/// subcategory "Fees" does not, and the visible group "Living" with the hidden "Rent" and the visible "Groceries".
	private struct HiddenFixture {
		let giro = Account(position: 0, name: "Giro", kind: .giro, source: .offline)
		let transfers = Domain.Category(position: 0, name: "Transfers", isGroup: true, showInDiagrams: false)
		let savings: Domain.Category
		let depot: Domain.Category
		let fees: Domain.Category
		let living = Domain.Category(position: 1, name: "Living", isGroup: true)
		let rent: Domain.Category
		let groceries: Domain.Category
		let day = Day(year: 2026, month: 11, day: 2)

		init() {
			savings = Domain.Category(parentID: transfers.id, position: 0, name: "To savings")
			depot = Domain.Category(parentID: transfers.id, position: 1, name: "To depot")
			fees = Domain.Category(parentID: transfers.id, position: 2, name: "Fees", showInDiagrams: false)
			rent = Domain.Category(parentID: living.id, position: 0, name: "Rent", showInDiagrams: false)
			groceries = Domain.Category(parentID: living.id, position: 1, name: "Groceries")
		}

		func row(_ c: Domain.Category, _ minor: Int64, pending: Bool = false, review: Bool = false) -> Transaction {
			Transaction(accountID: giro.id, bookingDate: day, amountMinor: minor, name: "Muster", isPending: pending, categoryID: c.id,
				categorizedBy: .manual, review: review ? .unclearBooking : nil)
		}

		func ledger(_ rows: [Transaction]) -> Ledger {
			Ledger(accounts: [giro], categories: [transfers, savings, depot, fees, living, rent, groceries], transactions: rows)
		}
	}

	/// charts "Categories can be left out of charts", "Nothing left to show": a hidden group above the view hides nothing in it.
	@Test("In the view of a hidden group, its visible subcategories fill the pie and the bars, and a hidden one inside stays out")
	func hiddenGroupShowsItsVisibleChildren() {
		let f = HiddenFixture()
		let l = f.ledger([f.row(f.savings, -200_000), f.row(f.depot, -50_000), f.row(f.fees, -500)])
		#expect(l.categoryTotals(of: l.transactions, below: f.transfers.id).map(\.category.name) == ["To savings", "To depot"])
		#expect(l.periodSums(of: l.transactions, period: .month, in: f.transfers.id).map(\.withdrawals) == [-250_000])
		// The view of an account leaves the whole hidden group out.
		#expect(l.categoryTotals(of: l.transactions).isEmpty)
		#expect(l.periodSums(of: l.transactions, period: .month).isEmpty)
	}

	/// charts "Categories can be left out of charts": "The category's own view still shows its bar chart."
	@Test("The view of a hidden category shows its bars, and the group above it leaves them out")
	func hiddenCategoryKeepsItsOwnBars() {
		let f = HiddenFixture()
		let l = f.ledger([f.row(f.rent, -95_000), f.row(f.groceries, -30_000)])
		let rentRows = l.transactions.filter { $0.categoryID == f.rent.id }
		#expect(l.periodSums(of: rentRows, period: .month, in: f.rent.id).map(\.withdrawals) == [-95_000])
		#expect(l.periodSums(of: l.transactions, period: .month, in: f.living.id).map(\.withdrawals) == [-30_000])
		#expect(l.categoryTotals(of: l.transactions, below: f.living.id).map(\.category.name) == ["Groceries"])
		#expect(l.categoryTotals(of: l.transactions).map(\.minorUnits) == [-30_000])
	}

	/// charts "Nothing left to show": the text names hidden categories only when a counted row falls in one.
	@Test("A chart hides rows only when a counted row falls in a hidden category of the view")
	func chartHidesRows() {
		let f = HiddenFixture()
		let netZero = f.ledger([f.row(f.groceries, 10_000), f.row(f.groceries, -10_000)])
		#expect(netZero.categoryTotals(of: netZero.transactions).map(\.minorUnits) == [0])
		#expect(!netZero.chartHidesRows(of: netZero.transactions))
		let onGroup = f.ledger([f.row(f.living, -10_000)])
		#expect(onGroup.categoryTotals(of: onGroup.transactions, below: f.living.id).isEmpty)
		#expect(!onGroup.chartHidesRows(of: onGroup.transactions, below: f.living.id))
		let rent = f.ledger([f.row(f.rent, -95_000)])
		#expect(rent.chartHidesRows(of: rent.transactions))
		#expect(rent.chartHidesRows(of: rent.transactions, below: f.living.id))
		// A pending row marked for review counts in no sum, so it hides nothing.
		let unclear = f.ledger([f.row(f.rent, -95_000, pending: true, review: true)])
		#expect(!unclear.chartHidesRows(of: unclear.transactions))
		// In the view of the hidden group "Transfers", only its hidden subcategory "Fees" hides rows.
		let transfers = f.ledger([f.row(f.savings, -200_000), f.row(f.fees, -500)])
		#expect(!transfers.chartHidesRows(of: transfers.transactions.filter { $0.categoryID == f.savings.id }, below: f.transfers.id))
		#expect(transfers.chartHidesRows(of: transfers.transactions, below: f.transfers.id))
	}

	@Test("A pending transaction counts in the balance, the bars, and the pie")
	func pendingCounts() {
		let giro = Account(position: 0, name: "Giro", kind: .giro, source: .offline, initialBalanceMinor: 100_000)
		let groceries = Domain.Category(position: 0, name: "Groceries")
		let today = Day(year: 2026, month: 11, day: 12)
		let l = Ledger(accounts: [giro], categories: [groceries], transactions: [
			Transaction(accountID: giro.id, bookingDate: today, amountMinor: -3_000, name: "Supermarkt", isPending: true,
				categoryID: groceries.id, categorizedBy: .manual),
		])
		#expect(l.computedBalance(of: giro).minorUnits == 97_000)
		#expect(l.balanceBars(accountIDs: [giro.id], range: DayRange(start: today, end: today)).map(\.minorUnits) == [97_000])
		#expect(l.categoryTotals(of: l.transactions).map(\.minorUnits) == [-3_000])
		#expect(l.categoryTotals(of: l.transactions).map(\.category.name) == ["Groceries"])
		#expect(l.periodSums(of: l.transactions, period: .month).map(\.withdrawals) == [-3_000])
		#expect(l.sidebarAmounts(today: today)[groceries.id]?.minorUnits == -3_000)
	}

	@Test("The initial balance that meets the bank balance subtracts the booked rows up to the day of that balance")
	func initialBalanceMeetingBankBalance() {
		let balanceDay = Day(year: 2026, month: 11, day: 10)
		let giro = Account(position: 0, name: "Giro", kind: .giro, source: .bank, bankBalanceMinor: 250_000, bankBalanceDate: balanceDay.date(),
			initialBalanceMinor: 99_999)
		func row(_ day: Int, _ minor: Int64, pending: Bool = false, currency: String = "EUR") -> Transaction {
			Transaction(accountID: giro.id, bookingDate: Day(year: 2026, month: 11, day: day), amountMinor: minor, currency: currency, name: "Row", isPending: pending)
		}
		let rows = [row(2, 100_000), row(5, -30_000), row(9, -3_000, pending: true), row(12, -5_000), row(6, -1_000, currency: "USD")]
		#expect(giro.initialBalanceMeetingBankBalance(of: rows) == 180_000)
		var offline = giro
		offline.bankBalanceMinor = nil
		#expect(offline.initialBalanceMeetingBankBalance(of: rows) == nil)
	}

	@Test("A bank balance that the booked rows miss proposes a calibration, and a pending row or an account without a bank access proposes none")
	func proposeCalibration() {
		let today = Day(year: 2026, month: 11, day: 12)
		func giro(initial: Int64) -> Account {
			Account(position: 0, name: "Giro", kind: .giro, source: .bank, bankBalanceMinor: 120_000, bankBalanceDate: today.date(),
				initialBalanceMinor: initial, initialBalanceIsSet: true)
		}
		func ledger(_ account: Account, pending: Bool) -> Ledger {
			var rows = [Transaction(accountID: account.id, bookingDate: Day(year: 2026, month: 11, day: 2), amountMinor: 100_000, name: "Beispiel GmbH")]
			if pending { rows.append(Transaction(accountID: account.id, bookingDate: today, amountMinor: -5_000, name: "Tankstelle Beispiel", isPending: true)) }
			return Ledger(accounts: [account], transactions: rows)
		}
		let unexplained = giro(initial: 25_000)
		#expect(ledger(unexplained, pending: false).computedBalance(of: unexplained, through: today).minorUnits == 125_000)
		#expect(ledger(unexplained, pending: false).proposedCalibration(of: unexplained, today: today, refresh: .idle)
			== CalibrationProposal(difference: Money(minorUnits: -5_000, currency: "EUR"), balanceToday: Money(minorUnits: 120_000, currency: "EUR")))

		let pending = giro(initial: 20_000)
		#expect(ledger(pending, pending: true).computedBalance(of: pending, through: today).minorUnits == 115_000)
		#expect(ledger(pending, pending: true).proposedCalibration(of: pending, today: today, refresh: .idle) == nil)

		var migrated = unexplained
		migrated.source = .migrated
		#expect(ledger(migrated, pending: false).proposedCalibration(of: migrated, today: today, refresh: .idle) == nil)
		var notSetYet = unexplained
		notSetYet.initialBalanceIsSet = false
		#expect(ledger(notSetYet, pending: false).proposedCalibration(of: notSetYet, today: today, refresh: .idle) == nil)
		var failed = unexplained
		failed.refreshError = RefreshError(failure: .network("The transactions could not be fetched."), date: Date())
		#expect(ledger(failed, pending: false).proposedCalibration(of: failed, today: today, refresh: .idle) == nil)
	}

	@Test("A row booked after the day of the bank balance proposes nothing, and a calibration fills in the balance of today and moves the initial balance by the difference")
	func calibrationOnTheDayOfTheBankBalance() {
		let today = Day(year: 2026, month: 11, day: 12)
		var giro = Account(position: 0, name: "Giro", kind: .giro, source: .bank, bankBalanceMinor: 50_000,
			bankBalanceDate: Day(year: 2026, month: 11, day: 10).date(), initialBalanceMinor: 70_000, initialBalanceIsSet: true)
		let rows = [
			Transaction(accountID: giro.id, bookingDate: Day(year: 2026, month: 11, day: 1), amountMinor: -20_000, name: "Wohnbau Musterstadt eG"),
			Transaction(accountID: giro.id, bookingDate: today, amountMinor: -3_000, name: "Bäckerei Gutbrot"),
		]
		#expect(Ledger(accounts: [giro], transactions: rows).computedBalance(of: giro, through: today).minorUnits == 47_000)
		#expect(Ledger(accounts: [giro], transactions: rows).proposedCalibration(of: giro, today: today, refresh: .idle) == nil)

		giro.bankBalanceMinor = 45_000
		let l = Ledger(accounts: [giro], transactions: rows)
		#expect(l.proposedCalibration(of: giro, today: today, refresh: .idle)?.balanceToday == Money(minorUnits: 42_000, currency: "EUR"))
		#expect(l.calibratedInitialBalance(of: giro, balanceToday: 42_000, today: today) == 65_000)
		giro.initialBalanceMinor = 65_000
		#expect(Ledger(accounts: [giro], transactions: rows).proposedCalibration(of: giro, today: today, refresh: .idle) == nil)
	}

	@Test("A pending transaction marked for review counts nowhere, a booked one marked for review counts")
	func pendingForReview() {
		let giro = Account(position: 0, name: "Giro", kind: .giro, source: .offline, initialBalanceMinor: 50_000)
		let groceries = Domain.Category(position: 0, name: "Groceries")
		func row(_ day: Int, pending: Bool) -> Transaction {
			Transaction(accountID: giro.id, bookingDate: Day(year: 2026, month: 11, day: day), amountMinor: -320, name: "Bäckerei Gutbrot",
				isPending: pending, categoryID: groceries.id, categorizedBy: .manual, review: .unclearBooking)
		}
		let l = Ledger(accounts: [giro], categories: [groceries], transactions: [row(12, pending: true), row(12, pending: true), row(13, pending: false)])
		let range = DayRange(start: Day(year: 2026, month: 11, day: 12), end: Day(year: 2026, month: 11, day: 13))
		#expect(l.computedBalance(of: giro).minorUnits == 49_680)
		#expect(l.balanceBars(accountIDs: [giro.id], range: range).map(\.minorUnits) == [50_000, 49_680])
		#expect(l.categoryTotals(of: l.transactions).map(\.minorUnits) == [-320])
		#expect(l.periodSums(of: l.transactions, period: .month).map(\.withdrawals) == [-320])
		#expect(l.sidebarAmounts(today: Day(year: 2026, month: 11, day: 13))[groceries.id]?.minorUnits == -320)
	}

	@Test("The sum of a list and its pending sum leave out a pending row marked for review")
	func listSumsWithReview() {
		let giro = Account(position: 0, name: "Giro", kind: .giro, source: .offline)
		func row(_ minor: Int64, pending: Bool, review: Bool) -> Transaction {
			Transaction(accountID: giro.id, bookingDate: Day(year: 2026, month: 11, day: 12), amountMinor: minor, name: "Café Beispiel",
				isPending: pending, review: review ? .unclearBooking : nil)
		}
		let rows = [row(-320, pending: true, review: true), row(-320, pending: true, review: true), row(-320, pending: false, review: true),
			row(-1_000, pending: true, review: false)]
		#expect(MoneySums(of: rows).amounts == [Money(minorUnits: -1_320, currency: "EUR")])
		#expect(MoneySums(of: rows.filter(\.isPending)).amounts == [Money(minorUnits: -1_000, currency: "EUR")])
	}

	@Test("A sum of zero has the currency of the view, also when every row is under review or the list is empty")
	func zeroSumInViewCurrency() {
		let travel = Account(position: 0, name: "Travel", kind: .giro, source: .offline, currency: "USD")
		func row(_ minor: Int64, _ currency: String) -> Transaction {
			Transaction(accountID: travel.id, bookingDate: Day(year: 2026, month: 11, day: 12), amountMinor: minor, currency: currency,
				name: "Diner Example", isPending: true, review: .unclearBooking)
		}
		let usd = [row(-1_250, "USD"), row(-1_250, "USD")]
		let eur = [row(-320, "EUR")]
		#expect(MoneySums(of: usd).shownAmounts(viewCurrency: "USD", rows: usd) == [Money(minorUnits: 0, currency: "USD")])
		#expect(MoneySums(of: []).shownAmounts(viewCurrency: "USD", rows: []) == [Money(minorUnits: 0, currency: "USD")])
		// A category in USD whose only rows are euro rows under review.
		#expect(MoneySums(of: eur).shownAmounts(viewCurrency: "USD", rows: eur) == [Money(minorUnits: 0, currency: "USD")])
		// A group has no currency of its own.
		#expect(MoneySums(of: usd).shownAmounts(viewCurrency: nil, rows: usd) == [Money(minorUnits: 0, currency: "USD")])
		#expect(MoneySums(of: []).shownAmounts(viewCurrency: nil, rows: []) == [Money(minorUnits: 0, currency: "EUR")])
		let counted = [Transaction(accountID: travel.id, bookingDate: Day(year: 2026, month: 11, day: 12), amountMinor: -500, currency: "USD", name: "Taxi")]
		#expect(MoneySums(of: counted).shownAmounts(viewCurrency: "USD", rows: counted) == [Money(minorUnits: -500, currency: "USD")])
	}

	@Test("A sum of zero of positions has the currency of the portfolio, then that of the first position, then the euro")
	func zeroSumOfPositions() {
		// A portfolio in USD without positions.
		#expect(MoneySums().shownAmounts(viewCurrency: "USD", firstRowCurrency: nil) == [Money(minorUnits: 0, currency: "USD")])
		// A group of portfolios, whose first position belongs to a portfolio in CHF and has no value.
		#expect(MoneySums().shownAmounts(viewCurrency: nil, firstRowCurrency: "CHF") == [Money(minorUnits: 0, currency: "CHF")])
		#expect(MoneySums().shownAmounts(viewCurrency: nil, firstRowCurrency: nil) == [Money(minorUnits: 0, currency: "EUR")])
		var sums = MoneySums()
		sums.add(Money(minorUnits: 123_450, currency: "USD"))
		#expect(sums.shownAmounts(viewCurrency: "EUR", firstRowCurrency: nil) == [Money(minorUnits: 123_450, currency: "USD")])
	}

	@Test("A balance counts only the rows in the currency of the account")
	func balanceInAccountCurrency() {
		let wallet = Account(position: 0, name: "Wallet", kind: .giro, source: .offline)
		let l = Ledger(accounts: [wallet], transactions: [
			Transaction(accountID: wallet.id, bookingDate: Day(year: 2026, month: 11, day: 2), amountMinor: 10_000, name: "Einzahlung"),
			Transaction(accountID: wallet.id, bookingDate: Day(year: 2026, month: 11, day: 3), amountMinor: 1_000, currency: "USD", name: "Diner New York"),
		])
		#expect(l.balance(of: wallet) == Money(minorUnits: 10_000, currency: "EUR"))
		#expect(l.computedBalance(of: wallet, through: Day(year: 2026, month: 11, day: 3)) == Money(minorUnits: 10_000, currency: "EUR"))
		#expect(l.dailyBalances(accountIDs: [wallet.id]).map(\.balance) == [10_000, 10_000])
	}

	@Test("An offline account adds its initial balance and its rows in its currency, pending rows included, except one marked for review")
	func offlineBalance() {
		let wallet = Account(position: 0, name: "Wallet", kind: .cash, source: .offline, initialBalanceMinor: 5_000)
		func row(_ day: Int, _ minor: Int64, currency: String = "EUR", pending: Bool = false, review: Bool = false) -> Transaction {
			Transaction(accountID: wallet.id, bookingDate: Day(year: 2026, month: 11, day: day), amountMinor: minor, currency: currency, name: "Row",
				isPending: pending, review: review ? .unclearBooking : nil)
		}
		let l = Ledger(accounts: [wallet], transactions: [
			row(2, 10_000), row(3, -480), row(4, -1_200), row(5, -1_000, pending: true), row(5, -500, pending: true, review: true),
			row(6, -1_000, currency: "USD"),
		])
		#expect(l.balance(of: wallet) == Money(minorUnits: 12_320, currency: "EUR"))
	}

	@Test("A manual row in an account with bank access counts in the daily balance and leaves the bank balance unchanged")
	func manualRowInBankAccount() {
		let deposit = Account(position: 0, name: "Festgeld", kind: .fixedTermDeposit, source: .bank, bankBalanceMinor: 1_000_000, initialBalanceIsSet: true)
		let start = Day(year: 2026, month: 3, day: 1)
		let l = Ledger(accounts: [deposit], transactions: [
			Transaction(accountID: deposit.id, bookingDate: start, amountMinor: 1_000_000, name: "Anlage", isManual: true),
		])
		#expect(l.balance(of: deposit) == Money(minorUnits: 1_000_000, currency: "EUR"))
		#expect(l.dailyBalances(accountIDs: [deposit.id]).first == DayBalance(day: start, balance: 1_000_000))
	}

	/// The state that a real first refresh leaves: the bank balance of `balanceMinor` on `balanceDay` and the initial balance derived from it.
	func afterFirstRefresh(_ account: Account, balanceMinor: Int64, on balanceDay: Day, calendar: Calendar) -> Ledger {
		var ledger = Ledger(accounts: [account])
		ledger.apply(reconcile(.refresh(RefreshResult(balance: Money(minorUnits: balanceMinor, currency: "EUR"), balanceDate: balanceDay.date(in: calendar),
			transactions: FetchedTransactions(rows: [], from: nil))), into: account, stored: [], deleted: [], rules: Categorizer(ledger: ledger),
			now: balanceDay.date(in: calendar)))
		return ledger
	}

	/// What the app does when it saves or deletes rows: the accounts first, then the rows.
	func commit(_ saved: [Transaction], deleting deleted: Set<UUID> = [], in ledger: inout Ledger, calendar: Calendar) throws {
		for a in try ledger.followingBankBalance(saving: saved, deleting: deleted, calendar: calendar) { ledger.upsert(a) }
		ledger.remove(transactionIDs: deleted)
		ledger.update(saved)
	}

	@Test("After a real first refresh, the initial balance of a fixed term deposit follows a manual deposit, so the computed balance keeps ending at the bank balance")
	func manualRowAfterFirstRefresh() throws {
		let calendar = Calendar(identifier: .gregorian)
		let balanceDay = Day(year: 2026, month: 11, day: 1)
		let fixed = Account(position: 0, name: "Festgeld", kind: .fixedTermDeposit, source: .bank)
		var ledger = afterFirstRefresh(fixed, balanceMinor: 1_000_000, on: balanceDay, calendar: calendar)
		var account = try #require(ledger.account(fixed.id))
		#expect(account.initialBalanceIsSet && account.initialBalanceIsDerived && account.initialBalanceMinor == 1_000_000)

		let deposit = Transaction(accountID: fixed.id, bookingDate: Day(year: 2026, month: 3, day: 1), amountMinor: 400_000, name: "Anlage", isManual: true)
		try commit([deposit], in: &ledger, calendar: calendar)
		account = try #require(ledger.account(fixed.id))
		#expect(account.initialBalanceMinor == 600_000)
		#expect(ledger.computedBalance(of: account, through: balanceDay) == Money(minorUnits: 1_000_000, currency: "EUR"))
		#expect(ledger.computedBalance(of: account, through: Day(year: 2026, month: 2, day: 28)) == Money(minorUnits: 600_000, currency: "EUR"))
		#expect(ledger.balance(of: account) == Money(minorUnits: 1_000_000, currency: "EUR"))
		#expect(ledger.proposedCalibration(of: account, today: balanceDay, refresh: .idle, calendar: calendar) == nil)

		// "Edit Transaction..." gives a manual row the corrected values and no original ones, so it stays only manual.
		var edited = deposit
		edited.edit(OriginalValues(bookingDate: deposit.bookingDate, valueDate: nil, amountMinor: 450_000, name: "Anlage", purpose: "Festgeld"))
		#expect(edited.isOnlyManual && edited.original == nil)
		try commit([edited], in: &ledger, calendar: calendar)
		#expect(ledger.account(fixed.id)?.initialBalanceMinor == 550_000)
		try commit([], deleting: [deposit.id], in: &ledger, calendar: calendar)
		#expect(ledger.account(fixed.id)?.initialBalanceMinor == 1_000_000)
		#expect(try ledger.followingBankBalance(saving: [], deleting: [deposit.id], calendar: calendar) == [])
	}

	@Test("A calibration difference that an older bank row left stays when the user adds, edits, and deletes a manual row")
	func manualRowsKeepCalibrationDifference() throws {
		let calendar = Calendar(identifier: .gregorian)
		let balanceDay = Day(year: 2026, month: 10, day: 10)
		let giro = Account(position: 0, name: "Giro", kind: .giro, source: .bank)
		var ledger = afterFirstRefresh(giro, balanceMinor: 100_000, on: balanceDay, calendar: calendar)
		// A later refresh brought a bank row of -7,00 € from before the first one, and the derived value stayed.
		ledger.update([Transaction(accountID: giro.id, bookingDate: Day(year: 2026, month: 9, day: 1), amountMinor: -700, name: "Fee", isFetched: true, sourceID: "TX-1")])
		func difference() throws -> Money? {
			ledger.proposedCalibration(of: try #require(ledger.account(giro.id)), today: balanceDay, refresh: .idle, calendar: calendar)?.difference
		}
		#expect(try difference() == Money(minorUnits: 700, currency: "EUR"))
		var kiosk = Transaction(accountID: giro.id, bookingDate: Day(year: 2026, month: 10, day: 3), amountMinor: -1_200, name: "Kiosk", isManual: true)
		try commit([kiosk], in: &ledger, calendar: calendar)
		#expect(ledger.account(giro.id)?.initialBalanceMinor == 101_200)
		#expect(try difference() == Money(minorUnits: 700, currency: "EUR"))
		kiosk.amountMinor = -2_000
		try commit([kiosk], in: &ledger, calendar: calendar)
		#expect(ledger.account(giro.id)?.initialBalanceMinor == 102_000)
		#expect(try difference() == Money(minorUnits: 700, currency: "EUR"))
		try commit([], deleting: [kiosk.id], in: &ledger, calendar: calendar)
		#expect(ledger.account(giro.id)?.initialBalanceMinor == 100_000)
		#expect(try difference() == Money(minorUnits: 700, currency: "EUR"))
	}

	@Test("A manual row that a file matched after it changed a derived initial balance gives the change back when the user deletes it")
	func matchedManualRowDeleted() throws {
		let calendar = Calendar(identifier: .gregorian)
		let balanceDay = Day(year: 2026, month: 10, day: 10)
		let giro = Account(position: 0, name: "Giro", kind: .giro, source: .bank)
		var ledger = afterFirstRefresh(giro, balanceMinor: 100_000, on: balanceDay, calendar: calendar)
		let kiosk = Transaction(accountID: giro.id, bookingDate: Day(year: 2026, month: 10, day: 3), amountMinor: -1_200, name: "Kiosk", isManual: true)
		try commit([kiosk], in: &ledger, calendar: calendar)
		#expect(ledger.account(giro.id)?.initialBalanceMinor == 101_200)
		let file = reconcile(.file([Transaction(accountID: giro.id, bookingDate: kiosk.bookingDate, amountMinor: -1_200, name: "KIOSK", fileIdentity: "csv:1")]),
			into: try #require(ledger.account(giro.id)), stored: ledger.transactions(ofAccount: giro.id), deleted: [], rules: Categorizer(ledger: ledger), now: Date())
		ledger.apply(file)
		#expect(ledger.transaction(kiosk.id)?.isOnlyManual == false)
		try commit([], deleting: [kiosk.id], in: &ledger, calendar: calendar)
		let account = try #require(ledger.account(giro.id))
		#expect(account.initialBalanceMinor == 100_000)
		#expect(ledger.computedBalance(of: account, through: balanceDay) == Money(minorUnits: 100_000, currency: "EUR"))
	}

	@Test("Only a manual row in the bank balance moves a derived initial balance, by its own booked amount")
	func rowsThatADerivedInitialBalanceCounts() throws {
		let calendar = Calendar(identifier: .gregorian)
		let balanceDay = Day(year: 2026, month: 11, day: 1)
		let derived = Account(position: 0, name: "Giro", kind: .giro, source: .bank, bankBalanceMinor: 50_000, bankBalanceDate: balanceDay.date(in: calendar),
			initialBalanceMinor: 50_000, initialBalanceIsSet: true, initialBalanceIsDerived: true)
		let unset = Account(position: 1, name: "New", kind: .giro, source: .bank, bankBalanceMinor: 50_000, bankBalanceDate: balanceDay.date(in: calendar))
		let wallet = Account(position: 2, name: "Wallet", kind: .cash, source: .offline)
		// The user typed 3.000,00 € in the account settings, so the value stays.
		let entered = Account(position: 3, name: "Entered", kind: .giro, source: .bank, bankBalanceMinor: 50_000, bankBalanceDate: balanceDay.date(in: calendar),
			initialBalanceMinor: 300_000, initialBalanceIsSet: true)
		let noBalanceDay = Account(position: 4, name: "No day", kind: .giro, source: .bank, bankBalanceMinor: 50_000,
			initialBalanceMinor: 50_000, initialBalanceIsSet: true, initialBalanceIsDerived: true)
		let l = Ledger(accounts: [derived, unset, wallet, entered, noBalanceDay])
		func row(_ account: Account, _ day: Day, manual: Bool = true, pending: Bool = false, currency: String = "EUR") -> Transaction {
			Transaction(accountID: account.id, bookingDate: day, amountMinor: -1_200, currency: currency, name: "Kiosk", isPending: pending,
				fileIdentity: manual ? nil : "csv:1", isManual: manual)
		}
		#expect(try l.followingBankBalance(saving: [row(derived, balanceDay)], calendar: calendar).map(\.initialBalanceMinor) == [51_200])
		// A row of a file or of the bank leaves the value for the calibration proposal.
		#expect(try l.followingBankBalance(saving: [row(derived, balanceDay, manual: false)], calendar: calendar) == [])
		#expect(try l.followingBankBalance(saving: [row(derived, balanceDay.adding(days: 1))], calendar: calendar) == [])
		#expect(try l.followingBankBalance(saving: [row(derived, balanceDay, pending: true)], calendar: calendar) == [])
		#expect(try l.followingBankBalance(saving: [row(derived, balanceDay, currency: "USD")], calendar: calendar) == [])
		#expect(try l.followingBankBalance(saving: [row(unset, balanceDay)], calendar: calendar) == [])
		#expect(try l.followingBankBalance(saving: [row(wallet, balanceDay)], calendar: calendar) == [])
		#expect(try l.followingBankBalance(saving: [row(entered, balanceDay)], calendar: calendar) == [])
		#expect(try l.followingBankBalance(saving: [row(noBalanceDay, balanceDay)], calendar: calendar) == [])
	}

	@Test("Mixed currencies: the sidebar sums the category currency, and the rows of the category add up per currency")
	func categorySumInCategoryCurrency() throws {
		let giro = Account(position: 0, name: "Giro", kind: .giro, source: .offline)
		let travel = Domain.Category(position: 0, name: "Travel")
		func row(_ minor: Int64, _ currency: String, _ name: String) -> Transaction {
			Transaction(accountID: giro.id, bookingDate: Day(year: 2026, month: 10, day: 5), amountMinor: minor, currency: currency, name: name,
				categoryID: travel.id, categorizedBy: .manual)
		}
		var l = Ledger(accounts: [giro], categories: [travel], transactions: [row(-20_000, "EUR", "Hotel"), row(-10_000, "EUR", "Bahn"), row(-5_000, "USD", "Taxi")])
		let today = Day(year: 2026, month: 11, day: 9)
		#expect(l.sidebarAmounts(today: today)[travel.id] == Money(minorUnits: -30_000, currency: "EUR"))
		let perCurrency = l.rows(in: .category(travel.id)).rows.reduce(into: MoneySums()) { $0.add($1.amount) }
		#expect(perCurrency.amounts == [Money(minorUnits: -30_000, currency: "EUR"), Money(minorUnits: -5_000, currency: "USD")])

		var inDollars = travel
		inDollars.currency = "USD"
		l.upsert(inDollars)
		#expect(l.sidebarAmounts(today: today)[travel.id] == Money(minorUnits: -5_000, currency: "USD"))
	}

	@Test("A euro group sums only the euro rows below it, also when a child holds a dollar row")
	func euroGroupLeavesOutDollarRows() {
		let giro = Account(position: 0, name: "Giro", kind: .giro, source: .offline)
		let living = Domain.Category(position: 0, name: "Living", isGroup: true)
		let rent = Domain.Category(parentID: living.id, position: 0, name: "Rent")
		let trips = Domain.Category(parentID: living.id, position: 1, name: "Trips", currency: "USD")
		func row(_ minor: Int64, _ currency: String, _ category: Domain.Category) -> Transaction {
			Transaction(accountID: giro.id, bookingDate: Day(year: 2026, month: 10, day: 5), amountMinor: minor, currency: currency, name: "Muster",
				categoryID: category.id, categorizedBy: .manual)
		}
		let l = Ledger(accounts: [giro], categories: [living, rent, trips],
			transactions: [row(-20_000, "EUR", rent), row(-1_000, "EUR", rent), row(-5_000, "USD", rent), row(-3_000, "USD", trips)])
		let amounts = l.sidebarAmounts(today: Day(year: 2026, month: 11, day: 9))
		#expect(amounts[living.id] == Money(minorUnits: -21_000, currency: "EUR"))
		#expect(amounts[rent.id] == Money(minorUnits: -21_000, currency: "EUR"))
		#expect(amounts[trips.id] == Money(minorUnits: -3_000, currency: "USD"))
	}

	@Test("The sum of a category for the current month counts a pending row and leaves out a pending row marked for review")
	func categorySumWithPendingRows() {
		let giro = Account(position: 0, name: "Giro", kind: .giro, source: .offline)
		let groceries = Domain.Category(position: 0, name: "Groceries", sidebarAmount: .currentMonth)
		func row(_ day: Int, _ minor: Int64, pending: Bool, review: Bool = false) -> Transaction {
			Transaction(accountID: giro.id, bookingDate: Day(year: 2026, month: 11, day: day), amountMinor: minor, name: "Supermarkt",
				isPending: pending, categoryID: groceries.id, categorizedBy: .manual, review: review ? .unclearBooking : nil)
		}
		let l = Ledger(accounts: [giro], categories: [groceries], transactions: [
			row(3, -8_000, pending: false), row(7, -4_000, pending: true), row(8, -500, pending: true, review: true),
		])
		let list = l.rows(in: .category(groceries.id)).rows
		#expect(list.count == 3)
		#expect(MoneySums(of: list).amounts == [Money(minorUnits: -12_000, currency: "EUR")])
		#expect(l.sidebarAmounts(today: Day(year: 2026, month: 11, day: 9))[groceries.id] == Money(minorUnits: -12_000, currency: "EUR"))
	}

	@Test("The sidebar shows the sum of the current month, the sum of a group, and no amount when the category says so")
	func sidebarAmount() {
		let giro = Account(position: 0, name: "Giro", kind: .giro, source: .offline)
		let today = Day(year: 2026, month: 11, day: 9)
		var groceries = Domain.Category(position: 0, name: "Groceries", sidebarAmount: .currentMonth)
		let living = Domain.Category(position: 1, name: "Living", isGroup: true, sidebarAmount: .totalSum)
		let rent = Domain.Category(parentID: living.id, position: 0, name: "Rent")
		let electricity = Domain.Category(parentID: living.id, position: 1, name: "Electricity")
		func row(_ month: Int, _ minor: Int64, _ category: Domain.Category) -> Transaction {
			Transaction(accountID: giro.id, bookingDate: Day(year: 2026, month: month, day: 2), amountMinor: minor, name: category.name,
				categoryID: category.id, categorizedBy: .manual)
		}
		let monthly = (1...12).flatMap { [row($0, -80_000, rent), row($0, -7_000, electricity)] }
		let l = Ledger(accounts: [giro], categories: [groceries, living, rent, electricity],
			transactions: [row(11, -12_000, groceries), row(10, -48_000, groceries)] + monthly)
		#expect(l.sidebarAmounts(today: today)[groceries.id] == Money(minorUnits: -12_000, currency: "EUR"))
		#expect(l.sidebarAmounts(today: today)[living.id] == Money(minorUnits: -1_044_000, currency: "EUR"))
		groceries.sidebarAmount = .none
		var hidden = l
		hidden.upsert(groceries)
		#expect(hidden.sidebarAmounts(today: today)[groceries.id] == nil)
	}

	@Test("Each of 300 categories in the sidebar sums its own rows, and a row of an unknown category counts in none")
	func sidebarAmountsOfManyCategories() {
		let giro = Account(position: 0, name: "Giro", kind: .giro, source: .offline)
		let categories = (0..<300).map { Domain.Category(position: $0, name: "Category \($0)", sidebarAmount: .totalSum) }
		let rows = categories.enumerated().map { i, c in
			Transaction(accountID: giro.id, bookingDate: Day(year: 2026, month: 11, day: 2), amountMinor: -Int64(i + 1), name: "Shop", categoryID: c.id, categorizedBy: .manual)
		}
		let unknown = Transaction(accountID: giro.id, bookingDate: Day(year: 2026, month: 11, day: 2), amountMinor: -5_000, name: "Shop", categoryID: UUID(), categorizedBy: .manual)
		let amounts = Ledger(accounts: [giro], categories: categories, transactions: rows + [unknown]).sidebarAmounts(today: Day(year: 2026, month: 11, day: 9))
		#expect(amounts.count == 300)
		#expect(amounts[categories[0].id] == Money(minorUnits: -1, currency: "EUR"))
		#expect(amounts[categories[299].id] == Money(minorUnits: -300, currency: "EUR"))
		#expect(categories.enumerated().allSatisfy { i, c in amounts[c.id] == Money(minorUnits: -Int64(i + 1), currency: "EUR") })
	}

	@Test("Current month, current quarter, and current year in the sidebar end at the last day of the period")
	func sidebarPeriodEnds() {
		let giro = Account(position: 0, name: "Giro", kind: .giro, source: .offline)
		let today = Day(year: 2026, month: 11, day: 9)
		let groceries = Domain.Category(position: 0, name: "Groceries", sidebarAmount: .currentMonth)
		let fuel = Domain.Category(position: 1, name: "Fuel", sidebarAmount: .currentQuarter)
		let insurance = Domain.Category(position: 2, name: "Insurance", sidebarAmount: .currentYear)
		let rows = [groceries, fuel, insurance].flatMap { category in
			[(Day(year: 2026, month: 11, day: 3), -1_000), (Day(year: 2026, month: 12, day: 1), -200), (Day(year: 2026, month: 8, day: 2), -30),
				(Day(year: 2027, month: 1, day: 2), -4)].map { day, minor in
				Transaction(accountID: giro.id, bookingDate: day, amountMinor: Int64(minor), name: category.name, categoryID: category.id, categorizedBy: .manual)
			}
		}
		let l = Ledger(accounts: [giro], categories: [groceries, fuel, insurance], transactions: rows)
		#expect(l.sidebarAmounts(today: today) == [
			groceries.id: Money(minorUnits: -1_000, currency: "EUR"), fuel.id: Money(minorUnits: -1_200, currency: "EUR"),
			insurance.id: Money(minorUnits: -1_230, currency: "EUR"),
		])
	}

	@Test("Each amount in the sidebar is the sum that the list of its category gives for its period and currency")
	func sidebarAmountsOfMixedLedger() {
		let giro = Account(position: 0, name: "Giro", kind: .giro, source: .offline)
		let card = Account(position: 1, name: "Card", kind: .creditCard, source: .offline, currency: "USD")
		let living = Domain.Category(position: 0, name: "Living", isGroup: true, sidebarAmount: .totalSum)
		let rent = Domain.Category(parentID: living.id, position: 0, name: "Rent", sidebarAmount: .currentMonth)
		let travel = Domain.Category(parentID: living.id, position: 1, name: "Travel", currency: "USD", sidebarAmount: .currentYear)
		let fuel = Domain.Category(position: 1, name: "Fuel", sidebarAmount: .currentQuarter)
		let hidden = Domain.Category(position: 2, name: "Hidden", sidebarAmount: .none)
		let refunds = Domain.Category(position: 3, name: "Refunds", sidebarAmount: .totalSum)
		let uncategorized = Domain.Category(position: 99, name: "Uncategorized", isDefault: true, sidebarAmount: .totalSum)
		func row(_ category: UUID?, _ year: Int, _ month: Int, _ day: Int, _ minor: Int64, _ currency: String = "EUR", pending: Bool = false,
			review: Bool = false) -> Transaction {
			Transaction(accountID: currency == "USD" ? card.id : giro.id, bookingDate: Day(year: year, month: month, day: day), amountMinor: minor,
				currency: currency, name: "Row", isPending: pending, categoryID: category, review: review ? .unclearBooking : nil)
		}
		let l = Ledger(accounts: [giro, card], categories: [living, rent, travel, fuel, hidden, refunds, uncategorized], transactions: [
			row(rent.id, 2026, 11, 3, -80_000), row(rent.id, 2026, 10, 3, -80_000), row(rent.id, 2026, 11, 5, -1_000, pending: true),
			row(rent.id, 2026, 11, 6, -500, pending: true, review: true),
			row(travel.id, 2026, 3, 10, -20_000, "USD"), row(travel.id, 2026, 4, 10, -3_000), row(travel.id, 2027, 1, 2, -700, "USD"),
			row(fuel.id, 2026, 12, 1, -4_000), row(fuel.id, 2026, 9, 30, -6_000),
			row(hidden.id, 2026, 11, 1, -900),
			row(refunds.id, 2026, 11, 1, 500), row(refunds.id, 2026, 11, 2, -500),
			row(nil, 2020, 1, 1, -50), row(UUID(), 2026, 11, 1, -77),
		])
		let amounts = l.sidebarAmounts(today: Day(year: 2026, month: 11, day: 9))
		#expect(amounts == [
			living.id: Money(minorUnits: -164_000, currency: "EUR"), rent.id: Money(minorUnits: -81_000, currency: "EUR"),
			travel.id: Money(minorUnits: -20_000, currency: "USD"), fuel.id: Money(minorUnits: -4_000, currency: "EUR"),
			uncategorized.id: Money(minorUnits: -50, currency: "EUR"),
		])
		let periods: [(Domain.Category, DayRange)] = [
			(living, .all), (rent, DayRange(start: Day(year: 2026, month: 11, day: 1), end: Day(year: 2026, month: 11, day: 30))),
			(travel, DayRange(start: Day(year: 2026, month: 1, day: 1), end: Day(year: 2026, month: 12, day: 31))),
			(fuel, DayRange(start: Day(year: 2026, month: 10, day: 1), end: Day(year: 2026, month: 12, day: 31))), (uncategorized, .all),
		]
		for (category, period) in periods {
			var f = TransactionFilter()
			f.period = period
			let list = MoneySums(of: l.rows(in: .category(category.id), filter: f).rows).byCurrency[category.currency]
			#expect(amounts[category.id]?.minorUnits == list)
		}
	}

	@Test("The ledger knows which accounts have transactions, also after a delete")
	func accountsWithTransactions() {
		let giro = Account(position: 0, name: "Giro", kind: .giro, source: .offline)
		let fixed = Account(position: 1, name: "Festgeld", kind: .fixedTermDeposit, source: .offline)
		let rent = Transaction(accountID: giro.id, bookingDate: Day(year: 2026, month: 11, day: 1), amountMinor: -95_000, name: "Miete")
		var ledger = Ledger(accounts: [giro, fixed], transactions: [rent])
		#expect(ledger.accountsWithTransactions == [giro.id])
		ledger.remove(transactionIDs: [rent.id])
		#expect(ledger.accountsWithTransactions.isEmpty)
	}

	@Test("A custom period applies both dates and refuses an end before the start")
	func customPeriod() {
		let start = Day(year: 2025, month: 4, day: 1), end = Day(year: 2026, month: 3, day: 31)
		#expect(PeriodChoice.custom(from: start, to: end) == .custom(start, end))
		#expect(PeriodChoice.custom(from: start, to: end)?.range() == DayRange(start: start, end: end))
		#expect(PeriodChoice.custom(from: start, to: start) == .custom(start, start))
		#expect(PeriodChoice.custom(from: Day(year: 2026, month: 10, day: 18), to: Day(year: 2025, month: 1, day: 1)) == nil)
		#expect(PeriodChoice.custom(from: start, to: start.adding(days: -1)) == nil)
	}

	@Test("A view resets the filter that its filter bar does not show")
	func resetHidden() {
		let groceries = Domain.Category(position: 0, name: "Groceries")
		let card = Account(position: 1, name: "Credit card", kind: .creditCard, source: .offline)
		let twelveMonths = DayRange(start: Day(year: 2025, month: 11, day: 10), end: Day(year: 2026, month: 11, day: 9))
		var f = TransactionFilter()
		f.categoryID = groceries.id
		f.account = .account(card.id)
		f.status = .unchecked
		f.period = twelveMonths
		for scope in [LedgerScope.account(giro.id), .accountGroup(UUID())] {
			var reset = f
			reset.resetHidden(in: scope)
			#expect(reset.account == nil)
			#expect(reset.categoryID == groceries.id)
			#expect(reset.status == .unchecked)
			#expect(reset.period == twelveMonths)
		}
		var reset = f
		reset.resetHidden(in: .category(food.id))
		#expect(reset.categoryID == nil)
		#expect(reset.account == .account(card.id))
		#expect(reset.status == .unchecked)
		#expect(reset.period == twelveMonths)
	}

	@Test("The pin saves the period and the filters, and not the search text")
	func savedFilterBar() throws {
		let start = Day(year: 2025, month: 4, day: 1), end = Day(year: 2026, month: 3, day: 31)
		var f = TransactionFilter()
		f.searchText = "amazon"
		f.period = DayRange(start: start, end: end)
		f.status = .unchecked
		f.amount = .range(min: -500, max: -100)
		f.categoryID = food.id
		f.account = .account(giro.id)
		let data = SavedFilterBar(period: .custom(start, end), filter: f).data
		let saved = try #require(SavedFilterBar(data: data))
		#expect(saved.period == .custom(start, end))
		var expected = f
		expected.searchText = ""
		#expect(saved.filter(in: ledger()) == expected)
	}

	@Test("The pin saves an amount range as its decimal ends, and the next launch reads them back")
	func savedAmountRange() throws {
		var f = TransactionFilter()
		f.status = .unchecked
		f.amount = .range(min: -500, max: try #require(Decimal(string: "-99.99")))
		let stored = try JSONSerialization.jsonObject(with: SavedFilterBar(period: .all, filter: f).data) as? NSDictionary
		#expect(stored == ["period": ["all": [:]], "status": ["unchecked": [:]], "amount": ["range": ["min": -500, "max": -99.99]]])
		let written = #"{"period":{"all":{}},"status":{"unchecked":{}},"amount":{"range":{"min":-500,"max":-99.99}}}"#
		let restored = try #require(SavedFilterBar(data: Data(written.utf8))).filter(in: ledger())
		#expect(restored.amount == .range(min: -500, max: Decimal(string: "-99.99")))
		#expect(restored.status == .unchecked)
	}

	@Test("A saved category or account that no longer exists comes back as Show All")
	func savedFilterBarOfRemovedEntries() throws {
		var f = TransactionFilter()
		f.status = .checked
		f.categoryID = UUID()
		f.account = .account(UUID())
		let saved = try #require(SavedFilterBar(data: SavedFilterBar(period: .all, filter: f).data))
		var expected = TransactionFilter()
		expected.status = .checked
		#expect(saved.filter(in: ledger()) == expected)
	}

	@Test("A saved \"30 Days\" counts from the day of the launch, and a saved month stays that month")
	func savedRelativePeriod() throws {
		let launch = Day(year: 2026, month: 11, day: 9)
		let days = try #require(SavedFilterBar(data: SavedFilterBar(period: .days30, filter: TransactionFilter()).data))
		#expect(days.filter(in: ledger(), today: launch).period == DayRange(start: Day(year: 2026, month: 10, day: 11), end: launch))
		let october = Day(year: 2025, month: 10, day: 1)
		let month = try #require(SavedFilterBar(data: SavedFilterBar(period: .month(october), filter: TransactionFilter()).data))
		#expect(month.filter(in: ledger(), today: launch).period == DayRange(start: october, end: Day(year: 2025, month: 10, day: 31)))
		#expect(SavedFilterBar(data: Data("pin".utf8)) == nil)
	}

	@Test("A saved custom period with its end before its start comes back with the dates swapped")
	func savedReversedCustomPeriod() throws {
		let start = Day(year: 2025, month: 4, day: 1), end = Day(year: 2026, month: 3, day: 31)
		let reversed = try #require(SavedFilterBar(data: SavedFilterBar(period: .custom(end, start), filter: TransactionFilter()).data))
		#expect(reversed.period == .custom(start, end))
		#expect(reversed.filter(in: ledger()).period == DayRange(start: start, end: end))
		let kept = try #require(SavedFilterBar(data: SavedFilterBar(period: .custom(start, start), filter: TransactionFilter()).data))
		#expect(kept.period == .custom(start, start))
	}
}
