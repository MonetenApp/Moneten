import Foundation

/// The rules of the assistant "Add Account" for the savings banks on the FinTS servers of Finanz Informatik and for
/// 1822direkt. Each bank group keeps its rules in a file of its own. The helper decides the rules of the dialog with
/// the bank by the same host test, in `Tools/FinTSHelper/SavingsBanks.java`.
extension BankDirectory.Entry {
	/// Whether the FinTS address of the bank is on the servers of the savings banks: the label of its host before
	/// ".de" starts with "s-fints-pt-", as in "banking-hs6.s-fints-pt-hs.de", or is "s-hbci". The host counts in lower
	/// case and without one trailing dot, as `SavingsBanks.name` of the helper reads it.
	public var isOnSavingsBankServer: Bool {
		guard var host = bank.url?.host()?.lowercased() else { return false }
		if host.hasSuffix(".") { host.removeLast() }
		let labels = host.split(separator: ".", omittingEmptySubsequences: false)
		guard labels.count >= 2, !labels.contains(where: \.isEmpty), labels[labels.count - 1] == "de" else { return false }
		let label = labels[labels.count - 2]
		return label.hasPrefix("s-fints-pt-") || label == "s-hbci"
	}

	/// The login name that the app sends to the bank and stores in the access. A savings bank may give a login name
	/// of 17 digits, and its FinTS server accepts only the first 16, so such a login name loses its last digit. Any
	/// other login name stays as typed, without the spaces at both ends.
	public func loginName(_ typed: String) -> String {
		let name = typed.trimmingCharacters(in: .whitespaces)
		guard isOnSavingsBankServer, name.count == 17, name.allSatisfy({ $0.isASCII && $0.isNumber }) else { return name }
		return String(name.prefix(16))
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
