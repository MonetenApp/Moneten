import Domain
import Foundation
import Synchronization
import Testing
@testable import FinTS

/// FinTSConnector over real pipes, against shell scripts that play the part of the helper.
@Suite("FinTS connector")
struct FinTSConnectorTests {
	static let access = Access(source: .fints(bankCode: "12030000", url: URL(string: "https://fints.example.com/fints")!), bankName: "Musterbank", loginName: "erika77")
	static let giro = AccountRequest(accountID: UUID(), name: "Giro", remoteID: "DE02120300000000202051")
	static let savings = AccountRequest(accountID: UUID(), name: "Savings", remoteID: "1234567890")

	/// A file that a script writes the lines of the app into.
	let record = FileManager.default.temporaryDirectory.appending(path: "fints-\(UUID().uuidString).txt")

	var recorded: [[String: String]] {
		let text = (try? String(contentsOf: record, encoding: .utf8)) ?? ""
		return text.split(separator: "\n").map { line in
			let object = (try? JSONSerialization.jsonObject(with: Data(line.utf8))) as? [String: Any] ?? [:]
			return object.mapValues { value in
				if let data = try? JSONSerialization.data(withJSONObject: value, options: [.fragmentsAllowed, .sortedKeys, .withoutEscapingSlashes]) {
					String(decoding: data, as: UTF8.self).trimmingCharacters(in: CharacterSet(charactersIn: "\""))
				} else {
					"\(value)"
				}
			}
		}
	}

	/// A connector whose helper is `/bin/sh -c script`. `$R` in the script is the file `record`.
	func connector(_ script: String, productID: String? = "TESTPRODUCT", inactivity: TimeInterval = 30, grace: TimeInterval = 5) -> FinTSConnector {
		FinTSConnector(helper: .init(executable: URL(filePath: "/bin/sh"), arguments: ["-c", "R='\(record.path)'\n" + script]), productID: productID, version: "0.0.1",
			inactivity: inactivity, grace: grace)
	}

	func refresh(_ script: String, accounts: [AccountRequest] = [giro], enforced: Bool = false, session: Session = Session()) async throws -> ConnectorReport {
		try await connector(script).refresh(RefreshRequest(access: Self.access, accounts: accounts, enforced: enforced), session)
	}

	func failure(of script: String, session: Session = Session()) async -> (any Error)? {
		do {
			_ = try await refresh(script, session: session)
			return nil
		} catch {
			return error
		}
	}

	@Test("Asks for the PIN, sends it through the pipe, and lists the accounts")
	func pin() async throws {
		let session = Session()
		let list = try await connector("""
			read cmd; printf '%s\\n' "$cmd" >> "$R"
			echo '{"type":"ask","id":1,"kind":"pin"}'
			read answer; printf '%s\\n' "$answer" >> "$R"
			echo '{"type":"notice","text":"Wartungsarbeiten am 14.11.2026 von 1 bis 5 Uhr"}'
			echo '{"type":"accounts","accounts":[{"number":"202051","iban":"DE02120300000000202051","bic":"BYLADEM1001","product":"Girokonto","kind":"1","owner":"Erika Mustermann","currency":"EUR"},{"number":"4711","kind":"50","currency":"EUR"},{"number":"9","kind":"12"},{"number":"9","subnumber":"01","kind":"12"}]}'
			echo '{"type":"state","data":"AQID"}'
			""").listAccounts(of: Self.access, state: AccessState(Data([9])), session: session)

		#expect(session.events == [.asked(.pin(PINRequest()))])
		let lines = recorded
		#expect(lines.count == 2)
		#expect(lines[0] == ["type": "accounts", "bankCode": "12030000", "url": "https://fints.example.com/fints", "user": "erika77", "product": "TESTPRODUCT",
			"version": "0.0.1", "state": "CQ=="])
		#expect(lines[1] == ["type": "answer", "id": "1", "value": "1234"])
		#expect(list.accounts == [
			FinTSAccount(number: "202051", subnumber: nil, iban: "DE02120300000000202051", bic: "BYLADEM1001", productName: "Girokonto", kind: .giro,
				owner: "Erika Mustermann", currency: "EUR"),
			FinTSAccount(number: "4711", subnumber: nil, iban: nil, bic: nil, productName: nil, kind: .creditCard, owner: nil, currency: "EUR"),
			FinTSAccount(number: "9", subnumber: nil, iban: nil, bic: nil, productName: nil, kind: .savings, owner: nil, currency: "EUR"),
			FinTSAccount(number: "9", subnumber: "01", iban: nil, bic: nil, productName: nil, kind: .savings, owner: nil, currency: "EUR"),
		])
		#expect(list.accounts.map(\.remoteID) == ["DE02120300000000202051", "4711", "9", "9/01"])
		#expect(list.state == AccessState(Data([1, 2, 3])))
		#expect(list.notices == [BankMessage(text: "Wartungsarbeiten am 14.11.2026 von 1 bis 5 Uhr")])
	}

	@Test("Asks for the PIN again with the answer of the bank after a rejection, and sends the new PIN", arguments: ["9942", "9931"])
	func pinRejectedAsksAgain(code: String) async throws {
		let session = Session()
		_ = try await connector("""
			read cmd
			echo '{"type":"ask","id":1,"kind":"pin"}'
			read answer
			echo '{"type":"ask","id":2,"kind":"pin","rejected":{"code":"\(code)","text":"PIN falsch"}}'
			read answer; printf '%s\\n' "$answer" >> "$R"
			echo '{"type":"accounts","accounts":[]}'
			""").listAccounts(of: Self.access, state: nil, session: session)
		#expect(session.events == [.asked(.pin(PINRequest())), .asked(.pin(PINRequest(rejected: BankMessage(code: code, text: "PIN falsch"))))])
		#expect(recorded == [["type": "answer", "id": "2", "value": "1234"]])
	}

	@Test("Asks for the TAN method, the TAN medium, and TANs with a flicker code or an image")
	func secondFactor() async throws {
		let session = Session()
		_ = try await connector("""
			read cmd
			echo '{"type":"ask","id":1,"kind":"tanMethod","purpose":"login","methods":[{"id":"921","name":"pushTAN 2.0"},{"id":"972","name":"chipTAN optisch"}]}'
			read a; printf '%s\\n' "$a" >> "$R"
			echo '{"type":"ask","id":2,"kind":"tanMedium","purpose":"login","media":["Handy","Karte 1"]}'
			read a; printf '%s\\n' "$a" >> "$R"
			echo '{"type":"ask","id":3,"kind":"tan","purpose":"download","prompt":"Bitte TAN erzeugen","flicker":"0f04871100030333"}'
			read a; printf '%s\\n' "$a" >> "$R"
			echo '{"type":"ask","id":4,"kind":"tan","purpose":"download","prompt":"Bitte scannen","image":"iVBORw=="}'
			read a; printf '%s\\n' "$a" >> "$R"
			echo '{"type":"accounts","accounts":[]}'
			""").listAccounts(of: Self.access, state: nil, session: session)

		#expect(session.events == [
			.asked(.secondFactor(SecondFactorRequest(purpose: .login, system: .fintsServer,
				challenge: .chooseTANMethod([TANMethod(id: "921", name: "pushTAN 2.0"), TANMethod(id: "972", name: "chipTAN optisch")], current: nil)))),
			.asked(.secondFactor(SecondFactorRequest(purpose: .login, system: .fintsServer, challenge: .chooseTANMedium(["Handy", "Karte 1"])))),
			.asked(.secondFactor(SecondFactorRequest(purpose: .download, system: .fintsServer,
				challenge: .flickerCode(prompt: "Bitte TAN erzeugen", code: FlickerCode(hex: "0F04871100030333")!)))),
			.asked(.secondFactor(SecondFactorRequest(purpose: .download, system: .fintsServer,
				challenge: .enterTAN(prompt: "Bitte scannen", image: ChallengeImage(Data([0x89, 0x50, 0x4E, 0x47])))))),
		])
		#expect(recorded.map { $0["value"] } == ["921", "Handy", "123456", "123456"])
		#expect(!recorded.map { $0["id"] }.contains(nil))
	}

	@Test("Sends the PIN rules of the bank with the PIN request")
	func pinRules() async throws {
		let session = Session()
		_ = try await connector("""
			read cmd
			echo '{"type":"ask","id":1,"kind":"pin","rules":{"minLength":5,"maxLength":10}}'
			read answer
			echo '{"type":"accounts","accounts":[]}'
			""").listAccounts(of: Self.access, state: nil, session: session)
		#expect(session.events == [.asked(.pin(PINRequest(rules: PINRules(minLength: 5, maxLength: 10))))])
	}

	@Test("Offers the other TAN methods in the dialog of a challenge, and sends the method that the user changes to", arguments: ["tan", "approve"])
	func changeMethod(kind: String) async throws {
		let session = Session { request in
			guard case .secondFactor = request else { return .pin(Secret("1234")) }
			return .tanMethod("913")
		}
		_ = try await connector("""
			read cmd
			echo '{"type":"ask","id":1,"kind":"\(kind)","purpose":"login","prompt":"Bitte bestätigen","current":"922","methods":[{"id":"922","name":"pushTAN 2.0","delivery":"push"},{"id":"913","name":"chipTAN QR","delivery":"qr"},{"id":"901","name":"mobileTAN","medium":true,"delivery":"sms"}]}'
			read a; printf '%s\\n' "$a" >> "$R"
			echo '{"type":"accounts","accounts":[]}'
			""").listAccounts(of: Self.access, state: nil, session: session)

		let methods = [TANMethod(id: "922", name: "pushTAN 2.0", delivery: .pushNotification), TANMethod(id: "913", name: "chipTAN QR", delivery: .qrCode),
			TANMethod(id: "901", name: "mobileTAN", needsMedium: true, delivery: .smsCode)]
		let challenge: Challenge = kind == "tan" ? .enterTAN(prompt: "Bitte bestätigen", image: nil) : .approveInApp(prompt: "Bitte bestätigen", app: nil, image: nil, step: nil)
		#expect(session.events.first == .asked(.secondFactor(SecondFactorRequest(purpose: .login, system: .fintsServer, challenge: challenge, methods: methods,
			method: "922"))))
		#expect(recorded == [["type": "answer", "id": "1", "method": "913"]])
	}

	@Test("A flicker code that does not read fails the access with an invalid challenge and opens no dialog")
	func invalidFlicker() async throws {
		let session = Session()
		let error = await failure(of: """
			read cmd
			echo '{"type":"ask","id":1,"kind":"tan","purpose":"download","prompt":"Bitte TAN erzeugen","flicker":"0F0X"}'
			read a
			""", session: session)
		#expect(error as? SyncFailure == .invalidChallenge)
		#expect(session.events.isEmpty)
		#expect(SyncFailure.invalidChallenge.message == "The bank responded with an invalid challenge.")
	}

	@Test("Keeps an approval in the app open until the helper withdraws it")
	func approval() async throws {
		let session = Session()
		let report = try await refresh("""
			read cmd
			echo '{"type":"ask","id":1,"kind":"approve","purpose":"login","prompt":"Bitte in der App freigeben","method":"SecureGo plus"}'
			sleep 0.5
			echo '{"type":"withdraw","id":1}'
			echo '{"type":"result","account":"DE02120300000000202051","balance":{"amount":"2340.15","currency":"EUR","date":"2026-11-07"},"errors":[]}'
			""", session: session)

		#expect(session.events.first == .asked(.secondFactor(SecondFactorRequest(purpose: .login, system: .fintsServer,
			challenge: .approveInApp(prompt: "Bitte in der App freigeben", app: "SecureGo plus", image: nil, step: nil)))))
		#expect(session.events.last == .withdrawn)
		guard case let .fetched(result) = report.outcomes[Self.giro.accountID] else { Issue.record("not fetched"); return }
		#expect(result.balance == Money(minorUnits: 234_015, currency: "EUR"))
	}

	@Test("An approval that the helper withdraws at once still reaches the session, which then closes it")
	func approvalWithdrawnAtOnce() async throws {
		let session = Session()
		let report = try await refresh("""
			read cmd
			echo '{"type":"ask","id":1,"kind":"approve","purpose":"login","prompt":"Bitte freigeben"}'
			echo '{"type":"withdraw","id":1}'
			echo '{"type":"result","account":"DE02120300000000202051","balance":{"amount":"1","currency":"EUR"},"errors":[]}'
			""", session: session)

		#expect(session.events == [
			.asked(.secondFactor(SecondFactorRequest(purpose: .login, system: .fintsServer,
				challenge: .approveInApp(prompt: "Bitte freigeben", app: nil, image: nil, step: nil)))),
			.withdrawn,
		])
		#expect(report.outcomes.count == 1)
	}

	@Test("A request for the user ends when the helper ends", arguments: [
		("exit 3", SyncFailure.network("The FinTS helper stopped unexpectedly (status 3).")),
		("exit 0", HelperFailure.noAnswer),
	])
	func helperEndsWhileAsking(exit: String, expected: SyncFailure) async throws {
		let session = Session { _ in
			try await Task.sleep(for: .seconds(60))
			return .pin(Secret("1234"))
		}
		let error = await failure(of: "read cmd; echo '{\"type\":\"ask\",\"id\":1,\"kind\":\"pin\"}'; \(exit)", session: session)
		#expect(error as? SyncFailure == expected)
		#expect(session.events == [.asked(.pin(PINRequest())), .withdrawn])
	}

	@Test("Cancels the refresh when the user cancels the approval")
	func approvalCanceled() async throws {
		let session = Session { request in
			if case let .secondFactor(r) = request, case .approveInApp = r.challenge { throw CancellationError() }
			return .pin(Secret("1234"))
		}
		let error = await failure(of: """
			read cmd
			echo '{"type":"ask","id":1,"kind":"approve","purpose":"login","prompt":"Bitte freigeben"}'
			read line; printf '%s\\n' "$line" >> "$R"
			""", session: session)
		#expect(error is CancellationError)
		#expect(recorded.map { $0["type"] } == ["cancel"])
	}

	@Test("Reports a rejection or a block to the session when it arrives, before a cancel during the end of the helper", arguments: [
		(#"{"type":"failed","code":"9930","text":"Zugang gesperrt"}"#, SyncFailure.accessBlocked(BankMessage(code: "9930", text: "Zugang gesperrt"))),
		(#"{"type":"accountFailed","account":"DE02120300000000202051","code":"9942","text":"PIN falsch"}"#, .pinRejected(BankMessage(code: "9942", text: "PIN falsch"))),
		(#"{"type":"result","account":"DE02120300000000202051","balance":{"amount":"100","currency":"EUR"},"errors":[{"code":"9942","text":"PIN falsch"}]}"#,
			.pinRejected(BankMessage(code: "9942", text: "PIN falsch"))),
		(#"{"type":"ask","id":1,"kind":"pin","rejected":{"code":"9930","text":"PIN gesperrt"}}"#, .accessBlocked(BankMessage(code: "9930", text: "PIN gesperrt"))),
	])
	func rejectionBeforeCancel(line: String, expected: SyncFailure) async throws {
		let session = Session()
		let task = Task {
			try await connector("""
				read cmd
				echo '\(line)'
				sleep 3
				""", grace: 1).refresh(RefreshRequest(access: Self.access, accounts: [Self.giro]), session)
		}
		await until { session.events.contains(.rejected(expected)) }
		task.cancel()
		_ = try? await task.value
		#expect(session.events.filter { if case .rejected = $0 { true } else { false } } == [.rejected(expected)])
	}

	@Test("Reports a rejection that the helper writes after the cancel, while it ends")
	func rejectionDuringGrace() async throws {
		let session = Session()
		let task = Task {
			try await connector("""
				read cmd
				echo '{"type":"progress","done":0,"of":1}'
				read line
				echo '{"type":"failed","code":"9942","text":"PIN falsch"}'
				""", grace: 5).refresh(RefreshRequest(access: Self.access, accounts: [Self.giro]), session)
		}
		await until { session.events.contains(.progress(.fetching(done: 0, of: 1))) }
		task.cancel()
		_ = try? await task.value
		#expect(session.events.contains(.rejected(.pinRejected(BankMessage(code: "9942", text: "PIN falsch")))))
	}

	@Test("An account shows the rejection of the PIN that the session gets, also beside another error, and transactions keep the PIN", arguments: [
		(#"{"type":"result","account":"DE02120300000000202051","balance":{"amount":"100","currency":"EUR"},"errors":[{"code":"9010","text":"Verarbeitung nicht möglich"},{"code":"9942","text":"PIN falsch"}]}"#,
			SyncFailure?.some(.pinRejected(BankMessage(code: "9942", text: "PIN falsch")))),
		(#"{"type":"result","account":"DE02120300000000202051","transactions":{"rows":[]},"errors":[{"code":"9942","text":"PIN falsch"}]}"#, nil),
	])
	func mixedErrors(line: String, shown: SyncFailure?) async throws {
		let session = Session()
		let report = try await refresh("read cmd; echo '\(line)'", session: session)
		guard case let .fetched(result) = report.outcomes[Self.giro.accountID] else { Issue.record("not fetched"); return }
		#expect(result.transactionFailure == shown)
		#expect(session.events == shown.map { [.rejected($0)] } ?? [])
	}

	@Test("A canceled refresh sends cancel, and the helper ends")
	func cancel() async throws {
		let session = Session()
		let grace: TimeInterval = 30
		let task = Task {
			try await connector("""
				read cmd
				echo '{"type":"progress","done":0,"of":1}'
				read line; printf '%s\\n' "$line" >> "$R"
				""", grace: grace).refresh(RefreshRequest(access: Self.access, accounts: [Self.giro]), session)
		}
		await until { session.events.contains(.progress(.fetching(done: 0, of: 1))) }
		let canceled = ContinuousClock.now
		task.cancel()
		await #expect(throws: CancellationError.self) { try await task.value }
		// Only a helper that ends by itself lets the run end before the grace is over.
		#expect(ContinuousClock.now - canceled < .seconds(grace))
		#expect(recorded.map { $0["type"] } == ["cancel"])
	}

	@Test("A helper that ignores cancel ends after 5 seconds")
	func cancelIgnored() async throws {
		let session = Session()
		let task = Task {
			try await refresh("""
				read cmd
				echo '{"type":"progress","done":0,"of":1}'
				trap 'echo "{\\"type\\":\\"terminated\\"}" >> "$R"; exit 1' TERM
				read line; printf '%s\\n' "$line" >> "$R"
				sleep 60 & wait
				""", session: session)
		}
		await until { session.events.contains(.progress(.fetching(done: 0, of: 1))) }
		let canceled = ContinuousClock.now
		task.cancel()
		await #expect(throws: CancellationError.self) { try await task.value }
		#expect(ContinuousClock.now - canceled >= .seconds(5))
		#expect(recorded.map { $0["type"] } == ["cancel", "terminated"])
	}

	@Test("Cancel returns at once while the helper does not read its input, and the helper ends after 5 seconds")
	func cancelBlockedWrite() async throws {
		// A state far larger than the buffer of a pipe, to a helper that never reads it.
		let state = AccessState(Data(repeating: 7, count: 1_000_000))
		let task = Task {
			try await connector(#"trap 'echo "{\"type\":\"terminated\"}" >> "$R"; exit 1' TERM; sleep 60 & wait"#).listAccounts(of: Self.access, state: state, session: Session())
		}
		try await Task.sleep(for: .milliseconds(300))
		let canceled = ContinuousClock.now
		task.cancel()
		// A cancel that waited for the write would return only when the helper ends, 5 seconds later.
		#expect(ContinuousClock.now - canceled < .seconds(5))
		await #expect(throws: CancellationError.self) { try await task.value }
		#expect(ContinuousClock.now - canceled >= .seconds(5))
		#expect(recorded.map { $0["type"] } == ["terminated"])
	}

	@Test("A helper that ignores SIGTERM is killed, and the canceled refresh ends", .timeLimit(.minutes(1)))
	func cancelIgnoresTerm() async throws {
		let grace: TimeInterval = 1
		let task = Task {
			try await connector("trap '' TERM; read cmd; exec sleep 600", grace: grace).listAccounts(of: Self.access, state: nil, session: Session())
		}
		try await Task.sleep(for: .milliseconds(300))
		let canceled = ContinuousClock.now
		task.cancel()
		await #expect(throws: CancellationError.self) { try await task.value }
		// Only SIGKILL, 2 seconds after SIGTERM, ends the helper within the time limit of the test.
		#expect(ContinuousClock.now - canceled >= .seconds(grace + 2))
	}

	@Test("A helper that stays silent fails with a timeout, through cancel and then termination")
	func timeout() async throws {
		let inactivity: TimeInterval = 1, grace: TimeInterval = 1
		let start = ContinuousClock.now
		await #expect(throws: SyncFailure.network("The connection to the FinTS server of the bank timed out. Try again later.")) {
			try await connector("""
				read cmd
				trap 'echo "{\\"type\\":\\"terminated\\"}" >> "$R"; exit 1' TERM
				read line; printf '%s\\n' "$line" >> "$R"
				sleep 60 & wait
				""", inactivity: inactivity, grace: grace).refresh(RefreshRequest(access: Self.access, accounts: [Self.giro]), Session())
		}
		#expect(ContinuousClock.now - start >= .seconds(inactivity + grace))
		#expect(recorded.map { $0["type"] } == ["cancel", "terminated"])
	}

	@Test("A helper that sends a line and then stays silent fails with a timeout", .timeLimit(.minutes(1)))
	func timeoutAfterLine() async throws {
		// The line counts until the run has handled it. Afterwards the silence must time out, as when
		// the helper reported that it sent a message and the bank never answers.
		let start = ContinuousClock.now
		await #expect(throws: SyncFailure.network("The connection to the FinTS server of the bank timed out. Try again later.")) {
			try await connector("""
				read cmd
				trap 'echo "{\\"type\\":\\"terminated\\"}" >> "$R"; exit 1' TERM
				echo '{"type":"alive"}'
				read line; printf '%s\\n' "$line" >> "$R"
				sleep 60 & wait
				""", inactivity: 1, grace: 1).refresh(RefreshRequest(access: Self.access, accounts: [Self.giro]), Session())
		}
		#expect(recorded.map { $0["type"] } == ["cancel", "terminated"])
		// The helper would end on its own after 60 seconds.
		#expect(ContinuousClock.now - start < .seconds(30))
	}

	@Test("A helper that closes its output but keeps running gets the cancel and ends", .timeLimit(.minutes(1)))
	func outputClosedEarly() async throws {
		let run = Task {
			try? await connector("""
				read cmd
				exec >&-
				trap 'echo "{\\"type\\":\\"terminated\\"}" >> "$R"; exit 1' TERM
				read line; printf '%s\\n' "$line" >> "$R"
				sleep 60 & wait
				""", grace: 1).refresh(RefreshRequest(access: Self.access, accounts: [Self.giro]), Session())
		}
		// Without the cancel, the run would wait for the helper without end and could not be awaited.
		let start = ContinuousClock.now
		while !recorded.contains(where: { $0["type"] == "terminated" }), ContinuousClock.now - start < .seconds(30) {
			try await Task.sleep(for: .milliseconds(100))
		}
		#expect(recorded.map { $0["type"] } == ["cancel", "terminated"])
		guard recorded.contains(where: { $0["type"] == "terminated" }) else { return }
		_ = await run.value
	}

	@Test("A helper that does not read a large state fails with a timeout")
	func timeoutBlockedWrite() async throws {
		let state = AccessState(Data(repeating: 7, count: 1_000_000))
		let start = ContinuousClock.now
		await #expect(throws: SyncFailure.network("The connection to the FinTS server of the bank timed out. Try again later.")) {
			try await connector("exec sleep 60", inactivity: 1, grace: 1).listAccounts(of: Self.access, state: state, session: Session())
		}
		// The helper would end on its own after 60 seconds; termination ends it after about 2.
		#expect(ContinuousClock.now - start < .seconds(30))
	}

	@Test("Each line restarts the timeout, and a request for the user pauses it")
	func timeoutRestartsAndPauses() async throws {
		let session = Session { _ in
			try await Task.sleep(for: .seconds(2))
			return .pin(Secret("1234"))
		}
		let list = try await connector("""
			read cmd
			for i in 1 2 3 4; do echo '{"type":"alive"}'; sleep 0.6; done
			echo '{"type":"ask","id":1,"kind":"pin"}'
			read answer
			echo '{"type":"accounts","accounts":[]}'
			""", inactivity: 1).listAccounts(of: Self.access, state: nil, session: session)
		#expect(list.accounts.isEmpty)
	}

	@Test("A helper that sends lines while the app is busy does not time out")
	func busyApp() async throws {
		// The app takes 2 seconds for the progress, while the helper sends a line every half second.
		let session = Session(progress: { _ in try? await Task.sleep(for: .seconds(2)) })
		let report = try await connector("""
			read cmd
			echo '{"type":"progress","done":0,"of":1}'
			for i in 1 2 3 4 5 6; do echo '{"type":"alive"}'; sleep 0.5; done
			echo '{"type":"result","account":"DE02120300000000202051","balance":{"amount":"1","currency":"EUR"},"errors":[]}'
			""", inactivity: 1).refresh(RefreshRequest(access: Self.access, accounts: [Self.giro]), session)
		#expect(report.outcomes.count == 1)
	}

	@Test("A request for the user that waits behind a busy app does not time out")
	func requestBehindBusyApp() async throws {
		// The helper asks for the PIN at once and then waits, while the app takes 2 seconds for the progress.
		let session = Session(progress: { _ in try? await Task.sleep(for: .seconds(2)) })
		let report = try await connector("""
			read cmd
			echo '{"type":"progress","done":0,"of":1}'
			echo '{"type":"ask","id":1,"kind":"pin"}'
			read answer
			echo '{"type":"result","account":"DE02120300000000202051","balance":{"amount":"1","currency":"EUR"},"errors":[]}'
			""", inactivity: 1).refresh(RefreshRequest(access: Self.access, accounts: [Self.giro]), session)
		#expect(report.outcomes.count == 1)
	}

	@Test("A helper that ended does not time out while the app handles its last line")
	func endedWhileBusy() async throws {
		let session = Session(progress: { _ in try? await Task.sleep(for: .seconds(2)) })
		let report = try await connector("""
			read cmd
			echo '{"type":"progress","done":0,"of":1}'
			""", inactivity: 1).refresh(RefreshRequest(access: Self.access, accounts: [Self.giro]), session)
		#expect(report.outcomes.isEmpty)
	}

	@Test("A helper that crashes fails the access")
	func crash() async throws {
		#expect(await failure(of: "read cmd; echo '{\"type\":\"progress\",\"done\":0,\"of\":1}'; kill -9 $$") as? SyncFailure
			== .network("The FinTS helper stopped unexpectedly (signal 9)."))
		#expect(await failure(of: "read cmd; echo '{\"type\":\"ask\",\"id\":1,\"kind\":\"pin\"}'; exit 3") as? SyncFailure
			== .network("The FinTS helper stopped unexpectedly (status 3)."))
	}

	@Test("A line that does not read fails the access and cancels the helper")
	func malformed() async throws {
		#expect(await failure(of: "read cmd; echo 'not json'; read line; printf '%s\\n' \"$line\" >> \"$R\"") as? SyncFailure
			== .network("The FinTS helper sent a line that Moneten cannot read."))
		#expect(recorded.map { $0["type"] } == ["cancel"])
	}

	@Test("Asks for the full history first and when enforced, and otherwise for at most 90 days, in one command")
	func periods() async throws {
		let today = Day.today()
		let recent = AccountRequest(accountID: UUID(), name: "Giro", remoteID: "A", since: today.adding(days: -10))
		let old = AccountRequest(accountID: UUID(), name: "Savings", remoteID: "B", since: today.adding(days: -200))
		let new = AccountRequest(accountID: UUID(), name: "Card", remoteID: "C")
		let script = "read cmd; printf '%s\\n' \"$cmd\" >> \"$R\""
		_ = try await refresh(script, accounts: [recent, old, new])
		_ = try await refresh(script, accounts: [recent, old, new], enforced: true)
		#expect(recorded.map { $0["accounts"] } == [
			"[{\"from\":\"\(today.adding(days: -10))\",\"id\":\"A\"},{\"from\":\"\(today.adding(days: -90))\",\"id\":\"B\"},{\"id\":\"C\"}]",
			"[{\"id\":\"A\"},{\"id\":\"B\"},{\"id\":\"C\"}]",
		])
	}

	@Test("Reads the lines that the helper writes for an MT940 statement, a camt.052 report, and an account that fails")
	func helperLines() async throws {
		// The self-test of the helper writes this file: scripts/build-fints-helper.sh.
		let lines = URL(filePath: #filePath).deletingLastPathComponent().appending(path: "helper-lines.jsonl")
		let card = AccountRequest(accountID: UUID(), name: "Card", remoteID: "4711")
		let report = try await refresh("read cmd; cat '\(lines.path)'", accounts: [Self.giro, Self.savings, card])

		guard case let .fetched(giro) = report.outcomes[Self.giro.accountID] else { Issue.record("giro not fetched"); return }
		#expect(giro.balance == Money(minorUnits: 109_620, currency: "EUR"))
		#expect(giro.balanceDate.map { Day($0) } == Day(year: 2026, month: 11, day: 3))
		#expect(giro.transactions?.from == Day(year: 2026, month: 10, day: 1))
		let mt940 = giro.transactions?.rows ?? []
		#expect(mt940.count == 2)
		if mt940.count == 2 {
			#expect(mt940[0] == Transaction(id: mt940[0].id, accountID: Self.giro.accountID, bookingDate: Day(year: 2026, month: 11, day: 2),
				valueDate: Day(year: 2026, month: 11, day: 2), amountMinor: -2380, currency: "EUR", name: "Stadtwerke Musterstadt", purpose: "Rechnung 1001",
				counterpartyIBAN: "DE02120300000000202051", counterpartyBIC: "BYLADEM1001", bookingText: "FOLGELASTSCHRIFT", endToEndReference: "RE-2026-1001",
				mandateReference: "M-4711", creditorID: "DE98ZZZ09999999999", createdAt: mt940[0].createdAt))
			#expect(mt940[1].amountMinor == 12_000 && mt940[1].name == "Erika Mustermann" && mt940[1].purpose == "Miete November")
		}

		guard case let .fetched(savings) = report.outcomes[Self.savings.accountID] else { Issue.record("savings not fetched"); return }
		#expect(savings.isComplete)
		let camt = savings.transactions?.rows ?? []
		#expect(camt.map(\.amountMinor) == [-4612, -850])
		#expect(camt.map(\.isPending) == [false, true])
		#expect(camt.map(\.name) == ["Coffee Shop", "Bäckerei Muster"])
		#expect(camt.map(\.endToEndReference) == ["SW-778899", nil])
		#expect(camt.last?.bookingDate == Day(year: 2026, month: 11, day: 10))

		guard case let .failed(failure) = report.outcomes[card.accountID] else { Issue.record("card not failed"); return }
		#expect(failure == HelperFailure.noBookingDate)
	}

	@Test("Fails two requests for the same account of the bank, and fetches the others")
	func clash() async throws {
		let twin = AccountRequest(accountID: UUID(), name: "Giro 2", remoteID: Self.giro.remoteID)
		let report = try await refresh(#"""
			read cmd; printf '%s\n' "$cmd" >> "$R"
			echo '{"type":"result","account":"1234567890","balance":{"amount":"1","currency":"EUR"},"errors":[]}'
			"""#, accounts: [Self.giro, Self.savings, twin])
		#expect(recorded.map { $0["accounts"] } == [#"[{"id":"1234567890"}]"#])
		let clash = SyncFailure.unsupported("Two accounts of this access are the same account at the bank.")
		for id in [Self.giro.accountID, twin.accountID] {
			guard case let .failed(failure) = report.outcomes[id] else { Issue.record("not failed"); continue }
			#expect(failure == clash)
		}
		guard case .fetched = report.outcomes[Self.savings.accountID] else { Issue.record("savings not fetched"); return }
	}

	@Test("Maps every field of the result, with calendar days and pending rows")
	func fields() async throws {
		let session = Session()
		let card = AccountRequest(accountID: UUID(), name: "Card", remoteID: "4711")
		let loan = AccountRequest(accountID: UUID(), name: "Loan", remoteID: "777")
		let report = try await refresh(#"""
			read cmd
			echo '{"type":"progress","done":0,"of":3}'
			echo '{"type":"notice","text":"Neue Bedingungen ab 1.12."}'
			echo '{"type":"result","account":"DE02120300000000202051","balance":{"amount":"2340.15","currency":"EUR","date":"2026-11-07"},"transactions":{"from":"2026-08-11","rows":[{"type":"row","booked":"2026-11-02","value":"2026-10-30","amount":"-23.8","currency":"EUR","name":"Stadtwerke Musterstadt","iban":"DE02120300000000202051","bic":"BYLADEM1001","purpose":"Rechnung 1001","endToEnd":"RE-2026-1001","mandate":"M-4711","creditor":"DE98ZZZ09999999999","bookingText":"FOLGELASTSCHRIFT","pending":false},{"type":"row","booked":"2026-11-09","value":"2026-11-09","amount":"-46.12","currency":"EUR","name":"Coffee Shop","purpose":"Kartenzahlung","endToEnd":"SW-778899","pending":true}]},"errors":[]}'
			echo '{"type":"progress","done":1,"of":3}'
			echo '{"type":"result","account":"1234567890","balance":{"amount":"100","currency":"EUR"},"errors":[{"code":"9010","text":"Verarbeitung nicht möglich"}]}'
			echo '{"type":"result","account":"4711","transactions":{"rows":[]},"errors":[{"code":"9210","text":"Saldo nicht verfügbar"}]}'
			echo '{"type":"accountFailed","account":"777","kind":"unsupported","text":"The FinTS server of the bank offers neither the balance nor the transactions of this account."}'
			echo '{"type":"state","data":"AQID"}'
			"""#, accounts: [Self.giro, Self.savings, card, loan], session: session)

		guard case let .fetched(giro) = report.outcomes[Self.giro.accountID] else { Issue.record("giro not fetched"); return }
		#expect(giro.balance == Money(minorUnits: 234_015, currency: "EUR"))
		#expect(giro.balanceDate.map { Day($0) } == Day(year: 2026, month: 11, day: 7))
		#expect(giro.transactions?.from == Day(year: 2026, month: 8, day: 11))
		#expect(giro.isComplete == false)
		let rows = giro.transactions?.rows ?? []
		#expect(rows.count == 2)
		if rows.count == 2 {
			#expect(rows[0] == Transaction(id: rows[0].id, accountID: Self.giro.accountID, bookingDate: Day(year: 2026, month: 11, day: 2),
				valueDate: Day(year: 2026, month: 10, day: 30), amountMinor: -2380, currency: "EUR", name: "Stadtwerke Musterstadt", purpose: "Rechnung 1001",
				counterpartyIBAN: "DE02120300000000202051", counterpartyBIC: "BYLADEM1001", bookingText: "FOLGELASTSCHRIFT", endToEndReference: "RE-2026-1001",
				mandateReference: "M-4711", creditorID: "DE98ZZZ09999999999", createdAt: rows[0].createdAt))
			#expect(rows[1] == Transaction(id: rows[1].id, accountID: Self.giro.accountID, bookingDate: Day(year: 2026, month: 11, day: 9),
				valueDate: Day(year: 2026, month: 11, day: 9), amountMinor: -4612, currency: "EUR", name: "Coffee Shop", purpose: "Kartenzahlung",
				endToEndReference: "SW-778899", isPending: true, createdAt: rows[1].createdAt))
		}

		guard case let .fetched(savings) = report.outcomes[Self.savings.accountID] else { Issue.record("savings not fetched"); return }
		#expect(savings.balance == Money(minorUnits: 10_000, currency: "EUR"))
		#expect(savings.balanceDate == nil)
		#expect(savings.transactions == nil)
		#expect(savings.transactionFailure == .bank(BankMessage(code: "9010", text: "Verarbeitung nicht möglich")))

		guard case let .fetched(cardResult) = report.outcomes[card.accountID] else { Issue.record("card not fetched"); return }
		#expect(cardResult.balance == nil)
		#expect(cardResult.transactions?.from == nil)
		#expect(cardResult.isComplete)
		#expect(cardResult.transactionFailure == nil)

		guard case let .failed(loanFailure) = report.outcomes[loan.accountID] else { Issue.record("loan not failed"); return }
		#expect(loanFailure == .unsupported("The FinTS server of the bank offers neither the balance nor the transactions of this account."))

		#expect(report.state == AccessState(Data([1, 2, 3])))
		#expect(report.notices == [BankMessage(text: "Neue Bedingungen ab 1.12."), BankMessage(code: "9210", text: "Saldo nicht verfügbar")])
		#expect(session.events == [.progress(.fetching(done: 0, of: 3)), .progress(.fetching(done: 1, of: 3))])
	}

	@Test("A result that does not read fails only its account", arguments: [
		(#"{"type":"result","account":"DE02120300000000202051","transactions":{"rows":[{"booked":"2026-11-02","amount":"zwölf","pending":false}]},"errors":[]}"#,
			HelperFailure.unreadable),
		(#"{"type":"result","account":"DE02120300000000202051","balance":{"currency":"EUR"},"errors":[]}"#, HelperFailure.unreadable),
		(#"{"type":"result","account":"DE02120300000000202051","transactions":{"rows":[{"amount":"-1","pending":true}]},"errors":[]}"#,
			SyncFailure.unsupported("The bank sent a transaction without a booking date, so nothing of this account was stored.")),
	])
	func unreadableResult(line: String, expected: SyncFailure) async throws {
		let report = try await refresh("""
			read cmd
			echo '\(line)'
			echo '{"type":"result","account":"1234567890","balance":{"amount":"1","currency":"EUR"},"errors":[]}'
			""", accounts: [Self.giro, Self.savings])
		guard case let .failed(failure) = report.outcomes[Self.giro.accountID] else { Issue.record("giro not failed"); return }
		#expect(failure == expected)
		guard case .fetched = report.outcomes[Self.savings.accountID] else { Issue.record("savings not fetched"); return }
	}

	@Test("Maps the errors of the bank to failures", arguments: [
		(#"{"type":"failed","code":"9078","text":"FinTS-Produkt ist nicht registriert"}"#, SyncFailure.notRegistered),
		(#"{"type":"failed","code":"9942","text":"PIN falsch"}"#, .pinRejected(BankMessage(code: "9942", text: "PIN falsch"))),
		(#"{"type":"failed","code":"9340","text":"PIN ungültig"}"#, .pinRejected(BankMessage(code: "9340", text: "PIN ungültig"))),
		(#"{"type":"failed","code":"9930","text":"PIN gesperrt"}"#, .accessBlocked(BankMessage(code: "9930", text: "PIN gesperrt"))),
		(#"{"type":"failed","code":"9931","text":"Anmeldename oder PIN ist falsch"}"#, .pinRejected(BankMessage(code: "9931", text: "Anmeldename oder PIN ist falsch"))),
		(#"{"type":"failed","code":"9010","text":"Verarbeitung nicht möglich"}"#, .bank(BankMessage(code: "9010", text: "Verarbeitung nicht möglich"))),
		(#"{"type":"failed","text":"Dialog abgebrochen"}"#, .bank(BankMessage(text: "Dialog abgebrochen"))),
		(#"{"type":"failed","kind":"network","text":"Connection refused"}"#, .network("Connection refused")),
		(#"{"type":"failed","kind":"invalidChallenge","text":"The bank responded with an invalid challenge."}"#, .invalidChallenge),
		(#"{"type":"failed","kind":"unsupported","text":"The bank offers no encrypted FinTS address."}"#, .unsupported("The bank offers no encrypted FinTS address.")),
		(#"{"type":"failed","kind":"certificate","text":"The certificate of the server fints.example.com is not valid."}"#,
			.network("The certificate of the server fints.example.com is not valid.")),
		(#"{"type":"ask","id":1,"kind":"pin","rejected":{"code":"9930","text":"PIN gesperrt"}}"#, .accessBlocked(BankMessage(code: "9930", text: "PIN gesperrt"))),
	])
	func errors(line: String, expected: SyncFailure) async throws {
		let session = Session()
		#expect(await failure(of: "read cmd; echo '\(line)'", session: session) as? SyncFailure == expected)
		// No dialog opens. Only a rejection of the PIN or a block reaches the session, at once.
		#expect(session.events == (expected.rejectsPIN ? [.rejected(expected)] : []))
	}

	@Test("Refuses an access without https and a build without a product ID before it starts the helper")
	func refusals() async throws {
		let http = Access(source: .fints(bankCode: "12030000", url: URL(string: "http://fints.example.com/fints")!), bankName: "Musterbank", loginName: "erika77")
		let script = "printf 'started\\n' >> \"$R\""
		await #expect(throws: SyncFailure.unsupported("The bank offers no encrypted FinTS address.")) {
			try await connector(script).refresh(RefreshRequest(access: http, accounts: [Self.giro]), Session())
		}
		await #expect(throws: SyncFailure.unsupported("This build of Moneten has no FinTS product ID, and banks accept only registered apps.")) {
			try await connector(script, productID: nil).refresh(RefreshRequest(access: Self.access, accounts: [Self.giro]), Session())
		}
		#expect(!FileManager.default.fileExists(atPath: record.path))
	}

	@Test("Lets macOS decide whether to trust the certificate of the bank's server")
	func certificate() async throws {
		// A self-signed certificate for fints.example.com, which macOS does not trust.
		let selfSigned = "MIIBbjCCARSgAwIBAgIUZLBNL2oHyVE4uWYcY2AsrJoRs1wwCgYIKoZIzj0EAwIwHDEaMBgGA1UEAwwRZmludHMuZXhhbXBsZS5jb20wIBcNMjYxMTEyMDkwNzA2WhgPMjEyNjEwMTkwOTA3MDZaMBwxGjAYBgNVBAMMEWZpbnRzLmV4YW1wbGUuY29tMFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAECfzMwKS0EZ30jfANBH637mHSfMao4flhFhxcprnVgHJkuHJBfW/6Q5nvVInTBjBMBtn5u2i4nhB+T3q+kd6NbqMyMDAwHQYDVR0OBBYEFLqzKE6BcWLapiQh64hKhdTm+St0MA8GA1UdEwEB/wQFMAMBAf8wCgYIKoZIzj0EAwIDSAAwRQIga6Dk0TBJmqVRQeTtLDsObTgchRXljI06HpI4NcEQBtYCIQDXlOpNDsxpw0I/cMyiVP2D7QH5XZDWiEzLCC/FhVMICQ=="
		let session = Session()
		_ = try await refresh("""
			read cmd
			echo '{"type":"trust","id":1,"host":"fints.example.com","chain":["\(selfSigned)"]}'
			read a; printf '%s\\n' "$a" >> "$R"
			echo '{"type":"trust","id":2,"host":"fints.example.com","chain":["AAAA"]}'
			read a; printf '%s\\n' "$a" >> "$R"
			""", session: session)
		let answers = recorded
		#expect(answers.map { $0["id"] } == ["1", "2"])
		#expect(answers.allSatisfy { $0["value"]?.hasPrefix("The certificate of the bank's server fints.example.com is not valid: ") == true })
		#expect(session.events.isEmpty)
	}

	@Test("Starts the helper without the environment of the app, without a crash file, and with the proxy of macOS")
	func environment() async throws {
		_ = try await connector(#"read cmd; printf '%s\n' "${HOME-none} ${TMPDIR-none}" >> "$R"; echo '{"type":"bank"}'"#).bankInfo(bankCode: "12030000")
		#expect((try? String(contentsOf: record, encoding: .utf8)) == "none none\n")
		let arguments = FinTSConnector.Helper.bundled.arguments
		#expect(arguments.contains("-XX:ErrorFile=/dev/null"))
		#expect(arguments.contains("-Djava.net.useSystemProxies=true"))
		#expect(arguments.contains("-XX:+DisableAttachMechanism") && arguments.contains("-Xrs"))
		#expect(arguments.last == "FinTSHelper")
	}

	@Test("Looks up a bank in the bank directory")
	func bankInfo() async throws {
		let bank = try await connector(#"""
			read cmd; printf '%s\n' "$cmd" >> "$R"
			echo '{"type":"bank","name":"Deutsche Kreditbank Berlin","bic":"BYLADEM1001","url":"https://fints.dkb.de/fints"}'
			"""#).bankInfo(bankCode: "12030000")
		#expect(bank == FinTSBank(name: "Deutsche Kreditbank Berlin", bic: "BYLADEM1001", url: URL(string: "https://fints.dkb.de/fints")))
		#expect(recorded == [["type": "bankInfo", "bankCode": "12030000"]])
		#expect(try await connector(#"read cmd; echo '{"type":"bank"}'"#).bankInfo(bankCode: "99999999") == nil)
	}

	/// Waits until the condition holds, for at most five seconds.
	func until(_ condition: () -> Bool) async {
		for _ in 0..<500 where !condition() {
			try? await Task.sleep(for: .milliseconds(10))
		}
	}
}

/// A session that answers every request at once, and waits on an approval until it is withdrawn.
final class Session: SyncSession {
	enum Event: Equatable {
		case asked(UserRequest)
		case withdrawn
		case progress(SyncProgress)
		case rejected(SyncFailure)
	}

	private let answer: @Sendable (UserRequest) async throws -> UserAnswer
	private let progress: @Sendable (SyncProgress) async -> Void
	private let log = Mutex<[Event]>([])

	init(answer: @escaping @Sendable (UserRequest) async throws -> UserAnswer = Session.standard,
		progress: @escaping @Sendable (SyncProgress) async -> Void = { _ in }) {
		self.answer = answer
		self.progress = progress
	}

	var events: [Event] { log.withLock { $0 } }

	func ask(_ request: UserRequest) async throws -> UserAnswer {
		log.withLock { $0.append(.asked(request)) }
		do {
			return try await answer(request)
		} catch is CancellationError where Task.isCancelled {
			log.withLock { $0.append(.withdrawn) }
			throw CancellationError()
		}
	}

	func report(_ progress: SyncProgress) async {
		log.withLock { $0.append(.progress(progress)) }
		await self.progress(progress)
	}

	func rejected(_ failure: SyncFailure) async {
		log.withLock { $0.append(.rejected(failure)) }
	}

	@Sendable static func standard(_ request: UserRequest) async throws -> UserAnswer {
		guard case let .secondFactor(r) = request else { return .pin(Secret("1234")) }
		switch r.challenge {
		case let .chooseTANMethod(methods, _): return .tanMethod(methods[0].id)
		case let .chooseTANMedium(media): return .tanMedium(media.first ?? "")
		case .approveInApp:
			try await Task.sleep(for: .seconds(60))
			throw CancellationError()
		default: return .tan(Secret("123456"))
		}
	}
}
