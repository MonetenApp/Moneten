import Domain
import Foundation

/// What a bank calls the login name of FinTS, for the login step of "Add Account". Each hint comes
/// from a public page of the bank, and a bank without a confirmed page gets no hint. All of these
/// banks ask to leave the customer ID empty, so the login step has no field for it.
public struct LoginHint: Sendable, Equatable {
	/// The name that customers know the bank by, which the bank directory may not use, such as "DKB"
	/// for "Deutsche Kreditbank Berlin". The search of the first step finds the bank by it.
	let bankName: String?
	/// The Bankleitzahlen that a page of the bank names as its own. A bank on the same FinTS server,
	/// such as DAB BNP Paribas on the server of Consorsbank, is a bank of its own.
	let bankCodes: [String]
	/// The label of the login name field.
	public let label: String
	/// One sentence under the field, and in the message of a rejected PIN at the first login.
	public let help: String
	/// The public page of the bank that says so, which the login step links to.
	public let source: URL
	/// The title of the link. The page for the savings banks is the guide of one of them.
	public let sourceTitle: String

	// Bankleitzahl: https://www.consorsbank.de/web/Wissen/FAQ/kontokarten/Bankleitzahl-Consorsbank
	static let consorsbank = LoginHint(bankName: "Consorsbank", bankCodes: ["76030080"], label: "Account number + 001",
		help: "Consorsbank expects the account number followed by the three-digit Berechtigtennummer, usually 001, for example 900123456001.",
		source: URL(string: "https://www.consorsbank.de/web/Wissen/FAQ/kontokarten/HBCI-Schnittstelle-Konto-und-Zahlungsverkehrsprogramm")!, sourceTitle: "Help page of Consorsbank")
	// Bankleitzahl: the source page.
	static let dkb = LoginHint(bankName: "DKB", bankCodes: ["12030000"], label: "Login name",
		help: "DKB expects the login name of its online banking.",
		source: URL(string: "https://www.dkb.de/geschaeftskunden/electronic-banking")!, sourceTitle: "Help page of DKB")
	// Bankleitzahlen: https://www.comdirect.de/business-partners/faq.html names these four.
	static let comdirect = LoginHint(bankName: "comdirect", bankCodes: ["20041111", "20041133", "20041144", "20041155"], label: "Access number",
		help: "comdirect expects the Zugangsnummer that you also use for its online banking.",
		source: URL(string: "https://www.comdirect.de/cms/sicherheit-software-banking-fints.html")!, sourceTitle: "Help page of comdirect")
	// Bankleitzahl: https://www.ing.de/impressum/
	static let ing = LoginHint(bankName: "ING", bankCodes: ["50010517"], label: "User name",
		help: "ING expects the user name that you chose for its online banking.",
		source: URL(string: "https://www.ing.de/hilfe/log-in/fints/")!, sourceTitle: "Help page of ING")
	static let savingsBank = LoginHint(bankName: nil, bankCodes: [], label: "Login name or Legitimations-ID",
		help: "A Sparkasse expects the Anmeldename or the Legitimations-ID that it gave you for online banking.",
		source: URL(string: "https://www.ospa.de/content/dam/myif/ostseespk-rostock/work/dokumente/pdf/allgemein/anleitung-zur-konfiguration-der-finanz-software.pdf")!, sourceTitle: "Example: Ostseesparkasse Rostock")

	static let byCode = Dictionary(uniqueKeysWithValues: [consorsbank, dkb, comdirect, ing].flatMap { hint in hint.bankCodes.map { ($0, hint) } })
}

extension BankDirectory.Entry {
	/// The hint for the login name of this bank, by its Bankleitzahl. The savings banks are too many
	/// for a list: each has a host of its own on the FinTS servers of the savings banks, so a savings
	/// bank is a bank with "Sparkasse" in its name on these servers. A Bausparkasse is not one, nor is
	/// a bank of another group with "Sparkasse" in its name, nor an old entry of a merged savings bank.
	public var loginHint: LoginHint? {
		if let hint = LoginHint.byCode[code] { return hint }
		guard let host = bank.url?.host()?.lowercased() else { return nil }
		let name = TextFolding.fold(bank.name)
		let savingsServer = host.contains(".s-fints-pt-") || host.hasSuffix(".s-hbci.de")
		return savingsServer && !isObsolete && name.contains("sparkasse") && !name.contains("bausparkasse") ? .savingsBank : nil
	}
}
