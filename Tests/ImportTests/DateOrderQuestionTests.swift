import Domain
import Foundation
import Testing
@testable import Import

@Suite("The question for the date order")
struct DateOrderQuestionTests {
	static let text = "Date,Value date,Name,Amount\n11/03/2026,11/04/2026,Kiosk,-4.20\n11/04/2026,11/05/2026,Bakery,-2.00\n"

	@Test("Import stays disabled until the user chooses an order, and either answer enables it")
	func importWaitsForTheAnswer() throws {
		let file = try CSVFile(data: Data(Self.text.utf8))
		var layout = try file.detectedLayout()
		let preview = try file.preview(layout, currency: "EUR")
		var question = DateOrderQuestion()
		question.read(preview)
		#expect(question.asks(layout))
		#expect(!question.allowsImport(preview))
		question.answer = .dayMonthYear
		#expect(!question.asks(layout))
		#expect(question.allowsImport(preview))
		question.answer = .monthDayYear
		layout.dateOrder = .monthDayYear
		let chosen = try file.preview(layout, currency: "EUR")
		question.read(chosen)
		#expect(question.allowsImport(chosen))
		#expect(chosen.transactions.map(\.bookingDate) == [Day(year: 2026, month: 11, day: 3), Day(year: 2026, month: 11, day: 4)])
		// A change in the date format control after the answer is no answer.
		layout.dateOrder = .dayMonthYear
		#expect(question.asks(layout))
		#expect(!question.allowsImport(try file.preview(layout, currency: "EUR")))
	}

	@Test("A file that decides the order needs no answer")
	func decidedFile() throws {
		let file = try CSVFile(data: Data("Date,Name,Amount\n11/13/2026,Kiosk,-4.20\n".utf8))
		let layout = try file.detectedLayout()
		let preview = try file.preview(layout, currency: "EUR")
		var question = DateOrderQuestion()
		question.read(preview)
		#expect(!question.asks(layout))
		#expect(question.allowsImport(preview))
		#expect(question.profileAnswer(layout, header: file.header) == nil)
	}

	@Test("Another booking date or value date column asks again, and another column of a different field keeps the answer")
	func newDateColumnAsksAgain() throws {
		let file = try CSVFile(data: Data(Self.text.utf8))
		let layout = try file.detectedLayout()
		var question = DateOrderQuestion(answer: layout.dateOrder)
		var other = layout
		other.assign(2, to: .purpose)
		question.change(from: layout, to: other)
		#expect(question.answer == layout.dateOrder)
		// The value date column becomes the booking date column, and the value date column is no longer mapped.
		for field in [CSVField.bookingDate, nil] {
			var moved = layout
			moved.assign(1, to: field)
			var asked = DateOrderQuestion(answer: layout.dateOrder)
			asked.change(from: layout, to: moved)
			#expect(asked.answer == nil)
		}
	}

	@Test("A saved profile stores the answer with the titles of the date columns, and nothing without an answer")
	func storedAnswer() throws {
		let file = try CSVFile(data: Data(Self.text.utf8))
		var layout = try file.detectedLayout()
		layout.dateOrder = .monthDayYear
		var question = DateOrderQuestion()
		#expect(question.profileAnswer(layout, header: file.header) == nil)
		question.answer = .monthDayYear
		#expect(question.profileAnswer(layout, header: file.header) == DateOrderAnswer(order: .monthDayYear, bookingDate: "Date", valueDate: "Value date"))
		layout.assign(1, to: nil)
		#expect(question.profileAnswer(layout, header: file.header) == DateOrderAnswer(order: .monthDayYear, bookingDate: "Date", valueDate: nil))
		layout.dateOrder = .dayMonthYear
		#expect(question.profileAnswer(layout, header: file.header) == nil)
	}
}
