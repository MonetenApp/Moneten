import AppKit
import Domain
import Foundation
import Import
import Observation
import Storage
import Sync
import SwiftUI

enum SidebarSelection: Hashable {
	case account(UUID)
	case group(UUID)
	case category(UUID)

	var scope: LedgerScope {
		switch self {
		case let .account(id): .account(id)
		case let .group(id): .accountGroup(id)
		case let .category(id): .category(id)
		}
	}
}

enum ViewMode: String, CaseIterable {
	case list, barChart, pieChart
}

enum BalanceMode: String {
	case daily, monthlyAverage
}

enum PeriodChoice: Hashable {
	case all, days30, days90, months12
	case month(Day)
	case quarter(Day)
	case year(Day)
	case custom(Day, Day)

	/// The period of a bar in the balance chart: its day or days, or its month.
	init(bar: BalanceBar, monthly: Bool) {
		let last = bar.end.adding(days: -1)
		self = monthly ? .month(bar.start) : .custom(bar.start, last)
	}

	/// The period of a bar in a category chart.
	init(start: Day, chartPeriod: ChartPeriod) {
		switch chartPeriod {
		case .month: self = .month(start)
		case .quarter: self = .quarter(start)
		case .year: self = .year(start)
		}
	}

	func range(today: Day = .today()) -> DayRange {
		switch self {
		case .all: .all
		case .days30: DayRange(start: today.adding(days: -29), end: today)
		case .days90: DayRange(start: today.adding(days: -89), end: today)
		case .months12: DayRange(start: today.adding(months: -12).adding(days: 1), end: today)
		case let .month(d): DayRange(start: d, end: d.adding(months: 1).adding(days: -1))
		case let .quarter(d): DayRange(start: d, end: d.adding(months: 3).adding(days: -1))
		case let .year(d): DayRange(start: d, end: d.adding(months: 12).adding(days: -1))
		case let .custom(a, b): DayRange(start: a, end: b)
		}
	}
}

/// Settings that the app needs before the database is open. They hold no personal data.
enum Preference {
	static let lockOnClose = "lockWhenMainWindowIsClosed"
	/// Version 1 stored "lockAfterMinutes" also while the lock was off, as the suggestion of the
	/// old number field. The new key starts at the default of 10 minutes; `registerDefaults` keeps
	/// the old value only where the lock was on.
	static let lockAfterMinutes = "lockAfterInactivityMinutes"
	static let lockAfterEnabled = "lockAfterInactivity"
	static let unlockAutomatically = "unlockAutomatically"
	static let unlockWithTouchID = "unlockWithTouchID"
	static let unlockWithAppleWatch = "unlockWithAppleWatch"
	static let viewMode = "viewMode"
	static let balanceMode = "balanceMode"

	/// The app locks after 10 minutes without activity unless the user turns it off. MoneyMoney has
	/// this off and suggests 5 minutes; the owner chose on with 10 minutes.
	static let defaultLockAfterMinutes = 10

	/// The values of settings the user has not changed. A user who turned the inactivity lock on in
	/// version 1 keeps the minutes chosen there.
	static func registerDefaults() {
		adoptLegacyDomain()
		let d = UserDefaults.standard
		let oldMinutes = "lockAfterMinutes"
		if d.object(forKey: lockAfterMinutes) == nil, d.object(forKey: lockAfterEnabled) as? Bool == true,
			d.integer(forKey: oldMinutes) > 0 {
			d.set(d.integer(forKey: oldMinutes), forKey: lockAfterMinutes)
		}
		d.removeObject(forKey: oldMinutes)
		d.register(defaults: [lockAfterEnabled: true, lockAfterMinutes: defaultLockAfterMinutes])
	}

	/// Copies the settings of the bundle identifier before the rename to Moneten (ADR 0013) once.
	/// Runs with their own data folder skip it, so tests never write the real settings.
	private static func adoptLegacyDomain() {
		guard ProcessInfo.processInfo.environment["MONETEN_DATA_DIR"] == nil else { return }
		let d = UserDefaults.standard, done = "adoptedSettingsOfMonetenMoneten"
		guard !d.bool(forKey: done) else { return }
		for (key, value) in d.persistentDomain(forName: "io.github.alexander-schneider.MonetenMoneten") ?? [:] where d.object(forKey: key) == nil {
			d.set(value, forKey: key)
		}
		d.set(true, forKey: done)
	}
}

@MainActor
@Observable
final class AppModel {
	enum Phase: Equatable {
		case starting
		case firstLaunch
		case locked
		case unlocked
		case failed(String)
	}

	let vault = Vault(folder: .standard())
	/// The refreshes of the bank accesses and their dialogs.
	let sync = SyncCoordinator()
	private(set) var phase: Phase = .starting
	private(set) var hasPassword = false
	private(set) var store: Store?
	private(set) var ledger = Ledger()

	var selection: SidebarSelection?
	var filter = TransactionFilter()
	var period: PeriodChoice = .all {
		didSet {
			filter.period = period.range()
			if !choosingBar { chartRange = filter.period }
		}
	}
	/// The period of the charts. A click on a bar narrows the list to that bar and keeps this, so
	/// the other bars stay and the user can click the next one. Every other choice sets both.
	private(set) var chartRange = DayRange.all
	private var choosingBar = false

	/// A period from the period menu: it sets the list and the charts, also when the list already
	/// shows it after a click on a bar.
	func choose(period: PeriodChoice) {
		self.period = period
		chartRange = filter.period
	}

	/// Shows the transactions of a clicked bar in the list.
	func select(bar period: PeriodChoice) {
		choosingBar = true
		self.period = period
		choosingBar = false
	}
	var keepFilters = false
	var viewMode: ViewMode = ViewMode(rawValue: UserDefaults.standard.string(forKey: Preference.viewMode) ?? "") ?? .barChart {
		didSet { UserDefaults.standard.set(viewMode.rawValue, forKey: Preference.viewMode) }
	}
	var balanceMode: BalanceMode = BalanceMode(rawValue: UserDefaults.standard.string(forKey: Preference.balanceMode) ?? "") ?? .daily {
		didSet { UserDefaults.standard.set(balanceMode.rawValue, forKey: Preference.balanceMode) }
	}
	var chartPeriod: ChartPeriod = .month
	var selectedTransactions = Set<UUID>()

	/// A message for an alert.
	var alert: AlertMessage?
	var sheet: SheetKind?
	var settingsTab = SettingsTab.security
	/// Changes when many transactions change at once, so that the transaction table starts over
	/// instead of inserting thousands of rows one by one. See `TransactionTable`.
	private(set) var tableGeneration = 0
	/// Column widths and order of the transaction table. They live here, so a new table keeps them.
	var transactionColumns = TableColumnCustomization<Transaction>()

	private var lastActivity = Date()
	private var eventMonitor: Any?
	private var idleTimer: Timer?

	init() {
		Preference.registerDefaults()
		// A closure that captures `self` can be handed over only once every stored property is set.
		sync.deliver = { [weak self] accountID, result in try self?.merge(.refresh(result), into: accountID) }
		start()
		installActivityMonitor()
	}

	// MARK: Opening and locking

	func start() {
		do {
			switch try vault.state() {
			case .empty:
				phase = .firstLaunch
			case .randomKey:
				do {
					hasPassword = false
					try open(try vault.openWithRandomKey())
				} catch Vault.Failure.incorrectPassword {
					// Setting the first password stopped after the key had changed. The password opens it.
					hasPassword = true
					phase = .locked
				}
			case .password:
				hasPassword = true
				if UserDefaults.standard.bool(forKey: Preference.unlockAutomatically), let pw = vault.storedPassword(), let s = try? vault.open(password: pw) {
					try open(s)
				} else {
					phase = .locked
				}
			}
		} catch {
			phase = .failed(String(describing: error))
		}
	}

	func createDatabase(password: String?) {
		do {
			let store = try vault.create(password: password, starterCategories: StarterCategories.make())
			hasPassword = password != nil
			try open(store)
		} catch {
			phase = .failed(String(describing: error))
		}
	}

	/// Returns false for a wrong password.
	@discardableResult
	func unlock(password: String) -> Bool {
		do {
			try open(try vault.open(password: password))
			return true
		} catch Vault.Failure.incorrectPassword {
			return false
		} catch {
			phase = .failed(String(describing: error))
			return true
		}
	}

	/// The unlock methods whose setting is on. They need the database password in the Keychain.
	var unlockMethods: [UnlockMethod] {
		guard hasPassword, vault.storedPassword() != nil else { return [] }
		return UnlockMethod.allCases.filter { UserDefaults.standard.bool(forKey: $0.preference) }
	}

	func unlock(with methods: [UnlockMethod]) {
		UnlockMethod.authenticate(methods) { ok in
			Task { @MainActor in
				guard ok, let pw = self.vault.storedPassword() else { return }
				self.unlock(password: pw)
			}
		}
	}

	private func open(_ store: Store) throws {
		self.store = store
		ledger = try store.loadLedger()
		if selection == nil {
			if let first = ledger.childGroups(of: nil).first {
				selection = .group(first.id)
			} else if let a = ledger.accounts(inGroup: nil).first {
				selection = .account(a.id)
			}
		}
		lastActivity = Date()
		phase = .unlocked
	}

	func lock() {
		guard hasPassword, phase == .unlocked else { return }
		// A locked app refreshes nothing and forgets the PINs that were not saved.
		sync.cancelAll()
		sync.broker.forgetPINs()
		try? store?.close()
		store = nil
		ledger = Ledger()
		sheet = nil
		selectedTransactions = []
		phase = .locked
	}

	func setPassword(_ password: String) {
		guard let store else { return }
		do {
			try vault.setPassword(password, on: store)
			hasPassword = true
			alert = AlertMessage(title: "The password has been changed.", message: "From now on, the database password opens Moneten.")
		} catch {
			alert = AlertMessage(title: "Could not change password of database.", message: String(describing: error))
		}
	}

	func changePassword(current: String, new: String) -> String? {
		guard let store else { return nil }
		do {
			try vault.changePassword(current: current, new: new, on: store)
			return nil
		} catch Vault.Failure.incorrectPassword {
			return "Incorrect password!"
		} catch {
			return "Could not change password of database. \(error)"
		}
	}

	// MARK: Inactivity

	private func installActivityMonitor() {
		eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .leftMouseDown, .rightMouseDown, .scrollWheel, .mouseMoved]) { [weak self] event in
			MainActor.assumeIsolated { self?.lastActivity = Date() }
			return event
		}
		idleTimer = Timer.scheduledTimer(withTimeInterval: 20, repeats: true) { [weak self] _ in
			MainActor.assumeIsolated { self?.checkIdle() }
		}
		NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
			MainActor.assumeIsolated { self?.checkIdle() }
		}
	}

	private func checkIdle() {
		let d = UserDefaults.standard
		guard phase == .unlocked, d.bool(forKey: Preference.lockAfterEnabled) else { return }
		let stored = d.integer(forKey: Preference.lockAfterMinutes)
		let minutes = max(1, stored == 0 ? Preference.defaultLockAfterMinutes : stored)
		if Date().timeIntervalSince(lastActivity) >= Double(minutes) * 60 { lock() }
	}

	func mainWindowClosed() {
		if UserDefaults.standard.bool(forKey: Preference.lockOnClose) { lock() }
	}

	// MARK: Selection and filters

	func select(_ s: SidebarSelection?) {
		guard s != selection else { return }
		selection = s
		selectedTransactions = []
		if !keepFilters {
			let p = filter.period
			let search = filter.searchText
			filter = TransactionFilter()
			filter.period = p
			filter.searchText = search
		}
		// Changing rows while the list handles the selection change upsets the table view.
		DispatchQueue.main.async { [weak self] in self?.markSeen() }
	}

	var visibleTransactions: [Transaction] {
		guard let selection else { return [] }
		return ledger.transactions(in: selection.scope, filter: filter)
	}

	/// The transactions of the bar charts: the filters of the list, but over the period of the charts.
	var chartTransactions: [Transaction] {
		guard let selection else { return [] }
		var f = filter
		f.period = chartRange
		return ledger.transactions(in: selection.scope, filter: f)
	}

	/// New transactions count as seen when the user opens their account.
	private func markSeen() {
		guard case let .account(id) = selection, let store else { return }
		var seen = ledger.transactions(ofAccount: id).filter(\.isNew)
		guard !seen.isEmpty, (try? store.markSeen(account: id)) != nil else { return }
		for i in seen.indices { seen[i].isNew = false }
		ledger.update(seen)
	}

	var title: String {
		switch selection {
		case let .account(id): ledger.account(id)?.name ?? ""
		case let .group(id): ledger.group(id)?.name ?? ""
		case let .category(id): ledger.categoryPath(id)
		case nil: "Moneten"
		}
	}

	// MARK: Changing transactions

	private func commit(_ changed: [Transaction]) {
		guard let store, !changed.isEmpty else { return }
		do {
			try store.save(changed)
			ledger.update(changed)
		} catch {
			alert = AlertMessage(title: "Could not save the change.", message: String(describing: error))
		}
	}

	func assign(category: UUID?, to ids: Set<UUID>) {
		let target = category == ledger.defaultCategory?.id ? nil : category
		let changed = ids.compactMap { ledger.transaction($0) }.map { t -> Transaction in
			var t = t
			t.categoryID = target
			t.categorizedBy = target == nil ? .none : .manual
			return t
		}
		commit(changed)
	}

	/// Checking a row also clears its new mark and its review mark.
	func setChecked(_ checked: Bool, for ids: Set<UUID>) {
		let rows = ids.compactMap { ledger.transaction($0) }
		if checked {
			commit(rows.filter(Self.needsCheck).map { var t = $0; t.markChecked(); return t })
		} else {
			commit(rows.filter(\.isChecked).map { var t = $0; t.isChecked = false; return t })
		}
	}

	/// A row that checking changes. A checked row can still carry a review mark that a later merge set.
	private static func needsCheck(_ t: Transaction) -> Bool { !t.isChecked || t.isNew || t.needsReview }

	func toggleChecked(_ id: UUID) {
		guard let t = ledger.transaction(id) else { return }
		setChecked(!t.isChecked, for: [id])
	}

	/// "Mark All Transactions as Checked": the transactions of the view that are unchecked, new, or
	/// marked for review, after the user confirms how many in how many accounts.
	func markAllChecked() {
		let unchecked = visibleTransactions.filter(Self.needsCheck)
		guard !unchecked.isEmpty else { return }
		let accounts = Set(unchecked.map(\.accountID)).count
		let alert = NSAlert()
		alert.messageText = "Mark all transactions as checked?"
		alert.informativeText = "A total of \(unchecked.count) \(unchecked.count == 1 ? "transaction" : "transactions") in \(accounts) \(accounts == 1 ? "account" : "accounts") will be marked as checked."
		alert.addButton(withTitle: "Mark as Checked")
		alert.addButton(withTitle: "Cancel")
		if alert.runModal() == .alertFirstButtonReturn { setChecked(true, for: Set(unchecked.map(\.id))) }
	}

	func setComment(_ comment: String, for ids: Set<UUID>) {
		let value = comment.trimmingCharacters(in: .whitespacesAndNewlines)
		commit(ids.compactMap { ledger.transaction($0) }.map { var t = $0; t.comment = value.isEmpty ? nil : value; return t })
	}

	func save(transaction t: Transaction) {
		var t = t
		if t.categoryID == nil, t.categorizedBy != .manual {
			var ledgerWithNew = ledger
			ledgerWithNew.update([t])
			Categorizer(ledger: ledgerWithNew).categorize(&t)
		}
		commit([t])
	}

	func delete(transactions ids: Set<UUID>) {
		guard let store else { return }
		do {
			try store.deleteTransactions(Array(ids))
			ledger.remove(transactionIDs: ids)
			selectedTransactions.subtract(ids)
		} catch {
			alert = AlertMessage(title: "Could not delete the transactions.", message: String(describing: error))
		}
	}

	// MARK: Accounts and groups

	func save(account: Account) {
		guard let store else { return }
		do {
			try store.save(account)
			ledger.upsert(account)
			if let value = account.portfolioValue() { ledger.record(value) }
			ledger.replace()
		} catch {
			alert = AlertMessage(title: "Could not save the account.", message: String(describing: error))
		}
	}

	func addOfflineAccount(name: String, kind: AccountKind, currency: String, groupID: UUID?) {
		let position = ledger.nextTreePosition(in: groupID)
		let a = Account(groupID: groupID, position: position, name: name, kind: kind, source: .offline, currency: currency)
		save(account: a)
		selection = .account(a.id)
	}

	func addGroup(name: String) {
		guard let store else { return }
		let g = AccountGroup(name: name, position: ledger.nextTreePosition(in: nil))
		do {
			try store.save(g)
			ledger.upsert(g)
			selection = .group(g.id)
		} catch {
			alert = AlertMessage(title: "Could not save the account group.", message: String(describing: error))
		}
	}

	func save(group: AccountGroup) {
		guard let store else { return }
		try? store.save(group)
		ledger.upsert(group)
	}

	func move(account id: UUID, toGroup groupID: UUID?) {
		guard var a = ledger.account(id), a.groupID != groupID else { return }
		a.groupID = groupID
		a.position = ledger.nextTreePosition(in: groupID)
		save(account: a)
	}

	func remove(account id: UUID) {
		guard let store else { return }
		do {
			try store.deleteAccount(id)
			ledger.replace(accounts: ledger.accounts.filter { $0.id != id }, transactions: ledger.transactions.filter { $0.accountID != id })
			if selection == .account(id) { selection = nil }
		} catch {
			alert = AlertMessage(title: "Could not remove the account.", message: String(describing: error))
		}
	}

	func remove(group id: UUID) {
		guard let store else { return }
		do {
			try store.deleteGroup(id)
			let groups = ledger.groups.filter { $0.id != id }.map { g -> AccountGroup in var g = g; if g.parentID == id { g.parentID = nil }; return g }
			let accounts = ledger.accounts.map { a -> Account in var a = a; if a.groupID == id { a.groupID = nil }; return a }
			ledger.replace(groups: groups, accounts: accounts)
			if selection == .group(id) { selection = nil }
		} catch {
			alert = AlertMessage(title: "Could not remove the account group.", message: String(describing: error))
		}
	}

	// MARK: Categories

	func addCategory(name: String, isGroup: Bool, parentID: UUID?, assigning ids: Set<UUID> = []) {
		let position = (ledger.childCategories(of: parentID).map(\.position).max() ?? -1) + 1
		let c = Domain.Category(parentID: parentID, position: position, name: name, isGroup: isGroup)
		save(category: c)
		if !ids.isEmpty, ledger.category(c.id) != nil { assign(category: c.id, to: ids) }
		selection = .category(c.id)
	}

	func save(category: Domain.Category) {
		guard let store else { return }
		do {
			try store.save(category)
			ledger.upsert(category)
			ledger.replace()
		} catch {
			alert = AlertMessage(title: "Could not save the category.", message: String(describing: error))
		}
	}

	func remove(category id: UUID) {
		guard let store, let c = ledger.category(id), !c.isDefault else { return }
		do {
			try store.deleteCategory(id)
			let removed = ledger.categoryIDs(inTree: id)
			let transactions = ledger.transactions.map { t -> Transaction in
				var t = t
				if let c = t.categoryID, removed.contains(c) { t.categoryID = nil; t.categorizedBy = .none }
				return t
			}
			ledger.replace(categories: ledger.categories.filter { !removed.contains($0.id) }, transactions: transactions)
			if case let .category(sel) = selection, removed.contains(sel) { selection = nil }
		} catch {
			alert = AlertMessage(title: "Could not remove the category.", message: String(describing: error))
		}
	}

	func apply(rule: Rule, of category: Domain.Category, mode: RuleApplication) async {
		let ledger = self.ledger
		let changed = await Task.detached(priority: .userInitiated) {
			RuleApplier.apply(category: category, rule: rule, to: ledger.transactions, ledger: ledger, mode: mode)
		}.value
		commit(changed)
		tableGeneration += 1
		alert = AlertMessage(title: "Categorized transactions: \(changed.count)", message: "")
	}

	/// The transactions of a category tree, for the amount next to it in the sidebar.
	func sidebarAmount(of category: Domain.Category) -> Money? {
		let range: DayRange
		let today = Day.today()
		switch category.sidebarAmount {
		case .none: return nil
		case .totalSum: range = .all
		case .currentMonth: range = DayRange(start: today.firstOfMonth, end: nil)
		case .currentQuarter: range = DayRange(start: today.firstOfQuarter, end: nil)
		case .currentYear: range = DayRange(start: today.firstOfYear, end: nil)
		}
		var f = TransactionFilter()
		f.period = range
		let sum = ledger.transactions(in: .category(category.id), filter: f).filter { !$0.isPending }.reduce(Int64(0)) { $0 + $1.amountMinor }
		return sum == 0 ? nil : Money(minorUnits: sum, currency: category.currency)
	}

	// MARK: Migration

	func runMigration(plan: MoneyMoneyMigration.Plan) throws {
		guard let store else { return }
		let starters = replaceableStarterCategories
		try store.save(groups: plan.groups, accounts: plan.accounts + plan.updatedAccounts, categories: plan.categories + plan.updatedCategories,
			transactions: plan.transactions + plan.updatedTransactions)
		for c in starters { try? store.deleteCategory(c.id) }
		ledger = try store.loadLedger()
		tableGeneration += 1
		if case let .category(id) = selection, ledger.category(id) == nil { selection = nil }
		if selection == nil, let g = ledger.childGroups(of: nil).first { selection = .group(g.id) }
	}

	/// The ledger that a migration plan is built against. While the database has no transactions, it
	/// leaves out the starter categories, which the migration replaces with the categories of MoneyMoney.
	var ledgerForMigration: Ledger {
		let removed = Set(replaceableStarterCategories.flatMap { ledger.categoryIDs(inTree: $0.id) })
		var l = ledger
		l.replace(categories: ledger.categories.filter { !removed.contains($0.id) })
		return l
	}

	/// Root starter categories that the user has not changed: the same name, rule, and kind, no color
	/// or icon of the user, and only unchanged starter subcategories below. A changed or extended tree stays.
	private var replaceableStarterCategories: [Domain.Category] {
		guard ledger.transactions.isEmpty else { return [] }
		let template = StarterCategories.make()
		func same(_ a: Domain.Category, _ b: Domain.Category) -> Bool {
			a.name == b.name && a.isGroup == b.isGroup && a.rule == b.rule && a.sourceID == nil && !a.isDefault
				&& a.color == b.color && a.symbol == b.symbol
		}
		return ledger.categories.filter { root in
			guard root.parentID == nil, let starter = template.first(where: { $0.parentID == nil && same(root, $0) }) else { return false }
			let starterChildren = template.filter { $0.parentID == starter.id }
			return ledger.categoryIDs(inTree: root.id).subtracting([root.id]).allSatisfy { id in
				guard let c = ledger.category(id), c.parentID == root.id else { return false }
				return starterChildren.contains { same(c, $0) }
			}
		}
	}

	/// The one way that fetched or imported transactions reach the history.
	@discardableResult
	func merge(_ delivery: Delivery, into accountID: UUID) throws -> Reconciliation {
		guard let store else { return Reconciliation() }
		let result = try store.merge(delivery, into: accountID)
		ledger.apply(result)
		if !result.added.isEmpty || !result.dropped.isEmpty { tableGeneration += 1 }
		return result
	}
}

struct AlertMessage: Identifiable {
	let id = UUID()
	var title: String
	var message: String
}

enum SheetKind: Identifiable, Equatable {
	case newAccount
	case newGroup
	/// `assigning` are the transactions that "Add category" in "Assign Category" moves into it.
	case newCategory(isGroup: Bool, assigning: Set<UUID> = [])
	case accountSettings(UUID)
	case groupSettings(UUID)
	case categorySettings(UUID)
	case transaction(UUID?)
	case comment(Set<UUID>)
	case migration
	case setPassword
	case changePassword

	var id: String { String(describing: self) }
}

enum StarterCategories {
	static func make() -> [Domain.Category] {
		var result: [Domain.Category] = []
		var position = 0
		func group(_ name: String, _ children: [String], rule: [String: String] = [:], showInDiagrams: Bool = true) {
			let g = Domain.Category(position: position, name: name, isGroup: true, showInDiagrams: showInDiagrams)
			position += 1
			result.append(g)
			for (i, c) in children.enumerated() {
				result.append(Domain.Category(parentID: g.id, position: i, name: c, showInDiagrams: showInDiagrams, rule: rule[c] ?? ""))
			}
		}
		group("Income", ["Salary", "Other income"], rule: ["Salary": #""Gehalt" OR "Lohn""#])
		group("Living", ["Rent", "Groceries", "Electricity", "Internet & Phone"])
		group("Mobility", ["Fuel", "Public transport", "Car"])
		group("Leisure", ["Restaurants", "Travel", "Hobbies"])
		group("Insurance", ["Health", "Liability", "Car insurance"])
		result.append(Domain.Category(position: position, name: "Transfers", showInDiagrams: false))
		result.append(Domain.Category(position: 1_000, name: "Uncategorized", isDefault: true))
		return result
	}
}
