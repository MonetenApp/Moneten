import Foundation
import Testing
@testable import Domain

extension ReconcileTests {
	@Test("Gate 5: 6,144 booked comparisons keep main's legacy pairing")
	func gate5LegacyComparisons() {
		for seed in 0..<6_144 {
			var random = PairingRandom(state: UInt64(seed) + 1)
			let stored = (0..<4).map { i in
				var t = rent(1 + random.next(7), purpose: ["RENT", "BANK"][random.next(2)], pending: false)
				t.counterpartyIBAN = [nil, "DE02120300000000202051"][random.next(2)]
				t.sourceID = random.next(2) == 0 ? "BANK-\(i)" : nil
				return t
			}
			let rows = [fresh(stored[random.next(4)]), fresh(stored[random.next(4)])]
			let tombstones = [DeletedTransaction(stored[3], deletedAt: now)]
			let unrelated = row(1, -99, "Other", month: 11, pending: true)
			let expected = partners(of: rows, stored: stored + [unrelated], deleted: tombstones)
			let actual = partners(of: rows, stored: stored + [unrelated], deleted: tombstones, delivery: refresh(rows), today: day(20))
			#expect(actual.map { $0?.slot } == expected.map { $0?.slot }, "legacy seed \(seed)")
		}
		print("gate5 legacy: 6,144 comparisons with main's unchanged partner function")
	}

	@Test("Gate 5: 3,000 seeded histories keep the same result in reversed input order")
	func gate5SeededOrderIndependence() {
		for seed in 0..<3_000 {
			var random = PairingRandom(state: UInt64(seed) + 1)
			func make(_ index: Int) -> Transaction {
				var t = rent(1 + random.next(21), purpose: ["RENT", "BANK", "OTHER"][random.next(3)], pending: true)
				t.id = UUID(uuidString: String(format: "00000000-0000-0000-%04X-%012X", seed, index))!
				t.createdAt = Date(timeIntervalSince1970: Double(index))
				t.amountMinor = [-80_000, -1_200][random.next(2)]
				t.name = ["Vermieter A", "Vermieter B", ""][random.next(3)]
				t.counterpartyIBAN = [nil, "DE02120300000000202051", "DE89370400440532013000"][random.next(3)]
				t.endToEndReference = [nil, "RENT-A", "RENT-B"][random.next(3)]
				t.sourceID = [nil, "BANK-A", "BANK-B"][random.next(3)]
				t.isFetched = random.next(2) == 0
				t.fileIdentity = [nil, "file:A", "file:B"][random.next(3)]
				t.comment = "Comment \(index)"
				return t
			}
			let stored = (0..<6).map(make)
			let deleted = (6..<8).map { DeletedTransaction(make($0), deletedAt: now) }
			var rows = (8..<12).map(make)
			if seed % 2 == 0 { rows[0] = fresh(stored[0]); rows[0].id = make(12).id }
			func delivery(_ ts: [Transaction]) -> Delivery {
				switch seed % 3 {
				case 0: .file(ts)
				case 1: .migration(ts)
				default: refresh(ts)
				}
			}
			let first = merge(delivery(rows), stored: stored, deleted: deleted, at: noon(20, month: 11))
			let second = merge(delivery(rows.reversed()), stored: stored.reversed(), deleted: deleted.reversed(), at: noon(20, month: 11))
			let a = history(stored, after: first).sorted { $0.id.uuidString < $1.id.uuidString }
			let b = history(stored, after: second).sorted { $0.id.uuidString < $1.id.uuidString }
			#expect(a == b, "seed \(seed)")
			#expect(first.skipped == second.skipped, "seed \(seed)")
			#expect(Set(first.relinked) == Set(second.relinked), "seed \(seed)")
		}
		print("gate5 fuzz: 3,000 seeds, two delivery/storage/tombstone orders")
	}
}

private struct PairingRandom {
	var state: UInt64
	mutating func next(_ bound: Int) -> Int {
		state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
		return Int((state >> 32) % UInt64(bound))
	}
}
