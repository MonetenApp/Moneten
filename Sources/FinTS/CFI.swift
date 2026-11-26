import Domain

/// The asset class of a CFI code, the classification of financial instruments of ISO 10962, which a bank can send for a
/// holding of MT535 in field 12C with the qualifier CLAS. The first letter of a code is its category and the second its
/// group, so one table of both letters holds every rule. A pair that the table does not list gives no class, because
/// its instruments are of several kinds or of none of the eight classes: limited partnership units (EL), structured
/// instruments (EY, DS, DE), other equities and debt (EM, DM), rights and warrants (R), derivatives (O, F, S, H, I, J, K, L),
/// referential instruments such as commodities and currencies (T), and others (M).
enum CFI {
	static let classes: [String: AssetClass] = [
		// Equities: shares, preferred shares, convertible shares, and depositary receipts on them. The edition of 2001
		// names preference shares ER and EV, and units of investment funds EU, which the edition of 2015 moved to C.
		"ES": .stocks, "EP": .stocks, "EC": .stocks, "EF": .stocks, "ED": .stocks, "ER": .stocks, "EV": .stocks, "EU": .funds,
		// Collective investment vehicles: exchange traded funds and real estate investment trusts have their own group.
		// Every other group is a fund: standard investment funds, hedge funds, pension funds, funds of funds, private
		// equity funds, and others.
		"CE": .etfs, "CB": .realEstate, "CI": .funds, "CH": .funds, "CS": .funds, "CF": .funds, "CP": .funds, "CM": .funds,
		// Debt: bonds, convertible bonds, bonds with warrants, medium-term notes, money market instruments, asset-backed and
		// mortgage-backed securities, municipal bonds, and depositary receipts on debt.
		"DB": .bonds, "DC": .bonds, "DW": .bonds, "DT": .bonds, "DY": .bonds, "DA": .bonds, "DG": .bonds, "DN": .bonds, "DD": .bonds,
	]

	/// The class of `code`, or nil for a code that the table does not list or that is not six letters A to Z.
	static func assetClass(of code: String) -> AssetClass? {
		guard code.utf8.count == 6, code.utf8.allSatisfy({ (UInt8(ascii: "A")...UInt8(ascii: "Z")).contains($0) }) else { return nil }
		return classes[String(code.prefix(2))]
	}
}
