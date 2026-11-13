import Domain
import Foundation

/// What a bank calls the login name of FinTS, for the login step of "Add Account". Each hint comes
/// from a public page of the bank, and a bank without a confirmed page gets no hint. All of these
/// banks ask to leave the customer ID empty, so the login step has no field for it.
public struct LoginHint: Sendable, Equatable {
	/// The name that customers know the bank by, which the bank directory may not use, such as "DKB"
	/// for "Deutsche Kreditbank Berlin". The search of the first step finds the bank by it.
	let bankName: String?
	/// The label of the login name field.
	public let label: String
	/// One sentence under the field, and in the message of a rejected PIN at the first login.
	public let help: String
	/// The public page of the bank that says so, which the login step links to.
	public let source: URL

	static let consorsbank = LoginHint(bankName: "Consorsbank", label: "Account number + 001",
		help: "Consorsbank expects the account number followed by the three-digit Berechtigtennummer, usually 001, for example 900123456001.",
		source: URL(string: "https://www.consorsbank.de/web/Wissen/FAQ/kontokarten/HBCI-Schnittstelle-Konto-und-Zahlungsverkehrsprogramm")!)
	static let dkb = LoginHint(bankName: "DKB", label: "Login name",
		help: "DKB expects the login name of its online banking.",
		source: URL(string: "https://www.dkb.de/geschaeftskunden/electronic-banking")!)
	static let comdirect = LoginHint(bankName: "comdirect", label: "Access number",
		help: "comdirect expects the Zugangsnummer that you also use for its online banking.",
		source: URL(string: "https://www.comdirect.de/cms/sicherheit-software-banking-fints.html")!)
	static let ing = LoginHint(bankName: "ING", label: "User name",
		help: "ING expects the user name that you chose for its online banking.",
		source: URL(string: "https://www.ing.de/hilfe/log-in/fints/")!)
	static let savingsBank = LoginHint(bankName: nil, label: "Login name or Legitimations-ID",
		help: "A Sparkasse expects the Anmeldename or the Legitimations-ID that it gave you for online banking.",
		source: URL(string: "https://www.ospa.de/content/dam/myif/ostseespk-rostock/work/dokumente/pdf/allgemein/anleitung-zur-konfiguration-der-finanz-software.pdf")!)

	/// The banks by the host of their FinTS address, which stays the same for all their Bankleitzahlen.
	static let byHost = [
		"brokerage-hbci.consorsbank.de": consorsbank,
		"fints.dkb.de": dkb,
		"fints.comdirect.de": comdirect,
		"fints.ing.de": ing,
	]
}

extension FinTSBank {
	/// The hint for the login name of this bank. Each savings bank has a host of its own on the FinTS
	/// servers of the savings banks, so a savings bank is a bank with "Sparkasse" in its name on these
	/// servers. A Bausparkasse is not one, nor is a bank of another group with "Sparkasse" in its name.
	public var loginHint: LoginHint? {
		guard let host = url?.host()?.lowercased() else { return nil }
		if let hint = LoginHint.byHost[host] { return hint }
		let name = TextFolding.fold(name)
		let savingsServer = host.contains(".s-fints-pt-") || host.hasSuffix(".s-hbci.de")
		return savingsServer && name.contains("sparkasse") && !name.contains("bausparkasse") ? .savingsBank : nil
	}
}
