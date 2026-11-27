import Domain
import Foundation
import SwiftUI

extension Format {
	/// An amount in major units for a chart, with the decimal places of its currency.
	static func chartValue(_ minor: Int64, _ currency: String) -> Double {
		NSDecimalNumber(decimal: Money(minorUnits: minor, currency: currency).decimal).doubleValue
	}

	/// The text of an existing amount in a field, in the decimal mark of the Mac: "2500,00" in Germany.
	static func editableAmount(_ minor: Int64, _ currency: String) -> String {
		editableAmount(Money(minorUnits: minor, currency: currency))
	}

	/// The placeholder of an empty amount field, "0,00" in Germany and "0.00" in the United States.
	static func emptyAmount(_ currency: String = "EUR") -> String {
		editableAmount(0, currency)
	}

	/// Whether an amount field is empty or holds a text that `AmountParser` reads without doubt.
	static func isReadableAmount(_ text: String) -> Bool {
		text.isEmpty || AmountParser.decimal(from: text) != nil
	}

	/// The month and year of a day, read from noon GMT as `day` reads it.
	static func monthTitle(_ d: Day) -> String {
		var style = Date.FormatStyle.dateTime.month(.wide).year()
		style.calendar = Day.calendar(like: .current)
		style.timeZone = style.calendar.timeZone
		return d.noon.formatted(style)
	}

	/// A day with the name of its month, "3. November 2026" in Germany, so that day and month cannot be swapped.
	static func longDay(_ d: Day) -> String {
		var style = Date.FormatStyle.dateTime.day().month(.wide).year()
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
	/// A color of the form "#RRGGBB", read as `HexColor` reads one, nil for any other text.
	init?(hex: String?) {
		guard let color = hex.flatMap(HexColor.init) else { return nil }
		self.init(color.srgb)
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
	/// Increased on a selected table row, where red would be hard to read on the accent color.
	@Environment(\.backgroundProminence) private var prominence
	@Environment(\.negativeRed) private var red
	var body: some View {
		// A positive amount takes the color of its surroundings, such as the text color of the band.
		Text(Format.money(money))
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
	/// The red of negative amounts. The band sets a red that is clear on its gray.
	@Entry var negativeRed = Palette.red
}

/// The colors of the app, each for light and dark mode, as sRGB.
/// The content of the window, from the band at the top to the status line, uses fixed neutral grays (issue #614).
/// macOS 26 tints the system background colors, such as the control background of a table, with the desktop
/// picture, which made the dark list read as dark blue. These colors are plain sRGB values, which macOS draws as
/// they are. The sidebar, the toolbar, and the window keep the system materials (ADR 0012).
/// `.secondary` is 50 % black, about 3.9:1 on white, too faint for body text, so the content uses these colors.
enum Palette {
	/// The background of the content: the list, the empty space below the rows, and the status line.
	static let list = dynamic("list", light: .white, dark: rgb(0x161618))
	/// The band behind the title of the view and its chart, one step lighter than the list in dark mode and one
	/// step darker in light mode.
	static let band = dynamic("band", light: rgb(0xF5F5F7), dark: rgb(0x1D1D1F))
	/// Title, IBAN, balance, and icon on the band: 15:1 in light mode and 14:1 in dark mode.
	static let onBand = dynamic("onBand", light: rgb(0x1D1D1F), dark: rgb(0xECECEE), increasedContrast: .black)
	/// The months, years, and periods of the charts, and the amounts at the edge of a category chart: 4.7:1 on the
	/// band in light mode, 10:1 with "Increase contrast", and 6.5:1 in dark mode.
	static let bandLabel = dynamic("bandLabel", light: rgb(0x6E6E73), dark: rgb(0xA1A1A6), increasedContrast: rgb(0x3A3A3C))
	/// Negative amounts on the band: 5.3:1 on it in light mode, 8.9:1 with "Increase contrast", and 5.9:1 in dark mode.
	static let bandRed = dynamic("bandRed", light: rgb(0xC4262E), dark: rgb(0xF2706A), increasedContrast: rgb(0x8A1017))
	/// The line where a month or a year starts in the balance chart.
	static let bandLine = dynamic("bandLine", light: rgb(0xD2D2D7), dark: rgb(0x3A3A3C), increasedContrast: rgb(0x8E8E93))
	/// The bars of the balance chart: 3.15:1 on the band in light mode, 10.2:1 in dark mode, and 4.7:1 with "Increase
	/// contrast", so that the bars, which carry data, reach the 3:1 of non-text content.
	static let bandBar = dynamic("bandBar", light: rgb(0x868B92), dark: rgb(0xC9C9CC), increasedContrast: rgb(0x6E6E73))
	/// The column behind the bar under the pointer.
	static let bandHover = dynamic("bandHover", light: NSColor(white: 0, alpha: 0.06), dark: NSColor(white: 1, alpha: 0.12))
	/// The dashed line at zero behind the bars of the balance chart.
	static let bandZero = dynamic("bandZero", light: NSColor(white: 0, alpha: 0.25), dark: NSColor(white: 1, alpha: 0.25))
	/// The rim around a pie, a bit darker than the band in light mode and lighter in dark mode.
	static let pieRim = dynamic("pieRim", light: rgb(0xD8D8DC), dark: rgb(0x5A5A5F))
	/// The mode switch of a chart: the chosen segment dark with white text, the others light.
	static let switchChosen = dynamic("switchChosen", light: rgb(0x636366), dark: rgb(0x5E5E62))
	static let switchChosenText = Color.white
	static let switchBackground = dynamic("switchBackground", light: .white, dark: rgb(0xBDBDC0))
	static let switchText = dynamic("switchText", light: rgb(0x3A3A3C), dark: rgb(0x2A2A2C))
	static let switchBorder = dynamic("switchBorder", light: rgb(0xA1A1A6), dark: rgb(0x0E0E10))
	static let filterBar = dynamic("filterBar", light: rgb(0xFAFAFA), dark: rgb(0x1A1A1C))
	/// The line between the filters of the filter bar.
	static let filterSeparator = dynamic("filterSeparator", light: rgb(0xA3A3A3), dark: NSColor(white: 1, alpha: 0.15))
	/// The line below each row of a list.
	static let separator = dynamic("separator", light: rgb(0xEBEBED), dark: rgb(0x2C2C2E), increasedContrast: rgb(0xC7C7CC))
	/// Labels, empty states, and other text that steps back: 5.1:1 on the list in light mode, 9:1 with "Increase
	/// contrast", and 7:1 in dark mode. Also at least 4.5:1 on the band, the filter bar, and a pending row.
	static let secondaryText = dynamic("secondaryText", light: rgb(0x6E6E73), dark: rgb(0xA1A1A6), increasedContrast: rgb(0x48484A))
	/// The box of an unchecked transaction, opaque so that it stays clear on hatched rows.
	static let checkBox = dynamic("checkBox", light: .white, dark: NSColor(white: 0.36, alpha: 1))
	static let checkBoxBorder = dynamic("checkBoxBorder", light: rgb(0xBFBFBF), dark: .clear)
	/// Text below or beside the main text, such as a purpose or a count: about 8:1 on white. As in
	/// MoneyMoney, the weight of the main text sets the hierarchy, not a faint color. A hierarchical
	/// style, so it turns light on a selected table row like the system colors do.
	static var detail: AnyShapeStyle { AnyShapeStyle(.primary.opacity(0.82)) }
	/// Negative amounts and error messages. The system red reaches only 3.6:1 on white, so light mode
	/// uses a darker red with 5.7:1. Dark mode keeps the system red, 5.3:1 on the dark list.
	static let red = dynamic("textRed", light: rgb(0xC4262E), dark: .systemRed)
	/// The profit of a position. The system green reaches only 2.2:1 on white, so light mode uses a darker green with
	/// 5.1:1, and 8:1 with "Increase contrast". Dark mode keeps the system green, 8.9:1 on the dark list.
	static let green = dynamic("textGreen", light: rgb(0x1A7F37), dark: .systemGreen, increasedContrast: rgb(0x0B5D1E))
	/// A value that may be out of date, such as the day of an old quote. The system orange reaches only 2.1:1 on white,
	/// so light mode uses a darker orange with 5.9:1, and 8:1 with "Increase contrast". Dark mode keeps the system orange.
	static let warning = dynamic("textWarning", light: rgb(0x9A5200), dark: .systemOrange, increasedContrast: rgb(0x7A4300))
	/// The speech bubble of a position with a comment, the note color of the draft that the owner approved on 27 November
	/// 2026: 3.2:1 on the list in light mode and 10:1 in dark mode, above the 3:1 of a symbol. The comment itself is body text.
	static let note = dynamic("note", light: rgb(0xB7860B), dark: rgb(0xE8C25A), increasedContrast: rgb(0x7A5900))

	/// `increasedContrast` replaces `light` when the user turns on "Increase contrast".
	private static func dynamic(_ name: String, light: NSColor, dark: NSColor, increasedContrast: NSColor? = nil) -> Color {
		Color(nsColor: NSColor(name: name) { appearance in
			let match = appearance.bestMatch(from: [.aqua, .darkAqua, .accessibilityHighContrastAqua, .accessibilityHighContrastDarkAqua])
			if match == .darkAqua || match == .accessibilityHighContrastDarkAqua { return dark }
			return match == .accessibilityHighContrastAqua ? increasedContrast ?? light : light
		})
	}

	fileprivate static func rgb(_ hex: Int) -> NSColor {
		NSColor(srgbRed: CGFloat(hex >> 16 & 0xFF) / 255, green: CGFloat(hex >> 8 & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
	}
}

/// The color of each asset class, for its ribbon, its heading, and the allocation, which all show it muted as a ribbon
/// does (`RibbonFill`): the color that the user chose in the asset class settings, else the default of the class. The
/// defaults are the colors of the palette of the categories, one for each class in the order of the submenu
/// "Asset Class", so a class looks like a category.
enum AssetClassColors {
	/// The chosen color of `chosen`, `Ledger.assetClassColors`, or the default when there is none or it cannot be read.
	static func color(of assetClass: AssetClass, chosen: [AssetClass: String]) -> Color {
		Color(hex: chosen[assetClass]) ?? defaultColor(of: assetClass)
	}

	static func defaultColor(of assetClass: AssetClass) -> Color {
		CategoryColors.palette[(AssetClass.allCases.firstIndex(of: assetClass) ?? 0) % CategoryColors.palette.count]
	}
}

/// The color of a category: its own color, else the color of its top-level category from a fixed
/// palette, so that the sidebar and the pie chart show the same color for the same category.
enum CategoryColors {
	static let palette: [Color] = [.blue, .orange, .green, .pink, .purple, .teal, .yellow, .indigo, .mint, .brown, .cyan, .red]
	/// The name of each color of `palette`, in its order, which VoiceOver reads for its swatch.
	static var paletteNames: [String] {
		[String(localized: "Blue"), String(localized: "Orange"), String(localized: "Green"), String(localized: "Pink"), String(localized: "Purple"),
			String(localized: "Teal"), String(localized: "Yellow"), String(localized: "Indigo"), String(localized: "Mint"), String(localized: "Brown"),
			String(localized: "Cyan"), String(localized: "Red")]
	}

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
		if let bankCode = account.iban?.germanBankCode { return bankCode }
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
