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
	/// A number of units, or a nominal amount when `isNominal` is set.
	public var quantity: Decimal
	public var isNominal: Bool
	/// The currency of a nominal amount, nil when the source names none. Without it, a percentage gives no value and no gain.
	public var nominalCurrency: String?
	public var quote: Quote?
	/// The market value that the source reports, without accrued interest.
	public var marketValue: Money?
	public var accruedInterest: Money?
	/// The purchase price of one unit, or the purchase rate in percent of a nominal amount.
	public var purchasePrice: Quote?
	/// The rate that converts the quote or the purchase price into the currency of the value.
	public var exchangeRate: ExchangeRate?
	/// The asset class that the source of the position sends, nil when it sends none. Each refresh replaces it.
	public var sourceAssetClass: AssetClass?
	/// The asset class that the user chose, nil while the user chose none. No refresh changes it.
	///
	/// The two are separate facts, and every pair of them is a valid state, so no pair needs a rule. The class that the
	/// position shows is never stored: `assetClass` derives it, so it cannot disagree with them. Keeping the class of the
	/// source next to the choice lets a refresh update it while the choice holds, and lets "Automatic" go back to it at once.
	public var userAssetClass: AssetClass?

	public init(id: UUID = UUID(), accountID: UUID, security: Security, quantity: Decimal, isNominal: Bool = false, nominalCurrency: String? = nil, quote: Quote? = nil,
		marketValue: Money? = nil, accruedInterest: Money? = nil, purchasePrice: Quote? = nil, exchangeRate: ExchangeRate? = nil,
		sourceAssetClass: AssetClass? = nil, userAssetClass: AssetClass? = nil) {
		self.id = id
		self.accountID = accountID
		self.security = security
		self.quantity = quantity
		self.isNominal = isNominal
		self.nominalCurrency = nominalCurrency
		self.quote = quote
		self.marketValue = marketValue
		self.accruedInterest = accruedInterest
		self.purchasePrice = purchasePrice
		self.exchangeRate = exchangeRate
		self.sourceAssetClass = sourceAssetClass
		self.userAssetClass = userAssetClass
	}

	/// The class that the position shows: the user's choice, or else the class of the source, or else "Others". The app
	/// never guesses a class from the name of the security.
	public var assetClass: AssetClass {
		userAssetClass ?? sourceAssetClass ?? .others
	}

	/// The profit or loss of a position: the amount, and its share of the purchase value in percent.
	/// The percentage is nil when the purchase value is 0.
	public struct Gain: Hashable, Sendable {
		public let amount: Money
		public let percent: Decimal?
	}

	/// What the position adds to its account: the market value plus the accrued interest, converted with the
	/// exchange rate into the currency of the market value when it differs. Without a
	/// market value from the source, the quantity times the quote, in `currency` when the exchange rate
	/// links the currencies. Nil without a market value and without a quote, and when the value is above
	/// `Money.maxMinorUnits`, because the plain initializer would wrap it around.
	public func value(in currency: String) -> Money? {
		exactValue(in: currency).flatMap { Money(fitting: $0.amount, currency: $0.currency) }
	}

	/// The value before it is rounded to the currency, so that a source of untrusted numbers can check its range first.
	public func exactValue(in currency: String) -> (amount: Decimal, currency: String)? {
		guard let market = marketDecimal(in: currency) else { return nil }
		var total = market.amount
		if let accruedInterest, let interest = convert(accruedInterest.decimal, from: accruedInterest.currency, to: market.currency) { total += interest }
		return (total, market.currency)
	}

	/// The value less the purchase value, without the accrued interest. Nil without a purchase price, when the
	/// purchase value cannot be converted into the currency of the value, and when the value, the purchase value,
	/// or the gain is above `Money.maxMinorUnits`.
	public func gain(in currency: String) -> Gain? {
		guard let market = marketDecimal(in: currency), let purchase = purchaseValue(in: market.currency),
			Money(fitting: market.amount, currency: market.currency) != nil, Money(fitting: purchase, currency: market.currency) != nil,
			case let difference = market.amount - purchase, let amount = Money(fitting: difference, currency: market.currency) else { return nil }
		return Gain(amount: amount, percent: purchase == 0 ? nil : difference / abs(purchase) * 100)
	}

	/// Whether every amount that the position gives in `currency` is within `Money.maxMinorUnits`: its value and,
	/// with a purchase price, its gain. A source whose quantity times its quote is beyond the limit fails at the edge,
	/// so that no amount of the position is lost later. Decimal multiplication cannot wrap; it gives no finite number instead.
	public func amountsFit(in currency: String) -> Bool {
		guard let market = marketDecimal(in: currency) else { return true }
		return value(in: currency) != nil && (purchaseValue(in: market.currency) == nil || gain(in: currency) != nil)
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

	/// The quantity at a price, in the currency of the price, or of the nominal amount for a percentage. Nil for a
	/// percentage of a nominal amount whose currency is unknown, because guessing it would convert a foreign bond wrongly.
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

	/// Gives each delivered position the ID and the user's asset class of a stored one of the same security, so a position
	/// keeps its identity and the user's choice across refreshes. A source never sends a choice of the user, so a position
	/// without a stored one has none. Every position first takes the stored one with its ISIN. Then a position
	/// matches by its security number, or else by its name, but only when one of the two has no ISIN: two
	/// different ISINs are two securities, whatever their names. Each stored position matches at most once.
	public static func identify(_ delivered: [Holding], stored: [Holding]) -> [Holding] {
		var free = stored
		var result = delivered.map { var holding = $0; holding.userAssetClass = nil; return holding }
		func take(_ j: Int, for i: Int) {
			let match = free.remove(at: j)
			result[i].id = match.id
			result[i].userAssetClass = match.userAssetClass
		}
		var open: [Int] = []
		for (i, holding) in delivered.enumerated() {
			if let isin = holding.security.isin, let j = free.firstIndex(where: { $0.security.isin == isin }) {
				take(j, for: i)
			} else {
				open.append(i)
			}
		}
		let keys: [(Holding) -> String?] = [\.security.securityNumber, { $0.security.name }]
		for i in open {
			let holding = delivered[i]
			for key in keys {
				guard let wanted = key(holding), !wanted.isEmpty,
					let j = free.firstIndex(where: { key($0) == wanted && (holding.security.isin == nil || $0.security.isin == nil) }) else { continue }
				take(j, for: i)
				break
			}
		}
		return result
	}
}
