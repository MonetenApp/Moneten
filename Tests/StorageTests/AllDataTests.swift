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
				isChecked: true, categoryID: pets.id, categorizedBy: .manual, sourceID: "moneymoney:1", createdAt: Date(timeIntervalSince1970: 1_794_600_001.123), returnReason: "AC04"),
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
		#expect(after.transactions.first { $0.sourceID == "moneymoney:1" }?.returnReason == "AC04")
		#expect(Set(after.accounts) == Set(before.accounts))
		#expect(Set(after.groups) == Set(before.groups))
		#expect(Set(after.categories) == Set(before.categories))
		#expect(Set(after.transactions) == Set(before.transactions))
		#expect(after.holdings(of: after.accounts.map(\.id)) == before.holdings(of: before.accounts.map(\.id)))
		let depot = try #require(before.accounts.first { $0.name == "Depot" })
		#expect(after.portfolioValues(of: depot.id) == before.portfolioValues(of: depot.id))
		#expect(Set(try target.deletedTransactions()) == Set(try source.deletedTransactions()))
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

	@Test("An amount at the bounds of the minor units reads exactly, and one beyond them is refused")
	func amountBounds() throws {
		var json = try JSONSerialization.jsonObject(with: try filledStore().exportAllData(at: exportedAt).json()) as! [String: Any]
		var rows = json["transactions"] as! [[String: Any]]
		rows[1]["amount"] = "-92233720368547758.08"
		json["transactions"] = rows
		#expect(try AllData(json: try JSONSerialization.data(withJSONObject: json)).transactions[1].amountMinor == Int64.min)
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

	@Test("Every currency code has exactly three uppercase ASCII letters")
	func currencyCodes() throws {
		let original = try JSONSerialization.jsonObject(with: try filledStore().exportAllData(at: exportedAt).json()) as! [String: Any]
		let target = try emptyStore("codes")
		let fields = [("accounts", ["currency"]), ("transactions", ["currency"]), ("deletedTransactions", ["currency"]),
			("categories", ["currency"]), ("portfolioValues", ["currency"]), ("holdings", ["nominalCurrency"]),
			("holdings", ["price", "currency"]), ("holdings", ["marketValue", "currency"]), ("holdings", ["accruedInterest", "currency"]),
			("holdings", ["purchasePrice", "currency"]), ("holdings", ["exchangeRate", "base"]), ("holdings", ["exchangeRate", "quoted"])]
		for (key, path) in fields {
			for code in ["not a currency", "eur", "EU1", "EURO", "EU", "ÉUR", ""] {
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
				#expect(throws: AllData.ReadError.damaged("at \(key)[0], \"\(code)\" is not a currency code in the form [A-Z]{3}")) {
					try target.importAllData(try AllData(json: JSONSerialization.data(withJSONObject: json)))
				}
			}
		}
		#expect(try target.exportAllData(at: exportedAt) == AllData(exportedAt: exportedAt))
		let syntacticallyValid = AllData(accounts: [Account(position: 0, name: "Test", kind: .cash, source: .offline, currency: "ZZZ")])
		#expect(try AllData(json: syntacticallyValid.json()).accounts[0].currency == "ZZZ")
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
		#expect(throws: AllData.ReadError.damaged("at holdings[0], the stored holding cannot be read")) {
			try store.exportAllData(at: exportedAt)
		}
		let file = root.appending(path: "export.json")
		try Data("keep".utf8).write(to: file)
		#expect(throws: AllData.ReadError.damaged("at holdings[0], the stored holding cannot be read")) {
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

	@Test("Decimal values longer than 38 digits are refused without changing the database")
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
			#expect(throws: AllData.ReadError.damaged("at holdings[0], the decimal number exceeds 38 digits")) {
				try target.importAllData(try AllData(json: JSONSerialization.data(withJSONObject: json)))
			}
		}
		#expect(try target.exportAllData(at: exportedAt) == AllData(exportedAt: exportedAt))
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
