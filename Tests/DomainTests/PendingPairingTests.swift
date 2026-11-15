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
			let booking = merge(refresh([rent(1, purpose: "BOOKED BANK", pending: false)]), stored: [live], at: noon(1, month: 12))
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

	@Test("Gate 3 item 6: an exact file repeat cannot restore a cleared comment")
	func gate3ClearedComment() {
		var file = rent(1)
		file.comment = "Shared rent"
		var live = file
		live.comment = ""
		let r = merge(.file([file]), stored: [live], at: noon(21, month: 11))
		#expect(r.updated == [])
		#expect(history([live], after: r).map(\.comment) == [""])
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
