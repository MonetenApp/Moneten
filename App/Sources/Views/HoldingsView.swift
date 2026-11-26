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
		// The search and the filter "Asset class" of the key, as for the transaction table. The parent starts this view
		// over for a new search or class, instead of removing shown rows in place.
		let rows = key.filter.positions(of: all)
		VStack(spacing: 0) {
			HoldingsFilterBar(entries: AssetClass.entries(of: all))
			// The table stays also without rows, with the empty state on top. The rows keep their IDs across a
			// refresh, so a refresh updates them in place. A refresh that drops a shown position starts the table
			// over (#135, #151), with the placeholder of `AppModel.replacingTable` in between.
			Group {
				if holds {
					Color.clear
				} else {
					// The days compare with every position of the portfolio, also those that the filters hide.
					HoldingsTable(rows: rows, oldQuoteDays: Holding.oldQuoteDays(in: all), selection: guardedSelection)
						// One line below the last row while the filter "Asset class" hides positions, on the table and not on its rows.
						.background(FilterHintsFooter(hints: key.filter.positionHints, rowCount: rows.count))
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

/// The filter bar above the positions, built like the one of the transactions: "Asset class" with "Show All" and the
/// classes that the positions of the view have.
struct HoldingsFilterBar: View {
	@Environment(AppModel.self) private var model
	let entries: [AssetClass]

	var body: some View {
		HStack(spacing: 6) {
			FilterMenu("Asset class:", title: model.filter.assetClass?.name ?? String(localized: "Show All")) {
				Button("Show All") { model.filter.assetClass = nil }
				Divider()
				ForEach(entries, id: \.self) { c in Button(c.name) { model.filter.assetClass = c } }
			}
			Spacer()
		}
		// As high as the filter bar of the transactions, whose pin is 22 points high, so the list does not move.
		.frame(minHeight: 22)
		.font(.callout)
		.padding(.horizontal, 10)
		.padding(.vertical, 6)
		.background(Palette.filterBar)
	}
}

struct HoldingsTable: View {
	@Environment(AppModel.self) private var model
	let rows: [Holding]
	/// The day of each quote that is older than the newest of its portfolio: `Holding.oldQuoteDays(in:)`.
	let oldQuoteDays: [UUID: Day]
	@Binding var selection: Set<UUID>

	var body: some View {
		Table(rows, selection: $selection) {
			TableColumn("Name") { h in
				VStack(alignment: .leading, spacing: 2) {
					Text(h.security.name).lineLimit(1)
					HStack(spacing: 6) {
						if let number = h.security.isin ?? h.security.securityNumber {
							Text(number).font(.callout).foregroundStyle(Palette.detail)
						}
						AssetClassTag(assetClass: h.assetClass)
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
				Text(h.purchasePrice.map { Format.purchasePrice($0) } ?? "").monospacedDigit()
			}
			.width(min: 80, ideal: 110)
			.alignment(.trailing)
			TableColumn("Last quote") { h in
				VStack(alignment: .trailing, spacing: 2) {
					Text(h.quote.map { Format.price($0) } ?? "").monospacedDigit()
					if let day = oldQuoteDays[h.id] { TintedText(text: Format.day(day), tint: Palette.warning).font(.callout) }
				}
			}
			.width(min: 80, ideal: 110)
			.alignment(.trailing)
			TableColumn("Value") { h in
				if let value = h.value(in: currency(of: h)) { AmountText(money: value).fontWeight(.semibold) }
			}
			.width(min: 90, ideal: 120)
			.alignment(.trailing)
			TableColumn("Profit/Loss") { h in
				if let gain = h.gain(in: currency(of: h)) {
					// The color and the sign say profit or loss, so the row needs no word for it. A text that shows zero has
					// neither, so "0,00 %" below "+0,01 €" has no color.
					VStack(alignment: .trailing, spacing: 2) {
						TintedText(text: Format.gain(gain.amount), tint: tint(Format.gainSign(gain.amount))).monospacedDigit()
						if let percent = gain.percent {
							TintedText(text: Format.gainPercent(percent), tint: tint(Format.gainSign(percent: percent))).font(.callout).monospacedDigit()
						}
					}
				}
			}
			.width(min: 100, ideal: 130)
			.alignment(.trailing)
		}
		.tableStyle(.bordered(alternatesRowBackgrounds: false))
		// On the table and not on its rows. The table hands over the clicked or selected positions.
		.contextMenu(forSelectionType: UUID.self) { ids in
			let positions = rows.filter { ids.contains($0.id) }
			if !positions.isEmpty { AssetClassMenu(positions: positions) }
		}
	}

	private func tint(_ sign: Format.GainSign?) -> Color? {
		switch sign {
		case .profit: Palette.green
		case .loss: Palette.red
		case nil: nil
		}
	}

	private func currency(of h: Holding) -> String {
		model.ledger.account(h.accountID)?.currency ?? h.marketValue?.currency ?? "EUR"
	}
}

/// The asset class of a position as a small tag next to its ISIN.
struct AssetClassTag: View {
	let assetClass: AssetClass

	var body: some View {
		Text(assetClass.name)
			.font(.caption)
			.foregroundStyle(Palette.detail)
			.padding(.horizontal, 5)
			.padding(.vertical, 1)
			.background(.quaternary, in: .capsule)
			.fixedSize()
	}
}

/// A text in a color of its own, such as a profit in green. A selected table row shows it in the color of the row text,
/// where the color would be hard to read on the accent color, as `AmountText` does with a negative amount.
struct TintedText: View {
	let text: String
	let tint: Color?
	@Environment(\.backgroundProminence) private var prominence

	var body: some View {
		Text(text).foregroundStyle(tint.flatMap { prominence == .increased ? nil : AnyShapeStyle($0) } ?? AnyShapeStyle(.primary))
	}
}

/// The submenu "Asset Class" of the selected positions: "Automatic" and the eight classes, with a mark at the user's
/// choice that all of them share, or at "Automatic" when none of them has a choice.
struct AssetClassMenu: View {
	@Environment(AppModel.self) private var model
	let positions: [Holding]

	var body: some View {
		let ids = Set(positions.map(\.id))
		let choices = Set(positions.map(\.userAssetClass))
		// Nil when the positions differ, so no entry has a mark.
		let shared: AssetClass?? = choices.count == 1 ? choices.first : nil
		Menu("Asset Class") {
			Toggle("Automatic", isOn: chosen(shared == .some(nil)) { model.setAssetClass(nil, of: ids) })
			Divider()
			ForEach(AssetClass.allCases, id: \.self) { c in
				Toggle(c.name, isOn: chosen(shared == .some(c)) { model.setAssetClass(c, of: ids) })
			}
		}
	}

	/// A mark that chooses its entry on every click, also on a marked one, as a menu item does.
	private func chosen(_ isMarked: Bool, choose: @escaping () -> Void) -> Binding<Bool> {
		Binding(get: { isMarked }, set: { _ in choose() })
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
		let firstRowCurrency = model.ledger.sumCurrency(of: shown, portfolios: model.selectedPortfolios ?? [])
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
