import Foundation

/// What one source delivered for one account.
public enum Delivery: Sendable {
	case refresh(RefreshResult)
	/// The rows of a file that the user imported. A file never removes a pending row and carries no balance.
	case file([Transaction])
	/// The rows of a MoneyMoney migration. Like a file, but every row the user deleted stays deleted, except
	/// the booked version of a deleted pending row.
	case migration([Transaction])
}

/// What the app keeps of a transaction that the user deleted: the fields that its identity comes from.
/// A later refresh that delivers the transaction again does not add it ("Deleted transactions stay
/// deleted"). A file import adds it again unless a refresh had delivered it. A MoneyMoney migration never adds it again. A deleted pending row never keeps out its booked version.
///
/// One record per deleted row. Deleting one of two identical rows absorbs one delivered copy, and the
/// stored row absorbs the other. The records go with their account.
public struct DeletedTransaction: Hashable, Sendable, Codable {
	public var accountID: UUID
	public var sourceID: String?
	public var bookingDate: Day
	public var amountMinor: Int64
	public var isPending: Bool
	public var purpose: String
	public var counterpartyIBAN: String?
	public var endToEndReference: String?
	/// A refresh had delivered the row. Only then does the record keep a file import from adding it.
	public var wasFetched: Bool
	public var deletedAt: Date

	public init(_ t: Transaction, deletedAt: Date) {
		accountID = t.accountID
		sourceID = t.sourceID
		bookingDate = t.bookingDate
		amountMinor = t.amountMinor
		isPending = t.isPending
		purpose = t.purpose
		counterpartyIBAN = t.counterpartyIBAN
		endToEndReference = t.endToEndReference
		wasFetched = t.isFetched
		self.deletedAt = deletedAt
	}
}

/// What a merge changes. The lists are disjoint, and every row in them belongs to the merged account.
/// `Store.merge` writes it in one transaction, and `Ledger.apply` takes it over.
public struct Reconciliation: Sendable, Equatable {
	/// New rows, in the order of the delivery: marked new, categorized by the rules, without a checkmark.
	/// A booked row whose pending version is unclear also carries `needsReview`.
	public internal(set) var added: [Transaction] = []
	/// Stored pending rows that took the bank fields of their booked version. Each keeps its ID,
	/// comment, checkmark, hand-set category, and new mark. The rules ran again on it.
	public internal(set) var booked: [Transaction] = []
	/// Stored rows that a source with IDs delivered with changed bank fields, that took over the source
	/// ID of the delivered row, or that a refresh delivered for the first time. User fields kept.
	public internal(set) var updated: [Transaction] = []
	/// Stored pending rows that now carry `needsReview`, because more than one row could be their booked version.
	public internal(set) var marked: [Transaction] = []
	/// Stored pending rows that the bank dropped. Never a booked row.
	public internal(set) var dropped: [UUID] = []
	/// Delivered rows that were stored already, or that the user deleted. A stored row that such a delivered
	/// row changed is in `updated` as well.
	public internal(set) var skipped = 0
	/// The account with the balance and the date of this refresh. Nil for a file, and when the refresh
	/// brought no balance in the currency of the account.
	public internal(set) var account: Account?

	public init() {}
}

/// Merges what a source delivered for one account into the stored history of that account.
///
/// Pure: the same input gives the same result, and merging the same delivery into the result gives
/// nothing to write except the balance. `stored` must be all live rows of `account`, and `deleted` all
/// its deleted rows. Delivered rows are read for their bank fields and, from a file, the comment.
public func reconcile(_ delivery: Delivery, into account: Account, stored: [Transaction], deleted: [DeletedTransaction],
	rules: Categorizer, now: Date) -> Reconciliation {
	let rows = delivery.rows
	let fetched = delivery.isFetched
	let partners = partners(of: rows, stored: stored, deleted: deleted.filter(delivery.honors))
	let taken = Set(partners.compactMap { partner -> Int? in
		if case let .live(j) = partner?.slot { j } else { nil }
	})
	let released = stored.indices.filter { stored[$0].isPending && !taken.contains($0) }
	let fresh = rows.indices.filter { partners[$0] == nil && !rows[$0].isPending }
	let bookings = Bookings(pending: released.map { ($0, stored[$0]) }, booked: fresh.map { ($0, rows[$0]) })

	var r = Reconciliation()
	for (i, delivered) in rows.enumerated() {
		if let partner = partners[i] {
			guard case let .live(j) = partner.slot else {
				r.skipped += 1
				continue
			}
			let live = stored[j]
			var next = live
			switch partner.evidence {
			case .sourceID:
				// A migration only books a pending row. Any other change could undo a booking or an edit
				// that the app made since the earlier run.
				if case .migration = delivery, !(live.isPending && !delivered.isPending) { break }
				next = live.takingBankFields(of: delivered)
				if next != live { rules.categorize(&next) }
			case .fingerprint:
				if let id = delivered.sourceID, Identity.remote(next.sourceID) == nil { next.sourceID = id }
			}
			if fetched { next.isFetched = true }
			if live.isPending && !next.isPending {
				r.booked.append(next)
			} else {
				r.skipped += 1
				if next != live { r.updated.append(next) }
			}
		} else if case let .pair(j) = bookings.ofBooked[i] {
			var next = stored[j].takingBankFields(of: delivered)
			rules.categorize(&next)
			if fetched { next.isFetched = true }
			r.booked.append(next)
		} else {
			var t = Transaction(arriving: delivered, in: account.id, fetched: fetched)
			t.needsReview = bookings.ofBooked[i] == .review
			rules.categorize(&t)
			r.added.append(t)
		}
	}
	for j in released {
		let pending = stored[j]
		switch bookings.ofPending[j] {
		case .pair: break
		case .review:
			if !pending.needsReview {
				var t = pending
				t.needsReview = true
				r.marked.append(t)
			}
		case nil:
			if delivery.covers(pending.bookingDate), !pending.needsReview { r.dropped.append(pending.id) }
		}
	}
	if case let .refresh(result) = delivery, let balance = result.balance, balance.currency == account.currency {
		var a = account
		a.bankBalanceMinor = balance.minorUnits
		a.bankBalanceDate = result.balanceDate ?? now
		r.account = a
	}
	return r
}

extension Delivery {
	var rows: [Transaction] {
		switch self {
		case let .refresh(result): result.transactions?.rows ?? []
		case let .file(rows), let .migration(rows): rows
		}
	}

	var isFetched: Bool {
		if case .refresh = self { true } else { false }
	}

	func covers(_ day: Day) -> Bool {
		guard case let .refresh(result) = self, let answer = result.transactions else { return false }
		return answer.from.map { day >= $0 } ?? true
	}

	func honors(_ deleted: DeletedTransaction) -> Bool {
		switch self {
		case .file: deleted.wasFetched
		case .refresh, .migration: true
		}
	}
}

enum Slot: Hashable {
	case live(Int)
	case deleted(Int)
}

struct Partner {
	enum Evidence { case sourceID, fingerprint }

	let slot: Slot
	let evidence: Evidence
}

/// Each step takes rows out of the pool, so a weaker rule never takes a row that a stronger one claimed.
/// At each step a stored row comes before a deleted one.
func partners(of rows: [Transaction], stored: [Transaction], deleted: [DeletedTransaction]) -> [Partner?] {
	var result = [Partner?](repeating: nil, count: rows.count)
	var taken = Set<Slot>()
	let ids = Set(rows.compactMap(\.sourceID))
	if !ids.isEmpty {
		var byID: [String: [Slot]] = [:]
		for (j, t) in stored.enumerated() {
			if let id = t.sourceID, ids.contains(id) { byID[id, default: []].append(.live(j)) }
		}
		for (k, d) in deleted.enumerated() {
			if let id = d.sourceID, ids.contains(id) { byID[id, default: []].append(.deleted(k)) }
		}
		func isDeletedPending(_ slot: Slot) -> Bool {
			if case let .deleted(k) = slot { deleted[k].isPending } else { false }
		}
		for (i, t) in rows.enumerated() {
			guard let id = t.sourceID, let slots = byID[id] else { continue }
			let free = slots.filter { !taken.contains($0) }
			if let slot = free.first(where: { t.isPending || !isDeletedPending($0) }) {
				taken.insert(slot)
				result[i] = Partner(slot: slot, evidence: .sourceID)
			} else if let used = free.first {
				// A deleted pending row does not block its booked version, also when both carry the same ID.
				// The booked version uses it up, so it cannot absorb another pending row later.
				taken.insert(used)
			}
		}
	}
	let days = Set(rows.map(\.bookingDate))
	var candidates: [Identity.Key: [(slot: Slot, identity: Identity)]] = [:]
	for (j, t) in stored.enumerated() where days.contains(t.bookingDate) && !taken.contains(.live(j)) {
		let identity = Identity(t)
		candidates[identity.key, default: []].append((.live(j), identity))
	}
	for (k, d) in deleted.enumerated() where days.contains(d.bookingDate) && !taken.contains(.deleted(k)) {
		let identity = Identity(d)
		candidates[identity.key, default: []].append((.deleted(k), identity))
	}
	let identities = rows.map(Identity.init)
	for step in Identity.steps {
		for i in rows.indices where result[i] == nil {
			let delivered = identities[i]
			guard let match = candidates[delivered.key]?.first(where: { !taken.contains($0.slot) && step.accepts(delivered, $0.identity) }) else { continue }
			taken.insert(match.slot)
			result[i] = Partner(slot: match.slot, evidence: .fingerprint)
		}
	}
	return result
}

/// Built from the bank fields at every merge and never stored, so a change of the rule needs no migration.
struct Identity {
	let remoteID: String?
	let key: Key
	let isPending: Bool
	let counterparty: String?
	let endToEnd: String?

	/// The purpose is folded without white space, so the 27-character lines of an MT940 purpose and the
	/// same text in one line have the same key.
	struct Key: Hashable {
		// The synthesized Hashable conformance reads these properties, which Periphery cannot see.
		// periphery:ignore
		let day: Day
		// periphery:ignore
		let amount: Int64
		// periphery:ignore
		let purpose: String
	}

	enum Fit {
		case exact
		/// A file often lacks the counterparty or the reference where a refresh has them.
		case compatible
	}

	enum Pending {
		case same
		/// A delivered pending row whose booked version is stored. The other way round is a booking, which
		/// `Bookings` decides, because it must check for ambiguity.
		case bookedVersion
	}

	struct Step {
		let fit: Fit
		let pending: Pending

		func accepts(_ delivered: Identity, _ candidate: Identity) -> Bool {
			let states = switch pending {
			case .same: delivered.isPending == candidate.isPending
			case .bookedVersion: delivered.isPending && !candidate.isPending
			}
			return states && (delivered.remoteID == nil || candidate.remoteID == nil) && delivered.fit(candidate) == fit
		}
	}

	static let steps = [Step(fit: .exact, pending: .same), Step(fit: .compatible, pending: .same),
		Step(fit: .exact, pending: .bookedVersion), Step(fit: .compatible, pending: .bookedVersion)]

	init(sourceID: String?, day: Day, amount: Int64, isPending: Bool, purpose: String, counterparty: String?, endToEnd: String?) {
		remoteID = Self.remote(sourceID)
		key = Key(day: day, amount: amount, purpose: TextFolding.fold(purpose).filter { !$0.isWhitespace })
		self.isPending = isPending
		self.counterparty = counterparty.map(TextFolding.accountKey).flatMap { $0.isEmpty ? nil : $0 }
		self.endToEnd = endToEnd.flatMap { $0.isEmpty || $0 == "NOTPROVIDED" ? nil : $0 }
	}

	init(_ t: Transaction) {
		self.init(sourceID: t.sourceID, day: t.bookingDate, amount: t.amountMinor, isPending: t.isPending, purpose: t.purpose,
			counterparty: t.counterpartyIBAN, endToEnd: t.endToEndReference)
	}

	init(_ d: DeletedTransaction) {
		self.init(sourceID: d.sourceID, day: d.bookingDate, amount: d.amountMinor, isPending: d.isPending, purpose: d.purpose,
			counterparty: d.counterpartyIBAN, endToEnd: d.endToEndReference)
	}

	static func remote(_ sourceID: String?) -> String? {
		sourceID.flatMap { $0.hasPrefix(Transaction.migrationIDPrefix) ? nil : $0 }
	}

	func fit(_ other: Identity) -> Fit? {
		guard key == other.key else { return nil }
		if counterparty == other.counterparty && endToEnd == other.endToEnd { return .exact }
		func agree(_ a: String?, _ b: String?) -> Bool { a == nil || b == nil || a == b }
		return agree(counterparty, other.counterparty) && agree(endToEnd, other.endToEnd) ? .compatible : nil
	}
}

struct Bookings {
	enum Outcome: Equatable {
		case pair(Int)
		case review
	}

	private(set) var ofPending: [Int: Outcome] = [:]
	private(set) var ofBooked: [Int: Outcome] = [:]

	init(pending: [(Int, Transaction)], booked: [(Int, Transaction)]) {
		guard !pending.isEmpty, !booked.isEmpty else { return }
		let p = pending.map { PendingMatch($0.1) }
		let b = booked.map { PendingMatch($0.1) }
		var bookedByAmount: [Money: [Int]] = [:]
		for (y, m) in b.enumerated() { bookedByAmount[m.amount, default: []].append(y) }
		var edgesOfPending = [[Int]](repeating: [], count: p.count)
		var edgesOfBooked = [[Int]](repeating: [], count: b.count)
		for (x, m) in p.enumerated() {
			for y in bookedByAmount[m.amount] ?? [] where m.fits(b[y]) {
				edgesOfPending[x].append(y)
				edgesOfBooked[y].append(x)
			}
		}
		var seenPending = Set<Int>()
		var seenBooked = Set<Int>()
		for start in p.indices where !edgesOfPending[start].isEmpty && !seenPending.contains(start) {
			var groupPending: [Int] = []
			var groupBooked: [Int] = []
			var stack = [start]
			seenPending.insert(start)
			while let x = stack.popLast() {
				groupPending.append(x)
				for y in edgesOfPending[x] where seenBooked.insert(y).inserted {
					groupBooked.append(y)
					for other in edgesOfBooked[y] where seenPending.insert(other).inserted { stack.append(other) }
				}
			}
			if groupPending.count == 1, groupBooked.count == 1 {
				ofPending[pending[groupPending[0]].0] = .pair(booked[groupBooked[0]].0)
				ofBooked[booked[groupBooked[0]].0] = .pair(pending[groupPending[0]].0)
			} else {
				for x in groupPending { ofPending[pending[x].0] = .review }
				for y in groupBooked { ofBooked[booked[y].0] = .review }
			}
		}
	}
}

struct PendingMatch {
	static let maxDaysApart = 7

	let amount: Money
	let day: Int
	let iban: String?
	let words: [Substring]

	init(_ t: Transaction) {
		amount = t.amount
		day = t.bookingDate.daysSince1970
		iban = t.counterpartyIBAN.map(TextFolding.accountKey).flatMap { $0.isEmpty ? nil : $0 }
		words = TextFolding.fold(t.name).split { !$0.isLetter && !$0.isNumber }
	}

	func fits(_ other: PendingMatch) -> Bool {
		guard amount == other.amount, abs(day - other.day) <= Self.maxDaysApart else { return false }
		if let iban, let otherIBAN = other.iban { return iban == otherIBAN }
		guard !words.isEmpty, !other.words.isEmpty else { return false }
		return words.starts(with: other.words) || other.words.starts(with: words)
	}
}

extension Transaction {
	init(arriving delivered: Transaction, in account: UUID, fetched: Bool) {
		self.init(id: delivered.id, accountID: account, bookingDate: delivered.bookingDate, valueDate: delivered.valueDate, amountMinor: delivered.amountMinor,
			currency: delivered.currency, name: delivered.name, purpose: delivered.purpose, counterpartyIBAN: delivered.counterpartyIBAN,
			counterpartyBIC: delivered.counterpartyBIC, bookingText: delivered.bookingText, endToEndReference: delivered.endToEndReference,
			mandateReference: delivered.mandateReference, creditorID: delivered.creditorID, comment: delivered.comment, isPending: delivered.isPending,
			isNew: true, isFetched: fetched, sourceID: delivered.sourceID, createdAt: delivered.createdAt)
	}

	func takingBankFields(of delivered: Transaction) -> Transaction {
		var t = self
		t.bookingDate = delivered.bookingDate
		t.valueDate = delivered.valueDate ?? valueDate
		t.amountMinor = delivered.amountMinor
		t.currency = delivered.currency
		t.name = delivered.name
		t.purpose = delivered.purpose
		t.counterpartyIBAN = delivered.counterpartyIBAN ?? counterpartyIBAN
		t.counterpartyBIC = delivered.counterpartyBIC ?? counterpartyBIC
		t.bookingText = delivered.bookingText ?? bookingText
		t.endToEndReference = delivered.endToEndReference ?? endToEndReference
		t.mandateReference = delivered.mandateReference ?? mandateReference
		t.creditorID = delivered.creditorID ?? creditorID
		t.isPending = delivered.isPending
		// A migration ID never replaces the ID of a source that took the row over.
		if Identity.remote(delivered.sourceID) != nil || Identity.remote(sourceID) == nil {
			t.sourceID = delivered.sourceID ?? sourceID
		}
		return t
	}
}
