import Domain
import Foundation

/// The rules of the assistant "Add Account" for the savings banks on the FinTS servers of Finanz Informatik and for
/// 1822direkt. Each bank group keeps its rules in a file of its own. The helper decides the rules of the dialog with
/// the bank by the same host test, in `Tools/FinTSHelper/SavingsBanks.java`.
extension BankDirectory.Entry {
	/// Whether the FinTS address of the bank is on the servers of the savings banks (`FinTSServer.isSavingsBank`).
	/// The login name rule of these servers is in `FinTSServer.loginName`, with the rules of the other servers.
	public var isOnSavingsBankServer: Bool {
		FinTSServer.isSavingsBank(bank.url)
	}
}

extension BankLookup {
	/// The Bankleitzahl of Frankfurter Sparkasse, which 1822direkt also gives its customers in their IBANs.
	static let frankfurterSparkasse = "50050201"

	/// A note of the first step about the bank that the entry found. 1822direkt gives its customers IBANs with the
	/// Bankleitzahl of Frankfurter Sparkasse, whose entry leads to the FinTS server of Frankfurter Sparkasse. Its own
	/// server has the Bankleitzahl 50050222. A Bankleitzahl that the user enters or chooses means that bank, so only
	/// an IBAN gets the note.
	public var note: String? {
		guard bank?.code == Self.frankfurterSparkasse, entry.first(where: { !$0.isWhitespace })?.isLetter == true else { return nil }
		return String(localized: "A customer of 1822direkt enters the Bankleitzahl 50050222 here in place of the IBAN.")
	}
}
