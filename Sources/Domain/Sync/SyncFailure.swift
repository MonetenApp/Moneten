import Foundation

/// A message of the bank: its code and its text. The app shows the text in the words of the bank.
/// Logs and diagnostics mask it, because it can contain names and amounts.
public struct BankMessage: Sendable, Equatable {
	/// The return code, for example "9942" in FinTS. Nil when the source has none.
	public let code: String?
	public let text: String

	public init(code: String? = nil, text: String) {
		self.code = code
		self.text = text
	}
}

/// Why a refresh of an access or of one account failed. Each case names what the user can do.
public enum SyncFailure: Error, Sendable, Equatable {
	/// An automatic refresh needed a PIN or a second factor.
	case needsUser(UserRequest.Kind)
	/// The bank rejected the PIN. The app does not send it again in this refresh.
	case pinRejected(BankMessage)
	case accessBlocked(BankMessage)
	/// The bank did not accept the TAN that the user typed.
	case tanRejected(BankMessage)
	/// The user declined the approval in the app of the bank, or did not answer there in time.
	case approvalDeclined(BankMessage?)
	/// The user did not answer the dialog within the validity of the challenge.
	case challengeExpired
	/// FinTS 9078: the bank does not know the product number of Moneten yet.
	case notRegistered
	/// The account was not fetched, because an earlier request of the same session failed.
	case notFetched
	/// Any other answer of the bank.
	case bank(BankMessage)
	/// No Internet connection. Shown only for a manual refresh.
	case offline
	case network(String)
	/// The bank does not offer what the account needs, for example transactions of a portfolio.
	case unsupported(String)
	/// The app could not store what the bank delivered for the account. Nothing of the account changed,
	/// and the next refresh delivers the same rows again.
	case notSaved(String)

	/// The answer of the bank in this failure, for its code in the error popover.
	public var bankMessage: BankMessage? {
		switch self {
		case let .pinRejected(m), let .accessBlocked(m), let .tanRejected(m), let .bank(m): m
		case let .approvalDeclined(m): m
		case .needsUser, .challengeExpired, .notRegistered, .notFetched, .offline, .network, .unsupported, .notSaved: nil
		}
	}

	/// The text that the app shows on the account and in the error popover.
	public var message: String {
		switch self {
		case .needsUser(.pin):
			"The PIN is needed. Choose “Refresh Account” to enter it."
		case .needsUser(.secondFactor):
			"An authorization is needed. Choose “Refresh Account” to give it."
		case let .pinRejected(m):
			"The bank did not accept the PIN: \(m.text)\nMore wrong attempts can block the access."
		case let .accessBlocked(m):
			"The bank blocked the access: \(m.text)"
		case let .tanRejected(m):
			"The bank did not accept the entered TAN: \(m.text)"
		case let .approvalDeclined(m):
			"The required authorization was not carried out." + (m.map { " \($0.text)" } ?? "")
		case .challengeExpired:
			"The two-factor authentication timed out."
		case .notRegistered:
			"The bank does not know Moneten yet. Banks take some weeks to accept a new app. Try again later."
		case .notFetched:
			"Canceled because of the previous error."
		case let .bank(m):
			m.text
		case .offline:
			"There is no Internet connection."
		case let .network(text):
			"The bank could not be reached: \(text)"
		case let .unsupported(text):
			text
		case let .notSaved(text):
			"The fetched transactions could not be saved: \(text)"
		}
	}
}
