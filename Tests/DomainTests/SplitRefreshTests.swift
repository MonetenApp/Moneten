import Foundation
import Testing
@testable import Domain

extension ReconcileTests {
	@Test("A refresh keeps a split while its amount stays, and undoes it when the amount changes")
	func splitRefresh() {
		let groceries = Category(position: 0, name: "Groceries")
		let drinks = Category(position: 1, name: "Drinks", rule: "DANKE")
		var original = stored(row(3, -8000, "REWE Markt GmbH", "Receipt", sourceID: "TX-1"))
		original.categoryID = groceries.id
		original.categorizedBy = .rule
		let rules = Categorizer(ledger: Ledger(accounts: [giro], categories: [groceries, drinks]))
		func run(_ delivered: Transaction, _ live: Transaction) -> Reconciliation {
			reconcile(refresh([delivered]), into: giro, stored: [live], deleted: [], split: [live.id], rules: rules, now: now)
		}
		let changed = row(3, -8000, "REWE Markt GmbH", "REWE SAGT DANKE", sourceID: "TX-1")
		let kept = run(changed, original)
		#expect(kept.added.isEmpty)
		#expect(kept.skipped == 1)
		#expect(kept.unsplit.isEmpty)
		#expect(kept.updated.map(\.purpose) == ["REWE SAGT DANKE"])
		#expect(kept.updated.map(\.amountMinor) == [-8000])
		#expect(kept.updated.map(\.categoryID) == [groceries.id])
		original.categorizedBy = .manual
		let undone = run(row(3, -8500, "REWE Markt GmbH", sourceID: "TX-1"), original)
		#expect(undone.added.isEmpty)
		#expect(undone.unsplit == [original.id])
		#expect(undone.updated.map(\.amountMinor) == [-8500])
		#expect(undone.updated.map(\.categoryID) == [groceries.id])
		#expect(undone.updated.map(\.review) == [.splitUndone])
		original.sourceID = nil
		let linked = run(row(3, -8000, "REWE Markt GmbH", "Receipt", sourceID: "TX-1"), original)
		var expected = original; expected.sourceID = "TX-1"
		#expect(linked.updated == [expected])
		#expect(linked.unsplit.isEmpty)
	}

	@Test("A pending delivery leaves a split booked", arguments: [-8000, -8500])
	func pendingSplit(amount: Int64) {
		let original = stored(row(3, -8000, "REWE Markt GmbH", "Receipt", sourceID: "TX-1"))
		let delivered = row(3, amount, "REWE Markt GmbH", "Changed", pending: true, sourceID: "TX-1")
		let r = reconcile(refresh([delivered]), into: giro, stored: [original], deleted: [], split: [original.id],
			rules: Categorizer(ledger: Ledger()), now: now)
		#expect(r.updated.isEmpty)
		#expect(r.unsplit.isEmpty)
		#expect(r.added.isEmpty)
		#expect(history([original], after: r) == [original])
	}

	@Test("A pending currency correction leaves a split booked")
	func pendingSplitCurrency() {
		let original = stored(row(3, -8000, "REWE Markt GmbH", "Receipt", sourceID: "TX-1"))
		var delivered = row(3, -8000, "REWE Markt GmbH", pending: true, sourceID: "TX-1")
		delivered.currency = "USD"
		let r = reconcile(refresh([delivered]), into: giro, stored: [original], deleted: [], split: [original.id],
			rules: Categorizer(ledger: Ledger()), now: now)
		#expect(r.updated.isEmpty)
		#expect(r.unsplit.isEmpty)
		#expect(history([original], after: r) == [original])
	}

	@Test("Checking an undone split clears its review", arguments: [false, true])
	func checkUndoneSplit(checked: Bool) {
		var t = row(3, -8500, "REWE Markt GmbH")
		t.review = .splitUndone
		t.isChecked = checked
		#expect(t.changesWhenChecked)
		t.markChecked()
		#expect(t.isChecked)
		#expect(t.review == nil)
	}
}

extension SplitLedgerTests {
	@Test("Rows follow a merge that undoes a split")
	func mergeUnsplit() {
		var t = original()
		var l = ledger([t])
		let ps = parts(t)
		l.replaceParts(of: t.id, with: ps)
		t.amountMinor = -8500
		t.review = .splitUndone
		var r = Reconciliation()
		r.updated = [t]
		r.unsplit = [t.id]
		l.apply(r)
		#expect(l.rows(in: .account(account.id)).rows == [t])
		#expect(l.parts(of: t.id).isEmpty)
		#expect(ps.allSatisfy { l.row($0.id) == nil && l.part($0.id) == nil })
		var f = TransactionFilter(); f.searchText = "-25,00"
		#expect(l.rows(in: .account(account.id), filter: f).rows == ledger([t]).rows(in: .account(account.id), filter: f).rows)
	}

	@Test("Clearing review through a part is independent of row order")
	func clearPartReview() {
		var t = original(); t.review = .unclearBooking
		var l = ledger([t]); l.replaceParts(of: t.id, with: parts(t))
		let rows = l.rows(in: .account(account.id)).rows
		var cleared = rows[0]; cleared.review = nil
		for edits in [[cleared, rows[1]], [rows[1], cleared]] {
			let changes = l.changes(from: edits)
			#expect(changes.transactions.map(\.id) == [t.id])
			#expect(changes.transactions.map(\.review) == [nil])
			#expect(changes.parts.isEmpty)
		}
	}
}
