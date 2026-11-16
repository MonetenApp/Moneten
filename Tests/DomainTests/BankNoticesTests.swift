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
			BankNotice(bankName: "Musterbank", code: "3900", text: "Neue Preise ab 01.01.2027"),
			BankNotice(bankName: "Beispielbank", text: "Wartungsarbeiten am 14.11.2026 von 1 bis 5 Uhr"),
		])
		notices.dismiss()
		#expect(notices.waiting.isEmpty)
	}

	@Test("A notice waits until the user is there and brings the window forward once, and a repeat or a dismissed notice brings nothing forward")
	func forward() {
		var notices = BankNotices()
		var forward: [Bool] = []
		notices.add([Self.maintenance], from: "Musterbank")
		#expect(notices.waiting == [BankNotice(bankName: "Musterbank", text: "Wartungsarbeiten am 14.11.2026 von 1 bis 5 Uhr")])
		forward.append(notices.bringForward())
		forward.append(notices.bringForward())
		notices.add([Self.maintenance], from: "Musterbank")
		forward.append(notices.bringForward())
		notices.add([BankMessage(text: "Neue Preise ab 01.01.2027")], from: "Musterbank")
		forward.append(notices.bringForward())
		notices.add([BankMessage(text: "Neue Öffnungszeiten ab 01.12.2026")], from: "Musterbank")
		notices.dismiss()
		forward.append(notices.bringForward())
		#expect(forward == [true, false, false, true, false])
	}

	@Test("A notice that the setup showed never waits")
	func shownInTheSetup() {
		var notices = BankNotices()
		notices.markShown([Self.maintenance], from: "Musterbank")
		notices.add([Self.maintenance], from: "Musterbank")
		#expect(notices.waiting.isEmpty)
		let forward = notices.bringForward()
		#expect(!forward)
		notices.add([Self.maintenance], from: "Beispielbank")
		#expect(notices.waiting == [BankNotice(bankName: "Beispielbank", text: "Wartungsarbeiten am 14.11.2026 von 1 bis 5 Uhr")])
	}

	@Test("A notice that the setup showed under the error of its failed login never waits, and a canceled login shows none")
	func shownAfterFailedSetupLogin() {
		var notices = BankNotices()
		let maintenance = BankMessage(text: "Wartungsarbeiten bis 5 Uhr")
		let failure = SyncFailure.bank(BankMessage(code: "9800", text: "Dialog abgebrochen"))
		let failed = notices.setupFailed(FailureWithNotices(failure, notices: [maintenance]), from: "Musterbank")
		#expect(failed.failure as? SyncFailure == failure)
		#expect(failed.notices == [maintenance])
		notices.add([maintenance], from: "Musterbank")
		#expect(notices.waiting.isEmpty)

		let prices = BankMessage(text: "Neue Preise ab 01.01.2027")
		let canceled = notices.setupFailed(FailureWithNotices(CancellationError(), notices: [prices]), from: "Musterbank")
		#expect(canceled.failure is CancellationError)
		#expect(canceled.notices.isEmpty)
		notices.add([prices], from: "Musterbank")
		#expect(notices.waiting == [BankNotice(bankName: "Musterbank", text: "Neue Preise ab 01.01.2027")])
	}

	@Test("A notice about one account keeps the account and the code, and each account has a notice of its own")
	func aboutOneAccount() {
		var notices = BankNotices()
		notices.add([BankMessage(code: "9210", text: "Saldo nicht verfügbar", accountName: "Tagesgeld"),
			BankMessage(code: "9210", text: "Saldo nicht verfügbar", accountName: "Girokonto")], from: "Musterbank")
		#expect(notices.waiting == [
			BankNotice(bankName: "Musterbank", accountName: "Tagesgeld", code: "9210", text: "Saldo nicht verfügbar"),
			BankNotice(bankName: "Musterbank", accountName: "Girokonto", code: "9210", text: "Saldo nicht verfügbar"),
		])
	}
}
