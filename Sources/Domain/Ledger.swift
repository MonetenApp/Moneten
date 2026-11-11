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

	private var transactionIndex: [UUID: Int] = [:]
	private var searchText: [UUID: String] = [:]
	/// The number of new transactions per account.
	public private(set) var newTransactionCounts: [UUID: Int] = [:]

	public init(groups: [AccountGroup] = [], accounts: [Account] = [], categories: [Category] = [], transactions: [Transaction] = [],
		portfolioValues: [PortfolioValue] = []) {
		self.groups = groups
		self.accounts = accounts
		self.categories = categories
		self.transactions = transactions
		for v in portfolioValues { record(v) }
		rebuildIndexes()
	}

	private mutating func rebuildIndexes() {
		sortAndIndex()
		let accountsByID = Dictionary(uniqueKeysWithValues: accounts.map { ($0.id, $0) })
		searchText = Dictionary(uniqueKeysWithValues: transactions.map { ($0.id, Self.searchText(of: $0, account: accountsByID[$0.accountID])) })
		countNew()
	}

	/// The order and the positions only. The search texts of unchanged rows stay as they are.
	private mutating func sortAndIndex() {
		transactions.sort { ($0.bookingDate, $0.createdAt) > ($1.bookingDate, $1.createdAt) }
		transactionIndex = Dictionary(uniqueKeysWithValues: transactions.enumerated().map { ($0.element.id, $0.offset) })
	}

	private mutating func countNew() {
		var counts: [UUID: Int] = [:]
		for t in transactions where t.isNew { counts[t.accountID, default: 0] += 1 }
		newTransactionCounts = counts
	}

	static func searchText(of t: Transaction, account: Account?) -> String {
		let amounts = amountTexts(t.amountMinor, decimals: t.amount.decimalPlaces)
		let parts: [String?] = [t.name, t.purpose, t.bookingText, t.endToEndReference, t.mandateReference, t.creditorID, t.comment,
			t.counterpartyIBAN, t.counterpartyBIC, account?.name] + amounts
		return TextFolding.fold(parts.compactMap { $0 }.joined(separator: "\u{1}"))
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
	/// The recorded values of a portfolio, the oldest first.
	public func portfolioValues(of accountID: UUID) -> [PortfolioValue] { portfolioHistory[accountID] ?? [] }

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

	/// All categories from top to bottom as the sidebar shows them, with "Uncategorized" last.
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

	/// The balance in the sidebar. The bank's balance where there is one, otherwise the computed one.
	public func balance(of account: Account) -> Money {
		if let b = account.bankBalanceMinor { return Money(minorUnits: b, currency: account.currency) }
		return computedBalance(of: account)
	}

	/// The initial balance plus all booked transactions.
	public func computedBalance(of account: Account, through day: Day? = nil) -> Money {
		var sum = account.initialBalanceMinor
		for t in transactions where t.accountID == account.id && !t.isPending {
			if let day, t.bookingDate > day { continue }
			sum += t.amountMinor
		}
		return Money(minorUnits: sum, currency: account.currency)
	}

	public func sum(ofGroup group: UUID) -> MoneySums {
		var sums = MoneySums()
		for id in accountIDs(inGroupTree: group) {
			if let a = account(id), !a.isClosed { sums.add(balance(of: a)) }
		}
		return sums
	}

	// MARK: Filtering

	public func transactions(in scope: LedgerScope, filter: TransactionFilter = TransactionFilter()) -> [Transaction] {
		let base: [Transaction]
		switch scope {
		case let .account(id):
			base = transactions.filter { $0.accountID == id }
		case let .accountGroup(id):
			let ids = accountIDs(inGroupTree: id)
			base = transactions.filter { ids.contains($0.accountID) }
		case let .category(id):
			let ids = categoryIDs(inTree: id)
			let defaultID = defaultCategory?.id
			base = transactions.filter { ids.contains($0.categoryID ?? defaultID ?? UUID()) }
		}
		let words = TextFolding.words(filter.searchText).map(String.init)
		let categoryFilter = filter.categoryID.map { categoryIDs(inTree: $0) }
		let defaultID = defaultCategory?.id ?? UUID()
		return base.filter { t in
			guard filter.period.contains(t.bookingDate) else { return false }
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
				let value = abs(t.amountMinor)
				if let min, value < min { return false }
				if let max, value > max { return false }
			}
			if let categoryFilter, !categoryFilter.contains(t.categoryID ?? defaultID) { return false }
			if let a = filter.accountID, t.accountID != a { return false }
			if !words.isEmpty {
				let haystack = searchText[t.id] ?? ""
				if !words.allSatisfy({ haystack.contains($0) }) { return false }
			}
			return true
		}
	}

	// MARK: Changes

	public mutating func replace(groups: [AccountGroup]? = nil, accounts: [Account]? = nil, categories: [Category]? = nil, transactions: [Transaction]? = nil) {
		if let groups { self.groups = groups }
		if let accounts {
			self.accounts = accounts
			let ids = Set(accounts.map(\.id))
			portfolioHistory = portfolioHistory.filter { ids.contains($0.key) }
		}
		if let categories { self.categories = categories }
		if let transactions { self.transactions = transactions }
		// The search text holds the account name, so only new accounts or transactions build it again.
		if accounts != nil || transactions != nil { rebuildIndexes() } else { countNew() }
	}

	/// Replaces transactions with the same identifier. Faster than `replace` for a handful of rows.
	public mutating func update(_ changed: [Transaction]) {
		var needsSort = false
		let accountsByID = Dictionary(uniqueKeysWithValues: accounts.map { ($0.id, $0) })
		for t in changed {
			if let i = transactionIndex[t.id] {
				if transactions[i].bookingDate != t.bookingDate { needsSort = true }
				transactions[i] = t
			} else {
				transactions.append(t)
				needsSort = true
			}
			searchText[t.id] = Self.searchText(of: t, account: accountsByID[t.accountID])
		}
		// An import of 2,000 rows into 50,000 sorts again but builds the search text of the new rows only.
		if needsSort { sortAndIndex() }
		countNew()
	}

	public mutating func remove(transactionIDs ids: Set<UUID>) {
		transactions.removeAll { ids.contains($0.id) }
		for id in ids { searchText[id] = nil }
		sortAndIndex()
		countNew()
	}

	public mutating func upsert(_ account: Account) {
		if let i = accounts.firstIndex(where: { $0.id == account.id }) {
			let renamed = accounts[i].name != account.name
			accounts[i] = account
			// The search text holds the account name.
			if renamed {
				for t in transactions where t.accountID == account.id { searchText[t.id] = Self.searchText(of: t, account: account) }
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
		if let i = categories.firstIndex(where: { $0.id == category.id }) { categories[i] = category } else { categories.append(category) }
	}
}

public struct TransactionFilter: Hashable, Sendable {
	public enum Status: Hashable, Sendable { case all, checked, unchecked }
	public enum AmountFilter: Hashable, Sendable {
		case all, deposits, withdrawals
		/// Absolute amounts in minor units.
		case range(min: Int64?, max: Int64?)
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
