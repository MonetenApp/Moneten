import Testing
@testable import Domain

/// login-credentials "Check a PIN against the rules of the bank": the app names the broken rule
/// before it sends anything.
@Suite("PIN rules")
struct PINRulesTests {
	@Test("Letters in a numeric PIN")
	func numeric() {
		let rules = PINRules(digitsOnly: true, minLength: 5, maxLength: 5)
		#expect(rules.check("12a45") == "The PIN must be numeric.")
		#expect(rules.check("12345") == nil)
	}

	@Test("A PIN that is too long or too short names the limit, in digits or in characters")
	func length() {
		let digits = PINRules(digitsOnly: true, maxLength: 5)
		#expect(digits.check("123456") == "The PIN is too long. The maximum is 5 digits.")
		let characters = PINRules(minLength: 6, maxLength: 20)
		#expect(characters.check("geheim") == nil)
		#expect(characters.check("ab1de") == "The PIN is too short. The minimum is 6 characters.")
		#expect(characters.check(String(repeating: "x", count: 21)) == "The PIN is too long. The maximum is 20 characters.")
		#expect(PINRules(minLength: 1).check("1", secretName: "password") == nil)
		#expect(PINRules(minLength: 8).check("kurz", secretName: "password") == "The password is too short. The minimum is 8 characters.")
	}

	@Test("Without rules every PIN passes")
	func none() {
		#expect(PINRules().check("a") == nil)
		#expect(PINRequest().rules == PINRules())
	}
}
