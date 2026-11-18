import Domain

/// Lets a test write a valid IBAN as a literal. A typing error in a test stops the test run at once.
extension IBAN: ExpressibleByStringLiteral {
	public init(stringLiteral value: String) {
		self = IBAN(value)!
	}
}
