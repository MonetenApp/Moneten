import Charts
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
			BalanceChart(accountIDs: model.ledger.accountIDs(inGroupTree: id))
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
		let accounts = accountIDs.compactMap { model.ledger.account($0) }.filter { !$0.isClosed && $0.kind != .portfolio }
		let currencies = ChartCurrency.ranked(accounts.map(\.currency))
		let currency = ChartCurrency.current(currencies, picked: picked)
		let ids = Set(accounts.filter { $0.currency == currency }.map(\.id))
		let monthly = model.balanceMode == .monthlyAverage
		VStack(alignment: .trailing, spacing: 4) {
			ChartCurrency.Picker(currencies: currencies, current: currency, picked: $picked)
			bars(ids: ids, currency: currency, monthly: monthly)
		}
	}

	private func bars(ids: Set<UUID>, currency: String, monthly: Bool) -> some View {
		GeometryReader { geometry in
			// A bar is at least 4 points wide, so long periods are averaged instead of drawn as hairlines.
			let bars = monthly
				? model.ledger.monthlyAverageBalances(accountIDs: ids, range: model.chartRange)
					.map { BalanceBar(start: $0.day, end: $0.day.adding(months: 1), minorUnits: $0.minorUnits) }
				: model.ledger.balanceBars(accountIDs: ids, range: model.chartRange, maxBars: max(1, Int(geometry.size.width / 4)))
			if bars.isEmpty {
				Text("No transactions; no bar chart.")
					.foregroundStyle(.secondary)
					.frame(maxWidth: .infinity, maxHeight: .infinity)
			} else {
				BalanceBarChart(bars: bars, currency: currency, monthly: monthly, width: geometry.size.width)
			}
		}
	}
}

/// The bars of `BalanceChart`. The pointer lives here, so moving it redraws the chart without
/// computing the bars again.
struct BalanceBarChart: View {
	@Environment(AppModel.self) private var model
	let bars: [BalanceBar]
	let currency: String
	let monthly: Bool
	let width: CGFloat
	@State private var pointer: Date?

	var body: some View {
		let hovered = pointer.flatMap { p in bars.first { $0.start.date() <= p && p < $0.end.date() } }
		// Wide bars get a gap between them. Narrow bars touch, or the gaps would hide them.
		let gap = width / CGFloat(bars.count) >= 6 ? 0.2 : 0
		// A label is about 70 points wide and starts at its mark.
		let dates = DateAxis(from: bars.first!.start, to: bars.last!.end, trailing: Double(70 / max(70, width)))
		Chart {
			ForEach(bars) { bar in
				Self.mark(bar, currency: currency, gap: gap, dimmed: hovered != nil && hovered != bar)
			}
			RuleMark(y: .value("Zero", 0))
				.lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
				.foregroundStyle(.secondary)
			if let bar = hovered {
				RuleMark(x: .value("Pointer", bar.start.date()))
					.foregroundStyle(.clear)
					.annotation(position: .top, spacing: 0, overflowResolution: .init(x: .fit(to: .chart), y: .fit(to: .chart))) {
						ChartValueLabel(title: Self.title(of: bar, monthly: monthly), value: Money(minorUnits: bar.minorUnits, currency: currency))
					}
			}
		}
		.chartXSelection(value: $pointer)
		// A click on a bar sets the period filter to its time, so the list shows its transactions.
		.onTapGesture { if let bar = hovered { model.select(bar: PeriodChoice(bar: bar, monthly: monthly)) } }
		.help("Click a bar to show its transactions")
		.chartStyle(currency: currency, amounts: AmountAxis(values: bars.map { Format.chartValue($0.minorUnits, currency) }, unit: Format.chartValue(1, currency)),
			dates: Self.dateFormat(dates.unit), marks: dates.marks.map { $0.date() })
	}

	private static func dateFormat(_ unit: DateAxis.Unit) -> Date.FormatStyle {
		switch unit {
		case .day: .dateTime.day().month(.abbreviated)
		case .month: .dateTime.month(.abbreviated).year()
		case .year: .dateTime.year()
		}
	}

	private static func mark(_ bar: BalanceBar, currency: String, gap: Double, dimmed: Bool) -> some ChartContent {
		let start = bar.start.date()
		let end = start.addingTimeInterval(bar.end.date().timeIntervalSince(start) * (1 - gap))
		return RectangleMark(xStart: .value("From", start), xEnd: .value("To", end),
			yStart: .value("Zero", 0.0), yEnd: .value("Balance", Format.chartValue(bar.minorUnits, currency)))
			.foregroundStyle(bar.minorUnits < 0 ? Color.red : Color.accentColor)
			.opacity(dimmed ? 0.45 : 1)
	}

	private static func title(of bar: BalanceBar, monthly: Bool) -> String {
		if monthly { return Format.monthTitle(bar.start) + ", average" }
		let last = bar.end.adding(days: -1)
		return last == bar.start ? Format.day(bar.start) : "\(Format.day(bar.start)) to \(Format.day(last)), average"
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
			HStack(spacing: 8) {
				ChartCurrency.Picker(currencies: currencies, current: currency, picked: $picked)
				Picker("Period", selection: $model.chartPeriod) {
					Text("M").help("Monthly view").tag(ChartPeriod.month)
					Text("Q").help("Quarterly view").tag(ChartPeriod.quarter)
					Text("Y").help("Yearly view").tag(ChartPeriod.year)
				}
				.pickerStyle(.segmented)
				.labelsHidden()
				.fixedSize()
			}
			if sums.isEmpty {
				Text("No transactions; no bar chart.").foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
			} else {
				CategoryBarChart(sums: sums, period: model.chartPeriod, currency: currency)
			}
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

/// The bars of `CategoryBars`. The pointer lives here, so moving it does not sum the rows again.
struct CategoryBarChart: View {
	@Environment(AppModel.self) private var model
	let sums: [PeriodSum]
	let period: ChartPeriod
	let currency: String
	@State private var pointer: Date?

	var body: some View {
		let hovered = pointer.flatMap { p in sums.first { period.start(of: Day(p)) == $0.start } }
		Chart {
			ForEach(sums) { s in
				BarMark(x: .value("Period", s.start.date(), unit: unit), y: .value("Deposits", Format.chartValue(s.deposits, currency)))
					.foregroundStyle(Color.green)
					.opacity(hovered == nil || hovered == s ? 1 : 0.45)
				BarMark(x: .value("Period", s.start.date(), unit: unit), y: .value("Withdrawals", Format.chartValue(s.withdrawals, currency)))
					.foregroundStyle(Color.red)
					.opacity(hovered == nil || hovered == s ? 1 : 0.45)
			}
			RuleMark(y: .value("Zero", 0))
				.lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
				.foregroundStyle(.secondary)
			if let s = hovered {
				RuleMark(x: .value("Pointer", s.start.date(), unit: unit))
					.foregroundStyle(.clear)
					.annotation(position: .top, spacing: 0, overflowResolution: .init(x: .fit(to: .chart), y: .fit(to: .chart))) {
						ChartValueLabel(title: title(of: s.start),
							value: Money(minorUnits: s.deposits, currency: currency), second: Money(minorUnits: s.withdrawals, currency: currency))
					}
			}
		}
		.chartXSelection(value: $pointer)
		.onTapGesture { if let s = hovered { model.select(bar: PeriodChoice(start: s.start, chartPeriod: period)) } }
		.help("Click a bar to show its transactions")
		.chartStyle(currency: currency, amounts: AmountAxis(values: sums.flatMap { [Format.chartValue($0.deposits, currency), Format.chartValue($0.withdrawals, currency)] },
				unit: Format.chartValue(1, currency)),
			dates: dateAxis.format, values: dateAxis.values, marks: sums.count <= 12 ? sums.map { $0.start.date() } : nil)
	}

	private var unit: Calendar.Component {
		switch period {
		case .month: .month
		case .quarter: .quarter
		case .year: .year
		}
	}

	/// One label at each bar while they fit, so empty months between bars get none.
	private var dateAxis: (values: AxisMarkValues, format: Date.FormatStyle) {
		switch period {
		case .month: (.automatic(desiredCount: 6), .dateTime.month(.abbreviated).year())
		case .quarter: (.automatic(desiredCount: 6), .dateTime.quarter().year())
		case .year: (.automatic(desiredCount: 6), .dateTime.year())
		}
	}

	private func title(of start: Day) -> String {
		switch period {
		case .month: Format.monthTitle(start)
		case .quarter: "Q\((start.month - 1) / 3 + 1) \(String(start.year))"
		case .year: String(start.year)
		}
	}
}

/// The date and the exact amount of the bar under the pointer.
struct ChartValueLabel: View {
	let title: String
	let value: Money
	/// The withdrawals of a category bar, below the deposits.
	var second: Money?

	var body: some View {
		VStack(alignment: .leading, spacing: 2) {
			Text(title).font(.caption).foregroundStyle(Palette.detail)
			if let second {
				Text("Deposits: \(Format.money(value))").font(.callout).monospacedDigit()
				Text("Withdrawals: \(Format.money(second))").font(.callout).monospacedDigit()
			} else {
				AmountText(money: value).font(.callout.weight(.semibold))
			}
		}
		.padding(.horizontal, 8)
		.padding(.vertical, 5)
		.background(.regularMaterial, in: .rect(cornerRadius: 6))
		.overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.separator))
	}
}

extension View {
	/// The axes of every bar chart: dates on top with a line at each, as in MoneyMoney, and about
	/// three round amounts on the trailing side, in the format of the list: whole amounts without cents, and a step such as 2,5 € with its decimals.
	/// `marks` puts the dates at exactly these days instead of `values`.
	func chartStyle(currency: String, amounts: AmountAxis, dates format: Date.FormatStyle, values: AxisMarkValues = .automatic, marks: [Date]? = nil) -> some View {
		// The marks are whole multiples of the smallest amount of the currency, so its decimal places suffice.
		let decimals = max(0, Int((-log10(Format.chartValue(1, currency))).rounded()))
		return chartXAxis {
			if let marks {
				AxisMarks(position: .top, values: marks) { _ in
					AxisGridLine().foregroundStyle(.quaternary)
					AxisValueLabel(format: format)
				}
			} else {
				AxisMarks(position: .top, values: values) { _ in
					AxisGridLine().foregroundStyle(.quaternary)
					AxisValueLabel(format: format)
				}
			}
		}
		.chartYScale(domain: amounts.lower...amounts.upper)
		.chartYAxis {
			AxisMarks(position: .trailing, values: amounts.marks) { value in
				AxisGridLine().foregroundStyle(.quinary)
				AxisValueLabel {
					if let amount = value.as(Double.self) {
						Text(Decimal(amount).formatted(.currency(code: currency).precision(.fractionLength(0...decimals))))
					}
				}
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
		VStack(alignment: .trailing, spacing: 4) {
			ChartCurrency.Picker(currencies: currencies, current: currency, picked: $picked)
			HStack(spacing: 30) {
				PieChart(title: "Withdrawals", slices: slices.withdrawals)
				PieChart(title: "Deposits", slices: slices.deposits)
			}
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

struct PieSlice: Identifiable, Equatable {
	let id: UUID
	let name: String
	let money: Money
	let color: Color
	var value: Double { Format.chartValue(money.minorUnits, money.currency) }
}

/// One ring of `CategoryPie`. Under the pointer, the slice stands out and the middle of the ring
/// names its category, amount, and share. The pointer lives here, so moving it does not sum the rows again.
struct PieChart: View {
	let title: String
	let slices: [PieSlice]
	@State private var pointer: Double?

	/// `pointer` presets the pointer, for a snapshot of the debug harness.
	init(title: String, slices: [PieSlice], pointer: Double? = nil) {
		self.title = title
		self.slices = slices
		_pointer = State(initialValue: pointer)
	}

	var body: some View {
		VStack {
			Text(title).font(.headline)
			if slices.isEmpty {
				Text("No transactions; no pie chart.").foregroundStyle(.secondary).frame(maxHeight: .infinity)
			} else {
				let total = slices.reduce(0) { $0 + $1.value }
				let hovered = pointer.flatMap(slice(at:))
				Chart(slices) { s in
					SectorMark(angle: .value(title, s.value), innerRadius: .ratio(0.5), angularInset: 1)
						.foregroundStyle(by: .value("Category", s.id.uuidString))
						.opacity(hovered == nil || hovered == s ? 1 : 0.45)
				}
				// The same colors as the category dots in the sidebar. The scale is keyed by the category,
				// not its name: two categories may share a name and still have their own colors. So the
				// legend names them itself.
				.chartForegroundStyleScale(domain: slices.map(\.id.uuidString), range: slices.map(\.color))
				.chartLegend(position: .trailing, alignment: .center) {
					VStack(alignment: .leading, spacing: 4) {
						ForEach(slices) { s in
							HStack(spacing: 4) {
								Circle().fill(s.color).frame(width: 8, height: 8)
								Text(s.name).font(.caption).foregroundStyle(Color.secondary).lineLimit(1)
							}
						}
					}
				}
				.chartAngleSelection(value: $pointer)
				.chartBackground { proxy in
					GeometryReader { geometry in
						if let s = hovered, let plot = proxy.plotFrame {
							let frame = geometry[plot]
							VStack(spacing: 2) {
								Text(s.name).font(.caption).foregroundStyle(Palette.detail).lineLimit(1)
								AmountText(money: s.money).font(.callout.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.6)
								Text((s.value / total).formatted(.percent.precision(.fractionLength(0...1)))).font(.caption).foregroundStyle(Palette.detail)
							}
							.frame(width: min(frame.width, frame.height) * 0.48)
							.position(x: frame.midX, y: frame.midY)
						}
					}
				}
			}
		}
		.frame(maxWidth: .infinity)
	}

	/// The slice that covers a value of the angle scale, which runs from 0 to the sum of the slices.
	private func slice(at value: Double) -> PieSlice? {
		var end = 0.0
		for s in slices {
			end += s.value
			if value <= end { return s }
		}
		return slices.last
	}
}
