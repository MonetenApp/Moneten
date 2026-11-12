import Foundation

// MARK: The entry of the first setup step

/// What the user types into "IBAN or Bankleitzahl" in the first step of "Add Account".
public enum BankEntry {
	/// The Bankleitzahl that an IBAN or a Bankleitzahl names. Spaces and lower case letters do not
	/// matter. The checks run before any bank is contacted ("Check the IBAN before any connection").
	public static func bankCode(of entry: String) throws(BankEntryError) -> String {
		let text = entry.uppercased().filter { !$0.isWhitespace }
		guard !text.isEmpty else { throw .empty }
		if text.allSatisfy(\.isASCIIDigit) {
			guard text.count == 8 else { throw .bankCodeDigits }
			return text
		}
		let country = String(text.prefix(2))
		guard country.allSatisfy(\.isASCIIUppercase), let length = ibanLengths[country] else { throw .country }
		guard text.count == length else { throw .length(country: country, characters: length) }
		guard hasValidChecksum(text) else { throw .checksum }
		guard country == "DE" else { throw .notGermany }
		return String(text.dropFirst(4).prefix(8))
	}

	/// ISO 7064 MOD 97-10: the first four characters move to the end, letters become 10 to 35, and
	/// the number must leave the remainder 1.
	private static func hasValidChecksum(_ iban: String) -> Bool {
		var remainder = 0
		for character in iban.dropFirst(4) + iban.prefix(4) {
			guard let value = character.isASCIIDigit ? character.wholeNumberValue : character.isASCIIUppercase ? Int(character.asciiValue! - 55) : nil else { return false }
			remainder = (remainder * (value < 10 ? 10 : 100) + value) % 97
		}
		return remainder == 1
	}

	/// The length of an IBAN in each country of the IBAN registry that the app expects.
	private static let ibanLengths: [String: Int] = [
		"AD": 24, "AE": 23, "AL": 28, "AT": 20, "AZ": 28, "BA": 20, "BE": 16, "BG": 22, "BH": 22, "BR": 29, "BY": 28, "CH": 21, "CR": 22,
		"CY": 28, "CZ": 24, "DE": 22, "DK": 18, "DO": 28, "EE": 20, "EG": 29, "ES": 24, "FI": 18, "FO": 18, "FR": 27, "GB": 22, "GE": 22,
		"GI": 23, "GL": 18, "GR": 27, "GT": 28, "HR": 21, "HU": 28, "IE": 22, "IL": 23, "IQ": 23, "IS": 26, "IT": 27, "JO": 30, "KW": 30,
		"KZ": 20, "LB": 28, "LC": 32, "LI": 21, "LT": 20, "LU": 20, "LV": 21, "MC": 27, "MD": 24, "ME": 22, "MK": 19, "MR": 27, "MT": 31,
		"MU": 30, "NL": 18, "NO": 15, "PK": 24, "PL": 28, "PS": 29, "PT": 25, "QA": 29, "RO": 24, "RS": 22, "SA": 24, "SC": 31, "SE": 24,
		"SI": 19, "SK": 24, "SM": 27, "ST": 25, "SV": 28, "TL": 23, "TN": 24, "TR": 26, "UA": 29, "VA": 22, "VG": 24, "XK": 20,
	]
}

public enum BankEntryError: Error, Equatable, Sendable {
	case empty
	case bankCodeDigits
	case country
	case length(country: String, characters: Int)
	case checksum
	/// A valid IBAN of another country. Only German banks offer FinTS.
	case notGermany

	public var message: String {
		switch self {
		case .empty: "Enter an IBAN or a Bankleitzahl."
		case .bankCodeDigits: "A Bankleitzahl has 8 digits."
		case .country: "The IBAN starts with an unexpected country code."
		case let .length(country, characters): "An IBAN with the country code \(country) has \(characters) characters."
		case .checksum: "The checksum of the IBAN is invalid. Look for typing errors."
		case .notGermany: "Moneten finds banks only by a German IBAN or Bankleitzahl so far."
		}
	}
}

private extension Character {
	var isASCIIDigit: Bool { isASCII && isNumber }
	var isASCIIUppercase: Bool { isASCII && isUppercase }
}

// MARK: Accounts of a new access

extension Access {
	/// The same login name at the same bank or service. A second setup of a login joins the access
	/// that the app has, so that one login keeps one session ("One session for the accounts of one login").
	public func isSameLogin(as other: Access) -> Bool {
		guard loginName == other.loginName else { return false }
		switch (source, other.source) {
		case let (.fints(mine, _), .fints(theirs, _)): return mine == theirs
		default: return source == other.source
		}
	}
}

/// How an account that the bank lists for a new access relates to the accounts in the app
/// ("Do not add an account twice").
public enum SetupMatch: Equatable, Sendable {
	case new
	/// The app has the account already, and the setup does not add it again.
	case present(Account)
	/// A migrated account without an access. The setup connects it, and it keeps its history.
	case migrated(Account)
}

extension Ledger {
	/// The account of the app with the IBAN of `candidate`, or with its account number and Bankleitzahl.
	public func setupMatch(for candidate: Account) -> SetupMatch {
		func iban(_ a: Account) -> String? { a.iban.map { $0.uppercased().filter { !$0.isWhitespace } } }
		func number(_ a: Account) -> String? { a.accountNumber.map { String($0.drop { $0 == "0" }) } }
		let found = accounts.first { a in
			if let mine = iban(a), mine == iban(candidate) { return true }
			return number(a) != nil && number(a) == number(candidate) && a.bankCode == candidate.bankCode
		}
		guard let found else { return .new }
		return found.source == .migrated && found.accessID == nil ? .migrated(found) : .present(found)
	}

	/// What the setup stores for the selected candidates: each new account after the accounts of its
	/// group, and each migrated account that a candidate connects. A candidate that the app has is left out.
	public func accountsToAdd(_ candidates: [Account]) -> [Account] {
		var next: [UUID?: Int] = [:]
		return candidates.compactMap { candidate in
			switch setupMatch(for: candidate) {
			case .present:
				return nil
			case var .migrated(account):
				account.source = .bank
				account.accessID = candidate.accessID
				account.remoteID = candidate.remoteID
				return account
			case .new:
				var account = candidate
				account.position = next[candidate.groupID] ?? nextTreePosition(in: candidate.groupID)
				next[candidate.groupID] = account.position + 1
				return account
			}
		}
	}
}

// MARK: Refresh commands

/// The accounts of a refresh command.
public enum RefreshScope: Hashable, Sendable {
	/// "Refresh All Accounts"
	case all
	/// "Refresh Account"
	case account(UUID)
	/// "Refresh Accounts" on a group, with its subgroups.
	case group(UUID)
}

extension Ledger {
	/// The accounts that a refresh command fetches, by the ID of their access. Accounts without an access
	/// and closed accounts are left out. The refresh intervals of issue #40 will narrow this further.
	public func refreshAccounts(_ scope: RefreshScope, calendar: Calendar = .current) -> [UUID: [AccountRequest]] {
		let chosen: Set<UUID>? = switch scope {
		case .all: nil
		case let .account(id): [id]
		case let .group(id): accountIDs(inGroupTree: id)
		}
		var plan: [UUID: [AccountRequest]] = [:]
		for a in accounts where !a.isClosed && chosen?.contains(a.id) != false {
			guard let accessID = a.accessID, let remoteID = a.remoteID else { continue }
			// 14 days of overlap with the last success. The connector asks for no more than 90 days.
			let since = a.refreshedAt.map { Day($0, calendar: calendar).adding(days: -14, calendar: calendar) }
			plan[accessID, default: []].append(AccountRequest(accountID: a.id, name: a.name, remoteID: remoteID, since: since))
		}
		return plan
	}
}

// MARK: Status of an account

/// The error of the last refresh of an account: the sidebar shows the message in place of the
/// balance, and the error popover shows all of it.
public struct RefreshError: Codable, Hashable, Sendable {
	public var message: String
	/// The return code of the bank, for example "9010".
	public var code: String?
	public var date: Date
	/// The notices of the bank from the same session.
	public var notices: [String]

	public init(message: String, code: String? = nil, date: Date, notices: [String] = []) {
		self.message = message
		self.code = code
		self.date = date
		self.notices = notices
	}
}

/// How the refresh of one account ended.
public enum AccountRefresh: Sendable, Equatable {
	case refreshed(Date)
	case failed(RefreshError)
}

extension Account {
	/// A success records its time and clears the error ("An error ends with the next success"). A
	/// failure keeps the time of the last success.
	public mutating func record(_ refresh: AccountRefresh) {
		switch refresh {
		case let .refreshed(date):
			refreshedAt = date
			refreshError = nil
		case let .failed(error):
			refreshError = error
		}
	}
}

extension SyncState {
	/// How each requested account ended, once the refresh ended. A canceled refresh gives no account an
	/// outcome, so its accounts keep their last state ("Cancel a refresh"). `date` is the time of a failure
	/// of the whole access.
	public func accountRefreshes(of accounts: [UUID], notices: [BankMessage], at date: Date) -> [UUID: AccountRefresh] {
		func error(_ failure: SyncFailure, at date: Date) -> AccountRefresh {
			.failed(RefreshError(message: failure.message, code: failure.bankMessage?.code, date: date, notices: notices.map(\.text)))
		}
		switch self {
		case let .finished(summary):
			var result: [UUID: AccountRefresh] = [:]
			for id in accounts {
				if summary.fetched.contains(id) { result[id] = .refreshed(summary.finishedAt) }
				else if let failure = summary.failures[id] { result[id] = error(failure, at: summary.finishedAt) }
			}
			return result
		case let .failed(failure):
			return Dictionary(uniqueKeysWithValues: accounts.map { ($0, error(failure, at: date)) })
		case .idle, .connecting, .fetching, .needsUser, .cancelled:
			return [:]
		}
	}
}
