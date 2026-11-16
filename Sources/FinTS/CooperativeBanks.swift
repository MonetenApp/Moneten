import Domain
import Foundation

/// The rules of the cooperative banks on the FinTS servers of Atruvia, and of apoBank, which shares
/// some of them. A bank belongs to the group by the host of its FinTS address (`FinTSServer`), because
/// the rules are rules of these servers, and a few banks of the group by their Bankleitzahl.
enum CooperativeBanks {
	// The page of the Volksbanken Raiffeisenbanken names the VR-NetKey and the alias that replaces it.
	static let hint = LoginHint(bankName: nil, bankCodes: [], label: String(localized: "VR-NetKey or alias"),
		help: String(localized: "A Volksbank or Raiffeisenbank expects the VR-NetKey or the alias of its online banking."),
		source: URL(string: "https://www.vr.de/privatkunden/produkte/konten-karten/online-banking/faq-online-banking.html")!,
		sourceTitle: String(localized: "Help page of the Volksbanken Raiffeisenbanken"))

	/// The name of a bank that its customers know, which the bank directory does not use, by its
	/// Bankleitzahl. Skatbank and Ordensbank are brands of the bank that holds the Bankleitzahl.
	static let knownNames = ["83065408": "Skatbank", "51090000": "Ordensbank", "30060601": "apoBank"]

	/// The name that the app shows for a brand: the name of the bank and the brand.
	static let brandNames = ["83065408": "VR-Bank Altenburger Land / Skatbank", "51090000": "Wiesbadener Volksbank / Ordensbank"]

	/// The longest login name that the FinTS servers of Atruvia accept, the length of the user ID in FinTS.
	static let maxLoginLength = 30

	/// The PIN length that these servers accepted before they raised the minimum.
	static let refusedPINLength = 6

	/// The BIC that an account of the bank gets. EthikBank still sends its old BIC for some accounts.
	static func bic(_ bic: String?, bankCode: String?) -> String? {
		bankCode == "83094495" && bic == "GENODEF1ESN" ? "GENODEF1ETK" : bic
	}

	/// The PIN rules of the bank parameters, with the six characters that the servers of Atruvia refuse
	/// once the minimum is higher.
	static func pinRules(minLength: Int?, maxLength: Int?, server: URL?) -> PINRules {
		PINRules(minLength: minLength, maxLength: maxLength, refusedLength: FinTSServer.isAtruvia(server) ? refusedPINLength : nil)
	}
}

extension BankDirectory.Entry {
	/// The login name to send and store for what the user typed: without the spaces around it, and a
	/// VR-Kennung of a cooperative bank in capitals.
	public func loginName(_ typed: String) -> String {
		FinTSServer.loginName(typed.trimmingCharacters(in: .whitespaces), server: bank.url)
	}

	/// What makes the login name unusable at this bank before any connection, or nil.
	public func loginNameProblem(_ name: String) -> String? {
		guard FinTSServer.isAtruvia(bank.url), name.count > CooperativeBanks.maxLoginLength else { return nil }
		return String(localized: "The FinTS server of the bank accepts no alias longer than \(CooperativeBanks.maxLoginLength) characters. Change the alias in the online banking of the bank first.")
	}

	/// The hint of a cooperative bank on the servers of Atruvia. A Sparda-Bank on the same servers calls
	/// its login name the Sparda-NetKey, and the Südtiroler Sparkasse (70012600) is no cooperative bank, so
	/// they get none.
	var cooperativeHint: LoginHint? {
		FinTSServer.isAtruvia(bank.url) && !TextFolding.fold(bank.name).contains("sparda") && code != "70012600" ? CooperativeBanks.hint : nil
	}
}

extension TANMediumName {
	/// apoBank asks for the TAN medium of apoTAN and lists none. It needs the name only when the bank
	/// reports an error without it.
	public static let apoTANDevice = TANMediumName(label: String(localized: "apoTAN device name"),
		help: String(localized: "Leave the field empty, unless the bank reports an error in the next step. Then enter the name exactly as the website of apoBank shows it under Benutzereinstellungen > apoTAN verwalten. When a later refresh reports that error, enter the name with “Edit Login Data...”."))
}
