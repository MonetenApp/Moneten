import Foundation

/// A detail that the source delivered for a transaction. The help tag of a row and the transaction sheet show
/// them with their labels, and a copied row adds them to its purpose.
public enum TransactionDetail: Hashable, Sendable {
	case bookingText(String)
	case returnReason(String)
	case endToEndReference(String)
	case mandateReference(String)
	case creditorID(String)
	/// The amount before the bank converted it.
	case originalAmount(Money)
	/// The deviating recipient of a debit or the deviating originator of a credit.
	case deviatingParty(String, recipient: Bool)
	case valueDate(Day)
	/// The account of the counterparty when it is a valid IBAN.
	case iban(IBAN)
	/// The account of the counterparty as the source gave it when it is no valid IBAN, such as an older account number.
	case accountNumber(String)
	case bic(String)

	/// The same label as the field of the transaction sheet, so that one detail has one name in the app.
	public var label: String {
		switch self {
		case .bookingText: String(localized: "Transaction type")
		case .returnReason: String(localized: "Return reason")
		case .endToEndReference: String(localized: "End-to-end reference")
		case .mandateReference: String(localized: "Mandate reference")
		case .creditorID: String(localized: "Creditor ID")
		case .originalAmount: String(localized: "Original amount")
		case let .deviatingParty(_, recipient): recipient ? String(localized: "Deviating recipient") : String(localized: "Deviating originator")
		case .valueDate: String(localized: "Value date")
		case .iban: String(localized: "IBAN")
		case .accountNumber: String(localized: "Account number")
		case .bic: String(localized: "BIC")
		}
	}
}

extension Transaction {
	/// The details with a value, in the order of the help tag: the references first, then the original amount and the
	/// deviating party, then the value date, then the account of the counterparty. A text of only spaces counts as no value.
	public var details: [TransactionDetail] {
		func text(_ value: String?, _ detail: (String) -> TransactionDetail) -> TransactionDetail? {
			guard let value, value.contains(where: { !$0.isWhitespace }) else { return nil }
			return detail(value)
		}
		return [text(bookingText, TransactionDetail.bookingText), text(returnReason, TransactionDetail.returnReason),
			text(endToEndReference, TransactionDetail.endToEndReference), text(mandateReference, TransactionDetail.mandateReference),
			text(creditorID, TransactionDetail.creditorID), originalAmount.map(TransactionDetail.originalAmount),
			text(deviatingParty) { TransactionDetail.deviatingParty($0, recipient: amountMinor < 0) }, valueDate.map(TransactionDetail.valueDate),
			text(counterpartyIBAN) { IBAN($0).map(TransactionDetail.iban) ?? .accountNumber($0) }, text(counterpartyBIC, TransactionDetail.bic)].compactMap { $0 }
	}

	/// The name as the row shows it: the booking text stands in for a missing name.
	public var shownName: String { name.isEmpty ? (bookingText ?? "") : name }
}

/// The text that Copy puts on the pasteboard for selected rows: one line per row, joined with line breaks, with
/// no header. The fields are separated by tabs, so that a spreadsheet puts each into a column of its own.
public enum TransactionCopy {
	public static func text(_ rows: [Transaction], locale: Locale) -> String {
		let date = dateFormatter(locale)
		let marks = Marks(locale)
		return rows.map { t in
			[date.string(from: t.bookingDate.noon), noFormula(oneLine(t.shownName)), noFormula(purpose(t, marks: marks)), noFormula(accountNumber(t.counterpartyIBAN)),
				noFormula(bankCode(t.counterpartyBIC)), marks.amount(t.amountMinor, t.currency)].joined(separator: "\t")
		}.joined(separator: "\n")
	}

	/// The purpose on one line, followed by each detail that the row does not show in a column of its own. The original
	/// amount has the marks of the region and its currency, because it is not in the currency of the amount column.
	static func purpose(_ t: Transaction, marks: Marks) -> String {
		var pieces = [oneLine(t.purpose)]
		if let comment = t.comment, comment.contains(where: { !$0.isWhitespace }) { pieces.append("\(String(localized: "Comment")): \(oneLine(comment))") }
		for detail in t.details {
			switch detail {
			case let .bookingText(v), let .returnReason(v), let .endToEndReference(v), let .mandateReference(v), let .creditorID(v), let .deviatingParty(v, _):
				pieces.append("\(detail.label): \(oneLine(v))")
			case let .originalAmount(money):
				pieces.append("\(detail.label): \(marks.amount(money.minorUnits, money.currency)) \(money.currency)")
			case .valueDate, .iban, .accountNumber, .bic: break
			}
		}
		return pieces.filter { !$0.isEmpty }.joined(separator: ", ")
	}

	/// Copy escapes a formula with the rule of the CSV export. The amount never goes through here.
	static func noFormula(_ field: String) -> String { SpreadsheetFormula.escaped(field) }

	/// Every run of whitespace, also a line break or a tab, becomes one space.
	static func oneLine(_ text: String) -> String {
		text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
	}

	/// An account number of digits loses its leading zeros, as it would in a cell of a spreadsheet. An IBAN stays.
	static func accountNumber(_ value: String?) -> String {
		let value = oneLine(value ?? "")
		guard !value.isEmpty, value.allSatisfy(\.isASCIIDigit) else { return value }
		let trimmed = value.drop { $0 == "0" }
		return trimmed.isEmpty ? "0" : String(trimmed)
	}

	/// "XXX" at the end of a BIC of 11 characters names the head office, which the 8 characters already name.
	static func bankCode(_ value: String?) -> String {
		let value = oneLine(value ?? "")
		let c = Array(value)
		guard c.count == 11, c[0..<6].allSatisfy({ $0.isASCII && $0.isUppercase }), c[6..<8].allSatisfy({ $0.isASCII && ($0.isUppercase || $0.isNumber) }),
			value.hasSuffix("XXX") else { return value }
		return String(value.prefix(8))
	}

	/// The short date of the region with a four-digit year. A format without a day, a month, and a year falls back to
	/// dd.MM.yyyy. A booking date has no time zone, so the formatter counts in UTC.
	static func dateFormatter(_ locale: Locale) -> DateFormatter {
		let f = DateFormatter()
		var components = Locale.Components(locale: locale)
		components.numberingSystem = "latn"
		f.locale = Locale(components: components)
		f.timeZone = TimeZone(identifier: "UTC")
		var calendar = Calendar(identifier: .gregorian)
		calendar.timeZone = TimeZone(identifier: "UTC")!
		f.calendar = calendar
		f.dateStyle = .short
		var format = f.dateFormat ?? ""
		if !format.contains("yyyy") { format = format.replacingOccurrences(of: "y+", with: "yyyy", options: .regularExpression) }
		f.dateFormat = format.contains("d") && format.contains("M") && format.contains("yyyy") ? format : "dd.MM.yyyy"
		return f
	}

	/// The decimal mark and the thousands separator of the region, when a spreadsheet can read them. Others fall back
	/// to the point for thousands and the comma for decimals.
	struct Marks {
		let decimal: String
		let grouping: String

		init(_ locale: Locale) {
			self.init(decimal: locale.decimalSeparator ?? ",", grouping: locale.groupingSeparator ?? "")
		}

		/// A no-break space, also the narrow one of France, becomes a plain space, so that the text holds no invisible
		/// character.
		init(decimal: String, grouping: String) {
			let grouping = grouping.replacingOccurrences(of: "\u{00A0}", with: " ").replacingOccurrences(of: "\u{202F}", with: " ")
			if [",", "."].contains(decimal), [",", ".", " ", "'", "\u{2019}", ""].contains(grouping), grouping != decimal {
				self.decimal = decimal
				self.grouping = grouping
			} else {
				self.decimal = ","
				self.grouping = "."
			}
		}

		/// The amount with the decimal places of its currency, a hyphen for a withdrawal, and no currency.
		func amount(_ minorUnits: Int64, _ currency: String) -> String {
			let plain = AmountText.text(minorUnits, currency)
			let negative = plain.hasPrefix("-")
			let parts = plain.dropFirst(negative ? 1 : 0).split(separator: ".", maxSplits: 1)
			let whole = Array(parts[0])
			var grouped = ""
			for (i, digit) in whole.enumerated() {
				if i > 0, (whole.count - i) % 3 == 0 { grouped += grouping }
				grouped.append(digit)
			}
			return (negative ? "-" : "") + grouped + (parts.count > 1 ? decimal + parts[1] : "")
		}
	}
}

private extension Character {
	var isASCIIDigit: Bool { isASCII && isNumber }
}
