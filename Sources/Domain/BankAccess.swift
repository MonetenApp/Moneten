import Foundation

// MARK: The entry of the first setup step

/// An IBAN or a Bankleitzahl that the user types into "Bank, IBAN, or Bankleitzahl" in the first step of "Add Account".
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
		case .empty: "Enter the name of the bank, an IBAN, or a Bankleitzahl."
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
	/// A login without a user name, such as an OAuth login of an extension, names no login to compare,
	/// so each of its setups is an access of its own.
	public func isSameLogin(as other: Access) -> Bool {
		guard !loginName.isEmpty, loginName == other.loginName else { return false }
		switch (source, other.source) {
		case let (.fints(mine, _), .fints(theirs, _)): return mine == theirs
		// The service of an extension is its bank: the script gets it as the bank code.
		case (.extension, .extension): return source == other.source && bankName == other.bankName
		default: return source == other.source
		}
	}
}

/// How an account that the bank lists for a new access relates to the accounts in the app
/// ("Do not add an account twice", "Connect a migrated account to its bank").
public enum SetupMatch: Equatable, Sendable {
	case new
	/// The app has the account already, and the setup does not add it again.
	case present(Account)
	/// An account without an access, for example a migrated one. The setup connects it, and it keeps its history.
	case connects(Account)
	/// Several open accounts without an access match. The setup connects the one that the user
	/// chooses, and adds a new account until the user chooses one.
	case choice([Account])
}

extension Ledger {
	/// How `candidate` relates to the accounts of the app, of all the accounts that the bank `listed`.
	/// An account matches in the currency of the candidate: by its IBAN when both have one, by the ID
	/// that the bank knows it by when the account has one, and else by account number and Bankleitzahl.
	/// So a subaccount with the same number is another account. An account with an access or an offline
	/// account is present. Of the others, an open account is connected, and a closed one is left as it
	/// is. An open account that matches several listed accounts, such as a migrated account without a
	/// subnumber, is a choice and is never connected on its own.
	public func setupMatch(for candidate: Account, listed: [Account]) -> SetupMatch {
		let matches = accounts.filter { Self.isSame($0, as: candidate) }
		if let present = matches.first(where: { $0.accessID != nil || $0.source == .offline }) { return .present(present) }
		let open = matches.filter { !$0.isClosed }
		switch open.count {
		case 0: return .new
		case 1 where listed.filter({ Self.isSame(open[0], as: $0) }).count <= 1: return .connects(open[0])
		default: return .choice(open)
		}
	}

	private static func isSame(_ account: Account, as candidate: Account) -> Bool {
		func iban(_ a: Account) -> String? { a.iban.map { $0.uppercased().filter { !$0.isWhitespace } } }
		func number(_ a: Account) -> String? { a.accountNumber.map { String($0.drop { $0 == "0" }) } }
		guard account.currency == candidate.currency else { return false }
		if let mine = iban(account), let theirs = iban(candidate) { return mine == theirs }
		guard account.bankCode == candidate.bankCode, let mine = number(account), mine == number(candidate) else { return false }
		return account.remoteID.map { $0 == candidate.remoteID } ?? true
	}

	/// What the setup stores for the `chosen` candidates of the `listed` accounts: each new account after
	/// the accounts of its group, and each account that a candidate connects. `connecting` holds the
	/// account that the user chose for a candidate with a choice, by the ID of the candidate. A candidate
	/// that the app has is left out, and an account is connected to one candidate at most.
	public func accountsToAdd(_ chosen: [Account], listed: [Account], connecting choices: [UUID: UUID] = [:]) -> [Account] {
		var next: [UUID?: Int] = [:]
		var connected: Set<UUID> = []
		return chosen.compactMap { candidate in
			let existing: Account?
			switch setupMatch(for: candidate, listed: listed) {
			case .present: return nil
			case let .connects(account): existing = account
			case let .choice(accounts): existing = accounts.first { $0.id == choices[candidate.id] }
			case .new: existing = nil
			}
			if var account = existing, connected.insert(account.id).inserted {
				account.source = .bank
				// The account keeps its history and its initial balance.
				account.initialBalanceIsSet = true
				account.accessID = candidate.accessID
				account.remoteID = candidate.remoteID
				return account
			}
			var account = candidate
			account.position = next[candidate.groupID] ?? nextTreePosition(in: candidate.groupID)
			next[candidate.groupID] = account.position + 1
			return account
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

/// "Refresh" in the account settings.
public enum RefreshInterval: String, Codable, CaseIterable, Sendable {
	case everyTwoHours, fourTimesADay, onceADay, onceAWeek
	/// Left out of the automatic refresh, fetched by every command.
	case onlyManually
	/// Fetched only by "Refresh Account" on the account itself.
	case never

	public var title: String {
		switch self {
		case .everyTwoHours: "every two hours"
		case .fourTimesADay: "four times a day"
		case .onceADay: "once a day"
		case .onceAWeek: "once a week"
		case .onlyManually: "only manually"
		case .never: "never"
		}
	}

	/// The time after the last refresh of the account at which the automatic refresh fetches it again.
	var period: TimeInterval? {
		switch self {
		case .everyTwoHours: 2 * 3600
		case .fourTimesADay: 6 * 3600
		case .onceADay: 24 * 3600
		case .onceAWeek: 7 * 24 * 3600
		case .onlyManually, .never: nil
		}
	}
}

extension Ledger {
	/// The accounts that a refresh command fetches, by the ID of their access. Accounts without an access
	/// and closed accounts are left out, and so is an account with the interval "never", unless the command
	/// names that account.
	public func refreshAccounts(_ scope: RefreshScope, calendar: Calendar = .current) -> [UUID: [AccountRequest]] {
		let chosen: Set<UUID>? = switch scope {
		case .all: nil
		case let .account(id): [id]
		case let .group(id): accountIDs(inGroupTree: id)
		}
		var plan: [UUID: [AccountRequest]] = [:]
		for a in accounts where !a.isClosed && chosen?.contains(a.id) != false {
			guard let accessID = a.accessID, let remoteID = a.remoteID else { continue }
			if a.refreshInterval == .never, scope != .account(a.id) { continue }
			// 14 days of overlap with the last success. The connector asks for no more than 90 days.
			let since = a.refreshedAt.map { Day($0, calendar: calendar).adding(days: -14, calendar: calendar) }
			plan[accessID, default: []].append(AccountRequest(accountID: a.id, name: a.name, remoteID: remoteID, since: since))
		}
		return plan
	}

	/// The accounts that the automatic refresh fetches at `now`, by the ID of their access. `canceled`
	/// holds the time at which the user canceled the refresh of an account.
	public func dueAccounts(at now: Date, canceled: [UUID: Date] = [:], calendar: Calendar = .current) -> [UUID: [AccountRequest]] {
		refreshAccounts(.all, calendar: calendar)
			.mapValues { $0.filter { account($0.accountID)?.isDue(at: now, canceledAt: canceled[$0.accountID]) == true } }
			.filter { !$0.value.isEmpty }
	}
}

extension Account {
	/// The period of the interval passed since the last refresh. After a failure or a cancel that counts
	/// from then, so a bank that is down is not asked at every run, and a refresh that the user canceled
	/// does not start again a minute later. An account that waits for the user is never due: only a
	/// refresh command asks the user.
	func isDue(at now: Date, canceledAt: Date?) -> Bool {
		guard let period = refreshInterval.period, refreshError?.waitsForUser != true else { return false }
		guard let last = [refreshedAt, refreshError?.date, canceledAt].compactMap({ $0 }).max() else { return true }
		return now.timeIntervalSince(last) >= period
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
	/// Only the user can resolve the error, with a refresh command (`SyncFailure.waitsForUser`).
	public var waitsForUser: Bool

	public init(message: String, code: String? = nil, date: Date, notices: [String] = [], waitsForUser: Bool = false) {
		self.message = message
		self.code = code
		self.date = date
		self.notices = notices
		self.waitsForUser = waitsForUser
	}

	/// An error stored before `waitsForUser` existed has no such key.
	public init(from decoder: Decoder) throws {
		let c = try decoder.container(keyedBy: CodingKeys.self)
		message = try c.decode(String.self, forKey: .message)
		code = try c.decodeIfPresent(String.self, forKey: .code)
		date = try c.decode(Date.self, forKey: .date)
		notices = try c.decode([String].self, forKey: .notices)
		waitsForUser = try c.decodeIfPresent(Bool.self, forKey: .waitsForUser) ?? false
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

	/// Takes the fields that the account settings edit from `edited`, the account as the settings showed
	/// it. The balance and the status of a refresh that ended while the settings were open stay.
	public mutating func takeSettings(from edited: Account) {
		name = edited.name
		kind = edited.kind
		isClosed = edited.isClosed
		if edited.initialBalanceMinor != initialBalanceMinor {
			initialBalanceMinor = edited.initialBalanceMinor
			initialBalanceIsSet = true
		}
		color = edited.color
		refreshInterval = edited.refreshInterval
	}
}

extension SyncState {
	/// How each requested account ended, once the refresh ended. A canceled refresh gives no account an
	/// outcome, so its accounts keep their last state ("Cancel a refresh"). `date` is the time of a failure
	/// of the whole access.
	public func accountRefreshes(of accounts: [UUID], notices: [BankMessage], at date: Date) -> [UUID: AccountRefresh] {
		func error(_ failure: SyncFailure, at date: Date) -> AccountRefresh {
			.failed(RefreshError(message: failure.message, code: failure.bankMessage?.code, date: date, notices: notices.map(\.text),
				waitsForUser: failure.waitsForUser))
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
