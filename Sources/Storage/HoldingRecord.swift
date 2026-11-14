import Domain
import Foundation
import GRDB

/// A row of the table "holding": one position of a portfolio with its security, quote, and purchase price
/// flattened. Quantities, prices, and rates are decimal text, because SQLite has no decimal type and a
/// double loses decimal places. A price without a currency is a percentage.
struct HoldingRecord: Codable, FetchableRecord, PersistableRecord, TableRecord {
	static let databaseTableName = "holding"
	var id: UUID
	var accountID: UUID
	var name: String
	var isin: String?
	var securityNumber: String?
	var quantity: String
	var nominalCurrency: String?
	var price: String?
	var priceCurrency: String?
	var priceDay: Day?
	var marketValueMinor: Int64?
	var marketValueCurrency: String?
	var accruedInterestMinor: Int64?
	var accruedInterestCurrency: String?
	var purchasePrice: String?
	var purchasePriceCurrency: String?
	var purchaseDay: Day?
	var rateBase: String?
	var rateQuoted: String?
	var rate: String?

	init(_ h: Holding) {
		id = h.id
		accountID = h.accountID
		name = h.security.name
		isin = h.security.isin
		securityNumber = h.security.securityNumber
		quantity = h.quantity.description
		nominalCurrency = h.nominalCurrency
		price = h.quote?.amount.description
		priceCurrency = h.quote?.currency
		priceDay = h.quote?.day
		marketValueMinor = h.marketValue?.minorUnits
		marketValueCurrency = h.marketValue?.currency
		accruedInterestMinor = h.accruedInterest?.minorUnits
		accruedInterestCurrency = h.accruedInterest?.currency
		purchasePrice = h.purchasePrice?.amount.description
		purchasePriceCurrency = h.purchasePrice?.currency
		purchaseDay = h.purchasePrice?.day
		rateBase = h.exchangeRate?.base
		rateQuoted = h.exchangeRate?.quoted
		rate = h.exchangeRate?.rate.description
	}

	/// The position, or nil when a decimal does not read, which only a foreign writer of the table causes.
	var holding: Holding? {
		guard let quantity = Self.decimal(quantity) else { return nil }
		let money = { (minor: Int64?, currency: String?) in minor.flatMap { m in currency.map { Money(minorUnits: m, currency: $0) } } }
		var exchangeRate: ExchangeRate?
		if let rateBase, let rateQuoted, let rate = rate.flatMap(Self.decimal) {
			exchangeRate = ExchangeRate(base: rateBase, quoted: rateQuoted, rate: rate)
		}
		return Holding(id: id, accountID: accountID, security: Security(name: name, isin: isin, securityNumber: securityNumber), quantity: quantity,
			nominalCurrency: nominalCurrency, quote: price.flatMap(Self.decimal).map { Quote(amount: $0, currency: priceCurrency, day: priceDay) },
			marketValue: money(marketValueMinor, marketValueCurrency), accruedInterest: money(accruedInterestMinor, accruedInterestCurrency),
			purchasePrice: purchasePrice.flatMap(Self.decimal).map { Quote(amount: $0, currency: purchasePriceCurrency, day: purchaseDay) },
			exchangeRate: exchangeRate)
	}

	/// `Decimal.description` writes a plain number with a point, which this reads back exactly.
	static func decimal(_ text: String) -> Decimal? {
		Decimal(string: text, locale: Locale(identifier: "en_US_POSIX"))
	}
}
