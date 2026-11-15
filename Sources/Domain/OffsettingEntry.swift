import Foundation

/// An offline account in the menu "Create Offsetting Entry". It is disabled when a selected row has another
/// currency: the entry keeps the currency of its source, and the balance of the account would not count it.
public struct OffsettingTarget: Hashable, Sendable {
	public let account: Account
	public let isEnabled: Bool
}

extension Ledger {
	/// The offline accounts that "Create Offsetting Entry" offers for `rows`, in sidebar order, without the
	/// accounts of the rows themselves.
	public func offsettingTargets(for rows: [Transaction]) -> [OffsettingTarget] {
		let own = Set(rows.map(\.accountID))
		let currencies = Set(rows.map(\.currency))
		return accountsInSidebarOrder.filter { $0.isOffline && !own.contains($0.id) }.map {
			OffsettingTarget(account: $0, isEnabled: currencies.allSatisfy { [currency = $0.currency] in $0 == currency })
		}
	}

	/// One manual transaction in `target` for each row, with the opposite amount in the currency of the row.
	/// It keeps the name, the purpose, and the comment, so that rules and the search find both rows, and takes
	/// the booking date of the row as its booking date and value date. The IBAN and BIC of the source account
	/// become the counterparty account, so the entry shows where the money came from. Nothing links the rows.
	///
	/// The copied category counts as chosen by hand, so no rule moves it. A row without a category, or with
	/// one whose restriction leaves out `target`, gives an entry that the rules sort.
	public func offsettingEntries(of rows: [Transaction], into target: Account, now: Date = Date()) -> [Transaction] {
		let rules = Categorizer(ledger: self)
		return rows.map { source in
			let from = account(source.accountID)
			let kept = source.categoryID.flatMap { id -> UUID? in
				guard let c = category(id), allowedAccounts(of: c)?.contains(target.id) ?? true else { return nil }
				return id
			}
			var entry = Transaction(accountID: target.id, bookingDate: source.bookingDate, valueDate: source.bookingDate, amountMinor: -source.amountMinor,
				currency: source.currency, name: source.name, purpose: source.purpose, counterpartyIBAN: from?.iban,
				counterpartyBIC: from?.iban == nil ? nil : from?.bic, comment: source.comment, categoryID: kept,
				categorizedBy: kept == nil ? .none : .manual, createdAt: now)
			rules.categorize(&entry)
			return entry
		}
	}
}
