import Foundation

/// The CSV file of "Export Transactions...": a header and one line per transaction, separated by semicolons,
/// with dates and decimal marks in the format of a locale and amounts without thousands separators.
public enum TransactionCSV {
	public static func rows(visible: [Transaction], selection: Set<UUID>) -> [Transaction] {
		let selected = visible.filter { selection.contains($0.id) }
		return selected.isEmpty ? visible : selected
	}

	static let columns = ["Date", "Value date", "Category", "Name", "Purpose", "Account", "Bank", "Amount", "Currency", "Own account", "Booking text",
		"End-to-end reference", "Mandate reference", "Creditor ID", "Comment", "Checked", "Pending"]

	/// The file in UTF-8 with a byte order mark, so that spreadsheet programs read umlauts correctly.
	public static func data(_ rows: [Transaction], ledger: Ledger, locale: Locale = .current) throws -> Data {
		Data([0xEF, 0xBB, 0xBF]) + Data(try text(rows, ledger: ledger, locale: locale).utf8)
	}

	static func text(_ rows: [Transaction], ledger: Ledger, locale: Locale) throws -> String {
		// Every date is Gregorian, in the order of day, month, and year and with the separators of the locale, in ASCII
		// digits. A date of the Buddhist, the Islamic, the Japanese, or the Republic of China calendar, such as
		// 03/11/2569 for 3 November 2026 in Thailand, has a year that a spreadsheet and the import of this app read as
		// a Gregorian year, so the day would come back about 543 years later.
		var dateLocale = Locale.Components(locale: locale)
		dateLocale.numberingSystem = "latn"
		dateLocale.calendar = .gregorian
		let dates = DateFormatter()
		dates.locale = Locale(components: dateLocale)
		dates.calendar = Calendar(identifier: .gregorian)
		dates.timeZone = TimeZone(identifier: "UTC")
		dates.dateFormat = DateFormatter.dateFormat(fromTemplate: "ddMMyyyy", options: 0, locale: dates.locale)
		var calendar = Calendar(identifier: .gregorian)
		calendar.timeZone = TimeZone(identifier: "UTC")!
		func day(_ d: Day?) -> String {
			guard let d, let date = calendar.date(from: DateComponents(year: d.year, month: d.month, day: d.day)) else { return "" }
			// The Arabic patterns put direction marks between the fields, which no spreadsheet and no import reads as part
			// of a date.
			return String(String.UnicodeScalarView(dates.string(from: date).unicodeScalars.filter { !directionMarks.contains($0) }))
		}
		let mark = locale.decimalSeparator ?? "."
		func amount(_ minorUnits: Int64, _ currency: String) -> String {
			var text = AmountText.text(minorUnits, currency)
			if !text.contains(".") { text += "." }
			let places = text.count - text.distance(from: text.startIndex, to: text.firstIndex(of: ".")!) - 1
			text += String(repeating: "0", count: max(0, 2 - places))
			return text.replacingOccurrences(of: ".", with: mark)
		}
		let accounts = Dictionary(ledger.accounts.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
		var lines = [columns.joined(separator: ";")]
		lines.reserveCapacity(rows.count + 1)
		for (i, t) in rows.enumerated() {
			if i % 1_000 == 0 { try Task.checkCancellation() }
			let own = accounts[t.accountID].map { $0.iban?.electronic ?? $0.accountNumber ?? $0.name } ?? ""
			let fields = [day(t.bookingDate), day(t.valueDate), categoryPath(t.categoryID, in: ledger), t.name, t.purpose, t.counterpartyIBAN ?? "",
				t.counterpartyBIC ?? "", amount(t.amountMinor, t.currency), t.currency, own, t.bookingText ?? "", t.endToEndReference ?? "", t.mandateReference ?? "",
				t.creditorID ?? "", t.comment ?? "", t.isChecked ? "X" : "", t.isPending ? "X" : ""]
			lines.append(fields.enumerated().map { quoted($0.element, protectFormula: $0.offset != 7) }.joined(separator: ";"))
		}
		return lines.joined(separator: "\r\n") + "\r\n"
	}

	/// The left-to-right mark, the right-to-left mark, and the Arabic letter mark.
	private static let directionMarks: Set<Unicode.Scalar> = ["\u{200E}", "\u{200F}", "\u{061C}"]

	private static func categoryPath(_ id: UUID?, in ledger: Ledger) -> String {
		guard let id, var c = ledger.category(id) else { return ledger.defaultCategory?.name ?? "" }
		var names = [c.name]
		while let p = c.parentID, let parent = ledger.category(p) {
			names.insert(parent.name, at: 0)
			c = parent
		}
		return names.joined(separator: " - ")
	}

	private static func quoted(_ field: String, protectFormula: Bool) -> String {
		var field = field
		if protectFormula { field = SpreadsheetFormula.escaped(field) }
		guard field.contains(where: { $0 == ";" || $0 == "\"" || $0.isNewline }) else { return field }
		return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
	}
}
