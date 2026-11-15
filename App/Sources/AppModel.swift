import AppKit
import Domain
import ExtensionCatalog
import ExtensionConnector
import FinTS
import Foundation
import Import
import Network
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

/// Settings that the app needs before the database is open. Only `savedFilterBar` holds data of the user: the
/// dates of a custom period, the ends of an amount range, and the IDs of a category and an account.
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
	/// "Update extensions automatically" in the Extensions window, on unless the user turns it off.
	static let updateExtensionsAutomatically = "updateExtensionsAutomatically"
	/// "Show Moneten icon in menu bar", off unless the user turns it on.
	static let showMenuBarIcon = "showMenuBarIcon"
	/// The pin of the filter bar, and the `SavedFilterBar` it keeps for the next launch.
	static let pinFilterBar = "pinFilterBar"
	static let savedFilterBar = "savedFilterBar"

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
	let sync = SyncCoordinator(broker: SessionBroker(defaults: .standard, scope: DataFolder.standard().databaseFile.path))
	/// The FinTS connector of the setup and of every refresh.
	let fints = AppModel.makeFinTSConnector()
	/// The installed extensions and the catalog.
	let extensions = ExtensionLibrary()
	/// The connector of each extension that the debug harness loaded from a path, by the name of its package.
	/// An installed extension of the same name goes first.
	var extensionConnectors: [String: ExtensionConnector] = [:]
	/// What failed setups of extension services left for the next setup of the same service and login.
	/// It lives in memory until the lock.
	let extensionSetupStates = KeptSetupStates()
	/// The bank accesses, by ID. Their states stay in the database until a refresh reads them.
	private(set) var accesses: [UUID: Access] = [:]
	/// The "Add Account" assistant while its sheet is open.
	private(set) var setup: AccountSetup?
	private(set) var phase: Phase = .starting {
		didSet { if phase != oldValue { Trail.log("phase \(phase.trailName)") } }
	}
	private(set) var hasPassword = false
	private(set) var store: Store?
	private(set) var ledger = Ledger() {
		didSet {
			ledgerRevision += 1
			// While locked the ledger is empty, which says nothing about the notifications of the database.
			if store != nil { notices.update(newCounts: ledger.newTransactionCounts) }
			// The count of the last line, not `oldValue`: reading `oldValue` would copy the ledger on every change.
			let rows = ledger.transactions.count
			Trail.log("ledger \(ledgerChange) rows=\(rows) delta=\(rows - trailRows) accounts=\(ledger.accounts.count)")
			trailRows = rows
			ledgerChange = "edit"
			noteUndrawn(rows: true)
			// The ledger decides between positions and transactions, for example when the last transaction of a
			// portfolio goes. That changes the table like a click, one drawing after the rows.
			if selectedPortfolios != tableKey.portfolios { tableChanged() }
		}
	}
	/// The kind of the next change of `ledger`, for the trail.
	@ObservationIgnored var ledgerChange = "edit"
	@ObservationIgnored private var ledgerRevision = 0
	var exportTask: Task<Void, Never>?
	var isTransferringTransactions: Bool { fileImport != nil || exportTask != nil }
	@ObservationIgnored private var trailRows = 0
	/// "Automatically refresh accounts" and the notification settings of the "General" tab.
	let refreshSettings = RefreshSettings(defaults: .standard)
	let autoRefresh: AutoRefresh
	let notices = Notices()
	private let announcer: NewTransactionsAnnouncer
	/// A failure of an automatic refresh, which the status line shows until the user opens it. An
	/// automatic refresh opens no alert.
	var backgroundProblem: AlertMessage?
	private let pathMonitor = NWPathMonitor()
	private var refreshTimer: Timer?
	/// The accounts of a notification that the user clicked while the app was locked, selected after the unlock.
	private var notifiedAccounts: [UUID]?
	/// When the user canceled the refresh of each account, so that the automatic refresh does not start it again at once.
	private var canceledRefreshes: [UUID: Date] = [:]
	/// Opens the main window, also when it is closed. The window sets it, because only a view can open a scene.
	@ObservationIgnored var openMainWindow: () -> Void = {}
	/// The notices of the banks for the window "Notice". The lock drops them.
	var bankNotices = BankNotices()
	/// Opens the window "Notice", or brings it forward. The main window sets it, as `openMainWindow`.
	@ObservationIgnored var openNoticeWindow: () -> Void = {}
	/// What the account view says about the history at the bank, by account, from the refreshes while the
	/// app runs ("Say when the bank has no older transactions", "Use only what the bank allows").
	var bankHistories: [UUID: BankHistory] = [:]

	var selection: SidebarSelection? {
		didSet {
			guard selection != oldValue else { return }
			// The selected rows go in a drawing of their own, and the table of the new view follows one drawing
			// later: SwiftUI stopped the app in AttributeGraph when a table saw a change of its selection in the
			// drawing that removed it (issue #135). Every view change clears them, so that no hidden row stays
			// selected for "Add Comment...". Setting an empty selection again would notify its readers too.
			if !selectedTransactions.isEmpty { selectedTransactions = [] }
			// After the selected rows, so that the new filter waits for their drawing like the new view.
			if let selection { filter.resetHidden(in: selection.scope) }
			tableChanged()
		}
	}
	var filter = TransactionFilter() {
		didSet {
			guard filter != oldValue else { return }
			tableChanged()
			saveFilterBar()
		}
	}
	/// The view and the filters that the transaction table shows, its identity. They follow `selection` and
	/// `filter`, one drawing late when a change of the ledger is not drawn yet: a new table must not come in
	/// the drawing that changes the rows (issue #151). The rows of the old table stay as they are meanwhile,
	/// because new rows in place would remove shown rows, and the search field changes at once.
	private(set) var tableKey = TableKey()
	@ObservationIgnored private var tableKeyWaits = false
	/// A change that the cells of the open table read (the ledger or the selected rows), or a change of the
	/// identity of the table, that SwiftUI has not drawn yet. The two must not meet in one drawing (issues
	/// #135, #151), so each one waits until the other is drawn.
	@ObservationIgnored private var rowsUndrawn = false
	@ObservationIgnored private var tableUndrawn = false
	@ObservationIgnored private var watchesDrawing = false
	/// Counts the drawings that changes wait for. `DrawProbe` in the transaction view reads it and reports
	/// the number it saw once SwiftUI has updated that view.
	private(set) var drawRequest = 0
	@ObservationIgnored private var requestCount = 0
	/// Each work waits for the number that its call of `afterDraw` set, so a drawing that came before the call
	/// never releases it, also when the call came from an action inside that update.
	@ObservationIgnored private var drawWaiters: [(request: Int, work: @MainActor () -> Void)] = []
	@ObservationIgnored private var drawProbes = 0
	var period: PeriodChoice = .all {
		didSet {
			filter.period = period.range()
			if !choosingBar { chartRange = filter.period }
			saveFilterBar()
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
	/// The pin of the filter bar. Turning it on saves the filter bar, and each later change saves it again.
	/// Turning it off sets every filter to "Show All" and clears the search.
	var isFilterBarPinned = UserDefaults.standard.bool(forKey: Preference.pinFilterBar) {
		didSet {
			guard isFilterBarPinned != oldValue else { return }
			UserDefaults.standard.set(isFilterBarPinned, forKey: Preference.pinFilterBar)
			if isFilterBarPinned {
				saveFilterBar()
			} else {
				UserDefaults.standard.removeObject(forKey: Preference.savedFilterBar)
				savedBar = nil
				choose(period: .all)
				filter = TransactionFilter()
			}
		}
	}

	/// What `saveFilterBar` last wrote, so that typing a search or a change of the period, which also changes
	/// `filter.period`, writes nothing new.
	@ObservationIgnored private var savedBar: SavedFilterBar?

	private func saveFilterBar() {
		guard isFilterBarPinned else { return }
		let bar = SavedFilterBar(period: period, filter: filter)
		guard bar != savedBar else { return }
		savedBar = bar
		UserDefaults.standard.set(bar.data, forKey: Preference.savedFilterBar)
	}

	/// Shows the saved filter bar of a pin that is on. The first view then resets the filter it does not show.
	private func restoreFilterBar() {
		guard isFilterBarPinned, let data = UserDefaults.standard.data(forKey: Preference.savedFilterBar),
			let saved = SavedFilterBar(data: data) else { return }
		choose(period: saved.period)
		filter = saved.filter(in: ledger)
	}
	var viewMode: ViewMode = ViewMode(rawValue: UserDefaults.standard.string(forKey: Preference.viewMode) ?? "") ?? .barChart {
		didSet { UserDefaults.standard.set(viewMode.rawValue, forKey: Preference.viewMode) }
	}
	var balanceMode: BalanceMode = BalanceMode(rawValue: UserDefaults.standard.string(forKey: Preference.balanceMode) ?? "") ?? .daily {
		didSet { UserDefaults.standard.set(balanceMode.rawValue, forKey: Preference.balanceMode) }
	}
	var chartPeriod: ChartPeriod = .month
	/// The cells of the transaction table read the selection, so a change of it waits for a drawing before the
	/// table goes, like a change of the ledger (issue #135).
	var selectedTransactions = Set<UUID>() {
		didSet { noteUndrawn(rows: true) }
	}
	/// The number of selected rows of the table of positions, for the trail. The selection lives in that view.
	@ObservationIgnored var selectedPositions = 0

	/// How far `apply(rule:of:mode:)` has come, or nil when no rule is applied.
	private(set) var ruleProgress: (done: Int, total: Int)?
	/// Set for the whole run, so views that only ask whether a run is active do not redraw on each report.
	private(set) var isApplyingRule = false
	/// The run of `apply(rule:of:mode:)`, which a lock cancels.
	@ObservationIgnored private var ruleRun: Task<[Transaction], Never>?

	/// A message for an alert.
	var alert: AlertMessage? {
		didSet { if (alert == nil) != (oldValue == nil) { Trail.log(alert == nil ? "alert closed" : "alert shown") } }
	}
	/// The file import that runs. There is one at a time, and a lock cancels it.
	var fileImport: FileImport?
	@ObservationIgnored var importResult: NSAlert?
	var sheet: SheetKind? {
		didSet {
			guard sheet != oldValue else { return }
			Trail.log("sheet \(sheet?.trailName ?? "none")")
			// A menu command can open another sheet over the question or preview of an import, which then would wait
			// for an answer that never comes.
			if case let .fileImport(run) = oldValue, (run.question != nil || run.preview != nil) { run.cancel() }
		}
	}
	var settingsTab = SettingsTab.security
	/// The number of transaction tables that `replacingTable` started, for the trail.
	@ObservationIgnored private(set) var tableGeneration = 0
	/// The changes of `replacingTable` that wait for their new table. While there is one, a placeholder
	/// stands in for the transaction table.
	private(set) var tableHolds = 0
	/// Column widths and order of the transaction table. They live here, so a new table keeps them.
	var transactionColumns = TableColumnCustomization<Transaction>()

	private var lastActivity = Date()
	private var eventMonitor: Any?
	private var idleTimer: Timer?

	init() {
		Preference.registerDefaults()
		autoRefresh = AutoRefresh(settings: refreshSettings, now: Self.refreshClock)
		announcer = NewTransactionsAnnouncer(settings: refreshSettings, center: notices)
		// A closure that captures `self` can be handed over only once every stored property is set.
		sync.deliver = { [weak self] accountID, result in
			guard let self else { return }
			self.announcer.stored(try await self.mergeRefresh(result, into: accountID).added)
			if let kind = self.ledger.account(accountID)?.kind {
				self.bankHistories[accountID] = result.bankHistory(after: self.bankHistories[accountID], of: kind)
			}
		}
		sync.ended = { [weak self] access, state, accounts, attended in
			let failed = accounts.values.filter { if case .failed = $0 { true } else { false } }.count
			guard let self else { return }
			Trail.log("refresh end access=\(self.trailNumber(of: access)) accounts=\(accounts.count) failed=\(failed)")
			// The times and errors change the accounts in the ledger, which must not meet a new view in one drawing.
			if self.tableUndrawn {
				Task {
					while self.tableUndrawn { await self.drawn() }
					self.recordRefresh(of: access, state: state, accounts: accounts, attended: attended)
				}
			} else {
				self.recordRefresh(of: access, state: state, accounts: accounts, attended: attended)
			}
			self.extensions.sessionEnded()
			if attended { self.showNotices() }
		}
		sync.noticed = { [weak self] access, messages in
			guard let self, let bank = self.accesses[access]?.bankName else { return }
			self.bankNotices.add(messages, from: bank)
		}
		sync.runEnded = { [weak self] in
			guard let self else { return }
			self.announcer.runEnded(ledger: self.ledger)
		}
		sync.userCanceled = { [weak self] accounts in self?.recordCancel(of: accounts) }
		sync.mayStartUnattended = { [weak self] in self?.autoRefresh.allowsUnattended ?? false }
		autoRefresh.run = { [weak self] now in self?.refreshDue(at: now) }
		notices.onOpen = { [weak self] accounts in self?.show(notified: accounts) }
		extensions.model = self
		sync.broker.onStoreFailure = { [weak self] failure in
			guard let self else { return }
			self.report(AlertMessage(title: failure.title, message: failure.message), attended: !self.sync.runsUnattended(failure.access))
		}
		start()
		installActivityMonitor()
		installRefreshTriggers()
		showDialogsInMainWindow()
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
			let store = try vault.create(password: password, starterCategories: StarterCategories.make(language: starterLanguage))
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
		let loaded = try store.loadLedger()
		ledgerChange = "load"
		ledger = loaded
		accesses = Dictionary(uniqueKeysWithValues: try store.accesses().map { ($0.id, $0) })
		// The saved PINs live only in the database, so a refresh after a restart or an unlock does not ask.
		try sync.broker.open(store)
		if selection == nil {
			restoreFilterBar()
			if let first = ledger.childGroups(of: nil).first {
				selection = .group(first.id)
			} else if let a = ledger.accounts(inGroup: nil).first {
				selection = .account(a.id)
			}
		}
		lastActivity = Date()
		phase = .unlocked
		extensions.open(store)
		announcer.unlock()
		if let notified = notifiedAccounts {
			notifiedAccounts = nil
			select(notified: notified)
		}
		autoRefresh.isUnlocked = true
	}

	func lock() {
		guard hasPassword, phase == .unlocked else { return }
		// A locked app refreshes nothing and forgets every PIN in memory. The saved ones come back from the database at the next unlock.
		// The announcer locks first, because the cancel below can end the run at once.
		announcer.lock(keeping: ledger)
		fileImport?.cancel()
		exportTask?.cancel()
		if let result = importResult { result.window.sheetParent?.endSheet(result.window) }
		autoRefresh.isUnlocked = false
		notices.clearBadge()
		sync.cancelAll()
		sync.broker.forgetPINs()
		extensionSetupStates.clear()
		setup?.cancel()
		setup = nil
		ruleRun?.cancel()
		extensions.close()
		try? store?.close()
		store = nil
		accesses = [:]
		bankNotices = BankNotices()
		bankHistories = [:]
		sheet = nil
		phase = .locked
		// The lock removes the transaction table in this drawing and empties its rows after it, so that the
		// table never goes in the drawing that changes its rows (issue #151).
		afterDraw { [weak self] in
			Task { @MainActor in
				guard let self, self.phase == .locked else { return }
				self.ledgerChange = "clear"
				self.ledger = Ledger()
				self.selectedTransactions = []
			}
		}
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

	/// Brings the window "Notice" forward when a notice came since it last did. The app calls it only when
	/// the user is there, at the end of a refresh that the user started and when the main window comes
	/// forward, because an automatic refresh opens no dialog ("An automatic refresh never asks the user").
	func showNotices() {
		if bankNotices.bringForward() { openNoticeWindow() }
	}

	// MARK: Selection and filters

	func select(_ s: SidebarSelection?) {
		guard s != selection else { return }
		Trail.log("view change from=\(tableKey.trailKind) selected=\(tableKey.portfolios == nil ? selectedTransactions.count : selectedPositions)")
		selection = s
		// The rows change after SwiftUI drew the new view: changing them while the list handles the
		// selection change upsets the table view.
		afterDraw { [weak self] in Task { @MainActor in self?.markSeen() } }
	}

	/// True while the tables show `key`, its view is still the chosen one, and no placeholder is about to take
	/// their place. A table that SwiftUI removes in its next update can still report a click, and a change of
	/// its selection would reach it in the update that removes it (issue #135), or stay selected, hidden, in the
	/// next view. So the tables keep a selection only while this holds. It reads without observing, because a
	/// table asks inside an update of SwiftUI.
	func shows(_ key: TableKey) -> Bool { _tableKey == key && _selection == key.selection && _tableHolds == 0 }

	/// A selection that the transaction table of `key` reports.
	func select(transactions ids: Set<UUID>, in key: TableKey) {
		if shows(key) { selectedTransactions = ids }
	}

	/// The rows of the transaction table, for the view and the filters of `tableKey`.
	var visibleTransactions: [Transaction] { rows(for: tableKey).rows }

	/// The selected rows that the table shows. A search keeps the selection of the rows that it hides.
	/// It filters the rows, so a menu reads it in its action and not in its `disabled` check.
	var visibleSelection: Set<UUID> { selectedTransactions.intersection(visibleTransactions.map(\.id)) }

	/// The rows of a transaction table with the view and the filters of `key`.
	func rows(for key: TableKey) -> TransactionSearchResult {
		guard let selection = key.selection else { return TransactionSearchResult(rows: [], gaveUp: false) }
		return ledger.rows(in: selection.scope, filter: key.filter)
	}

	/// The transactions of the bar charts: the filters of the list, but over the period of the charts.
	var chartTransactions: [Transaction] {
		guard let selection else { return [] }
		var f = filter
		f.period = chartRange
		return ledger.rows(in: selection.scope, filter: f).rows
	}

	/// New transactions count as seen when the user opens their account.
	private func markSeen() {
		// The rows wait until SwiftUI drew a new table.
		if tableUndrawn {
			afterDraw { [weak self] in Task { @MainActor in self?.markSeen() } }
			return
		}
		guard case let .account(id) = selection, let store else { return }
		var seen = ledger.transactions(ofAccount: id).filter(\.isNew)
		guard !seen.isEmpty, (try? store.markSeen(account: id)) != nil else { return }
		for i in seen.indices { seen[i].isNew = false }
		ledgerChange = "seen"
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

	/// Saves the rows and returns whether they are saved. A locked app has no database and saves nothing.
	@discardableResult
	private func commit(_ changed: (transactions: [Transaction], parts: [SplitPart])) -> Bool {
		guard let store else { return false }
		guard !changed.transactions.isEmpty || !changed.parts.isEmpty else { return true }
		do {
			try store.save(changed.transactions, parts: changed.parts)
			ledgerChange = "commit rows=\(changed.transactions.count) parts=\(changed.parts.count)"
			ledger.update(changed.transactions, parts: changed.parts)
			return true
		} catch {
			alert = AlertMessage(title: "Could not save the change.", message: String(describing: error))
			return false
		}
	}

	/// What ⌘K does: the category picker for the selected rows on screen.
	func openCategoryPicker() {
		let ids = visibleSelection
		if !ids.isEmpty { sheet = .assignCategory(ids, accounts: ledger.accountIDs(ofTransactions: ids)) }
	}

	func assign(category: UUID?, to ids: Set<UUID>) {
		let target = category == ledger.defaultCategory?.id ? nil : category
		let changed = ids.compactMap { ledger.row($0) }.map { t -> Transaction in
			var t = t
			t.categoryID = target
			t.categorizedBy = target == nil ? .none : .manual
			return t
		}
		commit(ledger.changes(from: changed))
	}

	/// What a drag from this app carries: rows of the transaction list, or a category of the sidebar.
	enum Drag {
		case transactions(Set<UUID>)
		case category(UUID)
	}

	/// The drag in progress. SwiftUI hands the dragged data to a drop target only on the drop, so a category
	/// in the sidebar reads it here while the pointer is over it. A drop clears it, and the next drag replaces it.
	@ObservationIgnored private(set) var drag: Drag?

	func startDrag(of ids: Set<UUID>) -> DraggedTransactions {
		drag = .transactions(ids)
		return DraggedTransactions(ids: ids)
	}

	func startDrag(category id: UUID) -> DraggedCategory {
		drag = .category(id)
		return DraggedCategory(id: id)
	}

	func endDrag() { drag = nil }

	/// Whether the category row lights up for the drag in progress.
	func acceptsDrag(on category: Domain.Category) -> Bool {
		switch drag {
		case let .transactions(ids): canDrop(ids, on: category)
		case let .category(id): canDrop(category: id, on: category)
		case nil: false
		}
	}

	func canDrop(_ ids: Set<UUID>, on category: Domain.Category) -> Bool {
		let rows = ids.compactMap { ledger.row($0) }
		return !rows.isEmpty && ledger.canAssign(category, to: rows)
	}

	/// A drop of rows on a category in the sidebar. A group, or a category restricted to another account, refuses them.
	/// Like ⌘K and the context menu, the drop changes the table in place, also out of the open category view (issue #154).
	func drop(_ ids: Set<UUID>, on category: Domain.Category) {
		guard canDrop(ids, on: category) else { return }
		assign(category: category.id, to: ids)
	}

	/// A category dropped on a group goes to its end. `Ledger.move` refuses a category that is not a group,
	/// the group itself or one above it, and a drop that changes nothing.
	func canDrop(category id: UUID, on group: Domain.Category) -> Bool {
		!ledger.move(category: id, into: group.id, at: ledger.childCategories(of: group.id).count).isEmpty
	}

	func drop(category id: UUID, on group: Domain.Category) {
		move(category: id, into: group.id, at: ledger.childCategories(of: group.id).count)
	}

	/// Moves a category, or a group with everything in it, to the gap `index` among the children of `parent`.
	func move(category id: UUID, into parent: UUID?, at index: Int) {
		guard !ledger.move(category: id, into: parent, at: index).isEmpty else { return }
		if ledger.changesShownRows(moving: id, into: parent, roots: shownCategoryRoots) {
			Task { await replacingTable { moveNow(category: id, into: parent, at: index) } }
		} else {
			moveNow(category: id, into: parent, at: index)
		}
	}

	/// The categories whose trees the open table shows: the open category view and the category filter. Rows that
	/// come into or leave them in place remove shown rows (issue #135), so a move that does this comes with a new table.
	private var shownCategoryRoots: [UUID] {
		var roots = [tableKey.filter.categoryID]
		if case let .category(shown) = tableKey.selection { roots.append(shown) }
		return roots.compactMap { $0 }
	}

	private func moveNow(category id: UUID, into parent: UUID?, at index: Int) {
		let changed = ledger.move(category: id, into: parent, at: index)
		guard let store, !changed.isEmpty else { return }
		do {
			try store.save(categories: changed)
			var moved = ledger
			for c in changed { moved.upsert(c) }
			ledgerChange = "move categories=\(changed.count)"
			ledger = moved
		} catch {
			alert = AlertMessage(title: "Could not move the category.", message: String(describing: error))
		}
	}

	func setChecked(_ checked: Bool, for ids: Set<UUID>) {
		let rows = ids.compactMap { ledger.row($0) }
		if checked {
			commit(ledger.changes(from: rows.filter(\.changesWhenChecked).map { var t = $0; t.markChecked(); return t }))
		} else {
			commit(ledger.changes(from: rows.filter(\.isChecked).map { var t = $0; t.isChecked = false; return t }))
		}
	}

	func toggleChecked(_ id: UUID) {
		guard let t = ledger.row(id) else { return }
		setChecked(!t.isChecked, for: [id])
	}

	func markAllChecked() {
		let rows = visibleTransactions.compactMap { ledger.row($0.id) }.filter(\.changesWhenChecked)
		let changed = ledger.changes(from: rows.map { var t = $0; t.markChecked(); return t })
		let count = changed.transactions.count
		guard count > 0 else { return }
		let accounts = Set(rows.map(\.accountID)).count
		let alert = NSAlert()
		alert.messageText = "Mark all transactions as checked?"
		alert.informativeText = "A total of \(count) \(count == 1 ? "transaction" : "transactions") in \(accounts) \(accounts == 1 ? "account" : "accounts") will be marked as checked."
		alert.addButton(withTitle: "Mark as Checked")
		alert.addButton(withTitle: "Cancel")
		if alert.runModal() == .alertFirstButtonReturn { setChecked(true, for: Set(rows.map(\.id))) }
	}

	func setComment(_ comment: String, for ids: Set<UUID>) {
		let value = comment.trimmingCharacters(in: .whitespacesAndNewlines)
		commit(ledger.changes(from: ids.compactMap { ledger.row($0) }.map { var t = $0; t.comment = value.isEmpty ? nil : value; return t }))
	}

	func save(transaction t: Transaction) {
		var changed = ledger.changes(from: [t])
		let categorizer = Categorizer(ledger: ledger)
		for i in changed.transactions.indices where changed.transactions[i].categoryID == nil && changed.transactions[i].categorizedBy != .manual {
			categorizer.categorize(&changed.transactions[i])
		}
		commit(changed)
	}

	@discardableResult
	func replaceParts(of transactionID: UUID, with parts: [SplitPart]) async -> Bool {
		guard let store else { return false }
		return await replacingTable {
			guard self.store === store else { return false }
			do {
				try store.replaceParts(of: transactionID, with: parts)
				ledgerChange = "split parts=\(parts.count)"
				ledger.replaceParts(of: transactionID, with: parts)
				selectedTransactions = parts.isEmpty ? [transactionID] : Set(parts.map(\.id))
				return true
			} catch {
				alert = AlertMessage(title: "Could not split the transaction.", message: String(describing: error))
				return false
			}
		}
	}

	func delete(transactions ids: Set<UUID>) {
		guard let store else { return }
		do {
			try store.deleteTransactions(Array(ids))
			ledgerChange = "delete rows=\(ids.count)"
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

	/// Opens the "Add Account" assistant. The new accounts go into `group`.
	func addAccount(group: UUID? = nil) {
		setup?.cancel()
		setup = AccountSetup(model: self, groupID: group)
		sheet = .newAccount
	}

	/// Ends the assistant. A canceled setup leaves no access and no account.
	func closeAccountSetup() {
		setup?.cancel()
		setup = nil
		if sheet == .newAccount { sheet = nil }
	}

	/// Stores the access with the accounts that the user selected, keeps the PIN of the login in
	/// memory and saves it when the user asked to, selects the first new account, or the first connected
	/// one when none is new, and starts the first refresh ("Finish the setup"). A login that the app has
	/// already keeps its access. `listed` holds every account that the bank listed, and `notices` the notices
	/// of the bank that the assistant showed, which the window "Notice" then leaves out. Throws the error of
	/// the database, which the assistant shows.
	func add(_ new: Access, state: AccessState?, accounts candidates: [Account], listed: [Account], connecting: [UUID: UUID], notices: [BankMessage],
		pin: Secret, savePIN: Bool) throws {
		guard let store else { return }
		let (access, accounts) = try store.add(new, state: state, accounts: ledger.accountsToAdd(candidates, listed: listed, connecting: connecting))
		bankNotices.markShown(notices, from: access.bankName)
		let first = accounts.first { ledger.account($0.id) == nil } ?? accounts.first
		// The bank accepted the PIN at the login of the setup.
		do {
			try sync.broker.remember(pin, for: access.id, save: savePIN)
		} catch {
			alert = AlertMessage(title: "Could not save the PIN.", message: String(describing: error))
		}
		accesses[access.id] = access
		// The new accounts and the view of the first one come with a new transaction table.
		Task {
			await replacingTable {
				guard self.store != nil else { return }
				take(new: accounts)
				if let first { navigate(to: .account(first.id)) }
			}
			refresh(ledger.refreshAccounts(.all).filter { $0.key == access.id })
		}
	}

	/// Stores the access of an extension setup with the listed accounts that the app does not have yet.
	/// A login that the app has already keeps its access and its state. Without a new account nothing is
	/// stored, so that no access is left without accounts. Returns the stored accounts, which the caller
	/// takes into the ledger.
	func storeExtensionAccess(_ new: Access, state: AccessState, accounts listed: [Account]) throws -> [Account] {
		let added = ledger.accountsToAdd(listed, listed: listed)
		guard let store, !added.isEmpty else { return [] }
		let (access, accounts) = try store.add(new, state: state, accounts: added)
		accesses[access.id] = access
		return accounts
	}

	/// Takes the accounts of a new access, and the rows that its setup stored, into the ledger.
	func take(new accounts: [Account], merged: [Reconciliation] = []) {
		for a in accounts { ledger.upsert(a) }
		ledger.replace()
		for result in merged {
			ledgerChange = result.trailName("refresh")
			ledger.apply(result)
		}
	}

	func addOfflineAccount(name: String, kind: AccountKind, currency: String, groupID: UUID?) async {
		let position = ledger.nextTreePosition(in: groupID)
		let a = Account(groupID: groupID, position: position, name: name, kind: kind, source: .offline, currency: currency)
		await replacingTable {
			save(account: a)
			selection = .account(a.id)
		}
	}

	func addGroup(name: String) async {
		guard let store else { return }
		let g = AccountGroup(name: name, position: ledger.nextTreePosition(in: nil))
		do {
			try store.save(g)
			await replacingTable {
				ledger.upsert(g)
				selection = .group(g.id)
			}
		} catch {
			alert = AlertMessage(title: "Could not save the account group.", message: String(describing: error))
		}
	}

	func save(group: AccountGroup) {
		guard let store else { return }
		do {
			try store.save(group)
			ledger.upsert(group)
		} catch {
			alert = AlertMessage(title: "Could not save the account group.", message: String(describing: error))
		}
	}

	func move(account id: UUID, toGroup groupID: UUID?) {
		guard ledger.account(id).map({ $0.groupID != groupID }) == true else { return }
		// An account with rows that comes into or leaves the open group view inserts or removes all of them in
		// place, which removes shown rows (issue #135), so it comes with a new table.
		if case let .group(shown) = tableKey.selection, ledger.accountsWithTransactions.contains(id),
			ledger.accountIDs(inGroupTree: shown).contains(id) || isGroup(groupID, in: shown) {
			Task { await replacingTable { moveNow(account: id, toGroup: groupID) } }
		} else {
			moveNow(account: id, toGroup: groupID)
		}
	}

	/// Reads the account when the move happens, so that a refresh that stored it meanwhile keeps its balance,
	/// its time, and its kind, and changes only the group and the place in it.
	private func moveNow(account id: UUID, toGroup groupID: UUID?) {
		guard var a = ledger.account(id), a.groupID != groupID else { return }
		a.groupID = groupID
		a.position = ledger.nextTreePosition(in: groupID)
		save(account: a)
	}

	/// True when `group` is `tree` or a group below it.
	private func isGroup(_ group: UUID?, in tree: UUID) -> Bool {
		var next = group
		while let id = next {
			if id == tree { return true }
			next = ledger.group(id)?.parentID
		}
		return false
	}

	/// "Remove saved PIN": the next refresh of every account of the access asks for the PIN.
	func removeSavedPIN(of access: UUID) {
		do {
			try sync.broker.removeSavedPIN(of: access)
		} catch {
			alert = AlertMessage(title: "Could not remove the saved PIN.", message: String(describing: error))
		}
	}

	func remove(account id: UUID) async {
		guard let store else { return }
		do {
			if let access = try store.deleteAccount(id) {
				accesses[access] = nil
				sync.broker.forgetPIN(of: access)
			}
			await replacingTable {
				ledger.replace(accounts: ledger.accounts.filter { $0.id != id }, transactions: ledger.transactions.filter { $0.accountID != id })
				filter.dropMissing(in: ledger)
				if selection == .account(id) { selection = nil }
			}
		} catch {
			alert = AlertMessage(title: "Could not remove the account.", message: String(describing: error))
		}
	}

	func remove(group id: UUID) async {
		guard let store else { return }
		do {
			try store.deleteGroup(id)
			await replacingTable {
				let groups = ledger.groups.filter { $0.id != id }.map { g -> AccountGroup in var g = g; if g.parentID == id { g.parentID = nil }; return g }
				let accounts = ledger.accounts.map { a -> Account in var a = a; if a.groupID == id { a.groupID = nil }; return a }
				ledger.replace(groups: groups, accounts: accounts)
				if selection == .group(id) { selection = nil }
			}
		} catch {
			alert = AlertMessage(title: "Could not remove the account group.", message: String(describing: error))
		}
	}

	// MARK: Refresh

	/// The connector of the app, or in a debug build the fake helper that `MONETEN_FINTS_HELPER` names,
	/// so that the setup and the refresh run without a bank.
	private static func makeFinTSConnector() -> FinTSConnector {
		#if DEBUG
		if let path = ProcessInfo.processInfo.environment["MONETEN_FINTS_HELPER"], !path.isEmpty { return FinTSConnector(debugHelper: path) }
		#endif
		return FinTSConnector()
	}

	/// "Refresh All Accounts", "Refresh Account", and "Refresh Accounts", and with `enforced` the commands
	/// that ask the bank for the full history. Offline the accounts keep their last state, and the app says
	/// why nothing happens.
	func refresh(_ scope: RefreshScope, enforced: Bool = false) {
		guard autoRefresh.isOnline else {
			alert = AlertMessage(title: SyncFailure.offline.message, message: "Connect this Mac to the Internet and try again.")
			return
		}
		refresh(ledger.refreshAccounts(scope), enforced: enforced)
	}

	/// "Cancel Refresh". The lock cancels too, and then the accounts stay due for the unlock.
	func cancelRefresh() {
		recordCancel(of: sync.refreshingAccounts)
		sync.cancelAll()
	}

	/// The user canceled the refresh of these accounts, with "Cancel Refresh" or in a dialog.
	private func recordCancel(of accounts: Set<UUID>) {
		let now = Self.refreshClock()
		for id in accounts { canceledRefreshes[id] = now }
	}

	/// An alert for a command, and the note in the status line for an automatic refresh.
	private func report(_ message: AlertMessage, attended: Bool) {
		if attended { alert = message } else { backgroundProblem = message }
	}

	/// The automatic refresh: the due accounts, without any dialog.
	private func refreshDue(at now: Date) {
		let plan = ledger.dueAccounts(at: now, canceled: canceledRefreshes)
		guard !plan.isEmpty else { return }
		DebugHarness.shared?.log("autorefresh accesses=\(plan.count) accounts=\(plan.values.map(\.count).reduce(0, +))")
		refresh(plan, attended: false)
	}

	/// The clock of the automatic refresh. A debug build moves it ahead by `MONETEN_DEBUG_CLOCK_OFFSET`
	/// seconds, so that a check of the app sees an account become due within a minute.
	private static func refreshClock() -> Date {
		#if DEBUG
		if let offset = ProcessInfo.processInfo.environment["MONETEN_DEBUG_CLOCK_OFFSET"].flatMap(TimeInterval.init) { return Date() + offset }
		#endif
		return Date()
	}

	/// The timer of the automatic refresh, the sleep and the wake of the display, and the network.
	private func installRefreshTriggers() {
		refreshTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
			MainActor.assumeIsolated { self?.autoRefresh.tick() }
		}
		refreshTimer?.tolerance = 10
		autoRefresh.isUserPresent = CGDisplayIsAsleep(CGMainDisplayID()) == 0
		let workspace = NSWorkspace.shared.notificationCenter
		for (name, present) in [(NSWorkspace.screensDidSleepNotification, false), (NSWorkspace.willSleepNotification, false),
			(NSWorkspace.screensDidWakeNotification, true)] {
			workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
				MainActor.assumeIsolated { self?.autoRefresh.isUserPresent = present }
			}
		}
		pathMonitor.pathUpdateHandler = { [weak self] path in
			MainActor.assumeIsolated { self?.autoRefresh.isOnline = path.status == .satisfied }
		}
		pathMonitor.start(queue: .main)
	}

	/// The PIN sheet, the dialog "Two-Factor Authentication", and the alerts live in the main window. A
	/// refresh from the menu bar can ask or fail while that window is closed, so they bring the window back.
	/// `asking` tells whether the dialog of a refresh was open before, so that the trail logs each change once.
	private func showDialogsInMainWindow(asking: Bool = false) {
		withObservationTracking { _ = (sync.broker.current, alert) } onChange: { [weak self] in
			Task { @MainActor [weak self] in
				guard let self else { return }
				let asks = self.sync.broker.current != nil
				if asks != asking { Trail.log("dialog refresh \(asks ? "shown" : "closed")") }
				if asks || self.alert != nil {
					NSApp.activate()
					self.openMainWindow()
				}
				self.showDialogsInMainWindow(asking: asks)
			}
		}
	}

	/// A click on a notification: the main window with the first of its accounts, after the unlock when the app is locked.
	func show(notified accounts: [UUID]) {
		NSApp.activate()
		openMainWindow()
		if phase == .unlocked { select(notified: accounts) } else { notifiedAccounts = accounts }
	}

	private func select(notified accounts: [UUID]) {
		guard let first = ledger.accountsInSidebarOrder.first(where: { accounts.contains($0.id) }) else { return }
		navigate(to: .account(first.id))
	}

	func canRefresh(_ scope: RefreshScope) -> Bool {
		phase == .unlocked && !ledger.refreshAccounts(scope).isEmpty
	}

	/// Starts one refresh per access, with the state its connector returned last. Only a refresh that the
	/// user started shows an alert.
	func refresh(_ plan: [UUID: [AccountRequest]], attended: Bool = true, enforced: Bool = false) {
		guard let store else { return }
		let requests = plan.compactMap { id, accounts in accesses[id].map { ($0, accounts) } }.sorted { $0.0.bankName < $1.0.bankName }
		for (access, accounts) in requests {
			guard let connector = connector(for: access.source) else {
				if attended { alert = AlertMessage(title: "Could not refresh \(access.bankName).", message: "Moneten has no connector for this access yet.") }
				continue
			}
			do {
				sync.refresh(RefreshRequest(access: access, state: try store.state(of: access.id), accounts: accounts, enforced: enforced), with: connector,
					attended: attended)
				Trail.log("refresh start access=\(trailNumber(of: access.id)) accounts=\(accounts.count) attended=\(attended)")
			} catch {
				if attended { alert = AlertMessage(title: "Could not refresh \(access.bankName).", message: String(describing: error)) }
			}
		}
	}

	private func connector(for source: AccessSource) -> (any BankConnector)? {
		switch source {
		case .fints: fints
		case let .extension(id): extensions.connector(for: id) ?? extensionConnectors[id] ?? CheckedAtStart { throw SyncFailure.unsupported("The extension \(id) is not installed.") }
		case .finAPI: nil
		}
	}

	/// Stores how a refresh ended: the new state of the access, and the time or the error of each account.
	private func recordRefresh(of access: UUID, state: AccessState?, accounts results: [UUID: AccountRefresh], attended: Bool) {
		guard let store else { return }
		let accounts = results.compactMap { id, result in ledger.account(id).map { a -> Account in var a = a; a.record(result); return a } }
		guard state != nil || !accounts.isEmpty else { return }
		do {
			try store.recordRefresh(of: access, state: state, accounts: accounts)
			for a in accounts {
				ledgerChange = "account refreshed"
				ledger.upsert(a)
			}
		} catch {
			report(AlertMessage(title: "Could not save the result of the refresh.", message: String(describing: error)), attended: attended)
		}
	}

	/// The calibration that `account` proposes now. None while the refresh of its access runs or failed for it.
	func proposedCalibration(of account: Account) -> CalibrationProposal? {
		ledger.proposedCalibration(of: account, today: .today(), refresh: account.accessID.flatMap { sync.states[$0] } ?? .idle)
	}

	/// The step of the first running refresh, for the status line.
	var refreshStatus: String? {
		let running = sync.states.compactMap { id, state in state.isRunning ? (accesses[id]?.bankName ?? "the bank", state) : nil }.sorted { $0.0 < $1.0 }
		guard let (bank, state) = running.first else { return nil }
		switch state {
		case let .fetching(done, of): return "Getting transactions from \(bank) (\(min(done + 1, of)) of \(of))..."
		case .needsUser(_, waiting: true, _): return "\(bank) waits for your input..."
		case .needsUser: return "\(bank) needs your input..."
		default: return "Connecting to \(bank)..."
		}
	}

	// MARK: Categories

	func addCategory(name: String, isGroup: Bool, parentID: UUID?, assigning ids: Set<UUID> = []) async {
		let position = (ledger.childCategories(of: parentID).map(\.position).max() ?? -1) + 1
		let c = Domain.Category(parentID: parentID, position: position, name: name, isGroup: isGroup)
		await replacingTable {
			save(category: c)
			if !ids.isEmpty, ledger.category(c.id) != nil { assign(category: c.id, to: ids) }
			selection = .category(c.id)
		}
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

	func remove(category id: UUID) async {
		guard let store, let c = ledger.category(id), !c.isDefault else { return }
		do {
			let removed = ledger.categoryIDs(inTree: id)
			try store.deleteCategory(id)
			await replacingTable {
				ledger.remove(category: id)
				filter.dropMissing(in: ledger)
				if case let .category(sel) = selection, removed.contains(sel) { selection = nil }
			}
		} catch {
			alert = AlertMessage(title: "Could not remove the category.", message: String(describing: error))
		}
	}

	func apply(rule: Rule, of category: Domain.Category, mode: RuleApplication) async {
		guard ruleProgress == nil, let store else { return }
		let ledger = self.ledger
		let total = ledger.transactions.count
		ruleProgress = (0, total)
		isApplyingRule = true
		defer { ruleProgress = nil; ruleRun = nil; isApplyingRule = false }
		let (reports, reporter) = AsyncStream.makeStream(of: Int.self, bufferingPolicy: .bufferingNewest(1))
		let run = Task.detached(priority: .userInitiated) {
			defer { reporter.finish() }
			return RuleApplier.apply(category: category, rule: rule, to: ledger.transactions, ledger: ledger, mode: mode) { reporter.yield($0) }
		}
		ruleRun = run
		for await done in reports { ruleProgress = (done, total) }
		let changed = await run.value
		guard !run.isCancelled else { return }
		let saved = await replacingTable { () -> Int? in
			// A run saves only into the database it started with. A lock closes it, and an unlock opens a new one.
			guard self.store === store else { return nil }
			let rows = RuleApplier.rebase(changed, from: ledger, onto: self.ledger, category: category, rule: rule, mode: mode)
			return commit((transactions: rows, parts: [])) ? rows.count : nil
		}
		if let saved { alert = AlertMessage(title: "Categorized transactions: \(saved)", message: "") }
	}

	// MARK: Migration

	func runMigration(plan: MoneyMoneyMigration.Plan) async throws {
		guard let store else { return }
		let starters = replaceableStarterCategories
		try store.save(groups: plan.groups, accounts: plan.accounts + plan.updatedAccounts, categories: plan.categories + plan.updatedCategories,
			transactions: plan.transactions + plan.updatedTransactions, relinking: plan.relinkedDeletedRows)
		for c in starters { try? store.deleteCategory(c.id) }
		try await reloadAfterImport()
	}

	/// Loads the ledger and the bank accesses again after a migration or a complete import replaced the table, and
	/// selects the first group when the selection is gone.
	func reloadAfterImport() async throws {
		guard let store else { return }
		try await replacingTable {
			let loaded = try store.loadLedger()
			ledgerChange = "load"
			ledger = loaded
			accesses = Dictionary(uniqueKeysWithValues: try store.accesses().map { ($0.id, $0) })
			filter.dropMissing(in: ledger)
			if case let .category(id) = selection, ledger.category(id) == nil { selection = nil }
			// A complete import replaces the account groups.
			if case let .group(id) = selection, ledger.group(id) == nil { selection = nil }
			if selection == nil {
				selection = ledger.childGroups(of: nil).first.map { .group($0.id) } ?? ledger.accounts(inGroup: nil).first.map { .account($0.id) }
			}
		}
	}

	/// The ledger that a migration plan is built against. While the database has no transactions, it
	/// leaves out the starter categories, which the migration replaces with the categories of MoneyMoney.
	var ledgerForMigration: Ledger {
		let removed = Set(replaceableStarterCategories.flatMap { ledger.categoryIDs(inTree: $0.id) })
		// Replacing the categories builds the search text of every row again.
		guard !removed.isEmpty else { return ledger }
		var l = ledger
		l.replace(categories: ledger.categories.filter { !removed.contains($0.id) })
		return l
	}

	/// The deleted transactions that a migration plan keeps out.
	func deletedTransactions() throws -> [DeletedTransaction] {
		try store?.deletedTransactions() ?? []
	}

	/// The starter categories that a migration replaces, once the database holds no transactions.
	var replaceableStarterCategories: [Domain.Category] {
		ledger.transactions.isEmpty ? StarterCategories.unchangedRoots(in: ledger, language: starterLanguage) : []
	}

	/// The language of the interface, so that a new database and the migration agree on the starter set.
	private var starterLanguage: StarterCategories.Language {
		.init(localization: Bundle.main.preferredLocalizations.first)
	}

	/// Stores a delivery and takes it into the ledger. An import goes through `replacingTable`, because a
	/// file can bring thousands of rows; a refresh goes through `mergeRefresh`.
	@discardableResult
	func merge(_ delivery: Delivery, into accountID: UUID) throws -> Reconciliation {
		guard let store else { return Reconciliation() }
		let result = try store.merge(delivery, into: accountID)
		let kind = if case .file = delivery { "file" } else { "refresh" }
		ledgerChange = result.trailName(kind)
		ledger.apply(result)
		return result
	}

	func reloadFileImport(from store: Store) async throws {
		while self.store === store {
			let revision = ledgerRevision
			let updated = try await Task.detached(priority: .userInitiated) { try store.loadLedger() }.value
			guard self.store === store else { return }
			guard ledgerRevision == revision else { continue }
			ledgerChange = "file"
			ledger = updated
			return
		}
	}

	/// A refresh changes the rows of the open table in place, also a first refresh that brings the whole
	/// history (perf scenario "refresh-into-open-view"). When it can remove shown rows, pending rows or a sold
	/// position, the table starts over instead: removing shown rows in place stopped the app in
	/// AttributeGraph, while SwiftUI updated the row views that the table had just removed (issue #135).
	private func mergeRefresh(_ result: RefreshResult, into accountID: UUID) async throws -> Reconciliation {
		// A new view, for example of a click on the depot while the refresh runs, must not meet the new rows in
		// one drawing (issue #151): the rows wait until SwiftUI drew the view.
		if tableUndrawn { Trail.log("refresh waits for drawing") }
		while tableUndrawn { await drawn() }
		guard removesShownRows(result, of: accountID) else { return try merge(.refresh(result), into: accountID) }
		return try await replacingTable { try merge(.refresh(result), into: accountID) }
	}

	/// The open table shows pending rows of the account, which the bank can drop or book, or a position of
	/// the account that the delivered positions no longer hold.
	private func removesShownRows(_ result: RefreshResult, of accountID: UUID) -> Bool {
		if let portfolios = tableKey.portfolios {
			guard portfolios.contains(accountID), let delivered = result.holdings else { return false }
			let shown = ledger.holdings(of: [accountID])
			let kept = Set(Holding.identify(delivered, stored: shown).map(\.id))
			return shown.contains { !kept.contains($0.id) }
		}
		return visibleTransactions.contains { $0.accountID == accountID && $0.isPending }
	}

	/// Applies a change of the rows that comes with a new transaction table: an import, a migration, a
	/// rule applied to all, a new or removed account, group, or category with its view, or a refresh that
	/// removes shown rows. SwiftUI stopped the app in AttributeGraph when it removed a table, or rows of a
	/// table, in the drawing in which the rows that its cells read changed (issues #135, #151). So this
	/// drawing shows a placeholder in place of the table, and the change and the new table come in the
	/// next one. Bumping the table id a drawing after the change instead let the old table insert every new
	/// row first, and the app hung (863ac4b).
	@discardableResult
	func replacingTable<T>(_ change: @MainActor () async throws -> T) async rethrows -> T {
		// A change of the rows that SwiftUI has not drawn yet, such as the refresh of another account of the
		// same run, must not meet the removal of the table.
		while tableHolds == 0 && rowsUndrawn { await drawn() }
		tableHolds += 1
		// Removing the table is a change of its identity: a refresh in place waits until it is drawn.
		noteUndrawn(rows: false)
		Trail.log("table placeholder generation=\(tableGeneration)")
		await drawn()
		defer {
			tableHolds -= 1
			tableGeneration += 1
			Trail.log("table new generation=\(tableGeneration)")
		}
		return try await change()
	}

	/// The view or the filters changed. The table follows at once, or after SwiftUI drew a change of the
	/// ledger. While the placeholder stands in for the table, there is no table to protect.
	private func tableChanged() {
		guard !(rowsUndrawn && tableHolds == 0) else {
			if !tableKeyWaits {
				tableKeyWaits = true
				Trail.log("table waits for drawing")
				afterDraw { [weak self] in
					Task { @MainActor in
						self?.tableKeyWaits = false
						self?.tableChanged()
					}
				}
			}
			return
		}
		let key = TableKey(selection: selection, filter: filter, portfolios: selectedPortfolios)
		guard key != tableKey else { return }
		tableKey = key
		Trail.log("table selection=\(selection?.trailName ?? "none") view=\(key.trailKind) filter=\(filter.trailName) generation=\(tableGeneration)")
		noteUndrawn(rows: false)
	}

	private func noteUndrawn(rows: Bool) {
		if rows { rowsUndrawn = true } else { tableUndrawn = true }
		guard !watchesDrawing else { return }
		watchesDrawing = true
		afterDraw { [weak self] in
			self?.rowsUndrawn = false
			self?.tableUndrawn = false
			self?.watchesDrawing = false
		}
	}

	/// Waits until SwiftUI drew the changes made so far.
	private func drawn() async {
		await withCheckedContinuation { done in afterDraw { done.resume() } }
	}

	/// Runs `work` once SwiftUI has updated the transaction view with every change made so far: `DrawProbe`
	/// reports it. The point where the run loop waits is not enough, because SwiftUI can draw after it.
	/// Without a probe on screen there is no table to protect. A window that does not draw, for example
	/// a minimized one, releases the work after two seconds. `work` runs inside the update of SwiftUI, so
	/// a change that SwiftUI shows goes through a task, which gets a drawing of its own.
	private func afterDraw(_ work: @escaping @MainActor () -> Void) {
		guard drawProbes > 0 else {
			Task { @MainActor in work() }
			return
		}
		// A write only: reading `drawRequest` here, inside an update of SwiftUI such as a selection that a table
		// writes, would make that view depend on every later drawing request (issue #135).
		requestCount += 1
		let request = requestCount
		drawRequest = request
		drawWaiters.append((request, work))
		DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
			MainActor.assumeIsolated {
				guard let self, self.drawWaiters.contains(where: { $0.request <= request }) else { return }
				Trail.log("drawing late, released")
				self.didDraw(upTo: request)
			}
		}
	}

	/// `DrawProbe` saw `request` in an update of SwiftUI, or left the screen (`Int.max`).
	func didDraw(upTo request: Int) {
		let done = drawWaiters.filter { $0.request <= request }
		drawWaiters.removeAll { $0.request <= request }
		for waiter in done { waiter.work() }
	}

	func probeAppeared() { drawProbes += 1 }

	func probeDisappeared() {
		drawProbes -= 1
		didDraw(upTo: .max)
	}

	/// A number for an access in the trail, without its name: its place among the accesses.
	private func trailNumber(of access: UUID) -> Int {
		(accesses.keys.map(\.uuidString).sorted().firstIndex(of: access.uuidString) ?? -1) + 1
	}
}

/// The identity of the transaction table or of the table of positions: the view, the filters, and the
/// portfolios whose positions it shows in place of transactions.
struct TableKey: Hashable {
	var selection: SidebarSelection?
	var filter = TransactionFilter()
	var portfolios: [UUID]?
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
	/// The category picker of ⌘K for these transactions.
	/// `accounts` are those of the transactions, looked up once when the picker opens.
	case assignCategory(Set<UUID>, accounts: Set<UUID>)
	case accountSettings(UUID)
	/// The calibration window that the proposal in the account header opens.
	case calibration(UUID)
	case groupSettings(UUID)
	case categorySettings(UUID)
	case transaction(UUID?)
	case comment(Set<UUID>)
	case migration
	case exportAllData
	case fileImport(FileImport)
	case exporting
	case setPassword
	case changePassword

	var id: String { String(describing: self) }
}
