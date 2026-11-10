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
			CategoryBars(rows: rows)
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

	var body: some View {
		let accounts = accountIDs.compactMap { model.ledger.account($0) }.filter { !$0.isClosed }
		let currency = accounts.first?.currency ?? "EUR"
		let ids = Set(accounts.filter { $0.currency == currency && $0.kind != .portfolio }.map(\.id))
		let range = model.filter.period
		let monthly = model.balanceMode == .monthlyAverage || model.selection.map { if case .group = $0 { true } else { false } } == true
		let points = monthly ? model.ledger.monthlyAverageBalances(accountIDs: ids, range: range) : model.ledger.dailyBalances(accountIDs: ids, range: range)
		if points.isEmpty {
			Text(accounts.count == 1 ? "No transactions; no bar chart." : "No transactions; no bar chart.")
				.foregroundStyle(.secondary)
				.frame(maxWidth: .infinity, maxHeight: .infinity)
		} else {
			Chart(points) { p in
				if monthly {
					BarMark(x: .value("Month", p.day.date(), unit: .month), y: .value("Balance", Double(p.minorUnits) / 100))
						.foregroundStyle(p.minorUnits < 0 ? Color.red.gradient : Color.accentColor.gradient)
				} else {
					AreaMark(x: .value("Day", p.day.date(), unit: .day), y: .value("Balance", Double(p.minorUnits) / 100))
						.interpolationMethod(.stepEnd)
						.foregroundStyle(Color.accentColor.opacity(0.25).gradient)
					LineMark(x: .value("Day", p.day.date(), unit: .day), y: .value("Balance", Double(p.minorUnits) / 100))
						.interpolationMethod(.stepEnd)
						.foregroundStyle(Color.accentColor)
				}
			}
			.chartYAxis {
				AxisMarks { v in
					AxisGridLine()
					AxisValueLabel { if let d = v.as(Double.self) { Text(Format.money(Money(Decimal(d), currency: currency))) } }
				}
			}
			.chartYAxisLabel(monthly ? "Monthly average balance" : "Daily balance")
		}
	}
}

struct CategoryBars: View {
	@Environment(AppModel.self) private var model
	let rows: [Transaction]

	var body: some View {
		@Bindable var model = model
		let sums = model.ledger.periodSums(of: rows, period: model.chartPeriod)
		VStack(alignment: .trailing, spacing: 4) {
			Picker("", selection: $model.chartPeriod) {
				Text("M").help("Monthly view").tag(ChartPeriod.month)
				Text("Q").help("Quarterly view").tag(ChartPeriod.quarter)
				Text("Y").help("Yearly view").tag(ChartPeriod.year)
			}
			.pickerStyle(.segmented)
			.fixedSize()
			if sums.isEmpty {
				Text("No transactions; no bar chart.").foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
			} else {
				Chart(sums) { s in
					BarMark(x: .value("Period", s.start.date(), unit: unit), y: .value("Deposits", Double(s.deposits) / 100))
						.foregroundStyle(Color.green.gradient)
					BarMark(x: .value("Period", s.start.date(), unit: unit), y: .value("Withdrawals", Double(s.withdrawals) / 100))
						.foregroundStyle(Color.red.gradient)
				}
			}
		}
	}

	private var unit: Calendar.Component {
		switch model.chartPeriod {
		case .month: .month
		case .quarter: .quarter
		case .year: .year
		}
	}
}

struct CategoryPie: View {
	@Environment(AppModel.self) private var model
	let rows: [Transaction]

	var body: some View {
		let parent: UUID? = { if case let .category(id) = model.selection, !model.ledger.childCategories(of: id).isEmpty { return id }; return nil }()
		let totals = model.ledger.categoryTotals(of: rows, below: parent)
		let withdrawals = totals.filter { $0.minorUnits < 0 }.map { (name: $0.category.name, value: Double(-$0.minorUnits) / 100, color: CategoryColors.color(of: $0.category, in: model.ledger)) }
		let deposits = totals.filter { $0.minorUnits > 0 }.map { (name: $0.category.name, value: Double($0.minorUnits) / 100, color: CategoryColors.color(of: $0.category, in: model.ledger)) }
		HStack(spacing: 30) {
			pie("Withdrawals", withdrawals)
			pie("Deposits", deposits)
		}
	}

	@ViewBuilder
	private func pie(_ title: String, _ slices: [(name: String, value: Double, color: Color)]) -> some View {
		VStack {
			Text(title).font(.headline)
			if slices.isEmpty {
				Text("No transactions; no pie chart.").foregroundStyle(.secondary).frame(maxHeight: .infinity)
			} else {
				Chart(slices, id: \.name) { s in
					SectorMark(angle: .value(title, s.value), innerRadius: .ratio(0.5), angularInset: 1)
						.foregroundStyle(by: .value("Category", s.name))
				}
				// The same colors as the category dots in the sidebar.
				.chartForegroundStyleScale(domain: slices.map(\.name), range: slices.map(\.color))
				.chartLegend(position: .trailing, alignment: .center)
			}
		}
		.frame(maxWidth: .infinity)
	}
}
