import Foundation

/// The FinTS servers of Commerzbank and comdirect (issue #229). Each bank group keeps its rules in a file of its
/// own. The helper decides its rules by the same hosts, in Tools/FinTSHelper/CommerzbankGroup.java.
extension FinTSServer {
	/// The FinTS server of Commerzbank: the host `fints.commerzbank.de` or `hbci.commerzbank.de`.
	public static func isCommerzbank(_ server: URL?) -> Bool {
		["fints.commerzbank.de", "hbci.commerzbank.de"].contains(host(server))
	}

	/// The FinTS server of comdirect: the host `fints.comdirect.de`.
	public static func isComdirect(_ server: URL?) -> Bool {
		host(server) == "fints.comdirect.de"
	}

	/// The server of Commerzbank expects the 10-digit participant number, and customers know it as 8 digits, so a login
	/// name of exactly 8 ASCII digits gets "00" in front. Any other login name, such as an alias, stays as it is.
	static func commerzbankLoginName(_ name: String) -> String {
		name.count == 8 && name.allSatisfy({ $0.isASCII && $0.isNumber }) ? "00" + name : name
	}
}
