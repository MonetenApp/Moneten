import Domain
import Foundation

/// The rules of the assistant "Add Account" for Consorsbank and DAB BNP Paribas, two brands of one bank on the FinTS
/// server `brokerage-hbci.consorsbank.de` (#227). The server rules are in `Sources/Domain/Sync/ConsorsbankServer.swift`,
/// and the login hint of Consorsbank is `LoginHint.consorsbank`.
enum Consorsbank {
	/// The name that the app shows for 70120400, which the directory names after the bank and not after its brands.
	static let brandNames = ["70120400": "Consorsbank / DAB BNP Paribas"]

	/// The short name that customers know 70120400 by, which the search ranks first.
	static let knownNames = ["70120400": "DAB"]

	/// The bank name of every access on the server, whichever of the two Bankleitzahlen it has.
	static let accessName = "Consorsbank"
}

extension BankDirectory.Entry {
	/// The bank name of a new access to this bank: "Consorsbank" on the server of Consorsbank, and the name of the
	/// directory for every other bank.
	public var accessBankName: String {
		FinTSServer.isConsorsbank(bank.url) ? Consorsbank.accessName : bank.name
	}
}
