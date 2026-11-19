import Foundation

/// The FinTS server of Consorsbank, which DAB BNP Paribas shares (#227). Each bank group keeps its rules in a file of its
/// own. The rules of the assistant are in `Sources/FinTS/Consorsbank.swift`, and the helper decides the HKTAN rules of
/// the server by the same host, in `tanRules` of `Tools/FinTSHelper/FinTSHelper.java`.
extension FinTSServer {
	/// The Bankleitzahl that Consorsbank names as its own on its help page of the login.
	static let consorsbankCode = "76030080"

	/// The FinTS server of Consorsbank: the host `brokerage-hbci.consorsbank.de`, in lower case and without one trailing
	/// dot. Another host of the domain is another server, as in the helper.
	public static func isConsorsbank(_ server: URL?) -> Bool {
		guard var host = server?.host()?.lowercased() else { return false }
		if host.hasSuffix(".") { host.removeLast() }
		return host == "brokerage-hbci.consorsbank.de"
	}

	/// A login name of Consorsbank as the app shows it: 11 to 13 digits as the account number, a space, and the
	/// Berechtigtennummer of the last three digits. Only the page of Consorsbank for 76030080 names this form, so another
	/// Bankleitzahl on the server gets nil, as does any other login name. The app sends and stores it without the space,
	/// because `loginName(_:server:)` removes every space on this server.
	static func consorsbankShownLoginName(_ name: String, bankCode: String, server: URL?) -> String? {
		guard bankCode == consorsbankCode, isConsorsbank(server), (11...13).contains(name.count),
			name.allSatisfy({ $0.isASCII && $0.isNumber }) else { return nil }
		return name.dropLast(3) + " " + name.suffix(3)
	}
}
