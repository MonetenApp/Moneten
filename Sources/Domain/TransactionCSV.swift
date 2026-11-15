import Foundation

/// The CSV file of "Export Transactions...": a header and one line per transaction, separated by semicolons,
/// with dates and decimal marks in the format of a locale and amounts without thousands separators.
public enum TransactionCSV {
	public static func rows(visible: [Transaction], selection: Set<UUID>) -> [Transaction] {
		selection.isEmpty ? visible : visible.filter { selection.contains($0.id) }
	}

	static let columns = ["Date", "Value date", "Category", "Name", "Purpose", "Account", "Bank", "Amount", "Currency", "Own account", "Booking text",
		"End-to-end reference", "Mandate reference", "Creditor ID", "Comment", "Checked", "Pending"]

	/// The file in UTF-8 with a byte order mark, so that spreadsheet programs read umlauts correctly.
	public static func data(_ rows: [Transaction], ledger: Ledger, locale: Locale = .current) throws -> Data {
		Data([0xEF, 0xBB, 0xBF]) + Data(try text(rows, ledger: ledger, locale: locale).utf8)
	}

	/// Throws `CancellationError` when the task that builds it is canceled.
	static func text(_ rows: [Transaction], ledger: Ledger, locale: Locale) throws -> String {
		let dates = DateFormatter()
		dates.locale = locale
		dates.timeZone = TimeZone(identifier: "UTC")
		dates.dateFormat = DateFormatter.dateFormat(fromTemplate: "ddMMyyyy", options: 0, locale: locale)
		var calendar = Calendar(identifier: .gregorian)
		calendar.timeZone = TimeZone(identifier: "UTC")!
		func day(_ d: Day?) -> String {
			guard let d, let date = calendar.date(from: DateComponents(year: d.year, month: d.month, day: d.day)) else { return "" }
			return dates.string(from: date)
		}
		let mark = locale.decimalSeparator ?? "."
		/// The decimal places of the currency, at least two, with the decimal mark of the locale.
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
			let own = accounts[t.accountID].map { $0.iban ?? $0.accountNumber ?? $0.name } ?? ""
			let fields = [day(t.bookingDate), day(t.valueDate), categoryPath(t.categoryID, in: ledger), t.name, t.purpose, t.counterpartyIBAN ?? "",
				t.counterpartyBIC ?? "", amount(t.amountMinor, t.currency), t.currency, own, t.bookingText ?? "", t.endToEndReference ?? "", t.mandateReference ?? "",
				t.creditorID ?? "", t.comment ?? "", t.isChecked ? "X" : "", t.isPending ? "X" : ""]
			lines.append(fields.map(quoted).joined(separator: ";"))
		}
		return lines.joined(separator: "\r\n") + "\r\n"
	}

	/// "Household - Food", or the name of the default category for a row without a category.
	private static func categoryPath(_ id: UUID?, in ledger: Ledger) -> String {
		guard let id, var c = ledger.category(id) else { return ledger.defaultCategory?.name ?? "" }
		var names = [c.name]
		while let p = c.parentID, let parent = ledger.category(p) {
			names.insert(parent.name, at: 0)
			c = parent
		}
		return names.joined(separator: " - ")
	}

	private static func quoted(_ field: String) -> String {
		guard field.contains(where: { $0 == ";" || $0 == "\"" || $0.isNewline }) else { return field }
		return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
	}
}
