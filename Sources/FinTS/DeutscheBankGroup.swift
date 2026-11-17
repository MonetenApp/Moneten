import Domain
import Foundation

/// The rules of the assistant "Add Account" for the Deutsche Bank group: Deutsche Bank, Postbank with its business brand
/// FYRST, and norisbank (#231). A bank belongs to the group by the host of its FinTS address (`FinTSServer`). The login
/// name rule of these servers is in `FinTSServer.loginName`, with the rules of the other servers.
enum DeutscheBankGroup {
	// The page of Deutsche Bank on its login field. norisbank names its FinTS login on no public page, so it gets no hint.
	static let deutscheBankHint = LoginHint(bankName: nil, bankCodes: [], label: String(localized: "Deutsche Bank ID"),
		help: String(localized: "Deutsche Bank expects the Deutsche Bank ID. Unless you chose an ID of your own, it is your branch and account number without the subaccount number."),
		source: URL(string: "https://www.deutsche-bank.de/pk/service-und-kontakt/services/fragen-antworten/online-banking/was-gebe-ich-in-das-login-feld-deutsche-bank-id-ein-.html")!,
		sourceTitle: String(localized: "Help page of Deutsche Bank"))
	// The guide of Postbank for the setup of FinTS with the Postbank ID. A word joiner keeps the form of a business profile on one line.
	static let postbankHint = LoginHint(bankName: nil, bankCodes: [], label: String(localized: "Postbank ID"),
		help: String(localized: "Postbank expects the Postbank ID. For a business profile, enter the Postbank ID followed by # and the profile name, in the form Postbank-\u{2060}ID#Profil."),
		source: URL(string: "https://www.postbank.de/dam/postbank/pdf/geschaeftskunden/Postbank-ID-und-FinTS-Informationen-FinanzManager-20191015.pdf")!,
		sourceTitle: String(localized: "Guide of Postbank"))

	/// The name that the app shows for a brand on the Bankleitzahl of the bank: FYRST is the business brand of Postbank.
	static let brandNames = ["10010010": "Postbank / FYRST"]
}

extension BankDirectory.Entry {
	/// The hint of Deutsche Bank and of Postbank, by the host of the FinTS address.
	var deutscheBankGroupHint: LoginHint? {
		if FinTSServer.isDeutscheBank(bank.url) { return DeutscheBankGroup.deutscheBankHint }
		if FinTSServer.isPostbank(bank.url) { return DeutscheBankGroup.postbankHint }
		return nil
	}
}
