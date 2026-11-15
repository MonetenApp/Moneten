import Domain
import Foundation
import GRDB
import Testing
@testable import Storage

/// A database with every kind of object that the complete export holds. All names and numbers are made up.
@Suite("Complete export and import")
struct AllDataTests {
	let root = FileManager.default.temporaryDirectory.appendingPathComponent("MonetenTests-\(UUID().uuidString)")
	let exportedAt = Date(timeIntervalSince1970: 1_794_700_000)

	func emptyStore(_ name: String) throws -> Store {
		try Vault(folder: DataFolder(root: root.appendingPathComponent(name))).create(password: "korrekt-pferd-batterie-heftklammer", starterCategories: [])
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
			refreshError: RefreshError(message: "Die PIN ist falsch.", code: "9931", date: Date(timeIntervalSince1970: 1_794_660_000), notices: ["Wartung am Sonntag"]),
			refreshInterval: .onceADay)
		let linked = try store.add(access, state: AccessState(Data("bank parameters".utf8)), accounts: [giro])
		try store.savePIN(Secret("24680"), for: linked.access.id)
		let bank = try #require(linked.accounts.first)
		let rows = [
			Transaction(accountID: migrated.id, bookingDate: Day(year: 2026, month: 11, day: 2), valueDate: Day(year: 2026, month: 11, day: 3), amountMinor: -123_456,
				name: "Stadtwerke Musterstadt", purpose: "Abschlag\nNovember", counterpartyIBAN: "DE02120300000000202051", counterpartyBIC: "BYLADEM1001",
				bookingText: "Lastschrift", endToEndReference: "E2E-1", mandateReference: "M-1", creditorID: "DE98ZZZ09999999999", comment: "Strom",
				isChecked: true, categoryID: pets.id, categorizedBy: .manual, sourceID: "moneymoney:1", createdAt: Date(timeIntervalSince1970: 1_794_600_001.123)),
			Transaction(accountID: migrated.id, bookingDate: Day(year: 2026, month: 11, day: 4), amountMinor: -1_000, name: "Kiosk", isPending: true,
				categoryID: food.id, categorizedBy: .rule, isNew: true, needsReview: true, sourceID: "moneymoney:2"),
			Transaction(accountID: bank.id, bookingDate: Day(year: 2026, month: 11, day: 5), amountMinor: -2_000, currency: "USD", name: "Diner New York",
				isFetched: true, sourceID: "bank-4711"),
			Transaction(accountID: offline.id, bookingDate: Day(year: 2026, month: 11, day: 6), amountMinor: -480, name: "Bäckerei Gutbrot"),
		]
		try store.save(rows)
		try store.deleteTransactions([rows[3].id])
		try store.write { db in
			try HoldingRecord(Holding(accountID: portfolio.id, security: Security(name: "Beispiel Welt ETF", isin: "DE0000000001"), quantity: Decimal(string: "12.345")!,
				quote: Quote(amount: Decimal(string: "81.2")!, currency: "EUR", day: Day(year: 2026, month: 11, day: 13)),
				marketValue: Money(minorUnits: 100_241, currency: "EUR"), purchasePrice: Quote(amount: 70, currency: "EUR"),
				exchangeRate: ExchangeRate(base: "EUR", quoted: "USD", rate: Decimal(string: "1.0832")!))).insert(db)
		}
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
		#expect(Set(after.accounts) == Set(before.accounts))
		#expect(Set(after.groups) == Set(before.groups))
		#expect(Set(after.categories) == Set(before.categories))
		#expect(Set(after.transactions) == Set(before.transactions))
		#expect(after.holdings(of: after.accounts.map(\.id)) == before.holdings(of: before.accounts.map(\.id)))
		let depot = try #require(before.accounts.first { $0.name == "Depot" })
		#expect(after.portfolioValues(of: depot.id) == before.portfolioValues(of: depot.id))
		#expect(Set(try target.deletedTransactions()) == Set(try source.deletedTransactions()))
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
		#expect(text.contains(#""version" : 1"#))
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
			== "The file has format version 5, and this version of Moneten reads up to version 1. Install a newer version of Moneten to import it.")
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
		#expect(throws: AllData.ReadError.notAnExport) { try AllData(json: Data(#"{"format": 5}"#.utf8)) }
	}

	@Test("The import replaces account groups without accounts")
	func emptyGroupsReplaced() throws {
		let data = try AllData(json: try filledStore().exportAllData(at: exportedAt).json())
		let target = try emptyStore("groups")
		try target.save(AccountGroup(name: "Mine", position: 0))
		try target.importAllData(data)
		#expect(try target.loadLedger().groups.map(\.name).sorted() == ["Household", "Private"])
	}

	@Test("Every key of an export is described in docs/export-format.md")
	func documented() throws {
		let json = try JSONSerialization.jsonObject(with: try filledStore().exportAllData(at: exportedAt).json())
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
