import Foundation

/// Assigns categories to transactions with the rules of all categories.
///
/// The first category in sidebar order whose rule matches wins. A category that is
/// restricted to an account or account group only takes transactions of that account.
public struct Categorizer: Sendable {
	struct Entry: Sendable {
		let categoryID: UUID
		let rule: Rule
		let accounts: Set<UUID>?
	}

	let entries: [Entry]
	let accountsByID: [UUID: Account]

	public init(ledger: Ledger) {
		accountsByID = Dictionary(uniqueKeysWithValues: ledger.accounts.map { ($0.id, $0) })
		entries = ledger.categoriesInSidebarOrder.compactMap { c in
			guard let rule = try? c.savedRule() else { return nil }
			return Entry(categoryID: c.id, rule: rule, accounts: ledger.allowedAccounts(of: c))
		}
	}

	/// The category whose rule matches first, or nil.
	public func category(for t: Transaction) -> UUID? {
		let subject = RuleSubject(t, account: accountsByID[t.accountID])
		for e in entries {
			if let accounts = e.accounts, !accounts.contains(t.accountID) { continue }
			if e.rule.matches(subject) { return e.categoryID }
		}
		return nil
	}

	/// Sets the category of a transaction that has none, or whose category came from a rule.
	/// A manual choice stays.
	public func categorize(_ t: inout Transaction) {
		guard t.categorizedBy != .manual else { return }
		if let c = category(for: t) {
			t.categoryID = c
			t.categorizedBy = .rule
		} else {
			t.categoryID = nil
			t.categorizedBy = .none
		}
	}
}

/// How a changed rule is applied to transactions that already exist.
public enum RuleApplication: Sendable {
	/// "Apply only to not yet categorized transactions."
	case uncategorizedOnly
	/// "Apply to all transactions."
	case all
}

public enum RuleApplier {
	/// Applies the rule of one category to existing transactions and returns the changed ones.
	/// `progress` gets the count of checked transactions after every 1,000 and after the last one.
	/// A cancelled task stops the run, and it returns no changes.
	public static func apply(category: Category, rule: Rule, to transactions: [Transaction], ledger: Ledger, mode: RuleApplication,
		progress: (Int) -> Void = { _ in }) -> [Transaction] {
		let restriction = ledger.allowedAccounts(of: category)
		var changed: [Transaction] = []
		for (i, var t) in transactions.enumerated() {
			guard !Task.isCancelled else { return [] }
			defer { if (i + 1) % 1_000 == 0 || i + 1 == transactions.count { progress(i + 1) } }
			guard ledger.parts(of: t.id).isEmpty else { continue }
			let inScope = restriction.map { $0.contains(t.accountID) } ?? true
			let matches = inScope && rule.matches(RuleSubject(t, account: ledger.account(t.accountID)))
			switch mode {
			case .uncategorizedOnly:
				guard t.categoryID == nil, matches else { continue }
				t.categoryID = category.id
				t.categorizedBy = .rule
			case .all:
				if matches {
					guard t.categoryID != category.id || t.categorizedBy != .rule else { continue }
					t.categoryID = category.id
					t.categorizedBy = .rule
				} else if t.categoryID == category.id {
					t.categoryID = nil
					t.categorizedBy = .none
				} else {
					continue
				}
			}
			changed.append(t)
		}
		return changed
	}

	public static func matchCount(category: Category, rule: Rule, ledger: Ledger) -> Int {
		let restriction = ledger.allowedAccounts(of: category)
		return ledger.transactions.reduce(0) { count, transaction in
			guard ledger.parts(of: transaction.id).isEmpty,
				restriction.map({ $0.contains(transaction.accountID) }) ?? true else { return count }
			return count + (rule.matches(RuleSubject(transaction, account: ledger.account(transaction.accountID))) ? 1 : 0)
		}
	}

	/// The rows to save for a run of `apply` on `snapshot` when the ledger is now `current`. A row that is the
	/// same as in the snapshot takes the result of the run, a row that changed or arrived since is checked again
	/// against `current`, and a row that `current` no longer holds drops out.
	public static func rebase(_ results: [Transaction], from snapshot: Ledger, onto current: Ledger,
		category: Category, rule: Rule, mode: RuleApplication) -> [Transaction] {
		let changedSince = current.transactions.filter {
			snapshot.transaction($0.id) != $0 || snapshot.parts(of: $0.id).isEmpty != current.parts(of: $0.id).isEmpty
		}
		let rechecked = Set(changedSince.map(\.id))
		let kept = results.filter { !rechecked.contains($0.id) && current.transaction($0.id) != nil && current.parts(of: $0.id).isEmpty }
		return kept + apply(category: category, rule: rule, to: changedSince, ledger: current, mode: mode)
	}
}

extension Category {
	/// The rule that `Categorizer` applies, or nil when the category has none.
	/// A group has none, even with a migrated rule, because it holds no transactions of its own.
	/// `ruleError` reads the same result, so a category whose saved rule the categorizer cannot read always shows the mark.
	func savedRule() throws(RuleSyntaxError) -> Rule? {
		guard !isDefault, !isGroup, !rule.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
		return try Rule(parsing: rule)
	}

	/// The error of a saved rule that the app cannot parse, such as one that an older version accepted.
	/// `Categorizer` leaves such a category out, so it gets no new transactions until the user fixes the rule.
	public var ruleError: RuleSyntaxError? {
		do {
			_ = try savedRule()
			return nil
		} catch {
			return error
		}
	}
}
