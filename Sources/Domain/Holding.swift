import Foundation

/// A security as its source names it.
public struct Security: Hashable, Sendable {
	public var name: String
	public var isin: String?
	/// The national number of the security, such as the WKN in Germany.
	public var securityNumber: String?

	public init(name: String, isin: String? = nil, securityNumber: String? = nil) {
		self.name = name
		self.isin = isin
		self.securityNumber = securityNumber
	}
}

/// A price of a security: an amount per unit in a currency, or a percentage of the nominal amount when
/// it has no currency, as the price of a bond. The amount keeps every decimal place of its source.
public struct Quote: Hashable, Sendable {
	public var amount: Decimal
	/// Nil for a percentage.
	public var currency: String?
	/// The day of the quote, or of the purchase for a purchase price.
	public var day: Day?

	public init(amount: Decimal, currency: String?, day: Day? = nil) {
		self.amount = amount
		self.currency = currency
		self.day = day
	}

	public var isPercentage: Bool { currency == nil }
}

/// An exchange rate as the bank sends it: one unit of `base` costs `rate` units of `quoted`.
public struct ExchangeRate: Hashable, Sendable {
	public var base: String
	public var quoted: String
	public var rate: Decimal

	public init(base: String, quoted: String, rate: Decimal) {
		self.base = base
		self.quoted = quoted
		self.rate = rate
	}

	/// The amount in `target`, or nil when the rate does not link the two currencies.
	public func convert(_ amount: Decimal, from source: String, to target: String) -> Decimal? {
		if source == target { return amount }
		guard rate > 0 else { return nil }
		if source == base, target == quoted { return amount * rate }
		if source == quoted, target == base { return amount / rate }
		return nil
	}
}

/// One position of a portfolio: a security with its quantity, its last quote, its value, and its
/// purchase price, as the latest successful refresh delivered it.
public struct Holding: Identifiable, Hashable, Sendable {
	public var id: UUID
	public var accountID: UUID
	public var security: Security
	/// A number of units, or a nominal amount in `nominalCurrency`.
	public var quantity: Decimal
	/// The currency of a nominal amount. Nil for a number of units.
	public var nominalCurrency: String?
	public var quote: Quote?
	/// The market value that the source reports, without accrued interest.
	public var marketValue: Money?
	public var accruedInterest: Money?
	/// The purchase price of one unit, or the purchase rate in percent of a nominal amount.
	public var purchasePrice: Quote?
	/// The rate that converts the quote or the purchase price into the currency of the value.
	public var exchangeRate: ExchangeRate?

	public init(id: UUID = UUID(), accountID: UUID, security: Security, quantity: Decimal, nominalCurrency: String? = nil, quote: Quote? = nil,
		marketValue: Money? = nil, accruedInterest: Money? = nil, purchasePrice: Quote? = nil, exchangeRate: ExchangeRate? = nil) {
		self.id = id
		self.accountID = accountID
		self.security = security
		self.quantity = quantity
		self.nominalCurrency = nominalCurrency
		self.quote = quote
		self.marketValue = marketValue
		self.accruedInterest = accruedInterest
		self.purchasePrice = purchasePrice
		self.exchangeRate = exchangeRate
	}

	/// The profit or loss of a position: the amount, and its share of the purchase value in percent.
	/// The percentage is nil when the purchase value is 0.
	public struct Gain: Hashable, Sendable {
		public let amount: Money
		public let percent: Decimal?
	}

	/// What the position adds to its account: the market value plus the accrued interest. Without a
	/// market value from the source, the quantity times the quote, in `currency` when the exchange rate
	/// links the currencies. Nil without a market value and without a quote.
	public func value(in currency: String) -> Money? {
		guard let market = marketDecimal(in: currency) else { return nil }
		var total = market.amount
		if let accruedInterest, accruedInterest.currency == market.currency { total += accruedInterest.decimal }
		return Money(total, currency: market.currency)
	}

	/// The value less the purchase value, without the accrued interest. Nil without a purchase price, and
	/// when the purchase value cannot be converted into the currency of the value.
	public func gain(in currency: String) -> Gain? {
		guard let market = marketDecimal(in: currency), let purchase = purchaseValue(in: market.currency) else { return nil }
		let difference = market.amount - purchase
		return Gain(amount: Money(difference, currency: market.currency), percent: purchase == 0 ? nil : difference / abs(purchase) * 100)
	}

	/// The purchase value in `currency`, unrounded, so the gain rounds only once.
	func purchaseValue(in currency: String) -> Decimal? {
		guard let purchasePrice else { return nil }
		return worth(at: purchasePrice).flatMap { convert($0.amount, from: $0.currency, to: currency) }
	}

	/// The market value without accrued interest, unrounded: the one of the source, or else the quantity
	/// times the quote, converted into `currency` when the rate allows it.
	private func marketDecimal(in currency: String) -> (amount: Decimal, currency: String)? {
		if let marketValue { return (marketValue.decimal, marketValue.currency) }
		guard let quote, let worth = worth(at: quote) else { return nil }
		if let converted = convert(worth.amount, from: worth.currency, to: currency) { return (converted, currency) }
		return worth
	}

	/// The quantity at a price, in the currency of the price, or of the nominal amount for a percentage.
	private func worth(at price: Quote) -> (amount: Decimal, currency: String)? {
		if let currency = price.currency { return (quantity * price.amount, currency) }
		guard let nominalCurrency else { return nil }
		return (quantity * price.amount / 100, nominalCurrency)
	}

	private func convert(_ amount: Decimal, from source: String, to target: String) -> Decimal? {
		if source == target { return amount }
		return exchangeRate?.convert(amount, from: source, to: target)
	}
}

extension Holding {
	/// The order of a list of positions: by the name of the security without regard to case.
	public static func isOrdered(_ a: Holding, _ b: Holding) -> Bool {
		a.security.name.localizedCaseInsensitiveCompare(b.security.name) == .orderedAscending
	}

	/// Whether `text` occurs in the name, the ISIN, or the security number, without regard to case.
	public func matches(_ text: String) -> Bool {
		let fields = [security.name, security.isin, security.securityNumber].compactMap { $0 }
		return fields.contains { $0.localizedCaseInsensitiveContains(text) }
	}

	/// Gives each delivered position the ID of a stored one of the same security, so a position keeps its
	/// identity across refreshes. A stored position matches by its ISIN, or else by its security number,
	/// or else by its name, and at most once.
	public static func identify(_ delivered: [Holding], stored: [Holding]) -> [Holding] {
		var free = stored
		let keys: [(Holding) -> String?] = [\.security.isin, \.security.securityNumber, { $0.security.name }]
		return delivered.map { holding in
			var holding = holding
			for key in keys {
				guard let wanted = key(holding), !wanted.isEmpty, let i = free.firstIndex(where: { key($0) == wanted }) else { continue }
				holding.id = free.remove(at: i).id
				break
			}
			return holding
		}
	}
}
