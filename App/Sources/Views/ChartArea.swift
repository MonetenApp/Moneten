import Domain
import SwiftUI

struct ChartArea: View {
	@Environment(AppModel.self) private var model
	let rows: [Transaction]

	var body: some View {
		switch (model.viewMode, model.selection) {
		case (.pieChart, _):
			CategoryPie(rows: rows)
		case (.barChart, .category?):
			// After a click on a bar, the list shows that bar and the chart keeps all of them.
			CategoryBars(rows: model.filter.period == model.chartRange ? rows : model.chartTransactions)
		case let (.barChart, .account(id)?):
			BalanceChart(accountIDs: [id])
		case let (.barChart, .group(id)?):
			let ids = model.ledger.accountIDs(inGroupTree: id)
			// As in MoneyMoney: a group with an account without transactions draws no chart and names
			// that account. A portfolio has no transactions by nature, and a closed account is not drawn.
			if let empty = model.ledger.accounts.first(where: {
				ids.contains($0.id) && !$0.isClosed && $0.kind != .portfolio && !model.ledger.accountsWithTransactions.contains($0.id)
			}) {
				Text("The account “\(empty.name)” has no transactions; no bar chart.")
					.foregroundStyle(Palette.bandLabel)
					.frame(maxWidth: .infinity, maxHeight: .infinity)
			} else {
				BalanceChart(accountIDs: ids)
			}
		default:
			EmptyView()
		}
	}
}

struct BalanceChart: View {
	@Environment(AppModel.self) private var model
	let accountIDs: Set<UUID>
	/// The currency the user picked for a group with accounts in several currencies.
	@State private var picked: String?

	var body: some View {
		@Bindable var model = model
		let accounts = accountIDs.compactMap { model.ledger.account($0) }.filter { !$0.isClosed }
		let currencies = ChartCurrency.ranked(accounts.map(\.currency))
		let currency = ChartCurrency.current(currencies, picked: picked)
		let shown = accounts.filter { $0.currency == currency }
		let monthly = model.balanceMode == .monthlyAverage
		VStack(alignment: .trailing, spacing: 4) {
			HStack {
				portfolioCaption(shown.filter { $0.kind == .portfolio }, currency: currency)
				Spacer(minLength: 0)
				ChartCurrency.Picker(currencies: currencies, current: currency, picked: $picked)
			}
			HStack(alignment: .bottom, spacing: 8) {
				bars(ids: Set(shown.map(\.id)), currency: currency, monthly: monthly)
				ChartModeSwitch(selection: $model.balanceMode, options: [
					.init(value: .daily, label: "D", help: "Daily balance"),
					.init(value: .monthlyAverage, label: "M", help: "Monthly average balance"),
				])
			}
		}
	}

	/// Portfolios count in the bars from their first recorded value on, so the chart names that day.
	/// A portfolio without any record is left out of the bars, and the chart says how much that is.
	@ViewBuilder
	private func portfolioCaption(_ portfolios: [Account], currency: String) -> some View {
		let first = portfolios.compactMap { model.ledger.portfolioValues(of: $0.id).first?.day }.min()
		let unrecorded = portfolios.filter { model.ledger.portfolioValues(of: $0.id).isEmpty }
		let leftOut = Money(minorUnits: unrecorded.reduce(0) { $0 + model.ledger.balance(of: $1).minorUnits }, currency: currency)
		let parts = [first.map { "Portfolios from \(Format.day($0))" }, unrecorded.isEmpty ? nil : "Portfolios not shown: \(Format.money(leftOut))"]
		let text = parts.compactMap { $0 }.joined(separator: " · ")
		if !text.isEmpty {
			Text(text)
				.font(.callout)
				.foregroundStyle(Palette.bandLabel)
				.help("The bars count a portfolio from its first recorded value on. A portfolio without a recorded value is not in the bars. The total above counts every portfolio.")
		}
	}

	@ViewBuilder
	private func bars(ids: Set<UUID>, currency: String, monthly: Bool) -> some View {
		let bars = Self.stripBars(model.ledger, ids: ids, range: model.chartRange, currency: currency, monthly: monthly)
		if bars.isEmpty {
			let portfoliosOnly = !ids.isEmpty && ids.allSatisfy { model.ledger.account($0)?.kind == .portfolio }
			Text(portfoliosOnly ? "No portfolio items; no bar chart." : "No transactions; no bar chart.")
				.foregroundStyle(.secondary)
				.frame(maxWidth: .infinity, maxHeight: .infinity)
		} else {
			// As in MoneyMoney: a bar of 4 points and a gap of 2 for each day or month, white on the band, and red below zero.
			ScrollingBarChart(bars: bars, style: .separators, barWidth: 4, gap: 2, positive: Palette.bandBar, negative: Palette.red) { bar in
				model.select(bar: PeriodChoice(bar: BalanceBar(start: bar.start, end: bar.end, minorUnits: bar.money.minorUnits), monthly: monthly))
			}
			// A new view or period starts again at its newest bar. A click on a bar changes only the
			// period of the list, not `chartRange`, so the other bars stay where they are.
			.id([AnyHashable(ids), AnyHashable(monthly), AnyHashable(currency), AnyHashable(model.chartRange)])
		}
	}

	/// One bar for each day, or each month with its average balance. A line marks each month, or
	/// each year, with its name.
	static func stripBars(_ ledger: Ledger, ids: Set<UUID>, range: DayRange, currency: String, monthly: Bool) -> [StripBar] {
		if monthly {
			return ledger.monthlyAverageBalances(accountIDs: ids, range: range).map { point in
				let first = point.day.month == 1
				return StripBar(start: point.day, end: point.day.adding(months: 1), money: Money(minorUnits: point.minorUnits, currency: currency),
					title: Format.monthTitle(point.day) + ", average", label: first ? String(point.day.year) : nil, startsGroup: first)
			}
		}
		return ledger.balanceBars(accountIDs: ids, range: range).map { bar in
			let first = bar.start.day == 1
			return StripBar(start: bar.start, end: bar.end, money: Money(minorUnits: bar.minorUnits, currency: currency),
				title: Format.day(bar.start), label: first ? Format.shortMonth(bar.start) : nil, startsGroup: first)
		}
	}
}

struct CategoryBars: View {
	@Environment(AppModel.self) private var model
	let rows: [Transaction]
	@State private var picked: String?

	var body: some View {
		@Bindable var model = model
		let currencies = ChartCurrency.ranked(rows.map(\.currency))
		let currency = ChartCurrency.current(currencies, picked: picked)
		let sums = model.ledger.periodSums(of: ChartCurrency.rows(rows, in: currency, of: currencies), period: model.chartPeriod)
		VStack(alignment: .trailing, spacing: 4) {
			ChartCurrency.Picker(currencies: currencies, current: currency, picked: $picked)
			HStack(alignment: .bottom, spacing: 8) {
				bars(sums, currency: currency)
				ChartModeSwitch(selection: $model.chartPeriod, options: [
					.init(value: .month, label: "M", help: "Monthly view"),
					.init(value: .quarter, label: "Q", help: "Quarterly view"),
					.init(value: .year, label: "Y", help: "Yearly view"),
				])
			}
		}
	}

	@ViewBuilder
	private func bars(_ sums: [PeriodSum], currency: String) -> some View {
		if sums.isEmpty {
			Text("No transactions; no bar chart.").foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
		} else {
			// As in MoneyMoney: one bar of 40 points for each period with the sum of its
			// transactions, in the color of the category, darker below zero.
			let color = categoryColor
			ScrollingBarChart(bars: Self.stripBars(sums, period: model.chartPeriod, currency: currency, through: model.chartRange.end),
				style: .centered, barWidth: 40, gap: 8, positive: color, negative: color.mix(with: .black, by: 0.3)) { bar in
				model.select(bar: PeriodChoice(start: bar.start, chartPeriod: model.chartPeriod))
			}
			.id([AnyHashable(model.selection), AnyHashable(model.chartPeriod), AnyHashable(currency), AnyHashable(model.chartRange)])
		}
	}

	/// The color of the selected category, as in the sidebar.
	private var categoryColor: Color {
		guard case let .category(id) = model.selection, let c = model.ledger.category(id) else { return Palette.bandBar }
		return CategoryColors.color(of: c, in: model.ledger)
	}

	/// One bar for each period from the first with transactions to the current one, or to the end of
	/// the chosen period: a period without transactions shows a line at zero, as in MoneyMoney.
	static func stripBars(_ sums: [PeriodSum], period: ChartPeriod, currency: String, through end: Day?) -> [StripBar] {
		PeriodSum.continuous(sums, period: period, through: min(end ?? Day.today(), Day.today())).map { sum in
			let label = Format.periodLabel(sum.start, period: period)
			return StripBar(start: sum.start, end: period.next(sum.start), money: Money(minorUnits: sum.total, currency: currency),
				title: label, label: label, startsGroup: false)
		}
	}
}

/// Amounts in different currencies do not add up, so a chart shows one currency at a time: first
/// the one of most accounts or rows, and the others through a picker.
enum ChartCurrency {
	/// The currencies, the most frequent first.
	static func ranked(_ currencies: [String]) -> [String] {
		let counts = Dictionary(grouping: currencies, by: { $0 }).mapValues(\.count)
		return counts.keys.sorted { (counts[$0]!, $1) > (counts[$1]!, $0) }
	}

	static func current(_ ranked: [String], picked: String?) -> String {
		picked.flatMap { ranked.contains($0) ? $0 : nil } ?? ranked.first ?? "EUR"
	}

	/// The rows in the shown currency. A view in one currency keeps its rows as they are.
	static func rows(_ rows: [Transaction], in currency: String, of ranked: [String]) -> [Transaction] {
		ranked.count > 1 ? rows.filter { $0.currency == currency } : rows
	}

	struct Picker: View {
		let currencies: [String]
		let current: String
		@Binding var picked: String?

		var body: some View {
			if currencies.count > 1 {
				SwiftUI.Picker("Currency", selection: Binding(get: { current }, set: { picked = $0 })) {
					ForEach(currencies, id: \.self) { Text($0).help("Amounts in \($0)").tag($0) }
				}
				.pickerStyle(.segmented)
				.labelsHidden()
				.fixedSize()
			}
		}
	}
}

struct CategoryPie: View {
	@Environment(AppModel.self) private var model
	let rows: [Transaction]
	@State private var picked: String?

	var body: some View {
		let currencies = ChartCurrency.ranked(rows.map(\.currency))
		let currency = ChartCurrency.current(currencies, picked: picked)
		let slices = Self.slices(of: ChartCurrency.rows(rows, in: currency, of: currencies), in: model)
		GeometryReader { geometry in
			if slices.withdrawals.isEmpty, slices.deposits.isEmpty {
				Text("No transactions; no pie chart.").foregroundStyle(Palette.bandLabel).frame(maxWidth: .infinity, maxHeight: .infinity)
			} else {
				// Each pie takes half the width up to its own, and the outer labels use what is left at the edges.
				let width = min(PieChart.width, geometry.size.width / 2)
				let outerRoom = PieChart.innerRoom(width: width) + (geometry.size.width - 2 * width) / 2
				HStack(spacing: 0) {
					PieChart(title: "Withdrawals", empty: "No withdrawals", slices: slices.withdrawals, outside: .leading, width: width, outerRoom: outerRoom)
					PieChart(title: "Deposits", empty: "No deposits", slices: slices.deposits, outside: .trailing, width: width, outerRoom: outerRoom)
				}
				.frame(maxWidth: .infinity, maxHeight: .infinity)
			}
		}
		.clipped()
		.overlay(alignment: .topTrailing) {
			ChartCurrency.Picker(currencies: currencies, current: currency, picked: $picked)
		}
	}

	/// The categories of the view, or the subcategories of the selected category, split into
	/// withdrawals and deposits. The rows are in one currency.
	static func slices(of rows: [Transaction], in model: AppModel) -> (withdrawals: [PieSlice], deposits: [PieSlice]) {
		let parent: UUID? = { if case let .category(id) = model.selection, !model.ledger.childCategories(of: id).isEmpty { return id }; return nil }()
		let totals = model.ledger.categoryTotals(of: rows, below: parent)
		let currency = rows.first?.currency ?? "EUR"
		func slice(_ category: Domain.Category, _ minorUnits: Int64) -> PieSlice {
			PieSlice(id: category.id, name: category.name, money: Money(minorUnits: abs(minorUnits), currency: currency),
				color: CategoryColors.color(of: category, in: model.ledger))
		}
		return (totals.filter { $0.minorUnits < 0 }.map { slice($0.category, $0.minorUnits) },
			totals.filter { $0.minorUnits > 0 }.map { slice($0.category, $0.minorUnits) })
	}
}

struct PieSlice: Identifiable {
	let id: UUID
	let name: String
	let money: Money
	let color: Color
	var value: Double { Format.chartValue(money.minorUnits, money.currency) }
}

/// One pie of `CategoryPie`, as MoneyMoney draws it: a full pie in a rim, each slice named outside
/// with a line from its middle. Under the pointer, the slice stands out and the text below the pie
/// names its category, amount, and share. The pointer lives here, so moving it does not sum the rows again.
struct PieChart: View {
	let title: String
	/// What the pie says when it has no slices, such as "No deposits".
	let empty: String
	let slices: [PieSlice]
	/// The side away from the other pie, where the labels have room up to the edge of the chart.
	let outside: HorizontalEdge
	let width: CGFloat
	/// The width of a label on the outer side.
	let outerRoom: CGFloat
	@State private var hovered: PieSlice.ID?

	/// `hovered` presets the slice under the pointer, for a snapshot of the debug harness.
	init(title: String, empty: String, slices: [PieSlice], outside: HorizontalEdge, width: CGFloat = PieChart.width, outerRoom: CGFloat = 120,
		hovered: PieSlice.ID? = nil) {
		self.title = title
		self.empty = empty
		self.slices = slices
		self.outside = outside
		self.width = width
		self.outerRoom = min(outerRoom, 120)
		_hovered = State(initialValue: hovered)
	}

	// As in MoneyMoney: a pie of 110 points in a rim of 6. MoneyMoney puts the middles of its pies 225
	// points apart; 300 leave the labels between the two pies room for a name.
	private static let radius: CGFloat = 55
	private static let outerRadius: CGFloat = radius + 6
	/// The widest a pie with its labels gets. A narrow window gives it less.
	static let width: CGFloat = 300

	/// The width of a label between the two pies.
	static func innerRoom(width: CGFloat) -> CGFloat { max(0, width / 2 - lineEnd - 6) }
	/// Where the line to a label ends, beyond the rim.
	private static let lineEnd: CGFloat = outerRadius + 8
	private static let lineHeight: CGFloat = 14
	/// Slices below this share get no label, so that the labels of thin slices do not collide.
	private static let minLabelShare = 0.03

	var body: some View {
		if slices.isEmpty {
			Text(empty).foregroundStyle(Palette.bandLabel).frame(width: width).frame(maxHeight: .infinity)
		} else {
			let wedges = Self.wedges(slices)
			// A slice that is gone after the view changed under a resting pointer marks nothing.
			let active = wedges.contains { $0.id == hovered } ? hovered : nil
			GeometryReader { geometry in
				let center = CGPoint(x: geometry.size.width / 2, y: geometry.size.height / 2)
				let labels = Self.labels(wedges, center: center, height: geometry.size.height, outside: outside)
				ZStack {
					pie(wedges, center: center, active: active)
					labelViews(labels, center: center, active: active)
					if let w = wedges.first(where: { $0.id == active }) { hoverText(w, center: center) }
				}
				.contentShape(Rectangle())
				.onContinuousHover { phase in
					guard case let .active(point) = phase else { hovered = nil; return }
					hovered = Self.wedge(at: point, center: center, in: wedges)?.id
				}
			}
			.frame(width: width)
			.accessibilityElement(children: .ignore)
			.accessibilityLabel(title)
			.accessibilityValue(Self.spoken(wedges))
		}
	}

	// The body is split into these parts, because the compiler of CI could not type-check it as one expression.

	@ViewBuilder
	private func pie(_ wedges: [PieWedge], center: CGPoint, active: PieSlice.ID?) -> some View {
		Circle().fill(Palette.pieRim).frame(width: 2 * Self.outerRadius, height: 2 * Self.outerRadius).position(center)
		ZStack {
			ForEach(wedges) { w in
				Wedge(start: w.start, end: w.end).fill(w.slice.color).opacity(active == nil || active == w.id ? 1 : 0.45)
			}
		}
		.frame(width: 2 * Self.radius, height: 2 * Self.radius)
		.position(center)
		// A line in the color of the rim between the slices, which share the color of their group in its view.
		if wedges.count > 1 {
			Path { path in
				for w in wedges {
					path.move(to: center)
					path.addLine(to: CGPoint(x: center.x + Self.radius * sin(w.start), y: center.y - Self.radius * cos(w.start)))
				}
			}
			.stroke(Palette.pieRim, lineWidth: 1)
		}
	}

	@ViewBuilder
	private func labelViews(_ labels: [PieLabel], center: CGPoint, active: PieSlice.ID?) -> some View {
		Path { path in
			for l in labels {
				path.move(to: l.rim)
				path.addLine(to: CGPoint(x: center.x + (l.left ? -Self.lineEnd : Self.lineEnd), y: l.y))
			}
		}
		.stroke(Palette.onBand.opacity(0.5), lineWidth: 1)
		ForEach(labels) { l in
			let room: CGFloat = l.left == (outside == .leading) ? outerRoom : Self.innerRoom(width: width)
			let x: CGFloat = center.x + (l.left ? -1 : 1) * (Self.lineEnd + 3 + room / 2)
			Text(l.wedge.slice.name)
				.font(.system(size: 11, weight: active == l.id ? .semibold : .regular))
				.foregroundStyle(Palette.onBand)
				.lineLimit(1)
				.help(l.wedge.slice.name)
				.frame(width: room, alignment: l.left ? .trailing : .leading)
				.position(x: x, y: l.y)
		}
	}

	private func hoverText(_ w: PieWedge, center: CGPoint) -> some View {
		VStack(spacing: 1) {
			Text(w.slice.name).font(.caption.weight(.semibold)).foregroundStyle(Palette.onBand)
			HStack(spacing: 4) {
				AmountText(money: w.slice.money)
				Text(Self.percent(w.share)).foregroundStyle(Palette.bandLabel)
			}
			.font(.caption)
		}
		.lineLimit(1)
		.frame(width: 2 * Self.lineEnd)
		.position(x: center.x, y: center.y + Self.outerRadius + 20)
	}

	private static func percent(_ share: Double) -> String { share.formatted(.percent.precision(.fractionLength(0...1))) }

	private static func spoken(_ wedges: [PieWedge]) -> String {
		wedges.map { "\($0.slice.name): \(Format.money($0.slice.money)), \(percent($0.share))" }.joined(separator: "; ")
	}

	/// The slices with their angles, clockwise from the top in radians.
	private static func wedges(_ slices: [PieSlice]) -> [PieWedge] {
		let total = slices.reduce(0) { $0 + $1.value }
		var start = 0.0
		return slices.map { s in
			let share = total > 0 ? s.value / total : 1 / Double(slices.count)
			defer { start += share * 2 * .pi }
			return PieWedge(slice: s, start: start, end: start + share * 2 * .pi, share: share)
		}
	}

	private static func wedge(at point: CGPoint, center: CGPoint, in wedges: [PieWedge]) -> PieWedge? {
		let (dx, dy) = (point.x - center.x, point.y - center.y)
		guard dx * dx + dy * dy <= outerRadius * outerRadius else { return nil }
		var angle = atan2(Double(dx), Double(-dy))
		if angle < 0 { angle += 2 * .pi }
		return wedges.first { angle < $0.end } ?? wedges.last
	}

	/// A label for each slice that is not too thin, on the side of its middle, at the height of its
	/// middle where the labels of one side leave room for each other. A side keeps only as many
	/// labels as fit the height, those of the largest slices; the others show under the pointer.
	private static func labels(_ wedges: [PieWedge], center: CGPoint, height: CGFloat, outside: HorizontalEdge) -> [PieLabel] {
		let all = wedges.filter { $0.share >= minLabelShare }.map { w in
			let (dx, dy) = (CGFloat(sin(w.middle)), CGFloat(-cos(w.middle)))
			// A slice straight up or down, such as a single one, labels on the outer side, which has more room.
			let left = abs(dx) < 0.001 ? outside == .leading : dx < 0
			return PieLabel(wedge: w, rim: CGPoint(x: center.x + outerRadius * dx, y: center.y + outerRadius * dy),
				left: left, y: center.y + (outerRadius + 6) * dy)
		}
		let fitting = max(1, Int(height / lineHeight))
		func side(_ left: Bool) -> [PieLabel] {
			spaced(Array(all.filter { $0.left == left }.sorted { $0.wedge.share > $1.wedge.share }.prefix(fitting)), height: height)
		}
		return side(true) + side(false)
	}

	/// Pushes labels down until none overlaps the one above, then up from the bottom edge.
	private static func spaced(_ labels: [PieLabel], height: CGFloat) -> [PieLabel] {
		var ls = labels.sorted { $0.y < $1.y }
		for i in ls.indices {
			ls[i].y = max(ls[i].y, i == 0 ? lineHeight / 2 : ls[i - 1].y + lineHeight)
		}
		for i in ls.indices.reversed() {
			ls[i].y = min(ls[i].y, i == ls.count - 1 ? height - lineHeight / 2 : ls[i + 1].y - lineHeight)
		}
		return ls
	}
}

private struct PieWedge: Identifiable {
	let slice: PieSlice
	let start: Double
	let end: Double
	let share: Double
	var id: UUID { slice.id }
	var middle: Double { (start + end) / 2 }
}

private struct PieLabel: Identifiable {
	let wedge: PieWedge
	/// Where the line to the label starts, on the outer edge of the rim.
	let rim: CGPoint
	let left: Bool
	var y: CGFloat
	var id: UUID { wedge.id }
}

/// A slice of a pie between two angles, clockwise from the top in radians.
private struct Wedge: Shape {
	let start: Double
	let end: Double

	func path(in rect: CGRect) -> Path {
		let center = CGPoint(x: rect.midX, y: rect.midY)
		var path = Path()
		path.move(to: center)
		// In the flipped coordinates of SwiftUI, `clockwise: false` runs clockwise on the screen.
		path.addArc(center: center, radius: min(rect.width, rect.height) / 2, startAngle: .radians(start - .pi / 2),
			endAngle: .radians(end - .pi / 2), clockwise: false)
		path.closeSubpath()
		return path
	}
}

/// The switch of a chart between its modes, as MoneyMoney draws it: a column of small segments at
/// the bottom of the trailing edge of the chart, the chosen one dark.
struct ChartModeSwitch<Value: Hashable>: View {
	struct Option {
		let value: Value
		let label: String
		let help: String
	}

	@Binding var selection: Value
	let options: [Option]

	var body: some View {
		VStack(spacing: 0) {
			ForEach(options, id: \.label) { option in
				let chosen = option.value == selection
				Button { selection = option.value } label: {
					Text(option.label)
						.font(.system(size: 12, weight: .medium))
						.foregroundStyle(chosen ? Palette.switchChosenText : Palette.switchText)
						.frame(width: 22, height: 24)
						.background(chosen ? Palette.switchChosen : Palette.switchBackground)
						.contentShape(Rectangle())
				}
				.buttonStyle(.plain)
				.help(option.help)
				.accessibilityLabel(option.help)
				.accessibilityAddTraits(chosen ? .isSelected : [])
			}
		}
		.clipShape(RoundedRectangle(cornerRadius: 4))
		.overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Palette.switchBorder, lineWidth: 0.5))
		.padding(.bottom, ScrollingBarChart.bottomInset)
		.accessibilityElement(children: .contain)
	}
}
