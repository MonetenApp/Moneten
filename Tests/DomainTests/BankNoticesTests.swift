import Testing
@testable import Domain

/// The notices of the bank that wait for the window "Notice" (add-fints-banking "Show notices of the bank").
@Suite("Notices of the bank")
struct BankNoticesTests {
	static let maintenance = BankMessage(text: "Wartungsarbeiten am 14.11.2026 von 1 bis 5 Uhr")

	@Test("A notice waits with the name of its bank, and the same notice of a later refresh does not wait again")
	func onlyOnce() {
		var notices = BankNotices()
		notices.add([Self.maintenance], from: "Musterbank")
		notices.add([Self.maintenance], from: "Musterbank")
		#expect(notices.waiting == [BankNotice(bankName: "Musterbank", text: "Wartungsarbeiten am 14.11.2026 von 1 bis 5 Uhr")])
		notices.dismiss()
		notices.add([Self.maintenance], from: "Musterbank")
		#expect(notices.waiting.isEmpty)
	}

	@Test("Notices wait in the order they came, and the same text of another bank is a notice of its own")
	func order() {
		var notices = BankNotices()
		notices.add([Self.maintenance, BankMessage(code: "3900", text: "Neue Preise ab 01.01.2027")], from: "Musterbank")
		notices.add([Self.maintenance], from: "Beispielbank")
		#expect(notices.waiting == [
			BankNotice(bankName: "Musterbank", text: "Wartungsarbeiten am 14.11.2026 von 1 bis 5 Uhr"),
			BankNotice(bankName: "Musterbank", text: "Neue Preise ab 01.01.2027"),
			BankNotice(bankName: "Beispielbank", text: "Wartungsarbeiten am 14.11.2026 von 1 bis 5 Uhr"),
		])
		notices.dismiss()
		#expect(notices.waiting.isEmpty)
	}
}
