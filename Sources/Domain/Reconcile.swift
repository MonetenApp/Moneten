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
	public var fileIdentity: String?
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

	/// An edited row keeps the values of its source, so that the source cannot bring it back.
	public init(_ t: Transaction, deletedAt: Date) {
		let delivered = t.sourceValues
		accountID = t.accountID
		sourceID = t.sourceID
		fileIdentity = t.fileIdentity
		bookingDate = delivered.bookingDate
		amountMinor = delivered.amountMinor
		currency = t.currency
		isPending = t.isPending
		purpose = delivered.purpose
		counterpartyIBAN = t.counterpartyIBAN
		endToEndReference = t.endToEndReference
		wasFetched = t.isFetched
		self.deletedAt = deletedAt
	}
}

/// What a merge changes. Every row belongs to the merged account. Only `unsplit` overlaps `updated`.
/// `Store.merge` writes it in one transaction, and `Ledger.apply` takes it over.
public struct Reconciliation: Sendable, Equatable {
	/// New rows, in the order of the delivery: marked new, categorized by the rules, without a checkmark.
	/// A booked row whose pending version is unclear also carries `review`.
	public internal(set) var added: [Transaction] = []
	/// Stored pending rows that took the bank fields of their booked version. Each keeps its ID,
	/// comment, checkmark, hand-set category, and new mark. The rules ran again on it.
	public internal(set) var booked: [Transaction] = []
	/// Stored rows that a source with IDs delivered with changed bank fields, that took over the source
	/// ID of the delivered row, or that a refresh delivered for the first time. User fields kept.
	public internal(set) var updated: [Transaction] = []
	/// Stored pending rows that now carry `review` and no checkmark, because more than one row could be their
	/// booked version. A row that had the mark already and the checkmark of the user loses the checkmark.
	public internal(set) var marked: [Transaction] = []
	/// Stored pending rows that the bank dropped. Never a booked row.
	public internal(set) var dropped: [UUID] = []
	/// Corrected originals in `updated` whose split parts must be removed.
	public internal(set) var unsplit: [UUID] = []
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
public func reconcile(_ delivery: Delivery, into account: Account, stored all: [Transaction], deleted: [DeletedTransaction],
	holdings: [Holding] = [], split: Set<UUID> = [], rules: Categorizer, now: Date) -> Reconciliation {
	// No bank delivers a row that the user added by hand, so a refresh never pairs one: a delivered row with its
	// day, amount, and purpose is another booking. A file still pairs it, so the same cash rows from a file add no copies,
	// and from then on the row is a booking of that file, which the refresh pairs.
	// The scan comes first, because a copy of 50,000 rows on each refresh costs more than it.
	let stored = delivery.isFetched && all.contains(where: \.isOnlyManual) ? all.filter { !$0.isOnlyManual } : all
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
	// An edited row counts by the day of its source, as the pairing and the drop below read it.
	let future = Set(released.filter { !stored[$0].isFetched && stored[$0].sourceValues.bookingDate >= today && stored[$0].review == nil })

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
				// A migration only books a pending row. Any other change could undo a booking or an edit
				// that the app made since the earlier run. Only the link follows the source.
				if delivery.isMigration, !(live.isPending && !delivered.isPending) {
					next.sourceID = delivered.sourceID.map { Transaction.linkedID($0, pending: live.isPending, sourcePending: delivered.isPending) }
					break
				}
				if delivered.isPending && !live.isPending { break }
				next = live.takingBankFields(of: delivered)
				if split.contains(live.id) {
					// An edited amount stays, so the amount that the source delivered tells whether the bank changed it.
					if next.amount != live.amount || next.sourceValues.amountMinor != live.sourceValues.amountMinor {
						next.review = .splitUndone
						r.unsplit.append(live.id)
						rules.categorize(&next)
					}
				} else if next != live { rules.categorize(&next) }
			case .pending:
				next = live.takingBankFields(of: delivered)
				if next != live { rules.categorize(&next) }
				fallthrough
			case .fingerprint, .relaxedFile:
				if let id = delivered.sourceID, Identity.remote(next.sourceID) == nil {
					next.sourceID = Transaction.linkedID(id, pending: live.isPending, sourcePending: delivered.isPending)
				}
			}
			if fetched { next.isFetched = true }
			// A manual row that a file matched is a booking of that file from now on, so its deletion keeps a record.
			if case .file = delivery, next.fileIdentity == nil, live.isPending || delivered.isPending || live.isManual { next.fileIdentity = delivered.fileIdentity }
			if case .file = delivery, delivered.isPending, Identity(next).endToEnd == nil {
				next.endToEndReference = Identity(delivered).endToEnd
			}
			if case .file = delivery, partner.evidence == .relaxedFile {
				if next.comment?.isEmpty != false, let comment = delivered.comment { next.comment = comment }
				if live.categoryID == nil, let category = delivered.categoryID {
					next.categoryID = category
					next.categorizedBy = delivered.categorizedBy
				}
				next.isChecked = next.isChecked || delivered.isChecked
			}
			if live.isPending && !next.isPending {
				if !delivery.isMigration, let id = next.sourceID { next.sourceID = Transaction.linkedID(id, pending: false, sourcePending: true) }
				r.booked.append(next)
			} else {
				r.skipped += 1
				if next != live { r.updated.append(next) }
			}
		} else if case let .pair(j) = bookings.ofBooked[i] {
			var next = stored[j].takingBankFields(of: delivered)
			if case .file = delivery, next.fileIdentity == nil { next.fileIdentity = delivered.fileIdentity }
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
			t.review = bookings.ofBooked[i] == .review ? .unclearBooking : nil
			rules.categorize(&t)
			r.added.append(t)
		}
	}
	for j in released {
		let pending = stored[j]
		switch bookings.ofPending[j] {
		case .pair: break
		case .review:
			if pending.review == nil || pending.isChecked {
				var t = pending
				t.review = .unclearBooking
				t.isChecked = false
				r.marked.append(t)
			}
		case nil where future.contains(j): break
		case nil:
			if delivery.covers(pending.sourceValues.bookingDate), pending.review == nil || pending.isChecked { r.dropped.append(pending.id) }
		}
	}
	if case let .refresh(result) = delivery, let balance = result.balance, balance.currency == account.currency {
		var a = account
		let balanceDate = result.balanceDate ?? now
		a.bankBalanceMinor = balance.minorUnits
		a.bankBalanceDate = balanceDate
		if result.isPortfolio { a.kind = .portfolio }
		// A balance whose transactions failed would set the value without the rows that the next refresh brings.
		if a.derivesInitialBalance, result.transactionFailure == nil {
			// Dropped and marked rows are pending and do not count.
			let changed = Dictionary(uniqueKeysWithValues: (r.booked + r.updated).map { ($0.id, $0) })
			a.deriveInitialBalance(from: all.map { changed[$0.id] ?? $0 } + r.added)
		} else if a.initialBalanceIsDerived, let before = account.bankBalanceDate.map({ Day($0) }) {
			// A derived initial balance holds the manual rows up to the day of the bank balance. A new day moves the rows
			// that it passes into the bank balance, so a later change of such a row moves the initial balance back.
			// A value that the user entered stays. A manual row that a file matched is a booking of the file, which the
			// bank balance holds like any other row, so it does not move the value.
			let manual = all.filter(\.isOnlyManual)
			a.initialBalanceMinor += a.bookedSum(of: manual, through: before) - a.bookedSum(of: manual, through: Day(balanceDate))
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
		case let .refresh(result): (result.transactions?.rows ?? []).map { var t = $0; t.fileIdentity = nil; return t }
		case let .file(rows): rows.map { var t = $0; t.fileIdentity = t.originalFileIdentity; return t }
		case let .migration(rows): rows.map { var t = $0; t.fileIdentity = nil; return t }
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
	enum Evidence { case sourceID, fingerprint, pending, relaxedFile }

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
			if let id = t.sourceID.map(Transaction.matchingID), ids.contains(id) { byID[id, default: []].append(.live(j)) }
		}
		for (k, d) in deleted.enumerated() {
			if let id = d.sourceID.map(Transaction.matchingID), ids.contains(id) { byID[id, default: []].append(.deleted(k)) }
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
	for (j, t) in stored.enumerated() where days.contains(t.sourceValues.bookingDate) && !taken.contains(.live(j)) {
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

func partners(of rows: [Transaction], stored: [Transaction], deleted: [DeletedTransaction], delivery: Delivery, today: Day) -> [Partner?] {
	let days = Set(rows.flatMap { t in
		let day = t.bookingDate.daysSince1970
		return (-PendingMatch.maxDaysApart...PendingMatch.maxDaysApart).map { day + $0 }
	})
	let amounts = Set(rows.map(\.amountMinor))
	let ids = Set(rows.compactMap(\.sourceID))
	let fileIDs = Set(rows.compactMap(\.fileIdentity))
	let references = Set(rows.filter(\.isPending).compactMap(\.endToEndReference).filter { !$0.isEmpty && $0 != "NOTPROVIDED" })
	func relevant(day: Day, amount: Int64, sourceID: String?, fileIdentity: String?, reference: String?) -> Bool {
		(days.contains(day.daysSince1970) && amounts.contains(amount)) || sourceID.map { ids.contains(Transaction.matchingID($0)) } == true
			|| fileIdentity.map { fileIDs.contains($0) } == true
			|| reference.map { references.contains($0) } == true
	}
	// An edited row is found by the values of its source.
	let live = stored.indices.filter { relevant(day: stored[$0].sourceValues.bookingDate, amount: stored[$0].sourceValues.amountMinor, sourceID: stored[$0].sourceID, fileIdentity: stored[$0].fileIdentity, reference: stored[$0].endToEndReference) }
	let dead = deleted.indices.filter { relevant(day: deleted[$0].bookingDate, amount: deleted[$0].amountMinor, sourceID: deleted[$0].sourceID, fileIdentity: deleted[$0].fileIdentity, reference: deleted[$0].endToEndReference) }
	if rows.allSatisfy({ !$0.isPending }), stored.allSatisfy({ !$0.isPending }), deleted.allSatisfy({ !$0.isPending }),
		live.allSatisfy({ stored[$0].fileIdentity == nil }), dead.allSatisfy({ deleted[$0].fileIdentity == nil }) {
		return partners(of: rows, stored: stored, deleted: deleted)
	}

	enum Priority: Int { case identity, bookedFingerprint, reference, fetchedPending, filePending }
	struct Candidate {
		let delivered: Int
		let slot: Slot
		let priority: Priority
		let historical: Int
		let identityTombstone: Int
		let fit: Int
		let distance: Int
		let evidence: Partner.Evidence
		var legacy = false
	}
	let matches: [PendingMatch] = rows.map(PendingMatch.init)
	let liveMatches = Dictionary(uniqueKeysWithValues: live.map { ($0, PendingMatch(stored[$0])) })
	let deadMatches = Dictionary(uniqueKeysWithValues: dead.map { ($0, PendingMatch(deleted[$0])) })
	let incoming: [Identity] = matches.map(\.identity)
	let identifiedBookings: [Int] = rows.indices.filter { (i: Int) -> Bool in
		!rows[i].isPending && incoming[i].sourceID != nil
	}
	let bookedByID: [String: [Int]] = Dictionary(grouping: identifiedBookings, by: { (i: Int) -> String in incoming[i].sourceID! })
	var byDay: [Int: [Slot]] = [:]
	var byKey: [Identity.Key: [Slot]] = [:]
	var byReference: [String: [Slot]] = [:]
	var byFileIdentity: [String: [Slot]] = [:]
	var byID: [String: [Slot]] = [:]
	for j in live {
		let t = stored[j]
		byDay[liveMatches[j]!.day, default: []].append(.live(j))
		byKey[liveMatches[j]!.identity.key, default: []].append(.live(j))
		if let reference = liveMatches[j]!.identity.endToEnd { byReference[reference, default: []].append(.live(j)) }
		if let id = t.fileIdentity { byFileIdentity[id, default: []].append(.live(j)) }
		if let id = t.sourceID { byID[Transaction.matchingID(id), default: []].append(.live(j)) }
	}
	for k in dead {
		let d = deleted[k]
		byDay[deadMatches[k]!.day, default: []].append(.deleted(k))
		byKey[deadMatches[k]!.identity.key, default: []].append(.deleted(k))
		if let reference = deadMatches[k]!.identity.endToEnd { byReference[reference, default: []].append(.deleted(k)) }
		if let id = d.fileIdentity { byFileIdentity[id, default: []].append(.deleted(k)) }
		if let id = d.sourceID { byID[Transaction.matchingID(id), default: []].append(.deleted(k)) }
	}
	var candidates: [Candidate] = []

	for (i, t) in rows.enumerated() {
		let initialSlots: [Slot] = (t.isPending ? byDay[matches[i].day] : byKey[incoming[i].key]) ?? []
		var slots: Set<Slot> = Set(initialSlots)
		if let id = t.sourceID { slots.formUnion(byID[id] ?? []) }
		if let id = t.fileIdentity { slots.formUnion(byFileIdentity[id] ?? []) }
		if t.isPending, let reference = incoming[i].endToEnd { slots.formUnion(byReference[reference] ?? []) }
		if t.isPending && !delivery.isMigration {
			for offset in -PendingMatch.maxDaysApart...PendingMatch.maxDaysApart where offset != 0 {
				slots.formUnion(byDay[matches[i].day + offset] ?? [])
			}
		}
		for slot in slots {
			let identity: Identity
			let match: PendingMatch
			let fetched: Bool
			let future: Bool
			switch slot {
			case let .live(j):
				identity = liveMatches[j]!.identity
				match = liveMatches[j]!
				fetched = stored[j].isFetched
				let day = stored[j].sourceValues.bookingDate
				future = !stored[j].isFetched && stored[j].review == nil && day >= today && delivery.covers(day)
			case let .deleted(k):
				identity = deadMatches[k]!.identity
				match = deadMatches[k]!
				fetched = true
				future = false
			}
			let distance = abs(matches[i].day - match.day)
			if !t.isPending && !identity.isPending && identity.fileIdentity == nil {
				let legacy: Partner? = switch slot {
				case let .live(j): partners(of: [t], stored: [stored[j]], deleted: [])[0]
				case let .deleted(k): partners(of: [t], stored: [], deleted: [deleted[k]])[0]
				}
				guard let legacy else { continue }
				let source = legacy.evidence == .sourceID
				let tombstone = if case .deleted = slot { 1 } else { 0 }
				let fit = incoming[i].fit(identity) == .exact ? 0 : 1
				candidates.append(Candidate(delivered: i, slot: slot, priority: source ? .identity : .bookedFingerprint,
					historical: 0, identityTombstone: source ? tombstone : 0, fit: source ? 0 : fit,
					distance: distance, evidence: legacy.evidence, legacy: true))
				continue
			}
			if case .deleted = slot, identity.isPending {
				if !t.isPending { continue }
				if let id = identity.sourceID, incoming[i].sourceID != id,
					(bookedByID[id] ?? []).contains(where: { incoming[$0].agrees(with: identity) }) { continue }
			}
			guard incoming[i].agrees(with: identity) else { continue }
			let sourceAgrees = t.sourceID != nil && t.sourceID == identity.sourceID
			if !t.isPending && identity.isPending && !sourceAgrees { continue }
			let sameDay = t.bookingDate == identity.key.day
			let historical = t.isPending && !identity.isPending ? 1 : 0
			let tombstone = if case .deleted = slot { 1 } else { 0 }
			if case .file = delivery, t.isPending, identity.isPending, distance > PendingMatch.maxDaysApart { continue }
			if t.isPending, identity.isPending, let fileID = incoming[i].fileIdentity, let storedID = identity.fileIdentity, fileID != storedID { continue }
			let fileAgrees = incoming[i].fileIdentity != nil && incoming[i].fileIdentity == identity.fileIdentity
			if fileAgrees || sourceAgrees {
				candidates.append(Candidate(delivered: i, slot: slot, priority: .identity, historical: historical,
					identityTombstone: tombstone, fit: 0, distance: distance,
					evidence: (!fileAgrees && sourceAgrees) || (!t.isPending && identity.isPending) ? .sourceID : .fingerprint))
				continue
			}
			if t.isPending && !identity.isPending && t.bookingDate > identity.key.day { continue }
			guard matches[i].amount == match.amount else { continue }
			let sameReference = incoming[i].endToEnd != nil && incoming[i].endToEnd == identity.endToEnd
			let step: Int? = Identity.steps.firstIndex { (step: Identity.Step) -> Bool in step.accepts(incoming[i], identity) }
			if (t.isPending || identity.isPending || step == nil) && matches[i].counterpartyConflicts(with: match) { continue }
			let fit = step.map { $0 % 2 } ?? 2
			let rankedFit = t.isPending && matches[i].nameConflicts(with: match) ? 3 : fit
			if let fileID = incoming[i].fileIdentity, let storedID = identity.fileIdentity, fileID != storedID,
				!(t.isPending && !identity.isPending && sameReference),
				!(!t.isPending && !identity.isPending && step != nil) { continue }
			if step != nil && !identity.isPending {
				candidates.append(Candidate(delivered: i, slot: slot, priority: .bookedFingerprint, historical: historical,
					identityTombstone: 0, fit: rankedFit, distance: distance, evidence: .fingerprint))
				continue
			}
			if sameReference && t.isPending, step != nil || (!delivery.isMigration && (identity.isPending || !delivery.isFetched)) {
				candidates.append(Candidate(delivered: i, slot: slot, priority: .reference, historical: historical,
					identityTombstone: 0, fit: rankedFit, distance: distance, evidence: step == nil && delivery.isFetched ? .pending : .fingerprint))
				continue
			}
			guard t.isPending, identity.isPending else { continue }
			let pendingFits = !delivery.isMigration && matches[i].fits(match)
			guard step != nil || pendingFits else { continue }
			guard step != nil || !delivery.isFetched || fetched || future else { continue }
			let priority: Priority = fetched && (delivery.isFetched || sameDay) ? .fetchedPending : .filePending
			let evidence: Partner.Evidence = step != nil ? .fingerprint : (delivery.isFetched ? .pending : .relaxedFile)
			candidates.append(Candidate(delivered: i, slot: slot, priority: priority, historical: 0,
				identityTombstone: 0, fit: rankedFit, distance: distance, evidence: evidence))
		}
	}
	let hasLegacy = candidates.contains(where: \.legacy)
	func ranks(_ sorted: [Int], count: Int, precedes: (Int, Int) -> Bool) -> [Int: Int] {
		guard !sorted.isEmpty else { return [:] }
		if !hasLegacy { return Dictionary(uniqueKeysWithValues: sorted.enumerated().map { ($0.element, $0.offset) }) }
		// Legacy edges use raw indices, so scoped candidates keep their full-history rank in a mixed pool.
		var buckets = [Int](repeating: 0, count: sorted.count)
		for i in 0..<count {
			var low = 0
			var high = sorted.count
			while low < high {
				let middle = (low + high) / 2
				if precedes(i, sorted[middle]) { high = middle } else { low = middle + 1 }
			}
			if low < sorted.count { buckets[low] += 1 }
		}
		var rank = 0
		return Dictionary(uniqueKeysWithValues: sorted.enumerated().map { entry in
			rank += buckets[entry.offset]
			return (entry.element, rank)
		})
	}
	func positions(_ ts: [Transaction], indices: Set<Int>) -> [Int: Int] {
		let keys = Dictionary(uniqueKeysWithValues: indices.map { i in
			(i, (ts[i].sourceValues.bookingDate, ts[i].createdAt, ts[i].id.uuidString))
		})
		let sorted = indices.sorted { keys[$0]! < keys[$1]! }
		return ranks(sorted, count: ts.count) { i, j in
			let key = keys[j]!
			let day = ts[i].sourceValues.bookingDate
			if day != key.0 { return day < key.0 }
			if ts[i].createdAt != key.1 { return ts[i].createdAt < key.1 }
			return ts[i].id.uuidString < key.2
		}
	}
	let deliveredPositions: [Int: Int] = positions(rows, indices: Set(candidates.filter { !$0.legacy }.map(\.delivered)))
	let livePositions: [Int: Int] = positions(stored, indices: Set(candidates.compactMap { c in
		if !c.legacy, case let .live(j) = c.slot { j } else { nil }
	}))
	typealias DeadIdentityKey = (Day, String, String, String, String, Int64)
	typealias DeadFieldsKey = (String, String, Int, Int, Date)
	typealias DeadKey = (DeadIdentityKey, DeadFieldsKey)
	let deadCandidates = Set(candidates.compactMap { c -> Int? in
		if !c.legacy, case let .deleted(k) = c.slot { k } else { nil }
	})
	func deadKey(_ d: DeletedTransaction) -> DeadKey {
		let fileIdentity: String = d.fileIdentity.map { "1" + $0 } ?? "0"
		let sourceID: String = d.sourceID.map { "1" + $0 } ?? "0"
		let reference: String = d.endToEndReference.map { "1" + $0 } ?? "0"
		let iban: String = d.counterpartyIBAN.map { "1" + $0 } ?? "0"
		let pending: Int = d.isPending ? 1 : 0
		let fetched: Int = d.wasFetched ? 1 : 0
		let identity: DeadIdentityKey = (d.bookingDate, fileIdentity, sourceID, reference, d.currency, d.amountMinor)
		let fields: DeadFieldsKey = (d.purpose, iban, pending, fetched, d.deletedAt)
		return (identity, fields)
	}
	let deadKeys = Dictionary(uniqueKeysWithValues: deadCandidates.map { ($0, deadKey(deleted[$0])) })
	let deadOrder: [Int] = deadCandidates.sorted { (left: Int, right: Int) -> Bool in
		let lhs: DeadKey = deadKeys[left]!
		let rhs: DeadKey = deadKeys[right]!
		return lhs.0 == rhs.0 ? lhs.1 < rhs.1 : lhs.0 < rhs.0
	}
	let deadPositions = ranks(deadOrder, count: deleted.count) { i, j in
		if deleted[i].bookingDate != deleted[j].bookingDate { return deleted[i].bookingDate < deleted[j].bookingDate }
		let lhs = deadKeys[i] ?? deadKey(deleted[i])
		let rhs = deadKeys[j]!
		return lhs.0 == rhs.0 ? lhs.1 < rhs.1 : lhs.0 < rhs.0
	}.mapValues { $0 + stored.count }
	func position(_ slot: Slot, legacy: Bool = false) -> Int {
		switch slot {
		case let .live(j): legacy ? j : livePositions[j]!
		case let .deleted(k): legacy ? stored.count + k : deadPositions[k]!
		}
	}
	candidates.sort { (left: Candidate, right: Candidate) -> Bool in
		let leftHistory: Int = left.historical * 2 + left.identityTombstone
		let rightHistory: Int = right.historical * 2 + right.identityTombstone
		let leftDelivered: Int = left.legacy ? left.delivered : deliveredPositions[left.delivered]!
		let rightDelivered: Int = right.legacy ? right.delivered : deliveredPositions[right.delivered]!
		let leftStored: Int = position(left.slot, legacy: left.legacy)
		let rightStored: Int = position(right.slot, legacy: right.legacy)
		let lhs: (Int, Int, Int, Int, Int, Int) = (left.priority.rawValue, leftHistory, left.fit, left.distance, leftDelivered, leftStored)
		let rhs: (Int, Int, Int, Int, Int, Int) = (right.priority.rawValue, rightHistory, right.fit, right.distance, rightDelivered, rightStored)
		return lhs < rhs
	}
	var result = [Partner?](repeating: nil, count: rows.count)
	var taken = Set<Slot>()
	for candidate in candidates where result[candidate.delivered] == nil && !taken.contains(candidate.slot) {
		taken.insert(candidate.slot)
		result[candidate.delivered] = Partner(slot: candidate.slot, evidence: candidate.evidence)
	}
	return result
}

struct Identity {
	let fileIdentity: String?
	let sourceID: String?
	let remoteID: String?
	let key: Key
	let isPending: Bool
	let counterparty: String?
	let endToEnd: String?

	/// The purpose is folded without white space, so the 27-character lines of an MT940 purpose and the
	/// same text in one line have the same key.
	struct Key: Hashable {
		// The synthesized Hashable conformance reads these properties, which Periphery cannot see.
		let day: Day
		// periphery:ignore
		let amount: Int64
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

	init(fileIdentity: String?, sourceID: String?, day: Day, amount: Int64, isPending: Bool, purpose: String, counterparty: String?, endToEnd: String?) {
		self.fileIdentity = fileIdentity
		self.sourceID = sourceID.map(Transaction.matchingID)
		remoteID = Self.remote(sourceID)
		key = Key(day: day, amount: amount, purpose: TextFolding.fold(purpose).filter { !$0.isWhitespace })
		self.isPending = isPending
		self.counterparty = counterparty.map(TextFolding.accountKey).flatMap { $0.isEmpty ? nil : $0 }
		self.endToEnd = endToEnd.flatMap { $0.isEmpty || $0 == "NOTPROVIDED" ? nil : $0 }
	}

	/// An edited row is found by the values of its source.
	init(_ t: Transaction) {
		let delivered = t.sourceValues
		self.init(fileIdentity: t.fileIdentity, sourceID: t.sourceID, day: delivered.bookingDate, amount: delivered.amountMinor, isPending: t.isPending, purpose: delivered.purpose,
			counterparty: t.counterpartyIBAN, endToEnd: t.endToEndReference)
	}

	init(_ d: DeletedTransaction) {
		self.init(fileIdentity: d.fileIdentity, sourceID: d.sourceID, day: d.bookingDate, amount: d.amountMinor, isPending: d.isPending, purpose: d.purpose,
			counterparty: d.counterpartyIBAN, endToEnd: d.endToEndReference)
	}

	static func remote(_ sourceID: String?) -> String? {
		sourceID.flatMap { Transaction.matchingID($0).hasPrefix(Transaction.migrationIDPrefix) ? nil : $0 }
	}

	func sharesIdentity(with other: Identity) -> Bool {
		(fileIdentity != nil && fileIdentity == other.fileIdentity) || (remoteID != nil && remoteID == other.remoteID) || (endToEnd != nil && endToEnd == other.endToEnd)
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
		let p: [PendingMatch] = pending.map { (entry: (Int, Transaction)) -> PendingMatch in PendingMatch(entry.1) }
		let b: [PendingMatch] = booked.map { (entry: (Int, Transaction)) -> PendingMatch in PendingMatch(entry.1) }
		var edgesOfPending = [[Int]](repeating: [], count: p.count)
		var edgesOfBooked = [[Int]](repeating: [], count: b.count)
		var pendingByAmount: [Money: [Int]] = [:]
		for (x, m) in p.enumerated() { pendingByAmount[m.amount, default: []].append(x) }
		for (y, m) in b.enumerated() {
			let sameAmount: [Int] = pendingByAmount[m.amount] ?? []
			// The bank's own pending row may be booked on an earlier day, such as a salary shown for a Sunday and booked on the
			// Friday before. A file row only books on or after its own day. Rows on or before the booked day still come first.
			var fits: [Int] = sameAmount.filter { (i: Int) -> Bool in
				p[i].fits(m) && (pending[i].1.isFetched || p[i].day <= m.day)
			}
			let onOrBefore: [Int] = fits.filter { (i: Int) -> Bool in p[i].day <= m.day }
			if !onOrBefore.isEmpty { fits = onOrBefore }
			let explicit: [Int] = fits.filter { (i: Int) -> Bool in p[i].identity.sharesIdentity(with: m.identity) }
			if !explicit.isEmpty { fits = explicit }
			if let nearest = fits.map({ abs(p[$0].day - m.day) }).min() {
				fits = fits.filter { abs(p[$0].day - m.day) == nearest }
			}
			let fetched = fits.filter { pending[$0].1.isFetched }
			if fetched.count == 1 { fits = fetched }

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
		let delivered = t.sourceValues
		identity = Identity(t)
		amount = Money(minorUnits: delivered.amountMinor, currency: t.currency)
		day = delivered.bookingDate.daysSince1970
		iban = t.counterpartyIBAN.map(TextFolding.accountKey).flatMap { $0.isEmpty ? nil : $0 }
		words = TextFolding.fold(delivered.name).split { !$0.isLetter && !$0.isNumber }
	}

	init(_ d: DeletedTransaction) {
		identity = Identity(d)
		amount = Money(minorUnits: d.amountMinor, currency: d.currency)
		day = d.bookingDate.daysSince1970
		iban = d.counterpartyIBAN.map(TextFolding.accountKey).flatMap { $0.isEmpty ? nil : $0 }
		words = []
	}

	func counterpartyConflicts(with other: PendingMatch) -> Bool {
		if let iban, let otherIBAN = other.iban { return iban != otherIBAN }
		guard !words.isEmpty, !other.words.isEmpty else { return false }
		return !words.starts(with: other.words) && !other.words.starts(with: words)
	}

	func nameConflicts(with other: PendingMatch) -> Bool {
		!words.isEmpty && !other.words.isEmpty && !words.starts(with: other.words) && !other.words.starts(with: words)
	}

	func fits(_ other: PendingMatch) -> Bool {
		guard identity.agrees(with: other.identity), amount == other.amount, abs(day - other.day) <= Self.maxDaysApart,
			!counterpartyConflicts(with: other) else { return false }
		if identity.isPending == other.identity.isPending,
			let fileID = identity.fileIdentity, let otherID = other.identity.fileIdentity, fileID != otherID { return false }
		return identity.endToEnd != nil && identity.endToEnd == other.identity.endToEnd
			|| (iban != nil && other.iban != nil) || (!words.isEmpty && !other.words.isEmpty)
	}
}

extension Transaction {
	var originalFileIdentity: String {
		let identity = Identity(self)
		let counterparty = identity.counterparty.map { "iban:" + $0 } ?? "name:" + TextFolding.fold(name)
		return "file:1:" + [String(bookingDate.rawValue), String(amountMinor), currency, identity.key.purpose,
			counterparty, identity.sourceID ?? "", identity.endToEnd ?? ""].map { "\($0.utf8.count):\($0)" }.joined()
	}

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
			categoryID: delivered.categoryID, categorizedBy: delivered.categorizedBy, isNew: true, isFetched: fetched, sourceID: delivered.sourceID, createdAt: delivered.createdAt, returnReason: delivered.returnReason, fileIdentity: delivered.fileIdentity)
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
		if isPending || fileIdentity != nil { t.endToEndReference = Identity(delivered).endToEnd ?? endToEndReference }
		t.mandateReference = delivered.mandateReference ?? mandateReference
		t.creditorID = delivered.creditorID ?? creditorID
		t.returnReason = delivered.returnReason ?? returnReason
		t.isPending = delivered.isPending
		// A migration ID never replaces the ID of a source that took the row over.
		if Identity.remote(delivered.sourceID) != nil || Identity.remote(sourceID) == nil {
			t.sourceID = delivered.sourceID ?? sourceID
		}
		// An edited field keeps what the user wrote, and `original` follows the source.
		if let original {
			let source = OriginalValues(bookingDate: delivered.bookingDate, valueDate: delivered.valueDate ?? original.valueDate,
				amountMinor: delivered.amountMinor, name: delivered.name, purpose: delivered.purpose)
			var kept = source
			if bookingDate != original.bookingDate { kept.bookingDate = bookingDate }
			if valueDate != original.valueDate { kept.valueDate = valueDate }
			if amountMinor != original.amountMinor { kept.amountMinor = amountMinor }
			if name != original.name { kept.name = name }
			if purpose != original.purpose { kept.purpose = purpose }
			t.original = source
			t.edit(kept)
		}
		return t
	}
}
