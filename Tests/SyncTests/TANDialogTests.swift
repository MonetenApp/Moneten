import Domain
import Foundation
import SyncTesting
import Testing
@testable import Sync

/// tan-handling "Change the method inside the dialog", "Choose the TAN medium", and "Progress while a
/// challenge is requested": the dialog stays open with a progress text until the next request.
@MainActor
@Suite("TAN dialog")
struct TANDialogTests {
	let coordinator = SyncCoordinator()
	var broker: SessionBroker { coordinator.broker }
	static let musterbank = Access(source: .fints(bankCode: "12030000", url: URL(string: "https://fints.example.com/")!), bankName: "Musterbank",
		loginName: "erika77")
	static let beispielbank = Access(source: .fints(bankCode: "10010010", url: URL(string: "https://fints.example.org/")!), bankName: "Beispielbank",
		loginName: "erika77")
	static let giro = AccountRequest(accountID: UUID(), name: "Giro", remoteID: "1234", currency: "EUR")

	static let push = TANMethod(id: "922", name: "pushTAN 2.0", delivery: .pushNotification)
	static let qr = TANMethod(id: "913", name: "chipTAN QR", delivery: .qrCode)
	static let sms = TANMethod(id: "901", name: "mobileTAN", needsMedium: true, delivery: .smsCode)

	static func request(_ challenge: Challenge, methods: [TANMethod] = [], method: TANMethod.ID? = nil) -> UserRequest {
		.secondFactor(SecondFactorRequest(purpose: .login, system: .fintsServer, challenge: challenge, methods: methods, method: method))
	}

	static let chooseMethod = request(.chooseTANMethod([push, qr, sms], current: nil))
	static let chooseMedium = request(.chooseTANMedium(["Handy privat", "Handy Firma"]))
	static let smsTAN = request(.enterTAN(prompt: "Bitte geben Sie die TAN aus der SMS ein.", image: nil), methods: [push, qr, sms], method: sms.id)
	static let approval = request(.approveInApp(prompt: "Bitte bestätigen Sie den Vorgang in Ihrer pushTAN-App.", app: "pushTAN", image: nil, step: nil),
		methods: [push, qr, sms], method: push.id)
	static let qrTAN = request(.enterTAN(prompt: "Bitte scannen Sie den QR-Code.", image: ChallengeImage(Data([0x89, 0x50]))), methods: [push, qr, sms],
		method: qr.id)

	func refresh(_ access: Access, _ steps: [ScriptedConnector.Step]) -> ScriptedConnector {
		let connector = ScriptedConnector(steps)
		coordinator.refresh(RefreshRequest(access: access, accounts: [Self.giro]), with: connector, attended: true)
		return connector
	}

	func answer(_ answer: UserAnswer) {
		if let id = broker.current?.id { broker.answer(answer, to: id) }
	}

	@Test("After a method with media the dialog gets the list of TAN media, and after the medium it requests the SMS code")
	func mediaThenSMS() async {
		let connector = refresh(Self.musterbank, [.ask(Self.chooseMethod), .wait(.milliseconds(300)), .ask(Self.chooseMedium), .wait(.milliseconds(300)),
			.ask(Self.smsTAN)])
		await until { broker.current?.request == Self.chooseMethod }
		answer(.tanMethod("901"))
		#expect(broker.current == nil)
		#expect(broker.requesting?.access == Self.musterbank)
		#expect(broker.requesting?.progress == .tanMedia)
		await until { broker.current?.request == Self.chooseMedium }
		#expect(broker.requesting == nil)
		answer(.tanMedium("Handy Firma"))
		#expect(broker.requesting?.progress == .challenge(.smsCode))
		await until { broker.current?.request == Self.smsTAN }
		#expect(broker.requesting == nil)
		answer(.tan(Secret("482915")))
		await until { !coordinator.isRefreshing }
		#expect(connector.answers.all == [.tanMethod("901"), .tanMedium("Handy Firma"), .tan(Secret("482915"))])
	}

	@Test("Choosing another method while the dialog waits for an approval answers with that method and requests its challenge")
	func changeMethod() async {
		let connector = refresh(Self.musterbank, [.ask(Self.approval), .wait(.milliseconds(300)), .ask(Self.qrTAN)])
		await until { broker.current?.request == Self.approval }
		answer(.tanMethod("913"))
		#expect(broker.requesting?.progress == .challenge(.qrCode))
		await until { broker.current?.request == Self.qrTAN }
		answer(.tan(Secret("123456")))
		await until { !coordinator.isRefreshing }
		#expect(connector.answers.all == [.tanMethod("913"), .tan(Secret("123456"))])
	}

	@Test("A typed TAN closes the dialog without a progress text")
	func tanHasNoProgress() async {
		_ = refresh(Self.musterbank, [.ask(Self.smsTAN), .wait(.milliseconds(300))])
		await until { broker.current != nil }
		answer(.tan(Secret("482915")))
		#expect(broker.requesting == nil)
		await until { !coordinator.isRefreshing }
	}

	@Test("While the progress of one access shows, the dialog of another waits, and the progress ends when its access goes on")
	func otherAccessWaits() async {
		_ = refresh(Self.musterbank, [.ask(Self.chooseMethod), .wait(.milliseconds(400)), .progress(.fetching(done: 1, of: 2)), .wait(.milliseconds(200)),
			.fetched(Self.giro.accountID)])
		await until { broker.current != nil }
		answer(.tanMethod("922"))
		_ = refresh(Self.beispielbank, [.ask(Self.smsTAN)])
		await until { coordinator.states[Self.beispielbank.id] == .needsUser(.secondFactor, waiting: true, during: .connecting) }
		#expect(broker.current == nil)
		#expect(broker.requesting?.progress == .challenge(.pushNotification))
		await until { broker.current?.access == Self.beispielbank }
		#expect(broker.requesting == nil)
		#expect(coordinator.states[Self.musterbank.id] == .fetching(done: 1, of: 2))
		#expect(coordinator.states[Self.beispielbank.id] == .needsUser(.secondFactor, waiting: false, during: .connecting))
		broker.cancel(broker.current!.id)
		await until { !coordinator.isRefreshing }
	}

	@Test("The progress that the access reports before its first account keeps the dialog open until the new challenge")
	func progressBeforeChallenge() async {
		_ = refresh(Self.musterbank, [.ask(Self.chooseMethod), .progress(.fetching(done: 0, of: 2)), .wait(.milliseconds(300)), .ask(Self.qrTAN)])
		await until { broker.current?.request == Self.chooseMethod }
		answer(.tanMethod("913"))
		await until { coordinator.states[Self.musterbank.id] == .fetching(done: 0, of: 2) }
		#expect(broker.requesting?.progress == .challenge(.qrCode))
		await until { broker.current?.request == Self.qrTAN }
		broker.cancel(broker.current!.id)
		await until { !coordinator.isRefreshing }
	}

	@Test("An answer to a dialog whose request was withdrawn a moment before opens no progress")
	func staleAnswer() async throws {
		let broker = broker
		let asked = Task { try await broker.ask(Self.chooseMethod, for: Self.musterbank, accountNames: [], attended: true) }
		await until { broker.current != nil }
		let prompt = try #require(broker.current)
		// The cancel handler runs at once, and the answer comes before the dialog closes.
		asked.cancel()
		broker.answer(.tanMethod("922"), to: prompt.id)
		#expect(broker.requesting == nil)
		await #expect(throws: CancellationError.self) { try await asked.value }
		#expect(broker.requesting == nil)
	}

	@Test("The progress ends with the refresh of its access, and Cancel in the progress stops the access")
	func progressEnds() async {
		_ = refresh(Self.musterbank, [.ask(Self.chooseMethod)])
		await until { broker.current != nil }
		answer(.tanMethod("913"))
		await until { !coordinator.isRefreshing }
		#expect(broker.requesting == nil)

		_ = refresh(Self.musterbank, [.ask(Self.chooseMethod), .wait(.seconds(60))])
		await until { broker.current != nil }
		answer(.tanMethod("913"))
		broker.cancelRequest()
		#expect(broker.requesting == nil)
		await until { !coordinator.isRefreshing }
		#expect(coordinator.states[Self.musterbank.id] == .cancelled)
	}

	/// Waits until the condition holds, for at most two seconds.
	func until(_ condition: () -> Bool, sourceLocation: SourceLocation = #_sourceLocation) async {
		for _ in 0..<200 where !condition() {
			try? await Task.sleep(for: .milliseconds(10))
		}
		#expect(condition(), sourceLocation: sourceLocation)
	}
}
