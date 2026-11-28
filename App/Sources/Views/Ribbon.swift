import Domain
import SwiftUI

/// The ribbon of a row: the category of a transaction and the asset class of a position look the same. It starts at the
/// edge of the row, 113 points wide and 14 high, with the name in capitals in white on the color muted toward gray, as
/// the ribbons of MoneyMoney. The text stays white for every color, also a very light one that the user chose, by the
/// owner's decision of 28 November 2026.
struct Ribbon: View {
	static let width: CGFloat = 113
	static let height: CGFloat = 14

	let text: String
	let color: Color

	var body: some View {
		Text(text.uppercased())
			.font(.system(size: 10, weight: .bold))
			.kerning(0.2)
			.foregroundStyle(.white.opacity(0.95))
			.lineLimit(1)
			.padding(.leading, 4)
			.padding(.trailing, 10)
			.frame(width: Self.width, height: Self.height, alignment: .leading)
			.background(RibbonFill(color: color), in: RibbonShape())
	}
}

/// The fill of a ribbon, and of everything else that stands for a class, such as its dot in a heading and its share in the
/// allocation, so a class looks the same everywhere: `RibbonColor.fill(of:)` of the color as it resolves in light or dark
/// mode, which is `color.mix(with: Color(white: 0.6), by: 0.5)`.
struct RibbonFill: ShapeStyle {
	let color: Color

	func resolve(in environment: EnvironmentValues) -> Color {
		Color(RibbonColor.fill(of: SRGBColor(color.resolve(in: environment))))
	}
}

extension SRGBColor {
	init(_ resolved: Color.Resolved) {
		self.init(red: Double(resolved.red), green: Double(resolved.green), blue: Double(resolved.blue))
	}
}

extension Color {
	init(_ srgb: SRGBColor) {
		self.init(.sRGB, red: srgb.red, green: srgb.green, blue: srgb.blue)
	}
}

/// A band with a notch at its trailing end.
struct RibbonShape: Shape {
	func path(in rect: CGRect) -> Path {
		let notch: CGFloat = 7
		var path = Path()
		path.move(to: CGPoint(x: rect.minX, y: rect.minY))
		path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
		path.addLine(to: CGPoint(x: rect.maxX - notch, y: rect.midY))
		path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
		path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
		path.closeSubpath()
		return path
	}
}
