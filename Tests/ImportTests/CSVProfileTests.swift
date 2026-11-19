import Domain
import Foundation
import Testing
@testable import Import

@Suite("CSV profiles")
struct CSVProfileTests {
	static let header = "Datum;Valuta;Empfänger;IBAN;BIC;Text;Betrag;Währung;Notiz"
	static let row = "01.11.2026;01.11.2026;Broker AG;DE02120300000000202051;BYLADEM1001;Kauf Fonds;-500,00;EUR;Sparplan"

	static func broker() throws -> CSVProfile {
		let file = try CSVFile(data: Data("\(header)\n\(row)\n".utf8))
		var layout = try file.detectedLayout()
		layout.assign(5, to: .purpose)
		return CSVProfile(name: "Broker CSV", header: file.header, layout: layout, delimiter: file.delimiter)
	}

	@Test("A changed delimiter or detected date order requires confirmation")
	func signatureMismatch() throws {
		let original = try CSVFile(data: Data("Date;Name;Amount\n03/11/2026;Kiosk;-4.20\n".utf8))
		var layout = try original.detectedLayout()
		layout.dateOrder = .monthDayYear
		let profile = CSVProfile(name: "Month first", header: original.header, layout: layout, delimiter: original.delimiter)
		let changed = try CSVFile(data: Data("Date,Name,Amount\n03/11/2026,Kiosk,-4.20\n".utf8))
		for file in [original, changed] {
			guard case let .changed(_, start) = CSVProfile.match(for: file, in: [profile], detected: try file.detectedLayout()) else {
				Issue.record("A signature change must open the preview")
				continue
			}
			#expect(start.dateOrder == .dayMonthYear)
			#expect(try file.preview(start, currency: "EUR").transactions.map(\.bookingDate) == [Day(year: 2026, month: 11, day: 3)])
		}
	}

	@Test("A file whose dates fit both orders opens the preview with the question, even with a matching profile", arguments: [Import.DateOrder.dayMonthYear, .monthDayYear])
	func ambiguousFileOpensPreview(order: Import.DateOrder) throws {
		let file = try CSVFile(data: Data("Date,Name,Amount\n11/03/2026,Kiosk,-4.20\n11/04/2026,Bakery,-2.00\n".utf8))
		var layout = try file.detectedLayout()
		layout.dateOrder = order
		let profile = CSVProfile(name: "Card CSV", header: file.header, layout: layout, delimiter: file.delimiter)
		#expect(try profile.read(file, currency: "EUR") == nil)
		let decided = try CSVFile(data: Data("Date,Name,Amount\n\(order == .monthDayYear ? "11/13/2026" : "13/11/2026"),Kiosk,-4.20\n".utf8))
		#expect(try profile.read(decided, currency: "EUR")?.transactions.map(\.bookingDate) == [Day(year: 2026, month: 11, day: 13)])
	}

	/// "Card CSV" for "Date,Name,Amount", with month first chosen in the question for the date order.
	static func answered() throws -> CSVProfile {
		let file = try CSVFile(data: Data("Date,Name,Amount\n11/03/2026,Kiosk,-4.20\n".utf8))
		var layout = try file.detectedLayout()
		layout.dateOrder = .monthDayYear
		return CSVProfile(name: "Card CSV", header: file.header, layout: layout, delimiter: file.delimiter,
			dateOrderAnswer: DateOrderAnswer(order: .monthDayYear, layout: layout, header: file.header))
	}

	@Test("A profile with month first chosen in the question imports 11/03/2026 as 3 November without the preview")
	func answeredProfile() throws {
		let profile = try Self.answered()
		let file = try CSVFile(data: Data("Date,Name,Amount\n11/03/2026,Kiosk,-4.20\n".utf8))
		let match = CSVProfile.match(for: file, in: [profile], detected: try file.detectedLayout())
		#expect(match == .same(profile))
		#expect(match.answeredDateOrder(in: file) == .monthDayYear)
		#expect(try profile.read(file, currency: "EUR")?.transactions.map(\.bookingDate) == [Day(year: 2026, month: 11, day: 3)])
	}

	@Test("A date that the chosen order cannot read keeps the profile from applying, and the preview reads it day first")
	func contradictedProfile() throws {
		let profile = try Self.answered()
		let file = try CSVFile(data: Data("Date,Name,Amount\n11/03/2026,Kiosk,-4.20\n13/11/2026,Bakery,-2.00\n".utf8))
		#expect(try profile.read(file, currency: "EUR") == nil)
		let match = CSVProfile.match(for: file, in: [profile], detected: try file.detectedLayout())
		guard case let .changed(_, start) = match else {
			Issue.record("A contradicting date must open the preview")
			return
		}
		#expect(match.answeredDateOrder(in: file) == nil)
		#expect(start.dateOrder == .dayMonthYear)
		let preview = try file.preview(start, currency: "EUR")
		#expect(preview.ambiguousDate == nil)
		#expect(preview.transactions.map(\.bookingDate) == [Day(year: 2026, month: 3, day: 11), Day(year: 2026, month: 11, day: 13)])
	}

	@Test("A profile answers only while its chosen order and date column are those of its layout, and an older profile answers nothing")
	func answerFollowsTheLayout() throws {
		var profile = try Self.answered()
		#expect(profile.dateOrderAnswer == DateOrderAnswer(order: .monthDayYear, bookingDate: "Date", valueDate: nil))
		#expect(profile.answersDateOrder)
		profile.layout.dateOrder = .dayMonthYear
		#expect(!profile.answersDateOrder)
		profile.layout.dateOrder = .monthDayYear
		profile.layout.assign(1, to: .bookingDate)
		#expect(!profile.answersDateOrder)
		let older = Data("""
		{"name":"Card CSV","header":["Date","Name","Amount"],"delimiter":",",
		"layout":{"encoding":"utf8","columns":{"bookingDate":0,"name":1,"amount":2},"dateOrder":"monthDayYear","createsCategories":false}}
		""".utf8)
		let decoded = try JSONDecoder().decode(CSVProfile.self, from: older)
		#expect(decoded.dateOrderAnswer == nil)
		#expect(!decoded.answersDateOrder)
		let file = try CSVFile(data: Data("Date,Name,Amount\n11/03/2026,Kiosk,-4.20\n11/04/2026,Bakery,-2.00\n".utf8))
		#expect(try decoded.read(file, currency: "EUR") == nil)
		#expect(CSVProfile.match(for: file, in: [decoded], detected: try file.detectedLayout()).answeredDateOrder(in: file) == nil)
		#expect(try JSONDecoder().decode(CSVProfile.self, from: JSONEncoder().encode(try Self.answered())) == (try Self.answered()))
	}

	@Test("An answer for the column \"Date\" does not answer for a booking date in the column \"Booking date\"", .bug("https://github.com/MonetenApp/Moneten/pull/525"))
	func answerBelongsToItsColumn() throws {
		let original = try CSVFile(data: Data("Date,Name,Amount\n11/03/2026,Kiosk,-4.20\n".utf8))
		let layout = try original.detectedLayout()
		#expect(layout.dateOrder == .dayMonthYear)
		let profile = CSVProfile(name: "Card CSV", header: original.header, layout: layout, delimiter: original.delimiter,
			dateOrderAnswer: DateOrderAnswer(order: .dayMonthYear, layout: layout, header: original.header))
		#expect(profile.answersDateOrder)
		let file = try CSVFile(data: Data("Name,Amount,Booking date\nKiosk,-1.00,11/03/2026\n".utf8))
		let match = CSVProfile.match(for: file, in: [profile], detected: try file.detectedLayout())
		guard case let .changed(_, start) = match else {
			Issue.record("A moved header must open the preview from the profile")
			return
		}
		#expect(start.columns[.bookingDate] == 2)
		#expect(match.answeredDateOrder(in: file) == nil)
		var question = DateOrderQuestion(answer: match.answeredDateOrder(in: file))
		let preview = try file.preview(start, currency: "EUR")
		question.read(preview)
		#expect(question.asks(start))
		#expect(!question.allowsImport(preview))
	}

	@Test("A repeated booking date or value date title, also with spaces around it, keeps no answer, so the file asks", .bug("https://github.com/MonetenApp/Moneten/pull/525"), arguments: [
		("Date,Date,Name,Amount\n11/03/2026,05/06/2026,Kiosk,-1.00\n", CSVField.bookingDate, 1),
		("Date, Date ,Name,Amount\n11/03/2026,05/06/2026,Kiosk,-1.00\n", CSVField.bookingDate, 1),
		("Date,Value date,Value date,Name,Amount\n11/03/2026,11/04/2026,05/06/2026,Kiosk,-1.00\n", CSVField.valueDate, 2),
		("Date,Value date, Value date,Name,Amount\n11/03/2026,11/04/2026,05/06/2026,Kiosk,-1.00\n", CSVField.valueDate, 2),
	])
	func repeatedTitle(text: String, field: CSVField, moved: Int) throws {
		let file = try CSVFile(data: Data(text.utf8))
		let hasValueDate = field == .valueDate
		var layout = CSVLayout(encoding: file.encoding, columns: [.bookingDate: 0, .name: hasValueDate ? 3 : 2, .amount: hasValueDate ? 4 : 3],
			dateOrder: .dayMonthYear, decimalMark: nil)
		if hasValueDate { layout.columns[.valueDate] = 1 }
		let answer = try #require(DateOrderAnswer(order: .dayMonthYear, layout: layout, header: file.header))
		var profile = CSVProfile(name: "Card CSV", header: file.header, layout: layout, delimiter: file.delimiter, dateOrderAnswer: answer)
		#expect(!profile.answersDateOrder)
		// An older version that keeps the unknown answer points the field at the other column of the same title.
		profile.layout.columns[field] = moved
		#expect(!profile.answersDateOrder)
		let match = CSVProfile.match(for: file, in: [profile], detected: profile.layout)
		#expect(match == .same(profile))
		#expect(match.answeredDateOrder(in: file) == nil)
		#expect(try profile.read(file, currency: "EUR") == nil)
	}

	@Test("An answer stops counting when only the title of the value date column changes")
	func valueDateTitle() throws {
		let answer = DateOrderAnswer(order: .dayMonthYear, bookingDate: "Date", valueDate: "Value date")
		let layout = CSVLayout(encoding: .utf8, columns: [.bookingDate: 0, .valueDate: 1, .name: 2, .amount: 3], dateOrder: .dayMonthYear, decimalMark: nil)
		#expect(answer.answers(layout, header: ["Date", "Value date", "Name", "Amount"]))
		#expect(!answer.answers(layout, header: ["Date", "Valuta", "Name", "Amount"]))
		var without = layout
		without.columns[.valueDate] = nil
		#expect(!answer.answers(without, header: ["Date", "Value date", "Name", "Amount"]))
	}

	@Test("An added empty title still suggests the saved column mapping")
	func emptyTitles() throws {
		let original = try CSVFile(data: Data("Datum;Name;Betrag;\n".utf8))
		let profile = CSVProfile(name: "Empty titles", header: original.header, layout: try original.detectedLayout(), delimiter: original.delimiter)
		let file = try CSVFile(data: Data("Datum;;Name;Betrag;\n".utf8))
		guard case let .changed(_, layout) = CSVProfile.match(for: file, in: [profile], detected: try file.detectedLayout()) else {
			Issue.record("Empty titles must not count as repeated names")
			return
		}
		#expect(layout.columns[.name] == 2)
		#expect(layout.columns[.amount] == 3)
	}

	@Test("Missing category options and unknown column fields keep a profile readable")
	func tolerantLayout() throws {
		let profile = try Self.broker()
		var json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(profile)) as? [String: Any])
		var layout = try #require(json["layout"] as? [String: Any])
		layout.removeValue(forKey: "createsCategories")
		var columns = try #require(layout["columns"] as? [String: Any])
		columns["futureField"] = 99
		layout["columns"] = columns
		json["layout"] = layout
		let decoded = try JSONDecoder().decode([CSVProfile].self, from: JSONSerialization.data(withJSONObject: [json]))
		#expect(decoded.count == 1)
		#expect(decoded.first?.layout.createsCategories == false)
		#expect(decoded.first?.layout.columns[.amount] == 6)
	}

	@Test("A later file with the same header row matches the saved profile")
	func sameHeader() throws {
		let profile = try Self.broker()
		let second = try CSVFile(data: Data("\(Self.header)\n02.11.2026;02.11.2026;Broker AG;;;Dividende;12,00;EUR;\n".utf8))
		#expect(CSVProfile.match(for: second, in: [profile], detected: try second.detectedLayout()) == .same(profile))
		var newer = profile
		newer.name = "Broker neu"
		newer.layout.decimalMark = .comma
		#expect(CSVProfile.match(for: second, in: [profile, newer], detected: try second.detectedLayout()) == .same(newer))
		#expect(try second.preview(profile.layout, currency: "EUR").transactions.map(\.purpose) == ["Dividende"])
	}

	@Test("A file whose bank added a column starts from the profile, with each field in the column of the same title")
	func headerChanged() throws {
		let profile = try Self.broker()
		let changed = try CSVFile(data: Data("Datum;Valuta;Kategorie;Empfänger;IBAN;BIC;Text;Betrag;Währung;Notiz\n".utf8))
		var layout = profile.layout
		layout.columns = [.bookingDate: 0, .valueDate: 1, .category: 2, .name: 3, .iban: 4, .bic: 5, .purpose: 6, .amount: 7, .currency: 8, .comment: 9]
		#expect(CSVProfile.match(for: changed, in: [profile], detected: try changed.detectedLayout()) == .changed(profile, layout))
		let other = try CSVFile(data: Data("Date,Payee,Amount\n".utf8))
		#expect(CSVProfile.match(for: other, in: [profile], detected: try other.detectedLayout()) == .none)
		let anotherBank = try CSVFile(data: Data("Buchungstag;Wertstellung;Empfänger;IBAN;Verwendungszweck;Betrag;Währung\n".utf8))
		#expect(CSVProfile.match(for: anotherBank, in: [profile], detected: try anotherBank.detectedLayout()) == .none)
	}

	@Test("A changed header keeps separate debit and credit columns with the same title")
	func repeatedHeader() throws {
		let original = try CSVFile(data: Data("Datum;Betrag;Betrag\n01.11.2026;10,00;0,00\n".utf8))
		var layout = try original.detectedLayout()
		layout.assign(1, to: .debit)
		layout.assign(2, to: .credit)
		let profile = CSVProfile(name: "Separate amounts", header: original.header, layout: layout, delimiter: original.delimiter)
		let changed = try CSVFile(data: Data("Datum;Extra;Betrag;Betrag\n01.11.2026;Note;10,00;0,00\n".utf8))
		guard case let .changed(_, moved) = CSVProfile.match(for: changed, in: [profile], detected: try changed.detectedLayout()) else {
			Issue.record("The profile must match the moved columns")
			return
		}
		#expect(moved.columns[.debit] == 2)
		#expect(moved.columns[.credit] == 3)
		#expect(try changed.preview(moved, currency: "EUR").transactions.map(\.amountMinor) == [-1000])
	}

	@Test("A changed number of repeated header titles does not remap a saved profile", arguments: ["Datum;Betrag", "Datum;Betrag;Betrag;Betrag"])
	func repeatedHeaderCountChanged(header: String) throws {
		let original = try CSVFile(data: Data("Datum;Betrag;Betrag\n".utf8))
		var layout = try original.detectedLayout()
		layout.assign(1, to: .debit)
		layout.assign(2, to: .credit)
		let profile = CSVProfile(name: "Separate amounts", header: original.header, layout: layout, delimiter: original.delimiter)
		let changed = try CSVFile(data: Data((header + "\n").utf8))
		#expect(CSVProfile.match(for: changed, in: [profile], detected: try changed.detectedLayout()) == .none)
	}

	@Test("A profile reads a file with its header row, and gives nil when the file does not read in it, so the preview opens")
	func quietRead() throws {
		var profile = try Self.broker()
		let file = try CSVFile(data: "\(Self.header)\n02.11.2026;02.11.2026;Bäckerei;;;Brot;-2,00;EUR;\n".data(using: .windowsCP1252)!)
		profile.layout.encoding = .windows1252
		#expect(try profile.read(file, currency: "EUR")?.transactions.map(\.name) == ["Bäckerei"])
		profile.layout.encoding = .utf8
		#expect(try profile.read(file, currency: "EUR") == nil)
		let utf8 = try CSVFile(data: Data("\(Self.header)\n02.11.2026;02.11.2026;Bäckerei;;;Brot;-2,00;EUR;\n".utf8))
		profile.layout.encoding = .windows1252
		#expect(try profile.read(utf8, currency: "EUR") == nil)
		let ascii = try CSVFile(data: Data("Datum;Name;Betrag\n02.11.2026;Kiosk;-2,00\n".utf8))
		var plain = CSVProfile(name: "Plain", header: ascii.header, layout: try ascii.detectedLayout(), delimiter: ascii.delimiter)
		plain.layout.encoding = .windows1252
		#expect(try plain.read(ascii, currency: "EUR")?.transactions.map(\.name) == ["Kiosk"])
		#expect(plain.previewLayout(for: ascii).encoding == .utf8)
		profile.layout.encoding = .isoLatin1
		profile.layout.dateOrder = .dayMonthYear
		#expect(file.encoding == .windows1252)
		#expect(try profile.read(file, currency: "EUR")?.transactions.map(\.name) == ["Bäckerei"])
		profile.layout.encoding = .windows1252
		profile.layout.dateOrder = .monthDayYear
		let late = try CSVFile(data: "\(Self.header)\n13/11/2026;13/11/2026;Kiosk;;;Zeitung;-2,00;EUR;\n".data(using: .windowsCP1252)!)
		#expect(try profile.read(late, currency: "EUR") == nil)
	}

	@Test("A profile fallback keeps detected encoding and all mapped settings", arguments: [false, true])
	func fallbackEncoding(headerChanged: Bool) throws {
		let header = "Date;Name;Purpose;Amount;Category"
		let row = "03.11.2026;Bäckerei;Frühstück;-4,20;Büro"
		let original = try CSVFile(data: "\(header)\n\(row)\n".data(using: .windowsCP1252)!)
		var layout = try original.detectedLayout()
		layout.decimalMark = .comma
		layout.createsCategories = true
		let profile = CSVProfile(name: "Text encoding", header: original.header, layout: layout, delimiter: original.delimiter)
		let nextHeader = headerChanged ? "Date;Extra;Name;Purpose;Amount;Category" : header
		let nextRow = headerChanged ? "03.11.2026;Note;Bäckerei;Frühstück;-4,20;Büro" : row
		let file = try CSVFile(data: Data("\(nextHeader)\n\(nextRow)\n".utf8))
		#expect(file.encoding == .utf8)
		#expect(try profile.read(file, currency: "EUR") == nil)
		let start: CSVLayout
		switch CSVProfile.match(for: file, in: [profile], detected: try file.detectedLayout()) {
		case let .same(saved): start = saved.previewLayout(for: file)
		case let .changed(_, moved): start = moved
		case .none: Issue.record("The profile must remain a starting point"); return
		}
		#expect(start.encoding == .utf8)
		#expect(start.dateOrder == layout.dateOrder)
		#expect(start.decimalMark == .comma)
		#expect(start.createsCategories)
		#expect(start.columns[.name] == (headerChanged ? 2 : 1))
		let parsed = try file.with(start.encoding).preview(start, currency: "EUR").parsed
		#expect(parsed.transactions.map(\.name) == ["Bäckerei"])
		#expect(parsed.transactions.map(\.purpose) == ["Frühstück"])
		#expect(parsed.transactions.map(\.amountMinor) == [-420])
		#expect(Array(parsed.categories.values) == ["Büro"])
	}

	@Test("A saved profile comes back with every setting")
	func codable() throws {
		var profile = try Self.broker()
		profile.layout.dateOrder = .monthDayYear
		profile.layout.decimalMark = .comma
		profile.layout.encoding = .isoLatin1
		let data = try JSONEncoder().encode([profile])
		#expect(try JSONDecoder().decode([CSVProfile].self, from: data) == [profile])
	}

	@Test("Saving replaces the profile of the same name, and saving under a new name renames")
	func saveRenameDelete() throws {
		let broker = try Self.broker()
		var other = broker
		other.name = "Card CSV"
		other.header = ["Date", "Payee", "Amount"]
		var profiles = [broker, other]
		var changed = broker
		changed.layout.dateOrder = .monthDayYear
		profiles.save(changed, replacing: nil)
		#expect(profiles == [other, changed])
		var renamed = changed
		renamed.name = "Depot CSV"
		profiles.save(renamed, replacing: "Broker CSV")
		#expect(profiles.map(\.name) == ["Card CSV", "Depot CSV"])
	}

	@Test("A category column gives each row the text of its cell, and the profile keeps the option to create categories")
	func categoryColumn() throws {
		let file = try CSVFile(data: Data("Datum;Name;Kategorie;Betrag\n01.11.2026;Kiosk;Food;-4,20\n02.11.2026;Tierarzt;Pets;-80,00\n03.11.2026;Bank;;-1,00\n".utf8))
		var layout = try file.detectedLayout()
		#expect(layout.columns[.category] == 2)
		layout.createsCategories = true
		let parsed = try file.preview(layout, currency: "EUR").parsed
		#expect(parsed.transactions.map { parsed.categories[$0.id] } == ["Food", "Pets", nil])
		let profile = CSVProfile(name: "Card CSV", header: file.header, layout: layout, delimiter: file.delimiter)
		#expect(try JSONDecoder().decode(CSVProfile.self, from: JSONEncoder().encode(profile)).layout.createsCategories)
	}

	@Test("Only a file with a header row of known keywords can be saved as a profile, so no transaction row goes into the settings")
	func headerRowOnly() throws {
		#expect(try CSVFile(data: Data("\(Self.header)\n\(Self.row)\n".utf8)).hasHeaderRow)
		#expect(try !CSVFile(data: Data("01.11.2026;Kiosk;-1,50\n".utf8)).hasHeaderRow)
	}

	@Test("A new name renames the matched profile only while its settings are applied, so picking None and saving keeps it")
	func renameOnlyMatched() throws {
		let giro = try Self.broker()
		var depot = giro
		depot.name = "Depot CSV"
		depot.header = ["Date", "Payee", "Amount"]
		var profiles = [giro, depot]
		var other = giro
		other.name = "Other CSV"
		profiles.save(other, matched: "Broker CSV", applied: nil)
		#expect(profiles.map(\.name) == ["Broker CSV", "Depot CSV", "Other CSV"])
		var renamed = giro
		renamed.name = "Broker neu"
		profiles.save(renamed, matched: "Broker CSV", applied: "Broker CSV")
		#expect(profiles.map(\.name) == ["Depot CSV", "Other CSV", "Broker neu"])
	}
}
