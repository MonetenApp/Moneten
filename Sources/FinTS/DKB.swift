import Domain
import Foundation

/// The rules of DKB (Deutsche Kreditbank). Each bank group keeps its rules in a file of its own, so that the rules of
/// another group change no line of it. The login hint of DKB is `LoginHint.dkb`.
enum DKB {
	static let bankCode = "12030000"

	/// A DKB access has the Bankleitzahl 12030000 or a FinTS address on a host that ends in ".dkb.de". The host
	/// counts in lower case and without one trailing dot, as the hosts of the other bank groups do.
	static func isDKB(bankCode: String?, server: URL?) -> Bool {
		if bankCode == Self.bankCode { return true }
		guard var host = server?.host()?.lowercased() else { return false }
		if host.hasSuffix(".") { host.removeLast() }
		return host.hasSuffix(".dkb.de")
	}

	/// A DKB credit card has the 16 digit card number as its account number, which is the account that the
	/// connector asks for, because the card has no IBAN.
	static func isCard(_ remoteID: String) -> Bool {
		remoteID.count == 16 && remoteID.allSatisfy { $0.isASCII && $0.isNumber }
	}

	/// The most days by which DKB may move a booked card payment between two refreshes, in either direction ("Keep a
	/// moved card booking as one transaction").
	static let maxBookingShift = 7

	/// The outcome of an account, with the days by which a DKB card may move its booked payments.
	static func outcome(_ outcome: AccountOutcome, account remoteID: String, bankCode: String?, server: URL?) -> AccountOutcome {
		guard case var .fetched(result) = outcome, result.transactions != nil, isCard(remoteID), isDKB(bankCode: bankCode, server: server) else {
			return outcome
		}
		result.transactions?.maxBookingShift = maxBookingShift
		return .fetched(result)
	}

	/// The failure of a DKB card that allows no job that the app knows, with the card number, so that the user can
	/// quote the error to the DKB support. Nil for any other failure or account, which keeps the failure of its error.
	static func failure(of error: HelperError, account remoteID: String, bankCode: String?, server: URL?) -> SyncFailure? {
		guard error.kind == "noJobs", isCard(remoteID), isDKB(bankCode: bankCode, server: server) else { return nil }
		return .unsupported(String(localized: "The FinTS server of DKB offers neither the balance nor the transactions of the card \(remoteID). Try again later, or contact the DKB support with this message."))
	}

	/// A login without a TAN method names the DKB app as the method to set up, the approval that DKB asks for at
	/// every login and every download. Any other error stays as it is.
	static func failure(_ error: any Error, bankCode: String?, server: URL?) -> any Error {
		guard case let .noTANMethod(message)? = error as? SyncFailure, isDKB(bankCode: bankCode, server: server) else { return error }
		return SyncFailure.noTANMethodOfBank(message,
			nextStep: String(localized: "Set up the DKB app as the approval method on the website of DKB first, then choose “Edit Login Data...”."))
	}
}
