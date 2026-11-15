import Foundation

/// The fields of the window for a manual transaction as the user types them. The window keeps the
/// date and the comment itself, because a template and a suggestion leave both alone.
public struct TransactionDraft: Hashable, Sendable {
	public var name = ""
	/// The amount with its sign, as typed: "-4,80" goes out of the account, "50,00" comes in.
	public var amount = ""
	public var purpose = ""
	public var categoryID: UUID?

	public init() {}

	/// The fields of `t`: the window for a new transaction repeats a selected one, and the window
	/// for an existing one starts from its values. The amount keeps its sign.
	public init(template t: Transaction) {
		name = t.name
		amount = Self.text(of: t.amount)
		purpose = t.purpose
		categoryID = t.categoryID
	}

	/// An amount as the window shows it: its sign, every decimal place of its currency, and a decimal comma,
	/// such as "-12,00". Three decimals after at most three digits, as in "1,234", also read as a thousands
	/// group, so such a text ends with an extra zero, which `AmountParser` then reads without doubt.
	static func text(of money: Money) -> String {
		let places = money.decimalPlaces
		var digits = String(money.minorUnits.magnitude)
		if digits.count <= places { digits = String(repeating: "0", count: places + 1 - digits.count) + digits }
		let sign = money.isNegative ? "-" : ""
		let text = places == 0 ? sign + digits : sign + digits.dropLast(places) + "," + digits.suffix(places)
		return AmountParser.decimal(from: text) == nil ? text + "0" : text
	}

	/// The amount in minor units of `currency`, or why the window refuses it. An amount that rounds
	/// to zero in that currency counts as zero.
	public func amountMinor(in currency: String) -> Result<Int64, AmountProblem> {
		guard !amount.allSatisfy(\.isWhitespace) else { return .failure(.missing) }
		guard let value = AmountParser.decimal(from: amount) else { return .failure(.notANumber) }
		let minor = Money(value, currency: currency).minorUnits
		return minor == 0 ? .failure(.zero) : .success(minor)
	}

	/// Takes the suggestion that the user chose for the name. It fills the purpose and the category only
	/// while they are empty, so it never overwrites what the user typed. A category restricted to other
	/// accounts than `accountID` stays out, because the transaction could not keep it.
	public mutating func take(_ suggestion: Transaction, for accountID: UUID, in ledger: Ledger) {
		name = suggestion.name
		if purpose.isEmpty { purpose = suggestion.purpose }
		if categoryID == nil, let id = suggestion.categoryID, let c = ledger.category(id),
			ledger.allowedAccounts(of: c).map({ $0.contains(accountID) }) ?? true {
			categoryID = id
		}
	}
}

/// Why the window for a manual transaction refuses an amount.
public enum AmountProblem: Error, Hashable, Sendable {
	case missing, notANumber, zero

	public var message: String {
		switch self {
		case .missing: "Enter an amount."
		case .notANumber: "The amount is not a number."
		case .zero: "The amount should not be zero."
		}
	}
}

extension Ledger {
	/// The earlier transactions whose name starts with `text`, newest first and one for each name. Case and
	/// umlauts do not matter, so "bäck" finds "Baeckerei". The folded name opens the search text of each row,
	/// so a keystroke compares bytes and folds no name, which kept it within a frame for 50,000 names.
	public func nameSuggestions(for text: String, limit: Int = 8) -> [Transaction] {
		let prefix = TextFolding.fold(text)
		guard !prefix.isEmpty else { return [] }
		var seen: Set<String> = []
		var result: [Transaction] = []
		for t in transactions {
			guard let folded = searchText[t.id], folded.utf8.starts(with: prefix.utf8), seen.insert(t.name).inserted else { continue }
			result.append(t)
			if result.count == limit { break }
		}
		return result
	}
}
