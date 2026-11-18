import Domain
import Foundation

/// The rules of Targobank. Each bank group keeps its rules in a file of its own, so that the rules of another group
/// change no line of it.
enum Targobank {
	static let bankCode = "30020900"
	static let host = "fints.targobank.de"

	/// A Targobank access has the Bankleitzahl 30020900 or the FinTS host `fints.targobank.de`. The host counts in lower
	/// case and without one trailing dot, as the hosts of the other bank groups do.
	static func isTargobank(bankCode: String?, server: URL?) -> Bool {
		if bankCode == Self.bankCode { return true }
		guard var host = server?.host()?.lowercased() else { return false }
		if host.hasSuffix(".") { host.removeLast() }
		return host == Self.host
	}

	/// An account number of 16 digits, as a card account of Targobank has. Like `DKB.isCard`, it counts only ASCII digits.
	static func isCardNumber(_ remoteID: String) -> Bool {
		remoteID.count == 16 && remoteID.allSatisfy { $0.isASCII && $0.isNumber }
	}

	/// The outcome of an account, with each pending card debit as a debit. Only an account whose account number has 16
	/// digits gets the rule. The account number is the ID that the connector asks the helper for, because such an
	/// account has no IBAN.
	static func outcome(_ outcome: AccountOutcome, account remoteID: String, bankCode: String?, server: URL?) -> AccountOutcome {
		guard case var .fetched(result) = outcome, let fetched = result.transactions, isCardNumber(remoteID),
			isTargobank(bankCode: bankCode, server: server) else { return outcome }
		result.transactions = FetchedTransactions(rows: fetched.rows.map(debit), from: fetched.from, maxBookingShift: fetched.maxBookingShift)
		return .fetched(result)
	}

	/// Targobank may send a pending card debit as a positive amount with no name, no purpose, and no booking text (#242).
	/// Such a row becomes a debit of the same amount with the name and the purpose of `PendingCardDebit`. Every other row
	/// stays as the bank sent it, so a credit with a name, a purpose, a booking text, or an IBAN stays a credit.
	static func debit(_ row: Transaction) -> Transaction {
		guard row.isPending, row.amountMinor > 0, row.name.isEmpty, row.purpose.isEmpty, row.bookingText?.isEmpty ?? true,
			row.counterpartyIBAN == nil else { return row }
		var t = row
		t.amountMinor = -row.amountMinor
		// The original amount of a debit takes the minus as well, as the helper gives it to every other debit.
		t.originalAmount = Transaction.original(row.originalAmount, booked: t.amount)
		t.name = PendingCardDebit.name
		t.purpose = PendingCardDebit.purpose
		return t
	}
}
