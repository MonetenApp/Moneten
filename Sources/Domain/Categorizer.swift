import Foundation
import Synchronization

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
	/// The decision for the texts of each row, so a row with the same texts and every row of a repeat of `allOrNothing`
	/// read it instead of building the `RuleSubject` and testing the rules again.
	private let memo = Memo()

	/// The processor time that the slow regex calls of all rules of one categorizer may spend together. Each rule also
	/// stops by its own limits, so this bounds a batch with many slow rules: twelve rules of one second each would
	/// otherwise take twelve seconds. Only calls of `Rule.heavyCall` or more count, because 20 normal rules over a long
	/// history take 3 seconds too.
	static let batchLimit: UInt64 = 3_000_000_000

	public init(ledger: Ledger) {
		accountsByID = Dictionary(uniqueKeysWithValues: ledger.accounts.map { ($0.id, $0) })
		entries = ledger.categoriesInSidebarOrder.compactMap { c in
			guard let rule = try? c.savedRule() else { return nil }
			return Entry(categoryID: c.id, rule: rule, accounts: ledger.allowedAccounts(of: c))
		}
	}

	/// A text as its bytes. Swift compares strings by canonical equivalence, so "é" and "e" with a combining accent are
	/// equal, but a regular expression reads the code points and can tell them apart.
	private struct Raw: Hashable {
		let text: String?

		static func == (a: Raw, b: Raw) -> Bool {
			switch (a.text, b.text) {
			case (nil, nil): true
			case let (x?, y?): x.utf8.elementsEqual(y.utf8)
			default: false
			}
		}

		func hash(into hasher: inout Hasher) {
			guard var text else { return hasher.combine(-1) }
			hasher.combine(text.utf8.count)
			text.withUTF8 { hasher.combine(bytes: UnsafeRawBufferPointer($0)) }
		}
	}

	/// The fields of a row that a rule reads. Two rows with the same fields give every rule the same result. The synthesized
	/// Hashable conformance reads the fields, which Periphery cannot see.
	private struct Texts: Hashable {
		// periphery:ignore
		let accountID: UUID
		// periphery:ignore
		let name: Raw
		// periphery:ignore
		let purpose: Raw
		// periphery:ignore
		let bookingText: Raw
		// periphery:ignore
		let endToEndReference: Raw
		// periphery:ignore
		let mandateReference: Raw
		// periphery:ignore
		let creditorID: Raw
		// periphery:ignore
		let comment: Raw
		// periphery:ignore
		let counterpartyIBAN: Raw
		// periphery:ignore
		let currency: Raw
		// periphery:ignore
		let amountMinor: Int64

		init(_ t: Transaction) {
			accountID = t.accountID
			name = Raw(text: t.name)
			purpose = Raw(text: t.purpose)
			bookingText = Raw(text: t.bookingText)
			endToEndReference = Raw(text: t.endToEndReference)
			mandateReference = Raw(text: t.mandateReference)
			creditorID = Raw(text: t.creditorID)
			comment = Raw(text: t.comment)
			counterpartyIBAN = Raw(text: t.counterpartyIBAN)
			currency = Raw(text: t.currency)
			amountMinor = t.amountMinor
		}
	}

	/// What the rules give the texts of one row.
	private struct Decision {
		/// The index in `entries` of the first rule that matched, or nil.
		var match: Int?
		/// A stopped rule stands before the match, and could have matched first.
		var passedStop = false
		/// The number of stops in `State.stops` that the decision takes into account.
		var stops = 0
	}

	private struct State {
		/// The number of each row's texts, an index into `decisions`.
		var rows: [Texts: Int] = [:]
		var decisions: [Decision?] = []
		/// The entries whose rule stopped, in the order of the stops. A stop lasts for the categorizer, so this only grows.
		var stops: [Int] = []
		var stopped: Set<Int> = []
		/// The processor time of the regex calls of all rules that took `Rule.heavyCall` or more each.
		var heavy: UInt64 = 0
		/// The decisions that the current pass of `allOrNothing` used and that a later stop could change, or nil outside
		/// a pass.
		var used: [(account: UUID, decision: Decision)]?

		mutating func noteStop(_ entry: Int) {
			if stopped.insert(entry).inserted { stops.append(entry) }
		}
	}

	/// The categorizer runs on one thread in practice. The lock keeps it safe to share, and it is not held while a rule runs.
	private final class Memo: Sendable {
		let state = Mutex(State())
	}

	/// The decision for the texts of a row. A known decision takes the stops since it was made into account, so only a row
	/// that a stopped rule matched tests the rules after that one, and no rule tests one text twice.
	private func decision(for t: Transaction) -> Decision {
		let texts = Texts(t)
		let (row, known, stops) = memo.state.withLock { s -> (Int, Decision?, Int) in
			if let row = s.rows[texts] { return (row, s.decisions[row], s.stops.count) }
			s.rows[texts] = s.decisions.count
			s.decisions.append(nil)
			return (s.decisions.count - 1, nil, s.stops.count)
		}
		var d = known ?? Decision(stops: stops)
		var from: Int? = known == nil ? 0 : nil
		var subject: RuleSubject?
		while true {
			if let from {
				let s = subject ?? RuleSubject(t, account: accountsByID[t.accountID])
				subject = s
				evaluate(&d, from: from, t.accountID, s)
			}
			from = memo.state.withLock { s in
				guard let next = update(&d, account: t.accountID, stops: s.stops) else {
					s.decisions[row] = d
					if canChange(d) { s.used?.append((t.accountID, d)) }
					return nil
				}
				return next
			}
			if from == nil { return d }
		}
	}

	/// Tests the rules from the entry `start` on, after a decision for all rules before it.
	private func evaluate(_ d: inout Decision, from start: Int, _ account: UUID, _ subject: RuleSubject) {
		d.match = nil
		for i in start..<entries.count {
			let e = entries[i]
			if let accounts = e.accounts, !accounts.contains(account) { continue }
			if matches(i, subject) {
				d.match = i
				return
			}
			if e.rule.stoppedRegexPosition != nil { d.passedStop = true }
		}
	}

	private func matches(_ entry: Int, _ subject: RuleSubject) -> Bool {
		let rule = entries[entry].rule
		guard rule.hasRegex else { return rule.matches(subject) }
		guard rule.stoppedRegexPosition == nil else { return false }
		let heavy = rule.heavySpent
		let found = rule.matches(subject)
		let added = rule.heavySpent - heavy
		if added > 0 || rule.stoppedRegexPosition != nil {
			memo.state.withLock { s in
				s.heavy += added
				if s.heavy >= Self.batchLimit {
					for (i, e) in entries.enumerated() where e.rule.hasRegex {
						e.rule.stopAtFirstRegex()
						s.noteStop(i)
					}
				}
				if rule.stoppedRegexPosition != nil { s.noteStop(entry) }
			}
		}
		return found && rule.stoppedRegexPosition == nil
	}

	/// Takes the stops since the decision into account. A stopped rule before the match only marks the stop, because it
	/// did not match. A stop of the matched rule itself leaves the row to the rules after it, from the returned entry on.
	private func update(_ d: inout Decision, account: UUID, stops: [Int]) -> Int? {
		var next: Int?
		for e in stops[d.stops...] {
			if let match = d.match, e > match { continue }
			if let accounts = entries[e].accounts, !accounts.contains(account) { continue }
			d.passedStop = true
			if e == d.match { next = e + 1 }
		}
		d.stops = stops.count
		return next
	}

	/// A later stop can only change a decision whose match has a regular expression, or one that passed no stop yet.
	private func canChange(_ d: Decision) -> Bool {
		!d.passedStop || d.match.map { entries[$0].rule.hasRegex } == true
	}

	/// Sets the category of a transaction that has none, or whose category came from a rule.
	/// A manual choice stays. So does the category of a rule when a stopped rule stands before every match, because
	/// the stopped rule could have matched: a stop never moves a transaction that a rule sorted.
	public func categorize(_ t: inout Transaction) {
		guard t.categorizedBy != .manual else { return }
		let decision = decision(for: t)
		if decision.passedStop, t.categorizedBy == .rule { return }
		if let match = decision.match {
			t.categoryID = entries[match].categoryID
			t.categorizedBy = .rule
		} else {
			t.categoryID = nil
			t.categorizedBy = .none
		}
	}

	/// Runs one batch of categorization, such as the merge of one refresh. When a rule stops during the batch, the rows
	/// before the stop could have taken its category, so the batch runs again when a stop changed a decision that it
	/// used, and the stopped rule then matches none of its rows. The result never depends on the order of the rows.
	/// `body` must start from its inputs each time. A repeat reads the decision of each row, so it tests no rule again
	/// except the ones after a stopped rule that matched the row. Batches of one categorizer do not nest.
	public func allOrNothing<T>(_ body: () throws -> T) rethrows -> T {
		while true {
			let stops = memo.state.withLock { s in
				s.used = []
				return s.stops.count
			}
			let result: T
			do {
				result = try body()
			} catch {
				memo.state.withLock { $0.used = nil }
				throw error
			}
			// Each repetition follows at least one more stop, so this ends after at most one repetition for each rule.
			let changed = memo.state.withLock { s in
				defer { s.used = nil }
				guard s.stops.count > stops else { return false }
				return (s.used ?? []).contains { used in
					var d = used.decision
					return update(&d, account: used.account, stops: s.stops) != nil || d.passedStop != used.decision.passedStop
				}
			}
			if !changed { return result }
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
	/// A cancelled task stops the run, and it returns no changes. So does a rule whose regular expression stopped
	/// (`Rule.stoppedRegexPosition`), because "Apply to all transactions." would otherwise empty the category.
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
			if rule.stoppedRegexPosition != nil { return [] }
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

	/// The number of transactions that the rule matches, or 0 when its regular expression stopped or the task was cancelled.
	public static func matchCount(category: Category, rule: Rule, ledger: Ledger) -> Int {
		let restriction = ledger.allowedAccounts(of: category)
		var count = 0
		for (i, transaction) in ledger.transactions.enumerated() {
			// The category settings count again on every change of the rule and drop the count they no longer need.
			if i % 1_000 == 0, Task.isCancelled { return 0 }
			guard ledger.parts(of: transaction.id).isEmpty, restriction.map({ $0.contains(transaction.accountID) }) ?? true else { continue }
			if rule.matches(RuleSubject(transaction, account: ledger.account(transaction.accountID))) { count += 1 }
			if rule.stoppedRegexPosition != nil { return 0 }
		}
		return count
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
		let rows = kept + apply(category: category, rule: rule, to: changedSince, ledger: current, mode: mode)
		// A row that changed during the run can stop the rule, and then the run saves nothing, as `apply` does.
		return rule.stoppedRegexPosition == nil ? rows : []
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
	///
	/// A sidebar row reads it each time SwiftUI evaluates its body, and a long rule takes milliseconds to parse, so the
	/// result of the last parse of each category is kept with its rule text. A string compares with the string it was
	/// copied from without reading its characters, so a row whose rule did not change finds the result at once.
	public var ruleError: RuleSyntaxError? {
		guard !isDefault, !isGroup else { return nil }
		if let kept = Self.parses.withLock({ $0[id] }), kept.rule == rule { return kept.error }
		let error: RuleSyntaxError?
		do {
			_ = try savedRule()
			error = nil
		} catch let e {
			error = e
		}
		Self.parses.withLock {
			// Deleted categories leave their entries behind, which this bounds.
			if $0.count >= 10_000 { $0.removeAll() }
			$0[id] = (rule, error)
		}
		return error
	}

	private static let parses = Mutex<[UUID: (rule: String, error: RuleSyntaxError?)]>([:])
}
