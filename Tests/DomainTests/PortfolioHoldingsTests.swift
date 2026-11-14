import Foundation
import Testing
@testable import Domain

@Suite("Positions of portfolios")
struct PortfolioHoldingsTests {
	let depot = Account(position: 0, name: "Depot", kind: .portfolio, source: .bank)
	let fonds = Account(position: 1, name: "Fondsdepot", kind: .portfolio, source: .bank)
	let giro = Account(position: 2, name: "Giro", kind: .giro, source: .bank)
	let now = Date(timeIntervalSince1970: 1_794_441_600)

	func position(_ name: String, in account: Account? = nil, isin: String? = nil, value: Int64 = 100_000, purchase: Decimal? = nil) -> Holding {
		Holding(accountID: (account ?? depot).id, security: Security(name: name, isin: isin), quantity: 10,
			marketValue: Money(minorUnits: value, currency: "EUR"), purchasePrice: purchase.map { Quote(amount: $0, currency: "EUR") })
	}

	func reconcile(_ result: RefreshResult, stored: [Holding]) -> Reconciliation {
		Domain.reconcile(.refresh(result), into: depot, stored: [], deleted: [], holdings: stored, rules: Categorizer(ledger: Ledger(accounts: [depot])), now: now)
	}

	@Test("A refresh replaces the positions: a sold one leaves, a changed one keeps its ID")
	func refreshReplaces() {
		let share = position("Musterwerke AG", isin: "DE0001234567")
		let fund = position("Beispiel Fonds", isin: "DE0009876543")
		var more = position("Musterwerke AG", isin: "DE0001234567", value: 112_500)
		more.quantity = 45
		let r = reconcile(RefreshResult(balance: Money(minorUnits: 112_500, currency: "EUR"), transactions: nil, isPortfolio: true, holdings: [more]),
			stored: [share, fund])
		#expect(r.holdings == Reconciliation.Holdings(accountID: depot.id, holdings: [Holding(id: share.id, accountID: depot.id,
			security: more.security, quantity: 45, marketValue: more.marketValue)]))
	}

	@Test("A refresh without positions, as from a source that sends none, keeps the stored ones")
	func noPositionsKeepsThem() {
		let r = reconcile(RefreshResult(balance: Money(minorUnits: 100_000, currency: "EUR"), transactions: nil, isPortfolio: true), stored: [position("Gold")])
		#expect(r.holdings == nil)
	}

	@Test("An empty delivery empties the portfolio")
	func emptyDelivery() {
		let r = reconcile(RefreshResult(balance: Money(minorUnits: 0, currency: "EUR"), transactions: nil, isPortfolio: true, holdings: []),
			stored: [position("Gold")])
		#expect(r.holdings == Reconciliation.Holdings(accountID: depot.id, holdings: []))
	}

	@Test("The ledger takes over the positions of a merge, and lists those of several portfolios by name without regard to case")
	func ledgerOrder() {
		var ledger = Ledger(accounts: [depot, fonds, giro], holdings: [position("Musterwerke AG"), position("Anleihe Musterland", in: fonds)])
		var r = Reconciliation()
		r.holdings = Reconciliation.Holdings(accountID: depot.id, holdings: [position("Musterwerke AG"), position("beispiel Fonds")])
		ledger.apply(r)
		#expect(ledger.holdings(of: [depot.id, fonds.id]).map(\.security.name) == ["Anleihe Musterland", "beispiel Fonds", "Musterwerke AG"])
		#expect(ledger.holdings(of: [fonds.id]).map(\.security.name) == ["Anleihe Musterland"])
		#expect(ledger.holdings(of: [giro.id]).isEmpty)
	}

	@Test("Removing an account drops its positions from the ledger, as the database does")
	func removeAccount() {
		var ledger = Ledger(accounts: [depot, fonds], holdings: [position("Gold"), position("Silber", in: fonds)])
		ledger.replace(accounts: [fonds])
		#expect(ledger.holdings(of: [depot.id]).isEmpty)
		#expect(ledger.holdings(of: [fonds.id]).map(\.security.name) == ["Silber"])
	}

	@Test("The total gain of a group counts the positions with a purchase price only")
	func totalGain() {
		let ledger = Ledger(accounts: [depot, fonds], holdings: [
			position("Musterwerke AG", value: 120_000, purchase: 100), position("Beispiel Fonds", in: fonds, value: 95_000, purchase: 100),
			position("Gold", value: 500_000),
		])
		#expect(ledger.totalGain(of: [depot.id, fonds.id]).amounts == [Money(minorUnits: 15_000, currency: "EUR")])
		#expect(ledger.totalGain(of: [giro.id]).isEmpty)
	}

	@Test("A selection shows positions only when it holds portfolios and nothing else")
	func portfolioSelection() {
		let invest = AccountGroup(name: "Investments", position: 0)
		let mixed = AccountGroup(name: "Savings", position: 1)
		var d = depot, f = fonds, g = giro
		d.groupID = invest.id
		f.groupID = invest.id
		g.groupID = mixed.id
		let ledger = Ledger(groups: [invest, mixed], accounts: [d, f, g])
		#expect(ledger.portfolioAccounts(in: .accountGroup(invest.id)) == [d.id, f.id])
		#expect(ledger.portfolioAccounts(in: .account(d.id)) == [d.id])
		#expect(ledger.portfolioAccounts(in: .account(g.id)) == nil)
		#expect(ledger.portfolioAccounts(in: .accountGroup(mixed.id)) == nil)
	}
}
