import Domain
import Foundation

/// The rules of OLB (Oldenburgische Landesbank) and Bankhaus Neelmeyer (issue #237). Each bank group keeps its rules in
/// a file of its own. A bank belongs to the group by the host of its FinTS address: OLB by a host that ends in ".olb.de",
/// such as `hbci.olb.de`, which the bank directory gives 28020050, 28030300, and 70035000, and Bankhaus Neelmeyer by the
/// host `hbci.neelmeyer.de`. A host counts in lower case and without one trailing dot, as the hosts of the other groups do.
enum OLBGroup {
	// The FAQ of OLB on its online banking: "Bei Nutzung eines TAN-Verfahrens sind etwa Banking-Zugangsnummer und PIN
	// ausreichend", and finance software may use it. No public page of Bankhaus Neelmeyer names its FinTS login, so it
	// gets no hint.
	static let olbHint = LoginHint(bankName: "OLB", bankCodes: [], label: String(localized: "Access number"),
		help: String(localized: "OLB expects the Banking-Zugangsnummer and the PIN of its online banking."),
		source: URL(string: "https://www.olb.de/hilfe/ihre-fragen/faq-onlinebanking")!, sourceTitle: String(localized: "Help page of OLB"))

	/// The labels of the host, or nil for a host with an empty label.
	private static func labels(_ server: URL?) -> [Substring]? {
		guard var host = server?.host()?.lowercased() else { return nil }
		if host.hasSuffix(".") { host.removeLast() }
		let labels = host.split(separator: ".", omittingEmptySubsequences: false)
		return labels.contains(where: \.isEmpty) ? nil : labels
	}

	/// A FinTS server of OLB: a host that ends in ".olb.de".
	static func isOLB(_ server: URL?) -> Bool {
		guard let labels = labels(server) else { return false }
		return labels.count >= 3 && labels.suffix(2) == ["olb", "de"]
	}

	/// A FinTS server of OLB or the server of Bankhaus Neelmeyer.
	static func isGroup(_ server: URL?) -> Bool {
		isOLB(server) || labels(server) == ["hbci", "neelmeyer", "de"]
	}

	/// The note of a TAN dialog at OLB whose methods, by the names in `methods`, do not contain OLB-Sign: OLB offers
	/// OLB-Sign only on its website, and appTAN works with finance software. The text fits the step of `purpose`. A
	/// dialog that names no method, as a typed TAN of a method that the helper does not name, gets no note, because its
	/// method may be OLB-Sign. Nil for any other bank.
	static func tanNote(methods: [String], purpose: SecondFactorRequest.Purpose, server: URL?) -> String? {
		guard isOLB(server), !methods.isEmpty, !methods.contains(where: { $0.lowercased().contains("olb-sign") }) else { return nil }
		return switch purpose {
		case .login: String(localized: "OLB offers OLB-Sign only on its website. Log in with appTAN, which works with finance software.")
		case .download: String(localized: "OLB offers OLB-Sign only on its website. Approve this request with appTAN, which works with finance software.")
		case .order: String(localized: "OLB offers OLB-Sign only on its website. Approve this order with appTAN, which works with finance software.")
		}
	}

	/// The purchase price of a position of the group, which the bank sends as the purchase value of the whole position:
	/// divided by the quantity of units, or by the nominal amount and times 100, which gives a percentage. A purchase price
	/// in percent stays as it is, a position with the quantity 0 has none, and the price of any other bank stays as it is.
	static func purchasePrice(_ price: Quote?, quantity: Decimal, isNominal: Bool, server: URL?) -> Quote? {
		guard isGroup(server), let price, price.currency != nil else { return price }
		guard quantity != 0 else { return nil }
		if isNominal { return Quote(amount: price.amount * 100 / quantity, currency: nil, day: price.day) }
		return Quote(amount: price.amount / quantity, currency: price.currency, day: price.day)
	}
}

extension BankDirectory.Entry {
	/// The hint of OLB, by the host of the FinTS address.
	var olbGroupHint: LoginHint? {
		OLBGroup.isOLB(bank.url) ? OLBGroup.olbHint : nil
	}
}
