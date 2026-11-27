import Testing
@testable import Domain

@Suite("Hex colors and the colors of a ribbon")
struct HexColorTests {
	@Test("Only # and six ASCII hexadecimal digits read as a color, and the text comes back in capitals")
	func parse() {
		#expect(HexColor("#2e7d32")?.text == "#2E7D32")
		#expect(HexColor("#FF8000")?.srgb == SRGBColor(red: 1, green: 128.0 / 255, blue: 0))
		for text in ["green", "#ZZZZZZ", "#2E7D3", "#2E7D321", "2E7D32#", "#２E7D32", ""] {
			#expect(HexColor(text) == nil, "\(text)")
		}
	}

	@Test("The fill of a ribbon is its color mixed half with the gray 0.6 in OKLab, as SwiftUI mixes two colors")
	func fill() throws {
		// What `Color(red: 1, green: 0, blue: 0).mix(with: Color(white: 0.6), by: 0.5)` resolves to in sRGB.
		let red = RibbonColor.fill(of: SRGBColor(red: 1, green: 0, blue: 0))
		#expect(abs(red.red - 0.8308851) < 0.0005 && abs(red.green - 0.4373350) < 0.0005 && abs(red.blue - 0.3826304) < 0.0005)
		// The same of the system blue, (0, 0.533, 1) in sRGB.
		let blue = RibbonColor.fill(of: SRGBColor(red: 0, green: 0.53333336, blue: 1))
		#expect(abs(blue.red - 0.3961315) < 0.0005 && abs(blue.green - 0.5813696) < 0.0005 && abs(blue.blue - 0.8080401) < 0.0005)
		let gray = RibbonColor.fill(of: SRGBColor(red: 0.6, green: 0.6, blue: 0.6))
		#expect(abs(gray.red - 0.6) < 0.0005 && abs(gray.blue - 0.6) < 0.0005)
	}

	@Test("The text of a ribbon is white or near-black, whichever has the higher contrast of WCAG on the muted fill")
	func text() throws {
		for light in ["#FFFFFF", "#FFD60A"] {
			let fill = RibbonColor.fill(of: try #require(HexColor(light)).srgb)
			#expect(RibbonColor.text(on: fill) == .nearBlack, "\(light)")
			#expect(fill.contrast(with: .nearBlack) > fill.contrast(with: .white), "\(light)")
		}
		for dark in ["#000000", "#1D3557"] {
			let fill = RibbonColor.fill(of: try #require(HexColor(dark)).srgb)
			#expect(RibbonColor.text(on: fill) == .white, "\(dark)")
		}
		#expect(SRGBColor.white.contrast(with: .white) == 1)
		#expect(abs(SRGBColor.white.contrast(with: SRGBColor(red: 0, green: 0, blue: 0)) - 21) < 0.0001)
	}
}
