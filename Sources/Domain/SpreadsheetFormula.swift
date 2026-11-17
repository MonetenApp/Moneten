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
		guard let sign = field.unicodeScalars.first(where: { !$0.properties.isWhitespace }), signs.contains(sign) else { return field }
		return "'" + field
	}
}
