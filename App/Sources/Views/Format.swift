import Domain
import Foundation
import SwiftUI

enum Format {
	/// An amount with its currency, such as "−42,50 €", with a minus sign as in MoneyMoney.
	static func money(_ m: Money) -> String {
		minus(m.decimal.formatted(.currency(code: m.currency)))
	}

	/// An amount without its currency, such as "−42,50", for a list in one currency.
	static func amount(_ m: Money) -> String {
		minus(m.decimal.formatted(.number.precision(.fractionLength(m.decimalPlaces))))
	}

	private static func minus(_ text: String) -> String {
		text.replacingOccurrences(of: "-", with: "\u{2212}")
	}

	static func money(_ minor: Int64, _ currency: String) -> String {
		money(Money(minorUnits: minor, currency: currency))
	}

	/// An amount in major units for a chart, with the decimal places of its currency.
	static func chartValue(_ minor: Int64, _ currency: String) -> Double {
		NSDecimalNumber(decimal: Money(minorUnits: minor, currency: currency).decimal).doubleValue
	}

	/// An amount for a text field, such as "1234.56": no currency sign, no thousands separators, and
	/// ASCII digits in every locale, so that `AmountParser` reads it back unchanged.
	static func editableAmount(_ minor: Int64, _ currency: String) -> String {
		"\(Money(minorUnits: minor, currency: currency).decimal)"
	}

	static func sums(_ s: MoneySums) -> String {
		s.isEmpty ? "" : s.amounts.map(money).joined(separator: "  ")
	}

	static func day(_ d: Day) -> String {
		d.date().formatted(.dateTime.day(.twoDigits).month(.twoDigits).year(.defaultDigits))
	}

	/// "Today, 09:41", "Yesterday, 21:19", or the date and the time.
	static func dayAndTime(_ date: Date, calendar: Calendar = .current) -> String {
		let time = date.formatted(date: .omitted, time: .shortened)
		if calendar.isDateInToday(date) { return "Today, \(time)" }
		if calendar.isDateInYesterday(date) { return "Yesterday, \(time)" }
		return date.formatted(date: .abbreviated, time: .shortened)
	}

	static func monthTitle(_ d: Day) -> String {
		d.date().formatted(.dateTime.month(.wide).year())
	}

	/// A month on a chart, as MoneyMoney writes it: "Oct 26".
	static func shortMonth(_ d: Day) -> String { shortMonthFormatter.string(from: d.date()) }

	private static let shortMonthFormatter: DateFormatter = {
		let f = DateFormatter()
		f.setLocalizedDateFormatFromTemplate("MMMyy")
		return f
	}()

	/// The label of a bar of a category chart: "Oct 26", "Q4 26", or "2026".
	static func periodLabel(_ start: Day, period: ChartPeriod) -> String {
		switch period {
		case .month: shortMonth(start)
		case .quarter: "Q\((start.month - 1) / 3 + 1) \(String(format: "%02d", start.year % 100))"
		case .year: String(start.year)
		}
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
	var showsCurrency = true
	/// Increased on a selected table row, where red would be hard to read on the accent color.
	@Environment(\.backgroundProminence) private var prominence
	var body: some View {
		Text(showsCurrency ? Format.money(money) : Format.amount(money))
			.monospacedDigit()
			.foregroundStyle(money.isNegative && prominence != .increased ? Palette.red : Color.primary)
	}
}

/// Text colors for data. `.secondary` is 50 % black, about 3.9:1 on white, too faint for amounts,
/// purposes, and counts, so data uses these colors. Labels and empty states keep `.secondary`.
enum Palette {
	/// The bars of the balance chart, as MoneyMoney draws them: light gray on the dark window, and
	/// a middle gray on the light one.
	static let chartBar = Color(nsColor: NSColor(name: "chartBar") { appearance in
		appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
			? NSColor(srgbRed: 0xD3 / 255, green: 0xD4 / 255, blue: 0xD5 / 255, alpha: 1)
			: NSColor(srgbRed: 0x9A / 255, green: 0x9C / 255, blue: 0xA1 / 255, alpha: 1)
	})
	/// Text below or beside the main text, such as a purpose or a count: about 8:1 on white. As in
	/// MoneyMoney, the weight of the main text sets the hierarchy, not a faint color. A hierarchical
	/// style, so it turns light on a selected table row like the system colors do.
	static var detail: AnyShapeStyle { AnyShapeStyle(.primary.opacity(0.82)) }
	/// Negative amounts and error messages. The system red reaches only 3.6:1 on white, so light mode
	/// uses a darker red with 5.7:1. Dark mode keeps the system red, 4.9:1 on the dark window.
	static let red = Color(nsColor: NSColor(name: "textRed") { appearance in
		appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
			? .systemRed
			: NSColor(srgbRed: 0xC4 / 255, green: 0x26 / 255, blue: 0x2E / 255, alpha: 1)
	})
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

/// The icon of a category: an SF Symbol the user chose, else a dot, or a folder for a group.
/// MoneyMoney draws its own pictures; this app offers SF Symbols, which fit macOS and ship with it.
enum CategorySymbols {
	/// The symbols of the picker, sorted by topic, with the name that the tooltip and VoiceOver read.
	/// Each exists since macOS 13 or earlier; the app runs on macOS 15.0, so a newer symbol, such as
	/// "receipt" of macOS 15.2, would show nothing there. Check a new one in the "name_availability"
	/// list of SF Symbols.
	static let choices: [(symbol: String, name: String)] = [
		("house.fill", "House"), ("building.2.fill", "Building"), ("bolt.fill", "Electricity"), ("drop.fill", "Water"),
		("flame.fill", "Heating"), ("wifi", "Internet"), ("phone.fill", "Phone"), ("tv.fill", "Television"),
		("sofa.fill", "Furniture"), ("wrench.and.screwdriver.fill", "Repairs"),
		("cart.fill", "Shopping cart"), ("basket.fill", "Basket"), ("fork.knife", "Restaurant"), ("cup.and.saucer.fill", "Café"),
		("wineglass.fill", "Drinks"), ("birthday.cake.fill", "Cake"),
		("car.fill", "Car"), ("fuelpump.fill", "Fuel"), ("parkingsign.circle.fill", "Parking"), ("bus.fill", "Bus"),
		("tram.fill", "Train"), ("bicycle", "Bicycle"), ("airplane", "Airplane"), ("suitcase.fill", "Suitcase"),
		("beach.umbrella.fill", "Holiday"),
		("bag.fill", "Shopping bag"), ("tshirt.fill", "Clothing"), ("gift.fill", "Gift"), ("shippingbox.fill", "Parcel"),
		("desktopcomputer", "Computer"), ("scissors", "Hairdresser"), ("hammer.fill", "Tools"),
		("cross.case.fill", "Medical"), ("pills.fill", "Pharmacy"), ("stethoscope", "Doctor"), ("heart.fill", "Heart"),
		("figure.run", "Sport"), ("dumbbell.fill", "Fitness"),
		("gamecontroller.fill", "Games"), ("film.fill", "Film"), ("music.note", "Music"), ("book.fill", "Books"),
		("theatermasks.fill", "Theater"), ("pawprint.fill", "Pets"), ("leaf.fill", "Garden"), ("star.fill", "Star"),
		("person.fill", "Person"), ("person.2.fill", "People"), ("figure.2.and.child.holdinghands", "Family"),
		("graduationcap.fill", "Education"), ("briefcase.fill", "Work"),
		("banknote.fill", "Cash"), ("eurosign.circle.fill", "Euro"), ("dollarsign.circle.fill", "Dollar"),
		("creditcard.fill", "Credit card"), ("wallet.pass.fill", "Wallet"), ("building.columns.fill", "Bank"),
		("chart.line.uptrend.xyaxis", "Investments"), ("chart.pie.fill", "Shares"), ("percent", "Interest"),
		("arrow.left.arrow.right", "Transfer"), ("umbrella.fill", "Insurance"), ("shield.lefthalf.filled", "Protection"),
		("doc.text.fill", "Document"), ("list.bullet.rectangle.portrait.fill", "Bill"), ("tag.fill", "Tag"),
	]

	/// The name of a symbol for the tooltip and VoiceOver, or "Dot" and "Folder" for none.
	static func label(_ symbol: String?, isGroup: Bool) -> String {
		guard let symbol else { return isGroup ? "Folder" : "Dot" }
		return choices.first { $0.symbol == symbol }?.name ?? symbol
	}

	/// `filledGroup` is the folder of a group in the title bar, which MoneyMoney draws filled.
	static func name(of category: Domain.Category, filledGroup: Bool = false) -> String {
		if let symbol = category.symbol, !symbol.isEmpty { return symbol }
		return category.isGroup ? (filledGroup ? "folder.fill" : "folder") : "circle.fill"
	}

	/// The dot is drawn smaller than a symbol, as before there were symbols.
	static func isDot(_ category: Domain.Category) -> Bool { name(of: category) == "circle.fill" }
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
