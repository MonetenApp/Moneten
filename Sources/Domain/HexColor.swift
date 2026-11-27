import Foundation

/// A color as hex text, "#" and six hexadecimal digits such as "#2E7D32", as the user chooses one for an asset class
/// and the complete export writes it.
public struct HexColor: Equatable, Sendable {
	public let red: Int
	public let green: Int
	public let blue: Int

	/// Nil for any other text than "#" and six ASCII hexadecimal digits, in capitals or not.
	public init?(_ text: String) {
		let bytes = Array(text.utf8)
		guard bytes.count == 7, bytes[0] == 0x23 else { return nil }
		var value = 0
		for b in bytes.dropFirst() {
			let digit: Int
			switch b {
			case 0x30...0x39: digit = Int(b) - 0x30
			case 0x41...0x46: digit = Int(b) - 0x41 + 10
			case 0x61...0x66: digit = Int(b) - 0x61 + 10
			default: return nil
			}
			value = value * 16 + digit
		}
		(red, green, blue) = (value >> 16 & 0xFF, value >> 8 & 0xFF, value & 0xFF)
	}

	/// The text in capitals, such as "#2E7D32".
	public var text: String { String(format: "#%02X%02X%02X", red, green, blue) }

	public var srgb: SRGBColor { SRGBColor(red: Double(red) / 255, green: Double(green) / 255, blue: Double(blue) / 255) }
}

/// A color as its sRGB components from 0 to 1, gamma encoded, as `Color.Resolved` of SwiftUI gives them in `red`,
/// `green`, and `blue`.
public struct SRGBColor: Equatable, Sendable {
	public let red: Double
	public let green: Double
	public let blue: Double

	public static let white = SRGBColor(red: 1, green: 1, blue: 1)
	/// The near-black of the text of the rows, #1D1D1F.
	public static let nearBlack = SRGBColor(red: 0x1D / 255.0, green: 0x1D / 255.0, blue: 0x1F / 255.0)

	/// Each component held between 0 and 1, because a resolved color of the extended range can lie outside.
	public init(red: Double, green: Double, blue: Double) {
		self.red = min(1, max(0, red))
		self.green = min(1, max(0, green))
		self.blue = min(1, max(0, blue))
	}

	/// The relative luminance of WCAG 2, from 0 for black to 1 for white.
	public var luminance: Double {
		0.2126 * Self.linear(red) + 0.7152 * Self.linear(green) + 0.0722 * Self.linear(blue)
	}

	/// The contrast ratio of WCAG 2 between the two colors, from 1 to 21.
	public func contrast(with other: SRGBColor) -> Double {
		let (a, b) = (luminance, other.luminance)
		return (max(a, b) + 0.05) / (min(a, b) + 0.05)
	}

	static func linear(_ c: Double) -> Double { c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
	static func encoded(_ c: Double) -> Double { c <= 0.0031308 ? c * 12.92 : 1.055 * pow(c, 1 / 2.4) - 0.055 }
}

/// The colors of a ribbon, the category of a transaction and the asset class of a position alike: the color of the
/// category or class muted toward gray, and a text that stays readable on it, also on a light color that the user chose.
public enum RibbonColor {
	/// `color` mixed half with the gray 0.6 in OKLab, which is what `Color.mix(with: Color(white: 0.6), by: 0.5)` of
	/// SwiftUI gives, so the fill and the choice of its text come from the same numbers.
	public static func fill(of color: SRGBColor) -> SRGBColor {
		let a = OKLab(color), g = OKLab(SRGBColor(red: 0.6, green: 0.6, blue: 0.6))
		return OKLab(l: (a.l + g.l) / 2, a: (a.a + g.a) / 2, b: (a.b + g.b) / 2).srgb
	}

	/// White or near-black, whichever has the higher contrast ratio of WCAG on `fill`, white when both have the same.
	public static func text(on fill: SRGBColor) -> SRGBColor {
		fill.contrast(with: .nearBlack) > fill.contrast(with: .white) ? .nearBlack : .white
	}
}

/// The OKLab color space of Björn Ottosson, in which SwiftUI mixes two colors perceptually.
private struct OKLab {
	let l: Double
	let a: Double
	let b: Double

	init(l: Double, a: Double, b: Double) {
		(self.l, self.a, self.b) = (l, a, b)
	}

	init(_ c: SRGBColor) {
		let (r, g, bl) = (SRGBColor.linear(c.red), SRGBColor.linear(c.green), SRGBColor.linear(c.blue))
		let lms = (cbrt(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * bl), cbrt(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * bl),
			cbrt(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * bl))
		l = 0.2104542553 * lms.0 + 0.7936177850 * lms.1 - 0.0040720468 * lms.2
		a = 1.9779984951 * lms.0 - 2.4285922050 * lms.1 + 0.4505937099 * lms.2
		b = 0.0259040371 * lms.0 + 0.7827717662 * lms.1 - 0.8086757660 * lms.2
	}

	var srgb: SRGBColor {
		let lc = pow(l + 0.3963377774 * a + 0.2158037573 * b, 3)
		let mc = pow(l - 0.1055613458 * a - 0.0638541728 * b, 3)
		let sc = pow(l - 0.0894841775 * a - 1.2914855480 * b, 3)
		return SRGBColor(red: SRGBColor.encoded(4.0767416621 * lc - 3.3077115913 * mc + 0.2309699292 * sc),
			green: SRGBColor.encoded(-1.2684380046 * lc + 2.6097574011 * mc - 0.3413193965 * sc),
			blue: SRGBColor.encoded(-0.0041960863 * lc - 0.7034186147 * mc + 1.7076147010 * sc))
	}
}
