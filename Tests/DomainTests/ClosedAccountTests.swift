@testable import Domain
import Foundation
import Testing

@Suite("Closed accounts")
struct ClosedAccountTests {
	let day = Day(year: 2026, month: 11, day: 17)
	let uncategorized = Domain.Category(position: 9, name: "Uncategorized", isDefault: true)
	let fees = Domain.Category(position: 0, name: "Fees")
	let wallet = Account(position: 0, name: "Wallet", kind: .cash, source: .offline)
	/// An account of a bank access whose first refresh derived the initial balance: the bank reported 500,00 € and 35,00 US$.
	let giro = Account(position: 1, name: "Giro", kind: .giro, source: .bank, iban: "DE02120300000000202051", bankBalanceMinor: 50_000,
		bankBalanceDate: Date(timeIntervalSince1970: 1_763_337_600), initialBalanceMinor: 20_000, initialBalanceIsSet: true, initialBalanceIsDerived: true,
		refreshInterval: .onceADay, otherBankBalances: [Money(minorUnits: 3_500, currency: "USD")], bonusPoints: 12_400)

	func row(_ account: Account, _ minor: Int64, on day: Day? = nil, currency: String = "EUR", pending: Bool = false, name: String = "Kartenzahlung") -> Transaction {
		Transaction(accountID: account.id, bookingDate: day ?? self.day.adding(days: -3), amountMinor: minor, currency: currency, name: name, isPending: pending)
	}

	func ledger(_ accounts: [Account], _ rows: [Transaction], groups: [AccountGroup] = [], parts: [SplitPart] = []) -> Ledger {
		Ledger(groups: groups, accounts: accounts, categories: [fees, uncategorized], transactions: rows, parts: parts)
	}

	/// What OK in the account settings does with the result of a close: the account first, then the entry.
	func applying(_ closing: (account: Account, entry: Transaction?), to l: Ledger) -> Ledger {
		var l = l
		l.upsert(closing.account)
		if let entry = closing.entry { l.update([entry]) }
		return l
	}

	func closed(_ account: Account) -> Account {
		var a = account
		a.isClosed = true
		return a
	}

	func reopened(_ account: Account) -> Account {
		var a = account
		a.isClosed = false
		return a
	}

	// MARK: Clearing entry

	@Test("A balance of 12,34 € gives a booked clearing entry of -12,34 € on that day, without category and counterparty, new and not checked")
	func balanceLeft() throws {
		let l = ledger([wallet], [row(wallet, 1_234)])
		let result = try l.closing(closed(wallet), today: day)
		let entry = try #require(result.entry)
		#expect(entry.accountID == wallet.id)
		#expect(entry.amount == Money(minorUnits: -1_234, currency: "EUR"))
		#expect(entry.bookingDate == day && entry.valueDate == day)
		#expect(entry.name == "Clearing entry")
		#expect(entry.purpose.contains("closed"))
		#expect(entry.categoryID == nil && entry.categorizedBy == .none)
		#expect(entry.counterpartyIBAN == nil && entry.counterpartyBIC == nil && entry.comment == nil)
		#expect(entry.isNew && !entry.isChecked && !entry.isPending)
		// The user edits it like a transaction that they added.
		#expect(entry.isManual && entry.isOnlyManual)
		#expect(result.account.isClosed)
		#expect(result.account.clearingEntry == ClearingEntryMark(entry))
		let after = applying(result, to: l)
		#expect(after.balance(of: result.account) == Money(minorUnits: 0, currency: "EUR"))
	}

	@Test("A balance of zero gives no clearing entry and no mark")
	func balanceZero() throws {
		let l = ledger([wallet], [row(wallet, 1_234), row(wallet, -1_234)])
		let result = try l.closing(closed(wallet), today: day)
		#expect(result.entry == nil)
		#expect(result.account.isClosed && result.account.clearingEntry == nil)
	}

	@Test("A negative balance gives a positive clearing entry")
	func negativeBalance() throws {
		let l = ledger([wallet], [row(wallet, -4_000)])
		#expect(try l.closing(closed(wallet), today: day).entry?.amountMinor == 4_000)
	}

	@Test("An account without transactions but with an initial balance of 100,00 € gets a clearing entry of -100,00 €")
	func initialBalanceOnly() throws {
		var empty = wallet
		empty.initialBalanceMinor = 10_000
		let l = ledger([empty], [])
		#expect(try l.closing(closed(empty), today: day).entry?.amountMinor == -10_000)
	}

	@Test("An account of a bank access clears its computed balance of 480,00 €, not the bank balance of 500,00 €, and then shows 0,00 € alone")
	func bankAccount() throws {
		let l = ledger([giro], [row(giro, 30_000), row(giro, -2_000)])
		let result = try l.closing(closed(giro), today: day)
		#expect(result.entry?.amount == Money(minorUnits: -48_000, currency: "EUR"))
		let after = applying(result, to: l)
		let account = try #require(after.account(giro.id))
		// A closed account shows its computed balance, without the other currencies of the bank.
		#expect(after.balances(of: account) == [Money(minorUnits: 0, currency: "EUR")])
		#expect(account.reportedBalance == nil)
		// The stored values of the bank stay for a reopen.
		#expect(account.bankBalanceMinor == 50_000 && account.otherBankBalances == giro.otherBankBalances)
		#expect(account.initialBalanceMinor == giro.initialBalanceMinor)
	}

	@Test("A transaction after that day stays in the balance: 250,00 € is cleared and 80,00 € is left")
	func rowAfterToday() throws {
		let tomorrow = row(wallet, 8_000, on: day.adding(days: 1))
		let l = ledger([wallet], [row(wallet, 25_000), tomorrow])
		let result = try l.closing(closed(wallet), today: day)
		#expect(result.entry?.amountMinor == -25_000)
		let after = applying(result, to: l)
		#expect(after.transaction(tomorrow.id) == tomorrow)
		#expect(after.balance(of: result.account) == Money(minorUnits: 8_000, currency: "EUR"))
		#expect(after.computedBalance(of: result.account, through: day) == Money(minorUnits: 0, currency: "EUR"))
	}

	@Test("A pending transaction counts in the balance that is cleared and stays pending")
	func pendingRow() throws {
		let pending = row(wallet, -2_000, on: day.adding(days: -1), pending: true)
		let l = ledger([wallet], [row(wallet, 12_000), pending])
		let result = try l.closing(closed(wallet), today: day)
		#expect(result.entry?.amountMinor == -10_000)
		let after = applying(result, to: l)
		#expect(after.transaction(pending.id)?.isPending == true)
		#expect(after.balance(of: result.account) == Money(minorUnits: 0, currency: "EUR"))
	}

	@Test("Rows in another currency give no clearing entry of their own")
	func otherCurrency() throws {
		let l = ledger([giro], [row(giro, 10_000), row(giro, 3_500, currency: "USD")])
		let result = try l.closing(closed(giro), today: day)
		#expect(result.entry?.amount == Money(minorUnits: -30_000, currency: "EUR"))
		#expect(applying(result, to: l).balances(of: result.account) == [Money(minorUnits: 0, currency: "EUR")])
	}

	@Test("A portfolio gets no clearing entry and keeps its value")
	func portfolio() throws {
		let depot = Account(position: 2, name: "Depot", kind: .portfolio, source: .bank, bankBalanceMinor: 100_000)
		let l = ledger([depot], [])
		let result = try l.closing(closed(depot), today: day)
		#expect(result.entry == nil)
		#expect(applying(result, to: l).balance(of: result.account) == Money(minorUnits: 100_000, currency: "EUR"))
	}

	@Test("Closing clears the error of the last refresh, because no refresh of a closed account clears it")
	func refreshError() throws {
		var failed = giro
		failed.refreshError = RefreshError(message: "The bank is not available.", date: Date(timeIntervalSince1970: 1_763_337_600))
		let result = try ledger([failed], []).closing(closed(failed), today: day)
		#expect(result.account.refreshError == nil)
	}

	@Test("A balance whose opposite does not fit the limit of an amount refuses the close")
	func tooLarge() throws {
		var huge = wallet
		huge.initialBalanceMinor = Money.maxMinorUnits
		let l = ledger([huge], [row(huge, Money.maxMinorUnits)])
		#expect(throws: ClearingEntryTooLarge(accountName: "Wallet")) { try l.closing(closed(huge), today: day) }
	}

	@Test("The initial balance typed in the same OK counts in the clearing entry")
	func editedInitialBalance() throws {
		let l = ledger([wallet], [row(wallet, 1_000)])
		var edited = closed(wallet)
		edited.enterInitialBalance(500)
		#expect(try l.closing(edited, today: day).entry?.amountMinor == -1_500)
	}

	// MARK: Balance while closed

	@Test("Neither the clearing entry nor an edit of it in a closed account moves a derived initial balance")
	func noFollowWhileClosed() throws {
		let l = ledger([giro], [row(giro, 28_000)])
		let result = try l.closing(closed(giro), today: day)
		let entry = try #require(result.entry)
		var after = applying(result, to: l)
		#expect(try after.followingBankBalance(saving: [entry]).isEmpty)
		var edited = entry
		edited.edit(OriginalValues(bookingDate: day, valueDate: day, amountMinor: -40_000, name: entry.name, purpose: entry.purpose))
		#expect(try after.followingBankBalance(saving: [edited]).isEmpty)
		after.update([edited])
		#expect(after.balance(of: result.account) == Money(minorUnits: 8_000, currency: "EUR"))
	}

	@Test("The sum of a group leaves the closed account out, before and after its clearing entry")
	func groupSum() throws {
		let privat = AccountGroup(name: "Private", position: 0)
		var current = wallet
		current.groupID = privat.id
		var savings = Account(position: 2, name: "Old Savings", kind: .savings, source: .offline)
		savings.groupID = privat.id
		let l = ledger([current, savings], [row(current, 30_000), row(savings, 5_000)], groups: [privat])
		#expect(l.sum(ofGroup: privat.id).amounts == [Money(minorUnits: 35_000, currency: "EUR")])
		var marked = l
		marked.upsert(closed(savings))
		#expect(marked.sum(ofGroup: privat.id).amounts == [Money(minorUnits: 30_000, currency: "EUR")])
		let after = applying(try l.closing(closed(savings), today: day), to: l)
		#expect(after.sum(ofGroup: privat.id).amounts == [Money(minorUnits: 30_000, currency: "EUR")])
	}

	@Test("The bar chart of the closed account ends at 0,00 € on the day of the clearing entry")
	func barChart() throws {
		let today = Day.today()
		let l = ledger([wallet], [row(wallet, 1_234, on: today.adding(days: -2))])
		let after = applying(try l.closing(closed(wallet), today: today), to: l)
		let bars = after.balanceBars(accountIDs: [wallet.id])
		#expect(bars.map(\.minorUnits) == [1_234, 1_234, 0])
		#expect(bars.last?.start == today)
	}

	// MARK: Reopen

	@Test("Reopening removes the unchanged clearing entry, and the balance is 12,34 € again")
	func reopenUnchanged() throws {
		let l = ledger([wallet], [row(wallet, 1_234)])
		let closing = try l.closing(closed(wallet), today: day)
		let after = applying(closing, to: l)
		let result = try after.reopening(reopened(closing.account))
		#expect(result.removedEntry == closing.entry?.id)
		#expect(!result.account.isClosed && result.account.clearingEntry == nil)
		var back = after
		back.upsert(result.account)
		back.remove(transactionIDs: [try #require(result.removedEntry)])
		#expect(back.balance(of: result.account) == Money(minorUnits: 1_234, currency: "EUR"))
	}

	@Test("A checkmark, the read mark, and a category from a rule leave the clearing entry unchanged")
	func reopenReviewed() throws {
		let l = ledger([wallet], [row(wallet, 1_234)])
		let closing = try l.closing(closed(wallet), today: day)
		var reviewed = try #require(closing.entry)
		reviewed.isChecked = true
		reviewed.isNew = false
		reviewed.categoryID = fees.id
		reviewed.categorizedBy = .rule
		var after = applying(closing, to: l)
		after.update([reviewed])
		#expect(try after.reopening(reopened(closing.account)).removedEntry == reviewed.id)
	}

	@Test("A clearing entry that the user changed stays, and the mark is gone", arguments: ["date", "value date", "amount", "name", "purpose", "comment", "category", "split"])
	func reopenEdited(change: String) throws {
		let l = ledger([wallet], [row(wallet, 1_234)])
		let closing = try l.closing(closed(wallet), today: day)
		let entry = try #require(closing.entry)
		var edited = entry
		var values = OriginalValues(entry)
		var parts: [SplitPart] = []
		switch change {
		case "date": values.bookingDate = day.adding(days: -1)
		case "value date": values.valueDate = day.adding(days: 1)
		case "amount": values.amountMinor = -1_000
		case "name": values.name = "Restguthaben"
		case "purpose": values.purpose = "Konto aufgelöst"
		case "comment": edited.comment = "Bar ausgezahlt"
		case "category": edited.categoryID = fees.id; edited.categorizedBy = .manual
		default: parts = [SplitPart(transactionID: entry.id, position: 0, amountMinor: -1_000), SplitPart(transactionID: entry.id, position: 1, amountMinor: -234)]
		}
		edited.edit(values)
		var after = applying(closing, to: l)
		after.update([edited])
		if !parts.isEmpty { after.replaceParts(of: entry.id, with: parts) }
		let result = try after.reopening(reopened(closing.account))
		#expect(result.removedEntry == nil)
		#expect(!result.account.isClosed && result.account.clearingEntry == nil)
	}

	@Test("A clearing entry that the user deleted leaves nothing to remove")
	func reopenDeleted() throws {
		let l = ledger([wallet], [row(wallet, 1_234)])
		let closing = try l.closing(closed(wallet), today: day)
		var after = applying(closing, to: l)
		after.remove(transactionIDs: [try #require(closing.entry?.id)])
		#expect(try after.reopening(reopened(closing.account)).removedEntry == nil)
	}

	@Test("Reopening an account of a bank access shows 500,00 € and 35,00 US$ again and keeps the initial balance")
	func reopenBankAccount() throws {
		let l = ledger([giro], [row(giro, 28_000)])
		let closing = try l.closing(closed(giro), today: day)
		let after = applying(closing, to: l)
		let result = try after.reopening(reopened(closing.account))
		var back = after
		back.upsert(result.account)
		back.remove(transactionIDs: [try #require(result.removedEntry)])
		let account = try #require(back.account(giro.id))
		#expect(back.balances(of: account) == [Money(minorUnits: 50_000, currency: "EUR"), Money(minorUnits: 3_500, currency: "USD")])
		#expect(account.initialBalanceMinor == giro.initialBalanceMinor && account.followsBankBalance)
		#expect(back.computedBalance(of: account) == l.computedBalance(of: giro))
	}

	@Test("After an edited entry stays, a second close clears only the balance that is left")
	func closeAgain() throws {
		let l = ledger([wallet], [row(wallet, 1_234)])
		let first = try l.closing(closed(wallet), today: day)
		var edited = try #require(first.entry)
		edited.edit(OriginalValues(bookingDate: day, valueDate: day, amountMinor: -1_000, name: edited.name, purpose: edited.purpose))
		var after = applying(first, to: l)
		after.update([edited])
		let reopening = try after.reopening(reopened(first.account))
		after.upsert(reopening.account)
		let second = try after.closing(closed(reopening.account), today: day.adding(days: 1))
		#expect(second.entry?.amountMinor == -234)
		#expect(second.entry?.bookingDate == day.adding(days: 1))
	}

	// MARK: Refreshes of a closed account

	@Test("A refresh that arrives after the close changes nothing: a vanished pending row, a new booking, and a changed amount stay out")
	func lateRefresh() throws {
		var pending = row(giro, 2_000, on: day.adding(days: -1), pending: true)
		pending.isFetched = true
		var booked = row(giro, -500, on: day.adding(days: -2))
		booked.isFetched = true
		booked.sourceID = "bank:1"
		let l = ledger([giro], [pending, booked])
		let closing = try l.closing(closed(giro), today: day)
		let after = applying(closing, to: l)
		let account = try #require(after.account(giro.id))
		var changed = booked
		changed.id = UUID()
		changed.amountMinor = -600
		let fresh = row(giro, -300, on: day, name: "Neue Buchung")
		let delivery = Delivery.refresh(RefreshResult(balance: Money(minorUnits: 47_000, currency: "EUR"), balanceDate: Date(),
			transactions: FetchedTransactions(rows: [changed, fresh], from: day.adding(days: -10))))
		let r = reconcile(delivery, into: account, stored: after.transactions, deleted: [], rules: Categorizer(ledger: after), now: Date())
		#expect(r.added.isEmpty && r.dropped.isEmpty && r.updated.isEmpty && r.booked.isEmpty && r.marked.isEmpty)
		#expect(r.account == nil && r.refusal == nil)
	}

	@Test("A file still merges into a closed account, because only a refresh leaves it out")
	func fileIntoClosedAccount() throws {
		let closing = try ledger([wallet], [row(wallet, 1_234)]).closing(closed(wallet), today: day)
		let r = reconcile(.file([row(wallet, 700, on: day.adding(days: -5), name: "Bareinzahlung")]), into: closing.account, stored: [], deleted: [],
			rules: Categorizer(ledger: ledger([closing.account], [])), now: Date())
		#expect(r.added.count == 1)
	}

	@Test("The end of a refresh that ran during the close records neither its time nor its error")
	func lateStatus() {
		var account = closed(giro)
		account.record(.refreshed(Date(timeIntervalSince1970: 1_763_400_000)))
		account.record(.failed(RefreshError(message: "The bank is not available.", date: Date(timeIntervalSince1970: 1_763_400_000))))
		#expect(account.refreshedAt == nil && account.refreshError == nil)
	}

	// MARK: Marks that do not fit

	@Test("Reopening never removes a row of another account, even with the values of the entry")
	func foreignRow() throws {
		let l = ledger([wallet], [row(wallet, 1_234)])
		let closing = try l.closing(closed(wallet), today: day)
		var foreign = try #require(closing.entry)
		foreign.accountID = giro.id
		let other = ledger([closing.account, giro], [row(wallet, 1_234), foreign])
		#expect(try other.reopening(reopened(closing.account)).removedEntry == nil)
	}

	@Test("Reopening keeps an entry that a file matched, because it is a row of that file now")
	func matchedByFile() throws {
		let l = ledger([wallet], [row(wallet, 1_234)])
		let closing = try l.closing(closed(wallet), today: day)
		var matched = try #require(closing.entry)
		matched.fileIdentity = "file:1"
		var after = applying(closing, to: l)
		after.update([matched])
		#expect(try after.reopening(reopened(closing.account)).removedEntry == nil)
	}

	// MARK: A kept entry and the bank balance

	@Test("A kept entry of a bank account moves the derived initial balance at the reopen, so the balance meets the bank again")
	func keptEntryMeetsBank() throws {
		let bankDay = Day(giro.bankBalanceDate!)
		// The derived initial balance of 200,00 € and 300,00 € of rows meet the bank balance of 500,00 €.
		let l = ledger([giro], [row(giro, 30_000, on: bankDay.adding(days: -3))])
		let closing = try l.closing(closed(giro), today: bankDay)
		var edited = try #require(closing.entry)
		edited.edit(OriginalValues(bookingDate: edited.bookingDate, valueDate: edited.valueDate, amountMinor: edited.amountMinor, name: edited.name, purpose: "Konto aufgelöst"))
		var after = applying(closing, to: l)
		after.update([edited])
		let result = try after.reopening(reopened(closing.account))
		#expect(result.removedEntry == nil)
		var back = after
		back.upsert(result.account)
		let account = try #require(back.account(giro.id))
		#expect(account.initialBalanceMinor == 70_000 && account.followsBankBalance)
		#expect(back.computedBalance(of: account) == Money(minorUnits: 50_000, currency: "EUR"))
		#expect(back.proposedCalibration(of: account, today: bankDay, refresh: .idle) == nil)
		// Deleting the entry later moves the initial balance back.
		#expect(try back.followingBankBalance(saving: [], deleting: [edited.id]).first?.initialBalanceMinor == giro.initialBalanceMinor)
	}

	@Test("While an account is closed, only its clearing entry stays out of the derived initial balance, and another manual row moves it as before")
	func otherManualRowWhileClosed() throws {
		let bankDay = Day(giro.bankBalanceDate!)
		let l = ledger([giro], [row(giro, 30_000, on: bankDay.adding(days: -3))])
		let after = applying(try l.closing(closed(giro), today: bankDay), to: l)
		var cash = row(giro, -1_000, on: bankDay.adding(days: -1), name: "Barabhebung")
		cash.isManual = true
		#expect(try after.followingBankBalance(saving: [cash]).first?.initialBalanceMinor == giro.initialBalanceMinor + 1_000)
	}
}

