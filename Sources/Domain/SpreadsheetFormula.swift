/// A spreadsheet reads a cell that starts with a formula sign as a formula, which can show an error or open a link.
/// The CSV export and Copy of selected rows both write bank text into cells, so both escape it here, with one rule.
enum SpreadsheetFormula {
	/// The signs that start a formula. The full-width forms count too, because a spreadsheet in an East Asian locale
	/// can read them as the plain ones.
	private static let signs: Set<Unicode.Scalar> = ["=", "+", "-", "@", "\u{FF1D}", "\u{FF0B}", "\u{FF0D}", "\u{FF20}"]

	/// The field with an apostrophe in front when a spreadsheet could read it as a formula: when it starts with a tab, a
	/// carriage return, or a line feed, or when its first character after leading whitespace is a formula sign. A
	/// spreadsheet can trim the whitespace, so it cannot hide the sign. The apostrophe keeps the cell text. An amount
	/// never comes here, because a withdrawal starts with a minus sign.
	static func escaped(_ field: String) -> String {
		guard let first = field.unicodeScalars.first else { return field }
		if first == "\t" || first == "\r" || first == "\n" { return "'" + field }
		return startsWithSign(field.unicodeScalars[...]) ? "'" + field : field
	}

	/// A reader that splits at a comma, a tab, or a line break.
	private static let cellBreaks: Set<Unicode.Scalar> = [",", "\t", "\r", "\n"]

	/// The field escaped as one cell, and with an apostrophe after each comma, tab, or line break whose part, up to the next
	/// of these, starts with a formula sign after leading whitespace. The CSV export separates its fields with semicolons, but
	/// a spreadsheet in a region whose list separator is a comma, or one that splits at tabs, starts a new cell at each of
	/// these characters, and a quote in the middle of such a cell is plain text. Copy does not need this, because its fields
	/// hold no tab and a pasted line splits only at tabs.
	static func escapedInEveryPart(_ field: String) -> String {
		let scalars = escaped(field).unicodeScalars
		var result = String.UnicodeScalarView()
		var start = scalars.startIndex
		while let end = scalars[start...].firstIndex(where: cellBreaks.contains) {
			result.append(contentsOf: scalars[start...end])
			start = scalars.index(after: end)
			if startsWithSign(scalars[start...].prefix { !cellBreaks.contains($0) }) { result.append("'") }
		}
		result.append(contentsOf: scalars[start...])
		return String(result)
	}

	private static func startsWithSign(_ text: Substring.UnicodeScalarView) -> Bool {
		text.first { !$0.properties.isWhitespace }.map(signs.contains) ?? false
	}
}
