import Domain
import Foundation
import SwiftUI

enum Format {
	static func money(_ m: Money) -> String {
		m.decimal.formatted(.currency(code: m.currency))
	}

	static func money(_ minor: Int64, _ currency: String) -> String {
		money(Money(minorUnits: minor, currency: currency))
	}

	/// An amount for a text field: no currency sign and no thousands separators, so that
	/// `AmountParser` reads it back unchanged in every locale.
	static func editableAmount(_ minor: Int64, _ currency: String) -> String {
		Money(minorUnits: minor, currency: currency).decimal.formatted(.number.grouping(.never))
	}

	static func sums(_ s: MoneySums) -> String {
		s.isEmpty ? "" : s.amounts.map(money).joined(separator: "  ")
	}

	static func day(_ d: Day) -> String {
		d.date().formatted(.dateTime.day(.twoDigits).month(.twoDigits).year(.defaultDigits))
	}

	static func monthTitle(_ d: Day) -> String {
		d.date().formatted(.dateTime.month(.wide).year())
	}

	static func iban(_ s: String) -> String {
		let compact = s.replacingOccurrences(of: " ", with: "")
		guard compact.count > 8, compact.prefix(2).allSatisfy(\.isLetter) else { return s }
		return stride(from: 0, to: compact.count, by: 4).map { i -> String in
			let start = compact.index(compact.startIndex, offsetBy: i)
			let end = compact.index(start, offsetBy: min(4, compact.count - i))
			return String(compact[start..<end])
		}.joined(separator: " ")
	}
}

extension Color {
	init?(hex: String?) {
		guard let hex, hex.hasPrefix("#"), hex.count == 7, let v = Int(hex.dropFirst(), radix: 16) else { return nil }
		self.init(red: Double(v >> 16 & 0xFF) / 255, green: Double(v >> 8 & 0xFF) / 255, blue: Double(v & 0xFF) / 255)
	}

	var hex: String? {
		guard let c = NSColor(self).usingColorSpace(.sRGB) else { return nil }
		return String(format: "#%02X%02X%02X", Int(c.redComponent * 255), Int(c.greenComponent * 255), Int(c.blueComponent * 255))
	}
}

struct AmountText: View {
	let money: Money
	/// Sidebar amounts are secondary to the names beside them. Negative amounts stay red.
	var secondary = false
	var body: some View {
		Text(Format.money(money))
			.monospacedDigit()
			.foregroundStyle(money.isNegative ? AnyShapeStyle(Color.red) : secondary ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
	}
}

/// The color of a category: its own color, else the color of its top-level category from a fixed
/// palette, so that the sidebar and the pie chart show the same color for the same category.
enum CategoryColors {
	static let palette: [Color] = [.blue, .orange, .green, .pink, .purple, .teal, .yellow, .indigo, .mint, .brown, .cyan, .red]

	static func color(of category: Domain.Category, in ledger: Ledger) -> Color {
		if let own = Color(hex: category.color) { return own }
		if category.isDefault { return .gray }
		var root = category
		while let parent = root.parentID.flatMap({ ledger.category($0) }) { root = parent }
		if let own = Color(hex: root.color) { return own }
		let index = ledger.childCategories(of: nil).firstIndex { $0.id == root.id } ?? 0
		return palette[index % palette.count]
	}
}

extension AccountKind {
	var symbol: String {
		switch self {
		case .giro: "building.columns"
		case .savings: "banknote"
		case .fixedTermDeposit: "lock.square"
		case .loan: "arrow.down.left.circle"
		case .creditCard: "creditcard"
		case .portfolio: "chart.line.uptrend.xyaxis"
		case .cash: "dollarsign.circle"
		case .other: "tray"
		}
	}
}
