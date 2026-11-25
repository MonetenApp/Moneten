import Domain
import Foundation
import GRDB

/// The migration v34: amounts in BTC, ETH, USDC, and USDT get the decimal places of their codes (#581). An earlier version
/// stored them with 2, so each stored amount in these codes is multiplied to the places of `TwoPlaceTokenAmounts`, which
/// keeps the table as it was here. A later change of `Currency.exponent(of:)` needs a migration of its own.
enum TokenPlacesAtV34 {
	static func migrate(_ db: Database) throws {
		for code in TwoPlaceTokenAmounts.places.keys.sorted() {
			guard let factor = TwoPlaceTokenAmounts.factor(of: code) else { continue }
			func scaled(_ column: String) -> String {
				// SQLite makes a floating-point number of an integer product that overflows, so an amount beyond the range
				// holds at its bound, as `TwoPlaceTokenAmounts.converted` does. Int64.min has no negation, so no abs().
				let bound = Int64.max / factor
				return "\(column) = CASE WHEN \(column) > \(bound) THEN \(Int64.max) WHEN \(column) < -\(bound) THEN -\(Int64.max) ELSE \(column) * \(factor) END"
			}
			try db.execute(sql: "UPDATE account SET \(scaled("bankBalanceMinor")), \(scaled("initialBalanceMinor")) WHERE currency = ?", arguments: [code])
			try db.execute(sql: "UPDATE portfolioValue SET \(scaled("minorUnits")) WHERE accountID IN (SELECT id FROM account WHERE currency = ?)", arguments: [code])
			try db.execute(sql: "UPDATE bankTransaction SET \(scaled("amountMinor")) WHERE currency = ?", arguments: [code])
			try db.execute(sql: "UPDATE bankTransaction SET \(scaled("originalAmountMinor")) WHERE originalCurrency = ?", arguments: [code])
			try db.execute(sql: "UPDATE splitPart SET \(scaled("amountMinor")) WHERE transactionID IN (SELECT id FROM bankTransaction WHERE currency = ?)", arguments: [code])
			try db.execute(sql: "UPDATE deletedTransaction SET \(scaled("amountMinor")) WHERE currency = ?", arguments: [code])
			try db.execute(sql: "UPDATE holding SET \(scaled("marketValueMinor")) WHERE marketValueCurrency = ?", arguments: [code])
			try db.execute(sql: "UPDATE holding SET \(scaled("accruedInterestMinor")) WHERE accruedInterestCurrency = ?", arguments: [code])
		}
		let codes = TwoPlaceTokenAmounts.places.keys.sorted()
		let marks = codes.map { _ in "?" }.joined(separator: ", ")
		// The amounts inside JSON: the other balances of an account, each with its own currency, and the values of an
		// edited row and of a clearing entry, in the currency of the row and of its account.
		for row in try Row.fetchAll(db, sql: "SELECT id, otherBankBalances FROM account WHERE otherBankBalances <> '[]'") {
			guard let json = try converted(row["otherBankBalances"], { balance in balance["currency"] as? String }, at: [])
			else { continue }
			try db.execute(sql: "UPDATE account SET otherBankBalances = ? WHERE id = ?", arguments: [json, row["id"] as Data])
		}
		for row in try Row.fetchAll(db, sql: "SELECT id, currency, clearingEntry FROM account WHERE clearingEntry IS NOT NULL AND currency IN (\(marks))",
			arguments: StatementArguments(codes)) {
			guard let json = try converted(row["clearingEntry"], { _ in row["currency"] }, at: ["values"]) else { continue }
			try db.execute(sql: "UPDATE account SET clearingEntry = ? WHERE id = ?", arguments: [json, row["id"] as Data])
		}
		for row in try Row.fetchAll(db, sql: "SELECT id, currency, original FROM bankTransaction WHERE original IS NOT NULL AND currency IN (\(marks))",
			arguments: StatementArguments(codes)) {
			guard let json = try converted(row["original"], { _ in row["currency"] }, at: []) else { continue }
			try db.execute(sql: "UPDATE bankTransaction SET original = ? WHERE id = ?", arguments: [json, row["id"] as Data])
		}
		// A file identity holds the amount in minor units and its own currency.
		for table in ["bankTransaction", "deletedTransaction"] {
			for row in try Row.fetchAll(db, sql: "SELECT rowid, fileIdentity FROM \(table) WHERE fileIdentity IS NOT NULL") {
				guard let identity = TwoPlaceTokenAmounts.convertedFileIdentity(row["fileIdentity"]) else { continue }
				try db.execute(sql: "UPDATE \(table) SET fileIdentity = ? WHERE rowid = ?", arguments: [identity, row["rowid"] as Int64])
			}
		}
	}

	/// The JSON text with each amount converted, or nil when nothing changes. `path` leads to the object that holds
	/// `amountMinor` or `minorUnits`, and an array holds one such object per element. `currency` gives the currency of
	/// an object. JSON that does not read stays as it is, because the app would not read it either.
	private static func converted(_ text: String, _ currency: ([String: Any]) -> String?, at path: [String]) throws -> String? {
		guard let value = try? JSONSerialization.jsonObject(with: Data(text.utf8)) else { return nil }
		var changed = false
		func convert(_ value: Any, _ path: ArraySlice<String>) -> Any {
			if let array = value as? [Any] { return array.map { convert($0, path) } }
			guard var object = value as? [String: Any] else { return value }
			if let key = path.first {
				if let inner = object[key] { object[key] = convert(inner, path.dropFirst()) }
				return object
			}
			for key in ["amountMinor", "minorUnits"] {
				guard let minor = object[key] as? Int64, let code = currency(object), TwoPlaceTokenAmounts.factor(of: code) != nil else { continue }
				object[key] = TwoPlaceTokenAmounts.converted(minor, code)
				changed = true
			}
			return object
		}
		let result = convert(value, path[...])
		guard changed else { return nil }
		return String(decoding: try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys, .withoutEscapingSlashes]), as: UTF8.self)
	}
}
