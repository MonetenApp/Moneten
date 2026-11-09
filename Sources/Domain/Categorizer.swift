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
			guard !c.isDefault, !c.rule.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
				let rule = try? Rule(parsing: c.rule) else { return nil }
			var restriction: Set<UUID>?
			if let r = c.restrictedToID {
				restriction = ledger.account(r) != nil ? [r] : ledger.accountIDs(inGroupTree: r)
			}
			return Entry(categoryID: c.id, rule: rule, accounts: restriction)
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
	public static func apply(category: Category, rule: Rule, to transactions: [Transaction], ledger: Ledger, mode: RuleApplication) -> [Transaction] {
		var restriction: Set<UUID>?
		if let r = category.restrictedToID {
			restriction = ledger.account(r) != nil ? [r] : ledger.accountIDs(inGroupTree: r)
		}
		var changed: [Transaction] = []
		for var t in transactions {
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
}
