import Foundation

/// What the content view shows: everything, one account, one account group, or one category.
public enum LedgerScope: Hashable, Sendable {
	case account(UUID)
	case accountGroup(UUID)
	case category(UUID)
}

/// All accounts, categories, and transactions in memory, with the lookups that the views need.
///
/// The app loads the ledger once after unlocking and changes it together with the database.
public struct Ledger: Sendable {
	public private(set) var groups: [AccountGroup] = []
	public private(set) var accounts: [Account] = []
	public private(set) var categories: [Category] = []
	public private(set) var transactions: [Transaction] = []
	/// The recorded values of each portfolio, the oldest first.
	private var portfolioHistory: [UUID: [PortfolioValue]] = [:]
	/// The positions of each portfolio, in the order of `Holding.isOrdered`.
	private var holdingsByAccount: [UUID: [Holding]] = [:]

	private var partsByTransaction: [UUID: [SplitPart]] = [:]
	private var partRows: [UUID: [Transaction]] = [:]
	private var transactionByPart: [UUID: UUID] = [:]

	private var transactionIndex: [UUID: Int] = [:]
	private(set) var searchText: [UUID: String] = [:]
	/// The number of new transactions per account.
	public private(set) var newTransactionCounts: [UUID: Int] = [:]
	/// The accounts that have at least one transaction.
	public private(set) var accountsWithTransactions: Set<UUID> = []

	public init(groups: [AccountGroup] = [], accounts: [Account] = [], categories: [Category] = [], transactions: [Transaction] = [],
		portfolioValues: [PortfolioValue] = [], holdings: [Holding] = [], parts: [SplitPart] = []) {
		self.groups = groups
		self.accounts = accounts
		self.categories = categories
		self.transactions = transactions
		partsByTransaction = Dictionary(grouping: parts, by: \.transactionID).mapValues { $0.sorted { $0.position < $1.position } }
		for v in portfolioValues { record(v) }
		for (id, positions) in Dictionary(grouping: holdings, by: \.accountID) { holdingsByAccount[id] = positions.sorted(by: Holding.isOrdered) }
		rebuildIndexes()
	}

	private mutating func rebuildIndexes() {
		sortAndIndex()
		let accountsByID = Dictionary(uniqueKeysWithValues: accounts.map { ($0.id, $0) })
		let names = categoryNames
		partsByTransaction = partsByTransaction.filter { transactionIndex[$0.key] != nil }
		searchText = [:]
		partRows = [:]
		transactionByPart = [:]
		for t in transactions { rebuildRows(of: t, account: accountsByID[t.accountID], categoryNames: names) }
		countNew()
	}

	/// The order and the positions only. The search texts of unchanged rows stay as they are.
	private mutating func sortAndIndex() {
		transactions.sort { ($0.bookingDate, $0.createdAt) > ($1.bookingDate, $1.createdAt) }
		transactionIndex = Dictionary(uniqueKeysWithValues: transactions.enumerated().map { ($0.element.id, $0.offset) })
	}

	private mutating func countNew() {
		var counts: [UUID: Int] = [:]
		var used: Set<UUID> = []
		for t in transactions {
			used.insert(t.accountID)
			if t.isNew { counts[t.accountID, default: 0] += 1 }
		}
		newTransactionCounts = counts
		accountsWithTransactions = used
	}

	/// The name of each category, looked up once for the search texts of many rows. The key nil holds the name
	/// of the default category, which a row without a category is in.
	private var categoryNames: [UUID?: String] {
		var names = Dictionary(uniqueKeysWithValues: categories.map { (Optional($0.id), $0.name) })
		names[nil] = defaultCategory?.name
		return names
	}

	private mutating func rebuildRows(of t: Transaction, account: Account?, categoryNames: [UUID?: String]) {
		if let old = partRows.removeValue(forKey: t.id) {
			for row in old { searchText[row.id] = nil; transactionByPart[row.id] = nil }
		}
		searchText[t.id] = SearchText.of(t, account: account, categoryName: categoryNames[t.categoryID])
		guard let parts = partsByTransaction[t.id] else { return }
		let originalAmounts = Self.amountTexts(t.amountMinor, decimals: t.amount.decimalPlaces).joined(separator: "\u{1}")
		partRows[t.id] = parts.map { part in
			var row = t
			row.id = part.id
			row.amountMinor = part.amountMinor
			row.categoryID = part.categoryID
			row.comment = part.comment
			row.categorizedBy = .manual
			transactionByPart[part.id] = t.id
			searchText[part.id] = SearchText.of(row, account: account, categoryName: categoryNames[row.categoryID]) + "\u{1}" + originalAmounts
			return row
		}
	}

	/// Builds the search texts of the rows that `isAffected` picks again, after a change of a name or a number they hold.
	private mutating func refreshSearchText(where isAffected: (Transaction) -> Bool) {
		let accountsByID = Dictionary(uniqueKeysWithValues: accounts.map { ($0.id, $0) })
		let names = categoryNames
		for t in transactions where isAffected(t) || (partRows[t.id]?.contains(where: isAffected) ?? false) {
			rebuildRows(of: t, account: accountsByID[t.accountID], categoryNames: names)
		}
	}

	/// An amount as a user types it into the search: without trailing zeros ("-23.4", "-23,4") and
	/// with two decimals ("-23,40", "-23.40"). Integer arithmetic, because formatting a Decimal or a
	/// Double for each of 50,000 transactions took most of the time of building the ledger.
	static func amountTexts(_ minor: Int64, decimals: Int) -> [String] {
		let sign = minor < 0 ? "-" : ""
		let magnitude = minor.magnitude
		// 10^19 does not fit in UInt64. No currency has that many decimals.
		let decimals = min(max(0, decimals), 18)
		var scale: UInt64 = 1
		for _ in 0..<decimals { scale *= 10 }
		let whole = magnitude / scale
		let digits = decimals > 0 ? String(magnitude % scale) : ""
		let fraction = String(repeating: "0", count: decimals - digits.count) + digits
		var trimmed = fraction
		while trimmed.hasSuffix("0") { trimmed.removeLast() }
		let plain = trimmed.isEmpty ? "\(sign)\(whole)" : "\(sign)\(whole).\(trimmed)"
		// Two decimals, rounded half away from zero for a currency with more. Division before any
		// multiplication, so that no amount of an Int64 overflows.
		let two: String
		if decimals <= 2 {
			two = "\(sign)\(whole)." + fraction + String(repeating: "0", count: 2 - decimals)
		} else {
			let divisor = scale / 100
			let remainder = magnitude % divisor
			let cents = magnitude / divisor + (remainder >= divisor - remainder ? 1 : 0)
			two = "\(sign)\(cents / 100)." + (cents % 100 < 10 ? "0" : "") + "\(cents % 100)"
		}
		return [plain, plain.replacingOccurrences(of: ".", with: ","), two.replacingOccurrences(of: ".", with: ","), two]
	}

	// MARK: Lookups

	public func account(_ id: UUID) -> Account? { accounts.first { $0.id == id } }
	public func group(_ id: UUID) -> AccountGroup? { groups.first { $0.id == id } }
	public func category(_ id: UUID) -> Category? { categories.first { $0.id == id } }
	public func transaction(_ id: UUID) -> Transaction? { transactionIndex[id].map { transactions[$0] } }
	public func row(_ id: UUID) -> Transaction? {
		if let original = transactionByPart[id] { return partRows[original]?.first { $0.id == id } }
		return partsByTransaction[id] == nil ? transaction(id) : nil
	}

	public func parts(of transactionID: UUID) -> [SplitPart] { partsByTransaction[transactionID] ?? [] }

	public func part(_ rowID: UUID) -> SplitPart? {
		guard let id = transactionByPart[rowID] else { return nil }
		return partsByTransaction[id]?.first { $0.id == rowID }
	}

	/// The recorded values of a portfolio, the oldest first.
	public func portfolioValues(of accountID: UUID) -> [PortfolioValue] { portfolioHistory[accountID] ?? [] }

	/// The positions of the accounts, by the name of the security without regard to case, across the accounts.
	public func holdings(of accountIDs: [UUID]) -> [Holding] {
		let all = accountIDs.flatMap { holdingsByAccount[$0] ?? [] }
		return accountIDs.count > 1 ? all.sorted(by: Holding.isOrdered) : all
	}

	/// The accounts whose positions the view shows in place of transactions: the account when it is a portfolio,
	/// or every account of the group tree when all of them are portfolios, ordered by position. Nil otherwise.
	/// A portfolio with transactions, such as one taken over from MoneyMoney with its rows, keeps its transaction
	/// list, so no row disappears, and the view never swaps a filled transaction table for the positions.
	public func portfolioAccounts(in scope: LedgerScope) -> [UUID]? {
		let ids: Set<UUID>
		switch scope {
		case let .account(id): ids = [id]
		case let .accountGroup(id): ids = accountIDs(inGroupTree: id)
		case .category: return nil
		}
		let found = ids.compactMap(account).sorted { $0.position < $1.position }
		guard !found.isEmpty, found.allSatisfy({ $0.kind == .portfolio && !accountsWithTransactions.contains($0.id) }) else { return nil }
		return found.map(\.id)
	}

	/// The profit or loss of all positions of the accounts with a purchase price, in the currency of each value.
	public func totalGain(of accountIDs: [UUID]) -> MoneySums {
		var sums = MoneySums()
		for id in accountIDs {
			guard let currency = account(id)?.currency else { continue }
			for h in holdingsByAccount[id] ?? [] { if let gain = h.gain(in: currency) { sums.add(gain.amount) } }
		}
		return sums
	}

	/// The bank balance of each open portfolio that its history does not hold for the day of that
	/// balance: a portfolio migrated before the app kept a history, or one whose record failed to
	/// save. Once recorded, the list is empty.
	public var missingPortfolioValues: [PortfolioValue] {
		accounts.filter { !$0.isClosed }.compactMap { $0.portfolioValue() }.filter { !portfolioValues(of: $0.accountID).contains($0) }
	}

	public var defaultCategory: Category? { categories.first { $0.isDefault } }

	public func childGroups(of parent: UUID?) -> [AccountGroup] {
		groups.filter { $0.parentID == parent }.sorted { $0.position < $1.position }
	}

	public func accounts(inGroup group: UUID?) -> [Account] {
		accounts.filter { $0.groupID == group }.sorted { $0.position < $1.position }
	}

	/// The position after the last group or account of a group.
	public func nextTreePosition(in parent: UUID?) -> Int {
		(accountTree(in: parent).map(\.position).max() ?? -1) + 1
	}

	/// The subgroups and accounts of a group in one list, ordered by position, as the sidebar shows them.
	/// At the same position a group comes first.
	public func accountTree(in parent: UUID?) -> [AccountTreeItem] {
		let items = childGroups(of: parent).map(AccountTreeItem.group) + accounts(inGroup: parent).map(AccountTreeItem.account)
		return items.enumerated().sorted { a, b in
			(a.element.position, a.offset) < (b.element.position, b.offset)
		}.map(\.element)
	}

	/// The accounts of a group and of all its subgroups.
	public func accountIDs(inGroupTree group: UUID) -> Set<UUID> {
		var ids = Set(accounts(inGroup: group).map(\.id))
		for child in childGroups(of: group) { ids.formUnion(accountIDs(inGroupTree: child.id)) }
		return ids
	}

	public func childCategories(of parent: UUID?) -> [Category] {
		categories.filter { $0.parentID == parent && !$0.isDefault }.sorted { $0.position < $1.position }
	}

	/// All categories from top to bottom as the sidebar shows them, with the default category last.
	public var categoriesInSidebarOrder: [Category] {
		var result: [Category] = []
		func walk(_ parent: UUID?) {
			for c in childCategories(of: parent) {
				result.append(c)
				walk(c.id)
			}
		}
		walk(nil)
		if let d = defaultCategory { result.append(d) }
		return result
	}

	/// The accounts whose transactions a category takes: the account or the accounts of the account group
	/// that it is restricted to, or nil when it has no restriction.
	public func allowedAccounts(of category: Category) -> Set<UUID>? {
		guard let r = category.restrictedToID else { return nil }
		return account(r) != nil ? [r] : accountIDs(inGroupTree: r)
	}

	/// A category group holds no transactions, and a category restricted to an account or account group
	/// takes only transactions of that account or of an account in that group.
	public func canAssign(_ category: Category, to transactions: [Transaction]) -> Bool {
		guard !category.isGroup else { return false }
		guard let allowed = allowedAccounts(of: category) else { return true }
		return transactions.allSatisfy { allowed.contains($0.accountID) }
	}

	/// Moves a category, or a group with everything in it, into `parent` at the gap `index` of its
	/// children as the sidebar shows them before the move. Returns the categories whose parent or
	/// position changes, with positions without gaps in the old and the new parent. Transactions keep
	/// their category. "Uncategorized" does not move, and only a group or the top level takes a category.
	public func move(category id: UUID, into parent: UUID?, at index: Int) -> [Category] {
		guard var moved = category(id), !moved.isDefault else { return [] }
		if let parent {
			guard category(parent)?.isGroup == true, !categoryIDs(inTree: id).contains(parent) else { return [] }
		}
		var target = childCategories(of: parent)
		var gap = min(max(index, 0), target.count)
		if let old = target.firstIndex(where: { $0.id == id }) {
			target.remove(at: old)
			if old < gap { gap -= 1 }
		}
		let oldParent = moved.parentID
		moved.parentID = parent
		target.insert(moved, at: gap)
		var lists = [target]
		if oldParent != parent { lists.append(childCategories(of: oldParent).filter { $0.id != id }) }
		var changed: [Category] = []
		for list in lists {
			for (position, var c) in list.enumerated() {
				c.position = position
				if c != category(c.id) { changed.append(c) }
			}
		}
		return changed
	}

	/// The groups that accept a move to their end, in sidebar order.
	public func destinationGroups(forCategory id: UUID) -> [Category] {
		categoriesInSidebarOrder.filter { group in
			group.isGroup && !move(category: id, into: group.id, at: childCategories(of: group.id).count).isEmpty
		}
	}

	/// Whether a view or a filter on one of the categories `roots` shows other rows after the category `id` moves into `parent`.
	public func changesShownRows(moving id: UUID, into parent: UUID?, roots: [UUID]) -> Bool {
		guard let old = category(id) else { return false }
		let crossesRoot = roots.contains { root in
			let tree = categoryIDs(inTree: root)
			return (old.parentID.map(tree.contains) ?? false) != (parent.map(tree.contains) ?? false)
		}
		guard crossesRoot else { return false }
		let moved = categoryIDs(inTree: id)
		return transactions.contains { t in
			(partRows[t.id] ?? [t]).contains { $0.categoryID.map(moved.contains) ?? false }
		}
	}

	/// The categories that the category picker offers for a search, in sidebar order and without groups.
	public func categories(matching query: String) -> [Category] {
		let folded = TextFolding.fold(query.trimmingCharacters(in: .whitespaces))
		return categoriesInSidebarOrder.filter { !$0.isGroup && (folded.isEmpty || TextFolding.fold($0.name).contains(folded)) }
	}

	/// The accounts that hold these transactions, for `categories(matching:assignableTo:)`.
	public func accountIDs(ofTransactions ids: Set<UUID>) -> Set<UUID> {
		Set(ids.compactMap { row($0)?.accountID })
	}

	/// The same categories without those that the transactions of `accounts` cannot take. The picker passes
	/// the accounts of the selection, so a keystroke costs the same for 2 selected rows and for 50,000.
	public func categories(matching query: String, assignableTo accounts: Set<UUID>) -> [Category] {
		categories(matching: query).filter { allowedAccounts(of: $0).map(accounts.isSubset) ?? true }
	}

	public func categoryIDs(inTree root: UUID) -> Set<UUID> {
		var ids: Set<UUID> = [root]
		for c in categories where c.parentID == root { ids.formUnion(categoryIDs(inTree: c.id)) }
		return ids
	}

	/// The category of a transaction, with transactions without a category in the default category.
	public func effectiveCategoryID(of t: Transaction) -> UUID? {
		t.categoryID ?? defaultCategory?.id
	}

	/// A path such as "Living › Groceries".
	public func categoryPath(_ id: UUID?) -> String {
		guard let id, var c = category(id) else { return defaultCategory?.name ?? "" }
		var names = [c.name]
		while let p = c.parentID, let parent = category(p) {
			names.insert(parent.name, at: 0)
			c = parent
		}
		return names.joined(separator: " › ")
	}

	// MARK: Balances

	public func transactions(ofAccount id: UUID) -> [Transaction] {
		transactions.filter { $0.accountID == id }
	}

	/// The balance in the sidebar: the reported balance where the account shows one, otherwise the computed one.
	/// A migrated account follows its transactions. Its initial balance makes the computed balance end at the
	/// balance of the source at the migration.
	public func balance(of account: Account) -> Money {
		account.reportedBalance ?? computedBalance(of: account)
	}

	/// The initial balance plus the transactions in the currency of the account that a balance counts.
	public func computedBalance(of account: Account, through day: Day? = nil) -> Money {
		var sum = account.initialBalanceMinor
		for t in transactions where t.accountID == account.id && account.isInBalance(t) {
			if let day, t.bookingDate > day { continue }
			sum += t.amountMinor
		}
		return Money(minorUnits: sum, currency: account.currency)
	}

	/// The calibration that an account of a bank access needs when its booked rows up to the day of the bank
	/// balance miss that balance. It compares through `Account.initialBalanceMeetingBankBalance(of:calendar:)`,
	/// the rule that derives the initial balance, so neither a pending row nor a row booked after that day
	/// raises one. Nil before the initial balance is set, because the next full refresh derives it. `refresh` is
	/// the state of the refresh of its access.
	public func proposedCalibration(of account: Account, today: Day, refresh: SyncState, calendar: Calendar = .current) -> CalibrationProposal? {
		// A refresh whose transactions failed stores the bank balance without the rows it covers. `refreshError`
		// tells it only once the app recorded the end, so the state of the refresh covers the time before. The rows
		// are read in place, because copying the rows of an account on each drawing of the header cost most of a
		// frame with 50,000 rows.
		guard account.source == .bank, account.kind != .portfolio, account.initialBalanceIsSet, account.refreshError == nil,
			!refresh.mayLackRows(of: account.id),
			let meeting = account.initialBalanceMeetingBankBalance(of: transactions.lazy.filter { $0.accountID == account.id }, calendar: calendar),
			meeting != account.initialBalanceMinor else { return nil }
		let difference = meeting - account.initialBalanceMinor
		return CalibrationProposal(difference: Money(minorUnits: difference, currency: account.currency),
			balanceToday: Money(minorUnits: computedBalance(of: account, through: today).minorUnits + difference, currency: account.currency))
	}

	/// The initial balance at which the computed balance at the end of `today` is `balanceToday`. Every computed
	/// balance moves by the same difference.
	public func calibratedInitialBalance(of account: Account, balanceToday: Int64, today: Day) -> Int64 {
		account.initialBalanceMinor + balanceToday - computedBalance(of: account, through: today).minorUnits
	}

	public func sum(ofGroup group: UUID) -> MoneySums {
		var sums = MoneySums()
		for id in accountIDs(inGroupTree: group) {
			if let a = account(id), !a.isClosed { sums.add(balance(of: a)) }
		}
		return sums
	}

	/// The amounts next to the categories in the sidebar, for their "Display in sidebar" on `today`, in one pass
	/// over the transactions. A row counts in its category and in each group above it, in the period and the
	/// currency of each. Rows in another currency stay in the category, and the status line of its list sums them
	/// for each currency. A category with "No amount" or a sum of zero has no entry.
	public func sidebarAmounts(today: Day) -> [UUID: Money] {
		let index = CategoryIndex(categories.map(\.id))
		// A row of category i adds to `targets[chains[i]]`, which holds i and each group above it that shows an amount.
		var targets: [(category: Int, from: Int, through: Int, currency: String)] = []
		var chains: [Range<Int>] = []
		for c in categories {
			let first = targets.count
			var next = index.position(of: c.id)
			while let n = next {
				let k = categories[n]
				if let period = Self.sidebarPeriod(of: k.sidebarAmount, today: today) {
					targets.append((n, period.start?.rawValue ?? .min, period.end?.rawValue ?? .max, k.currency))
				}
				next = k.parentID.flatMap(index.position(of:))
			}
			chains.append(first..<targets.count)
		}
		var sums = [Int64](repeating: 0, count: categories.count)
		let defaultID = defaultCategory?.id
		func add(_ t: Transaction) {
			guard let id = t.categoryID ?? defaultID, let i = index.position(of: id) else { return }
			let day = t.bookingDate.rawValue
			for target in targets[chains[i]] where target.from <= day && day <= target.through && t.isInSum(of: target.currency) {
				sums[target.category] += t.amountMinor
			}
		}
		for t in transactions {
			if let rows = partRows[t.id] { for row in rows { add(row) } } else { add(t) }
		}
		var amounts: [UUID: Money] = [:]
		for (i, c) in categories.enumerated() where sums[i] != 0 {
			amounts[c.id] = Money(minorUnits: sums[i], currency: c.currency)
		}
		return amounts
	}

	private static func sidebarPeriod(of amount: SidebarAmount, today: Day) -> DayRange? {
		switch amount {
		case .none: nil
		case .totalSum: .all
		case .currentMonth: DayRange(start: today.firstOfMonth, end: today.firstOfMonth.adding(months: 1).adding(days: -1))
		case .currentQuarter: DayRange(start: today.firstOfQuarter, end: today.firstOfQuarter.adding(months: 3).adding(days: -1))
		case .currentYear: DayRange(start: today.firstOfYear, end: Day(year: today.year, month: 12, day: 31))
		}
	}

	// MARK: Filtering

	public func rows(in scope: LedgerScope, filter: TransactionFilter = TransactionFilter()) -> TransactionSearchResult {
		// One pass over the rows, because copying 50,000 rows into a list of the view first cost as much as the search.
		let inScope: (Transaction) -> Bool
		switch scope {
		case let .account(id):
			inScope = { $0.accountID == id }
		case let .accountGroup(id):
			let ids = accountIDs(inGroupTree: id)
			inScope = { ids.contains($0.accountID) }
		case let .category(id):
			let ids = categoryIDs(inTree: id)
			let defaultID = defaultCategory?.id
			inScope = { ids.contains($0.categoryID ?? defaultID ?? UUID()) }
		}
		let query = SearchQuery(filter.searchText)
		let accountsByID = query.readsFields ? Dictionary(uniqueKeysWithValues: accounts.map { ($0.id, $0) }) : [:]
		let names = query.readsFields ? categoryNames : [:]
		let categoryFilter = filter.categoryID.map { categoryIDs(inTree: $0) }
		let defaultID = defaultCategory?.id ?? UUID()
		var amountBounds: [Int: MinorBounds] = [:]
		func matches(_ t: Transaction) -> Bool {
			guard inScope(t), filter.period.contains(t.bookingDate) else { return false }
			switch filter.status {
			case .all: break
			case .checked: if !t.isChecked { return false }
			case .unchecked: if t.isChecked { return false }
			}
			switch filter.amount {
			case .all: break
			case .deposits: if t.amountMinor <= 0 { return false }
			case .withdrawals: if t.amountMinor >= 0 { return false }
			case let .range(min, max):
				let places = t.amount.decimalPlaces
				let bounds = amountBounds[places] ?? MinorBounds(min: min, max: max, decimalPlaces: places)
				amountBounds[places] = bounds
				if t.amountMinor < bounds.min || t.amountMinor > bounds.max { return false }
			}
			if let categoryFilter, !categoryFilter.contains(t.categoryID ?? defaultID) { return false }
			if let a = filter.accountID, t.accountID != a { return false }
			if query.isEmpty { return true }
			return query.matches(t, searchText: searchText[t.id] ?? "", account: { accountsByID[t.accountID] }, categoryName: { names[t.categoryID] })
		}
		var rows: [Transaction] = []
		for t in transactions {
			if query.gaveUp { break }
			if let parts = partRows[t.id] {
				for row in parts {
					if query.gaveUp { break }
					if matches(row) { rows.append(row) }
				}
			} else if matches(t) { rows.append(t) }
		}
		return TransactionSearchResult(rows: rows, gaveUp: query.gaveUp)
	}

	// MARK: Changes

	public mutating func replace(groups: [AccountGroup]? = nil, accounts: [Account]? = nil, categories: [Category]? = nil, transactions: [Transaction]? = nil) {
		if let groups { self.groups = groups }
		if let accounts {
			self.accounts = accounts
			let ids = Set(accounts.map(\.id))
			portfolioHistory = portfolioHistory.filter { ids.contains($0.key) }
			holdingsByAccount = holdingsByAccount.filter { ids.contains($0.key) }
		}
		if let categories { self.categories = categories }
		if let transactions { self.transactions = transactions }
		// The search text holds the names of the account and the category, so only new accounts, categories,
		// or transactions build it again.
		if accounts != nil || categories != nil || transactions != nil { rebuildIndexes() } else { countNew() }
	}

	public func changes(from rows: [Transaction]) -> (transactions: [Transaction], parts: [SplitPart]) {
		var changed: [UUID: Transaction] = [:]
		var parts: [SplitPart] = []
		for row in rows {
			if var part = part(row.id), let original = transaction(part.transactionID) {
				if part.categoryID != row.categoryID || part.comment != row.comment {
					part.categoryID = row.categoryID
					part.comment = row.comment
					parts.append(part)
				}
				var t = changed[original.id] ?? original
				if row.isChecked != original.isChecked { t.isChecked = row.isChecked }
				if row.isNew != original.isNew { t.isNew = row.isNew }
				if row.review != original.review { t.review = row.review }
				if t != original { changed[t.id] = t }
			} else if partsByTransaction[row.id] == nil, let stored = transaction(row.id), row != stored {
				changed[row.id] = row
			}
		}
		return (Array(changed.values), parts)
	}

	/// Replaces transactions with the same identifier. Faster than `replace` for a handful of rows.
	public mutating func update(_ changed: [Transaction], parts: [SplitPart] = []) {
		var needsSort = false
		let accountsByID = Dictionary(uniqueKeysWithValues: accounts.map { ($0.id, $0) })
		let names = categoryNames
		for t in changed {
			if let i = transactionIndex[t.id] {
				if transactions[i].bookingDate != t.bookingDate { needsSort = true }
				transactions[i] = t
			} else {
				transactions.append(t)
				needsSort = true
			}
			rebuildRows(of: t, account: accountsByID[t.accountID], categoryNames: names)
		}
		var affected: Set<UUID> = []
		for part in parts {
			guard let id = transactionByPart[part.id], let i = partsByTransaction[id]?.firstIndex(where: { $0.id == part.id }) else { continue }
			partsByTransaction[id]?[i].categoryID = part.categoryID
			partsByTransaction[id]?[i].comment = part.comment
			affected.insert(id)
		}
		for id in affected {
			if let t = transaction(id) { rebuildRows(of: t, account: accountsByID[t.accountID], categoryNames: names) }
		}
		// An import of 2,000 rows into 50,000 sorts again but builds the search text of the new rows only.
		if needsSort { sortAndIndex() }
		countNew()
	}

	/// Takes over a merge that the database stored: removes the dropped rows, upserts the others and
	/// the account, and records the value of a portfolio.
	public mutating func apply(_ r: Reconciliation) {
		if let account = r.account {
			upsert(account)
			if let value = account.portfolioValue() { record(value) }
		}
		if let h = r.holdings { holdingsByAccount[h.accountID] = h.holdings.sorted(by: Holding.isOrdered) }
		if !r.dropped.isEmpty { remove(transactionIDs: Set(r.dropped)) }
		for id in r.unsplit { replaceParts(of: id, with: []) }
		update(r.added + r.booked + r.updated + r.marked)
	}

	public mutating func remove(transactionIDs ids: Set<UUID>) {
		transactions.removeAll { ids.contains($0.id) }
		for id in ids {
			partsByTransaction[id] = nil
			for row in partRows.removeValue(forKey: id) ?? [] { searchText[row.id] = nil; transactionByPart[row.id] = nil }
			searchText[id] = nil
		}
		sortAndIndex()
		countNew()
	}

	public mutating func replaceParts(of transactionID: UUID, with parts: [SplitPart]) {
		guard let original = transaction(transactionID) else { return }
		partsByTransaction[transactionID] = parts.isEmpty ? nil : parts.map { part in
			var part = part
			part.transactionID = transactionID
			return part
		}.sorted { $0.position < $1.position }
		rebuildRows(of: original, account: account(original.accountID), categoryNames: categoryNames)
	}

	public mutating func remove(category id: UUID) {
		let removed = categoryIDs(inTree: id)
		categories.removeAll { removed.contains($0.id) }
		for i in transactions.indices where transactions[i].categoryID.map(removed.contains) ?? false {
			transactions[i].categoryID = nil
			transactions[i].categorizedBy = .none
		}
		for id in Array(partsByTransaction.keys) {
			partsByTransaction[id] = partsByTransaction[id]?.map { part in
				var part = part
				if part.categoryID.map(removed.contains) ?? false { part.categoryID = nil }
				return part
			}
		}
		rebuildIndexes()
	}

	public mutating func upsert(_ account: Account) {
		if let i = accounts.firstIndex(where: { $0.id == account.id }) {
			let old = accounts[i]
			accounts[i] = account
			if (old.name, old.iban, old.accountNumber) != (account.name, account.iban, account.accountNumber) {
				refreshSearchText { $0.accountID == account.id }
			}
		} else {
			accounts.append(account)
		}
	}

	/// Adds the value of a portfolio on a day. A record of the same account and day is replaced.
	public mutating func record(_ value: PortfolioValue) {
		var values = portfolioHistory[value.accountID] ?? []
		// From the end, so that loading records in order of their days appends each one at once.
		let before = values.lastIndex { $0.day <= value.day }
		if let before, values[before].day == value.day {
			values[before] = value
		} else {
			values.insert(value, at: before.map { $0 + 1 } ?? 0)
		}
		portfolioHistory[value.accountID] = values
	}

	public mutating func upsert(_ group: AccountGroup) {
		if let i = groups.firstIndex(where: { $0.id == group.id }) { groups[i] = group } else { groups.append(group) }
	}

	public mutating func upsert(_ category: Category) {
		let oldName = categories.first { $0.id == category.id }?.name
		let oldDefaultName = defaultCategory?.name
		if let i = categories.firstIndex(where: { $0.id == category.id }) { categories[i] = category } else { categories.append(category) }
		// A row without a category holds the name of the default category in its search text.
		let renamed = oldName.map { $0 != category.name } ?? false
		let defaultRenamed = defaultCategory?.name != oldDefaultName
		if renamed || defaultRenamed {
			refreshSearchText { $0.categoryID == nil ? defaultRenamed : renamed && $0.categoryID == category.id }
		}
	}
}

/// The ends of a custom amount range in the minor units of one number of decimal places. An end
/// between two minor units moves inward, so a row passes only when its exact amount lies in the range.
private struct MinorBounds {
	let min: Int64
	let max: Int64

	init(min: Decimal?, max: Decimal?, decimalPlaces: Int) {
		self.min = min.map { Self.minor($0, decimalPlaces, .up) } ?? .min
		self.max = max.map { Self.minor($0, decimalPlaces, .down) } ?? .max
	}

	private static func minor(_ value: Decimal, _ decimalPlaces: Int, _ mode: NSDecimalNumber.RoundingMode) -> Int64 {
		var scaled = value * Decimal(sign: .plus, exponent: decimalPlaces, significand: 1)
		// A text of more than about 160 digits overflows Decimal, which gives NaN without a sign.
		if scaled.isNaN { return value < 0 ? .min : .max }
		var rounded = Decimal()
		NSDecimalRound(&rounded, &scaled, 0, mode)
		if rounded >= Decimal(Int64.max) { return .max }
		if rounded <= Decimal(Int64.min) { return .min }
		return NSDecimalNumber(decimal: rounded).int64Value
	}
}

public struct TransactionFilter: Hashable, Sendable {
	public enum Status: Hashable, Sendable, Codable { case all, checked, unchecked }
	public enum AmountFilter: Hashable, Sendable, Codable {
		case all, deposits, withdrawals
		/// Amounts with their sign, both ends included. A missing end leaves the range open.
		case range(min: Decimal?, max: Decimal?)

		/// The range of "Custom...", or nil when the minimum lies above the maximum. Two empty ends hide nothing.
		public static func custom(min: Decimal?, max: Decimal?) -> AmountFilter? {
			if min == nil, max == nil { return .all }
			if let min, let max, min > max { return nil }
			return .range(min: min, max: max)
		}
	}

	public var searchText = ""
	public var period = DayRange.all
	public var status = Status.all
	public var amount = AmountFilter.all
	public var categoryID: UUID?
	public var accountID: UUID?

	public init() {}

	public var isActive: Bool {
		period != .all || status != .all || amount != .all || categoryID != nil || accountID != nil
	}

	/// Sets the filter that the filter bar of `scope` has no menu for to "Show All": the account filter in an
	/// account or a group, the category filter in a category. The list applies both filters in every view, so a
	/// kept filter without its menu would hide rows with no control to clear it.
	public mutating func resetHidden(in scope: LedgerScope) {
		switch scope {
		case .account, .accountGroup: accountID = nil
		case .category: categoryID = nil
		}
	}

	/// A filter on a category or an account that `ledger` no longer has goes back to "Show All", so the list does
	/// not stay empty after a removal.
	public mutating func dropMissing(in ledger: Ledger) {
		categoryID = categoryID.flatMap { ledger.category($0)?.id }
		accountID = accountID.flatMap { ledger.account($0)?.id }
	}
}

/// A row of the account tree: a group or an account.
public enum AccountTreeItem: Identifiable, Sendable {
	case group(AccountGroup)
	case account(Account)

	public var id: UUID {
		switch self {
		case let .group(g): g.id
		case let .account(a): a.id
		}
	}

	public var position: Int {
		switch self {
		case let .group(g): g.position
		case let .account(a): a.position
		}
	}
}

/// What the account view proposes after a refresh: the bank balance less the initial balance and the
/// booked rows up to its day, and the balance of today that the calibration window fills in.
public struct CalibrationProposal: Hashable, Sendable {
	public var difference: Money
	public var balanceToday: Money
}

/// The position of each category ID in `Ledger.categories`. The sidebar looks up the category of every
/// transaction, and a `Dictionary` hashes each UUID with SipHash in about 30 ns, most of the time of
/// `sidebarAmounts(today:)` at 50,000 transactions. This table hashes the low half of the UUID with one multiplication.
private struct CategoryIndex {
	private struct Entry {
		var low: UInt64
		var high: UInt64
		var position: Int
	}

	private var entries: [Entry]
	private let shift: UInt64

	init(_ ids: [UUID]) {
		var bits: UInt64 = 3
		while 1 << bits < ids.count * 4 { bits += 1 }
		shift = 64 - bits
		entries = Array(repeating: Entry(low: 0, high: 0, position: -1), count: 1 << bits)
		for (position, id) in ids.enumerated() {
			let (low, high) = Self.halves(of: id)
			var k = slot(of: low)
			while entries[k].position >= 0 { k = (k + 1) & (entries.count - 1) }
			entries[k] = Entry(low: low, high: high, position: position)
		}
	}

	func position(of id: UUID) -> Int? {
		let (low, high) = Self.halves(of: id)
		var k = slot(of: low)
		while entries[k].position >= 0 {
			if entries[k].low == low && entries[k].high == high { return entries[k].position }
			k = (k + 1) & (entries.count - 1)
		}
		return nil
	}

	private func slot(of low: UInt64) -> Int {
		Int(truncatingIfNeeded: (low &* 0x9E37_79B9_7F4A_7C15) >> shift)
	}

	private static func halves(of id: UUID) -> (UInt64, UInt64) {
		withUnsafeBytes(of: id.uuid) { ($0.loadUnaligned(fromByteOffset: 8, as: UInt64.self), $0.loadUnaligned(as: UInt64.self)) }
	}
}
