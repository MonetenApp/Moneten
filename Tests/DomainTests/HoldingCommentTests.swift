import Foundation
import Testing
@testable import Domain

/// The comment of a position: it belongs to the position, as the user's asset class does, so it survives every refresh
/// and goes with the position when the position leaves the portfolio.
@Suite("Comments of positions")
struct HoldingCommentTests {
	let depot = Account(position: 0, name: "Depot", kind: .portfolio, source: .bank)
	let now = Date(timeIntervalSince1970: 1_794_441_600)

	func position(_ name: String, isin: String? = nil, quantity: Decimal = 40, quote: Decimal = 70, comment: String? = nil) -> Holding {
		Holding(accountID: depot.id, security: Security(name: name, isin: isin), quantity: quantity,
			quote: Quote(amount: quote, currency: "EUR", day: Day(year: 2026, month: 11, day: 27)), comment: comment)
	}

	func refresh(_ delivered: [Holding], stored: [Holding]) -> [Holding] {
		let r = Domain.reconcile(.refresh(RefreshResult(balance: Money(minorUnits: 300_000, currency: "EUR"), transactions: nil, isPortfolio: true,
			holdings: delivered)), into: depot, stored: [], deleted: [], holdings: stored, rules: Categorizer(ledger: Ledger(accounts: [depot])), now: now)
		return r.holdings?.holdings ?? []
	}

	@Test("A refresh keeps the comment of the stored position, with a new quote and with another quantity")
	func refreshKeepsTheComment() {
		let share = position("Musterwerke AG", isin: "DE0001234567", comment: "Nachkaufen unter 70 €.")
		let fund = position("Weltindex UCITS ETF", isin: "IE0000000003", comment: "Sparplan")
		let after = refresh([position("Musterwerke AG", isin: "DE0001234567", quote: 77), position("Weltindex UCITS ETF", isin: "IE0000000003", quantity: 45)],
			stored: [share, fund])
		#expect(after.map(\.id) == [share.id, fund.id])
		#expect(after.map(\.comment) == ["Nachkaufen unter 70 €.", "Sparplan"])
		#expect(after.map(\.quantity) == [40, 45])
	}

	@Test("A position matched by its name without an ISIN keeps its comment, and a new position has none")
	func matchedByName() {
		let bond = position("Anleihe Musterland", comment: "Fällig 2030")
		let after = refresh([position("Anleihe Musterland"), position("Beispiel Fonds", isin: "DE0009876543")], stored: [bond])
		#expect(after.map(\.comment) == ["Fällig 2030", nil])
	}

	@Test("No source sets a comment: a delivered comment is dropped, also when the stored position has none")
	func deliveredCommentIsDropped() {
		let stored = position("Musterwerke AG", isin: "DE0001234567")
		let delivered = [position("Musterwerke AG", isin: "DE0001234567", comment: "Von der Bank"), position("Beispiel Fonds", comment: "Von der Bank")]
		#expect(Holding.identify(delivered, stored: [stored]).map(\.comment) == [nil, nil])
	}

	@Test("A security that leaves the portfolio takes its comment with it, and when it comes back it has none")
	func soldAndBoughtAgain() {
		let share = position("Musterwerke AG", isin: "DE0001234567", comment: "Nachkaufen unter 70 €.")
		let fund = position("Beispiel Fonds", isin: "DE0009876543")
		let sold = refresh([fund], stored: [share, fund])
		#expect(sold.map(\.security.name) == ["Beispiel Fonds"])
		let back = refresh([position("Musterwerke AG", isin: "DE0001234567"), fund], stored: sold)
		#expect(back.map(\.comment) == [nil, nil])
		#expect(back.first?.id != share.id)
	}

	@Test("The ledger changes the comment of one position only, and nil removes it")
	func ledgerSetsTheComment() {
		let share = position("Musterwerke AG", comment: "Alt")
		let fund = position("Beispiel Fonds")
		var ledger = Ledger(accounts: [depot], holdings: [share, fund])
		ledger.setComment("Sparplan 500 € am 1.", of: fund.id)
		#expect(ledger.holdings(of: [depot.id]).map(\.comment) == ["Sparplan 500 € am 1.", "Alt"])
		#expect(ledger.holding(fund.id)?.comment == "Sparplan 500 € am 1.")
		ledger.setComment(nil, of: share.id)
		#expect(ledger.holdings(of: [depot.id]).map(\.comment) == ["Sparplan 500 € am 1.", nil])
	}
}
