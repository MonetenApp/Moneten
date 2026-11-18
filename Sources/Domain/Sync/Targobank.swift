/// A pending card debit that Targobank sends without its party (#242). The bank sends it in MT940 as a positive amount
/// with no name, no purpose, and no booking text, and names the shop only with the booking. The FinTS connector stores
/// such a row as a debit with this name and purpose (`Targobank` in `Sources/FinTS`), and `reconcile` pairs it with its
/// booking by the amount alone, because it names no counterparty. Both texts are fixed German data of the row and not
/// localized texts: the purpose takes part in the identity of the row, so it must not change with the language of the app.
///
/// Never change either text. `isPendingCardDebit` recognizes the stored rows by them, so a card debit stored with an older
/// text would no longer pair with its booking, and the purpose is part of the identity by which a refresh finds a stored row.
public enum PendingCardDebit {
	public static let name = "Abbuchung"
	public static let purpose = "Targobank übermittelt den Namen einer vorgemerkten Kartenzahlung erst mit der Buchung. Der Umsatz ändert sich, wenn die Bank ihn bucht."
}

extension Transaction {
	/// Whether the row is a pending card debit of Targobank as the connector stored it: pending, negative, without an
	/// IBAN, and with exactly the name and the purpose of `PendingCardDebit`, as the bank delivered them.
	var isPendingCardDebit: Bool {
		guard isPending, counterpartyIBAN == nil else { return false }
		let delivered = sourceValues
		return delivered.amountMinor < 0 && delivered.name == PendingCardDebit.name && delivered.purpose == PendingCardDebit.purpose
	}
}
