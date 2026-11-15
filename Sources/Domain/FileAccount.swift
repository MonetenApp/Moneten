import Foundation

/// The account that a CAMT or MT940 file names: an IBAN, or an account number with its bank code when
/// the file has one.
public enum FileAccount: Hashable, Sendable {
	case iban(String)
	case number(bankCode: String?, account: String)

	/// Where the transactions of a file go when the user imports it into `selected`.
	public enum Destination: Hashable, Sendable {
		/// The file names the selected account, or no account.
		case selected
		/// The file names another account of the app, and the app asks before it imports there.
		case other(Account)
		/// No account of the app has the account of the file, and the app asks where to import.
		case unknown
	}

	/// Of several accounts with the number of the file, such as a portfolio and a giro account of one
	/// broker, the one in the `currency` of the file that is not a portfolio comes first.
	/// The selected account keeps the file unless another match ranks higher.
	public func destination(selected: Account, accounts: [Account], currency: String) -> Destination {
		func rank(_ account: Account) -> Int { (account.currency == currency ? 2 : 0) + (account.kind != .portfolio ? 1 : 0) }
		let others = accounts.filter { $0.id != selected.id && matches($0) }
		let best = others.max { rank($0) < rank($1) }
		if matches(selected), rank(selected) >= best.map(rank) ?? 0 { return .selected }
		return best.map(Destination.other) ?? .unknown
	}

	/// The offline account that "Create offline account" adds for the file, named by its IBAN or its account number.
	public func offlineAccount(groupID: UUID?, position: Int, currency: String) -> Account {
		var account = Account(groupID: groupID, position: position, name: "", kind: .giro, source: .offline, currency: currency)
		switch self {
		case let .iban(text):
			let iban = TextFolding.accountKey(text)
			account.iban = iban
			let characters = Array(iban)
			account.name = stride(from: 0, to: characters.count, by: 4).map { String(characters[$0..<min($0 + 4, characters.count)]) }.joined(separator: " ")
		case let .number(bankCode, number):
			account.bankCode = bankCode
			account.accountNumber = number
			account.name = "Account \(number)"
		}
		return account
	}

	/// An account number matches without its leading zeros, and also the number inside a German IBAN,
	/// whose digits 5 to 12 are the bank code and 13 to 22 the account number. So a German IBAN also
	/// matches an account that has only its bank code and account number.
	func matches(_ account: Account) -> Bool {
		// An extension can list an empty IBAN.
		let iban = account.iban.map(TextFolding.accountKey).flatMap { $0.isEmpty ? nil : $0 }
		switch self {
		case let .iban(text):
			let own = TextFolding.accountKey(text)
			// An extension can list the IBAN as the account number.
			if iban == own || account.accountNumber.map(TextFolding.accountKey) == own { return true }
			guard iban == nil, own.hasPrefix("DE"), own.count == 22 else { return false }
			let digits = Array(own)
			return FileAccount.number(bankCode: String(digits[4..<12]), account: String(digits[12...])).matches(account)
		case let .number(bankCode, number):
			let number = Self.withoutLeadingZeros(number)
			// An extension can list the IBAN as the account number.
			let german = (iban ?? account.accountNumber.map(TextFolding.accountKey)).flatMap { $0.hasPrefix("DE") && $0.count == 22 ? Array($0) : nil }
			let ownBankCode = account.bankCode ?? german.map { String($0[4..<12]) }
			// A file that names a bank never takes an account without a bank code, which an exact match elsewhere may own.
			if let own = account.accountNumber, Self.withoutLeadingZeros(own) == number, bankCode == nil || ownBankCode == bankCode { return true }
			guard let german else { return false }
			return (bankCode == nil || String(german[4..<12]) == bankCode) && Self.withoutLeadingZeros(String(german[12...])) == number
		}
	}

	private static func withoutLeadingZeros(_ text: String) -> String {
		String(text.drop { $0 == "0" })
	}
}
