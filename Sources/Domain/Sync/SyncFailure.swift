import Foundation

/// A message of the bank: its code and its text. The app shows the text in the words of the bank.
/// Logs and diagnostics mask it, because it can contain names and amounts.
public struct BankMessage: Sendable, Equatable {
	/// The return code, for example "9942" in FinTS. Nil when the source has none.
	public let code: String?
	public let text: String
	/// The name of the account in the app that the message is about, such as a balance request that failed
	/// beside transactions that worked. Nil for a message about the whole access.
	public let accountName: String?

	public init(code: String? = nil, text: String, accountName: String? = nil) {
		self.code = code
		self.text = text
		self.accountName = accountName
	}
}

/// Why a refresh of an access or of one account failed. Each case names what the user can do.
public enum SyncFailure: Error, Sendable, Equatable {
	/// An automatic refresh needed a PIN or a second factor.
	case needsUser(UserRequest.Kind)
	/// The bank rejected the PIN. The app does not send it again in this refresh.
	case pinRejected(BankMessage)
	/// An extension service rejected the login data. Automatic refreshes skip the access until the user enters it again.
	case loginRejected
	case accessBlocked(BankMessage)
	/// A savings bank answered that the user blocked this app under "Kontozugriffe" in its online banking. Only the
	/// user can unblock it there, so it acts like a blocked access.
	case appBlocked(BankMessage)
	/// ING refuses the FinTS login until the user logged in to its website, which it asks for at least every 90 days.
	/// The PIN is right, so it stays, and no PIN sheet opens. The automatic refresh goes on, so the access works again
	/// by itself once ING lets it log in.
	case websiteLoginNeeded(BankMessage)
	/// The bank did not accept the TAN that the user typed.
	case tanRejected(BankMessage)
	/// The user declined the approval in the app of the bank, or did not answer there in time.
	case approvalDeclined(BankMessage?)
	/// The user did not answer the dialog within the validity of the challenge.
	case challengeExpired
	/// The bank sent challenge data that the app cannot show, for example a flicker code that does not read.
	case invalidChallenge
	/// FinTS 9078: the bank does not know the product number of Moneten yet.
	case notRegistered
	/// The bank allows the user no TAN method for its FinTS server, so no login can succeed until the user
	/// sets one up on the website of the bank. The message is the answer of the bank that showed it.
	case noTANMethod(BankMessage?)
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

	/// The bank rejected the PIN or blocked the access or the app, or an extension service rejected the login data,
	/// so the PIN or the login data must never be sent again.
	public var rejectsPIN: Bool {
		switch self {
		case .pinRejected, .accessBlocked, .appBlocked, .loginRejected: true
		default: false
		}
	}

	/// Only the user can resolve the failure, so the automatic refresh leaves the account out until a
	/// manual refresh ends without it ("An automatic refresh never asks the user").
	public var waitsForUser: Bool {
		switch self {
		case .needsUser, .pinRejected, .loginRejected, .accessBlocked, .appBlocked, .noTANMethod: true
		default: false
		}
	}

	/// The bank ended the refresh of the whole access with a message of its own, or the authentication did
	/// not finish. Such an answer can mean that the bank wants the access set up again, for example after the
	/// user chose a new TAN method on its website or aborted an authentication, so the error of the account
	/// names "Edit Login Data..." ("Reinitialize an access after an aborted authentication"). The codes of the
	/// banks for it differ, and a message of the bank can also end the dialog after the login, so the app
	/// cannot tell it apart from other messages.
	public var mayAskForNewSetup: Bool {
		switch self {
		case .bank, .approvalDeclined, .challengeExpired, .invalidChallenge: true
		default: false
		}
	}

	/// No answer in a dialog resolves the failure: the bank blocked the access, or the user has no TAN
	/// method. So a command after an automatic refresh that failed with it does not run again with dialogs.
	public var dialogResolves: Bool {
		switch self {
		case .accessBlocked, .appBlocked, .noTANMethod: false
		default: waitsForUser
		}
	}

	/// The answer of the bank in this failure, for its code in the error popover.
	public var bankMessage: BankMessage? {
		switch self {
		case let .pinRejected(m), let .accessBlocked(m), let .appBlocked(m), let .websiteLoginNeeded(m), let .tanRejected(m), let .bank(m): m
		case let .approvalDeclined(m), let .noTANMethod(m): m
		case .needsUser, .loginRejected, .challengeExpired, .invalidChallenge, .notRegistered, .notFetched, .offline, .network, .unsupported, .notSaved: nil
		}
	}

	/// The text in the login step of "Add Account". Many banks answer an unknown user ID with a PIN
	/// error, so at the first login a rejected PIN also points to the user ID and to `userIDHelp`, the
	/// hint of the bank for it.
	public func messageAtFirstLogin(userIDHelp: String?) -> String {
		guard case let .pinRejected(m) = self else { return message }
		return String(localized: "The bank did not accept the PIN or the user ID: \(m.text)\nMany banks give this answer also for a wrong user ID, so check the user ID as well.")
			+ (userIDHelp.map { " \($0)" } ?? "") + "\n" + String(localized: "More wrong attempts can block the access.")
	}

	/// The text that the app shows on the account and in the error popover.
	public var message: String {
		switch self {
		case .needsUser(.pin):
			String(localized: "The PIN is needed. Choose “Refresh Account” to enter it.")
		case .needsUser(.secondFactor):
			String(localized: "An authorization is needed. Choose “Refresh Account” to give it.")
		case .needsUser(.allowHost):
			String(localized: "An extension asks to contact a new host. Choose “Refresh Account” to answer.")
		case .needsUser(.login):
			String(localized: "The login data is needed. Choose “Refresh Account” to enter it.")
		case .loginRejected:
			String(localized: "The login failed. The service did not accept the login data. Choose “Refresh Account” to enter it again.")
		case let .pinRejected(m):
			String(localized: "The bank did not accept the PIN: \(m.text)\nMore wrong attempts can block the access.")
		case let .accessBlocked(m):
			String(localized: "The bank blocked the access: \(m.text)\nAsk the bank to unblock it.")
		case let .appBlocked(m):
			String(localized: "Moneten is blocked in the online banking of the Sparkasse: \(m.text)\nUnblock Moneten there under “Service > Persönliche Einstellungen > Kontozugriffe”, then refresh the account.")
		case let .websiteLoginNeeded(m):
			String(localized: "ING asks for a login on its website first: \(m.text)\nLog in once at https://www.ing.de/ with the user name and the password, not with the QR code. About 24 hours later, the login of Moneten works again.")
		case let .tanRejected(m):
			String(localized: "The bank did not accept the entered TAN: \(m.text)")
		case let .approvalDeclined(m):
			String(localized: "The required authorization was not carried out.") + (m.map { " \($0.text)" } ?? "")
		case .challengeExpired:
			String(localized: "The two-factor authentication timed out.")
		case .invalidChallenge:
			String(localized: "The bank responded with an invalid challenge.")
		case .notRegistered:
			String(localized: "The bank does not know Moneten yet. Banks take some weeks to accept a new app. Try again later.")
		case let .noTANMethod(m):
			(m.map { String(localized: "There are no available TAN methods: \($0.text)") } ?? String(localized: "There are no available TAN methods."))
				+ "\n" + String(localized: "Set up a TAN method on the website of the bank, then choose “Edit Login Data...”.")
		case .notFetched:
			String(localized: "Canceled because of the previous error.")
		case let .bank(m):
			m.text
		case .offline:
			String(localized: "There is no Internet connection.")
		case let .network(text):
			String(localized: "The bank could not be reached: \(text)")
		case let .unsupported(text):
			text
		case let .notSaved(text):
			String(localized: "The fetched transactions could not be saved: \(text)")
		}
	}
}
