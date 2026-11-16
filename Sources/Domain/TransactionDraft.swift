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
	/// for an existing one starts from its values. The amount keeps its sign and shows every decimal
	/// place of its currency with a decimal comma, such as "-12,00".
	public init(template t: Transaction) {
		name = t.name
		amount = AmountParser.editableText(t.amount, decimalMark: .comma)
		purpose = t.purpose
		categoryID = t.categoryID
	}

	/// The amount in minor units of `currency`, or why the window refuses it.
	///
	/// The text has a reading with a decimal comma and one with a decimal point. A reading with more decimal places
	/// than the currency has does not count, so "1.234" is 1.234,00 € and "1,200" is 1.200 JPY. When two readings
	/// with different values remain, as "12,345" in KWD has, `region`, the decimal mark of the Mac, decides. A text
	/// whose readings all have too many decimal places is refused and never rounded.
	public func amountMinor(in currency: String, region: DecimalMark) -> Result<Int64, AmountProblem> {
		let text = Currency.removingSigns(of: currency, from: amount)
		guard !text.allSatisfy(\.isWhitespace) else { return .failure(.missing) }
		let readings = DecimalMark.allCases.compactMap { mark in AmountParser.decimal(from: text, decimalMark: mark).map { (mark: mark, value: $0) } }
		guard !readings.isEmpty else { return .failure(.notANumber) }
		let fitting = readings.filter { Currency.fits($0.value, currency) }
		guard let value = fitting.count == 2 && fitting[0].value != fitting[1].value
			? fitting.first(where: { $0.mark == region })?.value : fitting.first?.value else { return .failure(.tooManyDecimals) }
		// Beyond the range of minor units, the conversion would store another amount.
		let limit = Money(minorUnits: .max, currency: currency).decimal
		guard -limit <= value, value <= limit else { return .failure(.tooLarge) }
		let minor = Money(value, currency: currency).minorUnits
		return minor == 0 ? .failure(.zero) : .success(minor)
	}

	/// The user changed the name field to `text`. `offered` are the suggestions that the field showed for the
	/// name before the change. The suggestion list of the system reports no choice, so the change counts as a
	/// chosen suggestion when `text` is one of them and the user did not just type one more character or delete
	/// some. Then the suggestion fills the purpose and the category. Typing a name to its end fills nothing.
	public mutating func enterName(_ text: String, offered: [Transaction], for accountID: UUID, in ledger: Ledger) {
		let typed = text.count == name.count + 1 && text.hasPrefix(name) || name.hasPrefix(text)
		name = text
		guard !typed, let chosen = offered.first(where: { $0.name == text }) else { return }
		take(chosen, for: accountID, in: ledger)
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
	case missing, notANumber, tooManyDecimals, zero, tooLarge

	public var message: String {
		switch self {
		case .missing: "Enter an amount."
		case .notANumber: "The amount is not a number."
		case .tooManyDecimals: "The amount has more decimal places than its currency."
		case .zero: "The amount should not be zero."
		case .tooLarge: "The amount is too large."
		}
	}
}

/// The fields of a row that the window for a transaction can change.
public enum TransactionEditing: Sendable {
	case allFields
	/// A row from a file in an account with bank access: its date, amount, and purpose stay, because the next
	/// refresh pairs the row by them.
	case nameCategoryAndComment
	case categoryAndComment
}

extension DecimalMark {
	/// The decimal mark of a region, such as the comma for Germany and the point for the United States.
	public init(region: Locale) {
		self = region.decimalSeparator == "." ? .point : .comma
	}
}

extension Ledger {
	/// What the window can change in the row `rowID`, or in a new row for nil. A row of an offline account and a
	/// manual row that no source matched change in every field. A manual row that a file or a migration matched is a
	/// row of that source, because the next refresh pairs it by its date, amount, and purpose. A part of a split changes its category and its comment. In an account
	/// with bank access, a row from a file keeps its date, amount, and purpose, because a change of them makes the
	/// next refresh add the booking a second time. A row that a refresh or a migration brought, and an older row
	/// without the manual mark, changes only its category and its comment.
	public func editing(_ rowID: UUID?) -> TransactionEditing {
		guard let rowID else { return .allFields }
		guard part(rowID) == nil, let t = row(rowID), let account = account(t.accountID) else { return .categoryAndComment }
		if account.isOffline || t.isOnlyManual { return .allFields }
		return t.fileIdentity != nil && !t.isFetched ? .nameCategoryAndComment : .categoryAndComment
	}

	/// What "Add Transaction..." in `account` starts from: the one selected row of the account, also a part of a split,
	/// or an empty draft. A row in another currency gives no amount, because the window stores the amount in the
	/// currency of the account and would change its value.
	public func newTransactionDraft(in account: Account, selection: Set<UUID>) -> TransactionDraft {
		guard selection.count == 1, let id = selection.first, let t = row(id), t.accountID == account.id else { return TransactionDraft() }
		var draft = TransactionDraft(template: t)
		if t.currency != account.currency { draft.amount = "" }
		return draft
	}

	/// The earlier transactions whose name starts with `text`, newest first and one for each name. Case and
	/// umlauts do not matter, so "bäck" finds "Baeckerei". The folded name opens the search text of each row,
	/// so a keystroke compares bytes and folds no name, which kept it within a frame for 50,000 names.
	public func nameSuggestions(for text: String, limit: Int = 8) -> [Transaction] {
		// The search text has single spaces and none at its start, so the typed text gets the same.
		let folded = TextFolding.fold(text)
		let words = folded.split(whereSeparator: \.isWhitespace)
		guard !words.isEmpty else { return [] }
		let prefix = words.joined(separator: " ") + (folded.last?.isWhitespace == true ? " " : "")
		var seen: Set<String> = []
		var result: [Transaction] = []
		for t in transactions {
			guard let searched = searchText[t.id], searched.utf8.starts(with: prefix.utf8), seen.insert(t.name).inserted else { continue }
			result.append(t)
			if result.count == limit { break }
		}
		return result
	}
}
