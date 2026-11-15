import Domain
import Foundation
import Testing
@testable import Import

@Suite("Account named in a file")
struct FileAccountImportTests {
	static let entry = """
	<Ntry><Amt Ccy="EUR">89.00</Amt><CdtDbtInd>DBIT</CdtDbtInd><Sts><Cd>BOOK</Cd></Sts><BookgDt><Dt>2026-11-03</Dt></BookgDt></Ntry>
	"""

	@Test("A CAMT statement names the IBAN of its account, and not the IBAN of a counterparty")
	func camtIBAN() throws {
		let camt = """
		<?xml version="1.0" encoding="UTF-8"?>
		<Document xmlns="urn:iso:std:iso:20022:tech:xsd:camt.053.001.08"><BkToCstmrStmt><Stmt>
		<Acct><Id><IBAN>DE02120300000000202051</IBAN></Id></Acct>\(Self.entry)</Stmt></BkToCstmrStmt></Document>
		"""
		#expect(try TransactionFileImporter.parse(Data(camt.utf8), currency: "EUR").account == .iban("DE02120300000000202051"))
		let noAccount = """
		<?xml version="1.0" encoding="UTF-8"?>
		<Document xmlns="urn:iso:std:iso:20022:tech:xsd:camt.052.001.08"><BkToCstmrAcctRpt><Rpt>
		<Ntry><Amt Ccy="EUR">89.00</Amt><CdtDbtInd>DBIT</CdtDbtInd><BookgDt><Dt>2026-11-03</Dt></BookgDt>
		<NtryDtls><TxDtls><RltdPties><CdtrAcct><Id><IBAN>DE02120300000000202051</IBAN></Id></CdtrAcct></RltdPties></TxDtls></NtryDtls></Ntry></Rpt></BkToCstmrAcctRpt></Document>
		"""
		#expect(try TransactionFileImporter.parse(Data(noAccount.utf8), currency: "EUR").account == nil)
	}

	@Test("A CAMT report names an account without an IBAN by its number")
	func camtNumber() throws {
		let camt = """
		<?xml version="1.0" encoding="UTF-8"?>
		<Document xmlns="urn:iso:std:iso:20022:tech:xsd:camt.052.001.08"><BkToCstmrAcctRpt><Rpt>
		<Acct><Id><Othr><Id>0012345678</Id></Othr></Id></Acct>\(Self.entry)</Rpt></BkToCstmrAcctRpt></Document>
		"""
		#expect(try TransactionFileImporter.parse(Data(camt.utf8), currency: "EUR").account == .number(bankCode: nil, account: "0012345678"))
		let empty = camt.replacingOccurrences(of: "<Id>0012345678</Id>", with: "<Id></Id>")
		#expect(try TransactionFileImporter.parse(Data(empty.utf8), currency: "EUR").account == nil)
	}

	@Test("An MT940 file names its account in field 25 as an IBAN or as bank code and account number", arguments: [
		(":25:DE02120300000000202051", FileAccount.iban("DE02120300000000202051")),
		(":25:12030000/0000202051", FileAccount.number(bankCode: "12030000", account: "0000202051")),
		(":25:12030000/202051EUR", FileAccount.number(bankCode: "12030000", account: "202051")),
		(":25:0012345678", FileAccount.number(bankCode: nil, account: "0012345678")),
		(":25:DE02120300000000202051EUR", FileAccount.iban("DE02120300000000202051")),
		(":25:COBADEFFXXX/0000202051", FileAccount.number(bankCode: nil, account: "0000202051")),
		(":25:COBADEFFXXX/DE02120300000000202051", FileAccount.iban("DE02120300000000202051")),
		(":25:MT84MALT011000012345MTLCAST001S", FileAccount.iban("MT84MALT011000012345MTLCAST001S")),
		(":25:DE16120300000001000012EUR", FileAccount.iban("DE16120300000001000012")),
		(":25:/00797453990", FileAccount.number(bankCode: nil, account: "00797453990")),
	])
	func mt940(field: String, account: FileAccount) throws {
		let text = ":20:STARTUMS\n\(field)\n:28C:0\n:60F:C261031EUR1000,00\n:61:2611031103DR89,00NMSCNONREF\n:86:105?20Abschlag\n:62F:C261103EUR911,00\n-\n"
		#expect(try TransactionFileImporter.parse(Data(text.utf8), currency: "EUR").account == account)
	}

	@Test("A file with the statements of two accounts is refused")
	func twoAccounts() throws {
		let camt = """
		<?xml version="1.0" encoding="UTF-8"?>
		<Document xmlns="urn:iso:std:iso:20022:tech:xsd:camt.053.001.08"><BkToCstmrStmt>
		<Stmt><Acct><Id><IBAN>DE02120300000000202051</IBAN></Id></Acct>\(Self.entry)</Stmt>
		<Stmt><Acct><Id><Othr><Id>0099887766</Id></Othr></Id></Acct>\(Self.entry)</Stmt></BkToCstmrStmt></Document>
		"""
		#expect(throws: TransactionFileImporter.Failure.severalAccounts) { try TransactionFileImporter.parse(Data(camt.utf8), currency: "EUR") }
		let statement = ":28C:0\n:60F:C261031EUR1000,00\n:61:2611031103DR89,00NMSCNONREF\n:86:105?20Abschlag\n:62F:C261103EUR911,00\n-\n"
		let mt940 = ":20:STARTUMS\n:25:12030000/0000202051\n\(statement):20:STARTUMS\n:25:12030000/0099887766\n\(statement)"
		#expect(throws: TransactionFileImporter.Failure.severalAccounts) { try TransactionFileImporter.parse(Data(mt940.utf8), currency: "EUR") }
		let same = ":20:STARTUMS\n:25:12030000/0000202051\n\(statement):20:STARTUMS\n:25:12030000/0000202051\n\(statement)"
		#expect(try TransactionFileImporter.parse(Data(same.utf8), currency: "EUR").account == .number(bankCode: "12030000", account: "0000202051"))
	}
	@Test("A file keeps an omitted currency distinct from its explicit account fallback", arguments: ["EUR", "USD"])
	func declaredCurrency(fallback: String) throws {
		let camt = "<Document xmlns=\"urn:iso:std:iso:20022:tech:xsd:camt.053.001.08\"><BkToCstmrStmt><Stmt>" + Self.entry + "</Stmt></BkToCstmrStmt></Document>"
		let explicit = try TransactionFileImporter.parse(Data(camt.utf8), currency: fallback)
		#expect(explicit.declaredCurrency == "EUR")
		#expect(explicit.transactions.map(\.currency) == ["EUR"])
		let missing = try TransactionFileImporter.parse(Data(camt.replacingOccurrences(of: " Ccy=\"EUR\"", with: "").utf8), currency: fallback)
		#expect(missing.declaredCurrency == nil)
		#expect(missing.transactions.map(\.currency) == [fallback])
		let mt940 = ":20:STARTUMS\n:60F:C261101EUR0,00\n:61:2611031103D89,00NDDTNONREF\n-\n"
		let explicitMT = try TransactionFileImporter.parse(Data(mt940.utf8), currency: fallback)
		#expect(explicitMT.declaredCurrency == "EUR")
		#expect(explicitMT.transactions.map(\.currency) == ["EUR"])
		let missingMT = try TransactionFileImporter.parse(Data(mt940.replacingOccurrences(of: ":60F:C261101EUR0,00\n", with: "").utf8), currency: fallback)
		#expect(missingMT.declaredCurrency == nil)
		#expect(missingMT.transactions.map(\.currency) == [fallback])
	}

}
