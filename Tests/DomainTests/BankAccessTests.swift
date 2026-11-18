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
		("", BankEntryError.empty, "Enter the name of the bank, an IBAN, or a Bankleitzahl."),
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

	static func candidate(_ name: String, iban: IBAN? = nil, number: String, remoteID: String? = nil, group: UUID? = nil) -> Account {
		Account(groupID: group, position: 0, name: name, kind: .giro, source: .bank, iban: iban, accountNumber: number, bankCode: "12030000",
			accessID: accessID, remoteID: remoteID ?? iban?.electronic ?? number)
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

	@Test("A migrated account takes over the access, keeps its ID, name, group, and initial balance, and drops the balance of the source")
	func migratedConnects() {
		let migrated = Account(position: 3, name: "Haushalt", kind: .giro, source: .migrated, iban: "DE02120300000000202051", bankBalanceMinor: 133_320,
			bankBalanceDate: Date(timeIntervalSince1970: 1_793_534_400), initialBalanceMinor: 150_000, sourceID: "moneymoney:17")
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
		#expect(added.first?.initialBalanceMinor == 150_000)
		#expect(added.first?.bankBalanceMinor == nil && added.first?.bankBalanceDate == nil)

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

	@Test("A migrated account starts the assistant with its IBAN, else its Bankleitzahl")
	func setupEntry() {
		#expect(Self.migrated("Giro").setupEntry == "DE02120300000000202051")
		let numbered = Account(position: 0, name: "Sparen", kind: .savings, source: .migrated, accountNumber: "9", bankCode: "12030000")
		#expect(numbered.setupEntry == "12030000")
		#expect(Account(position: 0, name: "Bar", kind: .cash, source: .migrated).setupEntry == "")
		#expect(Account(position: 0, name: "Depot", kind: .portfolio, source: .migrated, accountNumber: "9", bankCode: "DEUTDEFFXXX").setupEntry == "")
	}

	@Test("Connect chooses the account in the one row with a choice that it matches, and in none when it matches several")
	func connectFromAccount() {
		let giro = Self.migrated("Giro")
		let household = Self.migrated("Haushalt")
		let listed = Self.candidate("Girokonto", iban: "DE02120300000000202051", number: "202051")
		let shared = SetupListing([listed], in: Ledger(accounts: [giro, household]))
		#expect(shared.connecting(household.id) == [listed.id: household.id])
		#expect(Ledger(accounts: [giro, household]).accountsToAdd([listed], listed: [listed], connecting: shared.connecting(household.id)).map(\.id) == [household.id])
		// An account that the setup connects on its own, and an account that no row matches, need no choice.
		#expect(SetupListing([listed], in: Ledger(accounts: [giro])).connecting(giro.id) == [:])
		#expect(shared.connecting(UUID()) == [:])

		let savings = Account(position: 0, name: "Sparen", kind: .savings, source: .migrated, accountNumber: "9", bankCode: "12030000")
		let first = Self.candidate("Sparkonto 01", number: "9", remoteID: "9/01")
		let second = Self.candidate("Sparkonto 02", number: "9", remoteID: "9/02")
		#expect(SetupListing([first, second], in: Ledger(accounts: [savings])).connecting(savings.id) == [:])
	}

	@Test("Look for New Accounts shows only the new subaccount, and matches it against every subaccount that the bank listed")
	func newSubaccountBesideMigrated() {
		let linked = Account(position: 0, name: "Sparkonto 01", kind: .savings, source: .bank, accountNumber: "9", bankCode: "12030000",
			accessID: Self.accessID, remoteID: "9/01")
		let migrated = Account(position: 1, name: "Sparen", kind: .savings, source: .migrated, accountNumber: "9", bankCode: "12030000")
		let ledger = Ledger(accounts: [linked, migrated])
		let first = Self.candidate("Sparkonto 01", number: "9", remoteID: "9/01")
		let second = Self.candidate("Sparkonto 02", number: "9", remoteID: "9/02")
		let listing = SetupListing([first, second], in: ledger, onlyNew: true)
		#expect(listing.candidates.map(\.id) == ["9/02"])
		#expect(listing.candidates.map(\.match) == [.choice([migrated])])
		// "New account" stays chosen, so the old history of "Sparen" is not attached to 9/02.
		#expect(ledger.accountsToAdd([second], listed: listing.listed).map(\.id) == [second.id])
		#expect(ledger.accountsToAdd([second], listed: listing.listed, connecting: [second.id: migrated.id]).map(\.id) == [migrated.id])
		#expect(SetupListing([first, second], in: ledger).candidates.map(\.isPresent) == [true, false])
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

	@Test("A VR-Kennung in another case or with spaces is the same login on a server of a cooperative bank, and on another server it is not")
	func sameVRKennung() {
		let atruvia = URL(string: "https://fints2.atruvia.de/cgi-bin/hbciservlet")!
		let stored = Access(source: .fints(bankCode: "51090000", url: atruvia), bankName: "Wiesbadener Volksbank", loginName: "vrk12345678")
		#expect(stored.isSameLogin(as: Access(source: .fints(bankCode: "51090000", url: atruvia), bankName: "Wiesbadener Volksbank", loginName: "VRK12345678")))
		#expect(stored.isSameLogin(as: Access(source: .fints(bankCode: "51090000", url: atruvia), bankName: "Wiesbadener Volksbank", loginName: "VRK 1234 5678")))
		#expect(!stored.isSameLogin(as: Access(source: .fints(bankCode: "51090000", url: atruvia), bankName: "Wiesbadener Volksbank", loginName: "VRK12345679")))
		let alias = Access(source: .fints(bankCode: "51090000", url: atruvia), bankName: "Wiesbadener Volksbank", loginName: "vrkonto1")
		#expect(!alias.isSameLogin(as: Access(source: .fints(bankCode: "51090000", url: atruvia), bankName: "Wiesbadener Volksbank", loginName: "VRKONTO1")))
		let other = URL(string: "https://fints.musterbank.example/fints")!
		#expect(!Access(source: .fints(bankCode: "12030000", url: other), bankName: "Musterbank", loginName: "vrk12345678")
			.isSameLogin(as: Access(source: .fints(bankCode: "12030000", url: other), bankName: "Musterbank", loginName: "VRK12345678")))
		let apoBank = URL(string: "https://fints.apobank.de/FinTs30PinTanHttpGate")!
		#expect(Access(source: .fints(bankCode: "30060601", url: apoBank), bankName: "apoBank", loginName: "vrk12345678")
			.isSameLogin(as: Access(source: .fints(bankCode: "30060601", url: apoBank), bankName: "apoBank", loginName: "VRK12345678")))
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

	@Test("A refresh request carries the stored balance, the end of the last refresh, and the notes, which an extension reads")
	func requestCarriesTheStoredBalance() {
		var giro = Self.bankAccount("Giro", refreshedAt: Self.noon)
		giro.bankBalanceMinor = 125_050
		giro.comment = "Contract 4711"
		let request = Ledger(accounts: [giro]).refreshAccounts(.all)[Self.accessID]?.first
		#expect(request?.balance == Money(minorUnits: 125_050, currency: giro.currency))
		#expect(request?.refreshedAt == Self.noon)
		#expect(request?.comment == "Contract 4711")
	}

	@Test("A first refresh asks for the full history, and a later one from 14 days before the last success")
	func since() {
		let fresh = Self.bankAccount("Giro")
		let known = Self.bankAccount("Savings", refreshedAt: Self.noon)
		let plan = Ledger(accounts: [fresh, known]).refreshAccounts(.all, calendar: Self.utc)[Self.accessID]
		#expect(plan?.map(\.since) == [nil, Day(year: 2026, month: 10, day: 18)])
		// The day of the last success itself, so an answer that starts after it may miss older transactions.
		#expect(plan?.map(\.lastFetched) == [nil, Day(year: 2026, month: 11, day: 1)])
		let enforced = RefreshRequest(access: Access(source: .fints(bankCode: "12030000", url: URL(string: "https://fints.example.com/fints")!),
			bankName: "Musterbank", loginName: "erika77"), accounts: plan ?? [], enforced: true)
		#expect(enforced.accounts.map(\.since) == [nil, nil])
		#expect(enforced.accounts.map(\.lastFetched) == [nil, Day(year: 2026, month: 11, day: 1)])
	}

	@Test("A refresh asks from the oldest pending row, so it removes a deposit older than the overlap that the bank dropped")
	func sincePending() {
		var giro = Self.bankAccount("Giro", refreshedAt: Self.noon.addingTimeInterval(21 * 86_400))
		giro.initialBalanceMinor = 100_000
		var deposit = Transaction(accountID: giro.id, bookingDate: Day(year: 2026, month: 11, day: 1), amountMinor: -50_000, name: "Autovermietung Beispiel",
			purpose: "Kaution", isPending: true)
		deposit.isFetched = true
		var ledger = Ledger(accounts: [giro], transactions: [deposit])
		let firstDays = DayRange(start: Day(year: 2026, month: 11, day: 1), end: Day(year: 2026, month: 11, day: 10))
		#expect(ledger.balanceBars(accountIDs: [giro.id], range: firstDays, calendar: Self.utc).map(\.minorUnits) == Array(repeating: 50_000, count: 10))
		let since = ledger.refreshAccounts(.all, calendar: Self.utc)[Self.accessID]?.first?.since
		#expect(since == Day(year: 2026, month: 11, day: 1))

		let charge = Transaction(accountID: giro.id, bookingDate: Day(year: 2026, month: 11, day: 22), amountMinor: -48_000, name: "Autovermietung Beispiel",
			purpose: "Miete")
		let delivery = Delivery.refresh(RefreshResult(balance: nil, transactions: FetchedTransactions(rows: [charge], from: since)))
		let r = reconcile(delivery, into: giro, stored: [deposit], deleted: [], rules: Categorizer(ledger: ledger), now: Self.noon.addingTimeInterval(21 * 86_400))
		#expect(r.dropped == [deposit.id])
		ledger.apply(r)
		#expect(ledger.computedBalance(of: giro) == Money(minorUnits: 52_000, currency: "EUR"))
		#expect(ledger.balanceBars(accountIDs: [giro.id], range: firstDays, calendar: Self.utc).map(\.minorUnits) == Array(repeating: 100_000, count: 10))
	}

	// MARK: Status of an account

	@Test("A refresh records its time and clears the error, a failure keeps the last time and shows the error")
	func status() {
		var giro = Self.bankAccount("Giro")
		let later = Self.noon.addingTimeInterval(3_600)
		giro.record(.refreshed(Self.noon))
		#expect(giro.refreshedAt == Self.noon)
		#expect(giro.refreshError == nil)

		let error = RefreshError(failure: .bank(BankMessage(code: "9010", text: "Zugang vorübergehend gesperrt")), date: later, notices: ["Wartung am 14.11.2026"])
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
		current.record(.failed(RefreshError(failure: .bank(BankMessage(code: "9010", text: "Zugang vorübergehend gesperrt")), date: Self.noon)))
		current.record(.refreshed(Self.noon))
		var edited = opened
		edited.name = "Haushalt"
		edited.kind = .savings
		edited.isClosed = true
		edited.initialBalanceMinor = 10_000
		edited.color = "#FF9500"

		current.takeSettings(from: edited, opened: opened)
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

	@Test("An initial balance that the user enters in the account settings ends the derived value, so no manual row moves it")
	func enteredInitialBalanceIsNotDerived() {
		var opened = Self.bankAccount("Giro")
		opened.initialBalanceMinor = 250_000
		opened.initialBalanceIsSet = true
		opened.initialBalanceIsDerived = true
		var renamed = opened
		renamed.name = "Haushalt"
		var kept = opened
		kept.takeSettings(from: renamed, opened: opened)
		#expect(kept.initialBalanceIsDerived)
		var typed = opened
		typed.initialBalanceMinor = 300_000
		var current = opened
		current.takeSettings(from: typed, opened: opened)
		#expect(current.initialBalanceMinor == 300_000 && current.initialBalanceIsSet && !current.initialBalanceIsDerived)
		var calibrated = opened
		calibrated.enterInitialBalance(260_000)
		#expect(calibrated.initialBalanceMinor == 260_000 && calibrated.initialBalanceIsSet && !calibrated.initialBalanceIsDerived)
	}

	@Test("Saving the account settings keeps a derived initial balance that a refresh set while they were open, when the user did not change the field")
	func settingsKeepDerivedValueOfRefresh() {
		var opened = Self.bankAccount("Giro")
		opened.initialBalanceMinor = 10_000
		opened.initialBalanceIsSet = true
		opened.initialBalanceIsDerived = true
		// A refresh past a manual row set the derived value to 15.000 while the settings showed 10.000.
		var current = opened
		current.initialBalanceMinor = 15_000
		var renamed = opened
		renamed.name = "Haushalt"
		current.takeSettings(from: renamed, opened: opened)
		#expect(current.name == "Haushalt")
		#expect(current.initialBalanceMinor == 15_000 && current.initialBalanceIsDerived)
		// A value that the user typed still wins over the one of the refresh.
		var typed = opened
		typed.initialBalanceMinor = 30_000
		current.takeSettings(from: typed, opened: opened)
		#expect(current.initialBalanceMinor == 30_000 && !current.initialBalanceIsDerived)
	}

	@Test("Saving the account settings keeps the portfolio type that a refresh set while they were open, also when the user chose another type")
	func settingsAfterPortfolioRefresh() {
		var opened = Self.bankAccount("Depot")
		opened.kind = .other
		var current = opened
		current.kind = .portfolio
		var renamed = opened
		renamed.name = "Wertpapiere"
		var kept = current
		kept.takeSettings(from: renamed, opened: opened)
		#expect(kept.name == "Wertpapiere")
		#expect(kept.kind == .portfolio)
		var retyped = opened
		retyped.kind = .savings
		current.takeSettings(from: retyped, opened: opened)
		#expect(current.kind == .portfolio)
	}

	@Test("The menu \"Account type\" offers every type but \"Portfolio\", and a portfolio has no menu")
	func accountTypeChoices() {
		#expect(AccountKind.giro.choices == [.giro, .savings, .fixedTermDeposit, .loan, .creditCard, .cash, .other])
		#expect(AccountKind.creditCard.choices == [.giro, .savings, .fixedTermDeposit, .loan, .creditCard, .cash, .other])
		#expect(AccountKind.portfolio.choices == nil)
	}

	@Test("Saving the account settings never makes an account a portfolio")
	func settingsNeverChoosePortfolio() {
		let opened = Self.bankAccount("Giro")
		var edited = opened
		edited.kind = .portfolio
		var current = opened
		current.takeSettings(from: edited, opened: opened)
		#expect(current.kind == .giro)
	}

	@Test("A login that the bank ends with its own message or an authentication that did not finish names Edit Login Data, a failure of one account does not")
	func editLoginDataAfterFailedLogin() {
		let giro = UUID(), savings = UUID()
		let at = Self.noon
		let tanMethod = BankMessage(code: "9955", text: "Das gewählte TAN-Verfahren ist nicht mehr zugelassen.")
		for failure in [SyncFailure.bank(tanMethod), .approvalDeclined(nil), .challengeExpired, .invalidChallenge] {
			#expect(SyncState.failed(failure).accountRefreshes(of: [giro], notices: [], at: at)[giro]
				== .failed(RefreshError(failure: failure, date: at, suggestsEditLoginData: true)))
		}
		for failure in [SyncFailure.network("timeout"), .offline, .pinRejected(BankMessage(code: "9942", text: "PIN falsch")), .tanRejected(tanMethod),
			.needsUser(.pin), .notRegistered] {
			guard case let .failed(error)? = SyncState.failed(failure).accountRefreshes(of: [giro], notices: [], at: at)[giro] else {
				Issue.record("no error")
				continue
			}
			#expect(!error.suggestsEditLoginData)
		}
		let finished = SyncState.finished(SyncSummary(finishedAt: at, fetched: [giro], failures: [savings: .bank(tanMethod)]))
		#expect(finished.accountRefreshes(of: [giro, savings], notices: [], at: at)[savings]
			== .failed(RefreshError(failure: .bank(tanMethod), date: at)))
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
			savings: .failed(RefreshError(failure: .bank(blocked), date: at, notices: ["Wartung am 14.11.2026"])),
			card: .failed(RefreshError(failure: .notFetched, date: at, notices: ["Wartung am 14.11.2026"])),
		])
		#expect(SyncState.failed(.needsUser(.secondFactor)).accountRefreshes(of: [giro, savings], notices: [], at: at) == [
			giro: .failed(RefreshError(failure: .needsUser(.secondFactor), date: at, notices: [], waitsForUser: true)),
			savings: .failed(RefreshError(failure: .needsUser(.secondFactor), date: at, notices: [], waitsForUser: true)),
		])
		#expect(SyncState.cancelled.accountRefreshes(of: [giro], notices: notices, at: at).isEmpty)
		#expect(SyncState.fetching(done: 0, of: 1).accountRefreshes(of: [giro], notices: [], at: at).isEmpty)
	}
}
