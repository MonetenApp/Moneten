import Domain
import Foundation
import GRDB
import Testing
@testable import Storage
import StorageTestSupport

/// A database with every kind of object that the complete export holds. All names and numbers are made up.
@Suite("Complete export and import")
struct AllDataTests {
	@Test("Complete export preserves original file identities and tombstones")
	func fileIdentitiesRoundTrip() throws {
		defer { try? FileManager.default.removeItem(at: root) }
		let source = try emptyStore("file-source")
		let account = Account(position: 0, name: "Giro", kind: .giro, source: .offline)
		try source.save(accounts: [account])
		let file = Transaction(accountID: account.id, bookingDate: Day(year: 2026, month: 12, day: 1), amountMinor: -80_000,
			name: "Vermieter A", purpose: "Rent", isPending: true)
		var second = file
		second.id = UUID()
		second.bookingDate = second.bookingDate.adding(days: 7)
		_ = try source.merge(.file([file, second]), into: account.id, now: exportedAt)
		try source.deleteTransactions([second.id])
		let exported = try source.exportAllData(at: exportedAt)
		let target = try emptyStore("file-target")
		try target.importAllData(try AllData(json: exported.json()))
		let imported = try target.exportAllData(at: exportedAt)
		#expect(imported == exported)
		#expect(imported.transactions.map(\.fileIdentity) == ["file:1:8:202612016:-800003:EUR4:rent16:name:vermieter a0:0:"])
		#expect(imported.deletedTransactions.map(\.fileIdentity) == ["file:1:8:202612086:-800003:EUR4:rent16:name:vermieter a0:0:"])
	}

	@Test("A split round trip keeps literal amounts, categories, comments, VAT, and review reasons")
	func splitRoundTrip() throws {
		defer { try? FileManager.default.removeItem(at: root) }
		let source = try emptyStore("split-source")
		let account = Account(position: 0, name: "Giro", kind: .giro, source: .offline, initialBalanceMinor: 100_000)
		let groceries = Domain.Category(position: 0, name: "Groceries")
		let household = Domain.Category(position: 1, name: "Household")
		let drinks = Domain.Category(position: 2, name: "Drinks")
		try source.save(accounts: [account], categories: [groceries, household, drinks])
		let original = Transaction(accountID: account.id, bookingDate: Day(year: 2026, month: 11, day: 3), amountMinor: -11900,
			name: "Example Market", comment: "Invoice", categoryID: groceries.id, categorizedBy: .manual, review: .unclearBooking, createdAt: exportedAt)
		let corrected = Transaction(accountID: account.id, bookingDate: Day(year: 2026, month: 11, day: 4), amountMinor: -8500,
			name: "Example Shop", review: .splitUndone, createdAt: exportedAt)
		try source.save([original, corrected])
		let parts = [
			SplitPart(transactionID: original.id, position: 0, amountMinor: -10000, categoryID: household.id, comment: "Net goods", vat: VATShare(role: .net, rate: VATRate(hundredths: 1900))),
			SplitPart(transactionID: original.id, position: 1, amountMinor: -1900, categoryID: drinks.id, comment: "Tax", vat: VATShare(role: .tax, rate: VATRate(hundredths: 1900)))]
		try source.replaceParts(of: original.id, with: parts)
		let file = try source.exportAllData(at: exportedAt).json()
		let json = try #require(try JSONSerialization.jsonObject(with: file) as? [String: Any])
		#expect(json["version"] as? Int == 4)
		let entries = json["splitParts"] as? [[String: Any]] ?? []
		#expect(entries.compactMap { $0["amount"] as? String } == ["-100.00", "-19.00"])
		#expect(entries.compactMap { ($0["vat"] as? [String: Any])?["rate"] as? Int } == [1900, 1900])
		let rows = try #require(json["transactions"] as? [[String: Any]])
		#expect(rows.compactMap { $0["review"] as? String } == ["unclearBooking", "splitUndone"])
		#expect(rows.allSatisfy { $0["needsReview"] == nil })
		let target = try emptyStore("split-target")
		try target.importAllData(try AllData(json: file))
		let reopened = try Vault(testing: DataFolder(root: root.appendingPathComponent("split-target"))).open(password: "korrekt-pferd-batterie-heftklammer")
		let ledger = try reopened.loadLedger()
		#expect(ledger.transactions.count == 2)
		#expect(ledger.transaction(original.id) == original)
		#expect(ledger.transaction(corrected.id) == corrected)
		let saved = ledger.parts(of: original.id)
		#expect(saved.map(\.id) == parts.map(\.id))
		#expect(saved.map(\.transactionID) == [original.id, original.id])
		#expect(saved.map(\.position) == [0, 1])
		#expect(saved.map(\.amountMinor) == [-10000, -1900])
		#expect(saved.map(\.categoryID) == [household.id, drinks.id])
		#expect(saved.map(\.comment) == ["Net goods", "Tax"])
		#expect(saved.map { $0.vat?.role } == [.net, .tax])
		#expect(saved.map { $0.vat?.rate.hundredths } == [1900, 1900])
		#expect(ledger.rows(in: .account(account.id)).rows.allSatisfy { $0.currency == "EUR" })
		#expect(ledger.computedBalance(of: account).minorUnits == 79600)
	}

	@Test("A v1 file with needsReview true imports as unclearBooking")
	func v1Review() throws {
		defer { try? FileManager.default.removeItem(at: root) }
		let file = Data(#"""
		{"format":"moneten-export","version":1,"exportedAt":"2026-11-14T23:46:40.000Z",
		"accountGroups":[],"accesses":[],"categories":[],"deletedTransactions":[],"portfolioValues":[],"holdings":[],
		"accounts":[{"id":"00000000-0000-0000-0000-000000000001","position":0,"name":"Giro","kind":"giro","source":"offline","currency":"EUR","initialBalance":"0.00","initialBalanceIsSet":true,"isClosed":false,"refreshInterval":"onlyManually"}],
		"transactions":[
		{"id":"00000000-0000-0000-0000-000000000002","accountID":"00000000-0000-0000-0000-000000000001","bookingDate":"2026-11-03","amount":"-20.00","currency":"EUR","name":"Example A","purpose":"","isChecked":false,"isPending":true,"categorizedBy":"none","isNew":false,"needsReview":true,"isFetched":false,"createdAt":"2026-11-14T23:46:40.000Z"},
		{"id":"00000000-0000-0000-0000-000000000003","accountID":"00000000-0000-0000-0000-000000000001","bookingDate":"2026-11-04","amount":"-30.00","currency":"EUR","name":"Example B","purpose":"","isChecked":false,"isPending":false,"categorizedBy":"none","isNew":false,"needsReview":false,"isFetched":false,"createdAt":"2026-11-14T23:46:40.000Z"}]}
		"""#.utf8)
		let target = try emptyStore("v1-target")
		try target.importAllData(try AllData(json: file))
		let reopened = try Vault(testing: DataFolder(root: root.appendingPathComponent("v1-target"))).open(password: "korrekt-pferd-batterie-heftklammer")
		let ledger = try reopened.loadLedger()
		let pending = try #require(ledger.transactions.first { $0.isPending })
		let booked = try #require(ledger.transactions.first { !$0.isPending })
		#expect(pending.amountMinor == -2000)
		#expect(pending.review == .unclearBooking)
		#expect(booked.amountMinor == -3000)
		#expect(booked.review == nil)
		#expect(ledger.parts(of: pending.id).isEmpty && ledger.parts(of: booked.id).isEmpty)
	}

	@Test("An export with a refresh error writes version 3 or later and the failure without its text, so a reader of version 2 asks for a newer app")
	func refreshErrorVersion() throws {
		let file = try filledStore().exportAllData(at: exportedAt).json()
		let json = try #require(try JSONSerialization.jsonObject(with: file) as? [String: Any])
		#expect(json["version"] as? Int == 4)
		let accounts = try #require(json["accounts"] as? [[String: Any]])
		let error = try #require(accounts.compactMap { $0["refreshError"] as? [String: Any] }.first)
		#expect(error["message"] == nil && error["code"] == nil)
		let failure = try #require(error["failure"] as? [String: Any])
		#expect(failure["reason"] as? String == "pinRejected")
		#expect(failure["code"] as? String == "9931")
	}

	@Test("A version-2 file with the text and the code of a refresh error imports them as an answer of the bank")
	func v2RefreshError() throws {
		defer { try? FileManager.default.removeItem(at: root) }
		let file = Data(#"""
		{"format":"moneten-export","version":2,"exportedAt":"2026-11-14T23:46:40.000Z",
		"accountGroups":[],"accesses":[],"categories":[],"transactions":[],"splitParts":[],"deletedTransactions":[],"portfolioValues":[],"holdings":[],
		"accounts":[{"id":"00000000-0000-0000-0000-000000000001","position":0,"name":"Giro","kind":"giro","source":"offline","currency":"EUR","initialBalance":"0.00","initialBalanceIsSet":true,"isClosed":false,"refreshInterval":"onlyManually",
		"refreshError":{"message":"Die PIN ist falsch.","code":"9931","date":"2026-11-14T23:46:40.000Z","notices":[],"waitsForUser":true}}]}
		"""#.utf8)
		let target = try emptyStore("v2-target")
		try target.importAllData(try AllData(json: file))
		let reopened = try Vault(testing: DataFolder(root: root.appendingPathComponent("v2-target"))).open(password: "korrekt-pferd-batterie-heftklammer")
		let error = try #require(try reopened.loadLedger().accounts.first?.refreshError)
		#expect(error.failure == .bank(BankMessage(code: "9931", text: "Die PIN ist falsch.")))
		#expect(error.waitsForUser)
	}

	@Test("An invalid split import writes nothing", arguments: ["transaction", "category", "pending", "id", "transaction-id", "position", "negative-position", "one", "zero", "sum", "overflow"])
	func invalidSplits(_ kind: String) throws {
		defer { try? FileManager.default.removeItem(at: root) }
		let account = Account(position: 0, name: "Giro", kind: .giro, source: .offline)
		var original = Transaction(accountID: account.id, bookingDate: Day(year: 2026, month: 11, day: 3), amountMinor: -11900, name: "Example")
		var parts = [SplitPart(transactionID: original.id, position: 0, amountMinor: -10000), SplitPart(transactionID: original.id, position: 1, amountMinor: -1900)]
		switch kind {
		case "transaction": parts[0].transactionID = UUID()
		case "category": parts[0].categoryID = UUID()
		case "pending": original.isPending = true
		case "id": parts[1].id = parts[0].id
		case "transaction-id": parts[0].id = original.id
		case "position": parts[1].position = 0
		case "negative-position": parts[0].position = -1
		case "one": parts = [SplitPart(transactionID: original.id, position: 0, amountMinor: -11900)]
		case "zero": parts[0].amountMinor = 0; parts[1].amountMinor = -11900
		case "sum": parts[1].amountMinor = -1800
		default: parts[0].amountMinor = Int64.max; parts[1].amountMinor = Int64.max
		}
		var data = AllData(exportedAt: exportedAt, accounts: [account], transactions: [original])
		data.splitParts = parts
		let target = try emptyStore("invalid")
		let before = try target.exportAllData(at: exportedAt)
		#expect(throws: AllData.ReadError.self) { try target.importAllData(data) }
		#expect(try target.exportAllData(at: exportedAt) == before)
		#expect(throws: AllData.ReadError.self) { try target.importAllData(try AllData(json: data.json())) }
		#expect(try target.exportAllData(at: exportedAt) == before)
	}

	@Test("Malformed v2 split fields and unknown review reasons are refused", arguments: ["missing", "null", "review", "role", "rate-zero", "rate-negative", "rate-text", "amount", "transaction", "category", "id", "transaction-id", "position", "negative-position", "pending", "one", "zero", "sum", "overflow"])
	func malformedSplitFile(_ kind: String) throws {
		defer { try? FileManager.default.removeItem(at: root) }
		let account = Account(position: 0, name: "Giro", kind: .giro, source: .offline)
		let original = Transaction(accountID: account.id, bookingDate: Day(year: 2026, month: 11, day: 3), amountMinor: -11900, name: "Example")
		let parts = [SplitPart(transactionID: original.id, position: 0, amountMinor: -10000), SplitPart(transactionID: original.id, position: 1, amountMinor: -1900)]
		let data = AllData(accounts: [account], transactions: [original], splitParts: parts)
		var json = try #require(JSONSerialization.jsonObject(with: data.json()) as? [String: Any])
		var entries = try #require(json["splitParts"] as? [[String: Any]])
		var rows = try #require(json["transactions"] as? [[String: Any]])
		switch kind {
		case "review": rows[0]["review"] = "futureReason"
		case "role": entries[0]["vat"] = ["role": "gross", "rate": 1900]
		case "rate-zero": entries[0]["vat"] = ["role": "net", "rate": 0]
		case "rate-negative": entries[0]["vat"] = ["role": "net", "rate": -1]
		case "rate-text": entries[0]["vat"] = ["role": "net", "rate": "19"]
		case "amount": entries[0]["amount"] = "-100.001"
		case "transaction": entries[0]["transactionID"] = UUID().uuidString
		case "category": entries[0]["categoryID"] = UUID().uuidString
		case "id": entries[1]["id"] = entries[0]["id"]
		case "transaction-id": entries[0]["id"] = original.id.uuidString
		case "position": entries[1]["position"] = 0
		case "negative-position": entries[0]["position"] = -1
		case "pending": rows[0]["isPending"] = true
		case "one": entries.removeLast(); entries[0]["amount"] = "-119.00"
		case "zero": entries[0]["amount"] = "0.00"; entries[1]["amount"] = "-119.00"
		case "sum": entries[1]["amount"] = "-18.00"
		case "overflow": entries[0]["amount"] = "92233720368547758.07"; entries[1]["amount"] = "92233720368547758.07"
		default: break
		}
		json["transactions"] = rows
		json["splitParts"] = kind == "null" ? NSNull() : entries
		if kind == "missing" { json.removeValue(forKey: "splitParts") }
		let target = try emptyStore("malformed")
		let before = try target.exportAllData(at: exportedAt)
		#expect(throws: AllData.ReadError.self) { try target.importAllData(AllData(json: JSONSerialization.data(withJSONObject: json))) }
		#expect(try target.exportAllData(at: exportedAt) == before)
	}

	@Test("Split amounts use the original currency and keep the bounds of Int64 that have a magnitude", arguments: ["EUR", "JPY", "KWD"])
	func splitCurrency(_ currency: String) throws {
		let original = Transaction(accountID: UUID(), bookingDate: Day(year: 2026, month: 11, day: 3), amountMinor: -1, currency: currency, name: "Example")
		let parts = [SplitPart(transactionID: original.id, position: 0, amountMinor: -Int64.max), SplitPart(transactionID: original.id, position: 1, amountMinor: Int64.max - 1)]
		let data = AllData(transactions: [original], splitParts: parts)
		let file = try data.json()
		let json = try #require(JSONSerialization.jsonObject(with: file) as? [String: Any])
		let entries = try #require(json["splitParts"] as? [[String: Any]])
		let expected = currency == "JPY" ? ["-9223372036854775807", "9223372036854775806"] : currency == "KWD" ? ["-9223372036854775.807", "9223372036854775.806"] : ["-92233720368547758.07", "92233720368547758.06"]
		#expect(entries.compactMap { $0["amount"] as? String } == expected)
		#expect(try AllData(json: file).splitParts.map(\.amountMinor) == [-Int64.max, Int64.max - 1])
	}

	/// Int64.min has no magnitude, so an absolute value or a negation of it would stop the app (issue #324).
	@Test("A restored split part, deleted row, or balance of Int64.min is refused")
	func smallestAmount() throws {
		let original = Transaction(accountID: UUID(), bookingDate: Day(year: 2026, month: 11, day: 3), amountMinor: -1, name: "Example")
		let parts = [SplitPart(transactionID: original.id, position: 0, amountMinor: .min), SplitPart(transactionID: original.id, position: 1, amountMinor: .max)]
		#expect(throws: AllData.ReadError.damaged("at splitParts[0], the amount \"-92233720368547758.08\" is not a decimal number with the decimal places of EUR")) {
			try AllData(json: try AllData(transactions: [original], splitParts: parts).json())
		}
		let deleted = DeletedTransaction(Transaction(accountID: UUID(), bookingDate: Day(year: 2026, month: 11, day: 3), amountMinor: .min, name: "Example"), deletedAt: exportedAt)
		#expect(throws: AllData.ReadError.self) { try AllData(json: try AllData(deletedTransactions: [deleted]).json()) }
		let account = Account(position: 0, name: "Giro", kind: .giro, source: .offline, initialBalanceMinor: .min)
		#expect(throws: AllData.ReadError.self) { try AllData(json: try AllData(accounts: [account]).json()) }
	}

	let root = FileManager.default.temporaryDirectory.appendingPathComponent("MonetenTests-\(UUID().uuidString)")
	let exportedAt = Date(timeIntervalSince1970: 1_794_700_000)

	func emptyStore(_ name: String) throws -> Store {
		try Vault(testing: DataFolder(root: root.appendingPathComponent(name))).create(password: "korrekt-pferd-batterie-heftklammer", starterCategories: [])
	}

	func filledStore() throws -> Store {
		let store = try emptyStore("source")
		let privat = AccountGroup(name: "Private", position: 0)
		let household = AccountGroup(name: "Household", parentID: privat.id, position: 0)
		let food = Domain.Category(position: 0, name: "Food", color: "#3478F6", rule: "REWE OR \"Bäckerei*\"")
		let pets = Domain.Category(position: 1, name: "Pets", symbol: "pawprint")
		let uncategorized = Domain.Category(position: 1_000, name: "Uncategorized", isDefault: true)
		let migrated = Account(groupID: household.id, position: 0, name: "Haushalt", kind: .giro, source: .migrated, iban: "DE02120300000000202051",
			bankBalanceMinor: 123_456, bankBalanceDate: Date(timeIntervalSince1970: 1_794_600_000.25), initialBalanceMinor: 100_000, initialBalanceIsSet: true,
			comment: "Gemeinsames Konto", sourceID: "moneymoney:A1", color: "#E88A2E")
		let offline = Account(groupID: privat.id, position: 1, name: "Bargeld", kind: .cash, source: .offline, initialBalanceMinor: 5_000)
		let portfolio = Account(position: 2, name: "Depot", kind: .portfolio, source: .offline, bankBalanceMinor: 1_000_000,
			bankBalanceDate: Date(timeIntervalSince1970: 1_794_600_000))
		try store.save(groups: [privat, household], accounts: [migrated, offline, portfolio], categories: [food, pets, uncategorized])
		let access = Access(source: .fints(bankCode: "12030000", url: URL(string: "https://banking.example.org/fints")!), bankName: "Musterbank", loginName: "erika77")
		let giro = Account(groupID: privat.id, position: 2, name: "Girokonto", kind: .giro, source: .bank, iban: "DE02120300000000202051", bankBalanceMinor: 250_000,
			refreshedAt: Date(timeIntervalSince1970: 1_794_650_000.5),
			refreshError: RefreshError(failure: .pinRejected(BankMessage(code: "9931", text: "Die PIN ist falsch.")), date: Date(timeIntervalSince1970: 1_794_660_000), notices: ["Wartung am Sonntag"]),
			refreshInterval: .onceADay, missesOlderTransactions: true, otherBankBalances: [Money(minorUnits: 3_500, currency: "USD")], bonusPoints: 12_400)
		let linked = try store.add(access, state: AccessState(Data("bank parameters".utf8)), accounts: [giro])
		try store.savePIN(Secret("24680"), for: linked.access.id)
		let bank = try #require(linked.accounts.first)
		let rows = [
			Transaction(accountID: migrated.id, bookingDate: Day(year: 2026, month: 11, day: 2), valueDate: Day(year: 2026, month: 11, day: 3), amountMinor: -123_456,
				name: "Stadtwerke Musterstadt", purpose: "Abschlag\nNovember", counterpartyIBAN: "DE02120300000000202051", counterpartyBIC: "BYLADEM1001",
				bookingText: "Lastschrift", endToEndReference: "E2E-1", mandateReference: "M-1", creditorID: "DE98ZZZ09999999999", comment: "Strom",
				isChecked: true, categoryID: pets.id, categorizedBy: .manual, sourceID: "moneymoney:1", createdAt: Date(timeIntervalSince1970: 1_794_600_001.123), returnReason: "AC04"),
			Transaction(accountID: migrated.id, bookingDate: Day(year: 2026, month: 11, day: 4), amountMinor: -1_000, name: "Kiosk", isPending: true,
				categoryID: food.id, categorizedBy: .rule, isNew: true, review: .unclearBooking, sourceID: "moneymoney:2"),
			{
				var t = Transaction(accountID: bank.id, bookingDate: Day(year: 2026, month: 11, day: 5), amountMinor: -2_000, currency: "USD", name: "Diner New York",
					isFetched: true, sourceID: "bank-4711", originalAmount: Money(minorUnits: -2_468, currency: "KWD"), deviatingParty: "Diner Beispiel")
				t.edit(OriginalValues(bookingDate: Day(year: 2026, month: 11, day: 4), valueDate: Day(year: 2026, month: 11, day: 6), amountMinor: -2_050,
					name: "Diner", purpose: "Dinner with a client"))
				return t
			}(),
			Transaction(accountID: offline.id, bookingDate: Day(year: 2026, month: 11, day: 6), amountMinor: -480, name: "Bäckerei Gutbrot"),
		]
		try store.save(rows)
		try store.deleteTransactions([rows[3].id])
		try store.write { db in
			try HoldingRecord(Holding(accountID: portfolio.id, security: Security(name: "Beispiel Welt ETF", isin: "DE0000000001"), quantity: Decimal(string: "12.345")!,
				quote: Quote(amount: Decimal(string: "81.2")!, currency: "EUR", day: Day(year: 2026, month: 11, day: 13)),
				marketValue: Money(minorUnits: 100_241, currency: "EUR"), purchasePrice: Quote(amount: 70, currency: "EUR"),
				exchangeRate: ExchangeRate(base: "EUR", quoted: "USD", rate: Decimal(string: "1.0832")!), sourceAssetClass: .funds, userAssetClass: .etfs)).insert(db)
		}
		var power = TransactionFilter()
		power.searchText = "name:Stadtwerke"
		power.status = .checked
		power.amount = .range(min: -2_000, max: Decimal(string: "-0.5"))
		power.categoryID = pets.id
		power.account = .account(migrated.id)
		_ = try store.appendSavedSearch(name: "Strom", period: .custom(Day(year: 2026, month: 10, day: 1), Day(year: 2026, month: 11, day: 30)), filter: power)
		var recent = TransactionFilter()
		recent.amount = .withdrawals
		recent.account = .group(household.id)
		_ = try store.appendSavedSearch(name: "Last 30 days", period: .days30, filter: recent)
		return store
	}

	@Test("A complete export imports into an empty database, and its export equals the first file apart from the export date")
	func roundTrip() throws {
		let source = try filledStore()
		_ = try source.loadLedger()
		let first = try source.exportAllData(at: exportedAt)
		let file = try first.json()
		let target = try emptyStore("target")
		try target.importAllData(try AllData(json: file))
		let second = try target.exportAllData(at: Date(timeIntervalSince1970: 1_794_800_000))
		#expect(try second.json() != file)
		var same = second
		same.exportedAt = exportedAt
		#expect(try same.json() == file)
		#expect(second.accounts.count == 4 && second.transactions.count == 3 && second.categories.count == 3 && second.groups.count == 2)
		#expect(second.deletedTransactions.count == 1 && second.portfolioValues.count == 1 && second.holdings.count == 1 && second.accesses.count == 1)

		let before = try source.loadLedger()
		let after = try target.loadLedger()
		#expect(after.transactions.first { $0.sourceID == "moneymoney:1" }?.returnReason == "AC04")
		#expect(after.transactions.first { $0.sourceID == "bank-4711" }?.originalAmount == Money(minorUnits: -2_468, currency: "KWD"))
		#expect(after.transactions.first { $0.sourceID == "bank-4711" }?.deviatingParty == "Diner Beispiel")
		#expect(after.transactions.first { $0.sourceID == "moneymoney:1" }?.originalAmount == nil)
		#expect(after.transactions.first { $0.sourceID == "bank-4711" }?.original == OriginalValues(bookingDate: Day(year: 2026, month: 11, day: 5),
			valueDate: nil, amountMinor: -2_000, name: "Diner New York", purpose: ""))
		#expect(Set(after.accounts) == Set(before.accounts))
		#expect(Set(after.groups) == Set(before.groups))
		#expect(Set(after.categories) == Set(before.categories))
		#expect(Set(after.transactions) == Set(before.transactions))
		#expect(after.holdings(of: after.accounts.map(\.id)) == before.holdings(of: before.accounts.map(\.id)))
		let depot = try #require(before.accounts.first { $0.name == "Depot" })
		#expect(after.portfolioValues(of: depot.id) == before.portfolioValues(of: depot.id))
		#expect(Set(try target.deletedTransactions()) == Set(try source.deletedTransactions()))
		#expect(try target.savedSearches() == source.savedSearches())
		#expect(try target.savedSearches().map(\.name) == ["Strom", "Last 30 days"])
	}

	@Test("A saved search keeps its period, its filters, and the ends of its amount range as decimal text")
	func savedSearchFields() throws {
		let text = String(decoding: try filledStore().exportAllData(at: exportedAt).json(), as: UTF8.self)
		#expect(text.contains(#""searchText" : "name:Stadtwerke""#))
		#expect(text.contains(#""start" : "2026-10-01""#) && text.contains(#""end" : "2026-11-30""#) && text.contains(#""kind" : "days30""#))
		#expect(text.contains(#""min" : "-2000""#) && text.contains(#""max" : "-0.5""#) && text.contains(#""status" : "checked""#))
		let json = try JSONSerialization.jsonObject(with: Data(text.utf8)) as! [String: Any]
		let searches = json["savedSearches"] as! [[String: Any]]
		#expect(searches[0]["accountID"] is String && searches[0]["accountGroupID"] == nil)
		#expect(searches[1]["accountGroupID"] is String && searches[1]["accountID"] == nil)
	}

	@Test("A saved search with both an account and an account group is refused with its place")
	func savedSearchWithAccountAndGroup() throws {
		var json = try JSONSerialization.jsonObject(with: try filledStore().exportAllData(at: exportedAt).json()) as! [String: Any]
		var searches = json["savedSearches"] as! [[String: Any]]
		searches[1]["accountID"] = UUID().uuidString
		json["savedSearches"] = searches
		#expect(throws: AllData.ReadError.damaged("at savedSearches[1], the saved search has both an account and an account group")) {
			try AllData(json: try JSONSerialization.data(withJSONObject: json))
		}
	}

	@Test("The complete import numbers the saved searches from 0 in their order, so the next saved search goes last")
	func savedSearchPositions() throws {
		var json = try JSONSerialization.jsonObject(with: try filledStore().exportAllData(at: exportedAt).json()) as! [String: Any]
		var searches = json["savedSearches"] as! [[String: Any]]
		searches[0]["position"] = Int.max
		searches[1]["position"] = 5
		json["savedSearches"] = searches
		let target = try emptyStore("target")
		try target.importAllData(try AllData(json: try JSONSerialization.data(withJSONObject: json)))
		try #require(try target.savedSearches().map(\.position) == [0, 1])
		#expect(try target.savedSearches().map(\.name) == ["Last 30 days", "Strom"])
		var f = TransactionFilter()
		f.searchText = "Miete"
		let rent = try target.appendSavedSearch(name: "Rent", period: .all, filter: f)
		#expect(rent.position == 2)
		#expect(try target.savedSearches().map(\.name) == ["Last 30 days", "Strom", "Rent"])
	}

	@Test("A saved search with an unknown period or an empty amount range is refused with its place", arguments: ["period", "amount"])
	func damagedSavedSearch(_ field: String) throws {
		var json = try JSONSerialization.jsonObject(with: try filledStore().exportAllData(at: exportedAt).json()) as! [String: Any]
		var searches = json["savedSearches"] as! [[String: Any]]
		searches[1][field] = field == "period" ? ["kind": "decade"] : ["kind": "range"]
		json["savedSearches"] = searches
		let expected = field == "period" ? "at savedSearches[1], \"decade\" is not a period" : "at savedSearches[1], the amount range has no end or its minimum lies above its maximum"
		#expect(throws: AllData.ReadError.damaged(expected)) { try AllData(json: try JSONSerialization.data(withJSONObject: json)) }
	}

	@Test("An export of an earlier version with an invalid or a spaced account IBAN imports, and the IBAN moves as from a bank",
		arguments: [("DE03120300000000202051", nil, "DE03120300000000202051"), ("de02 1203 0000 0000 2020 51", "DE02120300000000202051", nil)] as [(String, String?, String?)])
	func earlierAccountIBAN(text: String, iban: String?, accountNumber: String?) throws {
		var json = try JSONSerialization.jsonObject(with: try filledStore().exportAllData(at: exportedAt).json()) as! [String: Any]
		var accounts = json["accounts"] as! [[String: Any]]
		let index = try #require(accounts.firstIndex { $0["name"] as? String == "Haushalt" })
		#expect(accounts[index]["accountNumber"] is NSNull || accounts[index]["accountNumber"] == nil)
		accounts[index]["iban"] = text
		json["accounts"] = accounts
		let target = try emptyStore("target")
		try target.importAllData(try AllData(json: try JSONSerialization.data(withJSONObject: json)))
		let haushalt = try #require(try target.loadLedger().accounts.first { $0.name == "Haushalt" })
		#expect(haushalt.iban?.electronic == iban)
		#expect(haushalt.accountNumber == accountNumber)
	}

	/// The scenario "Empty name in an import of all data" of "Account name" in
	/// openspec/changes/add-account-management/specs/account-management/spec.md.
	@Test("An account whose name in the file is empty or only white space imports with the name of its type", arguments: ["", "  "])
	func emptyAccountName(name: String) throws {
		var json = try JSONSerialization.jsonObject(with: try filledStore().exportAllData(at: exportedAt).json()) as! [String: Any]
		var accounts = json["accounts"] as! [[String: Any]]
		let index = try #require(accounts.firstIndex { $0["name"] as? String == "Haushalt" })
		accounts[index]["name"] = name
		json["accounts"] = accounts
		let target = try emptyStore("target")
		try target.importAllData(try AllData(json: try JSONSerialization.data(withJSONObject: json)))
		let names = try target.loadLedger().accounts.map(\.name).sorted()
		#expect(names == ["Bargeld", "Depot", "Giro account", "Girokonto"])
	}

	@Test("An export without returnReason imports its transactions with no return reason")
	func missingReturnReason() throws {
		var json = try JSONSerialization.jsonObject(with: try filledStore().exportAllData(at: exportedAt).json()) as! [String: Any]
		var rows = json["transactions"] as! [[String: Any]]
		for i in rows.indices { rows[i].removeValue(forKey: "returnReason") }
		json["transactions"] = rows
		let target = try emptyStore("target")
		try target.importAllData(try AllData(json: try JSONSerialization.data(withJSONObject: json)))
		let imported = try target.loadLedger().transactions
		#expect(imported.count == 3)
		#expect(imported.allSatisfy { $0.returnReason == nil })
	}

	@Test("An export refuses an original amount above the limit of amounts, one without its currency, and a currency that is no code")
	func originalAmountChecks() throws {
		let file = try filledStore().exportAllData(at: exportedAt).json()
		for change in [["originalAmount": "10000000000000.01", "originalCurrency": "USD"], ["originalAmount": "1.00"], ["originalAmount": "1.00", "originalCurrency": "U$1"]] {
			var json = try JSONSerialization.jsonObject(with: file) as! [String: Any]
			var rows = json["transactions"] as! [[String: Any]]
			rows[0].merge(change) { $1 }
			json["transactions"] = rows
			#expect(throws: AllData.ReadError.self) {
				try (try emptyStore("target-\(UUID().uuidString)")).importAllData(try AllData(json: try JSONSerialization.data(withJSONObject: json)))
			}
		}
	}

	@Test("The mark of missing older transactions goes with the account, and a file without it imports the account without the mark")
	func missingOlderTransactionsMark() throws {
		let exported = try filledStore().exportAllData(at: exportedAt).json()
		var json = try #require(try JSONSerialization.jsonObject(with: exported) as? [String: Any])
		var accounts = try #require(json["accounts"] as? [[String: Any]])
		// Every account carries the key, and only the giro account is marked.
		let marks = accounts.map { $0["missesOlderTransactions"] as? Bool }
		#expect(marks.allSatisfy { $0 != nil })
		#expect(marks.filter { $0 == true }.count == 1)
		let marked = try emptyStore("marked")
		try marked.importAllData(try AllData(json: exported))
		#expect(try marked.loadLedger().accounts.filter(\.missesOlderTransactions).map(\.name) == ["Girokonto"])
		for i in accounts.indices { accounts[i].removeValue(forKey: "missesOlderTransactions") }
		json["accounts"] = accounts
		let older = try emptyStore("older")
		try older.importAllData(try AllData(json: try JSONSerialization.data(withJSONObject: json)))
		let imported = try older.loadLedger().accounts
		#expect(imported.count == 4)
		#expect(imported.allSatisfy { !$0.missesOlderTransactions })
	}

	@Test("Amounts are decimal text with a currency, and nothing is rounded")
	func noRounding() throws {
		let text = String(decoding: try filledStore().exportAllData(at: exportedAt).json(), as: UTF8.self)
		#expect(text.contains(#""amount" : "-1234.56""#))
		#expect(text.contains(#""amount" : "-20.00""#))
		#expect(text.contains(#""currency" : "USD""#))
		#expect(text.contains(#""quantity" : "12.345""#))
		#expect(text.contains(#""bookingDate" : "2026-11-02""#))
		#expect(text.contains(#""exportedAt" : "2026-11-14T23:46:40.000Z""#))
		#expect(text.contains(#""version" : 4"#))
	}

	/// "Decimal places of a token in the complete export": with 2 places for every code outside ISO 4217, these amounts
	/// could not be stored at all (#581).
	@Test("Token amounts have the places of their codes in the file, under version 4, and come back exactly")
	func tokenAmountsRoundTrip() throws {
		defer { try? FileManager.default.removeItem(at: root) }
		let source = try emptyStore("token-amounts-source")
		let account = Account(position: 0, name: "Wallet", kind: .giro, source: .offline, currency: "BTC", initialBalanceMinor: 100_000_000)
		try source.save(accounts: [account])
		let rows = [
			Transaction(accountID: account.id, bookingDate: Day(year: 2026, month: 11, day: 3), amountMinor: 12_345, currency: "BTC", name: "Example A", createdAt: exportedAt),
			Transaction(accountID: account.id, bookingDate: Day(year: 2026, month: 11, day: 4), amountMinor: 4_000, currency: "USDC", name: "Example B", createdAt: exportedAt),
			Transaction(accountID: account.id, bookingDate: Day(year: 2026, month: 11, day: 5), amountMinor: -21, currency: "ETH", name: "Example C", createdAt: exportedAt),
		]
		try source.save(rows)
		let exported = try source.exportAllData(at: exportedAt)
		let file = try exported.json()
		let json = try #require(try JSONSerialization.jsonObject(with: file) as? [String: Any])
		#expect(json["version"] as? Int == 4)
		let entries = try #require(json["transactions"] as? [[String: Any]])
		#expect(entries.compactMap { $0["amount"] as? String } == ["0.00012345", "0.004000", "-0.000000021"])
		#expect((json["accounts"] as? [[String: Any]])?.first?["initialBalance"] as? String == "1.00000000")
		let target = try emptyStore("token-amounts-target")
		try target.importAllData(try AllData(json: file))
		let imported = try target.exportAllData(at: exportedAt)
		#expect(imported == exported)
		#expect(imported.transactions.map(\.amount) == rows.map(\.amount))
	}

	/// "Token amounts of an earlier file": a file of version 3 wrote these codes with 2 places. Its amounts are decimal text
	/// and keep their value, but a file identity holds minor units, which the import converts, so the same bank file finds
	/// its rows again.
	@Test("A file of version 3 imports its token amounts with their values and converts its file identities, so the same bank file adds nothing")
	func tokenFileIdentityOfVersion3() throws {
		defer { try? FileManager.default.removeItem(at: root) }
		let source = try emptyStore("token-v3-source")
		let account = Account(position: 0, name: "Wallet", kind: .giro, source: .offline, currency: "BTC")
		try source.save(accounts: [account])
		let rows = [
			Transaction(accountID: account.id, bookingDate: Day(year: 2026, month: 11, day: 3), amountMinor: 25_000_000, currency: "BTC", name: "Example A", isPending: true),
			Transaction(accountID: account.id, bookingDate: Day(year: 2026, month: 11, day: 4), amountMinor: -1_500_000, currency: "USDC", name: "Example B", isPending: true),
			Transaction(accountID: account.id, bookingDate: Day(year: 2026, month: 11, day: 5), amountMinor: -2_000, currency: "EUR", name: "Example C", isPending: true),
		]
		let added = try source.merge(.file(rows), into: account.id, now: exportedAt).added
		try source.deleteTransactions([try #require(added.first { $0.currency == "USDC" }).id])
		let exported = try source.exportAllData(at: exportedAt)
		#expect(exported.transactions.compactMap(\.fileIdentity).allSatisfy { $0.contains("8:25000000") || $0.contains("5:-2000") })
		#expect(exported.deletedTransactions.compactMap(\.fileIdentity).allSatisfy { $0.contains("8:-1500000") })
		// The same file as version 3 wrote it, with 2 places for BTC and USDC.
		var text = String(decoding: try exported.json(), as: UTF8.self)
		for (new, old) in [(#""version" : 4"#, #""version" : 3"#), ("8:25000000", "2:25"), ("8:-1500000", "4:-150"),
			(#""0.25000000""#, #""0.25""#), (#""-1.500000""#, #""-1.50""#)] {
			#expect(text.contains(new))
			text = text.replacingOccurrences(of: new, with: old)
		}
		let target = try emptyStore("token-v3-target")
		try target.importAllData(try AllData(json: Data(text.utf8)))
		#expect(try target.exportAllData(at: exportedAt) == exported)
		// Two pending rows pair only when their file identities are equal. A file import adds a deleted row again by design.
		let again = try target.merge(.file(rows.filter { $0.currency != "USDC" }), into: account.id, now: exportedAt)
		#expect(again.added == [] && again.skipped == 2)
	}

	@Test("The file names the bank, the user ID, and the connector of an access, and holds neither its PIN nor its state")
	func savedPIN() throws {
		let text = String(decoding: try filledStore().exportAllData(at: exportedAt).json(), as: UTF8.self)
		#expect(text.contains(#""bankName" : "Musterbank""#) && text.contains(#""userID" : "erika77""#) && text.contains(#""bankCode" : "12030000""#))
		#expect(!text.contains("24680"))
		#expect(!text.contains("bank parameters") && !text.contains(Data("bank parameters".utf8).base64EncodedString()))
	}

	@Test("An imported access has its bank and user ID, and no saved PIN and no state")
	func accountsWithoutLoginData() throws {
		let target = try emptyStore("target")
		try target.importAllData(try AllData(json: try filledStore().exportAllData(at: exportedAt).json()))
		let access = try #require(try target.accesses().first)
		#expect(access.bankName == "Musterbank" && access.loginName == "erika77")
		#expect(try target.savedPINs().isEmpty)
		#expect(try target.state(of: access.id) == nil)
	}

	@Test("The import refuses a database with an account and changes nothing, and replaces only the starter categories it is given")
	func databaseInUse() throws {
		let data = try AllData(json: try filledStore().exportAllData(at: exportedAt).json())
		let used = try emptyStore("used")
		try used.save(Account(position: 0, name: "Giro", kind: .giro, source: .offline))
		#expect(throws: Store.ImportRefusal.notEmpty) { try used.importAllData(data) }
		#expect(try used.loadLedger().accounts.map(\.name) == ["Giro"])

		let searched = try emptyStore("searched")
		var f = TransactionFilter()
		f.searchText = "Miete"
		_ = try searched.appendSavedSearch(name: "Rent", period: .all, filter: f)
		#expect(throws: Store.ImportRefusal.notEmpty) { try searched.importAllData(data) }
		#expect(try searched.savedSearches().map(\.name) == ["Rent"])

		let starter = Domain.Category(position: 0, name: "Groceries")
		let fresh = try emptyStore("fresh")
		try fresh.save(starter)
		#expect(throws: Store.ImportRefusal.notEmpty) { try fresh.importAllData(data) }
		try fresh.importAllData(data, replacing: [starter.id])
		#expect(try fresh.loadLedger().categories.map(\.name).sorted() == ["Food", "Pets", "Uncategorized"])
	}

	@Test("A file of a newer format version is refused and names the need for a newer app")
	func newerFormat() throws {
		var json = try JSONSerialization.jsonObject(with: try filledStore().exportAllData(at: exportedAt).json()) as! [String: Any]
		json["version"] = 5
		#expect(throws: AllData.ReadError.newerVersion(5)) { try AllData(json: try JSONSerialization.data(withJSONObject: json)) }
		#expect(AllData.ReadError.newerVersion(5).description
			== "The file has format version 5, and this version of Moneten reads up to version 4. Install a newer version of Moneten to import it.")
		#expect(throws: AllData.ReadError.notAnExport) { try AllData(json: Data(#"{"format": "other", "version": 1}"#.utf8)) }
	}

	@Test("A file that ends in the middle of the transactions, or has a broken amount, is refused with the place of the error")
	func truncatedFile() throws {
		let file = try filledStore().exportAllData(at: exportedAt).json()
		let text = String(decoding: file, as: UTF8.self)
		let cut = try #require(text.range(of: "Stadtwerke Musterstadt"))
		let truncated = Data(text[..<cut.upperBound].utf8)
		let line = text[..<cut.upperBound].filter { $0 == "\n" }.count + 1
		let error = #expect(throws: AllData.ReadError.self) { try AllData(json: truncated) }
		#expect(error.map { "\($0)".contains("at line \(line), column ") } == true, "\(String(describing: error))")
		let broken = Data(text.replacingOccurrences(of: #""name" : "Kiosk","#, with: #""name" : "Kiosk";"#).utf8)
		let brokenError = #expect(throws: AllData.ReadError.self) { try AllData(json: broken) }
		#expect(brokenError.map { "\($0)".contains("at line ") } == true, "\(String(describing: brokenError))")

		var json = try JSONSerialization.jsonObject(with: file) as! [String: Any]
		var rows = json["transactions"] as! [[String: Any]]
		for (amount, reason) in [("zehn", "zehn"), ("1-2", "1-2"), ("12.345", "12.345"), ("99999999999999999.99", "99999999999999999.99")] {
			rows[1]["amount"] = amount
			json["transactions"] = rows
			#expect(throws: AllData.ReadError.damaged("at transactions[1], the amount \"\(reason)\" is not a decimal number with the decimal places of EUR")) {
				try AllData(json: try JSONSerialization.data(withJSONObject: json))
			}
		}
		#expect(throws: AllData.ReadError.notAnExport) { try AllData(json: Data(#"{"accounts": []}"#.utf8)) }
		#expect(throws: AllData.ReadError.notAnExport) { try AllData(json: Data("[1, 2]".utf8)) }
		for day in ["2026-02-31", "31.12.2026", "2026/11/02"] {
			rows[1]["bookingDate"] = day
			json["transactions"] = rows
			#expect(throws: AllData.ReadError.damaged("at transactions[1], \"\(day)\" is not a day in the form yyyy-MM-dd")) {
				try AllData(json: try JSONSerialization.data(withJSONObject: json))
			}
		}
		rows[1]["bookingDate"] = "2026-11-04"
		rows[1]["amount"] = 5
		json["transactions"] = rows
		#expect(throws: AllData.ReadError.damaged("at transactions[1].amount, expected to decode String but found number instead")) {
			try AllData(json: try JSONSerialization.data(withJSONObject: json))
		}
		#expect(throws: AllData.ReadError.notAnExport) { try AllData(json: Data(#"{"format": 5}"#.utf8)) }
	}

	@Test("A transaction amount at the bounds of the minor units reads exactly, and one without a magnitude or beyond them is refused")
	func amountBounds() throws {
		var json = try JSONSerialization.jsonObject(with: try filledStore().exportAllData(at: exportedAt).json()) as! [String: Any]
		var rows = json["transactions"] as! [[String: Any]]
		rows[1]["amount"] = "-92233720368547758.07"
		json["transactions"] = rows
		#expect(try AllData(json: try JSONSerialization.data(withJSONObject: json)).transactions[1].amountMinor == -Int64.max)
		rows[1]["amount"] = "-92233720368547758.08"
		json["transactions"] = rows
		#expect(throws: AllData.ReadError.damaged("at transactions[1], the amount \"-92233720368547758.08\" is not a decimal number with the decimal places of EUR")) {
			try AllData(json: try JSONSerialization.data(withJSONObject: json))
		}
		rows[1]["amount"] = "92233720368547758.08"
		json["transactions"] = rows
		#expect(throws: AllData.ReadError.self) { try AllData(json: try JSONSerialization.data(withJSONObject: json)) }
	}

	@Test("A file whose transaction names an account that it does not contain is refused, and the database stays empty")
	func brokenReference() throws {
		var json = try JSONSerialization.jsonObject(with: try filledStore().exportAllData(at: exportedAt).json()) as! [String: Any]
		var rows = json["transactions"] as! [[String: Any]]
		rows[1]["accountID"] = UUID().uuidString
		json["transactions"] = rows
		let target = try emptyStore("broken")
		#expect(throws: AllData.ReadError.damaged("an object refers to another object that the file does not contain")) {
			try target.importAllData(try AllData(json: try JSONSerialization.data(withJSONObject: json)))
		}
		#expect(try target.loadLedger().accounts.isEmpty)

		rows[1]["accountID"] = rows[0]["accountID"]
		rows[1]["id"] = rows[0]["id"]
		json["transactions"] = rows
		#expect(throws: AllData.ReadError.damaged("the file holds an object twice")) {
			try target.importAllData(try AllData(json: try JSONSerialization.data(withJSONObject: json)))
		}
	}

	@Test("The import replaces account groups without accounts")
	func emptyGroupsReplaced() throws {
		let data = try AllData(json: try filledStore().exportAllData(at: exportedAt).json())
		let target = try emptyStore("groups")
		try target.save(AccountGroup(name: "Mine", position: 0))
		try target.importAllData(data)
		#expect(try target.loadLedger().groups.map(\.name).sorted() == ["Household", "Private"])
	}

	@Test("Category and account group parent loops are refused without changing the database", arguments: ["category-self", "category-loop", "group-self", "group-loop"])
	func parentLoops(_ scenario: String) throws {
		let a = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
		let b = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
		let loop = scenario.hasSuffix("loop")
		let categories = scenario.hasPrefix("category")
		let data = AllData(groups: categories ? [] : [
			AccountGroup(id: a, name: "A", parentID: loop ? b : a, position: 0),
			AccountGroup(id: b, name: "B", parentID: a, position: 1)], categories: categories ? [
			Domain.Category(id: a, parentID: loop ? b : a, position: 0, name: "A"),
			Domain.Category(id: b, parentID: a, position: 1, name: "B")] : [])
		let target = try emptyStore("loops")
		let starter = Domain.Category(position: 0, name: "Starter")
		try target.save(starter)
		try target.save(AccountGroup(name: "Existing", position: 0))
		let before = try target.exportAllData(at: exportedAt)
		let reason = categories ? "at categories[0], the category is inside itself" : "at accountGroups[0], the account group is inside itself"
		#expect(throws: AllData.ReadError.damaged(reason)) {
			try target.importAllData(data, replacing: [starter.id])
		}
		#expect(try target.exportAllData(at: exportedAt) == before)
		#expect(throws: AllData.ReadError.damaged(reason)) {
			try target.importAllData(try AllData(json: data.json()), replacing: [starter.id])
		}
		#expect(try target.exportAllData(at: exportedAt) == before)
	}

	@Test("Overflowing days are refused before date parsing", arguments: ["bookingDate", "valueDate", "day"])
	func boundedDays(_ field: String) throws {
		var json = try JSONSerialization.jsonObject(with: try filledStore().exportAllData(at: exportedAt).json()) as! [String: Any]
		let key = field == "day" ? "portfolioValues" : "transactions"
		var rows = json[key] as! [[String: Any]]
		rows[0][field] = "01-01-9223372036854775807"
		json[key] = rows
		let target = try emptyStore("overflow")
		#expect(throws: AllData.ReadError.damaged("at \(key)[0], \"01-01-9223372036854775807\" is not a day in the form yyyy-MM-dd")) {
			try target.importAllData(try AllData(json: JSONSerialization.data(withJSONObject: json)))
		}
		#expect(try target.exportAllData(at: exportedAt) == AllData(exportedAt: exportedAt))
	}

	@Test("A portfolio value in a foreign currency is refused without changing the database")
	func portfolioCurrency() throws {
		var json = try JSONSerialization.jsonObject(with: try filledStore().exportAllData(at: exportedAt).json()) as! [String: Any]
		var values = json["portfolioValues"] as! [[String: Any]]
		values[0]["value"] = "100"
		values[0]["currency"] = "JPY"
		json["portfolioValues"] = values
		let target = try emptyStore("currency")
		#expect(throws: AllData.ReadError.damaged("at portfolioValues[0], the currency JPY differs from the account currency EUR")) {
			try target.importAllData(try AllData(json: JSONSerialization.data(withJSONObject: json)))
		}
		#expect(try target.exportAllData(at: exportedAt) == AllData(exportedAt: exportedAt))
	}

	@Test("A complete export creates and replaces a file with mode 0600")
	func privateExportFile() throws {
		let store = try filledStore()
		let file = root.appending(path: "export.json")
		for replacing in [false, true] {
			if replacing { try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: file.path) }
			try store.exportAllData(to: file)
			let attributes = try FileManager.default.attributesOfItem(atPath: file.path)
			#expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)
			#expect(try AllData(json: Data(contentsOf: file)).accounts.count == 4)
		}
		let folder = root.appending(path: "directory")
		try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
		#expect(throws: (any Error).self) { try store.exportAllData(to: folder) }
		#expect(try FileManager.default.contentsOfDirectory(atPath: root.path).sorted() == ["directory", "export.json", "source"])
	}

	@Test("Every currency code has 3 to 10 uppercase ASCII letters and digits and starts with a letter")
	func currencyCodes() throws {
		let original = try JSONSerialization.jsonObject(with: try filledStore().exportAllData(at: exportedAt).json()) as! [String: Any]
		let target = try emptyStore("codes")
		let fields = [("accounts", ["currency"]), ("transactions", ["currency"]), ("deletedTransactions", ["currency"]),
			("categories", ["currency"]), ("portfolioValues", ["currency"]), ("holdings", ["nominalCurrency"]),
			("holdings", ["price", "currency"]), ("holdings", ["marketValue", "currency"]), ("holdings", ["accruedInterest", "currency"]),
			("holdings", ["purchasePrice", "currency"]), ("holdings", ["exchangeRate", "base"]), ("holdings", ["exchangeRate", "quoted"])]
		for (key, path) in fields {
			for code in ["not a currency", "eur", "EU", "1EU", "U$D", "ÉUR", "", "ABCDEFGHIJK"] {
				var json = original
				var rows = json[key] as! [[String: Any]]
				if path.count == 1 {
					rows[0][path[0]] = code
				} else {
					var amount = rows[0][path[0]] as? [String: Any] ?? ["amount": "1.00", "currency": "EUR"]
					amount[path[1]] = code
					rows[0][path[0]] = amount
				}
				json[key] = rows
				#expect(throws: AllData.ReadError.damaged("at \(key)[0], \"\(code)\" is not a currency code in the form [A-Z][A-Z0-9]{2,9}")) {
					try target.importAllData(try AllData(json: JSONSerialization.data(withJSONObject: json)))
				}
			}
		}
		#expect(try target.exportAllData(at: exportedAt) == AllData(exportedAt: exportedAt))
		// An ISO 4217 code, the ticker of a crypto token that an extension gives, and any other code of this form (#569).
		for code in ["ZZZ", "USDC", "EURO", "MATIC1"] {
			let syntacticallyValid = AllData(accounts: [Account(position: 0, name: "Test", kind: .cash, source: .offline, currency: code)])
			#expect(try AllData(json: syntacticallyValid.json()).accounts[0].currency == code)
		}
	}

	@Test("Nonpositive format versions are refused", arguments: [0, -1])
	func positiveVersion(_ version: Int) throws {
		var json = try JSONSerialization.jsonObject(with: AllData().json()) as! [String: Any]
		json["version"] = version
		let target = try emptyStore("version")
		#expect(throws: AllData.ReadError.damaged("at version, the format version must be at least 1")) {
			try target.importAllData(try AllData(json: JSONSerialization.data(withJSONObject: json)))
		}
		#expect(try target.exportAllData(at: exportedAt) == AllData(exportedAt: exportedAt))
	}

	@Test("An unreadable stored holding fails the export and preserves an existing file")
	func unreadableHolding() throws {
		let store = try filledStore()
		try store.write { db in try db.execute(sql: "UPDATE holding SET quantity = 'broken'") }
		#expect(throws: AllData.ReadError.unreadableDatabase("at holdings[0], the stored holding cannot be read")) {
			try store.exportAllData(at: exportedAt)
		}
		let file = root.appending(path: "export.json")
		try Data("keep".utf8).write(to: file)
		#expect(throws: AllData.ReadError.unreadableDatabase("at holdings[0], the stored holding cannot be read")) {
			try store.exportAllData(to: file)
		}
		#expect(try String(contentsOf: file, encoding: .utf8) == "keep")
		#expect(try FileManager.default.contentsOfDirectory(atPath: root.path).sorted() == ["export.json", "source"])
	}

	@Test("The export error describes an unreadable database, with its position")
	func exportErrorDescription() throws {
		let store = try filledStore()
		try store.write { db in try db.execute(sql: "UPDATE holding SET quantity = 'broken'") }
		let error = try #require(throws: AllData.ReadError.self) { try store.exportAllData() }
		#expect(error.description == "The database contains unreadable data: at holdings[0], the stored holding cannot be read.")
	}

	@Test("Decimal values that would be rounded are refused without changing the database")
	func decimalPrecision() throws {
		let original = try JSONSerialization.jsonObject(with: try filledStore().exportAllData().json()) as! [String: Any]
		let target = try emptyStore("precision")
		for path in [["quantity"], ["price", "amount"], ["purchasePrice", "amount"], ["exchangeRate", "rate"]] {
			var json = original
			var rows = json["holdings"] as! [[String: Any]]
			if path.count == 1 {
				rows[0][path[0]] = "1.123456789012345678901234567890123456789"
			} else {
				var value = rows[0][path[0]] as! [String: Any]
				value[path[1]] = "1.123456789012345678901234567890123456789"
				rows[0][path[0]] = value
			}
			json["holdings"] = rows
			#expect(throws: AllData.ReadError.damaged("at holdings[0], the decimal number cannot be represented without rounding")) {
				try target.importAllData(try AllData(json: JSONSerialization.data(withJSONObject: json)))
			}
		}
		#expect(try target.exportAllData(at: exportedAt) == AllData(exportedAt: exportedAt))
		var boundary = original
		var rows = boundary["holdings"] as! [[String: Any]]
		rows[0]["quantity"] = "-1.1234567890123456789012345678901234567"
		boundary["holdings"] = rows
		let accepted = try AllData(json: JSONSerialization.data(withJSONObject: boundary))
		#expect(accepted.holdings[0].quantity.description == "-1.1234567890123456789012345678901234567")
	}

	@Test("Every exactly represented decimal survives its own export", arguments: [
		"0.12345678901234567890123456789012345678",
		"0.000000000000000000000000000000000000001",
		"100000000000000000000000000000000000000",
		"123456789012345678901234567890123456789",
		"340282366920938463463374607431768211455"
	])
	func exactDecimalRoundTrip(_ text: String) throws {
		let account = Account(position: 0, name: "Test", kind: .portfolio, source: .offline)
		let quantity = try #require(Decimal(string: text, locale: Locale(identifier: "en_US_POSIX")))
		#expect(quantity.description == text)
		let data = AllData(accounts: [account], holdings: [Holding(accountID: account.id, security: Security(name: "Test"), quantity: quantity)])
		let imported = try AllData(json: data.json())
		#expect(imported.holdings[0].quantity.description == text)
	}

	/// A balance in the account currency would count twice in the sum of a group, and a repeated currency would show twice
	/// in the sidebar row. A code that is not three letters is no currency.
	@Test("An import refuses other balances in the account currency, a repeated currency, or a code that is no currency", arguments: [
		[["amount": "120.00", "currency": "EUR"]],
		[["amount": "35.00", "currency": "USD"], ["amount": "1.00", "currency": "USD"]],
		[["amount": "35.00", "currency": "US$"]],
		[["amount": "35.00", "currency": "usd"]],
	])
	func refusedOtherBalances(_ balances: [[String: String]]) throws {
		var json = try JSONSerialization.jsonObject(with: try filledStore().exportAllData().json()) as! [String: Any]
		var accounts = json["accounts"] as! [[String: Any]]
		let index = try #require(accounts.firstIndex { $0["otherBankBalances"] != nil })
		#expect(accounts[index]["currency"] as? String == "EUR")
		accounts[index]["otherBankBalances"] = balances
		json["accounts"] = accounts
		#expect(throws: AllData.ReadError.self) { try AllData(json: JSONSerialization.data(withJSONObject: json)) }
	}

	@Test("The asset classes of a holding travel with their stored names, a file without them reads with none, and an unknown name is refused")
	func holdingAssetClasses() throws {
		var json = try JSONSerialization.jsonObject(with: try filledStore().exportAllData().json()) as! [String: Any]
		var rows = json["holdings"] as! [[String: Any]]
		#expect(rows[0]["sourceAssetClass"] as? String == "funds" && rows[0]["userAssetClass"] as? String == "etfs")
		rows[0]["sourceAssetClass"] = nil
		rows[0]["userAssetClass"] = nil
		json["holdings"] = rows
		let earlier = try AllData(json: JSONSerialization.data(withJSONObject: json))
		#expect(earlier.holdings[0].sourceAssetClass == nil && earlier.holdings[0].userAssetClass == nil && earlier.holdings[0].assetClass == .others)
		rows[0]["userAssetClass"] = "Aktien"
		json["holdings"] = rows
		#expect(throws: AllData.ReadError.self) { try AllData(json: JSONSerialization.data(withJSONObject: json)) }
	}

	@Test("An import refuses a holding value in a code that is no currency")
	func refusedHoldingCurrency() throws {
		var json = try JSONSerialization.jsonObject(with: try filledStore().exportAllData().json()) as! [String: Any]
		var rows = json["holdings"] as! [[String: Any]]
		rows[0]["marketValue"] = ["amount": "1.00", "currency": "US$"]
		json["holdings"] = rows
		#expect(throws: AllData.ReadError.self) { try AllData(json: JSONSerialization.data(withJSONObject: json)) }
	}

	@Test("Insignificant zeros and negative zero do not change decimal values", arguments: [
		("0001.2300", "1.23"), ("-0001.2300", "-1.23"), ("-000.000", "0"), ("000", "0")
	])
	func paddedDecimals(_ text: String, _ expected: String) throws {
		var json = try JSONSerialization.jsonObject(with: try filledStore().exportAllData().json()) as! [String: Any]
		var rows = json["holdings"] as! [[String: Any]]
		rows[0]["quantity"] = text
		json["holdings"] = rows
		let imported = try AllData(json: JSONSerialization.data(withJSONObject: json))
		#expect(imported.holdings[0].quantity.description == expected)
	}

	@Test("A complete export accepts a valid 235-byte destination name")
	func longExportFilename() throws {
		let store = try filledStore()
		let file = root.appending(path: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa.json")
		try store.exportAllData(to: file)
		#expect(try AllData(json: Data(contentsOf: file)).accounts.count == 4)
	}

	@Test("Every key of an export is described in docs/export-format.md")
	func documented() throws {
		let store = try filledStore()
		let original = try #require(store.loadLedger().transactions.first { !$0.isPending })
		try store.replaceParts(of: original.id, with: [
			SplitPart(transactionID: original.id, position: 0, amountMinor: -10000, comment: "Net", vat: VATShare(role: .net, rate: VATRate(hundredths: 1900))),
			SplitPart(transactionID: original.id, position: 1, amountMinor: original.amountMinor + 10000, vat: VATShare(role: .tax, rate: VATRate(hundredths: 1900)))])
		let json = try JSONSerialization.jsonObject(with: store.exportAllData(at: exportedAt).json())
		var keys = Set<String>()
		func collect(_ value: Any) {
			if let object = value as? [String: Any] {
				for (key, child) in object {
					keys.insert(key)
					collect(child)
				}
			} else if let list = value as? [Any] {
				list.forEach(collect)
			}
		}
		collect(json)
		let doc = URL(filePath: #filePath).deletingLastPathComponent().appending(path: "../../docs/export-format.md").standardized
		let text = try String(contentsOf: doc, encoding: .utf8)
		#expect(keys.count > 80)
		#expect(keys.filter { !text.contains("`\($0)`") }.sorted() == [])
	}
}
