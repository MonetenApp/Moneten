import Domain
import Foundation
import Testing
@testable import Storage

extension MergeTests {
	@Test("Gate 3: persisted file identity survives bank fields booking deletion and re-import", arguments: [false, true], [false, true])
	func pendingFileIdentityStored(booked: Bool, reference: Bool) throws {
		let store = try makeStore()
		defer { try? FileManager.default.removeItem(at: folder.root) }
		let date = Day(year: 2026, month: 12, day: 1)
		let now = Day(year: 2026, month: 11, day: 20).date()
		let file = Transaction(accountID: giro.id, bookingDate: date, amountMinor: -80_000, name: "Vermieter A", purpose: "Miete Dezember",
			counterpartyIBAN: "DE02120300000000202051", endToEndReference: reference ? "RENT-A" : nil, isPending: true)
		_ = try store.merge(.file([file]), into: giro.id, now: now)
		let bank = Transaction(accountID: giro.id, bookingDate: date, amountMinor: -80_000, name: "Vermieter A", purpose: "BANK",
			counterpartyIBAN: "DE02120300000000202051", isPending: true)
		_ = try store.merge(refresh([bank]), into: giro.id, now: now)
		if booked {
			var booking = bank
			booking.isPending = false
			booking.purpose = "BOOKED BANK"
			_ = try store.merge(refresh([booking]), into: giro.id, now: now)
		}
		let rows = try store.loadLedger().transactions(ofAccount: giro.id)
		#expect(rows.map(\.id) == [file.id])
		#expect(rows.map(\.endToEndReference) == [reference ? "RENT-A" : nil])
		#expect(rows.map(\.isPending) == [!booked])
		let identity = "file:1:8:202612016:-800003:EUR13:mietedezember27:iban:DE021203000000002020510:" + (reference ? "6:RENT-A" : "0:")
		#expect(rows.map(\.fileIdentity) == [identity])
		let liveRepeat = try store.merge(.file([file]), into: giro.id, now: now)
		#expect(liveRepeat.skipped == 1 && liveRepeat.added == [])
		try store.deleteTransactions([file.id])
		#expect(try store.deletedTransactions().map(\.fileIdentity) == [identity])
		#expect(try store.deletedTransactions().map(\.endToEndReference) == [reference ? "RENT-A" : nil])
		let repeatResult = try store.merge(.file([file]), into: giro.id, now: now)
		#expect(repeatResult.skipped == 1)
		#expect(repeatResult.added == [])
		#expect(try store.loadLedger().transactions(ofAccount: giro.id) == [])
	}
}
