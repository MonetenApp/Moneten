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

	/// The login name as `server` expects it: a VR-Kennung, "VRK" and digits, in capitals and without spaces
	/// on the servers of Atruvia and apoBank. Any other login name stays as it is.
	public static func loginName(_ name: String, server: URL?) -> String {
		guard isAtruvia(server) || isApoBank(server) else { return name }
		let joined = name.filter { !$0.isWhitespace }
		let digits = joined.dropFirst(3)
		guard joined.uppercased().hasPrefix("VRK"), !digits.isEmpty, digits.allSatisfy({ $0.isASCII && $0.isNumber }) else { return name }
		return joined.uppercased()
	}
}
