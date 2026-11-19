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
		let iban: IBAN
		do { iban = try IBAN(parsing: text) } catch {
			switch error {
			case .country: throw .country
			case let .length(country, characters): throw .length(country: country, characters: characters)
			case .checksum: throw .checksum
			}
		}
		guard let bankCode = iban.germanBankCode else { throw .notGermany }
		return bankCode
	}
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
		case .empty: String(localized: "Enter the name of the bank, an IBAN, or a Bankleitzahl.")
		case .bankCodeDigits: String(localized: "A Bankleitzahl has 8 digits.")
		case .country: String(localized: "The IBAN starts with an unexpected country code.")
		case let .length(country, characters): String(localized: "An IBAN with the country code \(country) has \(characters) characters.")
		case .checksum: String(localized: "The checksum of the IBAN is invalid. Look for typing errors.")
		case .notGermany: String(localized: "Moneten finds banks only by a German IBAN or Bankleitzahl so far.")
		}
	}
}

private extension Character {
	var isASCIIDigit: Bool { isASCII && isNumber }
}

// MARK: Accounts of a new access

extension Access {
	/// The same login name at the same bank or service. A second setup of a login joins the access
	/// that the app has, so that one login keeps one session ("One session for the accounts of one login").
	/// A login without a user name, such as an OAuth login of an extension, names no login to compare,
	/// so each of its setups is an access of its own. FinTS login names compare in the form that the server
	/// sees, so a VR-Kennung stored in lower case is the same login as the one in capitals.
	public func isSameLogin(as other: Access) -> Bool {
		guard !loginName.isEmpty else { return false }
		switch (source, other.source) {
		case let (.fints(mine, myServer), .fints(theirs, theirServer)):
			return mine == theirs && FinTSServer.loginName(loginName, server: myServer) == FinTSServer.loginName(other.loginName, server: theirServer)
		// The service of an extension is its bank: the script gets it as the bank code.
		case (.extension, .extension): return loginName == other.loginName && source == other.source && bankName == other.bankName
		default: return loginName == other.loginName && source == other.source
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

/// The accounts that a login listed in a setup, each with its match. It keeps every listed account, also
/// those that "Look for New Accounts..." does not show, because the match of one account depends on all of
/// them: a migrated account without a subnumber is a choice only while the bank lists several subaccounts of
/// its number. `Ledger.accountsToAdd(_:listed:connecting:)` gets `listed`, never only the shown candidates.
public struct SetupListing: Sendable {
	public struct Candidate: Identifiable, Sendable {
		public let account: Account
		public let match: SetupMatch
		public var id: String { account.remoteID ?? "" }
		public var isPresent: Bool { if case .present = match { true } else { false } }
	}

	/// Every account that the bank listed.
	public let listed: [Account]
	/// The listed accounts that the setup shows: all of them, or with `onlyNew` those that the app does not have.
	public let candidates: [Candidate]

	public init(_ listed: [Account], in ledger: Ledger, onlyNew: Bool = false) {
		self.listed = listed
		let all = listed.map { Candidate(account: $0, match: ledger.setupMatch(for: $0, listed: listed)) }
		candidates = onlyNew ? all.filter { !$0.isPresent } : all
	}

	/// What "Connect..." of `account` chooses: the account in the row of the one listed account that it matches,
	/// when that row is a choice. An account that matches several listed accounts, such as a migrated account
	/// without a subnumber, is chosen in none, also when the app has connected all of them but one, because the
	/// user has not said which subaccount it is.
	public func connecting(_ account: Account) -> [UUID: UUID] {
		let matching = listed.filter { Ledger.isSame(account, as: $0) }
		guard matching.count == 1, let row = candidates.first(where: { $0.account.id == matching[0].id }),
			case let .choice(accounts) = row.match, accounts.contains(where: { $0.id == account.id }) else { return [:] }
		return [row.account.id: account.id]
	}
}

extension Ledger {
	/// How `candidate` relates to the accounts of the app, of all the accounts that the bank `listed`.
	/// An account matches in the currency of the candidate: by its IBAN when both have one, by the ID
	/// that the bank knows it by when the account has one, and else by account number and Bankleitzahl.
	/// So a subaccount with the same number is another account. An account with an access or an offline
	/// account is present. Of the others, an open account is connected, and a closed one is left as it
	/// is. An open account that matches several listed accounts, such as a migrated account without a
	/// subnumber, is a choice and is never connected on its own.
	///
	/// An account that the access of the candidate has, with the ID that the bank knows it by, is present
	/// whatever its type says: a refresh can make an account a portfolio while the account list of the
	/// bank still names a giro account.
	public func setupMatch(for candidate: Account, listed: [Account]) -> SetupMatch {
		if let own = accounts.first(where: { $0.accessID != nil && $0.accessID == candidate.accessID && $0.remoteID != nil && $0.remoteID == candidate.remoteID }) {
			return .present(own)
		}
		let matches = accounts.filter { Self.isSame($0, as: candidate) }
		if let present = matches.first(where: { $0.accessID != nil || $0.source == .offline }) { return .present(present) }
		let open = matches.filter { !$0.isClosed }
		switch open.count {
		case 0: return .new
		case 1 where listed.filter({ Self.isSame(open[0], as: $0) }).count <= 1: return .connects(open[0])
		default: return .choice(open)
		}
	}

	/// A portfolio holds positions and a cash account holds transactions, so an account without an access,
	/// such as a migrated one, never takes over a listed account of the other type, even when a bank gives
	/// both the same number or IBAN. An account with an access is matched whatever its type, because its
	/// connection is established: a refresh of the same login can make it a portfolio, and a setup of that
	/// login lists it with a new access ID that the store replaces by the known one.
	fileprivate static func isSame(_ account: Account, as candidate: Account) -> Bool {
		func number(_ a: Account) -> String? { a.accountNumber.map { String($0.drop { $0 == "0" }) } }
		guard account.currency == candidate.currency else { return false }
		guard account.accessID != nil || (account.kind == .portfolio) == (candidate.kind == .portfolio) else { return false }
		if let mine = account.iban, let theirs = candidate.iban { return mine == theirs }
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
				// The account keeps its history and its initial balance. Until its first refresh it shows the
				// computed balance, not the balance of the source.
				account.initialBalanceIsSet = true
				account.bankBalanceMinor = nil
				account.bankBalanceDate = nil
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
		case .everyTwoHours: String(localized: "every two hours")
		case .fourTimesADay: String(localized: "four times a day")
		case .onceADay: String(localized: "once a day")
		case .onceAWeek: String(localized: "once a week")
		case .onlyManually: String(localized: "only manually")
		case .never: String(localized: "never")
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
		var oldestPending: [UUID: Day] = [:]
		for t in transactions where t.isPending {
			oldestPending[t.accountID] = min(oldestPending[t.accountID] ?? t.bookingDate, t.bookingDate)
		}
		var plan: [UUID: [AccountRequest]] = [:]
		for a in accounts where !a.isClosed && chosen?.contains(a.id) != false {
			guard let accessID = a.accessID, let remoteID = a.remoteID else { continue }
			if a.refreshInterval == .never, scope != .account(a.id) { continue }
			// 14 days of overlap with the last success, and back to the oldest pending row, because a refresh
			// removes a pending row that the bank dropped only within the days it asked for. The connector asks
			// for no more than 90 days.
			let since = a.refreshedAt.map { refreshed in
				let overlap = Day(refreshed, calendar: calendar).adding(days: -14, calendar: calendar)
				return oldestPending[a.id].map { min($0, overlap) } ?? overlap
			}
			plan[accessID, default: []].append(AccountRequest(accountID: a.id, name: a.name, remoteID: remoteID, since: since,
				lastFetched: a.refreshedAt.map { Day($0, calendar: calendar) }, currency: a.currency,
				balance: a.bankBalanceMinor.map { Money(minorUnits: $0, currency: a.currency) }, refreshedAt: a.refreshedAt, comment: a.comment))
		}
		return plan
	}

	/// The accounts that the automatic refresh fetches at `now`, by the ID of their access. `canceled`
	/// holds the time at which the user canceled the refresh of an account.
	public func dueAccounts(at now: Date, canceled: [UUID: Date] = [:], calendar: Calendar = .current) -> [UUID: [AccountRequest]] {
		refreshAccounts(.all, calendar: calendar)
			.filter { !pausesAutomaticRefresh(of: $0.key) }
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
/// balance, and the error popover shows all of it. It stores the failure as data and no text of the app, so the app
/// words it in the language that it has when it shows it (#310).
public struct RefreshError: Codable, Hashable, Sendable {
	/// Why the refresh failed, with the answer of the bank as the bank sent it.
	public var failure: SyncFailure
	public var date: Date
	/// The notices of the bank from the same session.
	public var notices: [String]
	/// Only the user can resolve the error, with a refresh command (`SyncFailure.waitsForUser`).
	public var waitsForUser: Bool
	/// The refresh of the whole access failed in a way that can mean that the bank wants it set up again, so
	/// the error popover names "Edit Login Data..." (`SyncFailure.mayAskForNewSetup`). The failure can come
	/// at the login or after it, so the command is a suggestion.
	public var suggestsEditLoginData: Bool
	/// Set only when ING refused the login until a login on its website (`SyncFailure.websiteLoginNeeded`): the
	/// automatic refreshes of the access in a row since the last refresh by hand that ended with it. At
	/// `lockedLoginLimit` the automatic refresh pauses (`Ledger.recorded`).
	public var lockedLogins: Int?

	/// The automatic refreshes in a row that may end with the lock of ING before the automatic refresh pauses. 9942
	/// means a wrong PIN, and the bank test of issue #11 has not shown yet whether ING counts these logins toward
	/// the block of the PIN. ING may block it at 3, and its count does not start again with a refresh by hand, so the
	/// app stops at 2.
	public static let lockedLoginLimit = 2

	public init(failure: SyncFailure, date: Date, notices: [String] = [], waitsForUser: Bool = false, suggestsEditLoginData: Bool = false,
		lockedLogins: Int? = nil) {
		self.failure = failure
		self.date = date
		self.notices = notices
		self.waitsForUser = waitsForUser
		self.suggestsEditLoginData = suggestsEditLoginData
		self.lockedLogins = lockedLogins
	}

	/// The text of the failure, in the language of the app at the time it is read.
	public var message: String { failure.message }

	/// The return code of the bank, for example "9010".
	public var code: String? { failure.bankMessage?.code }

	private enum CodingKeys: String, CodingKey {
		case failure, date, notices, waitsForUser, suggestsEditLoginData, lockedLogins
		/// The text of an error stored before #310, in the language of the app at that time, and its return code.
		case message, code
	}

	/// An error stored before `waitsForUser`, `suggestsEditLoginData`, or `lockedLogins` existed has no such key. One
	/// stored before #310 has `message` and `code` in place of `failure`. It reads as a message of the bank, which
	/// shows the stored text and the code as before, until the next refresh replaces it.
	public init(from decoder: Decoder) throws {
		let c = try decoder.container(keyedBy: CodingKeys.self)
		if c.contains(.failure) {
			failure = try c.decode(SyncFailure.self, forKey: .failure)
		} else {
			failure = .bank(BankMessage(code: try c.decodeIfPresent(String.self, forKey: .code), text: try c.decode(String.self, forKey: .message)))
		}
		date = try c.decode(Date.self, forKey: .date)
		notices = try c.decode([String].self, forKey: .notices)
		waitsForUser = try c.decodeIfPresent(Bool.self, forKey: .waitsForUser) ?? false
		suggestsEditLoginData = try c.decodeIfPresent(Bool.self, forKey: .suggestsEditLoginData) ?? false
		lockedLogins = try c.decodeIfPresent(Int.self, forKey: .lockedLogins)
	}

	public func encode(to encoder: Encoder) throws {
		var c = encoder.container(keyedBy: CodingKeys.self)
		try c.encode(failure, forKey: .failure)
		try c.encode(date, forKey: .date)
		try c.encode(notices, forKey: .notices)
		try c.encode(waitsForUser, forKey: .waitsForUser)
		try c.encode(suggestsEditLoginData, forKey: .suggestsEditLoginData)
		try c.encodeIfPresent(lockedLogins, forKey: .lockedLogins)
	}
}

/// How the refresh of one account ended.
public enum AccountRefresh: Sendable, Equatable {
	case refreshed(Date)
	case failed(RefreshError)
}

extension Ledger {
	/// Whether the automatic refresh of `access` paused, because ING kept its FinTS login locked for
	/// `RefreshError.lockedLoginLimit` automatic refreshes in a row. The pause holds for every account of the access,
	/// also one that the user added or reopened later. A closed account keeps the lock of its access, so closing or
	/// reopening accounts never ends the pause.
	public func pausesAutomaticRefresh(of access: UUID) -> Bool {
		accounts.contains { $0.accessID == access && $0.refreshError?.pausesForLockedLogin == true }
	}

	/// The lock of ING that the accounts of `access` carry, open or closed, with the highest count, or nil.
	public func lockedLogin(of access: UUID) -> RefreshError? {
		accounts.compactMap { $0.accessID == access ? $0.refreshError : nil }.filter { $0.lockedLogins != nil }
			.max { ($0.lockedLogins ?? 0) < ($1.lockedLogins ?? 0) }
	}

	/// The accounts of `access` after a refresh that ended with `results`, as `Account.record` records them, and the
	/// other accounts of the access whose lock of ING the refresh changed. A failure because ING waits for a login on
	/// its website counts the automatic refreshes in a row that ended with it. The count belongs to the access, because
	/// each of its accounts logs in with the same PIN, so every open account of the access that the refresh did not
	/// fetch takes the error with the count, also one that the refresh did not ask for, and a closed account that
	/// carries the lock takes the new count. So the count stays when the user closes, reopens, or deletes accounts.
	/// A refresh by hand starts the count again. A refresh without the lock ends it, and the copies of the lock go.
	/// At `RefreshError.lockedLoginLimit` the automatic refresh pauses for the access until a refresh by hand.
	public func recorded(_ results: [UUID: AccountRefresh], of access: UUID, attended: Bool) -> [Account] {
		let lock = results.values.lazy.compactMap { result -> RefreshError? in
			if case let .failed(error) = result, error.lockedLogins != nil { error } else { nil }
		}.first
		let count = attended ? 0 : (lockedLogin(of: access)?.lockedLogins ?? 0) + 1
		var changed: [Account] = []
		for var account in accounts where account.accessID == access {
			let result = results[account.id]
			if let result { account.record(result) }
			let carries = account.refreshError?.lockedLogins != nil
			if let lock {
				// An account that the same refresh fetched keeps its success.
				if case .refreshed = result {
					changed.append(account)
					continue
				}
				guard !account.isClosed || carries else { continue }
				var error = carries ? account.refreshError ?? lock : lock
				error.lockedLogins = count
				error.waitsForUser = count >= RefreshError.lockedLoginLimit
				account.refreshError = error
				changed.append(account)
			} else if result != nil {
				changed.append(account)
			} else if !results.isEmpty, carries {
				// The login of this refresh went through, or failed for another reason, so the copy of the lock goes.
				account.refreshError = nil
				changed.append(account)
			}
		}
		return changed
	}
}

extension Account {
	/// The error of the last refresh that the app shows. A closed account shows none: it keeps only the lock of ING
	/// of its access (`Ledger.closing`), which no refresh of it can end.
	public var shownRefreshError: RefreshError? { isClosed ? nil : refreshError }
}

extension RefreshError {
	/// The automatic refresh paused for the lock of ING.
	public var pausesForLockedLogin: Bool { waitsForUser && lockedLogins != nil }

	/// The text that the app shows. While the automatic refresh pauses for the lock of ING, it adds why, in the language
	/// of the app at the time it shows it.
	public var shownMessage: String {
		guard pausesForLockedLogin else { return message }
		return message + "\n" + String(localized: "The automatic refresh paused after \(Self.lockedLoginLimit) attempts. After the login on the website, refresh the account by hand.")
	}
}

extension Account {
	/// A success records its time and clears the error ("An error ends with the next success"). A
	/// failure keeps the time of the last success. A closed account records neither, because the end of a refresh
	/// that ran while the user closed it says nothing about the account any more.
	public mutating func record(_ refresh: AccountRefresh) {
		guard !isClosed else { return }
		switch refresh {
		case let .refreshed(date):
			refreshedAt = date
			refreshError = nil
		case let .failed(error):
			refreshError = error
		}
	}

	/// The name as an account keeps it, without the white space around it, or nil when nothing is left.
	/// An account always has a name ("Account name"), and a name of only white space counts as empty.
	public static func acceptedName(_ typed: String) -> String? {
		let name = typed.trimmingCharacters(in: .whitespacesAndNewlines)
		return name.isEmpty ? nil : name
	}

	/// Takes the fields that the account settings edit from `edited`, the account as the settings showed
	/// it. The balance and the status of a refresh that ended while the settings were open stay. The type
	/// changes only when the user changed it from the type of `opened`, the account as the settings
	/// opened, to one of the `Account.kindChoices` of the current account. A portfolio stays a portfolio, also
	/// one that a refresh made while the settings were open. The initial balance, too, counts as entered only
	/// when the user changed it from that of `opened`, so a derived value that a refresh set meanwhile stays.
	/// The name changes only when the user changed it from that of `opened`, so a stored name with white space
	/// around it stays as it is. An empty name keeps the old name, because an account always has a name.
	public mutating func takeSettings(from edited: Account, opened: Account) {
		if edited.name != opened.name { name = Self.acceptedName(edited.name) ?? name }
		if edited.kind != opened.kind, kindChoices?.contains(edited.kind) == true { kind = edited.kind }
		isClosed = edited.isClosed
		if edited.initialBalanceMinor != opened.initialBalanceMinor { enterInitialBalance(edited.initialBalanceMinor) }
		color = edited.color
		refreshInterval = edited.refreshInterval
	}
}

extension SyncState {
	/// How each requested account ended, once the refresh ended. A canceled refresh gives no account an
	/// outcome, so its accounts keep their last state ("Cancel a refresh"). `date` is the time of a failure
	/// of the whole access. Only such a failure names "Edit Login Data...", because the login worked when
	/// single accounts fail. A failure of the whole access can also come after the login, and the app cannot
	/// tell it apart, so the command is a suggestion.
	public func accountRefreshes(of accounts: [UUID], notices: [BankMessage], at date: Date) -> [UUID: AccountRefresh] {
		func error(_ failure: SyncFailure, at date: Date, ofAccess: Bool = false) -> AccountRefresh {
			.failed(RefreshError(failure: failure, date: date, notices: notices.map(\.text),
				waitsForUser: failure.waitsForUser, suggestsEditLoginData: ofAccess && failure.mayAskForNewSetup,
				lockedLogins: failure.isWebsiteLoginNeeded ? 0 : nil))
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
			return Dictionary(uniqueKeysWithValues: accounts.map { ($0, error(failure, at: date, ofAccess: true)) })
		case .idle, .connecting, .fetching, .needsUser, .cancelled:
			return [:]
		}
	}
}
