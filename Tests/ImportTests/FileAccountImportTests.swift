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
		(":25:COBADEFFXXX/0000202051", FileAccount.number(bankCode: nil, account: "0000202051", bic: "COBADEFFXXX")),
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

	@Test("The library decides the named account, destination, and remembered-answer key")
	func accountDecision() throws {
		let savings = Account(position: 0, name: "Savings", kind: .savings, source: .offline)
		let giro = Account(position: 1, name: "Giro", kind: .giro, source: .offline, iban: "DE02120300000000202051")
		let named = try TransactionFileImporter.accountDecision([.iban("DE02120300000000202051")], selected: savings, accounts: [giro, savings], currency: "EUR")
		#expect(named.account == .iban("DE02120300000000202051"))
		#expect(named.destination == .other(giro))
		#expect(named.cacheKey == .iban("DE02120300000000202051"))
		let absent = try TransactionFileImporter.accountDecision([], selected: savings, accounts: [giro, savings], currency: "EUR")
		#expect(absent.account == nil && absent.cacheKey == nil && absent.destination == .selected)
		#expect(throws: TransactionFileImporter.Failure.severalAccounts) {
			try TransactionFileImporter.accountDecision([.iban("DE02120300000000202051"), .number(bankCode: nil, account: "0099887766")])
		}
	}

	static func mt940Data(_ fields: [String]) -> Data {
		Data((":20:STARTUMS\n" + fields.joined(separator: "\n") + "\n:60F:C261031EUR1000,00\n:61:2611031103DR89,00NMSCNONREF\n:62F:C261103EUR911,00\n-\n").utf8)
	}

	@Test("Equal account numbers at different BICs ask for the other bank and refuse a mixed file")
	func differentBICs() throws {
		let first = Account(position: 0, name: "First", kind: .giro, source: .offline, bic: "AAAADEFFXXX", accountNumber: "202051")
		let second = Account(position: 1, name: "Second", kind: .giro, source: .offline, bic: "BBBBDEFFXXX", accountNumber: "202051")
		let parsed = try TransactionFileImporter.parse(Self.mt940Data([":25:BBBBDEFFXXX/202051"]), currency: "EUR")
		let decision = try TransactionFileImporter.accountDecision([parsed.account], selected: first, accounts: [first, second], currency: "EUR")
		#expect(decision.destination == .other(second))
		#expect(throws: TransactionFileImporter.Failure.severalAccounts) {
			try TransactionFileImporter.parse(Self.mt940Data([":25:AAAADEFFXXX/202051", ":25:BBBBDEFFXXX/202051"]), currency: "EUR")
		}
	}

	@Test("Field 25 normalizes zero padding and ignores unreadable lines", arguments: [":25:12030000/202051", ":25:EUR"])
	func repeatedMT940Account(second: String) throws {
		let data = Self.mt940Data([":25:12030000/0000202051", second])
		let parsed = try TransactionFileImporter.parse(data, currency: "EUR")
		let savings = Account(position: 0, name: "Savings", kind: .savings, source: .offline)
		let decision = try TransactionFileImporter.accountDecision([parsed.account], selected: savings, currency: "EUR")
		#expect(decision.destination == .unknown)
		#expect(decision.cacheKey == .number(bankCode: "12030000", account: "202051"))
		let repeated = try TransactionFileImporter.accountDecision([.number(bankCode: "12030000", account: "202051")], selected: savings, currency: "EUR")
		#expect(repeated.cacheKey == .number(bankCode: "12030000", account: "202051"))
	}

	@Test("A CAMT IBAN with and without spaces names one account and one remembered answer")
	func repeatedCAMTAccount() throws {
		let camt = "<Document xmlns=\"urn:iso:std:iso:20022:tech:xsd:camt.053.001.08\"><BkToCstmrStmt>"
			+ ["DE02120300000000202051", "DE02 1203 0000 0000 2020 51"].map {
				"<Stmt><Acct><Id><IBAN>\($0)</IBAN></Id></Acct>\(Self.entry)</Stmt>"
			}.joined() + "</BkToCstmrStmt></Document>"
		let parsed = try TransactionFileImporter.parse(Data(camt.utf8), currency: "EUR")
		let decision = try TransactionFileImporter.accountDecision([parsed.account])
		#expect(decision.cacheKey == .iban("DE02120300000000202051"))
		let spaced = try TransactionFileImporter.accountDecision([.iban("de02 1203 0000 0000 2020 51")])
		#expect(spaced.cacheKey == .iban("DE02120300000000202051"))
		#expect(parsed.transactions.count == 2)
	}

	@Test("An open account outranks a closed match, below the file currency")
	func openAccount() throws {
		let old = Account(position: 0, name: "Old closed", kind: .giro, source: .offline, iban: "DE02120300000000202051", isClosed: true)
		let new = Account(position: 1, name: "New open", kind: .giro, source: .offline, iban: "DE02120300000000202051")
		let savings = Account(position: 2, name: "Savings", kind: .savings, source: .offline)
		let names: [FileAccount?] = [.iban("DE02120300000000202051")]
		let decision = try TransactionFileImporter.accountDecision(names, selected: savings, accounts: [old, new, savings], currency: "EUR")
		#expect(decision.destination == .other(new))
		let selectedClosed = try TransactionFileImporter.accountDecision(names, selected: old, accounts: [old, new, savings], currency: "EUR")
		#expect(selectedClosed.destination == .other(new))
		var dollar = new
		dollar.currency = "USD"
		let euro = try TransactionFileImporter.accountDecision(names, selected: savings, accounts: [old, dollar, savings], currency: "EUR")
		#expect(euro.destination == .other(old))
		var openPortfolio = new
		openPortfolio.kind = .portfolio
		let open = try TransactionFileImporter.accountDecision(names, selected: savings, accounts: [old, openPortfolio, savings], currency: "EUR")
		#expect(open.destination == .other(openPortfolio))
	}

	@Test("Field 25 preserves hyphenated account numbers for every MT940 line ending", arguments: ["\n", "\r\n", "\r"])
	func field25LineEndings(ending: String) throws {
		let text = String(decoding: Self.mt940Data([":25:12030000/1234-567890"]), as: UTF8.self).replacingOccurrences(of: "\n", with: ending)
		let parsed = try TransactionFileImporter.parse(Data(text.utf8), currency: "EUR")
		#expect(parsed.account == .number(bankCode: "12030000", account: "1234-567890"))
		let account = Account(position: 0, name: "Hyphen", kind: .giro, source: .offline, accountNumber: "1234-567890", bankCode: "12030000")
		let decision = try TransactionFileImporter.accountDecision([parsed.account], selected: account, accounts: [account], currency: "EUR")
		#expect(decision.destination == .selected)
		#expect(parsed.transactions.map(\.amountMinor) == [-8900])
	}

	@Test("Zero is not an empty account number, and the account's own number is folded")
	func foldedAccountNumber() throws {
		let empty = Account(position: 0, name: "Empty", kind: .giro, source: .offline, accountNumber: "")
		let zero = try TransactionFileImporter.accountDecision([.number(bankCode: nil, account: "000")], selected: empty, accounts: [empty], currency: "EUR")
		#expect(zero.destination == .unknown)
		#expect(zero.cacheKey == .number(bankCode: nil, account: "0"))
		let spaced = Account(position: 1, name: "Spaced", kind: .giro, source: .offline, accountNumber: "4111 1111")
		let folded = try TransactionFileImporter.accountDecision([.number(bankCode: nil, account: "41111111")], selected: spaced, accounts: [empty, spaced], currency: "EUR")
		#expect(folded.destination == .selected)
		let actualZero = Account(position: 2, name: "Zero", kind: .giro, source: .offline, accountNumber: "0")
		let actual = try TransactionFileImporter.accountDecision([.number(bankCode: nil, account: "000")], selected: actualZero, accounts: [actualZero], currency: "EUR")
		#expect(actual.destination == .selected)
		let bank = Account(position: 3, name: "Folded bank", kind: .giro, source: .offline, accountNumber: "202051", bankCode: "12030000")
		let padded = try TransactionFileImporter.accountDecision([.number(bankCode: "12 03 00 00", account: "000 0202051")], selected: bank, accounts: [bank], currency: "EUR")
		#expect(padded.destination == .selected)
		#expect(padded.cacheKey == .number(bankCode: "12030000", account: "202051"))
	}

}
