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
	public var currency: String
	public var isPending: Bool
	public var purpose: String
	public var counterpartyIBAN: String?
	public var endToEndReference: String?
	/// A refresh had delivered the row. Only then does the record keep a file import from adding it.
	public var wasFetched: Bool
	public var deletedAt: Date

	/// A deleted row with the source ID that it takes. The store finds the row by its other fields.
	public struct Relink: Hashable, Sendable {
		public var row: DeletedTransaction
		public var sourceID: String?

		public init(row: DeletedTransaction, sourceID: String?) {
			self.row = row
			self.sourceID = sourceID
		}
	}

	public init(_ t: Transaction, deletedAt: Date) {
		accountID = t.accountID
		sourceID = t.sourceID
		bookingDate = t.bookingDate
		amountMinor = t.amountMinor
		currency = t.currency
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
	/// Stored pending rows that now carry `needsReview` and no checkmark, because more than one row could be their
	/// booked version. A row that had the mark already and the checkmark of the user loses the checkmark.
	public internal(set) var marked: [Transaction] = []
	/// Stored pending rows that the bank dropped. Never a booked row.
	public internal(set) var dropped: [UUID] = []
	/// Delivered rows that were stored already, or that the user deleted. A stored row that such a delivered
	/// row changed is in `updated` as well.
	public internal(set) var skipped = 0
	/// Deleted rows that keep out a row of a migration and take its source ID, so the balance of a migrated account
	/// counts them as rows of the source while the source has them. Only a migration fills it.
	public internal(set) var relinked: [DeletedTransaction.Relink] = []
	/// The account with the balance and the date of this refresh, and, on its first refresh with a
	/// balance, the initial balance that follows from them. Nil for a file, and when the refresh brought
	/// no balance in the currency of the account.
	public internal(set) var account: Account?
	/// The positions that replace those of the account, with the IDs of the stored positions of the same
	/// securities. Nil when the delivery brought none.
	public internal(set) var holdings: Holdings?

	public init() {}

	/// All positions of one portfolio after a refresh.
	public struct Holdings: Sendable, Equatable {
		public let accountID: UUID
		public let holdings: [Holding]
	}
}

/// Merges what a source delivered for one account into the stored history of that account.
///
/// Pure: the same input gives the same result, and merging the same delivery into the result gives
/// nothing to write except the balance. `stored` must be all live rows of `account`, and `deleted` all
/// its deleted rows, and `holdings` all its stored positions. Delivered rows are read for their bank fields
/// and, from a file, the comment and a category set by hand.
public func reconcile(_ delivery: Delivery, into account: Account, stored: [Transaction], deleted: [DeletedTransaction],
	holdings: [Holding] = [], rules: Categorizer, now: Date) -> Reconciliation {
	let rows = delivery.rows
	let fetched = delivery.isFetched
	let honored = deleted.filter(delivery.honors)
	let today = Day(now)
	let partners = partners(of: rows, stored: stored, deleted: honored, delivery: delivery, today: today)
	let taken = Set(partners.compactMap { partner -> Int? in
		if case let .live(j) = partner?.slot { j } else { nil }
	})
	let released = stored.indices.filter { stored[$0].isPending && !taken.contains($0) }
	let fresh = rows.indices.filter { partners[$0] == nil && !rows[$0].isPending }
	let bookings = Bookings(pending: released.map { ($0, stored[$0]) }, booked: fresh.map { ($0, rows[$0]) })
	let future = Set(released.filter { !stored[$0].isFetched && stored[$0].bookingDate >= today && !stored[$0].needsReview })

	var r = Reconciliation()
	for (i, delivered) in rows.enumerated() {
		if let partner = partners[i] {
			guard case let .live(j) = partner.slot else {
				if case let .deleted(k) = partner.slot, delivery.isMigration, let id = delivered.sourceID,
					partner.evidence == .sourceID || Identity.remote(honored[k].sourceID) == nil {
					let row = honored[k]
					let linked = Transaction.linkedID(id, pending: row.isPending, sourcePending: delivered.isPending)
					if linked != row.sourceID { r.relinked.append(DeletedTransaction.Relink(row: row, sourceID: linked)) }
				}
				r.skipped += 1
				continue
			}
			let live = stored[j]
			var next = live
			switch partner.evidence {
			case .sourceID:
				if delivered.isPending && !live.isPending { break }
				// A migration only books a pending row. Any other change could undo a booking or an edit
				// that the app made since the earlier run. Only the link follows the source.
				if delivery.isMigration, !(live.isPending && !delivered.isPending) {
					next.sourceID = delivered.sourceID.map { Transaction.linkedID($0, pending: live.isPending, sourcePending: delivered.isPending) }
					break
				}
				next = live.takingBankFields(of: delivered)
				if next != live { rules.categorize(&next) }
			case .pending:
				next = live.takingBankFields(of: delivered)
				if next != live { rules.categorize(&next) }
				fallthrough
			case .fingerprint, .sameDay:
				if let id = delivered.sourceID, Identity.remote(next.sourceID) == nil {
					next.sourceID = Transaction.linkedID(id, pending: live.isPending, sourcePending: delivered.isPending)
				}
			}
			if fetched { next.isFetched = true }
			if case .file = delivery, partner.evidence == .sameDay {
				if next.comment?.isEmpty != false, let comment = delivered.comment { next.comment = comment }
				if live.categoryID == nil, let category = delivered.categoryID {
					next.categoryID = category
					next.categorizedBy = delivered.categorizedBy
				}
				next.isChecked = next.isChecked || delivered.isChecked
			}
			if live.isPending && !next.isPending {
				r.booked.append(next)
			} else {
				r.skipped += 1
				if next != live { r.updated.append(next) }
			}
		} else if case let .pair(j) = bookings.ofBooked[i] {
			var next = stored[j].takingBankFields(of: delivered)
			// A row of the source that a file or a bank books counts as imported until the source books it too.
			if !delivery.isMigration, let id = next.sourceID { next.sourceID = Transaction.linkedID(id, pending: false, sourcePending: true) }
			if delivered.categorizedBy == .manual, next.categorizedBy != .manual {
				next.categoryID = delivered.categoryID
				next.categorizedBy = .manual
			}
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
			if !pending.needsReview || pending.isChecked {
				var t = pending
				t.needsReview = true
				t.isChecked = false
				r.marked.append(t)
			}
		case nil where future.contains(j): break
		case nil:
			if delivery.covers(pending.bookingDate), !pending.needsReview || pending.isChecked { r.dropped.append(pending.id) }
		}
	}
	if case let .refresh(result) = delivery, let balance = result.balance, balance.currency == account.currency {
		var a = account
		a.bankBalanceMinor = balance.minorUnits
		a.bankBalanceDate = result.balanceDate ?? now
		if result.isPortfolio { a.kind = .portfolio }
		// A balance whose transactions failed would set the value without the rows that the next refresh brings.
		if a.derivesInitialBalance, result.transactionFailure == nil {
			// Dropped and marked rows are pending and do not count.
			let changed = Dictionary(uniqueKeysWithValues: (r.booked + r.updated).map { ($0.id, $0) })
			a.deriveInitialBalance(from: stored.map { changed[$0.id] ?? $0 } + r.added)
		}
		r.account = a
	}
	if case let .refresh(result) = delivery, let delivered = result.holdings {
		r.holdings = Reconciliation.Holdings(accountID: account.id, holdings: Holding.identify(delivered, stored: holdings))
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

	var isMigration: Bool {
		if case .migration = self { true } else { false }
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
	enum Evidence { case sourceID, fingerprint, pending, sameDay }

	let slot: Slot
	let evidence: Evidence
}

func partners(of rows: [Transaction], stored: [Transaction], deleted: [DeletedTransaction], delivery: Delivery, today: Day) -> [Partner?] {
	struct Candidate {
		let delivered: Int
		let slot: Slot
		let priority: Int
		let distance: Int
		let evidence: Partner.Evidence?
	}
	let matches = rows.map(PendingMatch.init)
	let liveMatches = stored.map(PendingMatch.init)
	let deadMatches = deleted.map(PendingMatch.init)
	let incoming = matches.map(\.identity)
	var byDay: [Day: [Slot]] = [:]
	var byKey: [Identity.Key: [Slot]] = [:]
	var byID: [String: [Slot]] = [:]
	for (j, t) in stored.enumerated() {
		byDay[t.bookingDate, default: []].append(.live(j))
		byKey[liveMatches[j].identity.key, default: []].append(.live(j))
		if let id = t.sourceID { byID[Transaction.matchingID(id), default: []].append(.live(j)) }
	}
	for (k, d) in deleted.enumerated() {
		byDay[d.bookingDate, default: []].append(.deleted(k))
		byKey[deadMatches[k].identity.key, default: []].append(.deleted(k))
		if let id = d.sourceID { byID[Transaction.matchingID(id), default: []].append(.deleted(k)) }
	}
	func positions(_ ts: [Transaction]) -> [Int: Int] {
		let sorted = ts.indices.sorted {
			(ts[$0].bookingDate, ts[$0].createdAt, ts[$0].id.uuidString) < (ts[$1].bookingDate, ts[$1].createdAt, ts[$1].id.uuidString)
		}
		return Dictionary(uniqueKeysWithValues: sorted.enumerated().map { ($0.element, $0.offset) })
	}
	let deliveredPositions = positions(rows)
	let livePositions = positions(stored)
	let deadKeys = deleted.map { d in
		[String(d.bookingDate.rawValue), d.sourceID ?? "", d.endToEndReference ?? "", d.currency, String(d.amountMinor), d.purpose,
			d.counterpartyIBAN ?? "", String(d.isPending), String(d.deletedAt.timeIntervalSince1970)]
	}
	let deadOrder = deleted.indices.sorted { deadKeys[$0].lexicographicallyPrecedes(deadKeys[$1]) }
	let deadPositions = Dictionary(uniqueKeysWithValues: deadOrder.enumerated().map { ($0.element, $0.offset + stored.count) })
	func position(_ slot: Slot) -> Int {
		switch slot {
		case let .live(j): livePositions[j]!
		case let .deleted(k): deadPositions[k]!
		}
	}
	var candidates: [Candidate] = []
	for (i, t) in rows.enumerated() {
		var slots = Set((t.isPending ? byDay[t.bookingDate] : byKey[incoming[i].key]) ?? [])
		if let id = t.sourceID { slots.formUnion(byID[id] ?? []) }
		if t.isPending && !delivery.isMigration && delivery.isFetched {
			for offset in -PendingMatch.maxDaysApart...PendingMatch.maxDaysApart where offset != 0 {
				slots.formUnion(byDay[t.bookingDate.adding(days: offset)] ?? [])
			}
		}
		for slot in slots {
			let identity: Identity
			let match: PendingMatch
			let fetched: Bool
			let future: Bool
			switch slot {
			case let .live(j):
				identity = liveMatches[j].identity
				match = liveMatches[j]
				fetched = stored[j].isFetched
				future = !stored[j].isFetched && !stored[j].needsReview && stored[j].bookingDate >= today && delivery.covers(stored[j].bookingDate)
			case let .deleted(k):
				identity = deadMatches[k].identity
				match = deadMatches[k]
				fetched = true
				future = false
			}
			guard incoming[i].agrees(with: identity) else { continue }
			let distance = abs(matches[i].day - match.day)
			let sourceAgrees = t.sourceID != nil && t.sourceID == identity.sourceID
			let sameDay = t.bookingDate == identity.key.day
			if sourceAgrees {
				if !delivery.isFetched && !delivery.isMigration && t.isPending && !sameDay { continue }
				let evidence: Partner.Evidence? = if case .deleted = slot, !t.isPending && identity.isPending { nil } else { .sourceID }
				candidates.append(Candidate(delivered: i, slot: slot, priority: 0, distance: distance, evidence: evidence))
				continue
			}
			if let step = Identity.steps.firstIndex(where: { $0.accepts(incoming[i], identity) }) {
				let priority = t.isPending && identity.isPending ? (fetched ? 1 : 2) : 3 + step
				candidates.append(Candidate(delivered: i, slot: slot, priority: priority, distance: distance, evidence: .fingerprint))
			}
			let explicit = incoming[i].endToEnd != nil && incoming[i].endToEnd == identity.endToEnd
			guard t.isPending, !delivery.isMigration, matches[i].amount == match.amount, distance <= PendingMatch.maxDaysApart,
				explicit || matches[i].fits(match), identity.isPending || (!delivery.isFetched && fetched) else { continue }
			guard delivery.isFetched ? (explicit || (fetched && sameDay) || future) : sameDay else { continue }
			let priority = explicit ? 0 : (fetched ? 1 : 2)
			let fingerprint = Identity.steps.contains { $0.accepts(incoming[i], identity) }
			let evidence: Partner.Evidence = fingerprint ? .fingerprint : (delivery.isFetched ? .pending : .sameDay)
			candidates.append(Candidate(delivered: i, slot: slot, priority: priority, distance: distance, evidence: evidence))
		}
	}
	candidates.sort {
		($0.priority, $0.distance, deliveredPositions[$0.delivered]!, position($0.slot), $0.evidence == .sameDay ? 1 : 0)
			< ($1.priority, $1.distance, deliveredPositions[$1.delivered]!, position($1.slot), $1.evidence == .sameDay ? 1 : 0)
	}
	var result = [Partner?](repeating: nil, count: rows.count)
	var taken = Set<Slot>()
	var consumed = Set<Int>()
	for candidate in candidates where !consumed.contains(candidate.delivered) && !taken.contains(candidate.slot) {
		consumed.insert(candidate.delivered)
		taken.insert(candidate.slot)
		if let evidence = candidate.evidence {
			result[candidate.delivered] = Partner(slot: candidate.slot, evidence: evidence)
		}
	}
	return result
}

/// Built from the bank fields at every merge and never stored, so a change of the rule needs no migration.
struct Identity {
	let sourceID: String?
	let remoteID: String?
	let key: Key
	let isPending: Bool
	let counterparty: String?
	let endToEnd: String?

	/// The purpose is folded without white space, so the 27-character lines of an MT940 purpose and the
	/// same text in one line have the same key.
	struct Key: Hashable {
		let day: Day
		// The synthesized Hashable conformance reads these properties, which Periphery cannot see.
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
		self.sourceID = sourceID.map(Transaction.matchingID)
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
		sourceID.flatMap { Transaction.matchingID($0).hasPrefix(Transaction.migrationIDPrefix) ? nil : $0 }
	}

	func sharesIdentity(with other: Identity) -> Bool {
		(remoteID != nil && remoteID == other.remoteID) || (endToEnd != nil && endToEnd == other.endToEnd)
	}

	func agrees(with other: Identity) -> Bool {
		if let remoteID, let otherID = other.remoteID, remoteID != otherID { return false }
		if let endToEnd, let otherReference = other.endToEnd, endToEnd != otherReference { return false }
		return true
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
		var edgesOfPending = [[Int]](repeating: [], count: p.count)
		var edgesOfBooked = [[Int]](repeating: [], count: b.count)
		var pendingByAmount: [Money: [Int]] = [:]
		for (x, m) in p.enumerated() { pendingByAmount[m.amount, default: []].append(x) }
		for (y, m) in b.enumerated() {
			var fits = (pendingByAmount[m.amount] ?? []).filter { p[$0].fits(m) }
			let explicit = fits.filter { p[$0].identity.sharesIdentity(with: m.identity) }
			if !explicit.isEmpty { fits = explicit }
			else {
				let fetched = fits.filter { pending[$0].1.isFetched }
				if fetched.count == 1 { fits = fetched }
			}
			for x in fits {
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
	let identity: Identity

	init(_ t: Transaction) {
		identity = Identity(t)
		amount = t.amount
		day = t.bookingDate.daysSince1970
		iban = t.counterpartyIBAN.map(TextFolding.accountKey).flatMap { $0.isEmpty ? nil : $0 }
		words = TextFolding.fold(t.name).split { !$0.isLetter && !$0.isNumber }
	}

	init(_ d: DeletedTransaction) {
		identity = Identity(d)
		amount = Money(minorUnits: d.amountMinor, currency: d.currency)
		day = d.bookingDate.daysSince1970
		iban = d.counterpartyIBAN.map(TextFolding.accountKey).flatMap { $0.isEmpty ? nil : $0 }
		words = []
	}

	func fits(_ other: PendingMatch) -> Bool {
		guard identity.agrees(with: other.identity), amount == other.amount, abs(day - other.day) <= Self.maxDaysApart else { return false }
		if let iban, let otherIBAN = other.iban { return iban == otherIBAN }
		guard !words.isEmpty, !other.words.isEmpty else { return false }
		return words.starts(with: other.words) || other.words.starts(with: words)
	}
}

extension Transaction {
	/// The migration ID of a booked row whose row in the source is still pending, because a file or a bank booked it
	/// first. The row counts as imported, not as a row of the source, and a later migration still finds it by the ID.
	/// The prefix does not start with `migrationIDPrefix`, so a sum over the rows of the source leaves the row out.
	public static let bookedMigrationIDPrefix = "moneymoney-booked:"

	/// The ID by which a delivered row finds this one: the plain migration ID for its booked form, any other ID as it is.
	static func matchingID(_ id: String) -> String {
		id.hasPrefix(bookedMigrationIDPrefix) ? migrationIDPrefix + id.dropFirst(bookedMigrationIDPrefix.count) : id
	}

	/// The source ID that a stored row takes from a delivered row with `id`: the booked form of a migration ID when the
	/// stored row is booked and the row in the source is pending, otherwise the plain ID.
	static func linkedID(_ id: String, pending: Bool, sourcePending: Bool) -> String {
		let plain = matchingID(id)
		guard plain.hasPrefix(migrationIDPrefix), !pending, sourcePending else { return plain }
		return bookedMigrationIDPrefix + plain.dropFirst(migrationIDPrefix.count)
	}

	init(arriving delivered: Transaction, in account: UUID, fetched: Bool) {
		self.init(id: delivered.id, accountID: account, bookingDate: delivered.bookingDate, valueDate: delivered.valueDate, amountMinor: delivered.amountMinor,
			currency: delivered.currency, name: delivered.name, purpose: delivered.purpose, counterpartyIBAN: delivered.counterpartyIBAN,
			counterpartyBIC: delivered.counterpartyBIC, bookingText: delivered.bookingText, endToEndReference: delivered.endToEndReference,
			mandateReference: delivered.mandateReference, creditorID: delivered.creditorID, comment: delivered.comment, isPending: delivered.isPending,
			categoryID: delivered.categoryID, categorizedBy: delivered.categorizedBy, isNew: true, isFetched: fetched, sourceID: delivered.sourceID, createdAt: delivered.createdAt, returnReason: delivered.returnReason)
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
		t.endToEndReference = Identity(delivered).endToEnd ?? endToEndReference
		t.mandateReference = delivered.mandateReference ?? mandateReference
		t.creditorID = delivered.creditorID ?? creditorID
		t.returnReason = delivered.returnReason ?? returnReason
		t.isPending = delivered.isPending
		// A migration ID never replaces the ID of a source that took the row over.
		if Identity.remote(delivered.sourceID) != nil || Identity.remote(sourceID) == nil {
			t.sourceID = delivered.sourceID ?? sourceID
		}
		return t
	}
}
