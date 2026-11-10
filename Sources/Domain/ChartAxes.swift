import Foundation

/// The amount axis of a bar chart: a range from the lowest to the highest bar, always with zero,
/// and about three round amounts in it. The automatic scale of Swift Charts rounds the range out
/// to the next round amount, so one bar of a little more than 1,000,000 stretches the axis to
/// 2,000,000, and a small negative bar adds as much room below zero as above it.
public struct AmountAxis: Equatable, Sendable {
	public var lower: Double
	public var upper: Double
	public var marks: [Double]

	public init(values: [Double], count: Int = 3) {
		let low = min(0, values.min() ?? 0)
		let high = max(0, values.max() ?? 0)
		guard high > low else {
			self.init(lower: 0, upper: 1, marks: [0])
			return
		}
		// The smallest round step that gives at most one mark more than `count`.
		let magnitude = pow(10, (log10((high - low) / Double(max(1, count)))).rounded(.down))
		let step = [1, 2, 2.5, 5, 10, 20].map { $0 * magnitude }
			.first { ((high / $0).rounded(.down) - (low / $0).rounded(.up)) + 1 <= Double(count + 1) } ?? 20 * magnitude
		// A little room past the longest bar, so that it does not touch the edge of the chart.
		let room = (high - low) * 0.04
		self.init(lower: low < 0 ? low - room : 0, upper: high > 0 ? high + room : 0,
			marks: (Int((low / step).rounded(.up))...Int((high / step).rounded(.down))).map { Double($0) * step + 0 })
	}

	public init(lower: Double, upper: Double, marks: [Double]) {
		self.lower = lower
		self.upper = upper
		self.marks = marks
	}
}

/// The date axis of the balance chart: days for two months or less, month starts for two years or
/// less, and year starts for longer periods, at most about `count` of them.
public struct DateAxis: Equatable, Sendable {
	public enum Unit: Sendable { case day, month, year }

	public var unit: Unit
	public var marks: [Day]

	/// `start` is the first day of the chart and `end` the day after its last bar. A label starts at
	/// its mark, so a mark in the last `trailing` share of the chart is left out: the edge of the
	/// chart would cut off its label.
	public init(from start: Day, to end: Day, count: Int = 6, trailing: Double = 0, calendar: Calendar = .current) {
		let days = calendar.dateComponents([.day], from: start.date(in: calendar), to: end.date(in: calendar)).day ?? 0
		var marks: [Day]
		if days <= 62 {
			unit = .day
			let step = max(1, (days + count - 1) / count)
			marks = stride(from: 0, to: days, by: step).map { start.adding(days: $0, calendar: calendar) }
		} else if days <= 731 {
			unit = .month
			let months = days / 30
			let step = [1, 2, 3, 6].first { months / $0 <= count } ?? 12
			var month = start.day == 1 ? start : start.firstOfMonth.adding(months: 1, calendar: calendar)
			marks = []
			while month < end {
				if (month.month - 1) % step == 0 { marks.append(month) }
				month = month.adding(months: 1, calendar: calendar)
			}
		} else {
			unit = .year
			let years = days / 365
			let step = [1, 2, 5, 10, 20].first { years / $0 <= count } ?? 50
			var year = start.month == 1 && start.day == 1 ? start.year : start.year + 1
			marks = []
			while Day(year: year, month: 1, day: 1) < end {
				if year % step == 0 { marks.append(Day(year: year, month: 1, day: 1)) }
				year += 1
			}
		}
		let lastMark = end.adding(days: -Int((Double(days) * trailing).rounded(.up)), calendar: calendar)
		self.marks = marks.filter { $0 < lastMark }
	}
}
