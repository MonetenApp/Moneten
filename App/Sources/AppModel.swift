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
import Synchronization

enum SidebarSelection: Hashable {
	case account(UUID)
	case group(UUID)
	case category(UUID)
	/// A saved search, which shows the rows of every account.
	case search(UUID)

	var scope: LedgerScope {
		switch self {
		case let .account(id): .account(id)
		case let .group(id): .accountGroup(id)
		case let .category(id): .category(id)
		case .search: .all
		}
	}

	/// The row as the preference `Preference.selectedRow` stores it, such as "account:<UUID>".
	var preferenceValue: String {
		switch self {
		case let .account(id): "account:\(id.uuidString)"
		case let .group(id): "group:\(id.uuidString)"
		case let .category(id): "category:\(id.uuidString)"
		case let .search(id): "search:\(id.uuidString)"
		}
	}

	/// The stored row, or nil when it no longer exists in `ledger` or in `searches`.
	init?(preferenceValue: String, in ledger: Ledger, searches: [SavedSearch]) {
		let parts = preferenceValue.split(separator: ":", maxSplits: 1).map(String.init)
		guard parts.count == 2, let id = UUID(uuidString: parts[1]) else { return nil }
		switch parts[0] {
		case "account" where ledger.account(id) != nil: self = .account(id)
		case "group" where ledger.group(id) != nil: self = .group(id)
		case "category" where ledger.category(id) != nil: self = .category(id)
		case "search" where searches.contains(where: { $0.id == id }): self = .search(id)
		default: return nil
		}
	}
}

enum BalanceMode: String {
	case daily, monthlyAverage
}

/// Settings that the app needs before the database is open. Only `savedFilterBar` holds data of the user: the
/// dates of a custom period, the ends of an amount range, and the IDs of a category and an account.
enum Preference {
	// The unlock settings (`Vault.PasswordEntry`) and the lock settings (`LockSettings`) live in the database: any
	// program of the user can write the settings file, and every data folder shares it. The view modes keep their
	// keys in `ViewModes.key(of:)`.
	/// The selected sidebar row, which the next launch selects again.
	static let selectedRow = "selectedSidebarRow"
	static let balanceMode = "balanceMode"
	/// "Update extensions automatically" in the Extensions window, on unless the user turns it off.
	static let updateExtensionsAutomatically = "updateExtensionsAutomatically"
	/// "Show Moneten icon in menu bar", off unless the user turns it on.
	static let showMenuBarIcon = "showMenuBarIcon"
	/// The pin of the filter bar, and the `SavedFilterBar` it keeps for the next launch.
	static let pinFilterBar = "pinFilterBar"
	static let savedFilterBar = "savedFilterBar"
	/// "Checkmarks" and "Daily Balance" in the View menu.
	static let showsCheckmarks = "showsCheckmarks"
	static let showsDailyBalance = "showsDailyBalance"
	static let vatRates = "vatRates"

	static var rates: [VATRate] {
		VATRate.list(hundredths: AppSettings.defaults.array(forKey: vatRates) as? [Int64] ?? [])
	}

	/// The values of settings the user has not changed.
	static func registerDefaults() {
		adoptLegacyDomain()
		AppSettings.defaults.register(defaults: [vatRates: VATRate.standard.map(\.hundredths)])
	}

	/// Copies the settings of the bundle identifier before the rename to Moneten (ADR 0013) once.
	/// Runs with their own data folder skip it: their settings start empty in that folder (AppSettings).
	private static func adoptLegacyDomain() {
		guard DataFolder.requestedPath == nil else { return }
		let d = AppSettings.defaults, done = "adoptedSettingsOfMonetenMoneten"
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
		/// The database file changed outside the app while it was open. The store is closed, and the window
		/// offers to load the database again.
		case changedOnDisk
		/// A password change left the open connection unable to write safely. The store is closed, and the window
		/// offers to load the database again.
		case passwordChangeUnfinished
	}

	let vault = Vault(folder: .current, keychainOverride: AppKeychain.requestedPath)
	let crashes: CrashReportController
	/// The refreshes of the bank accesses and their dialogs.
	let sync = SyncCoordinator(broker: SessionBroker(defaults: AppSettings.defaults, scope: DataFolder.current.databaseFile.path))
	/// The FinTS connector of the setup and of every refresh.
	let fints = AppModel.makeFinTSConnector()
	/// The installed extensions and the catalog.
	let extensions = ExtensionLibrary()
	/// The updates of the app through Sparkle.
	let updater = AppUpdater()
	/// The connector of each extension that the debug harness loaded from a path, by the name of its package.
	/// An installed extension of the same name goes first.
	var extensionConnectors: [String: ExtensionConnector] = [:]
	/// What failed setups of extension services left for the next setup of the same service and login.
	/// It lives in memory until the lock.
	let extensionSetupStates = KeptSetupStates()
	/// The entries of the sidebar section "Searches", in their order. The lock empties them with the ledger.
	var savedSearches: [SavedSearch] = []
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
	@ObservationIgnored private(set) var ledgerRevision = 0
	@ObservationIgnored var migrationTask: Task<Void, Never>?
	/// True while a migration holds the database writer. Commands that read or change the database wait for its end, because
	/// a write on the main actor would block the window until the migration commits. A file import or an export does not set it.
	private(set) var isStoringMigration = false
	var exportTask: Task<Void, Never>?
	var isTransferringTransactions: Bool { fileImport != nil || exportTask != nil || isStoringMigration }
	@ObservationIgnored private var trailRows = 0
	/// "Automatically refresh accounts" and the notification settings of the "General" tab.
	let refreshSettings = RefreshSettings(defaults: AppSettings.defaults)
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
	/// The rows that keep the mark of new transactions while the view of their account stays open.
	private(set) var newMarks = NewMarks()
	/// The account whose view the user opened, where `markSeen` counted the new transactions as seen. Not observed, so
	/// that opening an account without new transactions redraws no row.
	@ObservationIgnored private var visitedAccount: UUID?

	/// The sidebar row of a new group whose name the user types, until Return, Escape, or a move of the focus away
	/// from the row ends edit mode.
	var namingRow: SidebarSelection?
	/// Whether the sections "Accounts" and "Categories" of the sidebar show their rows. A new group opens its section,
	/// so that its row in edit mode is on screen.
	var showsAccountsSection = true
	var showsCategoriesSection = true

	var selection: SidebarSelection? {
		didSet {
			guard selection != oldValue else { return }
			// The user left the view, so its rows lose the mark of new transactions ("New transactions are marked").
			leaveVisit()
			AppSettings.defaults.set(selection?.preferenceValue, forKey: Preference.selectedRow)
			// The selected rows go in a drawing of their own, and the table of the new view follows one drawing
			// later: SwiftUI stopped the app in AttributeGraph when a table saw a change of its selection in the
			// drawing that removed it (issue #135). Every view change clears them, so that no hidden row stays
			// selected for "Add Comment...". Setting an empty selection again would notify its readers too.
			if !selectedTransactions.isEmpty { selectedTransactions = [] }
			// After the selected rows, so that the new filter waits for their drawing like the new view.
			if let selection { filter.resetHidden(in: selection.scope) }
			if case let .search(id) = selection { applySavedSearch(id) }
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
	var isFilterBarPinned = AppSettings.defaults.bool(forKey: Preference.pinFilterBar) {
		didSet {
			guard isFilterBarPinned != oldValue else { return }
			AppSettings.defaults.set(isFilterBarPinned, forKey: Preference.pinFilterBar)
			if isFilterBarPinned {
				saveFilterBar()
			} else {
				AppSettings.defaults.removeObject(forKey: Preference.savedFilterBar)
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
		AppSettings.defaults.set(bar.data, forKey: Preference.savedFilterBar)
	}

	/// Shows the saved filter bar of a pin that is on. The first view then resets the filter it does not show.
	private func restoreFilterBar() {
		guard isFilterBarPinned, let data = AppSettings.defaults.data(forKey: Preference.savedFilterBar),
			let saved = SavedFilterBar(data: data) else { return }
		choose(period: saved.period)
		filter = saved.filter(in: ledger)
	}
	#if DEBUG || PERF_HARNESS
	/// Set by the debug harness: the next `save(account:)` fails, as a full disk would.
	@ObservationIgnored var failsNextAccountSave = false
	#endif
	private var viewModes = ViewModes(stored: AppSettings.defaults.string(forKey:), store: { AppSettings.defaults.set($1, forKey: $0) })
	/// The view mode of the selected view. Account views and category views each keep their own.
	var viewMode: ViewMode {
		get { viewModes[viewKind] }
		set { viewModes.set(newValue, for: viewKind) { AppSettings.defaults.set($1, forKey: $0) } }
	}
	/// A view without a selection draws no chart, so its mode is that of the account views.
	private var viewKind: ViewModes.Kind {
		switch selection {
		case .category?, .search?: .categories
		case .account?, .group?, nil: .accounts
		}
	}
	var balanceMode: BalanceMode = BalanceMode(rawValue: AppSettings.defaults.string(forKey: Preference.balanceMode) ?? "") ?? .daily {
		didSet { AppSettings.defaults.set(balanceMode.rawValue, forKey: Preference.balanceMode) }
	}
	var chartPeriod: ChartPeriod = .month
	/// The checkmark controls of the list. Hiding them keeps the stored checkmarks.
	var showsCheckmarks = AppSettings.defaults.object(forKey: Preference.showsCheckmarks) as? Bool ?? true {
		didSet { AppSettings.defaults.set(showsCheckmarks, forKey: Preference.showsCheckmarks) }
	}
	/// The balance at the end of each day in the list of a single account.
	var showsDailyBalance = AppSettings.defaults.bool(forKey: Preference.showsDailyBalance) {
		didSet { AppSettings.defaults.set(showsDailyBalance, forKey: Preference.showsDailyBalance) }
	}
	/// The cells of the transaction table read the selection, so a change of it waits for a drawing before the
	/// table goes, like a change of the ledger (issue #135).
	var selectedTransactions = Set<UUID>() {
		didSet { noteUndrawn(rows: true) }
	}
	/// The row that "Go to" selected, which the table of its view scrolls to. The number tells two requests for the
	/// same row apart.
	private(set) var revealedRow: RevealedRow?
	@ObservationIgnored private var revealCount = 0
	/// The number of selected rows of the table of positions, for the trail. The selection lives in that view.
	@ObservationIgnored var selectedPositions = 0

	/// How far `apply(rule:of:mode:)` has come, or nil when no rule is applied.
	private(set) var ruleProgress: (done: Int, total: Int)?
	/// Set for the whole run, so views that only ask whether a run is active do not redraw on each report.
	private(set) var isApplyingRule = false
	/// The run of `apply(rule:of:mode:)`, which a lock cancels.
	@ObservationIgnored private var ruleRun: Task<[Transaction], Never>?
	/// The rule that "Create Rule" puts into the settings of a category. The settings take it when they open,
	/// and it is saved only when the user confirms them.
	@ObservationIgnored var ruleDraft: (categoryID: UUID, rule: String)?
	/// The input of the open sheet, which the lock keeps in memory so that the sheet shows again after the unlock.
	/// The input belongs to the database file that was open at the lock (`DatabaseStamp`).
	@ObservationIgnored var heldSheet = HeldSheet<SheetKind, any Sendable, DatabaseStamp>()
	/// True while an unlock with the password opens the database, the only open that can give the held sheet back.
	@ObservationIgnored private var isUnlocking = false
	/// The sheet that the unlock gives back, from the unlock until `showHeldSheet()` opens it. The alerts wait for it.
	@ObservationIgnored var returningSheet: SheetKind?
	#if DEBUG || PERF_HARNESS
	/// The last input that a sheet wrote while the app was unlocked, and the one that "sheetinput mark" remembered,
	/// for the command "sheetinput" of the debug harness.
	@ObservationIgnored var debugSheetInput: AnyHashable?
	@ObservationIgnored var debugSheetInputMark: AnyHashable?
	#endif

	/// The alerts of the main window, which show once no sheet is on it.
	@ObservationIgnored let alerts = SheetAlerts(window: "main")
	/// The first message for an alert of the main window. Setting a message puts it in line after the others,
	/// and nil closes the first one, as its OK button does.
	var alert: AlertMessage? {
		get { alerts.message }
		set { if let newValue { alerts.post(newValue) } else { alerts.closeFirst() } }
	}
	/// The file import that runs. There is one at a time, and a lock cancels it.
	var fileImport: FileImport?
	var sheet: SheetKind? {
		didSet {
			guard sheet != oldValue else { return }
			Trail.log("sheet \(sheet?.trailName ?? "none")")
			// A sheet that the unlock gave back takes its input until it closes.
			if let oldValue { heldSheet.close(oldValue) }
			// A window on top of the sheet goes with it, and a late report of that window changes nothing.
			overSheet.sheetChanged()
			// So does an alert or a question on the sheet, also one that waits for the dialog of the bank.
			alertGate.sheetChanged()
			sheetAlert = nil
			// A menu command can open another sheet over the question or preview of an import, which then would wait
			// for an answer that never comes.
			if case let .fileImport(run) = oldValue, (run.question != nil || run.preview != nil) { run.cancel() }
		}
	}
	/// The window on top of the open sheet, such as the calibration window over the account settings. The dialog of
	/// the bank shows on it while it is open, and waits while it slides out (`BankDialogPlace`).
	var overSheet = OverSheetState()
	/// Where the dialog of the bank shows now, nil while it waits.
	var bankDialogPlace: BankDialogPlace? {
		BankDialogPlace(sheet: sheet != nil, crashReport: crashes.pending != nil, overSheet: overSheet.phase, alert: alertGate.alert)
	}
	/// The alerts and questions of the main window, on the window and on its sheet, and the dialog of the bank, which
	/// never show at the same time (`AlertGate`).
	var alertGate = AlertGate()
	/// The alert, question, or save panel of the open sheet until the user answers it: asked while a dialog of the bank
	/// or another alert is in the way, without a token, and on screen with the token of its opening.
	var sheetAlert: (alert: SheetAlert, token: AlertGate.Token?)?
	/// The alert of `alerts` on the main window, from its opening until it has slid out.
	@ObservationIgnored var windowAlert: AlertGate.Token?
	/// When the last alert of the main window opened and the last dialog of the bank ended, for `alertSettle`.
	@ObservationIgnored var alertOpenedAt: ContinuousClock.Instant?
	@ObservationIgnored var bankDialogEndedAt: ContinuousClock.Instant?
	var settingsTab = SettingsTab.general
	/// The number of transaction tables that `replacingTable` started, for the trail.
	@ObservationIgnored private(set) var tableGeneration = 0
	/// The changes of `replacingTable` that wait for their new table. While there is one, a placeholder
	/// stands in for the transaction table.
	private(set) var tableHolds = 0
	/// Column widths and order of the transaction table. They live here, so a new table keeps them.
	var transactionColumns = TableColumnCustomization<Transaction>()

	/// The lock settings of the open database. The database holds them, so they come with each unlock.
	private(set) var lockSettings = LockSettings()
	/// The unlock settings of this database that are on. Each open reads them from the database, and a change on the
	/// "Security" tab updates them. Before the first open of a launch they are the settings whose Keychain entry exists,
	/// because only the entries can be read then; the open checks an entry against the database (issue #405).
	var unlockSettings: Set<Vault.PasswordEntry> = []
	private var lastActivity = Date()
	private var eventMonitor: Any?
	private var idleTimer: Timer?

	init() {
		// The lock of the data folder comes before every service that writes into it, such as the crash reports, so a
		// second running copy changes no file there.
		let lock = try? DataFolderLock(folder: .current)
		crashes = CrashReportController(folder: .current)
		if lock != nil { crashes.start() }
		folderLock = lock
		Preference.registerDefaults()
		autoRefresh = AutoRefresh(settings: refreshSettings, now: Self.refreshClock)
		announcer = NewTransactionsAnnouncer(settings: refreshSettings, center: notices)
		// A closure that captures `self` can be handed over only once every stored property is set.
		sync.deliver = { [weak self] accountID, result in
			// A refresh that ran while the user closed the account delivers nothing into it. The merge checks it again in its write.
			guard let self, self.ledger.account(accountID)?.isClosed != true else { return }
			self.announcer.stored(try await self.mergeRefresh(result, into: accountID).added)
			if let kind = self.ledger.account(accountID)?.kind {
				self.bankHistories[accountID] = result.bankHistory(after: self.bankHistories[accountID], of: kind)
			}
		}
		// The coordinator asks for the state before it lets the next work of the access go, so it is stored at once.
		sync.storeState = { [weak self] access, state, attended in
			self?.recordRefresh(of: access, state: state, accounts: [:], attended: attended)
		}
		sync.ended = { [weak self] access, accounts, attended in
			let failed = accounts.values.filter { if case .failed = $0 { true } else { false } }.count
			guard let self else { return }
			Trail.log("refresh end access=\(self.trailNumber(of: access)) accounts=\(accounts.count) failed=\(failed)")
			// The times and errors change the accounts in the ledger, which must not meet a new view in one drawing.
			// `ended` is awaited, so a migration that pauses the refreshes starts only after this write.
			while self.tableUndrawn { await self.drawn() }
			self.recordRefresh(of: access, state: nil, accounts: accounts, attended: attended)
			self.sync.recordedRefresh(of: access)
			self.extensions.sessionEnded()
			if attended { self.showNotices() }
		}
		sync.noticed = { [weak self] access, messages in
			// A setup access is not stored, so its service names the bank.
			guard let self else { return }
			self.bankNotices.add(messages, from: self.accesses[access.id]?.bankName ?? access.bankName)
		}
		sync.runEnded = { [weak self] in
			guard let self else { return }
			self.announcer.runEnded(ledger: self.ledger)
		}
		sync.userCanceled = { [weak self] accounts in self?.recordCancel(of: accounts) }
		sync.mayStartUnattended = { [weak self] in self?.autoRefresh.allowsUnattended ?? false }
		sync.pausesUnattended = { [weak self] access in self?.ledger.pausesAutomaticRefresh(of: access) ?? false }
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
		alerts.hasSheet = { [weak self] in self?.sheet != nil || self?.returningSheet != nil }
		alerts.mayOpen = { [weak self] in self?.openWindowAlert() ?? true }
		alerts.didClose = { [weak self] window in self?.windowAlertClosed(window) }
		watchBankDialog()
		updater.isBusy = { [weak self] in self.map { $0.sync.isRefreshing || $0.sync.broker.current != nil } ?? false }
		// A window that opens while SwiftUI builds the scenes stops the app, so the checks run after it.
		DispatchQueue.main.async { [updater] in LaunchChecks.run(updater: updater) }
	}

	// MARK: Opening and locking

	/// What the window shows while the database opens: "Opening database..." or "Upgrading database...".
	/// Nil while nothing opens.
	private(set) var opening: String?
	/// Held while the app runs, so that no second running copy opens the same data folder.
	private var folderLock: DataFolderLock?
	/// Reports each change of the entries in the database folder, such as a backup put in place of the file.
	var diskSource: DispatchSourceFileSystemObject?
	/// True while a check of the database file runs away from the main thread.
	var checksDisk = false
	/// True while the window says that a database file from the Finder is not opened.
	var openedDatabaseFile = false
	/// Why the lock screen asks for the password although an unlock setting is on, such as a Keychain error
	/// or a password in the Keychain that does not open a database restored from a backup.
	private(set) var lockNotice: String?

	/// Opens the database after the seal check of the app, which runs away from the main thread. A command of
	/// the debug harness that opened or created the database meanwhile wins.
	func start() {
		let from = phase
		Task {
			if let damaged = await LaunchChecks.damagedApp { return phase = .failed(damaged) }
			guard phase == from else { return }
			await startOpening()
		}
	}

	private func startOpening() async {
		guard opening == nil else { return }
		// A launch or "Try Again" may open another database than the one that was locked.
		dropHeldSheet()
		phase = .starting
		// A second running copy of the app, such as one in the Downloads folder, opens nothing in this data folder.
		if folderLock == nil {
			do { folderLock = try DataFolderLock(folder: vault.folder) } catch {
				phase = .failed(String(describing: error))
				return
			}
			// A copy that got the lock only now, through "Try Again", starts its crash reports now.
			crashes.start()
		}
		do {
			switch try vault.state() {
			case .empty:
				phase = .firstLaunch
			case .randomKey:
				hasPassword = false
				do {
					try await openAway { vault, upgrading in try vault.openWithRandomKey(upgrading: upgrading) }
				} catch Vault.Failure.incorrectPassword {
					// Setting the first password stopped after the key had changed. The password opens it.
					hasPassword = true
					phase = .locked
				}
			case .password:
				hasPassword = true
				// Only the entry of the automatic unlock opens the database at launch, never one of Touch ID or Apple Watch.
				let stored: String?
				do {
					// The settings first, so a failed cleanup of the old shared entry still shows the entries that exist.
					unlockSettings = try vault.storedEntries()
					try vault.removeSharedEntry()
					stored = try vault.storedPassword(for: .automaticUnlock)
				} catch {
					lockNotice = String(describing: error)
					phase = .locked
					return
				}
				guard let stored else {
					phase = .locked
					return
				}
				do {
					try await openAway { vault, upgrading in try vault.open(storedFor: [.automaticUnlock], password: stored, upgrading: upgrading) }
				} catch Vault.Failure.incorrectPassword {
					lockNotice = Self.staleKeychainNotice
					phase = .locked
				} catch Vault.Failure.unlockMethodOff(let on) {
					refuseOffEntry(on: on)
				}
			}
		} catch is OpenOvertaken {
			// Another step, such as an unlock with the password, decided what the window shows.
		} catch {
			phase = .failed(vault.explanation(of: error))
		}
	}

	/// An opening whose result arrived after the app had moved on, for example to a new database.
	private struct OpenOvertaken: Error {}

	enum UnlockResult {
		case unlocked
		case incorrectPassword
		/// Another unlock is still opening the database, or finished first. The password was not tried.
		case busy
		/// The password opened nothing because the database could not be opened. The window shows why.
		case failed
	}

	private static var staleKeychainNotice: String {
		String(localized: "The password in the Keychain does not open this database, for example after a backup was put in its place. Enter the database password.")
	}

	/// Opens the database away from the main thread, so that the window can show what happens.
	/// When the app moved on while the database opened, the new store is closed and nothing is unlocked.
	private func openAway(_ opener: @escaping @Sendable (Vault, @escaping @Sendable () -> Void) throws -> Store) async throws {
		let phaseBefore = phase
		opening = String(localized: "Opening database...")
		defer { opening = nil }
		let vault = vault
		let store = try await Task.detached {
			try opener(vault) {
				Task { @MainActor [weak self] in
					if self?.opening != nil { self?.opening = String(localized: "Upgrading database...") }
				}
			}
		}.value
		guard phase == phaseBefore, self.store == nil else {
			try? store.close()
			throw OpenOvertaken()
		}
		try open(store)
	}

	func createDatabase(password: String?) {
		// Only the copy that holds the lock of the data folder creates a database. The vault itself refuses a folder with files.
		guard folderLock != nil else { return }
		do {
			let store = try vault.create(password: password, starterCategories: StarterCategories.make(language: starterLanguage))
			dropHeldSheet()
			// `create` removed the entries of a database that was here before, so every unlock setting is off.
			unlockSettings = []
			hasPassword = password != nil
			try open(store)
		} catch {
			phase = .failed(vault.explanation(of: error))
		}
	}

	/// The database has a setting off that the password from the Keychain was offered for, so the vault closed it again.
	/// The lock screen asks for the password and offers only the settings that are on and still have their entry.
	private func refuseOffEntry(on: Set<Vault.PasswordEntry>) {
		lockNotice = String(describing: Vault.Failure.unlockMethodOff(on: on))
		unlockSettings = on.intersection((try? vault.storedEntries()) ?? [])
		phase = .locked
	}

	/// A different password in the Keychain, such as the newer one of a database that the user replaced with
	/// a backup, is replaced after the unlock, and the entry of a setting that is off goes. A second unlock while one
	/// runs returns `.busy`, so the lock screen keeps the typed password. `offered` names the settings of a password
	/// from the Keychain, and the open then needs each of them on in the database.
	@discardableResult
	func unlock(password: String, offered: Set<Vault.PasswordEntry> = []) async -> UnlockResult {
		guard opening == nil, phase == .locked else { return phase == .unlocked ? .unlocked : .busy }
		// Only an unlock of the file that was locked gets the held sheet back (`open`).
		isUnlocking = true
		defer { isUnlocking = false }
		do {
			try await openAway { vault, upgrading in
				offered.isEmpty
					? try vault.open(password: password, upgrading: upgrading)
					: try vault.open(storedFor: offered, password: password, upgrading: upgrading)
			}
		} catch Vault.Failure.incorrectPassword {
			return .incorrectPassword
		} catch Vault.Failure.unlockMethodOff(let on) {
			refuseOffEntry(on: on)
			return .failed
		} catch is OpenOvertaken {
			return phase == .unlocked ? .unlocked : .busy
		} catch {
			dropHeldSheet()
			phase = .failed(vault.explanation(of: error))
			return .failed
		}
		lockNotice = nil
		do {
			if let store { try vault.refreshStoredPassword(password, on: store) }
			try loadUnlockSettings()
		} catch {
			// A write that failed may have removed its entry, which turned that setting off.
			try? loadUnlockSettings()
			alert = AlertMessage(title: String(localized: "The database password could not be stored in the Keychain."), message: String(describing: error))
		}
		return .unlocked
	}

	/// The unlock methods whose setting is on.
	func unlockMethods() -> [UnlockMethod] {
		guard hasPassword else { return [] }
		return UnlockMethod.allCases.filter { unlockSettings.contains($0.entry) }
	}

	/// Reads which unlock settings of the open database are on.
	func loadUnlockSettings() throws {
		guard let store else { return }
		unlockSettings = try store.unlockMethods()
	}

	func unlock(with methods: [UnlockMethod]) {
		UnlockMethod.authenticate(methods) { ok in
			Task { @MainActor in
				guard ok else { return }
				do {
					let offered = Set(methods.map(\.entry))
					guard let pw = try self.vault.unlockPassword(offered: offered) else { return }
					if await self.unlock(password: pw, offered: offered) == .incorrectPassword { self.lockNotice = Self.staleKeychainNotice }
				} catch {
					self.lockNotice = String(describing: error)
				}
			}
		}
	}

	private func open(_ store: Store) throws {
		self.store = store
		lockSettings = try store.lockSettings()
		unlockSettings = try store.unlockMethods()
		var loaded = try store.loadLedger()
		// An unchanged starter set of the other language takes the names of the interface language. A failed
		// write keeps the old names, which the next open tries again, and does not keep the database closed.
		let renamed = StarterCategories.renamed(in: loaded, to: starterLanguage)
		if !renamed.isEmpty {
			do {
				try store.save(categories: renamed)
				let byID = Dictionary(uniqueKeysWithValues: renamed.map { ($0.id, $0) })
				loaded.replace(categories: loaded.categories.map { byID[$0.id] ?? $0 })
			} catch {
				// The line names no category, because a name may be one that the user gave.
				Trail.log("starter rename failed categories=\(renamed.count) error=\(type(of: error))")
			}
		}
		ledgerChange = "load"
		ledger = loaded
		accesses = Dictionary(uniqueKeysWithValues: try store.accesses().map { ($0.id, $0) })
		savedSearches = try store.savedSearches()
		// The saved PINs live only in the database, so a refresh after a restart or an unlock does not ask.
		try sync.broker.open(store)
		if selection == nil {
			restoreFilterBar()
			// The row of the last session, or the first row when it no longer exists.
			selection = AppSettings.defaults.string(forKey: Preference.selectedRow).flatMap { SidebarSelection(preferenceValue: $0, in: ledger, searches: savedSearches) }
				?? firstSidebarRow
		}
		lastActivity = Date()
		// The held sheet returns only when this open is the unlock of the database file that was locked. The stamp is
		// taken now that the store is open, so it names the file that the store reads, also when another file took the
		// place of the database between the start of the unlock and the open. A launch, a new database, and a file
		// that changed while the app was locked drop it. A change after this stamp is a change on disk of the open
		// store, which closes the database and drops the input (`checkDisk`).
		returningSheet = heldSheet.unlock(database: isUnlocking ? vault.databaseStamp() : nil)
		isUnlocking = false
		phase = .unlocked
		watchDisk()
		extensions.open(store)
		announcer.unlock()
		if let notified = notifiedAccounts {
			notifiedAccounts = nil
			select(notified: notified)
		}
		// The selected view shows again after the lock, a new visit.
		mainWindowOpened()
		autoRefresh.isUnlocked = true
	}

	func lock() {
		guard hasPassword, phase == .unlocked else { return }
		storeVisitSeen()
		closeDatabase(then: .locked)
	}

	/// Closes the store and forgets everything that came from it, for the lock and after a change on disk.
	func closeDatabase(then next: Phase) {
		stopWatchingDisk()
		// A locked app refreshes nothing and forgets every PIN in memory. The saved ones come back from the database at the next unlock.
		// The announcer locks first, because the cancel below can end the run at once.
		announcer.lock(keeping: ledger)
		fileImport?.cancel()
		migrationTask?.cancel()
		exportTask?.cancel()
		// The alerts on screen close before the lock screen draws, and they show again after the unlock. The
		// action of a button that the user clicked just before, such as "Connect...", is dropped.
		alerts.isViewOnScreen = false
		extensions.alerts.isViewOnScreen = false
		autoRefresh.isUnlocked = false
		notices.clearBadge()
		sync.cancelAll()
		sync.broker.forgetPINs()
		extensionSetupStates.clear()
		setup?.cancel()
		setup = nil
		ruleRun?.cancel()
		extensions.close()
		if isStoringMigration, let store {
			Task.detached { try? store.close() }
		} else {
			try? store?.close()
		}
		store = nil
		accesses = [:]
		bankNotices = BankNotices()
		bankHistories = [:]
		// Only the lock keeps the input of the open sheet, for the file as the store left it. Any other close ends
		// this database for good. The held input is not observed, so this changes no view in the drawing that shows
		// the lock screen (issue #151).
		if next == .locked {
			heldSheet.lock(closing: sheet, database: vault.databaseStamp())
			returningSheet = nil
			#if DEBUG || PERF_HARNESS
			debugSheetInput = nil
			#endif
		} else {
			dropHeldSheet()
		}
		sheet = nil
		// A name half typed into a new group is lost, and the group keeps the name it has in the database.
		namingRow = nil
		phase = next
		// The lock removes the transaction table in this drawing and empties its rows after it, so that the
		// table never goes in the drawing that changes its rows (issue #151).
		afterDraw { [weak self] in
			Task { @MainActor in
				guard let self, self.phase == next else { return }
				self.ledgerChange = "clear"
				self.ledger = Ledger()
				self.newMarks = NewMarks()
				self.visitedAccount = nil
				self.savedSearches = []
				self.selectedTransactions = []
			}
		}
	}

	func setPassword(_ password: String) {
		guard let store else { return }
		do {
			try vault.setPassword(password, on: store)
			hasPassword = true
			alert = AlertMessage(title: String(localized: "The password has been changed."), message: String(localized: "From now on, the database password opens Moneten."))
		} catch let failure as Vault.Failure where failure.passwordChanged {
			hasPassword = true
			alert = AlertMessage(title: String(localized: "The password has been changed."), message: String(describing: failure))
		} catch {
			alert = AlertMessage(title: String(localized: "Could not change password of database."), message: String(describing: error))
			closeIfPasswordChangeLeftNoWrites(error)
		}
	}

	/// Returns the error for the sheet, or nil when the password has been changed.
	func changePassword(current: String, new: String) -> String? {
		guard let store else { return nil }
		do {
			try vault.changePassword(current: current, new: new, on: store)
			alert = AlertMessage(title: String(localized: "The password has been changed."), message: "")
			return nil
		} catch Vault.Failure.incorrectPassword {
			return String(localized: "Incorrect password!")
		} catch let failure as Vault.Failure where failure.passwordChanged {
			// A Keychain entry that could not take the new password may be gone, which turns its setting off.
			if case .keychainNotUpdated = failure { try? loadUnlockSettings() }
			alert = AlertMessage(title: String(localized: "The password has been changed."), message: String(describing: failure))
			return nil
		} catch {
			closeIfPasswordChangeLeftNoWrites(error)
			if case .passwordNotChanged? = error as? Vault.Failure { return String(describing: error) }
			if error is DatabaseChangedOnDisk { return String(describing: error) }
			return String(localized: "Could not change password of database. \(String(describing: error))")
		}
	}

	// MARK: Inactivity

	private func installActivityMonitor() {
		eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .leftMouseDown, .rightMouseDown, .scrollWheel, .mouseMoved]) { [weak self] event in
			MainActor.assumeIsolated { self?.lastActivity = Date() }
			return event
		}
		idleTimer = Timer.scheduledTimer(withTimeInterval: 20, repeats: true) { [weak self] _ in
			MainActor.assumeIsolated {
				self?.checkIdle()
				self?.checkDisk()
			}
		}
		NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
			MainActor.assumeIsolated { self?.checkDisk() }
		}
		NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
			MainActor.assumeIsolated { self?.checkIdle() }
		}
	}

	private func checkIdle() {
		guard phase == .unlocked, lockSettings.lockAfterMinutes > 0 else { return }
		#if DEBUG || PERF_HARNESS
		// The scripts of the debug harness run longer than the shortest lock time.
		if ProcessInfo.processInfo.environment["MONETEN_DEBUG_NO_IDLE_LOCK"] == "1" { return }
		#endif
		if Date().timeIntervalSince(lastActivity) >= Double(lockSettings.lockAfterMinutes) * 60 { lock() }
	}

	func mainWindowClosed() {
		// Closing the window ends the visit of the view as leaving it does, also when the app stays unlocked. The lock
		// ends it in the store alone.
		if lockSettings.lockOnClose && hasPassword && phase == .unlocked { lock() } else { leaveVisit() }
	}

	/// The app quits: the rows that came during the visit count as seen, so the next launch does not mark them again.
	func applicationWillTerminate() {
		storeVisitSeen()
	}

	/// The main window opened again, or the app was unlocked: the user sees the selected view anew.
	func mainWindowOpened() {
		guard phase == .unlocked else { return }
		afterDraw { [weak self] in Task { @MainActor in self?.markSeen() } }
	}

	/// Writes the lock settings to the database first, as every change does.
	func saveLockSettings(_ settings: LockSettings) throws {
		guard let store else { throw SecurityChangeFailure(description: String(localized: "Unlock Moneten to change this setting.")) }
		try store.saveLockSettings(settings)
		lockSettings = settings
	}

	/// Brings the window "Notice" forward when a notice came since it last did. The app calls it only when
	/// the user is there, at the end of a refresh that the user started and when the main window comes
	/// forward, because an automatic refresh opens no dialog ("An automatic refresh never asks the user").
	func showNotices() {
		if bankNotices.bringForward() { openNoticeWindow() }
	}

	// MARK: Selection and filters

	/// The first group or account of the sidebar, or nil without accounts.
	var firstSidebarRow: SidebarSelection? {
		switch ledger.accountTree(in: nil).first {
		case let .group(g): .group(g.id)
		case let .account(a): .account(a.id)
		case nil: nil
		}
	}

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

	/// "Go to": opens `target` with the row `id` selected and visible. The view change clears the selected rows, and
	/// a table must not see a change of its selection in the drawing that brings it (issue #135), so the row is
	/// selected once the table of `target` is drawn.
	func go(to target: SidebarSelection, selecting id: UUID) {
		navigate(to: target)
		select(id, whenDrawn: target, tries: 4)
	}

	/// The table of a view can wait for a drawing of a change of the ledger (issue #151), so this tries again after
	/// each drawing until the table of `target` is drawn. It gives up when the user chose another view meanwhile.
	private func select(_ id: UUID, whenDrawn target: SidebarSelection, tries: Int) {
		afterDraw { [weak self] in
			Task { @MainActor in
				guard let self, self._selection == target else { return }
				guard self._tableKey.selection == target, !self.tableUndrawn, self._tableHolds == 0 else {
					if tries > 0 { self.select(id, whenDrawn: target, tries: tries - 1) }
					return
				}
				// A portfolio shows positions, and a filter can hide the row.
				guard self._tableKey.portfolios == nil, self.visibleTransactions.contains(where: { $0.id == id }) else { return }
				self.selectedTransactions = [id]
				self.revealCount += 1
				self.revealedRow = RevealedRow(id: id, key: self._tableKey, request: self.revealCount)
			}
		}
	}

	/// The rows of the transaction table, for the view and the filters of `tableKey`.
	var visibleTransactions: [Transaction] { rows(for: tableKey).rows }

	/// The selected rows that the table shows. A search keeps the selection of the rows that it hides.
	/// It filters the rows, so a menu reads it in its action and not in its `disabled` check.
	var visibleSelection: Set<UUID> { shown(selectedTransactions) }

	/// The rows of `ids` that the table shows. A command acts only on these, so that it never changes a row that a
	/// search hides, such as the row that "Go to" selected before the user typed a search.
	func shown(_ ids: Set<UUID>) -> Set<UUID> { ids.intersection(visibleTransactions.map(\.id)) }

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

	/// New transactions count as seen when the user opens their account, so the number on its sidebar row goes. Their
	/// rows keep the mark until the user leaves the view (`newMarks`).
	private func markSeen() {
		guard !isStoringMigration else { return }
		// The rows wait until SwiftUI drew a new table.
		if tableUndrawn {
			afterDraw { [weak self] in Task { @MainActor in self?.markSeen() } }
			return
		}
		guard case let .account(id) = selection, store != nil else { return }
		visitedAccount = id
		// Without new transactions `newMarks` stays as it is, so that no date cell of the list draws again.
		guard ledger.newTransactionCounts[id, default: 0] > 0 else { return }
		storeSeen(newMarks.open(account: id, in: ledger), of: id)
	}

	/// Ends the visit of a view: its marks go, and the transactions that a refresh added to the visited account while
	/// its view was open count as seen now (`NewMarks.leave(account:in:)`).
	private func leaveVisit() {
		let visited = visitedAccount
		visitedAccount = nil
		guard visited != nil || !newMarks.isEmpty else { return }
		let seen = newMarks.leave(account: visited, in: ledger)
		if let visited, !isStoringMigration { storeSeen(seen, of: visited) }
	}

	/// Ends the visit in the database alone, for the lock and the end of the app. The lock removes the table in the
	/// drawing that it starts, so a change of the rows or of their marks must not come with it (issue #151). The ledger
	/// and the marks go one drawing later (`closeDatabase`), and the next unlock loads the rows as seen.
	private func storeVisitSeen() {
		guard let id = visitedAccount else { return }
		visitedAccount = nil
		guard !isStoringMigration, ledger.newTransactionCounts[id, default: 0] > 0, let store else { return }
		try? store.markSeen(account: id)
	}

	/// Writes that the `count` new transactions of an account are seen, through the store first, then into the ledger.
	private func storeSeen(_ count: Int, of id: UUID) {
		guard count > 0, let store, (try? store.markSeen(account: id)) != nil else { return }
		ledgerChange = "seen"
		ledger.markSeen(account: id)
	}

	var title: String {
		switch selection {
		case let .account(id): ledger.account(id)?.name ?? ""
		case let .group(id): ledger.group(id)?.name ?? ""
		case let .category(id): ledger.categoryPath(id)
		case let .search(id): savedSearches.first { $0.id == id }?.name ?? ""
		case nil: "Moneten"
		}
	}

	// MARK: Changing transactions

	/// Saves the rows, with the accounts whose derived initial balance they change, and returns whether they are saved.
	/// A locked app has no database and saves nothing.
	@discardableResult
	private func commit(_ changed: (transactions: [Transaction], parts: [SplitPart])) -> Bool {
		guard let store else { return false }
		guard !changed.transactions.isEmpty || !changed.parts.isEmpty else { return true }
		do {
			let accounts = try ledger.followingBankBalance(saving: changed.transactions)
			try store.save(changed.transactions, parts: changed.parts, accounts: accounts)
			ledgerChange = "commit rows=\(changed.transactions.count) parts=\(changed.parts.count)"
			for a in accounts { ledger.upsert(a) }
			ledger.update(changed.transactions, parts: changed.parts)
			return true
		} catch {
			alert = AlertMessage(title: String(localized: "Could not save the change."), message: String(describing: error))
			return false
		}
	}

	/// The user's choice of an asset class for the positions `ids`, nil for "Automatic", which goes back to the class of
	/// the source. It writes through the store first and changes the ledger only after the write succeeds.
	func setAssetClass(_ choice: AssetClass?, of ids: Set<UUID>) {
		guard let store, !ids.isEmpty else { return }
		do {
			try store.setUserAssetClass(choice, ofHoldings: ids)
			ledgerChange = "asset class"
			ledger.setUserAssetClass(choice, of: ids)
		} catch {
			alert = AlertMessage(title: String(localized: "Could not save the change."), message: String(describing: error))
		}
	}

	/// What ⌘K does: the category picker for the selected rows on screen.
	func openCategoryPicker() {
		let ids = visibleSelection
		if !ids.isEmpty { sheet = .assignCategory(ids, accounts: ledger.accountIDs(ofTransactions: ids)) }
	}

	/// What ⌘⇧K does: the comment of the selected rows on screen.
	func openCommentSheet() {
		let ids = visibleSelection
		if !ids.isEmpty { sheet = .comment(ids) }
	}

	/// What "Create Rule" in the context menu of a transaction does: the settings of the category, with
	/// `condition` added to its rule.
	func createRule(_ condition: String, in categoryID: UUID) {
		guard let c = ledger.category(categoryID) else { return }
		ruleDraft = (categoryID, Rule.adding(condition, to: c.rule))
		sheet = .categorySettings(categoryID)
	}

	/// Changes the rows of the open view in place (issue #154). An assignment that takes its last shown rows out of
	/// the view would remove the table in the update that changes its rows, so it comes with a new table, and the
	/// view shows its placeholder for no rows (issue #223).
	func assign(category: UUID?, to ids: Set<UUID>) {
		let changes = assignment(of: category, to: ids)
		if tableKey.portfolios == nil, let scope = tableKey.selection?.scope, ledger.leavesNoRows(in: scope, filter: tableKey.filter, saving: changes) {
			// The ledger can change while the placeholder waits for its drawing, so the rows are read again.
			Task { await replacingTable { commit(assignment(of: category, to: ids)) } }
		} else {
			commit(changes)
		}
	}

	private func assignment(of category: UUID?, to ids: Set<UUID>) -> (transactions: [Transaction], parts: [SplitPart]) {
		let target = category == ledger.defaultCategory?.id ? nil : category
		let changed = ids.compactMap { ledger.row($0) }.map { t -> Transaction in
			var t = t
			t.categoryID = target
			t.categorizedBy = target == nil ? .none : .manual
			return t
		}
		return ledger.changes(from: changed)
	}

	/// What a drag from this app carries: rows of the transaction list, a category, or a group or an account of the sidebar.
	enum Drag {
		case transactions(Set<UUID>)
		case category(UUID)
		case treeItem(UUID)
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

	func startDrag(treeItem id: UUID) -> DraggedTreeItem {
		drag = .treeItem(id)
		return DraggedTreeItem(id: id)
	}

	func endDrag() { drag = nil }

	/// Whether the group row lights up for the drag in progress: a group or an account that would move into it.
	func acceptsDrag(on group: AccountGroup) -> Bool {
		guard case let .treeItem(id) = drag else { return false }
		let (parent, index) = ledger.destination(of: .group(group.id))
		return !ledger.move(treeItem: id, into: parent, at: index).isEmpty
	}

	/// The drop of the dragged group or account. The row of a group and the gap beside it are two drop targets, and
	/// both could get the same drop, so the first drop ends the drag and moves the row, and a later one finds no drag.
	/// It reads the row from the drag and not from the dropped data, which arrives later, so that the order of the
	/// two targets decides and not the time the data takes.
	@discardableResult
	func dropTreeItem(on target: TreeDropTarget) -> Bool {
		guard case let .treeItem(id) = drag else { return false }
		drag = nil
		let (parent, index) = ledger.destination(of: target)
		guard !ledger.move(treeItem: id, into: parent, at: index).isEmpty else { return false }
		move(treeItem: id, into: parent, at: index)
		return true
	}

	/// Whether the category row lights up for the drag in progress.
	func acceptsDrag(on category: Domain.Category) -> Bool {
		switch drag {
		case let .transactions(ids): canDrop(ids, on: category)
		case let .category(id): canDrop(category: id, on: category)
		case .treeItem, nil: false
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
			alert = AlertMessage(title: String(localized: "Could not move the category."), message: String(describing: error))
		}
	}

	func setChecked(_ checked: Bool, for ids: Set<UUID>) {
		let rows = ids.compactMap { ledger.row($0) }
		if checked {
			guard commit(ledger.changes(from: rows.filter(\.changesWhenChecked).map { var t = $0; t.markChecked(); return t })) else { return }
			if !newMarks.isEmpty { newMarks.checked(ids) }
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
		alert.messageText = String(localized: "Mark all transactions as checked?")
		alert.informativeText = String(localized: "A total of \(String(localized: "\(count) transactions")) in \(String(localized: "\(accounts) accounts")) will be marked as checked.")
		alert.addButton(withTitle: String(localized: "Mark as Checked"))
		alert.addButton(withTitle: String(localized: "Cancel"))
		if alert.runModal() == .alertFirstButtonReturn { setChecked(true, for: Set(rows.map(\.id))) }
	}

	func setComment(_ comment: String, for ids: Set<UUID>) {
		let value = comment.trimmingCharacters(in: .whitespacesAndNewlines)
		commit(ledger.changes(from: ids.compactMap { ledger.row($0) }.map { var t = $0; t.comment = value.isEmpty ? nil : value; return t }))
	}

	func save(transaction t: Transaction, adding: Bool) {
		let categorizer = Categorizer(ledger: ledger)
		let changed = categorizer.allOrNothing {
			var changed = adding ? (transactions: [t], parts: [SplitPart]()) : ledger.changes(from: [t])
			for i in changed.transactions.indices where changed.transactions[i].categoryID == nil && changed.transactions[i].categorizedBy != .manual {
				categorizer.categorize(&changed.transactions[i])
			}
			return changed
		}
		commit(changed)
	}

	@discardableResult
	func replaceParts(of transactionID: UUID, with parts: [SplitPart]) async -> Bool {
		await replacingParts(of: transactionID, with: parts) == .done
	}

	/// The parts were computed from the ledger before the drawing wait. A rule run, ⌘K, or a refresh can change
	/// the transaction or its parts during the wait, so the parts are stored only when `Ledger.splitBase(of:)`
	/// is the same after it.
	func replacingParts(of transactionID: UUID, with parts: [SplitPart]) async -> SplitOutcome {
		guard let store, let base = ledger.splitBase(of: transactionID) else { return .missing }
		return await replacingTable {
			// The split window cancels its split when it closes, for example on a lock during the wait.
			guard !Task.isCancelled else { return .cancelled }
			guard self.store === store, let now = ledger.splitBase(of: transactionID) else { return .missing }
			guard now == base else { return .changed }
			do {
				try store.replaceParts(of: transactionID, with: parts)
				ledgerChange = "split parts=\(parts.count)"
				ledger.replaceParts(of: transactionID, with: parts)
				selectedTransactions = parts.isEmpty ? [transactionID] : Set(parts.map(\.id))
				return .done
			} catch {
				alert = AlertMessage(title: String(localized: "Could not split the transaction."), message: String(describing: error))
				return .failed
			}
		}
	}

	/// "Create Offsetting Entry": one manual transaction in the offline account for each row.
	/// The rows are those the list shows, so a part of a split gives an entry with the amount of the part.
	func createOffsettingEntries(of ids: Set<UUID>, in accountID: UUID) {
		guard let target = ledger.account(accountID) else { return }
		do {
			commit((transactions: try ledger.offsettingEntries(of: ids.compactMap { ledger.row($0) }, into: target), parts: []))
		} catch {
			alert = AlertMessage(title: String(localized: "Could not create the offsetting entries."),
				message: String(localized: "The amount of a selected transaction has no opposite amount that the app can store."))
		}
	}

	func delete(transactions ids: Set<UUID>) {
		guard !refusePartDeletion(in: ids) else { return }
		guard let store else { return }
		do {
			let accounts = try ledger.followingBankBalance(saving: [], deleting: ids)
			try store.deleteTransactions(Array(ids), accounts: accounts)
			ledgerChange = "delete rows=\(ids.count)"
			for a in accounts { ledger.upsert(a) }
			ledger.remove(transactionIDs: ids)
			selectedTransactions.subtract(ids)
		} catch {
			alert = AlertMessage(title: String(localized: "Could not delete the transactions."), message: String(describing: error))
		}
	}

	// MARK: Accounts and groups

	/// Saves the account. Marking it as closed also stores its clearing entry, and reopening it removes the entry that
	/// the user did not change, each in one write with the account.
	func save(account: Account) {
		guard let store else { return }
		let wasClosed = ledger.account(account.id)?.isClosed
		do {
			#if DEBUG || PERF_HARNESS
			if failsNextAccountSave {
				failsNextAccountSave = false
				throw CocoaError(.fileWriteOutOfSpace)
			}
			#endif
			var saved = account
			var entry: Transaction?
			var removed: UUID?
			if account.isClosed, wasClosed == false {
				(saved, entry) = try ledger.closing(account, today: .today())
			} else if !account.isClosed, wasClosed == true {
				(saved, removed) = try ledger.reopening(account)
			}
			if let entry {
				try store.save([entry], accounts: [saved])
			} else if let removed {
				try store.deleteTransactions([removed], accounts: [saved])
			} else {
				try store.save(saved)
			}
			ledgerChange = "account closed=\(saved.isClosed) entry=\(entry != nil) removed=\(removed != nil)"
			// A closed account takes no refresh: it leaves the refreshes that wait, and the merge drops what a running one delivers.
			if saved.isClosed, wasClosed == false { sync.leaveOut(account: saved.id) }
			ledger.upsert(saved)
			if let value = saved.portfolioValue() { ledger.record(value) }
			if let entry { ledger.update([entry]) }
			if let removed {
				ledger.remove(transactionIDs: [removed])
				selectedTransactions.remove(removed)
			}
			ledger.replace()
		} catch {
			alert = AlertMessage(title: String(localized: "Could not save the account."), message: String(describing: error))
		}
	}

	/// Opens the "Add Account" assistant, or with `purpose` "Look for New Accounts..." or "Edit Login
	/// Data...". The new accounts go into `group`.
	/// `connecting` is the migrated account whose "Connect..." opened the assistant.
	func addAccount(group: UUID? = nil, purpose: AccountSetup.Purpose = .add, connecting: Account? = nil) {
		setup?.cancel()
		setup = AccountSetup(model: self, groupID: group, purpose: purpose, connecting: connecting)
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
		pin: Secret?, savePIN: Bool) throws {
		guard let store else { return }
		let (access, accounts) = try store.add(new, state: state, accounts: ledger.accountsToAdd(candidates, listed: listed, connecting: connecting))
		bankNotices.markShown(notices, from: access.bankName)
		let first = accounts.first { ledger.account($0.id) == nil } ?? accounts.first
		// The bank accepted the PIN at the login of the setup. "Look for New Accounts..." logged in with the
		// PIN of the access, which the broker keeps already.
		if let pin {
			do {
				try sync.broker.remember(pin, for: access.id, save: savePIN)
			} catch {
				alert = AlertMessage(title: String(localized: "Could not save the PIN."), message: String(describing: error))
			}
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

	/// "Edit Login Data...": stores the login name and the state of the login that the bank just accepted,
	/// for all accounts of the access, with the PIN of that login as the saved PIN when "Save PIN" is on and
	/// no saved PIN when it is off, in one transaction. The broker takes the PIN into memory and follows the
	/// database, and each refresh of the access that waits runs with the new login. Throws the error of the database, which the assistant shows, and
	/// then nothing changed.
	func updateLogin(_ access: Access, state: AccessState?, pin: Secret, savePIN: Bool) throws {
		guard let store else { throw CancellationError() }
		try store.updateLogin(of: access.id, loginName: access.loginName, state: state, savedPIN: savePIN ? pin : nil)
		accesses[access.id] = access
		sync.update(access, state: state)
		sync.broker.adopt(pin, for: access.id, saved: savePIN)
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

	/// "Add Account Group" stores a new group at the end of the section "Accounts" and puts its row in edit mode for
	/// the name. A `name` gives the group that name and no edit mode, for the seeded data of the debug builds.
	func addGroup(name: String? = nil) async {
		// The name and the place come from the ledger after the wait for the table, without a suspension up to the
		// upsert, so that a second "Add Account Group" during the wait sees the first group and takes "New group 2".
		let added: AccountGroup? = await replacingTable {
			guard let store else { return nil }
			var g = ledger.newAccountGroup()
			if let name { g.name = name }
			do {
				try store.save(g)
			} catch {
				alert = AlertMessage(title: String(localized: "Could not save the account group."), message: String(describing: error))
				return nil
			}
			ledger.upsert(g)
			selection = .group(g.id)
			return g
		}
		if let added, name == nil {
			showsAccountsSection = true
			namingRow = .group(added.id)
		}
	}

	func save(group: AccountGroup) {
		guard let store else { return }
		do {
			try store.save(group)
			ledger.upsert(group)
		} catch {
			alert = AlertMessage(title: String(localized: "Could not save the account group."), message: String(describing: error))
		}
	}

	/// The disclosure triangle of a group row. The row can call it with the group of an earlier drawing, so the group
	/// comes from the ledger: a copy from the drawing before a rename in the sidebar would store the old name again.
	func setExpanded(group id: UUID, _ expanded: Bool) {
		guard var g = ledger.group(id), g.isExpanded != expanded else { return }
		g.isExpanded = expanded
		save(group: g)
	}

	/// "Move to Group" and a drop on a group row put the account at the end of the group.
	func move(account id: UUID, toGroup groupID: UUID?) {
		guard ledger.account(id).map({ $0.groupID != groupID }) == true else { return }
		move(treeItem: id, into: groupID, at: ledger.accountTree(in: groupID).count)
	}

	/// Moves a group or an account to the gap `index` among the rows of `parent` in the section "Accounts".
	func move(treeItem id: UUID, into parent: UUID?, at index: Int) {
		let change = ledger.move(treeItem: id, into: parent, at: index)
		guard !change.isEmpty else { return }
		// Accounts with rows that come into or leave the open group view insert or remove all of them in place,
		// which removes shown rows (issue #135), so such a move comes with a new table.
		if case let .group(shown) = tableKey.selection {
			var moved = ledger
			moved.apply(change)
			let entering = ledger.accountIDs(inGroupTree: shown).symmetricDifference(moved.accountIDs(inGroupTree: shown))
			if !entering.isDisjoint(with: ledger.accountsWithTransactions) {
				Task { await replacingTable { moveNow(treeItem: id, into: parent, at: index) } }
				return
			}
		}
		moveNow(treeItem: id, into: parent, at: index)
	}

	/// Reads the rows when the move happens, so that a refresh that stored an account meanwhile keeps its balance,
	/// its time, and its kind, and the move changes only the group and the place in it.
	private func moveNow(treeItem id: UUID, into parent: UUID?, at index: Int) {
		let change = ledger.move(treeItem: id, into: parent, at: index)
		guard let store, !change.isEmpty else { return }
		do {
			try store.save(groups: change.groups, accounts: change.accounts)
			ledgerChange = "move groups=\(change.groups.count) accounts=\(change.accounts.count)"
			ledger.apply(change)
		} catch {
			alert = AlertMessage(title: String(localized: "Could not move the account."), message: String(describing: error))
		}
	}

	/// "Remove saved PIN": the next refresh of every account of the access asks for the PIN.
	func removeSavedPIN(of access: UUID) {
		do {
			try sync.broker.removeSavedPIN(of: access)
		} catch {
			let title = accesses[access].flatMap(secretName(of:)) == nil ? String(localized: "Could not remove the saved PIN.")
				: String(localized: "Could not remove the saved login data.")
			alert = AlertMessage(title: title, message: String(describing: error))
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
			forgetInHistory(.account(id))
		} catch {
			alert = AlertMessage(title: String(localized: "Could not remove the account."), message: String(describing: error))
		}
	}

	func remove(group id: UUID) async {
		guard let store else { return }
		do {
			// The accounts and subgroups take the place of the group in the group above it ("Remove an account group").
			let change = ledger.removal(ofGroup: id)
			try store.deleteGroup(id, moving: change)
			await replacingTable {
				ledger.remove(group: id, moving: change)
				filter.dropMissing(in: ledger)
				if selection == .group(id) { selection = nil }
			}
			forgetInHistory(.group(id))
		} catch {
			alert = AlertMessage(title: String(localized: "Could not remove the account group."), message: String(describing: error))
		}
	}

	// MARK: Refresh

	/// The connector of the app, or in a debug build the fake helper that `MONETEN_FINTS_HELPER` names,
	/// so that the setup and the refresh run without a bank.
	private static func makeFinTSConnector() -> FinTSConnector {
		#if DEBUG
		if let path = ProcessInfo.processInfo.environment["MONETEN_FINTS_HELPER"], !path.isEmpty {
			return FinTSConnector(debugHelper: path, bankList: { BankDataUpdates.updater?.bankList() })
		}
		#endif
		return FinTSConnector(bankList: { BankDataUpdates.updater?.bankList() })
	}

	/// "Refresh All Accounts", "Refresh Account", and "Refresh Accounts", and with `enforced` the commands
	/// that ask the bank for the full history. Offline the accounts keep their last state, and the app says
	/// why nothing happens.
	func refresh(_ scope: RefreshScope, enforced: Bool = false) {
		// Before the network, because a connection would not help: the accounts need a bank access first.
		if let offer = ledger.connectOffer(scope, selected: selectedAccount?.id) { return offerConnect(offer) }
		guard autoRefresh.isOnline else {
			alert = AlertMessage(title: SyncFailure.offline.message, message: String(localized: "Connect this Mac to the Internet and try again."))
			return
		}
		refresh(ledger.refreshAccounts(scope), enforced: enforced)
	}

	/// The alert of a refresh command that found only accounts without a bank access, with "Connect..." as in their header.
	private func offerConnect(_ offer: ConnectOffer) {
		let account = offer.account
		alert = AlertMessage(
			title: offer.count == 1 ? String(localized: "“\(account.name)” is not connected to a bank yet.") : String(localized: "The accounts are not connected to a bank yet."),
			message: offer.count == 1 ? String(localized: "An account without a bank access cannot be refreshed. Connect sets up the access to its bank.")
				: String(localized: "An account without a bank access cannot be refreshed. Connect sets up the access for “\(account.name)”, and the assistant offers the other accounts of the same bank."),
			action: AlertAction(title: String(localized: "Connect...")) { [weak self] in
				// Only an unlocked app with no sheet, and none that comes back after the unlock, opens the assistant.
				guard let self, phase == .unlocked, sheet == nil, returningSheet == nil, let current = ledger.account(account.id),
					ledger.connectOffer(.account(current.id), selected: current.id) != nil else { return }
				addAccount(group: current.groupID, connecting: current)
			})
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
		DebugHarness.shared?.log("autorefresh", ("accesses", .count(plan.count)), ("accounts", .count(plan.values.map(\.count).reduce(0, +))))
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
			MainActor.assumeIsolated {
				self?.autoRefresh.isOnline = path.status == .satisfied
				// The first update that finds a connection starts the bank data, so the look at launch does
				// not run before the app knows the state of the network.
				if path.status == .satisfied { BankDataUpdates.start { [weak self] in self?.autoRefresh.isOnline ?? false } }
			}
		}
		pathMonitor.start(queue: .main)
	}

	/// The PIN sheet, the dialog "Two-Factor Authentication", and the alerts live in the main window. A
	/// refresh from the menu bar can ask or fail while that window is closed, so they bring the window back.
	/// `asking` tells whether the dialog of a refresh was open before, so that the trail logs each change once.
	private func showDialogsInMainWindow(asking: Bool = false) {
		withObservationTracking { _ = (sync.broker.current, alert, crashes.pending) } onChange: { [weak self] in
			Task { @MainActor [weak self] in
				guard let self else { return }
				let asks = self.sync.broker.current != nil
				if asks != asking { Trail.log("dialog refresh \(asks ? "shown" : "closed")") }
				if asks || self.alert != nil || self.crashes.pending != nil {
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

	/// A command that would only offer "Connect..." is enabled too, so that it says why it cannot refresh. With
	/// `offeringConnect` false it counts only accounts to refresh, for a place that shows no alert.
	func canRefresh(_ scope: RefreshScope, offeringConnect: Bool = true) -> Bool {
		phase == .unlocked && !isStoringMigration
			&& (ledger.canRefresh(scope) || offeringConnect && ledger.connectOffer(scope, selected: nil) != nil)
	}

	/// Starts one refresh per access, with the state its connector returned last. Only a refresh that the
	/// user started shows an alert.
	func refresh(_ plan: [UUID: [AccountRequest]], attended: Bool = true, enforced: Bool = false) {
		guard !isStoringMigration, let store else { return }
		#if DEBUG || PERF_HARNESS
		// A run of the debug harness reaches only the made-up bank and local services, also from a button that no command
		// checks, such as "Refresh All Accounts" in the popover of the menu bar icon (issue #498). With the opt-in of the
		// bank tests, a refresh here reaches a real bank through FinTS too. HarnessRun.mayRun is then the guard: the
		// harness takes no command that presses a control, unlocks, or refreshes, so only the person at the Mac or the
		// automatic refresh starts one.
		if let harness = DebugHarness.shared, !harness.mayRefresh(plan) {
			return harness.log("refresh refused", ("attended", .flag(attended)))
		}
		#endif
		let requests = plan.compactMap { id, accounts in accesses[id].map { ($0, accounts) } }.sorted { $0.0.bankName < $1.0.bankName }
		for (access, accounts) in requests {
			guard let connector = connector(for: access.source) else {
				if attended { alert = AlertMessage(title: String(localized: "Could not refresh \(access.bankName)."), message: String(localized: "Moneten has no connector for this access yet.")) }
				continue
			}
			do {
				sync.refresh(RefreshRequest(access: access, state: try store.state(of: access.id), accounts: accounts, enforced: enforced), with: connector,
					attended: attended)
				Trail.log("refresh start access=\(trailNumber(of: access.id)) accounts=\(accounts.count) attended=\(attended)")
			} catch {
				if attended { alert = AlertMessage(title: String(localized: "Could not refresh \(access.bankName)."), message: String(describing: error)) }
			}
		}
	}

	private func connector(for source: AccessSource) -> (any BankConnector)? {
		switch source {
		case .fints: fints
		case let .extension(id): extensions.connector(for: id) ?? extensionConnectors[id] ?? CheckedAtStart { throw SyncFailure.unsupported(String(localized: "The extension \(id) is not installed.")) }
		case .finAPI: nil
		}
	}

	/// Stores how a refresh ended: the new state of the access, and the time or the error of each account.
	private func recordRefresh(of access: UUID, state: AccessState?, accounts results: [UUID: AccountRefresh], attended: Bool) {
		guard let store else { return }
		let accounts = ledger.recorded(results, of: access, attended: attended)
		guard state != nil || !accounts.isEmpty else { return }
		do {
			try store.recordRefresh(of: access, state: state, accounts: accounts)
			for a in accounts {
				ledgerChange = "account refreshed"
				ledger.upsert(a)
			}
		} catch {
			report(AlertMessage(title: String(localized: "Could not save the result of the refresh."), message: String(describing: error)), attended: attended)
		}
	}

	/// The calibration that `account` proposes now. None while the refresh of its access runs or failed for it.
	func proposedCalibration(of account: Account) -> CalibrationProposal? {
		ledger.proposedCalibration(of: account, today: .today(), refresh: account.accessID.flatMap { sync.states[$0] } ?? .idle)
	}

	/// The step of the first running refresh, for the status line.
	var refreshStatus: String? {
		let running = sync.states.compactMap { id, state in state.isRunning ? (accesses[id]?.bankName ?? String(localized: "the bank"), state) : nil }.sorted { $0.0 < $1.0 }
		guard let (bank, state) = running.first else { return nil }
		switch state {
		case let .fetching(done, of): return String(localized: "Getting transactions from \(bank) (\(min(done + 1, of)) of \(of))...")
		case .needsUser(_, waiting: true, _): return String(localized: "\(bank) waits for your input...")
		case .needsUser: return String(localized: "\(bank) needs your input...")
		default: return String(localized: "Connecting to \(bank)...")
		}
	}

	// MARK: Categories

	/// `name` is the accepted name of `Ledger.checkCategoryName(_:in:renaming:)`, which the sheet checks before it calls this.
	func addCategory(name: String, parentID: UUID?, assigning ids: Set<UUID> = []) async {
		let position = (ledger.childCategories(of: parentID).map(\.position).max() ?? -1) + 1
		let c = Domain.Category(parentID: parentID, position: position, name: name)
		await replacingTable {
			save(category: c)
			if !ids.isEmpty, ledger.category(c.id) != nil { assign(category: c.id, to: ids) }
			selection = .category(c.id)
		}
	}

	/// The disclosure triangle of a category group, with the category from the ledger, as in `setExpanded(group:_:)`.
	func setExpanded(category id: UUID, _ expanded: Bool) {
		guard var c = ledger.category(id), c.isExpanded != expanded else { return }
		c.isExpanded = expanded
		save(category: c)
	}

	/// "Add Category Group" stores a new group beside the selection and puts its row in edit mode for the name.
	/// A collapsed group that gets it expands, so that the row is on screen.
	func addCategoryGroup() async {
		// The selection of the command, read before the wait, in which an earlier "Add Category Group" selects its group.
		let selected: UUID? = if case let .category(id) = selection { id } else { nil }
		// The name and the place come from the ledger after the wait, as in `addGroup(name:)`.
		let added: Domain.Category? = await replacingTable {
			let c = ledger.newCategoryGroup(selected: selected)
			save(category: c)
			guard ledger.category(c.id) != nil else { return nil }
			if let parentID = c.parentID, var parent = ledger.category(parentID), !parent.isExpanded {
				parent.isExpanded = true
				save(category: parent)
			}
			selection = .category(c.id)
			return c
		}
		if let added {
			showsCategoriesSection = true
			namingRow = .category(added.id)
		}
	}

	/// Ends edit mode of the row and stores the typed name. A nil `typed`, from Escape, keeps the name the row had,
	/// and so do a name that is empty or only spaces and the same name again.
	func endNaming(_ row: SidebarSelection, typed: String?) {
		if namingRow == row { namingRow = nil }
		guard let typed else { return }
		switch row {
		case let .group(id):
			guard var g = ledger.group(id), let name = GroupName.edited(typed, keeping: g.name) else { return }
			g.name = name
			save(group: g)
		case let .category(id):
			// A name that another entry of the group has keeps the old name, also when the focus leaves the row with it.
			guard var c = ledger.category(id), let name = GroupName.edited(typed, keeping: c.name),
				ledger.checkCategoryName(name, in: c.parentID, renaming: id) != .taken else { return }
			c.name = name
			save(category: c)
		default: break
		}
	}

	/// Whether Return keeps the row in edit mode: the typed name of a category group that another entry of its group has
	/// ("Name of a category"). The parent of the group, for the note under the field, or nil for the top level.
	func takenName(_ row: SidebarSelection, typed: String) -> (taken: Bool, parentID: UUID?) {
		guard case let .category(id) = row, let c = ledger.category(id) else { return (false, nil) }
		return (ledger.checkCategoryName(typed, in: c.parentID, renaming: id) == .taken, c.parentID)
	}

	func save(category: Domain.Category) {
		guard let store else { return }
		// A rename or a move by the user ends the record of the starter set.
		let category = ledger.userSaved(category)
		do {
			try store.save(category)
			ledger.upsert(category)
			ledger.replace()
		} catch {
			alert = AlertMessage(title: String(localized: "Could not save the category."), message: String(describing: error))
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
			for id in removed { forgetInHistory(.category(id)) }
		} catch {
			alert = AlertMessage(title: String(localized: "Could not remove the category."), message: String(describing: error))
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
		if changed.isEmpty, let position = rule.stoppedRegexPosition {
			alert = AlertMessage(title: RuleStop.message(position: position), message: "")
			return
		}
		let saved = await replacingTable { () -> Int? in
			// A run saves only into the database it started with. A lock closes it, and an unlock opens a new one.
			guard self.store === store else { return nil }
			// A stopped rule gives no rows, also when a row that changed during the run stopped it.
			let rows = RuleApplier.rebase(changed, from: ledger, onto: self.ledger, category: category, rule: rule, mode: mode)
			return commit((transactions: rows, parts: [])) ? rows.count : nil
		}
		if let position = rule.stoppedRegexPosition {
			alert = AlertMessage(title: RuleStop.message(position: position), message: "")
		} else if let saved { alert = AlertMessage(title: String(localized: "Categorized transactions: \(saved)"), message: "") }
	}

	// MARK: Migration

	func runMigration(plan: MoneyMoneyMigration.Plan, cancel: MigrationCancel,
		progress: @escaping @Sendable (MoneyMoneyMigration.Progress) -> Void) async throws -> MoneyMoneyMigration.Plan {
		// The sheet swallows a CancellationError and keeps waiting, so a refusal must be an error that it shows.
		guard let store else { throw MigrationRefused(description: String(localized: "The database is not open.")) }
		guard !isTransferringTransactions, !isApplyingRule else {
			throw MigrationRefused(description: String(localized: "Another import, an export, or a rule runs. Start this import again when that has ended."))
		}
		isStoringMigration = true
		defer {
			isStoringMigration = false
			Task { await extensions.applyUpdates() }
		}
		return try await sync.withRefreshesPaused {
			while !self.extensions.working.isEmpty { try await Task.sleep(for: .milliseconds(50)) }
			try Task.checkCancellation()
			// Another store, such as after a lock and an unlock during the wait, is not the one the plan was read against.
			guard self.store === store else { throw MigrationRefused(description: String(localized: "The database is not open.")) }
			let starters = replaceableStarterCategories.map(\.id)
			// A cancel of this task reaches the cancel token through importMigration.
			let imported = try await store.importMigration(plan, replacing: starters, cancel: cancel, progress: progress)
			progress(.init(step: .finishing))
			try await reloadAfterImport()
			return imported
		}
	}

	/// Loads the ledger and the bank accesses again after a migration or a complete import replaced the table, and
	/// selects the first group when the selection is gone.
	func reloadAfterImport() async throws {
		guard let store else { return }
		while true {
			let revision = ledgerRevision
			let (loaded, loadedAccesses, loadedSearches) = try await Task.detached {
				(try store.loadLedger(), try store.accesses(), try store.savedSearches())
			}.value
			guard self.store === store else { return }
			let applied = await replacingTable {
				guard ledgerRevision == revision else { return false }
				ledgerChange = "load"
				ledger = loaded
				accesses = Dictionary(uniqueKeysWithValues: loadedAccesses.map { ($0.id, $0) })
				// A complete import brings saved searches.
				savedSearches = loadedSearches
				filter.dropMissing(in: ledger)
				if case let .category(id) = selection, ledger.category(id) == nil { selection = nil }
				// A complete import replaces the account groups.
				if case let .group(id) = selection, ledger.group(id) == nil { selection = nil }
				if selection == nil { selection = firstSidebarRow }
				return true
			}
			if applied { return }
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

	/// The open table shows pending rows or split parts that a correction can remove, or a position of
	/// the account that the delivered positions no longer hold.
	private func removesShownRows(_ result: RefreshResult, of accountID: UUID) -> Bool {
		if let portfolios = tableKey.portfolios {
			guard portfolios.contains(accountID), let delivered = result.holdings else { return false }
			let shown = ledger.holdings(of: [accountID])
			let kept = Set(Holding.identify(delivered, stored: shown).map(\.id))
			return shown.contains { !kept.contains($0.id) }
		}
		let ledger = self.ledger
		return visibleTransactions.contains { $0.accountID == accountID && ($0.isPending || ledger.part($0.id) != nil) }
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

/// A row that the table of `key` scrolls to.
struct RevealedRow {
	let id: UUID
	let key: TableKey
	let request: Int
}

struct AlertMessage: Identifiable {
	let id = UUID()
	var title: String
	var message: String
	/// A button before "Cancel", such as "Connect..." of a refresh without a bank access. Without it the alert has only OK.
	var action: AlertAction?
}

/// The button of an alert that does something. It runs once the alert has slid out of the window.
struct AlertAction {
	var title: String
	var run: @MainActor () -> Void
}

enum SheetKind: Identifiable, Equatable {
	case newAccount
	/// `assigning` are the transactions that "Add category" in "Assign Category" moves into it.
	case newCategory(assigning: Set<UUID> = [])
	/// The category picker of ⌘K for these transactions.
	/// `accounts` are those of the transactions, looked up once when the picker opens.
	case assignCategory(Set<UUID>, accounts: Set<UUID>)
	case accountSettings(UUID)
	/// The calibration window that the proposal in the account header opens.
	case calibration(UUID)
	case groupSettings(UUID)
	case categorySettings(UUID)
	case transaction(UUID?)
	case split(Transaction)
	case undoSplit(UUID)
	case comment(Set<UUID>)
	case migration
	case exportAllData
	case fileImport(FileImport)
	case exporting
	case setPassword
	case changePassword
	/// The name of a new saved search, with the search field and the filter bar that are on screen.
	case saveSearch
	case renameSearch(UUID)

	var id: String { String(describing: self) }
}

/// Why a migration did not start. The sheet shows it, and nothing was stored.
private struct MigrationRefused: Error, CustomStringConvertible {
	let description: String
}
