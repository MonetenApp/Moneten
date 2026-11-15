import Domain
import Foundation
import Testing

extension ReconcileTests {
	func permutations<T>(_ rows: [T]) -> [[T]] {
		guard !rows.isEmpty else { return [[]] }
		return rows.indices.flatMap { i in
			var rest = rows
			let first = rest.remove(at: i)
			return permutations(rest).map { [first] + $0 }
		}
	}

	func pendingSummary(_ rows: [Transaction]) -> [String] {
		rows.map { "\($0.bookingDate.rawValue) \($0.amountMinor) \($0.isPending) \($0.isFetched) \($0.needsReview) \($0.purpose)" }.sorted()
	}

	@Test("Gate 3 item 1: global nearest pairs do not follow delivery order")
	func gate3GlobalNearest() {
		let file = [rent(1), rent(8)]
		let r = merge(refresh([rent(7, purpose: "BANK"), rent(15, purpose: "BANK")]), stored: file, at: noon(20, month: 11))
		#expect(pendingSummary(history(file, after: r)) == [
			"20261201 -80000 true false false Miete Dezember",
			"20261207 -80000 true true false BANK",
			"20261215 -80000 true true false BANK"
		])
		#expect(r.updated.map(\.id) == [file[1].id])
	}

	@Test("Gate 3 item 2: different explicit identities never pair", arguments: [false, true], [false, true])
	func gate3DifferentIdentities(source: Bool, fetched: Bool) {
		var first = rent(1)
		var second = rent(1)
		if source { first.sourceID = "FILE-A"; second.sourceID = "FILE-B" }
		else { first.endToEndReference = "RENT-A"; second.endToEndReference = "RENT-B" }
		let r = merge(fetched ? refresh([second]) : .file([second]), stored: [first], at: noon(20, month: 11))
		#expect(r.skipped == 0)
		#expect(r.added.map(\.amountMinor) == [-80_000])
		#expect(history([first], after: r).reduce(0) { $0 + $1.amountMinor } == -160_000)
	}

	@Test("Gate 3 item 3: file identity survives takeover booking and tombstone", arguments: [false, true], [false, true])
	func gate3IdentityLifecycle(booked: Bool, reference: Bool) throws {
		var file = rent(1)
		if reference { file.endToEndReference = "RENT-A" }
		else { file.sourceID = "FILE-A" }
		let takeover = merge(refresh([rent(1, purpose: "BANK")]), stored: [file], at: noon(20, month: 11))
		var live = try #require(history([file], after: takeover).first)
		#expect(live.endToEndReference == (reference ? "RENT-A" : nil))
		#expect(live.sourceID == (reference ? nil : "FILE-A"))
		if booked {
			let booking = merge(refresh([rent(2, purpose: "BOOKED BANK", pending: false)]), stored: [live], at: noon(1, month: 12))
			live = try #require(history([live], after: booking).first)
			#expect(!live.isPending)
		}
		let repeatLive = merge(.file([file]), stored: [live], at: noon(21, month: 11))
		#expect(repeatLive.added == [])
		#expect(repeatLive.skipped == 1)
		#expect(history([live], after: repeatLive).map(\.isPending) == [!booked])
		let repeatDeleted = merge(.file([file]), deleted: [DeletedTransaction(live, deletedAt: now)], at: noon(21, month: 11))
		#expect(repeatDeleted.added == [])
		#expect(repeatDeleted.skipped == 1)
	}

	@Test("Gate 3 item 3: an honored pending tombstone takes part in same-day matching")
	func gate3RelaxedTombstone() {
		let tombstone = DeletedTransaction(stored(rent(1, purpose: "BANK")), deletedAt: now)
		let r = merge(.file([rent(1)]), deleted: [tombstone], at: noon(21, month: 11))
		#expect(r.added == [])
		#expect(r.skipped == 1)
	}

	@Test("An agreeing end-to-end reference finds a tombstone without a counterparty IBAN")
	func gate3ReferenceWithoutIBAN() {
		var file = rent(1)
		file.counterpartyIBAN = nil
		file.endToEndReference = "RENT-A"
		var bank = stored(file)
		bank.purpose = "BANK"
		let r = merge(.file([file]), deleted: [DeletedTransaction(bank, deletedAt: now)], at: noon(21, month: 11))
		#expect(r.added == [])
		#expect(r.skipped == 1)
	}

	@Test("Gate 3 item 4: a changed bank purpose keeps the fetched partner")
	func gate3ChangedPurpose() {
		let file = [rent(1), rent(8)]
		let first = history(file, after: merge(refresh([rent(1, purpose: "BANK")]), stored: file, at: noon(20, month: 11)))
		let r = merge(refresh([rent(1, purpose: "CHANGED BANK")]), stored: first, at: noon(21, month: 11))
		#expect(pendingSummary(history(first, after: r)) == [
			"20261201 -80000 true true false CHANGED BANK",
			"20261208 -80000 true false false Miete Dezember"
		])
		#expect(r.updated.map(\.id) == [file[0].id])
		#expect(r.dropped == [])
	}

	@Test("Gate 3 item 5: exactly one fetched pending row wins a booking")
	func gate3BookedPrefersFetched() {
		let file = [rent(1), rent(8)]
		let first = history(file, after: merge(refresh([rent(1, purpose: "BANK")]), stored: file, at: noon(20, month: 11)))
		let r = merge(refresh([rent(2, purpose: "BOOKED BANK", pending: false)]), stored: first, at: noon(2, month: 12))
		#expect(pendingSummary(history(first, after: r)) == [
			"20261202 -80000 false true false BOOKED BANK",
			"20261208 -80000 true false false Miete Dezember"
		])
		#expect(r.booked.map(\.id) == [file[0].id])
		#expect(r.marked == [])
	}

	@Test("Gate 3 item 6: an exact file repeat cannot restore a cleared comment", arguments: [false, true])
	func gate3ClearedComment(reference: Bool) {
		var file = rent(1)
		file.comment = "Shared rent"
		if reference { file.endToEndReference = "RENT-A" }
		var live = file
		live.comment = ""
		let r = merge(.file([file]), stored: [live], at: noon(21, month: 11))
		#expect(r.updated == [])
		#expect(history([live], after: r).map(\.comment) == [""])
	}

	@Test("A bank-first skip retains the file identity before deletion", arguments: [false, true])
	func gate3BankFirstIdentity(booked: Bool) throws {
		var file = rent(1)
		file.counterpartyIBAN = nil
		file.endToEndReference = "RENT-A"
		var bank = stored(file)
		bank.endToEndReference = nil
		bank.purpose = "BANK"
		let first = merge(.file([file]), stored: [bank], at: noon(20, month: 11))
		var live = try #require(history([bank], after: first).first)
		#expect(live.endToEndReference == "RENT-A")
		var other = file
		other.endToEndReference = "RENT-B"
		#expect(merge(.file([other]), stored: [live], at: noon(21, month: 11)).added.map(\.amountMinor) == [-80_000])
		if booked {
			var booking = file
			booking.isPending = false
			booking.bookingDate = day(2, month: 12)
			booking.purpose = "BOOKED BANK"
			live = try #require(history([live], after: merge(refresh([booking]), stored: [live], at: noon(2, month: 12))).first)
		}
		let deleted = [DeletedTransaction(live, deletedAt: now)]
		let repeated = merge(.file([file]), deleted: deleted, at: noon(21, month: 11))
		#expect(repeated.added == [] && repeated.skipped == 1)
		#expect(merge(.file([other]), deleted: deleted, at: noon(21, month: 11)).added.map(\.amountMinor) == [-80_000])
	}

	@Test("An unrelated booked row cannot absorb a new pending file payment", arguments: [false, true])
	func gate3UnrelatedBooked(deleted: Bool) {
		let bank = stored(rent(1, purpose: "BANK", pending: false))
		let r = merge(.file([rent(1)]), stored: deleted ? [] : [bank], deleted: deleted ? [DeletedTransaction(bank, deletedAt: now)] : [], at: noon(20, month: 11))
		#expect(r.added.map(\.amountMinor) == [-80_000])
		#expect(r.skipped == 0)
	}

	@Test("An agreeing identity repeat preserves cleared user fields after a relaxed import", arguments: [false, true])
	func gate3KnownIdentityKeepsClearedFields(bankAlreadyKnows: Bool) throws {
		let housing = Domain.Category(position: 0, name: "Housing")
		var file = rent(1)
		file.endToEndReference = "RENT-A"
		file.comment = "Shared rent"
		file.categoryID = housing.id
		file.categorizedBy = .manual
		file.isChecked = true
		var bank = stored(rent(1, purpose: "BANK"))
		bank.endToEndReference = bankAlreadyKnows ? "RENT-A" : nil
		var live = bank
		if !bankAlreadyKnows {
			live = try #require(history([bank], after: merge(.file([file]), stored: [bank], categories: [housing])).first)
			#expect(live.comment == "Shared rent" && live.categoryID == housing.id && live.isChecked)
		}
		live.comment = ""
		live.categoryID = nil
		live.categorizedBy = .none
		live.isChecked = false
		let r = merge(.file([file]), stored: [live], categories: [housing])
		let kept = try #require(history([live], after: r).first)
		#expect(kept.comment == "")
		#expect(kept.categoryID == nil)
		#expect(!kept.isChecked)
	}

	@Test("A file reference survives successive bank date changes through booking")
	func gate3ReferenceAfterDateMoves() throws {
		var file = rent(1)
		file.endToEndReference = "RENT-A"
		let taken = history([file], after: merge(refresh([rent(8, purpose: "BANK")]), stored: [file], at: noon(20, month: 11)))
		let booked = history(taken, after: merge(refresh([rent(15, purpose: "BOOKED BANK", pending: false)]), stored: taken, at: noon(15, month: 12)))
		let live = try #require(booked.first)
		#expect(live.bookingDate == day(15, month: 12) && !live.isPending)
		let repeated = merge(.file([file]), stored: booked, at: noon(16, month: 12))
		#expect(repeated.added == [] && repeated.skipped == 1)
		let deleted = merge(.file([file]), deleted: [DeletedTransaction(live, deletedAt: now)], at: noon(16, month: 12))
		#expect(deleted.added == [] && deleted.skipped == 1)
	}

	@Test("Exact pending fingerprints win before compatible and relaxed partners", arguments: [false, true], [false, true])
	func gate3FingerprintPrecedence(fetched: Bool, fileDelivery: Bool) {
		var a = rent(1)
		a.counterpartyIBAN = "DE02120300000000202051"
		a.isFetched = fetched
		var b = rent(1)
		b.counterpartyIBAN = "DE89370400440532013000"
		b.isFetched = fetched
		var deliveredB = fresh(b)
		deliveredB.counterpartyIBAN = nil
		deliveredB.createdAt = Date(timeIntervalSince1970: 0)
		var deliveredA = fresh(a)
		deliveredA.createdAt = Date(timeIntervalSince1970: 1)
		for stored in permutations([a, b]) {
			for rows in permutations([deliveredB, deliveredA]) {
				let r = merge(fileDelivery ? .file(rows) : refresh(rows), stored: stored, at: noon(20, month: 11))
				#expect(r.added == [] && r.dropped == [] && r.skipped == 2)
				let after = history(stored, after: r)
				#expect(Set(after.map(\.id)) == Set([a.id, b.id]))
				#expect(after.map { $0.counterpartyIBAN ?? "" }.sorted() == ["DE02120300000000202051", "DE89370400440532013000"])
			}
		}
	}

	@Test("A live source-ID row wins over historical tombstones", arguments: [false, true], [false, true])
	func gate3LiveSourceBeforeTombstone(pendingTombstone: Bool, pendingEcho: Bool) {
		var old = stored(rent(1, purpose: "OLD", pending: pendingTombstone))
		old.sourceID = "BANK-X"
		var live = stored(rent(2, purpose: "OLD", pending: false))
		live.sourceID = "BANK-X"
		var corrected = rent(1, purpose: "CORRECTED", pending: false)
		corrected.sourceID = "BANK-X"
		var echo = fresh(old)
		echo.isPending = true
		echo.createdAt = Date(timeIntervalSince1970: 0)
		let other = stored(row(3, -1_200, "Other", "OTHER", month: 12, sourceID: "BANK-Y"))
		var oldOther = rent(4)
		oldOther.sourceID = "BANK-Z"
		for stored in permutations([live, other]) {
			for deleted in permutations([DeletedTransaction(old, deletedAt: now), DeletedTransaction(oldOther, deletedAt: now)]) {
				for delivered in permutations([corrected, fresh(other)] + (pendingEcho ? [echo] : [])) {
					let r = merge(refresh(delivered), stored: stored, deleted: deleted, at: noon(20, month: 11))
					#expect(r.added == [] && r.skipped == (pendingEcho ? 3 : 2))
					#expect(r.updated.map(\.id) == [live.id])
					#expect(pendingSummary(history(stored, after: r)) == ["20261201 -80000 false true false CORRECTED", "20261203 -1200 false true false OTHER"])
				}
			}
		}
	}

	@Test("A source ID reserves its row before a shared end-to-end reference")
	func gate3SourceBeforeReference() {
		var a = stored(rent(1))
		a.sourceID = "BANK-A"
		a.endToEndReference = "RECURRING-RENT"
		var b = stored(rent(1))
		b.sourceID = "BANK-B"
		b.endToEndReference = "RECURRING-RENT"
		var deliveredB = fresh(b)
		deliveredB.sourceID = nil
		deliveredB.createdAt = Date(timeIntervalSince1970: 0)
		var deliveredA = fresh(a)
		deliveredA.createdAt = Date(timeIntervalSince1970: 1)
		for stored in permutations([a, b]) {
			for delivered in permutations([deliveredB, deliveredA]) {
				let r = merge(refresh(delivered), stored: stored, at: noon(20, month: 11))
				let after = history(stored, after: r)
				#expect(r.added == [] && r.dropped == [] && r.skipped == 2)
				#expect(Set(after.map(\.id)) == Set([a.id, b.id]))
				#expect(after.map { $0.sourceID ?? "" }.sorted() == ["BANK-A", "BANK-B"])
			}
		}
	}

	@Test("Shared references preserve known counterparties and exact fingerprints", arguments: [(true, false), (false, false), (false, true)])
	func gate3SharedReferenceCounterparties(hasIBAN: Bool, changedPurpose: Bool) {
		var a = stored(rent(1, purpose: hasIBAN ? "RENT" : "RENT A"))
		a.endToEndReference = "RECURRING-RENT"
		a.counterpartyIBAN = hasIBAN ? "DE02120300000000202051" : nil
		a.comment = "USER-A"
		var b = stored(rent(1, purpose: hasIBAN ? "RENT" : "RENT B"))
		b.endToEndReference = "RECURRING-RENT"
		b.counterpartyIBAN = hasIBAN ? "DE89370400440532013000" : nil
		b.comment = "USER-B"
		if changedPurpose { b.name = "Vermieter B" }
		var deliveredB = fresh(b)
		deliveredB.createdAt = Date(timeIntervalSince1970: 0)
		var deliveredA = fresh(a)
		deliveredA.createdAt = Date(timeIntervalSince1970: 1)
		if changedPurpose { deliveredA.purpose = "CHANGED A"; deliveredB.purpose = "CHANGED B" }
		var expectedA = a
		var expectedB = b
		if changedPurpose { expectedA.purpose = "CHANGED A"; expectedB.purpose = "CHANGED B" }
		for stored in permutations([a, b]) {
			for delivered in permutations([deliveredB, deliveredA]) {
				let r = merge(refresh(delivered), stored: stored, at: noon(20, month: 11))
				let after = history(stored, after: r)
				#expect(r.added == [] && r.dropped == [] && r.skipped == 2)
				#expect(after.first { $0.id == a.id } == expectedA)
				#expect(after.first { $0.id == b.id } == expectedB)
			}
		}
	}

	@Test("A known booked fingerprint wins before a pending reference-only repeat")
	func gate3BookedReferenceFingerprint() {
		let pending = rent(1)
		var booked = rent(1, pending: false)
		booked.endToEndReference = "RECURRING-RENT"
		var incomingPending = fresh(pending)
		incomingPending.endToEndReference = "RECURRING-RENT"
		incomingPending.createdAt = Date(timeIntervalSince1970: 0)
		let incomingBooked = fresh(booked)
		for stored in permutations([pending, booked]) {
			for delivered in permutations([incomingPending, incomingBooked]) {
				let r = merge(.file(delivered), stored: stored, at: noon(20, month: 11))
				let after = history(stored, after: r)
				#expect(r.added == [] && r.booked == [] && r.skipped == 2)
				#expect(after.first { $0.id == pending.id }?.isPending == true)
				#expect(after.first { $0.id == booked.id }?.isPending == false)
			}
		}
	}

	@Test("A source arriving booked prevents its pending tombstone from absorbing a new look-alike", arguments: [false, true])
	func gate3BookedSourceReleasesLookalike(referenceAgrees: Bool) {
		var old = rent(1)
		old.sourceID = "moneymoney:3"
		old.endToEndReference = "RENT-A"
		var booked = fresh(old)
		booked.isPending = false
		booked.endToEndReference = referenceAgrees ? "RENT-A" : "RENT-B"
		var other = rent(1)
		other.sourceID = "moneymoney:7"
		other.endToEndReference = "RENT-A"
		for delivered in permutations([booked, other]) {
			let r = merge(.migration(delivered), deleted: [DeletedTransaction(old, deletedAt: now)], at: noon(20, month: 11))
			#expect(r.skipped == (referenceAgrees ? 0 : 1))
			#expect(r.added.map { "\($0.sourceID ?? "") \($0.isPending)" }.sorted() == (referenceAgrees ? ["moneymoney:3 false", "moneymoney:7 true"] : ["moneymoney:3 false"]))
		}
	}

	@Test("Tombstone keys retain flags and distinguish missing fields from empty text", arguments: ["fetched", "source", "reference", "iban"])
	func gate3TombstoneStableKeys(difference: String) {
		var delivered = rent(1)
		var lower = DeletedTransaction(delivered, deletedAt: now)
		if difference == "iban" { lower.counterpartyIBAN = nil; delivered.counterpartyIBAN = nil }
		var higher = lower
		switch difference {
		case "fetched": higher.wasFetched = true
		case "source": higher.sourceID = ""
		case "reference": higher.endToEndReference = ""
		default: higher.counterpartyIBAN = ""
		}
		delivered.sourceID = "moneymoney:3"
		for deleted in permutations([higher, lower]) {
			let r = merge(.migration([delivered]), deleted: deleted, at: noon(20, month: 11))
			#expect(r.added == [] && r.skipped == 1)
			#expect(r.relinked.map(\.row) == [lower])
			#expect(r.relinked.map(\.sourceID) == ["moneymoney:3"])
		}
	}

	@Test("Gate 3 items 1 4 5: every delivered and stored permutation has literal rows")
	func gate3AllPermutations() {
		for (fileDays, bankDays, expected) in [
			([1, 8], [7, 15], ["20261201 -80000 true false false Miete Dezember", "20261207 -80000 true true false BANK", "20261215 -80000 true true false BANK"]),
			([5, 1], [4, 10], ["20261201 -80000 true false false Miete Dezember", "20261204 -80000 true true false BANK", "20261210 -80000 true true false BANK"])
		] {
			let files = fileDays.map { rent($0) }
			let banks = bankDays.map { rent($0, purpose: "BANK") }
			for stored in permutations(files) {
				for delivered in permutations(banks) {
					let r = merge(refresh(delivered), stored: stored, at: noon(20, month: 11))
					#expect(pendingSummary(history(stored, after: r)) == expected)
				}
			}
		}
		let files = [rent(1), rent(8)]
		let first = history(files, after: merge(refresh([rent(1, purpose: "BANK")]), stored: files, at: noon(20, month: 11)))
		let extra = row(3, -1_200, "Other", "OTHER", month: 12, pending: true)
		for booked in [false, true] {
			let bank = rent(booked ? 2 : 1, purpose: booked ? "BOOKED BANK" : "CHANGED BANK", pending: !booked)
			let expected = booked ? ["20261202 -80000 false true false BOOKED BANK", "20261203 -1200 true true false OTHER", "20261208 -80000 true false false Miete Dezember"] : ["20261201 -80000 true true false CHANGED BANK", "20261203 -1200 true true false OTHER", "20261208 -80000 true false false Miete Dezember"]
			for stored in permutations(first) {
				for delivered in permutations([bank, extra]) {
					let r = merge(refresh(delivered), stored: stored, at: noon(21, month: 11))
					#expect(pendingSummary(history(stored, after: r)) == expected)
					#expect(r.marked == [])
					let next = history(stored, after: r)
					let repeatResult = merge(refresh(delivered), stored: next, at: noon(21, month: 11))
					#expect(pendingSummary(history(next, after: repeatResult)) == expected)
				}
			}
		}
	}
}
