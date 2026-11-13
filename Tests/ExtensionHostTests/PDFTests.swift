import CoreGraphics
import CoreText
@testable import ExtensionHost
import Foundation
import Testing

@Suite struct PDFTests {
	/// A one-page PDF with `line` as real text, drawn by Core Graphics.
	static func statement(_ line: String) -> Data {
		let data = NSMutableData()
		var page = CGRect(x: 0, y: 0, width: 595, height: 842)
		let context = CGContext(consumer: CGDataConsumer(data: data)!, mediaBox: &page, nil)!
		context.beginPDFPage(nil)
		let text = NSAttributedString(string: line, attributes: [kCTFontAttributeName as NSAttributedString.Key: CTFontCreateWithName("Helvetica" as CFString, 12, nil)])
		context.textPosition = CGPoint(x: 72, y: 760)
		CTLineDraw(CTLineCreateWithAttributedString(text), context)
		context.endPDFPage()
		context.closePDF()
		return data as Data
	}

	@Test func statementText() {
		let visit = Visit("""
			function Check()
				return PDF(Connection():request("GET", "https://bank.example/statement.pdf")):text()
			end
			""", pages: ["https://bank.example/statement.pdf": Self.statement("Kontostand 1.234,56 EUR")])
		guard case let .string(text) = visit.call() else {
			Issue.record("PDF:text returned no text")
			return
		}
		#expect(text.contains("Kontostand 1.234,56 EUR"))
	}

	@Test func notAPDFStops() {
		#expect(Visit("function Check() return PDF('Kontostand'):text() end").call() == .string("error: Demo.lua:2: The PDF document could not be read."))
	}
}
