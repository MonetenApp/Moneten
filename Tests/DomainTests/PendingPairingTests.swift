import Domain
import Foundation
import Testing

extension ReconcileTests {
	@Test("A fingerprint cannot bypass the PendingMatch currency check", arguments: [false, true], [false, true])
	func gate3FingerprintMoney(fileDelivery: Bool, booked: Bool) {
		var bank = rent(1, purpose: "RENT", pending: !booked)
		bank.currency = "USD"
		let file = rent(1, purpose: "RENT")
		let r = merge(fileDelivery ? .file([file]) : refresh([file]), stored: [bank], at: noon(20, month: 11))
		#expect(r.skipped == 0)
		#expect(r.added.map(\.currency) == ["EUR"])
		#expect(history([bank], after: r).map { "\($0.currency) \($0.amountMinor)" }.sorted() == ["EUR -80000", "USD -80000"])
	}

	@Test("Pending file import stops after seven days even with an agreeing reference", arguments: [8, 9], [false, true])
	func gate3ImportDayBound(fileDay: Int, reference: Bool) {
		var bank = stored(rent(1, purpose: "BANK"))
		var file = rent(fileDay)
		if reference { bank.endToEndReference = "SHARED"; file.endToEndReference = "SHARED" }
		let r = merge(.file([file]), stored: [bank], at: noon(20, month: 11))
		#expect(r.skipped == (fileDay == 8 ? 1 : 0))
		#expect(r.added.count == (fileDay == 8 ? 0 : 1))
	}

	@Test("Closest pending import distance wins over fetched status on another day")
	func gate3ImportClosestStored() {
		let bank = stored(rent(30, month: 11, purpose: "BANK"))
		let file = rent(1, purpose: "OLD FILE")
		for stored in permutations([bank, file]) {
			let r = merge(.file([rent(2)]), stored: stored, at: noon(20, month: 11))
			#expect(r.skipped == 1 && r.added == [])
			#expect(r.updated.map(\.id) == [file.id])
		}
	}

	@Test("Known name conflicts invalidate every weaker fingerprint", arguments: [false, true], [false, true])
	func gate3ReferenceNameConflict(fileDelivery: Bool, reference: Bool) {
		var stored = rent(1, purpose: "RENT")
		stored.counterpartyIBAN = nil
		stored.endToEndReference = reference ? "SHARED" : nil
		var delivered = rent(1, purpose: "RENT")
		delivered.counterpartyIBAN = nil
		delivered.endToEndReference = reference ? "SHARED" : nil
		delivered.name = "Vermieter B"
		let r = merge(fileDelivery ? .file([delivered]) : refresh([delivered]), stored: [stored], at: noon(20, month: 11))
		#expect(r.skipped == 0)
		#expect(r.added.map(\.name) == ["Vermieter B"])
		let rows = history([stored], after: r)
		#expect(rows.map(\.name).sorted() == ["Vermieter A", "Vermieter B"])
		#expect(rows.reduce(0) { $0 + $1.amountMinor } == -160_000)
	}

	@Test("Only a file import creates the original file fingerprint")
	func gate3FileFingerprintOrigin() throws {
		var delivered = rent(1, purpose: "A|B")
		delivered.fileIdentity = "forged"
		let file = merge(.file([delivered]), at: noon(20, month: 11))
		let identity = "file:1:8:202612016:-800003:EUR3:a|b27:iban:DE021203000000002020510:0:"
		#expect(file.added.map(\.fileIdentity) == [identity])
		#expect(merge(refresh([delivered]), at: noon(20, month: 11)).added.map(\.fileIdentity) == [nil])
		#expect(merge(.migration([delivered]), at: noon(20, month: 11)).added.map(\.fileIdentity) == [nil])
		var repeated = delivered
		repeated.id = UUID()
		repeated.comment = "Another comment"
		repeated.isChecked = true
		let again = merge(.file([repeated]), stored: file.added, at: noon(21, month: 11))
		#expect(again.skipped == 1)
		#expect(again.updated == [])
		var booked = delivered
		booked.isPending = false
		let booking = merge(.file([booked]), stored: file.added, at: noon(21, month: 11))
		#expect(booking.booked.map(\.fileIdentity) == [identity])
		#expect(booking.booked.map(\.isPending) == [false])
		var legacy = delivered
		legacy.fileIdentity = nil
		let legacyBooking = merge(.file([booked]), stored: [legacy], at: noon(21, month: 11))
		#expect(legacyBooking.booked.map(\.fileIdentity) == [identity])
	}

	@Test("An unidentified file stays identified after takeover booking and deletion", arguments: [false, true])
	func gate3OriginalFileFingerprint(bankFirst: Bool) throws {
		let file = rent(1)
		let bank = rent(1, purpose: "BANK")
		let initial = bankFirst ? history([], after: merge(refresh([bank]), at: noon(20, month: 11))) : []
		let imported = history(initial, after: merge(.file([file]), stored: initial, at: noon(20, month: 11)))
		let taken = history(imported, after: merge(refresh([bank]), stored: imported, at: noon(20, month: 11)))
		let booked = history(taken, after: merge(refresh([rent(2, purpose: "BOOKED BANK", pending: false)]), stored: taken, at: noon(1, month: 12)))
		let live = try #require(booked.first)
		#expect(booked.count == 1)
		let repeated = merge(.file([file]), stored: booked, at: noon(2, month: 12))
		#expect(repeated.added == [])
		#expect(repeated.skipped == 1)
		#expect(history(booked, after: repeated).map(\.isPending) == [false])
		let deleted = merge(.file([file]), deleted: [DeletedTransaction(live, deletedAt: now)], at: noon(2, month: 12))
		#expect(deleted.added == [])
		#expect(deleted.skipped == 1)
		var native = rent(2, purpose: "BOOKED BANK", pending: false)
		native.isFetched = true
		#expect(merge(.file([file]), stored: [native], at: noon(2, month: 12)).added.map(\.amountMinor) == [-80_000])
	}

	@Test("Different original file fingerprints cannot share a payment", arguments: [false, true])
	func gate3DifferentFileFingerprints(reference: Bool) {
		var first = rent(1, purpose: "Rent A")
		var second = rent(1, purpose: "Rent B")
		if reference { first.endToEndReference = "SHARED"; second.endToEndReference = "SHARED" }
		let stored = history([], after: merge(.file([first]), at: noon(20, month: 11)))
		let r = merge(.file([second]), stored: stored, at: noon(20, month: 11))
		#expect(r.skipped == 0)
		#expect(r.added.map(\.amountMinor) == [-80_000])
		#expect(history(stored, after: r).reduce(0) { $0 + $1.amountMinor } == -160_000)
	}

	@Test("Gate 4 item 1: a changed file booking keeps one payment through repeats and deletion", arguments: [false, true], [false, true])
	func gate4FileBooking(changedPurpose: Bool, reference: Bool) throws {
		var pending = rent(1)
		pending.endToEndReference = reference ? "RENT-A" : nil
		var booked = pending
		booked.id = UUID()
		booked.bookingDate = day(2, month: 12)
		booked.purpose = changedPurpose ? "BOOKED RENT" : "Miete Dezember"
		booked.isPending = false
		let other = row(3, -1_200, "Other", "OTHER", month: 12)
		let initial = merge(.file([pending, other]), at: noon(20, month: 11)).added
		for stored in permutations(initial) {
			for delivered in permutations([booked, fresh(other)]) {
				let r = merge(.file(delivered), stored: stored, at: noon(2, month: 12))
				#expect(r.booked.map(\.id) == [pending.id])
				let after = history(stored, after: r)
				#expect(after.count == 2)
				#expect(after.reduce(0) { $0 + $1.amountMinor } == -81_200)
				let live = try #require(after.first { $0.id == pending.id })
				#expect(!live.isPending && live.bookingDate == day(2, month: 12))
				#expect(live.purpose == (changedPurpose ? "BOOKED RENT" : "Miete Dezember"))
				for repeated in [pending, booked] {
					let again = merge(.file([repeated]), stored: after, at: noon(3, month: 12))
					#expect(again.added == [] && again.skipped == 1)
					var fetched = live
					fetched.isFetched = true
					let deleted = merge(.file([repeated]), deleted: [DeletedTransaction(fetched, deletedAt: now)], at: noon(3, month: 12))
					#expect(deleted.added == [] && deleted.skipped == 1)
				}
			}
		}
	}

	@Test("Gate 4 item 2: booked name reordering without an IBAN is skipped as on main", arguments: [false, true], [false, true])
	func gate4BookedNames(fileDelivery: Bool, identified: Bool) {
		var known = stored(row(10, -4_999, "MUSTERMANN, MAX", "Kartenzahlung 1234"))
		if identified { known = merge(.file([known])).added[0] }
		var delivered = fresh(known)
		delivered.name = "Max Mustermann"
		let other = stored(row(11, -1_200, "Other", "OTHER"))
		for stored in permutations([known, other]) {
			for rows in permutations([delivered, fresh(other)]) {
				let r = merge(fileDelivery ? .file(rows) : refresh(rows), stored: stored)
				#expect(r.added == [] && r.skipped == 2)
				let after = history(stored, after: r)
				#expect(after.count == 2)
				#expect(after.reduce(0) { $0 + $1.amountMinor } == -6_199)
				#expect(after.first { $0.id == known.id }?.name == "MUSTERMANN, MAX")
			}
		}
	}

	@Test("Gate 4 item 3: a fetched pending rent within seven days keeps its partner", arguments: [false, true])
	func gate4FetchedDateMove(persisted: Bool) {
		let originals = [rent(1), rent(8)]
		let files = persisted ? merge(.file(originals), at: noon(20, month: 11)).added : originals
		for firstStored in permutations(files) {
			let first = history(firstStored, after: merge(refresh([rent(1, purpose: "BANK")]), stored: firstStored, at: noon(20, month: 11)))
			let other = row(3, -1_200, "Other", "OTHER", month: 12)
			for stored in permutations(first) {
				for delivered in permutations([rent(2, purpose: "CHANGED BANK"), other]) {
					let r = merge(refresh(delivered), stored: stored, at: noon(21, month: 11))
					let after = history(stored, after: r)
					#expect(pendingSummary(after) == ["20261202 -80000 true true false CHANGED BANK", "20261203 -1200 false true false OTHER", "20261208 -80000 true false false Miete Dezember"])
					#expect(r.updated.map(\.id) == [originals[0].id])
					#expect(r.dropped == [])
					let repeated = merge(refresh(delivered), stored: after, at: noon(22, month: 11))
					#expect(pendingSummary(history(after, after: repeated)) == pendingSummary(after))
				}
			}
		}
	}

	@Test("Gate 4 item 4: booking considers only nearest file rows on or before its date", arguments: [false, true])
	func gate4NearestBooking(ambiguous: Bool) {
		let originals = [rent(7), rent(14)] + (ambiguous ? [rent(7)] : [])
		let files = merge(.file(originals), at: noon(20, month: 11)).added
		let other = row(3, -1_200, "Other", "OTHER", month: 12)
		for stored in permutations(files) {
			for delivered in permutations([rent(7, purpose: "BOOKED RENT", pending: false), other]) {
				let r = merge(refresh(delivered), stored: stored, at: noon(7, month: 12))
				let after = history(stored, after: r)
				#expect(after.first { $0.id == originals[1].id }?.needsReview == false)
				#expect(!r.marked.contains { $0.id == originals[1].id })
				#expect(r.booked.count == (ambiguous ? 0 : 1))
				#expect(r.marked.count == (ambiguous ? 2 : 0))
				#expect(after.count == (ambiguous ? 5 : 3))
				#expect(after.reduce(0) { $0 + $1.amountMinor } == (ambiguous ? -321_200 : -161_200))
			}
		}
	}

	@Test("Gate 4 booking never overrides conflicting real identities", arguments: [false, true])
	func gate4BookingConflict(source: Bool) {
		var pending = rent(1)
		var booked = rent(2, purpose: "BOOKED RENT", pending: false)
		if source { pending.sourceID = "FILE-A"; booked.sourceID = "FILE-B" }
		else { pending.endToEndReference = "RENT-A"; booked.endToEndReference = "RENT-B" }
		let files = merge(.file([pending]), at: noon(20, month: 11)).added
		let r = merge(.file([booked]), stored: files, at: noon(2, month: 12))
		#expect(r.booked == [] && r.marked == [])
		#expect(history(files, after: r).reduce(0) { $0 + $1.amountMinor } == -160_000)
	}

	@Test("A pending source-ID correction keeps its row and user fields")
	func gate4PendingSourceCorrection() {
		var known = stored(row(3, -10_000, "Broker", "Sparplan", pending: true, sourceID: "tx-1001"))
		known.comment = "ETF savings plan"
		known.isChecked = true
		let corrected = row(3, -10_050, "Broker", "Sparplan", pending: true, sourceID: "tx-1001")
		let r = merge(refresh([corrected]), stored: [known])
		#expect(r.added == [] && r.dropped == [])
		#expect(r.updated.map(\.id) == [known.id])
		#expect(r.updated.map(\.amountMinor) == [-10_050])
		#expect(r.updated.map(\.comment) == ["ETF savings plan"])
		#expect(r.updated.map(\.isChecked) == [true])
	}

	@Test("A reference-only pending delivery keeps main's booked-version eligibility", arguments: ["file", "refresh", "migration"], [false, true])
	func gate4ReferenceEligibility(kind: String, identified: Bool) {
		var booked = stored(rent(2, purpose: "BOOKED RENT", pending: false))
		booked.endToEndReference = "RENT-A"
		if identified { booked = stored(merge(.file([booked])).added[0]) }
		var pending = rent(1, purpose: "PENDING RENT")
		pending.endToEndReference = "RENT-A"
		let other = stored(row(3, -1_200, "Other", "OTHER", month: 12))
		for stored in permutations([booked, other]) {
			for rows in permutations([pending, fresh(other)]) {
				let delivery: Delivery = switch kind {
				case "file": .file(rows)
				case "refresh": refresh(rows)
				default: .migration(rows)
				}
				let r = merge(delivery, stored: stored, at: noon(3, month: 12))
				let after = history(stored, after: r)
				#expect(after.first { $0.id == booked.id }?.isPending == false)
				#expect(after.first { $0.id == booked.id }?.purpose == "BOOKED RENT")
				#expect(after.first { $0.id == booked.id }?.bookingDate == day(2, month: 12))
				#expect(after.count == (kind == "file" ? 2 : 3))
				#expect(after.reduce(0) { $0 + $1.amountMinor } == (kind == "file" ? -81_200 : -161_200))
			}
		}
	}

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

	@Test("Gate 3 item 5: exactly one fetched pending row wins a booking", arguments: [false, true])
	func gate3BookedPrefersFetched(sharedReference: Bool) {
		var file = [rent(1), rent(8)]
		var pending = rent(1, purpose: "BANK")
		var booked = rent(2, purpose: "BOOKED BANK", pending: false)
		if sharedReference {
			for i in file.indices { file[i].endToEndReference = "RECURRING-RENT" }
			pending.endToEndReference = "RECURRING-RENT"
			booked.endToEndReference = "RECURRING-RENT"
		}
		let first = history(file, after: merge(refresh([pending]), stored: file, at: noon(20, month: 11)))
		let r = merge(refresh([booked]), stored: first, at: noon(2, month: 12))
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
		#expect(r.updated.map(\.comment) == [""])
		let identified = history([live], after: r)
		#expect(identified.map(\.comment) == [""])
		#expect(merge(.file([file]), stored: identified, at: noon(22, month: 11)).updated == [])
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

	@Test("A current booked fingerprint wins before a historical pending reference", arguments: [false, true])
	func gate3BookedReferenceFingerprint(missingReference: Bool) {
		var pending = stored(rent(1, purpose: "PENDING"))
		pending.comment = "USER-A"
		var booked = stored(rent(1, purpose: "BOOKED", pending: false))
		booked.endToEndReference = "SHARED"
		booked.comment = "USER-B"
		var incomingPending = fresh(pending)
		incomingPending.purpose = "CHANGED"
		incomingPending.endToEndReference = "SHARED"
		incomingPending.createdAt = Date(timeIntervalSince1970: 0)
		var incomingBooked = fresh(booked)
		if missingReference { incomingBooked.endToEndReference = nil }
		for stored in permutations([pending, booked]) {
			for delivered in permutations([incomingPending, incomingBooked]) {
				let r = merge(.file(delivered), stored: stored, at: noon(20, month: 11))
				let after = history(stored, after: r)
				#expect(r.added == [] && r.booked == [] && r.skipped == 2)
				#expect(pendingSummary(after) == ["20261201 -80000 false true false BOOKED", "20261201 -80000 true true false PENDING"])
				#expect(after.first { $0.id == pending.id }?.comment == "USER-A")
				#expect(after.first { $0.id == booked.id }?.comment == "USER-B")
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

	@Test("Gate 3 items 1 4 5: every delivered and stored permutation has literal rows", arguments: [false, true])
	func gate3AllPermutations(persisted: Bool) {
		for (fileDays, bankDays, expected) in [
			([1, 8], [7, 15], ["20261201 -80000 true false false Miete Dezember", "20261207 -80000 true true false BANK", "20261215 -80000 true true false BANK"]),
			([5, 1], [4, 10], ["20261201 -80000 true false false Miete Dezember", "20261204 -80000 true true false BANK", "20261210 -80000 true true false BANK"])
		] {
			let original = fileDays.map { rent($0) }
			let files = persisted ? merge(.file(original), at: noon(20, month: 11)).added : original
			let banks = bankDays.map { rent($0, purpose: "BANK") }
			for stored in permutations(files) {
				for delivered in permutations(banks) {
					let r = merge(refresh(delivered), stored: stored, at: noon(20, month: 11))
					#expect(pendingSummary(history(stored, after: r)) == expected)
				}
			}
		}
		let cases: [([Transaction], [String])] = [
			([rent(1)], ["20261130 -80000 true true false BANK MIETE"]),
			([rent(1), rent(8)], ["20261201 -80000 true true false BANK MIETE", "20261208 -80000 true false false Miete Dezember"]),
			([rent(30, month: 11), rent(2)], ["20261201 -80000 true true false BANK MIETE", "20261202 -80000 true false false Miete Dezember"])
		]
		for (index, test) in cases.enumerated() {
			let bank = stored(index == 0 ? rent(30, month: 11, purpose: "BANK MIETE") : rent(1, purpose: "BANK MIETE"))
			let other = stored(row(3, -1200, "Other", "OTHER", month: 12, pending: true))
			for stored in permutations([bank, other]) {
				for delivered in permutations(test.0) {
					let r = merge(.file(delivered), stored: stored, at: noon(20, month: 11))
					let next = history(stored, after: r)
					let expected = (test.1 + ["20261203 -1200 true true false OTHER"]).sorted()
					#expect(r.skipped == 1)
					#expect(pendingSummary(next) == expected)
					let repeatResult = merge(.file(delivered), stored: next, at: noon(21, month: 11))
					#expect(pendingSummary(history(next, after: repeatResult)) == expected)
				}
			}
		}

		let original = [rent(1), rent(8)]
		let files = persisted ? merge(.file(original), at: noon(20, month: 11)).added : original
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
