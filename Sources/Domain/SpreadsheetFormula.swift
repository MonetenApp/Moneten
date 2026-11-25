/// A spreadsheet reads a cell that starts with a formula sign as a formula, which can show an error or open a link.
/// The CSV export and Copy of selected rows both write bank text into cells, so both escape it here.
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
		guard let sign = field.unicodeScalars.first(where: { !$0.properties.isWhitespace }), signs.contains(sign) else { return field }
		return "'" + field
	}

	/// A reader that splits at a comma, a tab, or a line break.
	private static let cellBreaks: Set<Unicode.Scalar> = [",", "\t", "\r", "\n"]

	/// The field escaped as one cell, and with an apostrophe at the start of each part, the text before the first comma,
	/// tab, or line break and the text after each of them up to the next, that a spreadsheet could read as a formula. The
	/// CSV export separates its fields with semicolons, but a spreadsheet in a region whose list separator is a comma, or
	/// one that splits at tabs, starts a new cell at each of these characters, and a quote in the middle of such a cell is
	/// plain text. Copy does not need this, because its fields hold no tab or line break and a pasted line splits at tabs.
	/// Excel can also split a pasted line at commas after Text to Columns with a comma, a setting this accepts.
	static func escapedInEveryPart(_ field: String) -> String {
		let scalars = escaped(field).unicodeScalars
		var result = String.UnicodeScalarView()
		var start = scalars.startIndex
		while true {
			let end = scalars[start...].firstIndex(where: cellBreaks.contains) ?? scalars.endIndex
			let part = scalars[start..<end]
			if startsFormula(part) { result.append("'") }
			result.append(contentsOf: part)
			guard end < scalars.endIndex else { return String(result) }
			result.append(scalars[end])
			start = scalars.index(after: end)
		}
	}

	/// Whether the first character of the part after leading whitespace, double quotes, control characters, and format
	/// characters is a formula sign. A reader reads a quote at the start of a cell as an empty quoted text and can drop a
	/// NUL or a zero-width space, so none of them hides the sign.
	private static func startsFormula(_ part: Substring.UnicodeScalarView) -> Bool {
		guard let sign = part.first(where: { !hides($0) }) else { return false }
		return signs.contains(sign)
	}

	/// A character that a reader can skip or drop before it reads a cell. Characters that some text renders as blank, such
	/// as U+3164, U+115F, U+2800, and U+FFFC, and the nonspacing marks such as U+034F and U+FE0F stay visible, because no
	/// known spreadsheet drops them before a formula sign.
	private static func hides(_ scalar: Unicode.Scalar) -> Bool {
		scalar.properties.isWhitespace || scalar == "\"" || [.control, .format].contains(scalar.properties.generalCategory)
	}
}
