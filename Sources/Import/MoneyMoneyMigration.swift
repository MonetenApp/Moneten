import AppKit
import Domain
import CoreGraphics
import Foundation
import ImageIO

/// Turns the AppleScript exports of MoneyMoney into accounts, categories, and transactions.
///
/// The exports are property lists. `export accounts` and `export categories` return flat lists in
/// sidebar order, where `indentation` gives the nesting and `group` marks a group.
/// `export transactions ... as "plist"` returns a dictionary with the key `transactions`.
public struct MoneyMoneyMigration: Sendable {
	fileprivate struct Exports: Sendable {
		let accounts: Data
		let categories: Data
		let transactions: Data
	}

	public struct Plan: Sendable {
		fileprivate let exports: Exports
		fileprivate let calendar: Calendar
		public var groups: [AccountGroup] = []
		public var accounts: [Account] = []
		public var categories: [Domain.Category] = []
		public var transactions: [Transaction] = []
		/// Accounts of an earlier run with the newer balance from MoneyMoney and the initial balance that follows,
		/// or the color of their icon.
		public var updatedAccounts: [Account] = []
		/// Stored transactions that this run books, marks for review, or gives changed bank fields or a source ID,
		/// as a refresh would. User fields stay.
		public var updatedTransactions: [Transaction] = []
		/// Categories of an earlier run without a color of their own, with the color of MoneyMoney.
		public var updatedCategories: [Domain.Category] = []
		/// Deleted rows that take another source ID: the ID of the row of the source that they keep out, or none when
		/// the source no longer has their row. So a later run counts a deleted row of the source exactly while the source has it.
		public var relinkedDeletedRows: [DeletedTransaction.Relink] = []
		/// Accounts and transactions that the ledger already holds, and transactions the user deleted.
		public var skippedAccounts = 0
		public var skippedTransactions = 0
		/// The portfolio accounts of the export by name, and whether each one has a bank access, which fetches its positions.
		var portfolios: [(name: String, connected: Bool)] = []
		public var notes: [String] = []
		/// Each account of the export, in its order, for the report.
		public var sources: [SourceAccount] = []

		package func rebased(into ledger: Ledger, deleted: [DeletedTransaction], isCanceled: () -> Bool,
			progress: @escaping (Progress) -> Void) throws -> Self {
			try MoneyMoneyMigration(calendar: calendar).plan(accounts: exports.accounts, categories: exports.categories,
				transactions: exports.transactions, into: ledger, deleted: deleted, progress: progress, isCanceled: isCanceled)
		}

		/// The booking dates of the oldest and the newest transaction that the import adds, for the summary before
		/// the import. Nil when it adds none. A second run names only the days of its new transactions, as its count does.
		public var transactionDays: ClosedRange<Day>? {
			guard let first = transactions.first else { return nil }
			let (oldest, newest) = transactions.reduce((first.bookingDate, first.bookingDate)) { (min($0.0, $1.bookingDate), max($0.1, $1.bookingDate)) }
			return oldest...newest
		}

		public var isEmpty: Bool {
			groups.isEmpty && accounts.isEmpty && categories.isEmpty && transactions.isEmpty && updatedAccounts.isEmpty && updatedTransactions.isEmpty
				&& updatedCategories.isEmpty && relinkedDeletedRows.isEmpty
		}
	}

	public enum Failure: Error, CustomStringConvertible {
		/// The export of one kind of object is not the property list that the plan reads.
		public enum Export: Sendable {
			case accounts, categories, transactions
		}

		/// What holds an amount that fails, so the message can name it.
		public enum Amount: Sendable {
			/// A transaction with its ID in the export, if it has one.
			case transaction(Int?)
			case accountBalance(String)
			case groupBalance(String)
		}

		case unreadable(Export)
		/// An amount above `Money.maxMinorUnits`.
		case tooLarge(Amount)
		/// An amount that is not a finite number.
		case unreadableAmount(Amount)
		/// An initial balance derived from the bank balance that is above `Money.maxMinorUnits`, with the name of its account.
		case initialBalanceTooLarge(String)

		public var description: String {
			switch self {
			case .unreadable(.accounts): String(localized: "The export of the accounts could not be read.")
			case .unreadable(.categories): String(localized: "The export of the categories could not be read.")
			case .unreadable(.transactions): String(localized: "The export of the transactions could not be read.")
			// The ID is a String in the text, so it is not grouped like a number, as in "4.711".
			case let .tooLarge(.transaction(id?)): String(localized: "The amount of transaction \(String(id)) is too large.")
			case .tooLarge(.transaction(nil)): String(localized: "The amount of a transaction is too large.")
			case let .tooLarge(.accountBalance(name)): String(localized: "The balance of the account \"\(name)\" is too large.")
			case let .tooLarge(.groupBalance(name)): String(localized: "The balance of the group \"\(name)\" is too large.")
			case let .unreadableAmount(.transaction(id?)): String(localized: "The amount of transaction \(String(id)) cannot be read.")
			case .unreadableAmount(.transaction(nil)): String(localized: "The amount of a transaction cannot be read.")
			case let .unreadableAmount(.accountBalance(name)): String(localized: "The balance of the account \"\(name)\" cannot be read.")
			case let .unreadableAmount(.groupBalance(name)): String(localized: "The balance of the group \"\(name)\" cannot be read.")
			case let .initialBalanceTooLarge(name): String(localized: "The initial balance of the account \"\(name)\" is too large.")
			}
		}
	}

	public let calendar: Calendar

	public init(calendar: Calendar = .current) {
		self.calendar = calendar
	}

	/// Builds the plan. Objects that the ledger already holds are skipped, and changes the user made since
	/// then stay. Transactions are recognized by `reconcile`, the rule of refreshes and files, so a row that
	/// a refresh stored or whose ID a source took over is not added twice. `deleted` are all deleted rows,
	/// and none of them comes back, except the booked version of a deleted pending row.
	public func plan(accounts accountsData: Data, categories categoriesData: Data, transactions transactionsData: Data, into ledger: Ledger,
		deleted: [DeletedTransaction] = [], progress: @escaping (Progress) -> Void = { _ in }, isCanceled: () -> Bool = { Task.isCancelled }) throws -> Plan {
		if isCanceled() { throw CancellationError() }
		guard let rawAccounts = try PropertyListSerialization.propertyList(from: accountsData, format: nil) as? [[String: Any]] else {
			throw Failure.unreadable(.accounts)
		}
		guard let rawCategories = try PropertyListSerialization.propertyList(from: categoriesData, format: nil) as? [[String: Any]] else {
			throw Failure.unreadable(.categories)
		}
		guard let rawTransactionsRoot = try PropertyListSerialization.propertyList(from: transactionsData, format: nil) as? [String: Any],
			let rawTransactions = rawTransactionsRoot["transactions"] as? [[String: Any]] else {
			throw Failure.unreadable(.transactions)
		}

		var reporter = MigrationProgressReporter(progress)
		var plan = Plan(exports: Exports(accounts: accountsData, categories: categoriesData, transactions: transactionsData), calendar: calendar)
		var accountMap: [String: UUID] = [:]
		var sourceCurrencies: [String: String] = [:]
		try mapAccounts(rawAccounts, ledger: ledger, plan: &plan, map: &accountMap, currencies: &sourceCurrencies, isCanceled: isCanceled)
		var categoryMap: [String: UUID?] = [:]
		try mapCategories(rawCategories, ledger: ledger, plan: &plan, map: &categoryMap, isCanceled: isCanceled)

		var rows: [Transaction] = []
		var sourceRows: [String: [Transaction]] = [:]
		let names = Dictionary(accountMap.compactMap { source, id in
			(ledger.account(id) ?? plan.accounts.first { $0.id == id }).map { (source, $0.name) } }, uniquingKeysWith: { first, _ in first })
		reporter.send(.init(step: .transactions, total: rawTransactions.count))
		// A transaction without a currency is in the currency of its account in the source, also when it goes into an
		// account of another currency here. The same amount in another currency is another transaction, so a default of
		// EUR would add a stored USD row a second time.
		for (index, raw) in rawTransactions.enumerated() {
			if isCanceled() { throw CancellationError() }
			defer { reporter.send(.init(step: .transactions, completed: index + 1, total: rawTransactions.count, account: (raw["accountUuid"] as? String).flatMap { names[$0] })) }
			guard let accountSource = raw["accountUuid"] as? String, let accountID = accountMap[accountSource] else { continue }
			let id = (raw["id"] as? Int).map { "\(Transaction.migrationIDPrefix)\($0)" }
			let currency = (raw["currency"] as? String)?.uppercased() ?? sourceCurrencies[accountSource] ?? "EUR"
			let amount = try Self.money((raw["amount"] as? Double) ?? 0, currency, .transaction(raw["id"] as? Int))
			let booking = (raw["bookingDate"] as? Date).map { Day($0, calendar: calendar) } ?? Day.today(calendar: calendar)
			let pending = !((raw["booked"] as? Bool) ?? true)
			var categoryID: UUID?
			if let c = raw["categoryUuid"] as? String, let mapped = categoryMap[c] { categoryID = mapped }
			let t = Transaction(accountID: accountID, bookingDate: booking,
				valueDate: (raw["valueDate"] as? Date).map { Day($0, calendar: calendar) },
				amountMinor: amount.minorUnits, currency: currency,
				name: Self.string(raw["name"]) ?? "", purpose: Self.string(raw["purpose"]) ?? "",
				counterpartyIBAN: Self.string(raw["accountNumber"]).map(IBAN.electronicForm), counterpartyBIC: Self.string(raw["bankCode"]),
				bookingText: Self.string(raw["bookingText"]), endToEndReference: Self.string(raw["endToEndReference"]),
				mandateReference: Self.string(raw["mandateReference"]), creditorID: Self.string(raw["creditorId"]),
				comment: Self.string(raw["comment"]), isChecked: (raw["checkmark"] as? Bool) ?? false, isPending: pending,
				categoryID: categoryID, categorizedBy: categoryID == nil ? .none : .manual, isNew: false, sourceID: id)
			rows.append(t)
			sourceRows[accountSource, default: []].append(t)
		}

		let delivered = Dictionary(grouping: rows, by: \.accountID)
		for i in plan.sources.indices { plan.sources[i].rows = sourceRows[plan.sources[i].sourceID] ?? [] }

		// `reconcile` decides which rows are new. A new row keeps what MoneyMoney says: its category, comment,
		// and checkmark, and no new mark. Only the review mark comes from `reconcile`.
		let stored = Dictionary(grouping: ledger.transactions, by: \.accountID)
		let tombstones = Dictionary(grouping: deleted, by: \.accountID)
		let rules = Categorizer(ledger: ledger)
		let totalTransactions = rows.count
		reporter.send(.init(step: .reconciling, total: totalTransactions))
		// One pass of the rules over all accounts, so a rule that stops in a later account matches none in an earlier one.
		let merged = try rules.allOrNothing {
			var added: [UUID: ReviewReason?] = [:]
			var relinked: [UUID: [DeletedTransaction.Relink]] = [:]
			var updated: [Transaction] = []
			var skipped = 0
			var compared = 0
			for account in ledger.accounts + plan.accounts {
				if isCanceled() { throw CancellationError() }
				guard let rows = delivered[account.id] else { continue }
				let r = try reconcile(.migration(rows), into: account, stored: stored[account.id] ?? [], deleted: tombstones[account.id] ?? [],
					rules: rules, now: Date(), checkpoint: { completed in
						if isCanceled() { throw CancellationError() }
						reporter.send(.init(step: .reconciling, completed: compared + completed, total: totalTransactions, account: account.name))
					})
				for t in r.added { added.updateValue(t.review, forKey: t.id) }
				updated += r.booked + r.updated + r.marked
				skipped += r.skipped
				relinked[account.id] = r.relinked
				compared += rows.count
				reporter.send(.init(step: .reconciling, completed: compared, total: totalTransactions, account: account.name))
			}
			return (added: added, relinked: relinked, updated: updated, skipped: skipped)
		}
		let added = merged.added
		let relinked = merged.relinked
		plan.updatedTransactions += merged.updated
		plan.skippedTransactions += merged.skipped
		for var t in rows {
			if isCanceled() { throw CancellationError() }
			guard let review = added[t.id] else { continue }
			t.review = review
			plan.transactions.append(t)
		}
		try Self.setInitialBalances(of: &plan, ledger: ledger, stored: stored, deleted: tombstones, relinked: relinked, exported: Set(accountMap.values),
			delivered: delivered.mapValues { Set($0.compactMap(\.sourceID)) })
		if !rawCategories.contains(where: { ($0["default"] as? Bool) != true && Self.string($0["rules"]) != nil }) {
			plan.notes.append(String(localized: "The export contains no categorization rules. Copy them from the category settings of MoneyMoney into the category settings of Moneten."))
		}
		let accountNumbers = Set(rawAccounts.filter { ($0["uuid"] as? String).flatMap { accountMap[$0] } != nil }
			.flatMap { [Self.string($0["accountNumber"]), Self.string($0["iban"])] }.compactMap { $0 }.map(TextFolding.accountKey)
			+ rows.compactMap(\.counterpartyIBAN).map(TextFolding.accountKey))
		let exportedRules = rawCategories.reduce(into: [String: String]()) { rules, item in
			if let source = item["uuid"] as? String { rules[source] = Self.string(item["rules"]) ?? "" }
		}
		let unchangedCategories = ledger.categories.filter { c in
			guard let source = c.sourceID else { return false }
			return exportedRules[source] == c.rule
		}
		for c in plan.categories + unchangedCategories {
			if isCanceled() { throw CancellationError() }
			if let error = c.ruleError {
				plan.notes.append(String(localized: "The rule of \"\(c.name)\" cannot be read at position \(error.position + 1): \(error.message) \"\(c.name)\" receives no transaction through its rule until you correct the rule in its settings."))
			}
			plan.notes += Self.ruleNotes(c, accountNumbers: accountNumbers)
		}
		plan.notes += try Self.groupSumNotes(rawAccounts)
		for portfolio in plan.portfolios {
			let name = portfolio.name
			plan.notes.append(portfolio.connected
				? String(localized: "The positions of \"\(name)\" were not migrated, because the portfolio export format is not verified. Its bank access fetches them with each refresh.")
				: String(localized: "The positions of \"\(name)\" were not migrated, because the portfolio export format is not verified. Connect the portfolio to its bank to fetch its positions."))
		}
		plan.notes += Self.notMigratedNotes
		let budgets = rawCategories.filter(Self.hasBudget).count
		if budgets == 1 {
			plan.notes.append(String(localized: "1 category has a budget in MoneyMoney. Moneten did not take the budget over."))
		} else if budgets > 1 {
			plan.notes.append(String(localized: "\(budgets) categories have a budget in MoneyMoney. Moneten did not take the budgets over."))
		}
		if (rawAccounts + rawCategories).contains(where: { $0["icon"] is Data }) {
			plan.notes.append(String(localized: "Moneten takes the color of each icon of MoneyMoney and shows its own icons instead of the pictures."))
		}
		if isCanceled() { throw CancellationError() }
		return plan
	}

	private static func ruleNotes(_ category: Domain.Category, accountNumbers: Set<String>) -> [String] {
		guard !category.isGroup, !category.isDefault, let tokens = try? RuleToken.positioned(in: category.rule) else { return [] }
		let chars = Array(category.rule)
		let name = category.name
		var notes: [String] = []
		for (i, entry) in tokens.enumerated() {
			if i > 0, case .field = tokens[i - 1].token { continue }
			switch entry.token {
			case let .word(term), let .quoted(term):
				let number = TextFolding.accountKey(term)
				let groups = term.split(separator: " ", omittingEmptySubsequences: false)
				let grouped = groups.count == 1 || (groups.dropLast().allSatisfy { $0.count == 4 } && (1...4).contains(groups.last!.count))
				let iban = term.utf8.allSatisfy { $0 < 128 } && grouped && IBAN(number) != nil
				let knownNumber = !number.isEmpty && number.allSatisfy { $0.isASCII && $0.isNumber } && accountNumbers.contains(number)
				if iban || knownNumber {
					notes.append(String(localized: "The rule of \"\(name)\" has an account term at position \(entry.position + 1) that does not search account fields. Use remote_account:\(number) to search the account of the counterparty."))
				}
			case .and, .or, .not:
				let length = entry.token == .or ? 2 : 3
				let word = String(chars[entry.position...].prefix(length))
				if ["and", "or", "not"].contains(word.lowercased()), word != word.uppercased() {
					notes.append(String(localized: "The rule of \"\(name)\" reads \"\(word)\" at position \(entry.position + 1) as an operator. Write \"\(word)\" in quotation marks to search the word itself."))
				}
			case let .constant(value):
				let word = String(chars[entry.position...].prefix(value ? 4 : 5))
				notes.append(value
					? String(localized: "The rule of \"\(name)\" reads \"\(word)\" at position \(entry.position + 1) as a constant that matches every transaction. Write \"\(word)\" in quotation marks to search the word itself.")
					: String(localized: "The rule of \"\(name)\" reads \"\(word)\" at position \(entry.position + 1) as a constant that matches no transaction. Write \"\(word)\" in quotation marks to search the word itself."))
			default: break
			}
		}
		return notes
	}

	/// The initial balance makes the booked rows of the source end at the balance of the source. A later run
	/// moves it by what changed in the source since the run before, so a row that the user imported or deleted
	/// keeps moving the balance, and so does an initial balance that the user typed.
	///
	/// A row that the user deleted counts as a row of the source while it carries a migration ID. It takes the ID
	/// of the row of the source that it keeps out, also one that it matched by its fingerprint. The export holds every
	/// transaction of an exported account, so a deleted row whose ID it leaves out is gone from the source: it counts
	/// before this run and not after, and the store forgets its source ID, so no later run counts it again.
	/// A deleted row in another currency never moves the balance, like a stored one.
	private static func setInitialBalances(of plan: inout Plan, ledger: Ledger, stored: [UUID: [Transaction]],
		deleted: [UUID: [DeletedTransaction]], relinked: [UUID: [DeletedTransaction.Relink]], exported: Set<UUID>,
		delivered: [UUID: Set<String>]) throws {
		// An initial balance is stored, so one above `Money.maxMinorUnits` fails the migration instead of holding at a bound.
		func limited(_ value: Int128, of account: Account) throws -> Int64 {
			guard let minor = Int64(limitedAmount: value) else { throw Failure.initialBalanceTooLarge(account.name) }
			return minor
		}
		let added = Dictionary(grouping: plan.transactions, by: \.accountID)
		for i in plan.accounts.indices {
			guard let balance = plan.accounts[i].bankBalanceMinor else { continue }
			plan.accounts[i].initialBalanceMinor = try limited(initialBalance(balance, of: plan.accounts[i], rows: added[plan.accounts[i].id] ?? []), of: plan.accounts[i])
		}
		let changed = Dictionary(uniqueKeysWithValues: plan.updatedTransactions.map { ($0.id, $0) })
		for old in ledger.accounts where old.source == .migrated && old.kind != .portfolio {
			let tombstones = exported.contains(old.id) ? deleted[old.id] ?? [] : []
			var after = tombstones
			for r in relinked[old.id] ?? [] {
				if let i = after.firstIndex(of: r.row) { after[i].sourceID = r.sourceID }
			}
			for i in after.indices where isCounted(after[i]) && after[i].sourceID.map((delivered[old.id] ?? []).contains) == false {
				after[i].sourceID = nil
			}
			plan.relinkedDeletedRows += zip(tombstones, after).compactMap { $0.sourceID == $1.sourceID ? nil : DeletedTransaction.Relink(row: $0, sourceID: $1.sourceID) }
			let k = plan.updatedAccounts.firstIndex { $0.id == old.id }
			var a = k.map { plan.updatedAccounts[$0] } ?? old
			guard let balance = a.bankBalanceMinor else { continue }
			let before = stored[old.id] ?? []
			let deletedBefore = tombstones.filter { isCounted($0) && $0.currency == old.currency }.reduce(Int128(0)) { $0 + Int128($1.amountMinor) }
			let deletedAfter = after.filter { isCounted($0) && $0.currency == old.currency }.reduce(Int128(0)) { $0 + Int128($1.amountMinor) }
			let target = initialBalance(balance, of: a, rows: before.map { changed[$0.id] ?? $0 } + (added[old.id] ?? [])) - deletedAfter
			a.initialBalanceMinor = try limited(old.bankBalanceMinor.map {
				Int128(old.initialBalanceMinor) + target - (initialBalance($0, of: old, rows: before) - deletedBefore)
			} ?? target, of: old)
			if let k {
				plan.updatedAccounts[k] = a
			} else if a != old {
				plan.updatedAccounts.append(a)
			}
		}
	}

	/// The balance before the booked rows of the source in the account currency. A row of the source carries a
	/// migration ID. A row that the user imported carries none, and a row that a file or a bank booked while the
	/// source has it pending carries the booked form of the ID, so both count on top. `v13` in `Schema` repairs stored
	/// values by the same rule, so this filter is spelled out here and in its SQL.
	private static func initialBalance(_ balance: Int64, of account: Account, rows: [Transaction]) -> Int128 {
		rows.reduce(Int128(balance)) { sum, t in
			!t.isPending && t.currency == account.currency && isOfSource(t.sourceID) ? sum - Int128(t.amountMinor) : sum
		}
	}

	static func isOfSource(_ sourceID: String?) -> Bool {
		sourceID?.hasPrefix(Transaction.migrationIDPrefix) == true
	}

	private static func isCounted(_ deleted: DeletedTransaction) -> Bool {
		!deleted.isPending && isOfSource(deleted.sourceID)
	}

	private func mapAccounts(_ raw: [[String: Any]], ledger: Ledger, plan: inout Plan, map: inout [String: UUID], currencies: inout [String: String],
		isCanceled: () -> Bool) throws {
		var parents: [Int: UUID] = [:]
		var positions: [UUID?: Int] = [:]
		for item in raw {
			if isCanceled() { throw CancellationError() }
			guard let source = item["uuid"] as? String, let name = item["name"] as? String else { continue }
			let indentation = (item["indentation"] as? Int) ?? 0
			let parent = indentation > 0 ? parents[indentation - 1] : nil
			let position = positions[parent, default: 0]
			positions[parent] = position + 1
			if (item["group"] as? Bool) == true {
				let id = ledger.groups.first(where: { $0.name == name && $0.parentID == parent })?.id
				if let id {
					parents[indentation] = id
				} else {
					let g = AccountGroup(name: name, parentID: parent, position: position)
					plan.groups.append(g)
					parents[indentation] = g.id
				}
				continue
			}
			let isPortfolio = (item["portfolio"] as? Bool) == true || Self.kind(item["type"] as? String) == .portfolio
			if isPortfolio { plan.portfolios.append((name, false)) }
			// MoneyMoney puts the IBAN into `accountNumber` and the BIC into `bankCode`.
			let number = Self.string(item["accountNumber"])
			let bankCode = Self.string(item["bankCode"])
			let ibanText = Self.string(item["iban"]) ?? number.flatMap { IBAN($0) == nil ? nil : $0 }
			let iban = ibanText.flatMap(IBAN.init)
			// An account whose bank sent an invalid IBAN keeps that text as its account number (`Account.takeIBAN(_:)`), and
			// MoneyMoney gives it as the IBAN or as the account number with the BIC as `bankCode`. Text in the shape of an IBAN
			// whose check digits fail is no plain account number, so it matches without a bank code. Any other text matches only
			// with its bank code.
			let invalidIBAN: String? = [Self.string(item["iban"]), number].compactMap { $0 }.first(where: Self.isInvalidIBAN).map(TextFolding.accountKey)
			let bic = Self.string(item["bic"]) ?? bankCode.flatMap { Self.isBIC($0) ? $0 : nil }
			var balanceMinor: Int64?
			var currency = (item["currency"] as? String)?.uppercased() ?? "EUR"
			if let balance = item["balance"] as? [[Any]], let first = balance.first, first.count >= 2,
				let amount = first[0] as? Double, let c = (first[1] as? String)?.uppercased() {
				currency = c
				balanceMinor = try Self.money(amount, c, .accountBalance(name)).minorUnits
			}
			currencies[source] = currency
			let balanceDate = (item["balanceDate"] as? Date) ?? (item["refreshTimestamp"] as? Date)
			let color = (item["icon"] as? Data).flatMap(Self.iconColor)
			defer { if let id = map[source] { plan.sources.append(SourceAccount(sourceID: source, name: name, accountID: id, balance: balanceMinor.map { Money(minorUnits: $0, currency: currency) })) } }
			// The MoneyMoney identifier decides. IBAN or account number match only accounts without one,
			// so that two MoneyMoney accounts with the same IBAN stay apart.
			if var existing = ledger.accounts.first(where: { $0.sourceID == source }) ?? ledger.accounts.first(where: { a in
				a.sourceID == nil && (
					(iban != nil && a.iban == iban)
						|| (invalidIBAN != nil && a.iban == nil && a.accountNumber.map { TextFolding.accountKey($0) } == invalidIBAN)
						|| (bankCode != nil && number != nil && a.bankCode == bankCode && a.accountNumber == number))
			}) {
				map[source] = existing.id
				plan.skippedAccounts += 1
				if isPortfolio, existing.accessID != nil { plan.portfolios[plan.portfolios.count - 1].connected = true }
				var changed = false
				if existing.source == .migrated, let balanceMinor, existing.bankBalanceMinor != balanceMinor || existing.bankBalanceDate != balanceDate {
					existing.bankBalanceMinor = balanceMinor
					existing.bankBalanceDate = balanceDate
					changed = true
				}
				// An account of an earlier run gets the color of its MoneyMoney icon, unless the user chose one.
				if let color, existing.color == nil {
					existing.color = color
					changed = true
				}
				if changed { plan.updatedAccounts.append(existing) }
				continue
			}
			var account = Account(groupID: parent, position: position, name: name,
				kind: isPortfolio ? .portfolio : Self.kind(item["type"] as? String),
				source: .migrated, currency: currency, bic: bic,
				accountNumber: number, bankCode: bankCode, owner: Self.string(item["owner"]),
				bankBalanceMinor: balanceMinor, bankBalanceDate: balanceDate,
				comment: Self.string(item["comment"]), sourceID: source, color: color)
			account.takeIBAN(ibanText)
			plan.accounts.append(account)
			map[source] = account.id
		}
	}

	private func mapCategories(_ raw: [[String: Any]], ledger: Ledger, plan: inout Plan, map: inout [String: UUID?], isCanceled: () -> Bool) throws {
		var parents: [Int: UUID] = [:]
		var positions: [UUID?: Int] = [:]
		let known = ledger.categories + plan.categories
		for item in raw {
			if isCanceled() { throw CancellationError() }
			guard let source = item["uuid"] as? String, let name = item["name"] as? String else { continue }
			if (item["default"] as? Bool) == true {
				// The default category of MoneyMoney maps to the default category: its transactions get no category.
				map[source] = .some(nil)
				continue
			}
			let indentation = (item["indentation"] as? Int) ?? 0
			let parent = indentation > 0 ? parents[indentation - 1] : nil
			let position = positions[parent, default: 0]
			positions[parent] = position + 1
			let isGroup = (item["group"] as? Bool) == true
			if isGroup, Self.string(item["rules"]) != nil {
				plan.notes.append(String(localized: "The rule of the group \"\(name)\" was not taken over, because a group holds no transactions. Move it to a category below the group."))
			}
			let color = (item["icon"] as? Data).flatMap(Self.iconColor)
			if let existing = known.first(where: { $0.sourceID == source || ($0.name == name && $0.parentID == parent && !$0.isDefault) }) {
				map[source] = existing.id
				if isGroup { parents[indentation] = existing.id }
				// A category of an earlier run gets the color of MoneyMoney, unless the user chose one.
				if let color, existing.color == nil, !plan.categories.contains(where: { $0.id == existing.id }),
					!plan.updatedCategories.contains(where: { $0.id == existing.id }) {
					var updated = existing
					updated.color = color
					plan.updatedCategories.append(updated)
				}
				continue
			}
			// A group holds no transactions of its own, so the app gives it no rule.
			let c = Domain.Category(parentID: parent, position: position, name: name, isGroup: isGroup, color: color,
				currency: (item["currency"] as? String)?.uppercased() ?? "EUR", rule: isGroup ? "" : Self.string(item["rules"]) ?? "", sourceID: source)
			plan.categories.append(c)
			map[source] = c.id
			if isGroup { parents[indentation] = c.id }
		}
	}

	/// The color of a MoneyMoney category or account, such as "#4A90E2". The export has no color, but
	/// MoneyMoney draws the icon of a category or an account in its color, so this is the mean of the
	/// opaque colored pixels of the icon, or of its opaque pixels when the icon is gray. Nil for an
	/// empty or unreadable icon.
	static func iconColor(_ data: Data) -> String? {
		guard let source = CGImageSourceCreateWithData(data as CFData, nil), let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
			let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
		let width = min(image.width, 64), height = min(image.height, 64)
		guard width > 0, height > 0 else { return nil }
		var pixels = [UInt8](repeating: 0, count: width * height * 4)
		let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
			guard let context = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
				space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
			context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
			return true
		}
		guard drawn else { return nil }
		var colored = (0.0, 0.0, 0.0, 0.0), opaque = (0.0, 0.0, 0.0, 0.0)
		for i in stride(from: 0, to: pixels.count, by: 4) where pixels[i + 3] >= 128 {
			let alpha = Double(pixels[i + 3])
			let r = Double(pixels[i]) * 255 / alpha, g = Double(pixels[i + 1]) * 255 / alpha, b = Double(pixels[i + 2]) * 255 / alpha
			opaque = (opaque.0 + r, opaque.1 + g, opaque.2 + b, opaque.3 + 1)
			let high = max(r, g, b), low = min(r, g, b)
			// Outlines, shadows, and highlights are dark or gray. They would pull the color toward gray.
			if high > 40, (high - low) / high > 0.25 { colored = (colored.0 + r, colored.1 + g, colored.2 + b, colored.3 + 1) }
		}
		let sum = colored.3 > 0 ? colored : opaque
		guard sum.3 > 0 else { return nil }
		func byte(_ v: Double) -> Int { min(255, max(0, Int((v / sum.3).rounded()))) }
		return String(format: "#%02X%02X%02X", byte(sum.0), byte(sum.1), byte(sum.2))
	}

	/// The scripting dictionary of MoneyMoney has no command that exports these.
	static let notMigratedNotes = [
		String(localized: "Login data was not migrated, because the AppleScript export of MoneyMoney does not contain it. Connect a migrated account to its bank with \"Add Account...\" and enter the login data there."),
		String(localized: "Transfer templates were not migrated, because the AppleScript export of MoneyMoney does not contain them. Use \"Export Transfer Templates...\" in MoneyMoney to keep them."),
		String(localized: "Standing orders were not migrated, because the AppleScript export of MoneyMoney does not contain them. Your bank keeps them, so they continue as before."),
		String(localized: "Statements were not migrated, because the AppleScript export of MoneyMoney does not contain them. Use \"Show in Finder...\" on \"Statements\" in MoneyMoney to find the statement files and copy them to keep them."),
	]

	/// The key layout of a budget in `export categories` was not recorded with the real export. A
	/// `budget` counts when it is a number other than zero, or a dictionary whose `amount` is one. A
	/// dictionary without `amount` counts when it has such a number. A budget of zero counts as none.
	static func hasBudget(_ item: [String: Any]) -> Bool {
		// A cast to Double also accepts a Boolean, so a flag such as a rollover would count as 1. A list such as
		// [[200.0, "EUR"]] is the form of a balance in the same export.
		func amount(_ value: Any?) -> Double? {
			if let list = value as? [Any] { return amount((list.first as? [Any])?.first) }
			guard let n = value as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID() else { return nil }
			return n.doubleValue
		}
		switch item["budget"] {
		case let budget as [String: Any]:
			if let value = budget["amount"] { return amount(value).map { $0 != 0 } ?? false }
			return budget.values.contains { amount($0).map { $0 != 0 } ?? false }
		case let value: return amount(value).map { $0 != 0 } ?? false
		}
	}

	/// Lists the groups whose balance in MoneyMoney differs from the sum of their accounts.
	/// MoneyMoney leaves closed accounts out of the sum of their group, and the export does not say
	/// which accounts are closed.
	static func groupSumNotes(_ raw: [[String: Any]]) throws -> [String] {
		func balances(_ item: [String: Any]) throws -> [String: Decimal] {
			var r: [String: Decimal] = [:]
			let name = item["name"] as? String ?? ""
			let what: Failure.Amount = (item["group"] as? Bool) == true ? .groupBalance(name) : .accountBalance(name)
			for case let entry as [Any] in (item["balance"] as? [Any]) ?? [] where entry.count >= 2 {
				if let amount = entry[0] as? Double, let currency = entry[1] as? String {
					r[currency, default: 0] += try money(amount, currency, what).decimal
				}
			}
			return r
		}
		var notes: [String] = []
		for (i, item) in raw.enumerated() where (item["group"] as? Bool) == true {
			let indentation = (item["indentation"] as? Int) ?? 0
			var sum: [String: Decimal] = [:]
			for child in raw[(i + 1)...] {
				if ((child["indentation"] as? Int) ?? 0) <= indentation { break }
				if (child["group"] as? Bool) == true { continue }
				for (c, v) in try balances(child) { sum[c, default: 0] += v }
			}
			let shown = try balances(item)
			let currencies = Set(shown.keys).union(sum.keys)
			if currencies.contains(where: { shown[$0, default: 0] != sum[$0, default: 0] }) {
				notes.append(String(localized: "The group \"\(item["name"] as? String ?? "")\" has a different balance in MoneyMoney than the sum of its accounts. MoneyMoney leaves closed accounts out of the sum, and its export does not say which accounts are closed. Turn on \"The account has been closed\" in the settings of each closed account of this group."))
			}
		}
		return notes
	}

	/// An amount of the export, named by `what` in the error, such as the transaction 4711. A number that is
	/// not finite fails before its conversion, because `Decimal(Double.infinity)` stops the app.
	static func money(_ value: Double, _ currency: String, _ what: Failure.Amount) throws -> Money {
		guard value.isFinite else { throw Failure.unreadableAmount(what) }
		guard let money = Money(fitting: Decimal(value), currency: currency) else { throw Failure.tooLarge(what) }
		return money
	}

	/// Text in the shape of an IBAN whose check digits do not fit: after folding only ASCII letters and digits, the country
	/// code of an IBAN country, two digits, and the length of an IBAN of that country. Text that merely starts with a
	/// country code, such as "DE4711" or "FR-4711", is an account number of its bank and matches only with its bank code.
	private static func isInvalidIBAN(_ text: String) -> Bool {
		do {
			_ = try IBAN(parsing: text)
			return false
		} catch {
			// The error `checksum` means that the country and the length fit.
			guard error == .checksum else { return false }
			let compact = TextFolding.accountKey(text).utf8
			let isDigit = { (c: UInt8) in c >= UInt8(ascii: "0") && c <= UInt8(ascii: "9") }
			return compact.allSatisfy { isDigit($0) || ($0 >= UInt8(ascii: "A") && $0 <= UInt8(ascii: "Z")) }
				&& compact.dropFirst(2).prefix(2).allSatisfy(isDigit)
		}
	}

	static func isBIC(_ value: String) -> Bool {
		let s = value.uppercased()
		guard s.count == 8 || s.count == 11, s.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber) }) else { return false }
		return s.prefix(6).allSatisfy(\.isLetter)
	}

	static func string(_ value: Any?) -> String? {
		guard let s = value as? String else { return nil }
		let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
		return t.isEmpty ? nil : t
	}

	static func kind(_ type: String?) -> AccountKind {
		switch type ?? "" {
		case "Giro account", "Girokonto": .giro
		case "Savings account", "Sparkonto", "Tagesgeld", "Tagesgeldkonto": .savings
		case "Fixed term deposit", "Festgeldkonto", "Festgeldanlage": .fixedTermDeposit
		case "Loan account", "Darlehenskonto": .loan
		case "Credit card", "Kreditkarte": .creditCard
		case "Cash account", "Bargeld": .cash
		case "Portfolio", "Depot": .portfolio
		default: .other
		}
	}
}

/// Sends the export commands only to the running MoneyMoney process.
public enum MoneyMoneyExporter {
	public enum Failure: Error, CustomStringConvertible, Equatable {
		case notInstalled
		case notRunning
		case locked
		case notAllowed
		case failed(String)

		public var description: String {
			switch self {
			case .notInstalled:
				String(localized: "MoneyMoney is not installed on this Mac. You can import transactions from CSV, CAMT, or MT940 files into an account instead.")
			case .notRunning:
				String(localized: "MoneyMoney is not running. Open MoneyMoney and unlock it, then choose \"Check again\".")
			case .locked:
				String(localized: "MoneyMoney is locked. Unlock MoneyMoney with its database password, then choose \"Check again\".")
			case .notAllowed:
				String(localized: "macOS does not allow Moneten to read data from MoneyMoney. Allow it in System Settings → Privacy & Security → Automation → Moneten, then choose \"Check again\".")
			case let .failed(message):
				String(localized: "MoneyMoney did not answer: \(message)")
			}
		}

		static func of(code: Int, message: String) -> Failure {
			switch code {
			case -1743: .notAllowed
			case -2720: .locked
			case -600, -609: .notRunning
			default: message.localizedCaseInsensitiveContains("locked") ? .locked : .failed(message.trimmingCharacters(in: .whitespacesAndNewlines))
			}
		}
	}

	// MoneyMoney.sdef defines these export events and their parameters.
	enum Command: UInt32, Sendable {
		case accounts = 0x65787061
		case categories = 0x65787063
		case transactions = 0x65787074
	}

	public static func exportAccounts() async throws -> Data { try await run(.accounts) }
	public static func exportCategories() async throws -> Data { try await run(.categories) }
	public static func exportTransactions() async throws -> Data { try await run(.transactions) }

	static func run(_ command: Command, bundleIdentifier: String = "com.moneymoney-app.retail", applicationURL: URL? = nil,
		send: @escaping @Sendable (NSAppleEventDescriptor) throws -> NSAppleEventDescriptor = { try $0.sendEvent(options: .waitForReply, timeout: 120) }) async throws -> Data {
		guard (applicationURL ?? NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier)) != nil else { throw Failure.notInstalled }
		return try await withCheckedThrowingContinuation { continuation in
			DispatchQueue.global(qos: .userInitiated).async {
				do {
					guard let application = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).first(where: { !$0.isTerminated }) else {
						throw Failure.notRunning
					}
					let event = NSAppleEventDescriptor(eventClass: 0x4d4f4e59, eventID: command.rawValue,
						targetDescriptor: NSAppleEventDescriptor(processIdentifier: application.processIdentifier), returnID: -1, transactionID: 0)
					if command == .transactions {
						event.setParam(NSAppleEventDescriptor(string: "1990-01-01"), forKeyword: 0x66726474)
						event.setParam(NSAppleEventDescriptor(string: "plist"), forKeyword: 0x66726d74)
					}
					let reply = try send(event)
					if let code = reply.paramDescriptor(forKeyword: 0x6572726e)?.int32Value, code != 0 {
						throw Failure.of(code: Int(code), message: reply.paramDescriptor(forKeyword: 0x65727273)?.stringValue ?? "Error \(code)")
					}
					guard let text = reply.paramDescriptor(forKeyword: 0x2d2d2d2d)?.stringValue else { throw Failure.failed(String(localized: "The export returned no property list.")) }
					continuation.resume(returning: Data(text.utf8))
				} catch let failure as Failure {
					continuation.resume(throwing: failure)
				} catch {
					let error = error as NSError
					continuation.resume(throwing: Failure.of(code: error.code, message: error.localizedDescription))
				}
			}
		}
	}
}
