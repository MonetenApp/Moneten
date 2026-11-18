import Domain
import Foundation

/// The rules of Oberbank (issue #236). Oberbank has the Bankleitzahl 70120700 on the FinTS server of Bank-Verlag, which
/// many banks share, so the rules follow the Bankleitzahl and never the host. Each bank group keeps its rules in a file of
/// its own.
enum Oberbank {
	static let bankCode = "70120700"

	// The guide "HBCI und xTAN" of Oberbank says to ask the customer adviser for xTAN, which a change of the Electronic
	// Banking contract switches on, and to set up the access in the software after the written confirmation. Its HBCI
	// page names no login name, so the field keeps "User ID".
	static let hint = LoginHint(bankName: nil, bankCodes: [bankCode], label: String(localized: "User ID"),
		help: String(localized: "If the login fails, ask your customer adviser at Oberbank whether the HBCI access with xTAN is switched on for you."),
		source: URL(string: "https://www.oberbank.de/documents/360322/464931/ipkde_infoxtan_NEU.pdf")!, sourceTitle: String(localized: "Guide of Oberbank"),
		note: String(localized: "Before the first login, ask your customer adviser at Oberbank for the HBCI access with xTAN by SMS. Oberbank stores your mobile number with a change of the Electronic Banking contract and confirms the access in writing. Log in after that."))

	// The page of the Security App (https://www.oberbank.de/security-app) names it a method of the internet banking, and
	// the HBCI page (https://www.oberbank.de/electronic-banking) names xTAN by SMS and the security file for finance
	// software. The ID is no code of a bank, so it never names a method of the server.
	static let securityApp = TANMethod(id: "oberbank-security-app", name: "Oberbank Security App",
		unavailable: String(localized: "Oberbank offers the Security App only for its internet banking, not for finance software."))

	/// The TAN methods to choose from at Oberbank: those of the FinTS server, and the Security App that cannot be chosen,
	/// when none of them is an app. A method is an app when the bank parameters mark it as an approval in an app or its
	/// name has the word "App". Any other bank keeps the methods of its server.
	static func methods(_ offered: [TANMethod], bankCode: String?) -> [TANMethod] {
		guard bankCode == Self.bankCode, !offered.contains(where: isApp) else { return offered }
		return offered + [securityApp]
	}

	private static func isApp(_ method: TANMethod) -> Bool {
		method.delivery == .pushNotification || TextFolding.fold(method.name).split(whereSeparator: { !$0.isLetter }).contains("app")
	}
}

extension BankDirectory.Entry {
	/// The hint of Oberbank, by its Bankleitzahl alone.
	var oberbankHint: LoginHint? {
		code == Oberbank.bankCode ? Oberbank.hint : nil
	}
}
