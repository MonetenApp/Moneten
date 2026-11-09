import AppKit
import Domain
import Foundation
import Import
import LocalAuthentication
import Observation
import Storage

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
	static let lockAfterMinutes = "lockAfterMinutes"
	static let lockAfterEnabled = "lockAfterInactivity"
	static let unlockAutomatically = "unlockAutomatically"
	static let unlockWithTouchID = "unlockWithTouchID"
	static let viewMode = "viewMode"
	static let balanceMode = "balanceMode"
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
	private(set) var phase: Phase = .starting
	private(set) var hasPassword = false
	private(set) var store: Store?
	private(set) var ledger = Ledger()

	var selection: SidebarSelection?
	var filter = TransactionFilter()
	var period: PeriodChoice = .all { didSet { filter.period = period.range() } }
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

	private var lastActivity = Date()
	private var eventMonitor: Any?
	private var idleTimer: Timer?

	init() {
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
				hasPassword = false
				try open(try vault.openWithRandomKey())
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

	var touchIDEnabled: Bool { hasPassword && UserDefaults.standard.bool(forKey: Preference.unlockWithTouchID) && vault.storedPassword() != nil }

	func unlockWithTouchID() {
		let context = LAContext()
		var error: NSError?
		guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometricsOrCompanion, error: &error) else { return }
		context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometricsOrCompanion, localizedReason: "open the MonetenMoneten database") { ok, _ in
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
			alert = AlertMessage(title: "The password has been changed.", message: "From now on, the database password opens MonetenMoneten.")
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
		let minutes = max(1, d.integer(forKey: Preference.lockAfterMinutes) == 0 ? 5 : d.integer(forKey: Preference.lockAfterMinutes))
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

	/// New transactions count as seen when the user opens their account.
	private func markSeen() {
		guard case let .account(id) = selection, let store else { return }
		var seen = ledger.transactions(ofAccount: id).filter(\.isNew)
		guard !seen.isEmpty else { return }
		for i in seen.indices { seen[i].isNew = false }
		try? store.save(seen)
		ledger.update(seen)
	}

	var title: String {
		switch selection {
		case let .account(id): ledger.account(id)?.name ?? ""
		case let .group(id): ledger.group(id)?.name ?? ""
		case let .category(id): ledger.categoryPath(id)
		case nil: "MonetenMoneten"
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

	func setChecked(_ checked: Bool, for ids: Set<UUID>) {
		commit(ids.compactMap { ledger.transaction($0) }.filter { $0.isChecked != checked }.map { var t = $0; t.isChecked = checked; return t })
	}

	func toggleChecked(_ id: UUID) {
		guard let t = ledger.transaction(id) else { return }
		setChecked(!t.isChecked, for: [id])
	}

	func markAllChecked() {
		setChecked(true, for: Set(visibleTransactions.map(\.id)))
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
			ledger.replace()
		} catch {
			alert = AlertMessage(title: "Could not save the account.", message: String(describing: error))
		}
	}

	func addOfflineAccount(name: String, kind: AccountKind, currency: String, groupID: UUID?) {
		let position = (ledger.accounts(inGroup: groupID).map(\.position).max() ?? -1) + 1
		let a = Account(groupID: groupID, position: position, name: name, kind: kind, source: .offline, currency: currency)
		save(account: a)
		selection = .account(a.id)
	}

	func addGroup(name: String) {
		guard let store else { return }
		let g = AccountGroup(name: name, position: (ledger.childGroups(of: nil).map(\.position).max() ?? -1) + 1)
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
		a.position = (ledger.accounts(inGroup: groupID).map(\.position).max() ?? -1) + 1
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

	func addCategory(name: String, isGroup: Bool, parentID: UUID?) {
		let position = (ledger.childCategories(of: parentID).map(\.position).max() ?? -1) + 1
		let c = Domain.Category(parentID: parentID, position: position, name: name, isGroup: isGroup)
		save(category: c)
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
		try store.save(groups: plan.groups, accounts: plan.accounts, categories: plan.categories, transactions: plan.transactions)
		ledger = try store.loadLedger()
		if selection == nil, let g = ledger.childGroups(of: nil).first { selection = .group(g.id) }
	}

	/// Removes the starter categories while the database has no transactions, so that a
	/// migration brings in the categories of MoneyMoney without a second set beside them.
	func removeUnusedStarterCategories() {
		guard let store, ledger.transactions.isEmpty else { return }
		for c in ledger.categories where !c.isDefault && c.sourceID == nil && c.parentID == nil {
			try? store.deleteCategory(c.id)
		}
		ledger = (try? store.loadLedger()) ?? ledger
	}

	func importTransactions(_ imported: [Transaction], into account: Account) -> (added: Int, skipped: Int) {
		let rows = imported.map { t -> Transaction in var t = t; t.accountID = account.id; t.isNew = true; return t }
		var (added, skipped) = ImportMatching.split(imported: rows, existing: ledger.transactions(ofAccount: account.id))
		var ledgerWithNew = ledger
		ledgerWithNew.update(added)
		let categorizer = Categorizer(ledger: ledgerWithNew)
		for i in added.indices { categorizer.categorize(&added[i]) }
		commit(added)
		return (added.count, skipped)
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
	case newCategory(isGroup: Bool)
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
