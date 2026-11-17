import Domain
import Foundation

/// The rules of Commerzbank and comdirect (issue #229). Both belong to the group by the host of their FinTS address
/// (`FinTSServer.isCommerzbank`, `FinTSServer.isComdirect`), which also holds the login name rule of Commerzbank.
/// Each bank group keeps its rules in a file of its own. The helper decides the rules of the dialog with the bank by
/// the same hosts, in `Tools/FinTSHelper/CommerzbankGroup.java`.
enum CommerzbankGroup {
	// The page names the access "FinTS/HBCI with photoTAN" and where to request it.
	static let commerzbankHint = LoginHint(bankName: nil, bankCodes: [], label: String(localized: "Participant number"),
		help: String(localized: "Commerzbank expects the 10-digit participant number. If the login fails, check that Commerzbank switched on “FinTS/HBCI with photoTAN” for you."),
		source: URL(string: "https://www.commerzbank.de/hbci")!, sourceTitle: String(localized: "Help page of Commerzbank"),
		note: String(localized: "Request the access at www.commerzbank.de/hbci before the first login. Commerzbank must switch on the method “FinTS/HBCI with photoTAN” for you, also when you already use photoTAN on the website."))

	/// The hint of comdirect, with what to set up before the first login. It covers the Bankleitzahlen that the page of
	/// comdirect names, as before, so a search for "comdirect" still offers 20041111 first.
	static var comdirectHint: LoginHint {
		var hint = LoginHint.comdirect
		hint.note = String(localized: "Before the first login, set up a TAN method such as photoTAN on the website of comdirect. comdirect needs about two business days before its FinTS server accepts it. If the login fails until then, try again later with “Edit Login Data...”.")
		return hint
	}

	/// The longest TAN that the field of a photoTAN of Commerzbank takes, and the length when the bank announces none.
	static let longestTAN = 15

	/// The field of a typed TAN of the method `method`, whose bank parameters announce `maxLength` characters. The photoTAN
	/// of Commerzbank (a code with "900") has at least 7 characters and at most the announced length, counted between 7
	/// and 15. The photoTAN of comdirect (a code with "902") has 6 or 7. Every other method keeps a field without a length.
	static func tanField(method: String?, maxLength: Int?, server: URL?) -> TANField {
		guard let method else { return TANField() }
		if FinTSServer.isCommerzbank(server), method.contains("900") {
			return TANField(length: 7...min(max(maxLength ?? longestTAN, 7), longestTAN))
		}
		if FinTSServer.isComdirect(server), method.contains("902") {
			return TANField(length: 6...7)
		}
		return TANField()
	}
}

extension BankDirectory.Entry {
	/// The hint of Commerzbank, by the host of the FinTS address, or of comdirect.
	var commerzbankGroupHint: LoginHint? {
		if FinTSServer.isCommerzbank(bank.url) { return CommerzbankGroup.commerzbankHint }
		if FinTSServer.isComdirect(bank.url), LoginHint.comdirect.bankCodes.contains(code) { return CommerzbankGroup.comdirectHint }
		return nil
	}
}
