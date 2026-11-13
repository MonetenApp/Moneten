import Foundation
import Testing
@testable import Domain

/// The bank accesses of accounts: the entry of the first setup step, accounts that the setup must
/// not add twice, the accounts that each refresh command fetches, and the status of an account after
/// a refresh (add-account-setup, add-account-refresh 1.1 to 1.3 and 1.14 to 1.17).
@Suite("Bank accesses")
struct BankAccessTests {
	static let accessID = UUID()
	static let otherAccessID = UUID()
	static let noon = Date(timeIntervalSince1970: 1_793_534_400)  // 2026-11-01 12:00 UTC
	static let utc: Calendar = {
		var c = Calendar(identifier: .gregorian)
		c.timeZone = TimeZone(identifier: "UTC")!
		return c
	}()

	// MARK: "IBAN or Bankleitzahl"

	@Test("An IBAN with spaces and lower case letters names its Bankleitzahl, and so does the Bankleitzahl itself")
	func bankCode() throws {
		#expect(try BankEntry.bankCode(of: "de02 1203 0000 0000 2020 51") == "12030000")
		#expect(try BankEntry.bankCode(of: "12030000") == "12030000")
		#expect(try BankEntry.bankCode(of: " 1203 0000 ") == "12030000")
	}

	@Test("A wrong entry names the failed check before any bank is contacted", arguments: [
		("", BankEntryError.empty, "Enter an IBAN or a Bankleitzahl."),
		("DE03120300000000202051", .checksum, "The checksum of the IBAN is invalid. Look for typing errors."),
		("DE0212030000000020205", .length(country: "DE", characters: 22), "An IBAN with the country code DE has 22 characters."),
		("XX02120300000000202051", .country, "The IBAN starts with an unexpected country code."),
		("1203000", .bankCodeDigits, "A Bankleitzahl has 8 digits."),
		("AT611904300234573201", .notGermany, "Moneten finds banks only by a German IBAN or Bankleitzahl so far."),
	])
	func wrongEntry(entry: String, error: BankEntryError, message: String) {
		#expect(throws: error) { try BankEntry.bankCode(of: entry) }
		#expect(error.message == message)
	}

	// MARK: Do not add an account twice

	static func candidate(_ name: String, iban: String? = nil, number: String, remoteID: String? = nil, group: UUID? = nil) -> Account {
		Account(groupID: group, position: 0, name: name, kind: .giro, source: .bank, iban: iban, accountNumber: number, bankCode: "12030000",
			accessID: accessID, remoteID: remoteID ?? iban ?? number)
	}

	@Test("An account with the same IBAN, or the same account number and Bankleitzahl, is present already")
	func present() {
		let giro = Account(position: 0, name: "Giro", kind: .giro, source: .offline, iban: "DE02 1203 0000 0000 2020 51")
		let card = Account(position: 1, name: "Card", kind: .creditCard, source: .offline, accountNumber: "0004711", bankCode: "12030000")
		let ledger = Ledger(accounts: [giro, card])
		#expect(ledger.setupMatch(for: Self.candidate("Girokonto", iban: "DE02120300000000202051", number: "202051"), listed: []) == .present(giro))
		#expect(ledger.setupMatch(for: Self.candidate("Kreditkarte", number: "4711"), listed: []) == .present(card))
		#expect(ledger.setupMatch(for: Self.candidate("Tagesgeld", iban: "DE89370400440532013000", number: "532013000"), listed: []) == .new)
		var elsewhere = Self.candidate("Kreditkarte", number: "4711")
		elsewhere.bankCode = "10010010"
		#expect(ledger.setupMatch(for: elsewhere, listed: [elsewhere]) == .new)
	}

	@Test("The setup adds only new accounts, after the accounts of their group, and never an account the app has")
	func notAddedTwice() {
		let group = UUID()
		let giro = Account(groupID: group, position: 0, name: "Giro", kind: .giro, source: .offline, iban: "DE02120300000000202051")
		let ledger = Ledger(groups: [AccountGroup(id: group, name: "Private", position: 0)], accounts: [giro])
		let again = Self.candidate("Girokonto", iban: "DE02120300000000202051", number: "202051", group: group)
		let savings = Self.candidate("Tagesgeld", iban: "DE89370400440532013000", number: "532013000", group: group)
		let card = Self.candidate("Kreditkarte", number: "4711", group: group)

		let added = ledger.accountsToAdd([again, savings, card], listed: [again, savings, card])
		#expect(added.map(\.name) == ["Tagesgeld", "Kreditkarte"])
		#expect(added.map(\.position) == [1, 2])
		#expect(added.map(\.groupID) == [group, group])
		#expect(added.map(\.accessID) == [Self.accessID, Self.accessID])
		#expect(added.map(\.remoteID) == ["DE89370400440532013000", "4711"])
	}

	@Test("A migrated account takes over the access and keeps its ID, name, and group")
	func migratedConnects() {
		let migrated = Account(position: 3, name: "Haushalt", kind: .giro, source: .migrated, iban: "DE02120300000000202051", sourceID: "moneymoney:17")
		let ledger = Ledger(accounts: [migrated])
		let listed = Self.candidate("Girokonto", iban: "DE02120300000000202051", number: "202051")
		#expect(ledger.setupMatch(for: listed, listed: [listed]) == .connects(migrated))

		let added = ledger.accountsToAdd([listed], listed: [listed])
		#expect(added.count == 1)
		#expect(added.first?.id == migrated.id)
		#expect(added.first?.name == "Haushalt")
		#expect(added.first?.position == 3)
		#expect(added.first?.source == .bank)
		#expect(added.first?.accessID == Self.accessID)
		#expect(added.first?.remoteID == "DE02120300000000202051")

		var connected = migrated
		connected.accessID = UUID()
		#expect(Ledger(accounts: [connected]).setupMatch(for: listed, listed: [listed]) == .present(connected))
	}

	static func migrated(_ name: String, currency: String = "EUR", closed: Bool = false) -> Account {
		Account(position: 0, name: name, kind: .giro, source: .migrated, currency: currency, iban: "DE02120300000000202051", isClosed: closed)
	}

	@Test("Of the migrated accounts with the IBAN, the setup connects the open one in the same currency")
	func openAccountInSameCurrency() {
		let old = Self.migrated("Giro (alt)", closed: true)
		let giro = Self.migrated("Giro")
		let dollar = Self.migrated("Giro USD", currency: "USD")
		let listed = Self.candidate("Girokonto", iban: "DE02120300000000202051", number: "202051")
		#expect(Ledger(accounts: [old, giro, dollar]).setupMatch(for: listed, listed: [listed]) == .connects(giro))
		#expect(Ledger(accounts: [giro, old]).setupMatch(for: listed, listed: [listed]) == .connects(giro))
		#expect(Ledger(accounts: [dollar]).setupMatch(for: listed, listed: [listed]) == .new)
		#expect(Ledger(accounts: [old]).setupMatch(for: listed, listed: [listed]) == .new)
		#expect(Ledger(accounts: [dollar]).accountsToAdd([listed], listed: [listed]).map(\.id) == [listed.id])
	}

	@Test("Several open migrated accounts with the IBAN are a choice, and only the account the user chooses is connected")
	func severalMatches() {
		let giro = Self.migrated("Giro")
		let household = Self.migrated("Haushalt")
		let ledger = Ledger(accounts: [giro, household])
		let listed = Self.candidate("Girokonto", iban: "DE02120300000000202051", number: "202051")
		#expect(ledger.setupMatch(for: listed, listed: [listed]) == .choice([giro, household]))

		#expect(ledger.accountsToAdd([listed], listed: [listed]).map(\.id) == [listed.id])
		let connected = ledger.accountsToAdd([listed], listed: [listed], connecting: [listed.id: household.id])
		#expect(connected.map(\.id) == [household.id])
		#expect(connected.first?.accessID == Self.accessID)

		// Two listed accounts never take over the same account.
		let twin = Self.candidate("Girokonto 2", iban: "DE02120300000000202051", number: "202051", remoteID: "202051/1")
		let both = ledger.accountsToAdd([listed, twin], listed: [listed, twin], connecting: [listed.id: giro.id, twin.id: giro.id])
		#expect(both.map(\.id) == [giro.id, twin.id])
	}

	@Test("An account of the bank without an access is connected again, an offline account is present")
	func withoutAccess() {
		let orphan = Account(position: 0, name: "Giro", kind: .giro, source: .bank, iban: "DE02120300000000202051", remoteID: "DE02120300000000202051")
		let offline = Account(position: 0, name: "Giro", kind: .giro, source: .offline, iban: "DE02120300000000202051")
		let listed = Self.candidate("Girokonto", iban: "DE02120300000000202051", number: "202051")
		#expect(Ledger(accounts: [orphan]).setupMatch(for: listed, listed: [listed]) == .connects(orphan))
		#expect(Ledger(accounts: [offline]).setupMatch(for: listed, listed: [listed]) == .present(offline))
		#expect(Ledger(accounts: [orphan]).accountsToAdd([listed], listed: [listed]).map(\.accessID) == [Self.accessID])
	}

	@Test("A subaccount with the same account number is new when the app has another subaccount of that number")
	func otherSubaccount() {
		let first = Account(position: 0, name: "Sparkonto 01", kind: .savings, source: .bank, accountNumber: "9", bankCode: "12030000",
			accessID: Self.accessID, remoteID: "9/01")
		let second = Self.candidate("Sparkonto 02", number: "9", remoteID: "9/02")
		#expect(Ledger(accounts: [first]).setupMatch(for: second, listed: [second]) == .new)
		#expect(Ledger(accounts: [first]).setupMatch(for: Self.candidate("Sparkonto 01", number: "9", remoteID: "9/01"), listed: []) == .present(first))
	}

	@Test("A migrated account without a subnumber is a choice when the bank lists several subaccounts of its number")
	func migratedSubaccounts() {
		let migrated = Account(position: 0, name: "Sparen", kind: .savings, source: .migrated, accountNumber: "9", bankCode: "12030000")
		let ledger = Ledger(accounts: [migrated])
		let first = Self.candidate("Sparkonto 01", number: "9", remoteID: "9/01")
		let second = Self.candidate("Sparkonto 02", number: "9", remoteID: "9/02")
		#expect(ledger.setupMatch(for: second, listed: [first, second]) == .choice([migrated]))
		#expect(ledger.accountsToAdd([first, second], listed: [first, second]).map(\.id) == [first.id, second.id])
		#expect(ledger.accountsToAdd([first, second], listed: [first, second], connecting: [second.id: migrated.id]).map(\.id) == [first.id, migrated.id])
	}

	@Test("An account with another IBAN is new, also with the same account number")
	func otherIBAN() {
		let migrated = Account(position: 0, name: "Giro", kind: .giro, source: .migrated, iban: "DE02120300000000202051", accountNumber: "202051",
			bankCode: "12030000")
		let sub = Self.candidate("Unterkonto", iban: "DE89370400440532013000", number: "202051", remoteID: "DE89370400440532013000")
		#expect(Ledger(accounts: [migrated]).setupMatch(for: sub, listed: [sub]) == .new)
	}

	// MARK: Refresh commands

	static func bankAccount(_ name: String, group: UUID? = nil, access: UUID = accessID, closed: Bool = false, refreshedAt: Date? = nil) -> Account {
		Account(groupID: group, position: 0, name: name, kind: .giro, source: .bank, isClosed: closed, accessID: access, remoteID: "R-\(name)", refreshedAt: refreshedAt)
	}

	static func names(_ plan: [UUID: [AccountRequest]]) -> [UUID: [String]] {
		plan.mapValues { $0.map(\.name) }
	}

	@Test("An extension login is the same only at the same service with the same user name, and a login without a user name never is")
	func sameExtensionLogin() {
		let tan = Access(source: .extension(id: "demo-tan"), bankName: "Demo TAN", loginName: "erika")
		#expect(tan.isSameLogin(as: Access(source: .extension(id: "demo-tan"), bankName: "Demo TAN", loginName: "erika")))
		#expect(!tan.isSameLogin(as: Access(source: .extension(id: "demo-tan"), bankName: "Demo Push", loginName: "erika")))
		#expect(!tan.isSameLogin(as: Access(source: .extension(id: "demo-tan"), bankName: "Demo TAN", loginName: "max")))
		let broker = Access(source: .extension(id: "demo-json-oauth"), bankName: "Demo Broker", loginName: "")
		#expect(!broker.isSameLogin(as: Access(source: .extension(id: "demo-json-oauth"), bankName: "Demo Broker", loginName: "")))
	}

	@Test("Refresh All Accounts fetches every account with an access that is not closed, one request per access")
	func refreshAll() {
		let offline = Account(position: 0, name: "Cash", kind: .cash, source: .offline)
		let migrated = Account(position: 0, name: "Old", kind: .giro, source: .migrated)
		let ledger = Ledger(accounts: [Self.bankAccount("Giro"), Self.bankAccount("Savings"), Self.bankAccount("Closed", closed: true),
			Self.bankAccount("Depot", access: Self.otherAccessID), offline, migrated])
		#expect(Self.names(ledger.refreshAccounts(.all)) == [Self.accessID: ["Giro", "Savings"], Self.otherAccessID: ["Depot"]])
		#expect(ledger.refreshAccounts(.all)[Self.accessID]?.map(\.remoteID) == ["R-Giro", "R-Savings"])
	}

	@Test("Refresh Account fetches only the selected account, also when its access has more")
	func refreshAccount() {
		let giro = Self.bankAccount("Giro")
		let ledger = Ledger(accounts: [giro, Self.bankAccount("Savings")])
		#expect(Self.names(ledger.refreshAccounts(.account(giro.id))) == [Self.accessID: ["Giro"]])
		let cash = Account(position: 0, name: "Cash", kind: .cash, source: .offline)
		#expect(Ledger(accounts: [cash]).refreshAccounts(.account(cash.id)).isEmpty)
		let closed = Self.bankAccount("Closed", closed: true)
		#expect(Ledger(accounts: [closed]).refreshAccounts(.account(closed.id)).isEmpty)
	}

	@Test("Refresh Accounts on a group fetches the accounts of the group and of its subgroups")
	func refreshGroup() {
		let privat = AccountGroup(name: "Private", position: 0)
		let travel = AccountGroup(name: "Travel", parentID: privat.id, position: 1)
		let business = AccountGroup(name: "Business", position: 1)
		let ledger = Ledger(groups: [privat, travel, business], accounts: [Self.bankAccount("Giro", group: privat.id),
			Self.bankAccount("Card", group: travel.id, access: Self.otherAccessID), Self.bankAccount("Office", group: business.id)])
		#expect(Self.names(ledger.refreshAccounts(.group(privat.id))) == [Self.accessID: ["Giro"], Self.otherAccessID: ["Card"]])
	}

	@Test("A first refresh asks for the full history, and a later one from 14 days before the last success")
	func since() {
		let fresh = Self.bankAccount("Giro")
		let known = Self.bankAccount("Savings", refreshedAt: Self.noon)
		let plan = Ledger(accounts: [fresh, known]).refreshAccounts(.all, calendar: Self.utc)[Self.accessID]
		#expect(plan?.map(\.since) == [nil, Day(year: 2026, month: 10, day: 18)])
	}

	// MARK: Status of an account

	@Test("A refresh records its time and clears the error, a failure keeps the last time and shows the error")
	func status() {
		var giro = Self.bankAccount("Giro")
		let later = Self.noon.addingTimeInterval(3_600)
		giro.record(.refreshed(Self.noon))
		#expect(giro.refreshedAt == Self.noon)
		#expect(giro.refreshError == nil)

		let error = RefreshError(message: "Zugang vorübergehend gesperrt", code: "9010", date: later, notices: ["Wartung am 14.11.2026"])
		giro.record(.failed(error))
		#expect(giro.refreshedAt == Self.noon)
		#expect(giro.refreshError == error)

		giro.record(.refreshed(later))
		#expect(giro.refreshedAt == later)
		#expect(giro.refreshError == nil)
	}

	@Test("Saving the account settings keeps the balance and the status of a refresh that ended while they were open")
	func settingsAfterRefresh() {
		let opened = Self.bankAccount("Giro")
		var current = opened
		current.bankBalanceMinor = 234_015
		current.bankBalanceDate = Self.noon
		current.record(.failed(RefreshError(message: "Zugang vorübergehend gesperrt", code: "9010", date: Self.noon)))
		current.record(.refreshed(Self.noon))
		var edited = opened
		edited.name = "Haushalt"
		edited.kind = .savings
		edited.isClosed = true
		edited.initialBalanceMinor = 10_000
		edited.color = "#FF9500"

		current.takeSettings(from: edited)
		#expect(current.name == "Haushalt")
		#expect(current.kind == .savings)
		#expect(current.isClosed)
		#expect(current.initialBalanceMinor == 10_000)
		#expect(current.color == "#FF9500")
		#expect(current.bankBalanceMinor == 234_015)
		#expect(current.bankBalanceDate == Self.noon)
		#expect(current.refreshedAt == Self.noon)
		#expect(current.refreshError == nil)
	}

	@Test("The end of a refresh gives each requested account its outcome, and a cancel gives none")
	func endOfRefresh() {
		let giro = UUID(), savings = UUID(), card = UUID()
		let at = Self.noon
		let notices = [BankMessage(text: "Wartung am 14.11.2026")]
		let blocked = BankMessage(code: "9010", text: "Zugang vorübergehend gesperrt")
		let finished = SyncState.finished(SyncSummary(finishedAt: at, fetched: [giro], failures: [savings: .bank(blocked), card: .notFetched]))
		#expect(finished.accountRefreshes(of: [giro, savings, card], notices: notices, at: at.addingTimeInterval(5)) == [
			giro: .refreshed(at),
			savings: .failed(RefreshError(message: "Zugang vorübergehend gesperrt", code: "9010", date: at, notices: ["Wartung am 14.11.2026"])),
			card: .failed(RefreshError(message: "Canceled because of the previous error.", code: nil, date: at, notices: ["Wartung am 14.11.2026"])),
		])
		#expect(SyncState.failed(.needsUser(.secondFactor)).accountRefreshes(of: [giro, savings], notices: [], at: at) == [
			giro: .failed(RefreshError(message: "An authorization is needed. Choose “Refresh Account” to give it.", code: nil, date: at, notices: [])),
			savings: .failed(RefreshError(message: "An authorization is needed. Choose “Refresh Account” to give it.", code: nil, date: at, notices: [])),
		])
		#expect(SyncState.cancelled.accountRefreshes(of: [giro], notices: notices, at: at).isEmpty)
		#expect(SyncState.fetching(done: 0, of: 1).accountRefreshes(of: [giro], notices: [], at: at).isEmpty)
	}
}
