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
		return CSVProfile(name: "Broker CSV", header: file.header, layout: layout)
	}

	@Test("A later file with the same header row matches the saved profile")
	func sameHeader() throws {
		let profile = try Self.broker()
		let second = try CSVFile(data: Data("\(Self.header)\n02.11.2026;02.11.2026;Broker AG;;;Dividende;12,00;EUR;\n".utf8))
		#expect(CSVProfile.match(for: second, in: [profile], detected: try second.detectedLayout()) == .same(profile))
		var newer = profile
		newer.name = "Broker neu"
		newer.layout.dateOrder = .monthDayYear
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
		var plain = CSVProfile(name: "Plain", header: ascii.header, layout: try ascii.detectedLayout())
		plain.layout.encoding = .windows1252
		#expect(try plain.read(ascii, currency: "EUR")?.transactions.map(\.name) == ["Kiosk"])
		profile.layout.encoding = .isoLatin1
		profile.layout.dateOrder = .dayMonthYear
		#expect(file.encoding == .windows1252)
		#expect(try profile.read(file, currency: "EUR")?.transactions.map(\.name) == ["Bäckerei"])
		profile.layout.encoding = .windows1252
		profile.layout.dateOrder = .monthDayYear
		let late = try CSVFile(data: "\(Self.header)\n13/11/2026;13/11/2026;Kiosk;;;Zeitung;-2,00;EUR;\n".data(using: .windowsCP1252)!)
		#expect(try profile.read(late, currency: "EUR") == nil)
	}

	@Test("A stored list keeps the profiles that read when one does not")
	func lenientList() throws {
		let profile = try Self.broker()
		let good = String(data: try JSONEncoder().encode(profile), encoding: .utf8)!
		let data = Data("[\(good), {\"name\": \"Broken\"}]".utf8)
		#expect(CSVProfile.list(from: data) == [profile])
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
		let profile = CSVProfile(name: "Card CSV", header: file.header, layout: layout)
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
