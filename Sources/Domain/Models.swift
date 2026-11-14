import Foundation

public enum AccountKind: String, Codable, Sendable, CaseIterable {
	case giro, savings, fixedTermDeposit, loan, creditCard, portfolio, cash, other

	public var title: String {
		switch self {
		case .giro: "Giro account"
		case .savings: "Savings account"
		case .fixedTermDeposit: "Fixed term deposit"
		case .loan: "Loan account"
		case .creditCard: "Credit card"
		case .portfolio: "Portfolio"
		case .cash: "Cash"
		case .other: "Other"
		}
	}
}

/// Where an account gets its data from.
public enum AccountSource: String, Codable, Sendable {
	/// An offline account. The user enters every transaction.
	case offline
	/// Taken over from MoneyMoney. The account has no bank access yet.
	case migrated
	/// Refreshed through its bank access, `Account.accessID`.
	case bank
}

public struct AccountGroup: Identifiable, Hashable, Sendable, Codable {
	public var id: UUID
	public var name: String
	public var parentID: UUID?
	public var position: Int
	public var showSum: Bool
	public var isExpanded: Bool
	/// "Group transactions by account": the list of the group shows the transactions of each account
	/// under a heading with its name.
	public var groupsByAccount: Bool

	public init(id: UUID = UUID(), name: String, parentID: UUID? = nil, position: Int, showSum: Bool = true, isExpanded: Bool = true,
		groupsByAccount: Bool = false) {
		self.id = id
		self.name = name
		self.parentID = parentID
		self.position = position
		self.showSum = showSum
		self.isExpanded = isExpanded
		self.groupsByAccount = groupsByAccount
	}
}

public struct Account: Identifiable, Hashable, Sendable, Codable {
	public var id: UUID
	public var groupID: UUID?
	public var position: Int
	public var name: String
	public var kind: AccountKind
	public var source: AccountSource
	public var currency: String
	public var iban: String?
	public var bic: String?
	public var accountNumber: String?
	public var bankCode: String?
	public var bankName: String?
	public var owner: String?
	/// The balance that the bank reported. Offline accounts compute their balance instead.
	public var bankBalanceMinor: Int64?
	public var bankBalanceDate: Date?
	/// The balance before the oldest transaction. Charts start from it.
	public var initialBalanceMinor: Int64
	/// The first refresh with a bank balance or the user set the initial balance, so the app never
	/// derives it again. The user changes it from then on, with "Calibrate" or by hand.
	public var initialBalanceIsSet: Bool
	public var isClosed: Bool
	public var comment: String?
	/// The identifier of the account in the program it came from.
	public var sourceID: String?
	/// The color of the account's icon as "#RRGGBB", chosen by the user.
	public var color: String?
	/// The bank access that refreshes the account. Nil for an offline or a migrated account.
	public var accessID: UUID?
	/// The ID that the access knows the account by, such as the IBAN.
	public var remoteID: String?
	/// The end of the last successful refresh. The next refresh asks for the transactions from 14 days before it.
	public var refreshedAt: Date?
	/// The error of the last refresh, until a refresh of the account succeeds.
	public var refreshError: RefreshError?
	/// "Refresh" in the account settings: how often the automatic refresh fetches the account.
	public var refreshInterval: RefreshInterval

	public init(id: UUID = UUID(), groupID: UUID? = nil, position: Int, name: String, kind: AccountKind, source: AccountSource, currency: String = "EUR",
		iban: String? = nil, bic: String? = nil, accountNumber: String? = nil, bankCode: String? = nil, bankName: String? = nil, owner: String? = nil,
		bankBalanceMinor: Int64? = nil, bankBalanceDate: Date? = nil, initialBalanceMinor: Int64 = 0, initialBalanceIsSet: Bool = false, isClosed: Bool = false, comment: String? = nil, sourceID: String? = nil,
		color: String? = nil, accessID: UUID? = nil, remoteID: String? = nil, refreshedAt: Date? = nil, refreshError: RefreshError? = nil,
		refreshInterval: RefreshInterval = .everyTwoHours) {
		self.id = id
		self.groupID = groupID
		self.position = position
		self.name = name
		self.kind = kind
		self.source = source
		self.currency = currency
		self.iban = iban
		self.bic = bic
		self.accountNumber = accountNumber
		self.bankCode = bankCode
		self.bankName = bankName
		self.owner = owner
		self.bankBalanceMinor = bankBalanceMinor
		self.bankBalanceDate = bankBalanceDate
		self.initialBalanceMinor = initialBalanceMinor
		self.initialBalanceIsSet = initialBalanceIsSet
		self.isClosed = isClosed
		self.comment = comment
		self.sourceID = sourceID
		self.color = color
		self.accessID = accessID
		self.remoteID = remoteID
		self.refreshedAt = refreshedAt
		self.refreshError = refreshError
		self.refreshInterval = refreshInterval
	}

	public var isOffline: Bool { source == .offline }

	/// The record of a portfolio with a bank balance: that balance on the day the bank reported it,
	/// or today when the day is unknown. Other accounts get their balance from transactions.
	public func portfolioValue(calendar: Calendar = .current) -> PortfolioValue? {
		guard kind == .portfolio, let bankBalanceMinor else { return nil }
		return PortfolioValue(accountID: id, day: Day(bankBalanceDate ?? Date(), calendar: calendar), minorUnits: bankBalanceMinor)
	}

	/// A row that the balance counts. A row in another currency stays in the account and its list.
	public func isInBalance(_ t: Transaction) -> Bool {
		t.isInSum(of: currency)
	}

	/// A bank refreshes the account and nothing set its initial balance yet. A portfolio gets its
	/// history from its recorded values instead.
	var derivesInitialBalance: Bool { source == .bank && kind != .portfolio && !initialBalanceIsSet }

	/// Sets the initial balance once, so that the computed balance at the end of the day of the bank
	/// balance equals the bank balance. `rows` are all live rows of the account. Pending rows, rows in
	/// another currency, and rows booked after that day are not in the bank balance.
	mutating func deriveInitialBalance(from rows: [Transaction], calendar: Calendar = .current) {
		guard derivesInitialBalance, let bankBalanceMinor else { return }
		let day = Day(bankBalanceDate ?? Date(), calendar: calendar)
		initialBalanceMinor = rows.reduce(bankBalanceMinor) { sum, t in
			isInBalance(t) && t.bookingDate <= day ? sum - t.amountMinor : sum
		}
		initialBalanceIsSet = true
	}
}

/// The value of a portfolio at the end of one day. A portfolio gets its value from the bank and not
/// from transactions, so the app records it once a day and draws its history from these records.
/// An account has at most one record per day.
public struct PortfolioValue: Hashable, Sendable, Codable {
	public var accountID: UUID
	public var day: Day
	public var minorUnits: Int64

	public init(accountID: UUID, day: Day, minorUnits: Int64) {
		self.accountID = accountID
		self.day = day
		self.minorUnits = minorUnits
	}
}

/// The amount that a category shows next to its name in the sidebar.
public enum SidebarAmount: String, Codable, Sendable, CaseIterable {
	case none, currentMonth, currentQuarter, currentYear, totalSum

	public var title: String {
		switch self {
		case .none: "No amount"
		case .currentMonth: "Current month"
		case .currentQuarter: "Current quarter"
		case .currentYear: "Current year"
		case .totalSum: "Total sum"
		}
	}
}

public struct Category: Identifiable, Hashable, Sendable, Codable {
	public var id: UUID
	public var parentID: UUID?
	public var position: Int
	public var name: String
	public var isGroup: Bool
	/// The one category that holds every transaction without another category. Its name is "Uncategorized".
	public var isDefault: Bool
	/// A color as "#RRGGBB".
	public var color: String?
	/// The name of an SF Symbol, such as "cart.fill". Nil shows a dot, or a folder for a group.
	public var symbol: String?
	public var currency: String
	public var showInDiagrams: Bool
	public var sidebarAmount: SidebarAmount
	/// An account or account group. The rule applies only to its transactions.
	public var restrictedToID: UUID?
	/// The categorization rule in the rule language. Empty for no rule.
	public var rule: String
	public var isExpanded: Bool
	public var sourceID: String?

	public init(id: UUID = UUID(), parentID: UUID? = nil, position: Int, name: String, isGroup: Bool = false, isDefault: Bool = false, color: String? = nil, symbol: String? = nil, currency: String = "EUR",
		showInDiagrams: Bool = true, sidebarAmount: SidebarAmount = .totalSum, restrictedToID: UUID? = nil, rule: String = "", isExpanded: Bool = true, sourceID: String? = nil) {
		self.id = id
		self.parentID = parentID
		self.position = position
		self.name = name
		self.isGroup = isGroup
		self.isDefault = isDefault
		self.color = color
		self.symbol = symbol
		self.currency = currency
		self.showInDiagrams = showInDiagrams
		self.sidebarAmount = sidebarAmount
		self.restrictedToID = restrictedToID
		self.rule = rule
		self.isExpanded = isExpanded
		self.sourceID = sourceID
	}
}

/// How a transaction got its category.
public enum Categorization: String, Codable, Sendable {
	case none, rule, manual
}

public struct Transaction: Identifiable, Hashable, Sendable, Codable {
	public var id: UUID
	public var accountID: UUID
	public var bookingDate: Day
	public var valueDate: Day?
	public var amountMinor: Int64
	public var currency: String
	/// The counterparty: payee of a withdrawal, payer of a deposit.
	public var name: String
	public var purpose: String
	public var counterpartyIBAN: String?
	public var counterpartyBIC: String?
	public var bookingText: String?
	public var endToEndReference: String?
	public var mandateReference: String?
	public var creditorID: String?
	public var comment: String?
	public var isChecked: Bool
	public var isPending: Bool
	public var categoryID: UUID?
	public var categorizedBy: Categorization
	/// True from the moment the transaction arrives until the user has seen it.
	public var isNew: Bool
	/// Set by a merge when more than one row could be the booked version of a pending row. The list
	/// shows a mark until the user checks or deletes the row. A merge never drops a pending row that has it.
	public var needsReview: Bool
	/// A refresh delivered this row. Once the user deletes it, a file import does not add it again.
	public var isFetched: Bool
	public var sourceID: String?
	public var createdAt: Date

	public init(id: UUID = UUID(), accountID: UUID, bookingDate: Day, valueDate: Day? = nil, amountMinor: Int64, currency: String = "EUR", name: String, purpose: String = "",
		counterpartyIBAN: String? = nil, counterpartyBIC: String? = nil, bookingText: String? = nil, endToEndReference: String? = nil, mandateReference: String? = nil,
		creditorID: String? = nil, comment: String? = nil, isChecked: Bool = false, isPending: Bool = false, categoryID: UUID? = nil, categorizedBy: Categorization = .none,
		isNew: Bool = false, needsReview: Bool = false, isFetched: Bool = false, sourceID: String? = nil, createdAt: Date = Date()) {
		self.id = id
		self.accountID = accountID
		self.bookingDate = bookingDate
		self.valueDate = valueDate
		self.amountMinor = amountMinor
		self.currency = currency
		self.name = name
		self.purpose = purpose
		self.counterpartyIBAN = counterpartyIBAN
		self.counterpartyBIC = counterpartyBIC
		self.bookingText = bookingText
		self.endToEndReference = endToEndReference
		self.mandateReference = mandateReference
		self.creditorID = creditorID
		self.comment = comment
		self.isChecked = isChecked
		self.isPending = isPending
		self.categoryID = categoryID
		self.categorizedBy = categorizedBy
		self.isNew = isNew
		self.needsReview = needsReview
		self.isFetched = isFetched
		self.sourceID = sourceID
		self.createdAt = createdAt
	}

	public var amount: Money { Money(minorUnits: amountMinor, currency: currency) }

	/// The rule for every sum in one currency, such as the balance of an account or the amount of a
	/// category. The minor units of another currency are not those of the sum, and a sum never converts.
	public func isInSum(of currency: String) -> Bool {
		!isPending && self.currency == currency
	}

	/// The prefix of the IDs that the MoneyMoney migration gives. Such an ID says where a row came from,
	/// not which source delivers it, so a source with IDs of its own takes the row over.
	public static let migrationIDPrefix = "moneymoney:"

	/// The user checked the row: it is no longer new and needs no more review.
	public mutating func markChecked() {
		isChecked = true
		isNew = false
		needsReview = false
	}
}
