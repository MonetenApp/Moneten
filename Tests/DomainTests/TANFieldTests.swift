import Testing
@testable import Domain

/// The entry field of a typed TAN.
@Suite struct TANFieldTests {
	/// A length below one never reaches `prefix`, which traps for a negative count.
	@Test func negativeLengthDoesNotTrap() {
		let field = TANField(label: "TAN", length: -1 ... -1, isNumeric: true)
		#expect(field.accept("123456") == "")
		#expect(!field.isComplete("1"))
	}

	@Test("The field names its length while the typed TAN is shorter, and says nothing when it is empty, complete, or without a length")
	func lengthNote() {
		let exact = TANField(length: 6...6)
		#expect(exact.lengthNote("12345") == "Enter 6 characters.")
		#expect(exact.lengthNote("1") == "Enter 6 characters.")
		#expect(exact.lengthNote("") == nil)
		#expect(exact.lengthNote("123456") == nil)

		let digits = TANField(length: 7...10, isNumeric: true)
		#expect(digits.lengthNote("123456") == "Enter 7 to 10 digits.")
		#expect(digits.lengthNote("1234567") == nil)
		#expect(TANField(length: 6...6, isNumeric: true).lengthNote("12345") == "Enter 6 digits.")
		#expect(TANField(length: 4...8).lengthNote("123") == "Enter 4 to 8 characters.")

		// A field whose lower bound any text that is not empty reaches never needs the note.
		#expect(TANField(length: 1...8).lengthNote("1") == nil)
		#expect(TANField().lengthNote("1") == nil)
	}
}
