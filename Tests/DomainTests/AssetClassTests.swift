import Foundation
import Testing
@testable import Domain

@Suite("Asset classes of positions")
struct AssetClassTests {
	let depot = Account(position: 0, name: "Depot", kind: .portfolio, source: .bank)
	let now = Date(timeIntervalSince1970: 1_794_441_600)

	func position(_ name: String, isin: String? = nil, source: AssetClass? = nil, user: AssetClass? = nil) -> Holding {
		Holding(accountID: depot.id, security: Security(name: name, isin: isin), quantity: 10, marketValue: Money(minorUnits: 100_000, currency: "EUR"),
			sourceAssetClass: source, userAssetClass: user)
	}

	@Test("The user's class wins over the class of the source, and a position without either is Others, whatever its name")
	func effectiveClass() {
		#expect(position("Musterwerke AG", source: .stocks).assetClass == .stocks)
		#expect(position("Beispiel Fonds", source: .funds, user: .etfs).assetClass == .etfs)
		#expect(position("Musterwerke AG", user: .stocks).assetClass == .stocks)
		#expect(position("Musterwelt ETF").assetClass == .others)
		#expect(position("Bitcoin").assetClass == .others)
	}

	@Test("The eight classes keep their stored names and their order")
	func storedNames() {
		#expect(AssetClass.allCases.map(\.rawValue) == ["stocks", "funds", "bonds", "realEstate", "commodities", "etfs", "cryptocurrencies", "others"])
	}

	@Test("A refresh takes the class of the source from the delivery and keeps the user's choice of the stored position")
	func refreshKeepsTheChoice() {
		let fund = position("Beispiel Fonds", isin: "DE0009876543", user: .etfs)
		let share = position("Musterwerke AG", isin: "DE0001234567", source: .stocks)
		let deliveredFund = position("Beispiel Fonds", isin: "DE0009876543", source: .funds)
		let deliveredShare = position("Musterwerke AG", isin: "DE0001234567")
		let newcomer = position("Anleihe Musterland", isin: "DE0000000004", source: .bonds)
		let r = Domain.reconcile(.refresh(RefreshResult(balance: Money(minorUnits: 300_000, currency: "EUR"), transactions: nil, isPortfolio: true,
			holdings: [deliveredFund, deliveredShare, newcomer])), into: depot, stored: [], deleted: [], holdings: [fund, share],
			rules: Categorizer(ledger: Ledger(accounts: [depot])), now: now)
		let classes = r.holdings?.holdings.map { [$0.sourceAssetClass, $0.userAssetClass, $0.assetClass] }
		// The fund keeps the user's ETFs over the Funds of the bank, the share loses the Stocks that the bank no longer sends,
		// and a new position has no choice of the user.
		#expect(classes == [[.funds, .etfs, .etfs], [nil, nil, .others], [.bonds, nil, .bonds]])
	}

	@Test("A choice of the user changes the chosen positions only, and nil goes back to the class of the source")
	func choose() {
		let fund = position("Beispiel Fonds", source: .funds)
		let share = position("Musterwerke AG")
		let bond = position("Anleihe Musterland", source: .bonds)
		var ledger = Ledger(accounts: [depot], holdings: [fund, share, bond])
		ledger.setUserAssetClass(.etfs, of: [fund.id, share.id])
		#expect(ledger.holdings(of: [depot.id]).map(\.assetClass) == [.bonds, .etfs, .etfs])
		ledger.setUserAssetClass(nil, of: [fund.id])
		#expect(ledger.holdings(of: [depot.id]).map(\.assetClass) == [.bonds, .funds, .etfs])
		#expect(ledger.holdings(of: [depot.id]).map(\.sourceAssetClass) == [.bonds, .funds, nil])
	}
}
