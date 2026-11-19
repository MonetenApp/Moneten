import Domain
import Foundation

/// The rules of Baader Bank and the brokers whose securities accounts it keeps (#226). The brokers share the FinTS
/// server of Baader Bank, so the app knows them by its host and not by a Bankleitzahl. Each bank group keeps its rules
/// in a file of its own.
enum BaaderBank {
	/// The FinTS server of Baader Bank: the host `fints.baaderbank.de`, in lower case and without one trailing dot, as
	/// the hosts of the other bank groups count.
	static func isBaaderBank(_ server: URL?) -> Bool {
		FinTSServer.host(server) == "fints.baaderbank.de"
	}

	// The customer portal of Baader Bank, whose login also leads to the FinTS access. The help line also goes into the
	// message of a rejected first login, because the answer of the bank to an unknown Stammnummer is not known yet.
	static let hint = LoginHint(bankName: nil, bankCodes: [], label: String(localized: "Stammnummer"),
		help: String(localized: "Baader Bank expects the Stammnummer that your broker gives you. If the bank rejects the login, check that the Stammnummer is valid and that Baader Bank activated the FinTS access."),
		source: URL(string: "https://konto.baaderbank.de/")!, sourceTitle: String(localized: "Customer portal of Baader Bank"),
		note: String(localized: "Request the FinTS access and its PIN at https://konto.baaderbank.de/ before the first login. Your broker gives you the Stammnummer."))
}

extension BankDirectory.Entry {
	/// The hint of Baader Bank, by the host of the FinTS address, for Baader Bank and for every broker on its server.
	var baaderBankHint: LoginHint? {
		BaaderBank.isBaaderBank(bank.url) ? BaaderBank.hint : nil
	}
}
