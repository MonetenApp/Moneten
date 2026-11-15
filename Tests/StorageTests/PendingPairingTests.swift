import Domain
import Foundation
import Testing
@testable import Storage

extension MergeTests {
	@Test("Gate 3: persisted file identity survives bank fields booking deletion and re-import", arguments: [false, true])
	func pendingFileIdentityStored(booked: Bool) throws {
		let store = try makeStore()
		defer { try? FileManager.default.removeItem(at: folder.root) }
		let date = Day(year: 2026, month: 12, day: 1)
		let now = Day(year: 2026, month: 11, day: 20).date()
		let file = Transaction(accountID: giro.id, bookingDate: date, amountMinor: -80_000, name: "Vermieter A", purpose: "Miete Dezember",
			counterpartyIBAN: "DE02120300000000202051", endToEndReference: "RENT-A", isPending: true)
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
		#expect(rows.map(\.endToEndReference) == ["RENT-A"])
		#expect(rows.map(\.isPending) == [!booked])
		try store.deleteTransactions([file.id])
		#expect(try store.deletedTransactions().map(\.endToEndReference) == ["RENT-A"])
		let repeatResult = try store.merge(.file([file]), into: giro.id, now: now)
		#expect(repeatResult.skipped == 1)
		#expect(repeatResult.added == [])
		#expect(try store.loadLedger().transactions(ofAccount: giro.id) == [])
	}
}
