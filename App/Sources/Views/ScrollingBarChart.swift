import Domain
import SwiftUI

/// One bar of a `ScrollingBarChart`: a day, a month, a quarter, or a year.
struct StripBar: Identifiable, Equatable {
	let start: Day
	/// The first day after the bar.
	let end: Day
	let money: Money
	/// The name of the bar for the pointer and VoiceOver, such as "3 Nov 2026".
	let title: String
	/// The text at the top: the month or year that starts here, or the period of the bar.
	let label: String?
	/// A line at the leading edge marks the start of a month or a year.
	let startsGroup: Bool
	var id: Int { start.rawValue }
	var value: Double { Format.chartValue(money.minorUnits, money.currency) }
}

/// A bar chart as MoneyMoney draws it: bars of a fixed width that do not stretch to the window, in a
/// row that scrolls sideways with the trackpad and starts at the newest bar on the right. The scale
/// covers every bar, so scrolling does not change it. The bars are drawn in chunks that SwiftUI
/// builds only while they are visible, so ten years of days stay fast.
struct ScrollingBarChart: View {
	enum Style {
		/// The balance chart: a line and a label where a month or a year starts, no amount axis.
		case separators
		/// The category chart: a label centered above each bar, and the highest amount, zero, and the
		/// lowest amount at the leading edge.
		case centered
	}

	let bars: [StripBar]
	let style: Style
	let barWidth: CGFloat
	let gap: CGFloat
	let positive: Color
	let negative: Color
	let select: (StripBar) -> Void
	@State private var hovered: Int?

	/// `hovered` presets the bar under the pointer, for a snapshot of the debug harness.
	init(bars: [StripBar], style: Style, barWidth: CGFloat, gap: CGFloat, positive: Color, negative: Color, hovered: Int? = nil,
		select: @escaping (StripBar) -> Void) {
		self.bars = bars
		self.style = style
		self.barWidth = barWidth
		self.gap = gap
		self.positive = positive
		self.negative = negative
		self.select = select
		_hovered = State(initialValue: hovered)
	}

	/// The strip of labels above the bars.
	nonisolated static let labelHeight: CGFloat = 22
	/// Room below the bars for the date and amount of the bar under the pointer, and the scroller.
	nonisolated static let bottomInset: CGFloat = 44

	private var pitch: CGFloat { barWidth + gap }

	var body: some View {
		let scale = Scale(values: bars.map(\.value))
		HStack(spacing: 0) {
			if style == .centered { AmountLabels(scale: scale) }
			GeometryReader { geometry in
				ScrollView(.horizontal) {
					ZStack(alignment: .topLeading) {
						LazyHStack(spacing: 0) {
							ForEach(chunks) { chunk in
								ChunkView(chunk: chunk, style: style, barWidth: barWidth, gap: gap, scale: scale,
									positive: positive, negative: negative, hovered: hovered, height: geometry.size.height)
							}
						}
						if let index = bars.firstIndex(where: { $0.id == hovered }) {
							valueLabel(bars[index], index: index, chartHeight: geometry.size.height)
						}
					}
					.contentShape(Rectangle())
					.onContinuousHover { phase in
						if case let .active(location) = phase { hovered = bar(at: location.x)?.id } else { hovered = nil }
					}
					.onTapGesture { location in
						if let bar = bar(at: location.x) { select(bar) }
					}
				}
				.defaultScrollAnchor(.trailing)
				.background {
					if style == .separators {
						// As in MoneyMoney: a dashed line at zero across the whole chart, behind the bars.
						Canvas { context, size in
							let y = scale.y(0, chartHeight: size.height) + 0.5
							let line = Path { $0.addLines([CGPoint(x: 0, y: y), CGPoint(x: size.width, y: y)]) }
							context.stroke(line, with: .color(Palette.bandZero), style: StrokeStyle(lineWidth: 1, dash: [3, 1.5]))
						}
					}
				}
			}
		}
	}

	/// As in MoneyMoney: the date and the amount of the bar under the pointer, below the bars and
	/// just after the bar, or before it when the row ends there.
	private func valueLabel(_ bar: StripBar, index: Int, chartHeight: CGFloat) -> some View {
		let left = CGFloat(index) * pitch + (style == .centered ? gap / 2 : 0)
		let right = left + barWidth
		let total = CGFloat(bars.count) * pitch
		return VStack(alignment: .leading, spacing: 0) {
			Text(bar.title)
			Text(Format.money(bar.money)).fontWeight(.bold).monospacedDigit()
		}
		.font(.system(size: 13))
		.foregroundStyle(Palette.onBand)
		.fixedSize()
		.alignmentGuide(.leading) { d in right + 6 + d.width <= total ? -(right + 6) : -max(0, left - 6 - d.width) }
		.offset(y: chartHeight - Self.bottomInset + 6)
		.allowsHitTesting(false)
	}

	/// The bar under a point of the scrolling row.
	private func bar(at x: CGFloat) -> StripBar? {
		let index = Int(x / pitch)
		return bars.indices.contains(index) ? bars[index] : nil
	}

	/// Bars that start a month or year begin a chunk, so a label never crosses the edge of its chunk.
	/// Without such starts, chunks hold twelve bars.
	private var chunks: [Chunk] {
		var result: [Chunk] = []
		var current: [StripBar] = []
		for bar in bars {
			let starts = style == .separators ? bar.startsGroup : current.count == 12
			if starts, !current.isEmpty {
				result.append(Chunk(bars: current))
				current = []
			}
			current.append(bar)
		}
		if !current.isEmpty { result.append(Chunk(bars: current)) }
		return result
	}

	struct Chunk: Identifiable {
		let bars: [StripBar]
		var id: Int { bars[0].id }
	}

	/// The values of the top and the bottom of the plot. Zero is always in it, and the longest bar
	/// keeps a little room to the edge.
	struct Scale {
		let lower: Double
		let upper: Double
		let maximum: Double
		let minimum: Double

		init(values: [Double]) {
			maximum = max(0, values.max() ?? 0)
			minimum = min(0, values.min() ?? 0)
			let room = max(maximum - minimum, 1) * 0.04
			upper = maximum > 0 ? maximum + room : (minimum < 0 ? room : 1)
			lower = minimum < 0 ? minimum - room : 0
		}

		/// The y of a value in a chart of `chartHeight`, between the labels and the room for the scroller.
		func y(_ value: Double, chartHeight: CGFloat) -> CGFloat {
			let top = ScrollingBarChart.labelHeight + 4
			let plot = chartHeight - top - ScrollingBarChart.bottomInset
			return top + CGFloat((upper - value) / (upper - lower)) * plot
		}
	}
}

/// The bars of one month, year, or twelve periods. A Canvas draws them in one pass.
private struct ChunkView: View {
	let chunk: ScrollingBarChart.Chunk
	let style: ScrollingBarChart.Style
	let barWidth: CGFloat
	let gap: CGFloat
	let scale: ScrollingBarChart.Scale
	let positive: Color
	let negative: Color
	let hovered: Int?
	let height: CGFloat

	var body: some View {
		let pitch = barWidth + gap
		let width = CGFloat(chunk.bars.count) * pitch
		Canvas { context, size in
			let zero = scale.y(0, chartHeight: size.height)
			for (i, bar) in chunk.bars.enumerated() {
				let x = CGFloat(i) * pitch + (style == .centered ? gap / 2 : 0)
				// As in MoneyMoney: a light column through the whole chart behind the bar under the pointer.
				if bar.id == hovered {
					context.fill(Path(CGRect(x: x, y: 0, width: barWidth, height: size.height)), with: .color(Palette.bandHover))
				}
				let y = scale.y(bar.value, chartHeight: size.height)
				// A bar of zero or a few cents is a line, so every period shows where it is.
				var rect = CGRect(x: x, y: min(y, zero), width: barWidth, height: abs(y - zero))
				if rect.height < 1 { rect = CGRect(x: x, y: zero - (bar.value < 0 ? 0 : 1), width: barWidth, height: 1) }
				let color = bar.value < 0 ? negative : positive
				context.fill(Path(rect), with: .color(color))
				if style == .centered, let label = bar.label {
					context.draw(Text(label).font(.system(size: 12)).foregroundStyle(Palette.bandLabel),
						at: CGPoint(x: x + barWidth / 2, y: 3), anchor: .top)
				}
			}
			if style == .separators, let first = chunk.bars.first, first.startsGroup {
				context.fill(Path(CGRect(x: 0, y: 0, width: 1, height: size.height - ScrollingBarChart.bottomInset)), with: .color(Palette.bandLine))
				if let label = first.label {
					let text = context.resolve(Text(label).font(.system(size: 12)).foregroundStyle(Palette.bandLabel))
					// A label that does not fit before the next month or year is left out.
					if text.measure(in: size).width + 6 <= size.width {
						context.draw(text, at: CGPoint(x: 5, y: 3), anchor: .topLeading)
					}
				}
			}
		}
		.frame(width: width, height: height)
		.accessibilityElement(children: .contain)
		.accessibilityChildren {
			ForEach(chunk.bars) { bar in
				Rectangle().accessibilityLabel("\(bar.title): \(Format.money(bar.money))")
			}
		}
	}
}

/// The highest amount, zero, and the lowest amount of a category chart, as MoneyMoney writes them
/// at the leading edge: whole units with a sign.
private struct AmountLabels: View {
	let scale: ScrollingBarChart.Scale

	var body: some View {
		GeometryReader { geometry in
			let values = [scale.maximum, 0, scale.minimum].filter { $0 != 0 } + [0]
			ForEach(Array(Set(values)).sorted(by: >), id: \.self) { value in
				Text(Self.text(value))
					.font(.system(size: 11))
					.foregroundStyle(Palette.bandLabel)
					.monospacedDigit()
					.fixedSize()
					.frame(width: geometry.size.width - 6, alignment: .trailing)
					.position(x: (geometry.size.width - 6) / 2, y: scale.y(value, chartHeight: geometry.size.height))
			}
		}
		.frame(width: 72)
		.accessibilityHidden(true)
	}

	static func text(_ value: Double) -> String {
		if value.rounded() == 0 { return "0" }
		let formatter = NumberFormatter()
		formatter.numberStyle = .decimal
		formatter.maximumFractionDigits = 0
		formatter.positivePrefix = "+"
		formatter.negativePrefix = "\u{2212}"
		return formatter.string(from: NSNumber(value: value.rounded())) ?? ""
	}
}
