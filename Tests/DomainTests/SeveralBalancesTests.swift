import Domain
import Foundation
import Testing

/// An account whose source reports balances in several currencies and bonus points.
@Suite("Several balances and bonus points")
struct SeveralBalancesTests {
	let group = AccountGroup(name: "Cards", position: 0)
	let now = Date(timeIntervalSince1970: 1_794_476_460)

	func eur(_ minor: Int64) -> Money { Money(minorUnits: minor, currency: "EUR") }
	func usd(_ minor: Int64) -> Money { Money(minorUnits: minor, currency: "USD") }

	func wallet() -> Account {
		Account(groupID: group.id, position: 0, name: "Wallet", kind: .other, source: .bank, accessID: UUID(), remoteID: "W-1 EUR")
	}

	func merge(_ result: RefreshResult, into account: Account) -> Account? {
		reconcile(.refresh(result), into: account, stored: [], deleted: [], rules: Categorizer(ledger: Ledger(accounts: [account])), now: now).account
	}

	@Test("A refresh stores the balances in other currencies and the bonus points beside the balance")
	func refreshStoresThem() throws {
		let merged = try #require(merge(RefreshResult(balance: eur(12_000), transactions: FetchedTransactions(rows: [], from: nil),
			otherBalances: [usd(3_500)], bonusPoints: 12_400), into: wallet()))
		#expect(merged.bankBalanceMinor == 12_000)
		#expect(merged.otherBankBalances == [usd(3_500)])
		#expect(merged.bonusPoints == 12_400)
		#expect(merged.reportedBalances == [eur(12_000), usd(3_500)])
	}

	/// Every connector hands its balances through `RefreshResult`, so a repeated currency adds up into one entry, a part in
	/// the currency of the balance goes to the balance, and a zero is left out. A refresh never stores a duplicate.
	@Test("A refresh adds up repeated currencies and moves the part in the account currency to the balance")
	func refreshCombinesCurrencies() throws {
		let result = RefreshResult(balance: eur(10_000), transactions: nil,
			otherBalances: [usd(1_000), eur(500), usd(250), Money(minorUnits: 0, currency: "GBP"), Money(minorUnits: 700, currency: "CHF"), usd(-1_250)])
		#expect(result.balance == eur(10_500))
		#expect(result.otherBalances == [Money(minorUnits: 700, currency: "CHF")])
		let merged = try #require(merge(result, into: wallet()))
		#expect(merged.bankBalanceMinor == 10_500)
		#expect(merged.otherBankBalances == [Money(minorUnits: 700, currency: "CHF")])
	}

	@Test("The next refresh replaces the balances and the bonus points, so what it no longer reports disappears")
	func nextRefreshReplacesThem() throws {
		var account = wallet()
		account.bankBalanceMinor = 12_000
		account.otherBankBalances = [usd(3_500)]
		account.bonusPoints = 12_400
		let merged = try #require(merge(RefreshResult(balance: eur(8_000), transactions: FetchedTransactions(rows: [], from: nil)), into: account))
		#expect(merged.reportedBalances == [eur(8_000)])
		#expect(merged.bonusPoints == nil)
	}

	@Test("A refresh without a balance keeps the stored balances and bonus points")
	func refreshWithoutBalanceKeepsThem() {
		var account = wallet()
		account.bankBalanceMinor = 12_000
		account.otherBankBalances = [usd(3_500)]
		account.bonusPoints = 12_400
		#expect(merge(RefreshResult(balance: nil, transactions: FetchedTransactions(rows: [], from: nil), bonusPoints: 7), into: account) == nil)
	}

	@Test("A portfolio shows only its value")
	func portfolioShowsOnlyItsValue() throws {
		let depot = Account(position: 1, name: "Depot", kind: .portfolio, source: .bank, accessID: UUID())
		let merged = try #require(merge(RefreshResult(balance: eur(2_451_837), transactions: nil, isPortfolio: true, otherBalances: [usd(100)],
			bonusPoints: 5), into: depot))
		#expect(merged.otherBankBalances.isEmpty)
		#expect(merged.bonusPoints == nil)
	}

	@Test("The sidebar, the header, and the sum of the group show every balance, the account currency first")
	func ledgerShowsEveryBalance() {
		var card = wallet()
		card.bankBalanceMinor = 12_000
		card.otherBankBalances = [usd(3_500)]
		let giro = Account(groupID: group.id, position: 1, name: "Giro", kind: .giro, source: .offline, initialBalanceMinor: 1_000)
		let ledger = Ledger(groups: [group], accounts: [card, giro])
		#expect(ledger.balances(of: card) == [eur(12_000), usd(3_500)])
		#expect(ledger.balances(of: giro) == [eur(1_000)])
		#expect(ledger.sum(ofGroup: group.id).amounts == [eur(13_000), usd(3_500)])
	}

	@Test("An account that computes its balance shows no stored balance in another currency")
	func computedBalanceHasNoOtherBalances() {
		var account = wallet()
		account.source = .offline
		account.accessID = nil
		account.otherBankBalances = [usd(3_500)]
		account.bankBalanceMinor = 12_000
		#expect(Ledger(accounts: [account]).balances(of: account) == [eur(0)])
	}
}
