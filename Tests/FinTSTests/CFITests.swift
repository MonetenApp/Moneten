import Domain
import Testing
@testable import FinTS

@Suite("Asset class of a CFI code (ISO 10962)")
struct CFITests {
	@Test("Shares, ETFs, REITs, other funds, and debt give their class", arguments: [
		("ESVUFR", AssetClass.stocks), ("EPNXFR", .stocks), ("ECVUFR", .stocks), ("EFNXFR", .stocks), ("EDSXFR", .stocks),
		// ER and EV are the preference shares of the edition of 2001, EU its units of investment funds.
		("ERVUFR", .stocks), ("EVVUFR", .stocks), ("EUOMFR", .funds),
		("CEOGLS", .etfs), ("CBOIRS", .realEstate), ("CIOGLS", .funds), ("CHSXXX", .funds), ("CSOXXX", .funds), ("CFOGLS", .funds), ("CPOXXX", .funds), ("CMXXXX", .funds),
		("DBFTFB", .bonds), ("DCFTFB", .bonds), ("DWFTFB", .bonds), ("DTFXFR", .bonds), ("DYFXXR", .bonds), ("DGFXXR", .bonds), ("DAFXXR", .bonds),
		("DNFXXR", .bonds), ("DDFXXR", .bonds),
	])
	func mapped(code: String, expected: AssetClass) {
		#expect(CFI.assetClass(of: code) == expected)
	}

	@Test("Codes whose class the standard does not tell give none", arguments: [
		// Limited partnership units, structured instruments, and other equities.
		"ELXXXR", "EYXXXX", "EMXXXX",
		// Structured products with and without capital protection, and other debt.
		"DSXXXX", "DEXXXX", "DMXXXX",
		// Rights and warrants, options, futures, referential instruments such as commodities and currencies, and others.
		"RWSNCA", "OCASPS", "FFICSX", "TTXXXX", "TCXXXX", "MMRXXX",
		// Codes of another form.
		"", "ES", "esvufr", "ESVUFR1", "E1VUFR", "ÄSVUFR",
	])
	func unmapped(code: String) {
		#expect(CFI.assetClass(of: code) == nil)
	}
}
