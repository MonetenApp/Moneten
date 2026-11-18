/// The fintech banks whose Bankleitzahl the bank list of hbci4java lacks, or lists under the name of the bank that runs
/// their accounts (#233). The bank list names no FinTS address for any of them. Each bank group keeps its rules in a file
/// of its own.
enum Fintechs {
	/// The name that the app shows for each of these Bankleitzahlen, with every brand that shares one. The Bankleitzahlen
	/// and names come from issue #233, which names no places. A Bankleitzahl that the bank list names keeps the bank of
	/// that list in front, as 12070088 keeps "Deutsche Bank", because other lists name a FinTS address for it.
	static let names = [
		"10010123": "Qonto",
		"10017997": "Holvi",
		"10018000": "Finom",
		"10019000": "Adyen / Tide",
		"11010100": "Solaris / Kontist / Tomorrow / ADAC",
		"11010101": "Solaris / Kontist / Tomorrow / ADAC",
		"12070088": "Deutsche Bank / PayPal",
		"20220800": "Banking Circle / TF Bank / Vivid",
		"37019000": "bunq",
		"37021500": "Ford Bank",
		"37021548": "Ford Bank",
		"50034200": "Openbank",
		"50110800": "J.P. Morgan / Pleo",
		"50110801": "J.P. Morgan / Pleo",
	]

	/// The entries of `names` whose Bankleitzahl is not among `codes`, the Bankleitzahlen of the bank list: without a
	/// place, a BIC, and a FinTS address, so that the first step names the bank and starts no login.
	static func missing(from codes: Set<String>) -> [BankDirectory.Entry] {
		names.filter { !codes.contains($0.key) }.map { BankDirectory.Entry(code: $0.key, city: "", bank: FinTSBank(name: $0.value, bic: nil, url: nil)) }
	}
}
