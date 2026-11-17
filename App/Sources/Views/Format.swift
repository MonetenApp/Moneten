import Domain
import Foundation
import SwiftUI

extension Format {
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

	/// An amount in major units for a chart, with the decimal places of its currency.
	static func chartValue(_ minor: Int64, _ currency: String) -> Double {
		NSDecimalNumber(decimal: Money(minorUnits: minor, currency: currency).decimal).doubleValue
	}

	/// An amount for a text field, such as "1234.56", that `AmountParser` reads back unchanged.
	static func editableAmount(_ minor: Int64, _ currency: String) -> String {
		AmountParser.editableText(Money(minorUnits: minor, currency: currency))
	}

	/// Whether an amount field is empty or holds a text that `AmountParser` reads without doubt.
	static func isReadableAmount(_ text: String) -> Bool {
		text.isEmpty || AmountParser.decimal(from: text) != nil
	}

	static func sums(_ s: MoneySums) -> String {
		sums(s.amounts)
	}

	static func sums(_ amounts: [Money]) -> String {
		amounts.map(money).joined(separator: "  ")
	}

	/// The day in the date format of the region, read from noon GMT, so a day that has no local midnight, such as
	/// 30 December 2011 in Samoa, still shows as itself. `DateField` passes its Gregorian calendar.
	static func day(_ d: Day, calendar: Calendar = Day.calendar(like: .current)) -> String {
		var style = Date.FormatStyle.dateTime.day(.twoDigits).month(.twoDigits).year(.defaultDigits)
		style.calendar = calendar
		style.timeZone = calendar.timeZone
		return d.noon.formatted(style)
	}

	/// "Today, 09:41", "Yesterday, 21:19", or the date and the time.
	static func dayAndTime(_ date: Date, calendar: Calendar = .current) -> String {
		let time = date.formatted(date: .omitted, time: .shortened)
		if calendar.isDateInToday(date) { return String(localized: "Today, \(time)") }
		if calendar.isDateInYesterday(date) { return String(localized: "Yesterday, \(time)") }
		return date.formatted(date: .abbreviated, time: .shortened)
	}

	/// The month and year of a day, read from noon GMT as `day` reads it.
	static func monthTitle(_ d: Day) -> String {
		var style = Date.FormatStyle.dateTime.month(.wide).year()
		style.calendar = Day.calendar(like: .current)
		style.timeZone = style.calendar.timeZone
		return d.noon.formatted(style)
	}

	/// A month on a chart, as MoneyMoney writes it: "Oct 26". Read from noon GMT as `day` reads it.
	static func shortMonth(_ d: Day) -> String { shortMonthFormatter.string(from: d.noon) }

	private static let shortMonthFormatter: DateFormatter = {
		let f = DateFormatter()
		f.calendar = Day.calendar(like: .current)
		f.timeZone = f.calendar.timeZone
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

}

extension Color {
	init?(hex: String?) {
		guard let hex, hex.hasPrefix("#"), hex.count == 7, let v = Int(hex.dropFirst(), radix: 16) else { return nil }
		self.init(red: Double(v >> 16 & 0xFF) / 255, green: Double(v >> 8 & 0xFF) / 255, blue: Double(v & 0xFF) / 255)
	}

	var hex: String? {
		guard let c = NSColor(self).usingColorSpace(.sRGB) else { return nil }
		// Rounded, so that a color read back from its hex gives the same hex again.
		func byte(_ v: CGFloat) -> Int { min(255, max(0, Int((v * 255).rounded()))) }
		return String(format: "#%02X%02X%02X", byte(c.redComponent), byte(c.greenComponent), byte(c.blueComponent))
	}
}

struct AmountText: View {
	let money: Money
	var showsCurrency = true
	/// Increased on a selected table row, where red would be hard to read on the accent color.
	@Environment(\.backgroundProminence) private var prominence
	@Environment(\.negativeRed) private var red
	var body: some View {
		// A positive amount takes the color of its surroundings, such as the text color of the band.
		Text(showsCurrency ? Format.money(money) : Format.amount(money))
			.monospacedDigit()
			.foregroundStyle(money.isNegative && prominence != .increased ? AnyShapeStyle(red) : AnyShapeStyle(.primary))
	}
}

/// The balances of an account in a row: the one in the account currency first, then each other currency the source reported.
/// In a sidebar or popover row they take the room they need before the account name beside them does, so a narrow row
/// shortens the name first. When the row is too narrow for all of them, the row shows the first balance whole and the
/// number of the others, and when even that does not fit, the first balance shortened and a short count of the others.
/// Every amount on screen is whole or ends with an ellipsis, never cut off at the edge of the row, and no balance leaves
/// the row without a count. The header shortens its title and the balances together.
struct BalancesText: View {
	let amounts: [Money]

	var body: some View {
		Group {
			if let first = amounts.first {
				// `ViewThatFits` takes the first option whose full width fits. Each option is a view of its own, never an
				// empty one, because an empty view fits every width.
				if amounts.count > 1 {
					ViewThatFits(in: .horizontal) {
						all
						HStack(spacing: 8) {
							AmountText(money: first)
							Text("+ \(amounts.count - 1) more")
								.foregroundStyle(Palette.detail)
						}
						.fixedSize()
						// The shortest form still says how many balances it leaves out.
						HStack(spacing: 6) {
							shortened(first)
							Text(verbatim: "+\(amounts.count - 1)").foregroundStyle(Palette.detail).fixedSize()
						}
					}
					// Every form gives the tooltip and VoiceOver all balances, also the ones that the row leaves out.
					.help(allAmounts)
					.accessibilityElement(children: .ignore)
					.accessibilityLabel(allAmounts)
				} else {
					// A single balance in one line is whole when it fits and ends with an ellipsis when it does not.
					shortened(first)
				}
			}
		}
		.layoutPriority(1)
	}

	/// Every balance, for the tooltip and for VoiceOver.
	private var allAmounts: String {
		amounts.map { Format.money($0) }.formatted(.list(type: .and))
	}

	private var all: some View {
		HStack(spacing: 8) {
			ForEach(amounts, id: \.currency) { AmountText(money: $0) }
		}
		.fixedSize()
	}

	private func shortened(_ money: Money) -> some View {
		AmountText(money: money).lineLimit(1).atLeastEllipsisWide()
	}
}

extension View {
	/// Keeps a name that a row shortens at least as wide as an ellipsis, so it shows "…" and never a cut part of a
	/// letter when the balances beside it take the rest of the row.
	func atLeastEllipsisWide() -> some View {
		ZStack(alignment: .leading) {
			Text(verbatim: "…").fixedSize().hidden().accessibilityHidden(true)
			self
		}
	}
}

extension EnvironmentValues {
	/// The red of negative amounts. The band sets a red that is clear on its slate.
	@Entry var negativeRed = Palette.red
}

/// The colors of the app, each for light and dark mode, measured in the windows of MoneyMoney as sRGB.
/// `.secondary` is 50 % black, about 3.9:1 on white, too faint for amounts, purposes, and counts, so
/// data uses these colors. Labels and empty states keep `.secondary`.
enum Palette {
	// Measured in MoneyMoney: light from a screenshot, dark from a window capture corrected by the
	// offset that the same reading showed against the screenshot. The dark ones are not checked
	// against a dark screenshot.
	/// The slate band behind the title of the view and its chart. With "Increase contrast" the band
	/// turns dark, so that its white bars reach 7:1.
	static let band = dynamic("band", light: rgb(0xAFBAC3), dark: rgb(0x292B31), increasedContrast: rgb(0x4E5964))
	/// Title, IBAN, balance, and icon on the band. MoneyMoney writes white on the light slate, which
	/// reaches only 2:1, so light mode writes dark slate with 8:1.
	static let onBand = dynamic("onBand", light: rgb(0x1C2329), dark: .white, increasedContrast: .white)
	/// The months, years, and periods of the charts, and the amounts at the edge of a category chart.
	/// At least 4.5:1 on the band in every mode.
	static let bandLabel = dynamic("bandLabel", light: rgb(0x3D4650), dark: rgb(0x9A9BA0), increasedContrast: rgb(0xD5DBE0))
	/// Negative amounts on the band, at least 4.5:1 on it. The red of the window reaches only 2.9:1
	/// on the light slate.
	static let bandRed = dynamic("bandRed", light: rgb(0x8A1017), dark: rgb(0xFF6961), increasedContrast: rgb(0xFFC4BF))
	/// The line where a month or a year starts in the balance chart.
	static let bandLine = dynamic("bandLine", light: rgb(0xA1ABB4), dark: rgb(0x3B3C40))
	/// The bars of the balance chart.
	static let bandBar = dynamic("bandBar", light: .white, dark: rgb(0xC9CACB))
	/// The column behind the bar under the pointer: white at 18% on the band, measured in MoneyMoney.
	static let bandHover = Color.white.opacity(0.18)
	/// The dashed line at zero behind the bars of the balance chart.
	static let bandZero = dynamic("bandZero", light: .white, dark: NSColor(white: 1, alpha: 0.25))
	/// The rim around a pie, measured in MoneyMoney in dark mode. The light one is estimated, a bit
	/// lighter than the light slate.
	static let pieRim = dynamic("pieRim", light: rgb(0xC5CDD4), dark: rgb(0x5A5A5F))
	/// The mode switch of a chart: the chosen segment dark with white text, the others light.
	static let switchChosen = dynamic("switchChosen", light: rgb(0x575C61), dark: rgb(0x5E6066))
	static let switchChosenText = Color.white
	static let switchBackground = dynamic("switchBackground", light: rgb(0xF8F8F8), dark: rgb(0xBDBEC0))
	static let switchText = dynamic("switchText", light: rgb(0x4A4A4A), dark: rgb(0x2A2A2C))
	static let switchBorder = dynamic("switchBorder", light: rgb(0x9099A0), dark: rgb(0x1E1F23))
	static let filterBar = dynamic("filterBar", light: rgb(0xF1F1F1), dark: NSColor(white: 1, alpha: 0.04))
	/// The line between the filters of the filter bar.
	static let filterSeparator = dynamic("filterSeparator", light: rgb(0xA3A3A3), dark: NSColor(white: 1, alpha: 0.15))
	/// The box of an unchecked transaction, opaque so that it stays clear on hatched rows.
	static let checkBox = dynamic("checkBox", light: .white, dark: NSColor(white: 0.36, alpha: 1))
	static let checkBoxBorder = dynamic("checkBoxBorder", light: rgb(0xBFBFBF), dark: .clear)
	/// Text below or beside the main text, such as a purpose or a count: about 8:1 on white. As in
	/// MoneyMoney, the weight of the main text sets the hierarchy, not a faint color. A hierarchical
	/// style, so it turns light on a selected table row like the system colors do.
	static var detail: AnyShapeStyle { AnyShapeStyle(.primary.opacity(0.82)) }
	/// Negative amounts and error messages. The system red reaches only 3.6:1 on white, so light mode
	/// uses a darker red with 5.7:1. Dark mode keeps the system red, 4.9:1 on the dark window.
	static let red = dynamic("textRed", light: rgb(0xC4262E), dark: .systemRed)

	/// `increasedContrast` replaces `light` when the user turns on "Increase contrast".
	private static func dynamic(_ name: String, light: NSColor, dark: NSColor, increasedContrast: NSColor? = nil) -> Color {
		Color(nsColor: NSColor(name: name) { appearance in
			let match = appearance.bestMatch(from: [.aqua, .darkAqua, .accessibilityHighContrastAqua, .accessibilityHighContrastDarkAqua])
			if match == .darkAqua || match == .accessibilityHighContrastDarkAqua { return dark }
			return match == .accessibilityHighContrastAqua ? increasedContrast ?? light : light
		})
	}

	private static func rgb(_ hex: Int) -> NSColor {
		NSColor(srgbRed: CGFloat(hex >> 16 & 0xFF) / 255, green: CGFloat(hex >> 8 & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
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

/// The color of an account's icon: the user's color, else one color for all accounts of a bank, as
/// MoneyMoney shows a bank's accounts in the bank's color, else a color for the kind of account.
enum AccountColors {
	static func color(of account: Account) -> Color {
		if let own = Color(hex: account.color) { return own }
		if let bank = bankKey(of: account) {
			// FNV-1a, because `hashValue` changes with every launch.
			let hash = bank.utf8.reduce(UInt32(2_166_136_261)) { ($0 ^ UInt32($1)) &* 16_777_619 }
			return CategoryColors.palette[Int(hash % UInt32(CategoryColors.palette.count))]
		}
		switch account.kind {
		case .giro: return .blue
		case .savings, .fixedTermDeposit: return .teal
		case .creditCard: return .orange
		case .portfolio: return .yellow
		case .loan: return .red
		case .cash: return .green
		case .other: return .gray
		}
	}

	/// The same bank, whether it is named by the bank code inside its IBAN, by a BIC with or without
	/// "XXX", or by its name. The IBAN wins, because MoneyMoney gives some accounts a BIC and others a
	/// Bankleitzahl.
	private static func bankKey(of account: Account) -> String? {
		if let iban = account.iban?.replacingOccurrences(of: " ", with: "").uppercased(), iban.count > 12, iban.hasPrefix("DE") {
			return String(iban.dropFirst(4).prefix(8))
		}
		if let code = account.bankCode, !code.isEmpty { return String(code.uppercased().prefix(8)) }
		return account.bankName
	}
}

/// As in MoneyMoney: an account is a small square in its color, with a darker edge.
struct AccountIcon: View {
	let account: Account
	var size: CGFloat = 13

	var body: some View {
		let color = AccountColors.color(of: account)
		RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
			.fill(color.gradient)
			.overlay(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous).strokeBorder(color.mix(with: .black, by: 0.3), lineWidth: 1))
			.frame(width: size, height: size)
			.accessibilityHidden(true)
	}
}

/// The icon of a category: an SF Symbol the user chose, else a bookmark, or a folder for a group.
/// MoneyMoney draws its own pictures and a colored bookmark for a category without one; this app
/// offers SF Symbols, which fit macOS and ship with it.
enum CategorySymbols {
	/// The symbols of the picker, sorted by topic, with the name that the tooltip and VoiceOver read.
	/// Each exists since macOS 13 or earlier; the app runs on macOS 15.0, so a newer symbol, such as
	/// "receipt" of macOS 15.2, would show nothing there. Check a new one in the "name_availability"
	/// list of SF Symbols.
	static let choices: [(symbol: String, name: String)] = [
		("house.fill", String(localized: "House")), ("building.2.fill", String(localized: "Building")), ("bolt.fill", String(localized: "Electricity")), ("drop.fill", String(localized: "Water")),
		("flame.fill", String(localized: "Heating")), ("wifi", String(localized: "Internet")), ("phone.fill", String(localized: "Phone")), ("tv.fill", String(localized: "Television")),
		("sofa.fill", String(localized: "Furniture")), ("wrench.and.screwdriver.fill", String(localized: "Repairs")),
		("cart.fill", String(localized: "Shopping cart")), ("basket.fill", String(localized: "Basket")), ("fork.knife", String(localized: "Restaurant")), ("cup.and.saucer.fill", String(localized: "Café")),
		("wineglass.fill", String(localized: "Drinks")), ("birthday.cake.fill", String(localized: "Cake")),
		("car.fill", String(localized: "Car")), ("fuelpump.fill", String(localized: "Fuel")), ("parkingsign.circle.fill", String(localized: "Parking")), ("bus.fill", String(localized: "Bus")),
		("tram.fill", String(localized: "Train")), ("bicycle", String(localized: "Bicycle")), ("airplane", String(localized: "Airplane")), ("suitcase.fill", String(localized: "Suitcase")),
		("beach.umbrella.fill", String(localized: "Holiday")),
		("bag.fill", String(localized: "Shopping bag")), ("tshirt.fill", String(localized: "Clothing")), ("gift.fill", String(localized: "Gift")), ("shippingbox.fill", String(localized: "Parcel")),
		("desktopcomputer", String(localized: "Computer")), ("scissors", String(localized: "Hairdresser")), ("hammer.fill", String(localized: "Tools")),
		("cross.case.fill", String(localized: "Medical")), ("pills.fill", String(localized: "Pharmacy")), ("stethoscope", String(localized: "Doctor")), ("heart.fill", String(localized: "Heart")),
		("figure.run", String(localized: "Sport")), ("dumbbell.fill", String(localized: "Fitness")),
		("gamecontroller.fill", String(localized: "Games")), ("film.fill", String(localized: "Film")), ("music.note", String(localized: "Music")), ("book.fill", String(localized: "Books")),
		("theatermasks.fill", String(localized: "Theater")), ("pawprint.fill", String(localized: "Pets")), ("leaf.fill", String(localized: "Garden")), ("star.fill", String(localized: "Star")),
		("person.fill", String(localized: "Person")), ("person.2.fill", String(localized: "People")), ("figure.2.and.child.holdinghands", String(localized: "Family")),
		("graduationcap.fill", String(localized: "Education")), ("briefcase.fill", String(localized: "Work")),
		("banknote.fill", String(localized: "Cash")), ("eurosign.circle.fill", String(localized: "Euro")), ("dollarsign.circle.fill", String(localized: "Dollar")),
		("creditcard.fill", String(localized: "Credit card")), ("wallet.pass.fill", String(localized: "Wallet")), ("building.columns.fill", String(localized: "Bank")),
		("chart.line.uptrend.xyaxis", String(localized: "Investments")), ("chart.pie.fill", String(localized: "Shares")), ("percent", String(localized: "Interest")),
		("arrow.left.arrow.right", String(localized: "Transfer")), ("umbrella.fill", String(localized: "Insurance")), ("shield.lefthalf.filled", String(localized: "Protection")),
		("doc.text.fill", String(localized: "Document")), ("list.bullet.rectangle.portrait.fill", String(localized: "Bill")), ("tag.fill", String(localized: "Tag")),
	]

	/// The name of a symbol for the tooltip and VoiceOver, or "Bookmark" and "Folder" for none.
	static func label(_ symbol: String?, isGroup: Bool) -> String {
		guard let symbol else { return isGroup ? String(localized: "Folder") : String(localized: "Bookmark") }
		return choices.first { $0.symbol == symbol }?.name ?? symbol
	}

	/// `filledGroup` is the folder of a group in the title bar, which MoneyMoney draws filled.
	static func name(of category: Domain.Category, filledGroup: Bool = false) -> String {
		if let symbol = category.symbol, !symbol.isEmpty { return symbol }
		return category.isGroup ? (filledGroup ? "folder.fill" : "folder") : "bookmark.fill"
	}
}

extension View {
	/// Marks an amount field whose text the app refuses, so the user sees why it stores no amount.
	func marksUnreadableAmount(_ text: String) -> some View {
		foregroundStyle(Format.isReadableAmount(text) ? Color.primary : Palette.red)
	}
}
