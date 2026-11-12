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
}
