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

	/// The types that the menu "Account type" offers for an account of this type, or nil for a portfolio.
	/// "Portfolio" decides that an account shows securities, so the user can neither choose it nor leave it.
	public var choices: [AccountKind]? {
		self == .portfolio ? nil : Self.allCases.filter { $0 != .portfolio }
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
	/// The balance that the bank or the migration source reported. `reportedBalance` says which accounts show it.
	public var bankBalanceMinor: Int64?
	public var bankBalanceDate: Date?
	/// The balance before the oldest transaction. Charts start from it.
	public var initialBalanceMinor: Int64
	/// The first refresh with a bank balance or the user set the initial balance, so the app never
	/// derives it again. The user changes it from then on, with "Calibrate" or by hand.
	public var initialBalanceIsSet: Bool
	/// A refresh derived the initial balance, and the user has not entered one since. Only then does a manual row
	/// move it to keep the bank balance. A value that the user enters stays as the user entered it.
	public var initialBalanceIsDerived: Bool
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
		bankBalanceMinor: Int64? = nil, bankBalanceDate: Date? = nil, initialBalanceMinor: Int64 = 0, initialBalanceIsSet: Bool = false, initialBalanceIsDerived: Bool = false, isClosed: Bool = false, comment: String? = nil, sourceID: String? = nil,
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
		self.initialBalanceIsDerived = initialBalanceIsDerived
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

	/// "Add Transaction..." works in every account except a portfolio, whose value comes from its positions.
	/// In an account with bank access, a manual row covers what the bank does not deliver.
	public var takesManualTransactions: Bool { kind != .portfolio }

	/// The balance that a portfolio or an account of a bank access shows. A portfolio gets its value from the
	/// bank, not from transactions. Every other account computes its balance, also a migrated one that keeps
	/// the balance of the source.
	public var reportedBalance: Money? {
		guard kind == .portfolio || source == .bank, let bankBalanceMinor else { return nil }
		return Money(minorUnits: bankBalanceMinor, currency: currency)
	}

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

	/// The rows that a bank balance for the end of `day` holds: booked rows in the account currency up to that
	/// day. Pending rows are not in it, with or without review, because a bank reports its booked balance.
	func bookedSum(of rows: some Sequence<Transaction>, through day: Day) -> Int64 {
		rows.reduce(0) { sum, t in
			!t.isPending && t.currency == currency && t.bookingDate <= day ? sum + t.amountMinor : sum
		}
	}

	/// The initial balance at which the booked rows up to the end of the day of the bank balance add up to
	/// the bank balance. `rows` are all live rows of the account. The pending rows then count on top.
	public func initialBalanceMeetingBankBalance(of rows: some Sequence<Transaction>, calendar: Calendar = .current) -> Int64? {
		bankBalanceMinor.map { $0 - bookedSum(of: rows, through: Day(bankBalanceDate ?? Date(), calendar: calendar)) }
	}

	/// The initial balance that the user enters in the account settings or with "Calibrate". It stays, so no refresh
	/// derives it again and no manual row moves it.
	public mutating func enterInitialBalance(_ minor: Int64) {
		initialBalanceMinor = minor
		initialBalanceIsSet = true
		initialBalanceIsDerived = false
	}

	/// Sets the initial balance once, so that the computed balance meets the bank balance.
	mutating func deriveInitialBalance(from rows: [Transaction], calendar: Calendar = .current) {
		guard derivesInitialBalance, let value = initialBalanceMeetingBankBalance(of: rows, calendar: calendar) else { return }
		initialBalanceMinor = value
		initialBalanceIsSet = true
		initialBalanceIsDerived = true
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
	/// The one category that holds every transaction without another category. The sidebar shows it last.
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

public enum ReviewReason: String, Codable, Sendable {
	case unclearBooking, splitUndone

	public var note: String {
		switch self {
		case .unclearBooking: "Several transactions could belong together. Check the rows and delete the ones you don't need."
		case .splitUndone: "The bank changed the amount; the split was undone."
		}
	}
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
	/// The ISO 20022 code with which the bank returned the payment, for example "AC04" for a closed account.
	public var returnReason: String?
	public var comment: String?
	public var isChecked: Bool
	public var isPending: Bool
	public var categoryID: UUID?
	public var categorizedBy: Categorization
	/// True from the moment the transaction arrives until the user has seen it.
	public var isNew: Bool
	/// Why a merge marked this row for review. The list shows a
	/// mark until the user checks a booked row or deletes the row. A merge drops a pending row that has it only
	/// after the user checked it, and a new review clears that checkmark.
	public var review: ReviewReason?
	/// A refresh delivered this row. Once the user deletes it, a file import does not add it again.
	public var isFetched: Bool
	public var sourceID: String?
	public var fileIdentity: String?
	public var createdAt: Date
	/// The user added the row with "Add Transaction...". It keeps the mark when a file or a migration matches it.
	public var isManual: Bool

	/// A manual row that no file and no migration matched. No source has it, so a refresh never pairs a delivered
	/// row with it, and deleting it keeps no record. A manual row that a source matched is a row of that source.
	public var isOnlyManual: Bool { isManual && sourceID == nil && fileIdentity == nil }
	/// The fields that "Edit Transaction..." changes, as the source delivered them. Nil until the user changes one
	/// of them. A merge finds the row by these values and updates them, and the fields keep what the user wrote.
	public var original: OriginalValues?

	public init(id: UUID = UUID(), accountID: UUID, bookingDate: Day, valueDate: Day? = nil, amountMinor: Int64, currency: String = "EUR", name: String, purpose: String = "",
		counterpartyIBAN: String? = nil, counterpartyBIC: String? = nil, bookingText: String? = nil, endToEndReference: String? = nil, mandateReference: String? = nil,
		creditorID: String? = nil, comment: String? = nil, isChecked: Bool = false, isPending: Bool = false, categoryID: UUID? = nil, categorizedBy: Categorization = .none,
		isNew: Bool = false, review: ReviewReason? = nil, isFetched: Bool = false, sourceID: String? = nil, createdAt: Date = Date(), returnReason: String? = nil, fileIdentity: String? = nil, isManual: Bool = false) {
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
		self.returnReason = returnReason
		self.comment = comment
		self.isChecked = isChecked
		self.isPending = isPending
		self.categoryID = categoryID
		self.categorizedBy = categorizedBy
		self.isNew = isNew
		self.review = review
		self.isFetched = isFetched
		self.sourceID = sourceID
		self.fileIdentity = fileIdentity
		self.createdAt = createdAt
		self.isManual = isManual
	}

	public var amount: Money { Money(minorUnits: amountMinor, currency: currency) }

	/// The editable fields as the source delivered them: `original` after an edit, otherwise the fields themselves.
	public var sourceValues: OriginalValues { original ?? OriginalValues(self) }

	/// What "Edit Transaction..." writes. The first change of a row from a source keeps the delivered values in
	/// `original`, so that a later refresh still finds the row and does not add it again. Values equal to the
	/// delivered ones clear it. A row that the user typed in has no source, so a correction replaces its values,
	/// and a file finds the row by the corrected ones.
	public mutating func edit(_ values: OriginalValues) {
		let delivered = sourceValues
		bookingDate = values.bookingDate
		valueDate = values.valueDate
		amountMinor = values.amountMinor
		name = values.name
		purpose = values.purpose
		original = !hasSource || values == delivered ? nil : delivered
	}

	/// Whether a bank, a file, or a migration delivered the row. A row that the user typed in has none.
	var hasSource: Bool { isFetched || sourceID != nil || fileIdentity != nil }

	/// The rule for every sum, such as a balance, a bar of a chart, or the amount of a category. A pending row
	/// counts like a booked one, except while it waits for review: then the booked row stands for the money.
	var countsInSums: Bool { !isPending || review == nil }

	/// The rule for every sum in one currency. The minor units of another currency are not those of the sum,
	/// and a sum never converts.
	public func isInSum(of currency: String) -> Bool {
		countsInSums && self.currency == currency
	}

	/// The prefix of the IDs that the MoneyMoney migration gives. Such an ID says where a row came from,
	/// not which source delivers it, so a source with IDs of its own takes the row over.
	public static let migrationIDPrefix = "moneymoney:"

	/// The user checked the row: it is no longer new, and a booked row needs no more review. A pending row keeps
	/// its mark, so it still counts in no sum while the booked row stands for its money.
	public mutating func markChecked() {
		isChecked = true
		isNew = false
		if !isPending { review = nil }
	}

	/// Checking the row changes it, so "Mark All Transactions as Checked" counts it.
	public var changesWhenChecked: Bool { !isChecked || isNew || (review != nil && !isPending) }
}

/// The fields of a transaction that the user can change with "Edit Transaction...".
public struct OriginalValues: Hashable, Sendable, Codable {
	public var bookingDate: Day
	public var valueDate: Day?
	public var amountMinor: Int64
	public var name: String
	public var purpose: String

	public init(bookingDate: Day, valueDate: Day?, amountMinor: Int64, name: String, purpose: String) {
		self.bookingDate = bookingDate
		self.valueDate = valueDate
		self.amountMinor = amountMinor
		self.name = name
		self.purpose = purpose
	}

	public init(_ t: Transaction) {
		self.init(bookingDate: t.bookingDate, valueDate: t.valueDate, amountMinor: t.amountMinor, name: t.name, purpose: t.purpose)
	}
}
