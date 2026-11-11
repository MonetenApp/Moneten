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
	@State private var pointerX: CGFloat = 0

	/// The strip of labels above the bars.
	static let labelHeight: CGFloat = 22
	/// Room below the bars for the scroller.
	static let bottomInset: CGFloat = 14

	private var pitch: CGFloat { barWidth + gap }

	var body: some View {
		let scale = Scale(values: bars.map(\.value))
		HStack(spacing: 0) {
			if style == .centered { AmountLabels(scale: scale) }
			GeometryReader { geometry in
				ScrollView(.horizontal) {
					LazyHStack(spacing: 0) {
						ForEach(chunks) { chunk in
							ChunkView(chunk: chunk, style: style, barWidth: barWidth, gap: gap, scale: scale,
								positive: positive, negative: negative, hovered: hovered, height: geometry.size.height)
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
				.onContinuousHover { phase in
					if case let .active(location) = phase { pointerX = location.x }
				}
				.overlay(alignment: .topLeading) {
					if let bar = bars.first(where: { $0.id == hovered }) {
						// Centered over the pointer and kept inside the chart.
						let x = pointerX, width = geometry.size.width
						ChartValueLabel(title: bar.title, value: bar.money)
							.fixedSize()
							.alignmentGuide(.leading) { d in -min(max(0, x - d.width / 2), max(0, width - d.width)) }
							.offset(y: Self.labelHeight)
							.allowsHitTesting(false)
					}
				}
			}
		}
		.help("Click a bar to show its transactions")
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

		/// The y of a value in a plot from `top` with `height`.
		func y(_ value: Double, top: CGFloat, height: CGFloat) -> CGFloat {
			top + CGFloat((upper - value) / (upper - lower)) * height
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
			let top = ScrollingBarChart.labelHeight + 4
			let plot = size.height - top - ScrollingBarChart.bottomInset
			let zero = scale.y(0, top: top, height: plot)
			// Under the pointer, the other bars fade.
			let dims = hovered != nil
			for (i, bar) in chunk.bars.enumerated() {
				let x = CGFloat(i) * pitch + (style == .centered ? gap / 2 : 0)
				let y = scale.y(bar.value, top: top, height: plot)
				// A bar of zero or a few cents is a line, so every period shows where it is.
				var rect = CGRect(x: x, y: min(y, zero), width: barWidth, height: abs(y - zero))
				if rect.height < 1 { rect = CGRect(x: x, y: zero - (bar.value < 0 ? 0 : 1), width: barWidth, height: 1) }
				let color = bar.value < 0 ? negative : positive
				context.fill(Path(rect), with: .color(color.opacity(dims && bar.id != hovered ? 0.5 : 1)))
				if style == .centered, let label = bar.label {
					context.draw(Text(label).font(.system(size: 12)).foregroundStyle(Color.secondary),
						at: CGPoint(x: x + barWidth / 2, y: 3), anchor: .top)
				}
			}
			if style == .separators, let first = chunk.bars.first, first.startsGroup {
				context.fill(Path(CGRect(x: 0, y: 0, width: 1, height: size.height - ScrollingBarChart.bottomInset)), with: .color(.primary.opacity(0.12)))
				if let label = first.label {
					let text = context.resolve(Text(label).font(.system(size: 12)).foregroundStyle(Color.secondary))
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
			let top = ScrollingBarChart.labelHeight + 4
			let plot = geometry.size.height - top - ScrollingBarChart.bottomInset
			let values = [scale.maximum, 0, scale.minimum].filter { $0 != 0 } + [0]
			ForEach(Array(Set(values)).sorted(by: >), id: \.self) { value in
				Text(Self.text(value))
					.font(.system(size: 11))
					.foregroundStyle(.secondary)
					.monospacedDigit()
					.fixedSize()
					.frame(width: geometry.size.width - 6, alignment: .trailing)
					.position(x: (geometry.size.width - 6) / 2, y: scale.y(value, top: top, height: plot))
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
