import Foundation

/// The FinTS servers of the Deutsche Bank group: Deutsche Bank, Postbank with its business brand FYRST, and norisbank
/// (#231). Each bank group keeps its rules in a file of its own. The rules of the assistant are in
/// `Sources/FinTS/DeutscheBankGroup.swift`, and those of the dialog with the bank in `Tools/FinTSHelper/DeutscheBankGroup.java`.
extension FinTSServer {
	public static func isDeutscheBank(_ server: URL?) -> Bool {
		host(of: server, endsIn: "deutsche-bank.de")
	}

	public static func isPostbank(_ server: URL?) -> Bool {
		host(of: server, endsIn: "postbank.de")
	}

	public static func isNorisbank(_ server: URL?) -> Bool {
		host(of: server, endsIn: "norisbank.de")
	}

	/// The servers whose login name has no spaces and whose typed TAN goes in capitals.
	public static func isDeutscheBankGroup(_ server: URL?) -> Bool {
		isDeutscheBank(server) || isPostbank(server) || isNorisbank(server)
	}

	/// Whether the host of `server` is a subdomain of `domain`. The host counts in lower case and without one trailing
	/// dot, and a host with an empty label counts as none, as `SavingsBanks.name` of the helper reads it.
	private static func host(of server: URL?, endsIn domain: String) -> Bool {
		guard var host = server?.host()?.lowercased() else { return false }
		if host.hasSuffix(".") { host.removeLast() }
		guard !host.hasPrefix("."), !host.hasSuffix("."), !host.contains("..") else { return false }
		return host.hasSuffix("." + domain)
	}

	/// The login name as the app shows it: a login name of exactly 10 digits at Deutsche Bank and norisbank as the branch
	/// number of 3 digits and the account number of 7, as the bank card prints it. The app sends and stores it without the
	/// space, because `loginName(_:server:)` removes every space for these servers.
	public static func shownLoginName(_ name: String, server: URL?) -> String {
		guard isDeutscheBank(server) || isNorisbank(server), name.count == 10, name.allSatisfy({ $0.isASCII && $0.isNumber }) else { return name }
		return name.prefix(3) + " " + name.dropFirst(3)
	}
}

extension Access {
	/// The login name for the PIN dialog, the TAN dialog, the progress of a challenge, the account settings, and the
	/// field of "Edit Login Data...".
	public var shownLoginName: String {
		guard case let .fints(code, url) = source else { return loginName }
		return FinTSServer.consorsbankShownLoginName(loginName, bankCode: code, server: url) ?? FinTSServer.shownLoginName(loginName, server: url)
	}
}
