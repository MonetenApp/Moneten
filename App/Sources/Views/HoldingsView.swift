import Domain
import SwiftUI

/// The positions of the selected portfolios, in place of the filter bar, the transaction list, and its status
/// line. The search field of the window filters them by name, ISIN, and security number.
struct HoldingsView: View {
	@Environment(AppModel.self) private var model
	/// `AppModel.tableKey`, from the parent, as for `TransactionTable` (issue #135).
	let key: TableKey
	/// The placeholder of `AppModel.replacingTable` stands in for the table.
	let holds: Bool
	let accountIDs: [UUID]
	@State private var selection: Set<UUID> = []

	var body: some View {
		let all = model.ledger.holdings(of: accountIDs)
		// The search of the key, as for the transaction table. The parent starts this view over for a new
		// search, instead of removing shown rows in place.
		let search = key.filter.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
		let rows = search.isEmpty ? all : all.filter { $0.matches(search) }
		VStack(spacing: 0) {
			// The table stays also without rows, with the empty state on top. The rows keep their IDs across a
			// refresh, so a refresh updates them in place. A refresh that drops a shown position starts the table
			// over (#135, #151), with the placeholder of `AppModel.replacingTable` in between.
			Group {
				if holds {
					Color.clear
				} else {
					HoldingsTable(rows: rows, selection: guardedSelection)
				}
			}
			.overlay {
				if rows.isEmpty, !holds {
					Text(all.isEmpty ? "No portfolio items found." : "No matching portfolio items found.")
						.foregroundStyle(.secondary)
				}
			}
			HoldingsStatusLine(rows: rows, selection: selection)
		}
		.onChange(of: selection.count, initial: true) { _, count in model.selectedPositions = count }
	}

	/// The selection, as long as the model shows this view: see `AppModel.shows(_:)`.
	private var guardedSelection: Binding<Set<UUID>> {
		let state = $selection
		return Binding(get: { state.wrappedValue }, set: { [model, key] in if model.shows(key) { state.wrappedValue = $0 } })
	}
}

struct HoldingsTable: View {
	@Environment(AppModel.self) private var model
	let rows: [Holding]
	@Binding var selection: Set<UUID>

	var body: some View {
		Table(rows, selection: $selection) {
			TableColumn("Name") { h in
				VStack(alignment: .leading, spacing: 2) {
					Text(h.security.name).lineLimit(1)
					if let number = h.security.isin ?? h.security.securityNumber {
						Text(number).font(.callout).foregroundStyle(Palette.detail)
					}
				}
			}
			.width(min: 180, ideal: 260)
			TableColumn("Quantity") { h in
				Text(Format.quantity(h)).monospacedDigit()
			}
			.width(min: 80, ideal: 110)
			.alignment(.trailing)
			TableColumn("Purchase price") { h in
				Text(h.purchasePrice.map(Format.price) ?? "").monospacedDigit()
			}
			.width(min: 80, ideal: 110)
			.alignment(.trailing)
			TableColumn("Last quote") { h in
				VStack(alignment: .trailing, spacing: 2) {
					Text(h.quote.map(Format.price) ?? "").monospacedDigit()
					if let day = h.quote?.day { Text(Format.day(day)).font(.callout).foregroundStyle(Palette.detail) }
				}
			}
			.width(min: 80, ideal: 110)
			.alignment(.trailing)
			TableColumn("Value") { h in
				if let value = h.value(in: currency(of: h)) { AmountText(money: value) }
			}
			.width(min: 90, ideal: 120)
			.alignment(.trailing)
			TableColumn("Profit/Loss") { h in
				if let gain = h.gain(in: currency(of: h)) {
					VStack(alignment: .trailing, spacing: 2) {
						AmountText(money: gain.amount)
						Text([gain.amount.isNegative ? String(localized: "Loss") : String(localized: "Profit"), gain.percent.map(Format.percent)].compactMap { $0 }.joined(separator: " "))
							.font(.callout).monospacedDigit().foregroundStyle(Palette.detail)
					}
				}
			}
			.width(min: 100, ideal: 130)
			.alignment(.trailing)
		}
		.tableStyle(.bordered(alternatesRowBackgrounds: false))
	}

	private func currency(of h: Holding) -> String {
		model.ledger.account(h.accountID)?.currency ?? h.marketValue?.currency ?? "EUR"
	}
}

/// The number of positions and their sum, or of the selected ones, as the status line of the transactions shows them.
struct HoldingsStatusLine: View {
	@Environment(AppModel.self) private var model
	let rows: [Holding]
	let selection: Set<UUID>

	var body: some View {
		let selected = rows.filter { selection.contains($0.id) }
		let shown = selected.count > 1 ? selected : rows
		let sums = shown.reduce(into: MoneySums()) { sums, h in
			if let value = h.value(in: model.ledger.account(h.accountID)?.currency ?? "EUR") { sums.add(value) }
		}
		// An empty sum takes the currency of the portfolio, as the status line of the transactions does.
		let firstRowCurrency = shown.first.flatMap { model.ledger.account($0.accountID)?.currency }
		HStack(spacing: 12) {
			Group {
				if let status = model.refreshStatus {
					HStack(spacing: 6) {
						ProgressView().controlSize(.mini)
						Text(status).lineLimit(1)
					}
					.foregroundStyle(.secondary)
				} else if let problem = model.backgroundProblem {
					BackgroundProblemButton(problem: problem)
				}
			}
			.frame(maxWidth: .infinity, alignment: .leading)
			HStack(spacing: 12) {
				Text(selected.count > 1 ? "\(selected.count) of \(rows.count) Portfolio Items" : (rows.count == 1 ? "1 Portfolio Item" : "\(rows.count) Portfolio Items"))
					.foregroundStyle(Palette.detail)
				Text("Sum: \(Format.sums(sums.shownAmounts(viewCurrency: model.selectedCurrency, firstRowCurrency: firstRowCurrency)))")
					.monospacedDigit()
					.textSelection(.enabled)
			}
			.fixedSize()
			Color.clear.frame(maxWidth: .infinity, maxHeight: 0)
		}
		.font(.system(size: 11))
		.padding(.horizontal, 16)
		.frame(height: StatusLine.height)
	}
}

/// The total profit or loss of the positions of the selected portfolios, for the upper right corner of the header.
struct TotalGainText: View {
	@Environment(AppModel.self) private var model
	let accountIDs: [UUID]

	var body: some View {
		let gain = model.ledger.totalGain(of: accountIDs)
		if !gain.isEmpty {
			let amounts = gain.amounts
			let label = amounts.allSatisfy { !$0.isNegative } ? String(localized: "Profit") : amounts.allSatisfy(\.isNegative) ? String(localized: "Loss") : String(localized: "Profit/Loss")
			Text("\(label): \(Format.sums(gain))").font(.subheadline).monospacedDigit().foregroundStyle(Palette.detail)
		}
	}
}

extension Format {
	/// "40 shares", "12,3456 shares", "1 share", or a nominal amount such as "5.000,00 €", or "5.000,00" without a
	/// known currency, with every decimal place of the source.
	static func quantity(_ h: Holding) -> String {
		let places = decimalPlaces(of: h.quantity)
		if h.isNominal {
			let precision = NumberFormatStyleConfiguration.Precision.fractionLength(2...max(2, places))
			guard let currency = h.nominalCurrency else { return signed(h.quantity.formatted(.number.precision(precision))) }
			return signed(h.quantity.formatted(.currency(code: currency).precision(precision)))
		}
		let number = signed(h.quantity.formatted(.number.precision(.fractionLength(0...places))))
		return h.quantity == 1 ? String(localized: "\(number) share") : String(localized: "\(number) shares")
	}

	/// "25,00 €", "12,3456 €", or "98,50 %": at least two decimal places, and every one of the source.
	static func price(_ q: Quote) -> String {
		let precision = NumberFormatStyleConfiguration.Precision.fractionLength(2...max(2, decimalPlaces(of: q.amount)))
		guard let currency = q.currency else { return signed(q.amount.formatted(.number.precision(precision))) + " %" }
		return signed(q.amount.formatted(.currency(code: currency).precision(precision)))
	}

	/// "25,00 %" or "−20,00 %".
	static func percent(_ value: Decimal) -> String {
		signed(value.formatted(.number.precision(.fractionLength(2)))) + " %"
	}

	private static func decimalPlaces(of value: Decimal) -> Int { max(0, -value.exponent) }

	private static func signed(_ text: String) -> String {
		text.replacingOccurrences(of: "-", with: "\u{2212}")
	}
}
