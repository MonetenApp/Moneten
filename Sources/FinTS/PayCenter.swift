import Domain
import Foundation

/// The rules of PayCenter GmbH and its consumer brand VIMpay, both on the Bankleitzahl 70017000 (issue #238). Each bank
/// group keeps its rules in a file of its own. No public page of the bank names its FinTS login, so it gets no login hint.
enum PayCenter {
	/// The name that the app shows for the Bankleitzahl: VIMpay is the consumer brand of PayCenter.
	static let brandNames = ["70017000": "PayCenter / VIMpay"]

	/// The method whose TAN has exactly `tanLength` characters.
	static let tanMethod = "911"
	static let tanLength = 6

	/// The FinTS server of PayCenter is the host `fints.paycenter.de`, in lower case and without one trailing dot, as the
	/// hosts of the other bank groups count.
	static func isPayCenter(_ server: URL?) -> Bool {
		guard var host = server?.host()?.lowercased() else { return false }
		if host.hasSuffix(".") { host.removeLast() }
		return host == "fints.paycenter.de"
	}

	/// The field of a typed TAN of the method 911 on the server of PayCenter: exactly 6 characters, so that a TAN with a
	/// missing character never counts as a wrong attempt at the bank. Nil for any other method or server, which keeps its field.
	static func tanField(method: String?, server: URL?) -> TANField? {
		guard method == tanMethod, isPayCenter(server) else { return nil }
		return TANField(length: tanLength...tanLength)
	}
}
