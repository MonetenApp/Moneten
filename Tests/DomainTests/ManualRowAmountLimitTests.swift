import Foundation
import Testing
@testable import Domain

/// A derived initial balance that a manual row moves or sets must stay within `Money.maxMinorUnits`, as the first
/// refresh keeps it (issue #324). The app refuses such a change and stores nothing, instead of a clamped or wrapped value.
@Suite("Manual rows and the amount limit")
struct ManualRowAmountLimitTests {
	let limit = Money.maxMinorUnits
	let calendar = Calendar.current
	let rules = Categorizer(ledger: Ledger())

	func day(_ d: Int) -> Day { Day(year: 2026, month: 11, day: d) }

	/// A credit card whose first refresh derived the initial balance `initial` from the bank balance of 01.11.2026.
	func card(initial: Int64, balanceDay: Int = 1) -> Account {
		Account(position: 0, name: "Kreditkarte", kind: .creditCard, source: .bank, bankBalanceMinor: 0, bankBalanceDate: day(balanceDay).date(in: calendar),
			initialBalanceMinor: initial, initialBalanceIsSet: true, initialBalanceIsDerived: true)
	}

	func manual(_ account: Account, _ d: Int, _ minor: Int64, pending: Bool = false) -> Transaction {
		Transaction(accountID: account.id, bookingDate: day(d), amountMinor: minor, name: "Hotel Beispiel", purpose: "Kartenzahlung", isPending: pending, isManual: true)
	}

	func refresh(balanceDay: Int) -> Delivery {
		.refresh(RefreshResult(balance: Money(minorUnits: 0, currency: "EUR"), balanceDate: day(balanceDay).date(in: calendar),
			transactions: FetchedTransactions(rows: [], from: day(1))))
	}

	@Test("A refresh whose new day passes a manual row refuses a derived initial balance beyond the limit and keeps the old one")
	func refreshPastManualRowBeyondTheLimit() throws {
		let account = card(initial: 0)
		let older = Transaction(accountID: account.id, bookingDate: day(1), amountMinor: -limit, name: "Musterfirma GmbH", isFetched: true, sourceID: "TX-1")
		let planned = manual(account, 5, -limit)
		let r = reconcile(refresh(balanceDay: 10), into: account, stored: [older, planned], deleted: [], rules: rules, now: day(10).date(in: calendar))
		#expect(r.refusal == InitialBalanceTooLarge(accountName: "Kreditkarte"))
		#expect(r.account.map(\.initialBalanceMinor) ?? 0 == 0)
		// Within the limit the same refresh sets the value by the rule.
		let fits = manual(account, 5, -limit + 1)
		let accepted = reconcile(refresh(balanceDay: 10), into: account, stored: [fits], deleted: [], rules: rules, now: day(10).date(in: calendar))
		#expect(accepted.refusal == nil && accepted.account?.initialBalanceMinor == limit - 1)
	}

	@Test("A file that books a pending manual row refuses to move a derived initial balance beyond the limit")
	func fileMoveBeyondTheLimit() throws {
		let small = card(initial: 10_000, balanceDay: 10)
		let file = Transaction(accountID: small.id, bookingDate: day(5), amountMinor: -5_000, name: "HOTEL BEISPIEL", purpose: "Kartenzahlung", fileIdentity: "csv:1")
		let moved = reconcile(.file([file]), into: small, stored: [manual(small, 5, -5_000, pending: true)], deleted: [], rules: rules, now: day(12).date(in: calendar))
		#expect(moved.refusal == nil && moved.account?.initialBalanceMinor == 15_000)
		let full = card(initial: limit, balanceDay: 10)
		var big = file
		big.amountMinor = -limit
		let r = reconcile(.file([big]), into: full, stored: [manual(full, 5, -limit, pending: true)], deleted: [], rules: rules, now: day(12).date(in: calendar))
		#expect(r.refusal == InitialBalanceTooLarge(accountName: "Kreditkarte"))
		#expect(r.account.map(\.initialBalanceMinor) ?? limit == limit)
	}

	@Test("Saving or deleting a manual row refuses to move a derived initial balance beyond the limit")
	func editMoveBeyondTheLimit() throws {
		let account = card(initial: limit, balanceDay: 10)
		let planned = manual(account, 5, 100)
		let ledger = Ledger(accounts: [account], transactions: [planned])
		#expect(throws: InitialBalanceTooLarge(accountName: "Kreditkarte")) { try ledger.followingBankBalance(saving: [], deleting: [planned.id], calendar: calendar) }
		var smaller = planned
		smaller.amountMinor = 50
		#expect(throws: InitialBalanceTooLarge(accountName: "Kreditkarte")) { try ledger.followingBankBalance(saving: [smaller], calendar: calendar) }
		var larger = planned
		larger.amountMinor = 200
		#expect(try ledger.followingBankBalance(saving: [larger], calendar: calendar).map(\.initialBalanceMinor) == [limit - 100])
	}

	@Test("Calibrate enters the initial balance that meets the typed balance, and refuses one beyond the limit")
	func calibrationBeyondTheLimit() throws {
		let wallet = Account(position: 0, name: "Wallet", kind: .cash, source: .offline, initialBalanceMinor: 1_000)
		let rows = [Transaction(accountID: wallet.id, bookingDate: day(5), amountMinor: limit, name: "Musterfirma GmbH")]
		let ledger = Ledger(accounts: [wallet], transactions: rows)
		let calibrated = try ledger.calibrated(wallet, balanceToday: limit, today: day(10))
		#expect(calibrated.initialBalanceMinor == 0 && calibrated.initialBalanceIsSet && !calibrated.initialBalanceIsDerived)
		#expect(throws: InitialBalanceTooLarge(accountName: "Wallet")) { try ledger.calibrated(wallet, balanceToday: -limit, today: day(10)) }
	}
}
