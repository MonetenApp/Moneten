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
	/// The width that a classic scroll bar takes from the table, which the header leaves free at its right end.
	@State private var scrollerInset: CGFloat = 0

	var body: some View {
		let all = model.ledger.holdings(of: accountIDs)
		// The search and the filter "Asset class" of the key, as for the transaction table. The parent starts this view
		// over for a new search or class, instead of removing shown rows in place. A new order of the header starts the
		// table over too: `AppModel.sortPositions(by:)`.
		let filtered = key.filter.positions(of: all)
		let ledger = model.ledger
		let rows = model.portfolioSort?.sorted(filtered) { ledger.positionCurrency(of: $0) } ?? filtered
		VStack(spacing: 0) {
			HoldingsFilterBar(entries: AssetClass.entries(of: all))
			HoldingsHeader(trailingInset: scrollerInset)
			// The table stays also without rows, with the empty state on top. The rows keep their IDs across a
			// refresh, so a refresh updates them in place. A refresh that drops a shown position starts the table
			// over (#135, #151), with the placeholder of `AppModel.replacingTable` in between.
			Group {
				if holds {
					Color.clear
				} else {
					// The days compare with every position of the portfolio, also those that the filters hide.
					HoldingsTable(key: key, rows: rows, oldQuoteDays: Holding.oldQuoteDays(in: all), selection: guardedSelection) { width in
						if scrollerInset != width { scrollerInset = width }
					}
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
		// The label of the first filter starts at the inset of the rows, after the 6 points of its hover highlight.
		.padding(.leading, PositionColumns.inset - 6)
		.padding(.trailing, 10)
		.padding(.vertical, 6)
		.background(Palette.filterBar)
	}
}

/// The widths of the columns of the positions, which the table and `HoldingsHeader` share, so that the header stays in
/// line with the cells at every width. Only "Name" grows. The measures are those of the draft that the owner approved
/// on 27 November 2026 (design of `refine-portfolio-view`).
@MainActor
enum PositionColumns {
	/// Where the text of the rows, of the header, and of the filter bar starts.
	static let inset: CGFloat = 20
	/// The table starts the first cell this far from the edge of the row, `DateCell.cellInset`.
	static let cellInset: CGFloat = DateCell.cellInset
	/// The gap that the table leaves between two cells.
	static let gap: CGFloat = 2 * RowChrome.halfGap
	/// The day over the ribbon. The name then starts 108 points from the edge, as in the draft.
	static let quoteDay: CGFloat = 85
	static let quantity: CGFloat = 70
	static let prices: CGFloat = 104
	/// The value over the profit or loss, with the 14 points that bring its end 20 points from the right edge.
	static let value: CGFloat = 146
	static let trailing: CGFloat = 14
	/// The space of the cells: 9 points above the first line and 10 below the second, less the 4 that the table leaves.
	static let top: CGFloat = 9 - RowChrome.inset
	static let bottom: CGFloat = 10 - RowChrome.inset
	static let lineGap: CGFloat = 6
}

/// The header of the positions in two lines, above the table, whose own header has only one. A click on a line sorts the
/// list by its value, a second click reverses it, and the line shows the direction.
struct HoldingsHeader: View {
	@Environment(AppModel.self) private var model
	/// The width of a classic scroll bar, which the table loses at its right end and the header must lose too.
	let trailingInset: CGFloat

	var body: some View {
		HStack(alignment: .top, spacing: PositionColumns.gap) {
			line(.quoteDay, "Quote date", primary: true)
				.padding(.leading, PositionColumns.inset - PositionColumns.cellInset)
				.frame(width: PositionColumns.quoteDay, alignment: .leading)
			line(.name, "Name", primary: true)
				.frame(maxWidth: .infinity, alignment: .leading)
			line(.quantity, "Quantity", primary: true)
				.frame(width: PositionColumns.quantity, alignment: .trailing)
			VStack(alignment: .trailing, spacing: 1) {
				line(.purchasePrice, "Purchase price", primary: true)
				line(.lastQuote, "Last quote", primary: false)
			}
			.frame(width: PositionColumns.prices, alignment: .trailing)
			VStack(alignment: .trailing, spacing: 1) {
				line(.value, "Value", primary: true)
				line(.gain, "Profit/Loss", primary: false)
			}
			.padding(.trailing, PositionColumns.trailing)
			.frame(width: PositionColumns.value, alignment: .trailing)
		}
		.font(.system(size: 10.5))
		.padding(.horizontal, PositionColumns.cellInset)
		.padding(.trailing, trailingInset)
		.padding(.vertical, 5)
		.frame(maxWidth: .infinity)
		// The table draws the line below the header. The header stands on the background of the table.
		.background(Color(nsColor: .controlBackgroundColor))
		.overlay(alignment: .top) { RowChrome.separator.frame(height: 1) }
	}

	/// One line of the header: the first line of a column in the color of the second lines of the rows, the second one
	/// lighter, as in the draft. The mark of the order stands right of the text, in the gap to the next column, so the
	/// text keeps its place.
	private func line(_ key: PortfolioSort.Key, _ title: LocalizedStringKey, primary: Bool) -> some View {
		let sort = model.portfolioSort
		let marked = sort?.key == key
		return Button {
			Task { await model.sortPositions(by: key) }
		} label: {
			Text(title)
				.fontWeight(primary ? .medium : .regular)
				.foregroundStyle(primary ? Palette.detail : AnyShapeStyle(.secondary))
				.lineLimit(1)
				.fixedSize()
				.overlay(alignment: .trailing) {
					if marked, let sort {
						Image(systemName: sort.isAscending ? "chevron.up" : "chevron.down")
							.font(.system(size: 7, weight: .bold))
							.foregroundStyle(Palette.detail)
							.fixedSize()
							.offset(x: 10)
					}
				}
				.contentShape(Rectangle())
		}
		.buttonStyle(.plain)
		.accessibilityAddTraits(marked ? .isSelected : [])
		.accessibilityValue(marked ? (sort?.isAscending == true ? Text("Ascending") : Text("Descending")) : Text(verbatim: ""))
	}
}

/// The rows of the positions in five columns of two lines each, without the header of the table: `HoldingsHeader` draws
/// it. The model comes from the table to every cell: AppKit can build a cell outside the environment of the window.
struct HoldingsTable: View {
	@Environment(AppModel.self) private var model
	let key: TableKey
	let rows: [Holding]
	/// The day of each quote that is older than the newest of its portfolio: `Holding.oldQuoteDays(in:)`.
	let oldQuoteDays: [UUID: Day]
	@Binding var selection: Set<UUID>
	/// Takes the width of a classic scroll bar for the header.
	let scrollerWidth: @MainActor (CGFloat) -> Void

	var body: some View {
		let ledger = model.ledger
		Table(rows, selection: $selection) {
			TableColumn("Quote date") { h in
				QuoteDayCell(holding: h, isOld: oldQuoteDays[h.id] != nil).positionCell(alignment: .topLeading)
			}
			.width(PositionColumns.quoteDay)
			TableColumn("Name") { h in
				NameCell(security: h.security).positionCell(alignment: .topLeading)
			}
			.width(min: 160, ideal: 360)
			TableColumn("Quantity") { h in
				VStack(alignment: .trailing, spacing: PositionColumns.lineGap) {
					Text(Format.quantity(h)).monospacedDigit().lineLimit(1)
					Text(Format.quantityUnit(h)).font(.system(size: 10.5)).foregroundStyle(.secondary).lineLimit(1)
				}
				.positionCell(alignment: .topTrailing)
			}
			.width(PositionColumns.quantity)
			TableColumn("Purchase price") { h in
				VStack(alignment: .trailing, spacing: PositionColumns.lineGap) {
					Text(h.purchasePrice.map { Format.purchasePrice($0) } ?? " ").monospacedDigit().foregroundStyle(Palette.detail).lineLimit(1)
					TintedText(text: h.quote.map { Format.price($0) } ?? "", tint: oldQuoteDays[h.id] == nil ? nil : Palette.warning).monospacedDigit().lineLimit(1)
				}
				.positionCell(alignment: .topTrailing)
			}
			.width(PositionColumns.prices)
			TableColumn("Value") { h in
				ValueCell(value: h.value(in: ledger.positionCurrency(of: h)), gain: h.gain(in: ledger.positionCurrency(of: h)))
					.padding(.trailing, PositionColumns.trailing)
					.positionCell(alignment: .topTrailing)
			}
			.width(PositionColumns.value)
		}
		.tableStyle(.bordered(alternatesRowBackgrounds: false))
		.tableColumnHeaders(.hidden)
		// On the table and not on its rows. The table hands over the clicked or selected positions.
		.contextMenu(forSelectionType: UUID.self) { ids in
			let positions = rows.filter { ids.contains($0.id) }
			if !positions.isEmpty { AssetClassMenu(positions: positions) }
		}
		// A plain click opens a position and a second one closes it, behind the table and not on its rows.
		.background(PositionClicks(click: { [model, key, rows] row in
			if rows.indices.contains(row) { model.clickPosition(rows[row].id, in: key) }
		}, scrollerWidth: scrollerWidth))
	}
}

extension View {
	/// The frame and the line below a cell of a position, as `rowChrome` gives a cell of a transaction.
	fileprivate func positionCell(alignment: Alignment) -> some View {
		font(.system(size: 11.5))
			.padding(.top, PositionColumns.top)
			.padding(.bottom, PositionColumns.bottom)
			.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment)
			.background { RowChrome(pending: false) }
			.listRowSeparator(.hidden)
	}
}

/// The day of the last quote over the ribbon of the asset class. An old day shows in the warning color.
struct QuoteDayCell: View {
	let holding: Holding
	let isOld: Bool

	var body: some View {
		VStack(alignment: .leading, spacing: PositionColumns.lineGap) {
			TintedText(text: holding.quote?.day.map { Format.day($0) } ?? " ", tint: isOld ? Palette.warning : nil, base: Palette.detail)
				.monospacedDigit()
				.padding(.leading, PositionColumns.inset - PositionColumns.cellInset)
			// The ribbon starts at the edge of the row and reaches into the gap before the name. As an overlay it leaves the
			// cell as wide as its column, as the category ribbon of a transaction does.
			Color.clear
				.frame(height: AssetClassRibbon.height)
				.overlay(alignment: .leading) { AssetClassRibbon(assetClass: holding.assetClass).padding(.leading, -PositionColumns.cellInset) }
		}
	}
}

/// The name in bold over the ISIN and the WKN, each only when the source sends it.
///
/// The comment line of an open position goes below these two lines (#611, design of `refine-portfolio-view`): after a
/// gap of 7 points, a speech bubble and the comment, with a negative trailing padding as wide as the columns to the right
/// of this one, so the text runs to the end of the row. `AppModel.openedPosition` says which position is open.
struct NameCell: View {
	let security: Security

	var body: some View {
		VStack(alignment: .leading, spacing: PositionColumns.lineGap) {
			Text(security.name).font(.system(size: 12.5, weight: .bold)).lineLimit(1)
			HStack(spacing: 10) {
				if let isin = security.isin { number("ISIN", isin) }
				if let wkn = security.securityNumber { number("WKN", wkn) }
			}
			.lineLimit(1)
		}
	}

	private func number(_ label: LocalizedStringKey, _ value: String) -> some View {
		HStack(spacing: 3) {
			Text(label).foregroundStyle(.secondary)
			Text(value).foregroundStyle(Palette.detail)
		}
		.fixedSize()
	}
}

/// The value in semibold over the profit or loss as "amount · percent". The color and the sign say profit or loss, so
/// the row needs no word for it. A text that shows zero has neither, so "0,00 %" next to "+0,01 €" has no color.
struct ValueCell: View {
	let value: Money?
	let gain: Holding.Gain?

	var body: some View {
		VStack(alignment: .trailing, spacing: PositionColumns.lineGap - 1) {
			if let value { AmountText(money: value).font(.system(size: 14, weight: .semibold)).lineLimit(1) } else { Text(verbatim: " ").font(.system(size: 14)) }
			if let gain {
				HStack(spacing: 0) {
					TintedText(text: Format.gain(gain.amount), tint: Self.tint(Format.gainSign(gain.amount)))
					if let percent = gain.percent {
						Text(verbatim: " · ").foregroundStyle(.secondary)
						TintedText(text: Format.gainPercent(percent), tint: Self.tint(Format.gainSign(percent: percent)))
					}
				}
				.font(.system(size: 10.5))
				.monospacedDigit()
				.lineLimit(1)
			}
		}
	}

	private static func tint(_ sign: Format.GainSign?) -> Color? {
		switch sign {
		case .profit: Palette.green
		case .loss: Palette.red
		case nil: nil
		}
	}
}

/// The asset class of a position as a ribbon from the edge of the row, in the color of the class with white text, as the
/// category of a transaction shows.
struct AssetClassRibbon: View {
	static let height: CGFloat = 16
	let assetClass: AssetClass

	var body: some View {
		Text(assetClass.name.uppercased())
			.font(.system(size: 9, weight: .bold))
			.kerning(0.45)
			.foregroundStyle(.white)
			.lineLimit(1)
			.padding(.leading, PositionColumns.inset)
			.padding(.trailing, 9)
			.frame(width: PositionColumns.cellInset + PositionColumns.quoteDay + 1, height: Self.height, alignment: .leading)
			.background(AssetClassColors.color(of: assetClass), in: RibbonShape())
			.fixedSize()
			.accessibilityLabel(assetClass.name)
	}
}

extension Ledger {
	/// The currency in which a position shows its value and its profit or loss, and by which it sorts: the currency of its account.
	func positionCurrency(of h: Holding) -> String {
		account(h.accountID)?.currency ?? h.marketValue?.currency ?? "EUR"
	}
}

/// Hands each plain click on a row of the table next to it to `click`, with the row, and the width that a classic scroll
/// bar takes from the table to `scrollerWidth`. The table reports no click on a row that is selected already, which a
/// second click on an open position is, so `PositionClickWatcher` reads the clicks of the window before the table gets them.
struct PositionClicks: NSViewRepresentable {
	let click: @MainActor (Int) -> Void
	let scrollerWidth: @MainActor (CGFloat) -> Void

	func makeNSView(context: Context) -> PositionClickWatcher {
		let watcher = PositionClickWatcher()
		watcher.click = click
		watcher.scrollerWidth = scrollerWidth
		watcher.monitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak watcher] event in
			MainActor.assumeIsolated { watcher?.handle(event) }
			return event
		}
		return watcher
	}

	func updateNSView(_ watcher: PositionClickWatcher, context: Context) {
		watcher.click = click
		watcher.scrollerWidth = scrollerWidth
	}

	static func dismantleNSView(_ watcher: PositionClickWatcher, coordinator: ()) { watcher.stop() }
}

/// A view without content behind the table of positions, with the frame of the table. It watches the clicks of its window
/// and the scroll bar of its table. The debug harness finds it by its class and hands it its click, because a click that
/// the harness sends never passes the monitor of the window.
final class PositionClickWatcher: NSView {
	var click: @MainActor (Int) -> Void = { _ in }
	var scrollerWidth: @MainActor (CGFloat) -> Void = { _ in }
	var monitor: Any?
	/// Found once, so a click costs no search through the views of the window.
	private weak var table: NSTableView?
	private var observers: [NSObjectProtocol] = []
	private var reportedWidth: CGFloat?

	/// A plain click inside the table opens or closes the position of its row. A click with ⌘, ⇧, ⌃, or ⌥ changes only the
	/// selection or opens the context menu, so it opens nothing, and neither does a double click or a click on a scroll bar.
	func handle(_ event: NSEvent) {
		guard event.window === window, event.clickCount == 1, event.modifierFlags.intersection([.command, .shift, .control, .option]).isEmpty,
			bounds.contains(convert(event.locationInWindow, from: nil)), let table = tableView() else { return }
		var hit = window?.contentView?.hitTest(event.locationInWindow)
		while let view = hit {
			if view is NSScroller { return }
			hit = view.superview
		}
		let point = table.convert(event.locationInWindow, from: nil)
		guard table.visibleRect.contains(point) else { return }
		let row = table.row(at: point)
		if row >= 0 { click(row) }
	}

	override func viewDidMoveToWindow() {
		super.viewDidMoveToWindow()
		// SwiftUI adds the table next to this view in the same update, so it is there a turn later.
		DispatchQueue.main.async { [weak self] in self?.watchScroller() }
	}

	override func setFrameSize(_ newSize: NSSize) {
		super.setFrameSize(newSize)
		reportScroller()
	}

	func stop() {
		if let monitor { NSEvent.removeMonitor(monitor) }
		monitor = nil
		observers.forEach(NotificationCenter.default.removeObserver)
		observers = []
	}

	/// A classic scroll bar, which a Mac with a mouse shows by default, comes and goes with the rows and narrows the clip
	/// view of the table, and the user can change the style of the scroll bars at any time.
	private func watchScroller() {
		guard window != nil, observers.isEmpty, let clip = tableView()?.enclosingScrollView?.contentView else { return }
		clip.postsFrameChangedNotifications = true
		let report: @Sendable (Notification) -> Void = { [weak self] _ in MainActor.assumeIsolated { self?.reportScroller() } }
		observers = [
			NotificationCenter.default.addObserver(forName: NSView.frameDidChangeNotification, object: clip, queue: .main, using: report),
			NotificationCenter.default.addObserver(forName: NSScroller.preferredScrollerStyleDidChangeNotification, object: nil, queue: .main, using: report),
		]
		reportScroller()
	}

	/// The width that the scroll bar takes from the table: the scroll view less its clip view, 0 for an overlay scroll bar.
	private func reportScroller() {
		guard let scroll = table?.enclosingScrollView else { return }
		let width = max(0, scroll.frame.width - scroll.contentView.frame.width - 2 * scroll.contentView.frame.minX)
		guard width != reportedWidth else { return }
		reportedWidth = width
		// After the layout of AppKit, not inside it, because the width changes the state of a SwiftUI view.
		DispatchQueue.main.async { [weak self] in self?.scrollerWidth(width) }
	}

	private func tableView() -> NSTableView? {
		if let table { return table }
		table = Self.table(near: self)
		return table
	}

	/// The table of the positions: the table whose scroll view covers the middle of this view, which stands behind the
	/// table with the same frame. The first table around this view can be another one, such as the list of the sidebar.
	private static func table(near view: NSView) -> NSTableView? {
		guard let root = view.window?.contentView else { return nil }
		let middle = view.convert(NSPoint(x: view.bounds.midX, y: view.bounds.midY), to: nil)
		func find(in v: NSView) -> NSTableView? {
			if let t = v as? NSTableView, let scroll = t.enclosingScrollView, scroll.convert(scroll.bounds, to: nil).contains(middle) { return t }
			for sub in v.subviews { if let t = find(in: sub) { return t } }
			return nil
		}
		return find(in: root)
	}
}

/// A text in a color of its own, such as a profit in green. A selected table row shows it in the color of the row text,
/// where the color would be hard to read on the accent color, as `AmountText` does with a negative amount.
struct TintedText: View {
	let text: String
	let tint: Color?
	/// The style without a tint.
	var base = AnyShapeStyle(.primary)
	@Environment(\.backgroundProminence) private var prominence

	var body: some View {
		Text(text).foregroundStyle(tint.flatMap { prominence == .increased ? nil : AnyShapeStyle($0) } ?? base)
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
