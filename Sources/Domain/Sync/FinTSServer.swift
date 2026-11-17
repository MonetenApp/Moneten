import Foundation

/// The FinTS servers whose rules the app knows by their host. The login name rule lives here and not in
/// the FinTS connector, because two accesses are the same login only when their login names agree in the
/// form that the server sees ("Send the login name in the form that the bank expects").
public enum FinTSServer {
	/// The FinTS servers of Atruvia for the cooperative banks, such as `fints2.atruvia.de`, and its other domain.
	public static func isAtruvia(_ server: URL?) -> Bool {
		guard let host = server?.host()?.lowercased() else { return false }
		return host.hasSuffix(".atruvia.de") || host.hasSuffix(".bankenit.de")
	}

	public static func isApoBank(_ server: URL?) -> Bool {
		server?.host()?.lowercased() == "fints.apobank.de"
	}

	/// The FinTS servers of Finanz Informatik for the savings banks: the label of the host before ".de" starts with
	/// "s-fints-pt-", as in "banking-hs6.s-fints-pt-hs.de", or is "s-hbci". The host counts in lower case and without
	/// one trailing dot, as `SavingsBanks.name` of the helper in Tools/FinTSHelper reads it, and a host with an empty
	/// label counts as none.
	public static func isSavingsBank(_ server: URL?) -> Bool {
		guard var host = server?.host()?.lowercased() else { return false }
		if host.hasSuffix(".") { host.removeLast() }
		let labels = host.split(separator: ".", omittingEmptySubsequences: false)
		guard labels.count >= 2, !labels.contains(where: \.isEmpty), labels[labels.count - 1] == "de" else { return false }
		let label = labels[labels.count - 2]
		return label.hasPrefix("s-fints-pt-") || label == "s-hbci"
	}

	/// The login name as `server` expects it: a VR-Kennung, "VRK" and digits, in capitals and without spaces
	/// on the servers of Atruvia and apoBank, and the first 16 digits of a login name of exactly 17 digits on the
	/// servers of the savings banks, which a savings bank may give and whose servers accept only 16 (#240). Any
	/// other login name stays as it is. The servers of Commerzbank follow `commerzbankLoginName` (#229), and the Deutsche
	/// Bank group takes a login name without spaces (#231).
	public static func loginName(_ name: String, server: URL?) -> String {
		if isCommerzbank(server) { return commerzbankLoginName(name) }
		if isDeutscheBankGroup(server) { return name.filter { !$0.isWhitespace } }
		if isSavingsBank(server) {
			return name.count == 17 && name.allSatisfy({ $0.isASCII && $0.isNumber }) ? String(name.prefix(16)) : name
		}
		guard isAtruvia(server) || isApoBank(server) else { return name }
		let joined = name.filter { !$0.isWhitespace }
		let digits = joined.dropFirst(3)
		guard joined.uppercased().hasPrefix("VRK"), !digits.isEmpty, digits.allSatisfy({ $0.isASCII && $0.isNumber }) else { return name }
		return joined.uppercased()
	}
}
