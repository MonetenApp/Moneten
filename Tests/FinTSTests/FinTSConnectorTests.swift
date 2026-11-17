import Domain
import Foundation
import Synchronization
import Testing
@testable import FinTS

/// FinTSConnector over real pipes, against shell scripts that play the part of the helper.
@Suite("FinTS connector")
struct FinTSConnectorTests {
	static let access = Access(source: .fints(bankCode: "12030000", url: URL(string: "https://fints.example.com/fints")!), bankName: "Musterbank", loginName: "erika77")
	static let giro = AccountRequest(accountID: UUID(), name: "Giro", remoteID: "DE02120300000000202051", currency: "EUR")
	static let savings = AccountRequest(accountID: UUID(), name: "Savings", remoteID: "1234567890", currency: "EUR")

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

	/// The line that a script writes into `record` when SIGTERM ends it, with the time by the clock of
	/// the helper, in seconds since 1970. It also ends the `sleep 60 &` of the script, which would
	/// otherwise hold stdout open for 60 seconds.
	static let terminatedTrap = #"trap 'echo "{\"type\":\"terminated\",\"at\":$(date +%s)}" >> "$R"; kill $! 2>/dev/null; exit 1' TERM"#

	/// The seconds from `start` until the trap of `terminatedTrap` ran. A test of a timeout measures
	/// this instead of the end of the run: the run also waits for a thread of Swift concurrency, and on
	/// a runner of CI the CPU-bound tests of other suites hold those threads for more than 30 seconds.
	func secondsToTermination(since start: Date) -> Double? {
		recorded.first { $0["type"] == "terminated" }?["at"].flatMap(Double.init).map { $0 - start.timeIntervalSince1970 }
	}

	/// A connector whose helper is `/bin/sh -c script`. `$R` in the script is the file `record`. A
	/// terminated helper gets 30 seconds before SIGKILL, so that the trap of a script runs also when a
	/// loaded runner of CI holds up the shell for more than the 2 seconds of the app.
	func connector(_ script: String, productID: String? = "TESTPRODUCT", inactivity: TimeInterval = 30, grace: TimeInterval = 5,
		killAfter: TimeInterval = 30, bankList: @escaping @Sendable () -> Data? = { nil }) -> FinTSConnector {
		FinTSConnector(helper: .init(executable: URL(filePath: "/bin/sh"), arguments: ["-c", "R='\(record.path)'\n" + script]), productID: productID, version: "0.0.1",
			inactivity: inactivity, grace: grace, killAfter: killAfter, bankList: bankList)
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
			echo '{"type":"accounts","accounts":[{"number":"202051","iban":"DE02120300000000202051","bic":"BYLADEM1001","product":"Girokonto","kind":"1","owner":"Erika Mustermann","currency":"EUR"},{"number":"4711","kind":"50","currency":"EUR"},{"number":"9","kind":"12"},{"number":"9","subnumber":"01","kind":"12"},{"number":"7654326","product":"Depot","currency":"EUR","securities":true}]}'
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
			// A depot whose bank gives no account type, which the helper knows by its jobs.
			FinTSAccount(number: "7654326", subnumber: nil, iban: nil, bic: nil, productName: "Depot", kind: .portfolio, owner: nil, currency: "EUR"),
		])
		#expect(list.accounts.map(\.remoteID) == ["DE02120300000000202051", "4711", "9", "9/01", "7654326"])
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
			echo '{"type":"ask","id":4,"kind":"tan","purpose":"download","prompt":"Bitte scannen","image":"iVBORw0KGgoAAAANSUhEUgAAAMgAAADICAYAAAA="}'
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
				challenge: .enterTAN(prompt: "Bitte scannen", image: ChallengeImage(Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAMgAAADICAYAAAA=")!))))),
		])
		#expect(recorded.map { $0["value"] } == ["921", "Handy", "123456", "123456"])
		#expect(!recorded.map { $0["id"] }.contains(nil))
		if case let .asked(.secondFactor(request))? = session.events.last, case let .enterTAN(_, image?) = request.challenge {
			#expect(image.picture?.width == 200)
		} else {
			Issue.record("no TAN request with an image")
		}
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

	@Test("A cooperative bank on a server of Atruvia refuses a six character PIN, and gets a VR-Kennung in capitals")
	func cooperativeBank() async throws {
		let session = Session()
		let access = Access(source: .fints(bankCode: "51090000", url: URL(string: "https://fints2.atruvia.de/cgi-bin/hbciservlet")!), bankName: "Wiesbadener Volksbank",
			loginName: "vrk12345678")
		_ = try await connector("""
			read cmd; printf '%s\\n' "$cmd" >> "$R"
			echo '{"type":"ask","id":1,"kind":"pin","rules":{"minLength":8,"maxLength":20}}'
			read answer
			echo '{"type":"ask","id":2,"kind":"tanMedium","purpose":"login","media":[]}'
			read answer; printf '%s\\n' "$answer" >> "$R"
			echo '{"type":"accounts","accounts":[]}'
			""").listAccounts(of: access, state: nil, session: session)
		#expect(session.events == [.asked(.pin(PINRequest(rules: PINRules(minLength: 8, maxLength: 20, refusedLength: 6)))),
			.asked(.secondFactor(SecondFactorRequest(purpose: .login, system: .fintsServer, challenge: .chooseTANMedium([]))))])
		#expect(recorded.first?["user"] == "VRK12345678")
	}

	@Test("An access of a savings bank that stored a login name of 17 digits sends its first 16 digits")
	func savingsBankLoginOf17Digits() async throws {
		let access = Access(source: .fints(bankCode: "50850049", url: URL(string: "https://banking-hs6.s-fints-pt-hs.de/fints30")!), bankName: "Sparkasse Musterstadt",
			loginName: "12345678901234567")
		_ = try await connector("""
			read cmd; printf '%s\\n' "$cmd" >> "$R"
			echo '{"type":"result","account":"DE02120300000000202051","balance":{"amount":"1","currency":"EUR"},"errors":[]}'
			""").refresh(RefreshRequest(access: access, accounts: [Self.giro], enforced: false), Session())
		#expect(recorded.first?["user"] == "1234567890123456")
	}

	@Test("apoBank asks for the name of the apoTAN device when it lists no TAN media, and the empty name goes to the helper")
	func apoTANDevice() async throws {
		let session = Session { request in
			guard case .secondFactor = request else { return .pin(Secret("12345678")) }
			return .tanMedium("")
		}
		let access = Access(source: .fints(bankCode: "30060601", url: URL(string: "https://fints.apobank.de/FinTs30PinTanHttpGate")!), bankName: "apoBank",
			loginName: "erika77")
		_ = try await connector("""
			read cmd
			echo '{"type":"ask","id":1,"kind":"pin","rules":{"minLength":8}}'
			read answer
			echo '{"type":"ask","id":2,"kind":"tanMedium","purpose":"login","media":[]}'
			read answer; printf '%s\\n' "$answer" >> "$R"
			echo '{"type":"accounts","accounts":[]}'
			""").listAccounts(of: access, state: nil, session: session)
		#expect(session.events == [.asked(.pin(PINRequest(rules: PINRules(minLength: 8)))),
			.asked(.secondFactor(SecondFactorRequest(purpose: .login, system: .fintsServer, challenge: .nameTANMedium(.apoTANDevice))))])
		#expect(recorded == [["type": "answer", "id": "2", "value": ""]])
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
		(#"{"type":"failed","kind":"appBlocked","code":"9010","text":"Kundenprodukt wurde vom Benutzer deaktiviert"}"#,
			.appBlocked(BankMessage(code: "9010", text: "Kundenprodukt wurde vom Benutzer deaktiviert"))),
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
		// Far above the 40 seconds that a run on CI can wait for a thread of Swift concurrency.
		let grace: TimeInterval = 120
		let task = Task {
			try await connector("""
				read cmd
				echo '{"type":"progress","done":0,"of":1}'
				read line; printf '%s\\n' "$line" >> "$R"
				""", inactivity: 300, grace: grace).refresh(RefreshRequest(access: Self.access, accounts: [Self.giro]), session)
		}
		await until { session.events.contains(.progress(.fetching(done: 0, of: 1))) }
		let canceled = ContinuousClock.now
		task.cancel()
		await #expect(throws: CancellationError.self) { try await task.value }
		// Only a helper that ends by itself lets the run end before the grace is over.
		#expect(ContinuousClock.now - canceled < .seconds(grace)) // time-ok: the grace holds 120 s for a loaded runner
		#expect(recorded.map { $0["type"] } == ["cancel"])
	}

	@Test("A helper that ignores cancel ends after 5 seconds")
	func cancelIgnored() async throws {
		let session = Session()
		let task = Task {
			try await connector("""
				read cmd
				echo '{"type":"progress","done":0,"of":1}'
				\(Self.terminatedTrap)
				read line; printf '%s\\n' "$line" >> "$R"
				echo "{\\"type\\":\\"waiting\\",\\"at\\":$(date +%s)}" >> "$R"
				sleep 60 & wait
				""", inactivity: 300).refresh(RefreshRequest(access: Self.access, accounts: [Self.giro]), session)
		}
		await until { session.events.contains(.progress(.fetching(done: 0, of: 1))) }
		let canceled = ContinuousClock.now
		task.cancel()
		await #expect(throws: CancellationError.self) { try await task.value }
		#expect(ContinuousClock.now - canceled >= .seconds(5))
		#expect(recorded.map { $0["type"] } == ["cancel", "waiting", "terminated"], "\(recorded)")
	}

	@Test("Cancel returns at once while the helper does not read its input, and the helper ends after 5 seconds", .timeLimit(.minutes(2)))
	func cancelBlockedWrite() async throws {
		// A state far larger than the buffer of a pipe, to a helper that never reads it.
		let state = AccessState(Data(repeating: 7, count: 1_000_000))
		let task = Task {
			try await connector(#"\#(Self.terminatedTrap); echo '{"type":"ready"}' >> "$R"; sleep 60 & wait"#, inactivity: 300)
				.listAccounts(of: Self.access, state: state, session: Session())
		}
		try await helperReady()
		let canceled = ContinuousClock.now
		task.cancel()
		// A cancel that waited for the write would return only when the helper ends, 5 seconds later.
		#expect(ContinuousClock.now - canceled < .seconds(5)) // time-ok: the helper ends at 5 s, so the limit cannot grow
		await #expect(throws: CancellationError.self) { try await task.value }
		#expect(ContinuousClock.now - canceled >= .seconds(5))
		#expect(recorded.map { $0["type"] } == ["ready", "terminated"])
	}

	@Test("A helper that ignores SIGTERM is killed, and the canceled refresh ends", .timeLimit(.minutes(3)))
	func cancelIgnoresTerm() async throws {
		let grace: TimeInterval = 1
		let task = Task {
			try await connector(#"trap '' TERM; echo '{"type":"ready"}' >> "$R"; read cmd; exec sleep 600"#, inactivity: 300, grace: grace, killAfter: 2)
				.listAccounts(of: Self.access, state: nil, session: Session())
		}
		try await helperReady()
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
				\(Self.terminatedTrap)
				read line; printf '%s\\n' "$line" >> "$R"
				sleep 60 & wait
				""", inactivity: inactivity, grace: grace).refresh(RefreshRequest(access: Self.access, accounts: [Self.giro]), Session())
		}
		#expect(ContinuousClock.now - start >= .seconds(inactivity + grace))
		#expect(recorded.map { $0["type"] } == ["cancel", "terminated"])
	}

	// The limit only ends a run that hangs because the watchdog never fired: the helper waits in `read` before its `sleep 60`.
	@Test("A helper that sends a line and then stays silent fails with a timeout", .timeLimit(.minutes(3)))
	func timeoutAfterLine() async throws {
		// The line counts until the run has handled it. Afterwards the silence must time out, as when
		// the helper reported that it sent a message and the bank never answers.
		let start = Date.now
		await #expect(throws: SyncFailure.network("The connection to the FinTS server of the bank timed out. Try again later.")) {
			try await connector("""
				read cmd
				\(Self.terminatedTrap)
				echo '{"type":"alive"}'
				read line; printf '%s\\n' "$line" >> "$R"
				sleep 60 & wait
				""", inactivity: 1, grace: 1).refresh(RefreshRequest(access: Self.access, accounts: [Self.giro]), Session())
		}
		#expect(recorded.map { $0["type"] } == ["cancel", "terminated"])
		// The helper would end on its own after 60 seconds; termination ends it after about 2.
		#expect(try #require(secondsToTermination(since: start)) < 30) // time-ok: about 2 s against the 60 s of the helper
	}

	@Test("A helper that closes its output but keeps running gets the cancel and ends")
	func outputClosedEarly() async throws {
		let run = Task {
			try? await connector("""
				read cmd
				exec >&-
				\(Self.terminatedTrap)
				read line; printf '%s\\n' "$line" >> "$R"
				sleep 60 & wait
				""", grace: 1).refresh(RefreshRequest(access: Self.access, accounts: [Self.giro]), Session())
		}
		// Without the cancel, the run would wait for the helper until its sleep ends and could not be
		// awaited soon. The deadline lies far above the 40 seconds that the run can wait on CI for a thread.
		let start = ContinuousClock.now
		while !recorded.contains(where: { $0["type"] == "terminated" }), ContinuousClock.now - start < .seconds(120) { // time-ok: a deadline far above the wait on CI
			try await Task.sleep(for: .milliseconds(100))
		}
		#expect(recorded.map { $0["type"] } == ["cancel", "terminated"])
		guard recorded.contains(where: { $0["type"] == "terminated" }) else { return }
		_ = await run.value
	}

	@Test("A helper that does not read a large state fails with a timeout")
	func timeoutBlockedWrite() async throws {
		let state = AccessState(Data(repeating: 7, count: 1_000_000))
		let start = Date.now
		await #expect(throws: SyncFailure.network("The connection to the FinTS server of the bank timed out. Try again later.")) {
			// The helper never reads its input, so the write of the command blocks.
			try await connector("""
				\(Self.terminatedTrap)
				sleep 60 & wait
				""", inactivity: 1, grace: 1).listAccounts(of: Self.access, state: state, session: Session())
		}
		// The helper would end on its own after 60 seconds; termination ends it after about 2.
		#expect(try #require(secondsToTermination(since: start)) < 30) // time-ok: about 2 s against the 60 s of the helper
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
		let recent = AccountRequest(accountID: UUID(), name: "Giro", remoteID: "A", since: today.adding(days: -10), currency: "EUR")
		let old = AccountRequest(accountID: UUID(), name: "Savings", remoteID: "B", since: today.adding(days: -200), currency: "EUR")
		let new = AccountRequest(accountID: UUID(), name: "Card", remoteID: "C", currency: "EUR")
		let script = "read cmd; printf '%s\\n' \"$cmd\" >> \"$R\""
		_ = try await refresh(script, accounts: [recent, old, new])
		_ = try await refresh(script, accounts: [recent, old, new], enforced: true)
		#expect(recorded.map { $0["accounts"] } == [
			"[{\"from\":\"\(today.adding(days: -10))\",\"id\":\"A\"},{\"from\":\"\(today.adding(days: -90))\",\"id\":\"B\"},{\"id\":\"C\"}]",
			"[{\"id\":\"A\"},{\"id\":\"B\"},{\"id\":\"C\"}]",
		])
	}

	@Test("A first refresh whose challenge for older transactions the user cancels gets the last 90 days without an error", arguments: ["tan", "approve"])
	func olderTransactionsSkipped(kind: String) async throws {
		let ninety = Day.today().adding(days: -90)
		let session = Session { request in
			if case let .secondFactor(second) = request, second.olderTransactions { throw OlderTransactionsSkipped() }
			return try await Session.standard(request)
		}
		let report = try await refresh("""
			read cmd
			echo '{"type":"ask","id":1,"kind":"\(kind)","purpose":"download","prompt":"Bitte bestätigen Sie den Abruf.","history":true}'
			read answer; printf '%s\\n' "$answer" >> "$R"
			echo '{"type":"result","account":"DE02120300000000202051","balance":{"amount":"10.00","currency":"EUR"},"transactions":{"from":"\(ninety)","rows":[]},"errors":[]}'
			""", session: session)
		#expect(recorded == [["type": "answer", "id": "1", "skip": "true"]])
		guard case let .fetched(result) = report.outcomes[Self.giro.accountID] else { Issue.record("giro not fetched"); return }
		#expect(result.missesOlder)
		#expect(!result.isComplete)
		#expect(result.transactionFailure == nil)
		#expect(session.events.contains { if case let .asked(.secondFactor(second)) = $0 { second.olderTransactions && second.purpose == .download } else { false } })
	}

	@Test("The fake helper of a debug build brings 90 days after the user canceled the TAN for the full history of the login \"historie\"")
	func fakeHelperHistory() async throws {
		let script = URL(filePath: #filePath).deletingLastPathComponent().appending(path: "../../scripts/fake-fints-helper.sh").standardized
		let access = Access(source: Self.access.source, bankName: "Musterbank", loginName: "historie")
		let connector = FinTSConnector(helper: .init(executable: URL(filePath: "/bin/sh"), arguments: [script.path]), productID: "TESTPRODUCT", version: "0.0.1")
		let session = Session { request in
			if case let .secondFactor(second) = request, second.olderTransactions { throw OlderTransactionsSkipped() }
			return try await Session.standard(request)
		}
		let report = try await connector.refresh(RefreshRequest(access: access, accounts: [Self.giro]), session)
		guard case let .fetched(result) = report.outcomes[Self.giro.accountID] else { Issue.record("giro not fetched"); return }
		#expect(result.transactions?.from == Day.today().adding(days: -90))
		#expect(result.missesOlder)
	}

	@Test("A refresh says that older transactions may be missing only when its answer starts after the last successful fetch")
	func longPause() async throws {
		let today = Day.today()
		// 200 days of pause: the 90 days leave a gap.
		let old = AccountRequest(accountID: UUID(), name: "Giro", remoteID: "A", since: today.adding(days: -214), lastFetched: today.adding(days: -200), currency: "EUR")
		// 80 days of pause: the 14 days of overlap reach back 94 days, but the 90 days cover everything since the last fetch.
		let pause = AccountRequest(accountID: UUID(), name: "Savings", remoteID: "B", since: today.adding(days: -94), lastFetched: today.adding(days: -80), currency: "EUR")
		// A pending row from 120 days ago, fetched yesterday.
		let pending = AccountRequest(accountID: UUID(), name: "Card", remoteID: "C", since: today.adding(days: -120), lastFetched: today.adding(days: -1), currency: "EUR")
		let recent = AccountRequest(accountID: UUID(), name: "Daily", remoteID: "D", since: today.adding(days: -10), lastFetched: today.adding(days: 4 - 14), currency: "EUR")
		let report = try await refresh("""
			read cmd
			echo '{"type":"result","account":"A","transactions":{"from":"\(today.adding(days: -90))","rows":[]},"errors":[]}'
			echo '{"type":"result","account":"B","transactions":{"from":"\(today.adding(days: -90))","rows":[]},"errors":[]}'
			echo '{"type":"result","account":"C","transactions":{"from":"\(today.adding(days: -90))","rows":[]},"errors":[]}'
			echo '{"type":"result","account":"D","transactions":{"from":"\(today.adding(days: -10))","rows":[]},"errors":[]}'
			""", accounts: [old, pause, pending, recent])
		let missing = [old, pause, pending, recent].map { request -> Bool? in
			if case let .fetched(result) = report.outcomes[request.accountID] { result.missesOlder } else { nil }
		}
		#expect(missing == [true, false, false, false])
	}

	@Test("The state of the access is the passport alone: each result says what its own answer misses, and the account keeps the mark")
	func markNotInState() async throws {
		let today = Day.today()
		let passport = Data([0xAC, 0xED, 0x00, 0x05, 0x01])
		let next = Data([0xAC, 0xED, 0x00, 0x05, 0x02])
		func refresh(from: String, first: Bool = false) async throws -> (RefreshResult?, AccessState?) {
			let giro = AccountRequest(accountID: Self.giro.accountID, name: "Giro", remoteID: Self.giro.remoteID, since: first ? nil : today.adding(days: -15),
				lastFetched: first ? nil : today.adding(days: -1), currency: "EUR")
			let report = try await connector("""
				read cmd; printf '%s\\n' "$cmd" >> "$R"
				echo '{"type":"result","account":"DE02120300000000202051","transactions":{"from":\(from),"rows":[]},"errors":[]}'
				echo '{"type":"state","data":"\(next.base64EncodedString())"}'
				""").refresh(RefreshRequest(access: Self.access, state: AccessState(passport), accounts: [giro]), Session())
			guard case let .fetched(result) = report.outcomes[giro.accountID] else { return (nil, report.state) }
			return (result, report.state)
		}
		// The user canceled the TAN for older transactions in the first refresh of the account.
		let (first, state) = try await refresh(from: "\"\(today.adding(days: -90))\"", first: true)
		#expect(first?.missesOlder == true)
		#expect(state == AccessState(next))
		// A normal refresh covers the days since the last fetch, so its own answer misses nothing.
		let (normal, _) = try await refresh(from: "\"\(today.adding(days: -15))\"")
		#expect(normal?.missesOlder == false)
		#expect(normal?.missesOlder(after: true) == true)
		#expect(recorded.map { $0["state"] } == [passport.base64EncodedString(), passport.base64EncodedString()])
	}

	@Test("A challenge with \"history\" may be for older transactions, and one without is not")
	func historyOfAsk() throws {
		func request(_ history: String) throws -> UserRequest {
			let line = #"{"type":"ask","id":1,"kind":"tan","purpose":"download","prompt":"Bitte TAN eingeben"\#(history)}"#
			guard case let .ask(_, ask) = try JSONDecoder().decode(HelperMessage.self, from: Data(line.utf8)) else { throw HelperFailure.unreadable }
			return try ask.request(server: nil)
		}
		guard case let .secondFactor(older) = try request(#","history":true"#), case let .secondFactor(plain) = try request("") else {
			Issue.record("no second factor")
			return
		}
		#expect(older.olderTransactions)
		#expect(!plain.olderTransactions)
	}

	@Test("Reads the lines that the helper writes for an MT940 statement, a camt.052 report, securities accounts, and accounts that fail")
	func helperLines() async throws {
		// The self-test of the helper writes this file: scripts/build-fints-helper.sh.
		let lines = URL(filePath: #filePath).deletingLastPathComponent().appending(path: "helper-lines.jsonl")
		let card = AccountRequest(accountID: UUID(), name: "Card", remoteID: "4711", currency: "EUR")
		let depots = ["7654321", "7654322", "7654323", "7654324", "7654325", "7654326"].map { AccountRequest(accountID: UUID(), name: "Depot", remoteID: $0, currency: "EUR") }
		let creditCard = AccountRequest(accountID: UUID(), name: "Visa", remoteID: "1234567890123456", since: Day(year: 2026, month: 10, day: 1), currency: "EUR")
		let report = try await refresh("read cmd; cat '\(lines.path)'", accounts: [Self.giro, Self.savings, card, creditCard] + depots)

		guard case let .fetched(depot) = report.outcomes[depots[0].accountID] else { Issue.record("depot not fetched"); return }
		#expect(depot.balance == Money(minorUnits: 2_451_837, currency: "EUR"))
		#expect(depot.balanceDate.map { Day($0) } == Day(year: 2026, month: 11, day: 12))
		#expect(depot.transactions == nil)
		#expect(depot.transactionFailure == nil)
		#expect(depot.isPortfolio)
		// A position without a name takes its ISIN as the name.
		#expect(depot.holdings?.map { Holding(id: UUID(uuidString: "00000000-0000-0000-0000-000000000000")!, accountID: $0.accountID, security: $0.security,
			quantity: $0.quantity, marketValue: $0.marketValue) } == [Holding(id: UUID(uuidString: "00000000-0000-0000-0000-000000000000")!,
			accountID: depots[0].accountID, security: Security(name: "DE0001234567", isin: "DE0001234567"), quantity: 1,
			marketValue: Money(minorUnits: 1_000_000, currency: "EUR"))])
		guard case let .fetched(empty) = report.outcomes[depots[4].accountID] else { Issue.record("empty depot not fetched"); return }
		#expect(empty.balance == Money(minorUnits: 0, currency: "EUR"))
		#expect(empty.isPortfolio)
		#expect(empty.balanceDate.map { Day($0) } == Day(year: 2026, month: 11, day: 13))
		#expect(empty.holdings?.isEmpty == true)
		guard case let .fetched(positions) = report.outcomes[depots[5].accountID] else { Issue.record("depot with positions not fetched"); return }
		let held = positions.holdings ?? []
		#expect(held.count == 2)
		if held.count == 2 {
			let posix = Locale(identifier: "en_US_POSIX")
			#expect(held[0] == Holding(id: held[0].id, accountID: depots[5].accountID,
				security: Security(name: "Musterwerke AG", isin: "DE0001234567", securityNumber: "123456"), quantity: Decimal(string: "40.12345", locale: posix)!,
				quote: Quote(amount: Decimal(string: "27.123456", locale: posix)!, currency: "USD", day: Day(year: 2026, month: 11, day: 11)),
				marketValue: Money(minorUnits: 100_000, currency: "EUR"), accruedInterest: Money(minorUnits: 10, currency: "EUR"),
				purchasePrice: Quote(amount: Decimal(string: "20.5", locale: posix)!, currency: "USD", day: Day(year: 2024, month: 3, day: 1)),
				exchangeRate: ExchangeRate(base: "EUR", quoted: "USD", rate: Decimal(string: "1.0845", locale: posix)!)))
			// A nominal amount without a currency of the security keeps its currency unknown. "%" is a percentage.
			#expect(held[1] == Holding(id: held[1].id, accountID: depots[5].accountID, security: Security(name: "Anleihe Musterland"), quantity: 5000,
				isNominal: true, quote: Quote(amount: Decimal(string: "98.5", locale: posix)!, currency: nil),
				marketValue: Money(minorUnits: 492_500, currency: "EUR"), purchasePrice: Quote(amount: 97, currency: nil)))
		}
		let failures = depots.dropFirst().prefix(3).map { request -> SyncFailure? in
			if case let .failed(failure) = report.outcomes[request.accountID] { failure } else { nil }
		}
		#expect(failures == [
			.unsupported("The bank sent no value for this securities account."),
			.bank(BankMessage(code: "9160", text: "Erforderliche Auftragsreferenz fehlt")),
			.unsupported("Moneten can't read this securities account at this bank yet."),
		])

		guard case let .fetched(giro) = report.outcomes[Self.giro.accountID] else { Issue.record("giro not fetched"); return }
		#expect(giro.balance == Money(minorUnits: 109_620, currency: "EUR"))
		#expect(giro.balanceDate.map { Day($0) } == Day(year: 2026, month: 11, day: 3))
		#expect(giro.transactions?.from == Day(year: 2026, month: 10, day: 1))
		#expect(!giro.isPortfolio)
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

		// The card statement of a credit card brings its balance and its transactions in one answer.
		guard case let .fetched(statement) = report.outcomes[creditCard.accountID] else { Issue.record("credit card not fetched"); return }
		#expect(statement.balance == Money(minorUnits: -123_456, currency: "EUR"))
		#expect(statement.balanceDate.map { Day($0) } == Day(year: 2026, month: 11, day: 12))
		#expect(statement.transactions?.from == Day(year: 2026, month: 10, day: 1))
		#expect(statement.transactions?.rows.map { [$0.amountMinor.description, $0.name, $0.purpose, $0.bookingText ?? "", "\($0.isPending)"] }
			== [["-1990", "Streaming Beispiel", "Streaming Beispiel / Musterstadt", "Kreditkartenzahlung", "false"],
				["-15000", "Hotel Beispiel", "Hotel Beispiel / Musterstadt", "Kreditkartenzahlung", "true"]])
		#expect(statement.transactions?.rows.map { [$0.bookingDate, $0.valueDate] }
			== [[Day(year: 2026, month: 11, day: 9), Day(year: 2026, month: 11, day: 8)], [Day(year: 2026, month: 11, day: 10), Day(year: 2026, month: 11, day: 10)]])
		#expect(statement.transactionFailure == nil)
	}

	@Test("A row without a currency gets the currency of the account")
	func rowCurrency() async throws {
		let dollars = AccountRequest(accountID: UUID(), name: "Dollar", remoteID: "1234567890", currency: "USD")
		let report = try await refresh(#"""
			read cmd
			echo '{"type":"result","account":"1234567890","transactions":{"rows":[{"type":"row","booked":"2026-11-02","amount":"-12.5","name":"Diner","pending":false}]},"errors":[]}'
			"""#, accounts: [dollars])
		guard case let .fetched(result) = report.outcomes[dollars.accountID] else { Issue.record("not fetched"); return }
		#expect(result.transactions?.rows.map(\.currency) == ["USD"])
		#expect(result.transactions?.rows.map(\.amountMinor) == [-1_250])
	}

	@Test("Fails two requests for the same account of the bank, and fetches the others")
	func clash() async throws {
		let twin = AccountRequest(accountID: UUID(), name: "Giro 2", remoteID: Self.giro.remoteID, currency: "EUR")
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
		let card = AccountRequest(accountID: UUID(), name: "Card", remoteID: "4711", currency: "EUR")
		let loan = AccountRequest(accountID: UUID(), name: "Loan", remoteID: "777", currency: "EUR")
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

		// A first refresh whose answer starts 90 days ago may miss older transactions, and the state is the passport alone.
		#expect(giro.missesOlder)
		#expect(report.state == AccessState(Data([1, 2, 3])))
		#expect(report.notices == [BankMessage(text: "Neue Bedingungen ab 1.12."), BankMessage(code: "9210", text: "Saldo nicht verfügbar", accountName: "Card")])
		#expect(session.events == [.progress(.fetching(done: 0, of: 3)), .progress(.fetching(done: 1, of: 3))])
	}

	@Test("A result that does not read fails only its account", arguments: [
		(#"{"type":"result","account":"DE02120300000000202051","transactions":{"rows":[{"booked":"2026-11-02","amount":"zwölf","pending":false}]},"errors":[]}"#,
			HelperFailure.unreadable),
		(#"{"type":"result","account":"DE02120300000000202051","balance":{"currency":"EUR"},"errors":[]}"#, HelperFailure.unreadable),
		// An amount whose minor units do not fit would otherwise turn into another amount.
		(#"{"type":"result","account":"DE02120300000000202051","transactions":{"rows":[{"booked":"2026-11-02","amount":"-92233720368547758.08","pending":false}]},"errors":[]}"#,
			HelperFailure.tooLarge),
		(#"{"type":"result","account":"DE02120300000000202051","transactions":{"rows":[{"amount":"-1","pending":true}]},"errors":[]}"#,
			SyncFailure.unsupported("The bank sent a transaction without a booking date, so nothing of this account was stored.")),
		(#"{"type":"result","account":"DE02120300000000202051","balance":{"amount":"1","currency":"EUR"},"errors":[],"securities":true,"holdings":[{"name":"Gold","quantity":"12abc"}]}"#,
			HelperFailure.unreadable),
		(#"{"type":"result","account":"DE02120300000000202051","balance":{"amount":"1","currency":"EUR"},"errors":[],"securities":true,"holdings":[{"name":"Gold"}]}"#,
			HelperFailure.unreadable),
		// A quantity times a price beyond the limit fails its account, also without a market value from the bank.
		(#"{"type":"result","account":"DE02120300000000202051","balance":{"amount":"1","currency":"EUR"},"errors":[],"securities":true,"holdings":[{"name":"Gold","quantity":"10000000000","price":{"amount":"10000000000","currency":"EUR"}}]}"#,
			HelperFailure.tooLarge),
		// An amount above 10.000.000.000.000,00 € fails its account, so no sum of stored amounts can overflow (issue #324).
		(#"{"type":"result","account":"DE02120300000000202051","balance":{"amount":"50000000000000000.00","currency":"EUR"},"errors":[]}"#, HelperFailure.tooLarge),
		(#"{"type":"result","account":"DE02120300000000202051","transactions":{"rows":[{"booked":"2026-11-02","amount":"-10000000000000.01","pending":false}]},"errors":[]}"#,
			HelperFailure.tooLarge),
		(#"{"type":"result","account":"DE02120300000000202051","balance":{"amount":"1","currency":"EUR"},"errors":[],"securities":true,"holdings":[{"name":"Gold","quantity":"1","value":{"amount":"1e20","currency":"EUR"}}]}"#,
			HelperFailure.unreadable),
		(#"{"type":"result","account":"DE02120300000000202051","balance":{"amount":"1","currency":"EUR"},"errors":[],"securities":true,"holdings":[{"name":"Gold","quantity":"1","value":{"amount":"20000000000000","currency":"EUR"}}]}"#,
			HelperFailure.tooLarge),
	] + ["12.3.4", "1-2", "-", ".", "--5", "1.", ".5", "-0.5.1"].flatMap { number in [
		// A number that reads only in part fails its account, in a quantity, a price, and a balance alike.
		(#"{"type":"result","account":"DE02120300000000202051","balance":{"amount":"1","currency":"EUR"},"errors":[],"securities":true,"holdings":[{"name":"Gold","quantity":"\#(number)"}]}"#,
			HelperFailure.unreadable),
		(#"{"type":"result","account":"DE02120300000000202051","balance":{"amount":"1","currency":"EUR"},"errors":[],"securities":true,"holdings":[{"name":"Gold","quantity":"1","price":{"amount":"\#(number)","currency":"EUR"}}]}"#,
			HelperFailure.unreadable),
		(#"{"type":"result","account":"DE02120300000000202051","balance":{"amount":"\#(number)","currency":"EUR"},"errors":[]}"#, HelperFailure.unreadable),
	] })
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
		(#"{"type":"failed","code":"9931","text":"Teilnehmersperre durchgeführt, Entsperren nur durch Kreditinstitut"}"#,
			.accessBlocked(BankMessage(code: "9931", text: "Teilnehmersperre durchgeführt, Entsperren nur durch Kreditinstitut"))),
		(#"{"type":"ask","id":1,"kind":"pin","rejected":{"code":"9931","text":"Sperrung des Kontos nach 3 Fehlversuchen"}}"#,
			.accessBlocked(BankMessage(code: "9931", text: "Sperrung des Kontos nach 3 Fehlversuchen"))),
		(#"{"type":"failed","code":"9931","text":"Zugang wegen ungültiger PIN gesperrt"}"#, .accessBlocked(BankMessage(code: "9931", text: "Zugang wegen ungültiger PIN gesperrt"))),
		(#"{"type":"failed","code":"9931","text":"Sperrung des Kontos wegen ungültiger PIN"}"#, .accessBlocked(BankMessage(code: "9931", text: "Sperrung des Kontos wegen ungültiger PIN"))),
		(#"{"type":"failed","code":"9931","text":"PIN falsch. Weitere Fehlversuche führen zur Sperrung."}"#,
			.pinRejected(BankMessage(code: "9931", text: "PIN falsch. Weitere Fehlversuche führen zur Sperrung."))),
		(#"{"type":"failed","code":"9931","text":"PIN falsch, Zugang nicht gesperrt"}"#, .pinRejected(BankMessage(code: "9931", text: "PIN falsch, Zugang nicht gesperrt"))),
		(#"{"type":"failed","code":"9931","text":"PIN ungültig - Zugang ist blockiert"}"#, .accessBlocked(BankMessage(code: "9931", text: "PIN ungültig - Zugang ist blockiert"))),
		(#"{"type":"failed","code":"9931","text":"Anmeldung fehlgeschlagen"}"#, .pinRejected(BankMessage(code: "9931", text: "Anmeldung fehlgeschlagen"))),
		(#"{"type":"failed","code":"9010","text":"Verarbeitung nicht möglich"}"#, .bank(BankMessage(code: "9010", text: "Verarbeitung nicht möglich"))),
		(#"{"type":"failed","text":"Dialog abgebrochen"}"#, .bank(BankMessage(text: "Dialog abgebrochen"))),
		(#"{"type":"failed","kind":"network","text":"Connection refused"}"#, .network("Connection refused")),
		(#"{"type":"failed","kind":"invalidChallenge","text":"The bank responded with an invalid challenge."}"#, .invalidChallenge),
		(#"{"type":"failed","kind":"unsupported","text":"The bank offers no encrypted FinTS address."}"#, .unsupported("The bank offers no encrypted FinTS address.")),
		(#"{"type":"failed","kind":"certificate","text":"The certificate of the server fints.example.com is not valid."}"#,
			.network("The certificate of the server fints.example.com is not valid.")),
		(#"{"type":"ask","id":1,"kind":"pin","rejected":{"code":"9930","text":"PIN gesperrt"}}"#, .accessBlocked(BankMessage(code: "9930", text: "PIN gesperrt"))),
		(#"{"type":"failed","code":"9933","text":"Ihr Zugang ist gesperrt"}"#, .accessBlocked(BankMessage(code: "9933", text: "Ihr Zugang ist gesperrt"))),
		(#"{"type":"failed","code":"3938","text":"Zugang vorläufig gesperrt"}"#, .accessBlocked(BankMessage(code: "3938", text: "Zugang vorläufig gesperrt"))),
		(#"{"type":"ask","id":1,"kind":"pin","rejected":{"code":"3938","text":"Zugang vorläufig gesperrt"}}"#,
			.accessBlocked(BankMessage(code: "3938", text: "Zugang vorläufig gesperrt"))),
		(#"{"type":"failed","code":"3931","text":"TAN-Generator gesperrt"}"#, .bank(BankMessage(code: "3931", text: "TAN-Generator gesperrt"))),
		(#"{"type":"failed","kind":"appBlocked","code":"9010","text":"Kundenprodukt wurde vom Benutzer deaktiviert"}"#,
			.appBlocked(BankMessage(code: "9010", text: "Kundenprodukt wurde vom Benutzer deaktiviert"))),
		(#"{"type":"ask","id":1,"kind":"pin","rejected":{"kind":"appBlocked","code":"9931","text":"Kundenprodukt wurde vom Benutzer deaktiviert"}}"#,
			.appBlocked(BankMessage(code: "9931", text: "Kundenprodukt wurde vom Benutzer deaktiviert"))),
		(#"{"type":"failed","code":"9010","text":"Kundenprodukt wurde vom Benutzer deaktiviert"}"#,
			.bank(BankMessage(code: "9010", text: "Kundenprodukt wurde vom Benutzer deaktiviert"))),
		(#"{"type":"failed","kind":"loginReplaced","code":"9940","text":"Bitte melden Sie sich im Online-Banking an oder kontaktieren den Support."}"#,
			.loginReplaced(BankMessage(code: "9940", text: "Bitte melden Sie sich im Online-Banking an oder kontaktieren den Support."))),
		(#"{"type":"ask","id":1,"kind":"pin","rejected":{"kind":"loginReplaced","code":"9940","text":"Bitte melden Sie sich im Online-Banking an oder kontaktieren den Support."}}"#,
			.loginReplaced(BankMessage(code: "9940", text: "Bitte melden Sie sich im Online-Banking an oder kontaktieren den Support."))),
		(#"{"type":"failed","kind":"websiteLogin","code":"9942","text":"Bitte erneuern Sie ihre Authentifizierung. Einfach unter ING.de einloggen."}"#,
			.websiteLoginNeeded(BankMessage(code: "9942", text: "Bitte erneuern Sie ihre Authentifizierung. Einfach unter ING.de einloggen."))),
		(#"{"type":"ask","id":1,"kind":"pin","rejected":{"kind":"websiteLogin","code":"9942","text":"Bitte erneuern Sie ihre Authentifizierung. Einfach unter ING.de einloggen."}}"#,
			.websiteLoginNeeded(BankMessage(code: "9942", text: "Bitte erneuern Sie ihre Authentifizierung. Einfach unter ING.de einloggen."))),
		(#"{"type":"failed","code":"9941","text":"TAN ungültig"}"#, .tanRejected(BankMessage(code: "9941", text: "TAN ungültig"))),
		(#"{"type":"failed","code":"9943","text":"TAN bereits verbraucht"}"#, .tanRejected(BankMessage(code: "9943", text: "TAN bereits verbraucht"))),
		(#"{"type":"failed","code":"9948","text":"TAN-Prüfung fehlgeschlagen"}"#, .tanRejected(BankMessage(code: "9948", text: "TAN-Prüfung fehlgeschlagen"))),
		(#"{"type":"failed","kind":"approvalDeclined","code":"9951","text":"Zeitüberschreitung im Zwei-Schritt-Verfahren"}"#,
			.approvalDeclined(BankMessage(code: "9951", text: "Zeitüberschreitung im Zwei-Schritt-Verfahren"))),
		(#"{"type":"failed","code":"9951","text":"Zeitüberschreitung im Zwei-Schritt-Verfahren"}"#, .bank(BankMessage(code: "9951", text: "Zeitüberschreitung im Zwei-Schritt-Verfahren"))),
		(#"{"type":"failed","kind":"approvalDeclined","code":"9941","text":"Freigabe abgelehnt"}"#, .approvalDeclined(BankMessage(code: "9941", text: "Freigabe abgelehnt"))),
		// The access has the Bankleitzahl of DKB, so the next step names the DKB app (DKBTests).
		(#"{"type":"failed","kind":"noTANMethod","code":"9075","text":"Starke Kundenauthentifizierung notwendig"}"#,
			.noTANMethodOfBank(BankMessage(code: "9075", text: "Starke Kundenauthentifizierung notwendig"), nextStep: "Set up the DKB app as the approval method on the website of DKB first, then choose “Edit Login Data...”.")),
		(#"{"type":"failed","code":"9955","text":"Ein-Schritt-TAN-Verfahren nicht zugelassen"}"#, .bank(BankMessage(code: "9955", text: "Ein-Schritt-TAN-Verfahren nicht zugelassen"))),
	])
	func errors(line: String, expected: SyncFailure) async throws {
		let session = Session()
		#expect(await failure(of: "read cmd; echo '\(line)'", session: session) as? SyncFailure == expected)
		// No dialog opens. Only a rejection of the PIN or a block reaches the session, at once.
		#expect(session.events == (expected.rejectsPIN ? [.rejected(expected)] : []))
	}

	/// 9931 is a block only when its text has the phrase of a block that happened and no phrase of attempts that remain,
	/// of a block to come, or of a denial. Every other text is a wrong PIN. Where a text has both, as the last text with a
	/// block, the app shows one more PIN sheet, and never sends a PIN on its own.
	@Test("Reads a 9931 as a block only when its text reports a block that happened", arguments: [
		("Anmeldename oder PIN ist falsch", false),
		("PIN falsch. Weitere Fehlversuche führen zur Sperrung.", false),
		("Weitere Fehlversuche führen zur Sperrung", false),
		("Falsche PIN. Bei 2 weiteren Fehlversuchen wird Ihr Zugang gesperrt.", false),
		("PIN ungültig. Ihr Zugang wird nach dem nächsten Fehlversuch gesperrt.", false),
		("PIN falsch, Zugang nicht gesperrt", false),
		("PIN falsch - kein gesperrter Zugang", false),
		("Teilnehmersperre durchgeführt, Entsperren nur durch Kreditinstitut", true),
		("Zugang wegen ungültiger PIN gesperrt", true),
		("Sperrung des Kontos wegen ungültiger PIN", true),
		("Sperrung des Kontos nach 3 Fehlversuchen", true),
		("PIN ungültig - Zugang ist blockiert", true),
		("PIN falsch. Ihr Zugang wurde gesperrt.", true),
		("Zugang gesperrt und Anmeldung nicht mehr möglich", true),
		("Nach weiteren Fehlversuchen wurde der Zugang gesperrt", false),
		("Keine Sperrung erfolgt, PIN falsch", false),
		("Sperrung nicht durchgeführt", false),
		("Ihr Zugang ist vorläufig gesperrt - Bitte PIN-Sperre aufheben.", true),
		("Anmeldung fehlgeschlagen", false),
		("", false),
		("PIN falsch. Noch 1 Fehlversuch bis zur Sperrung.", false),
		("Zugang ist gesperrt und wird erst nach Freischaltung wieder nutzbar.", true),
		("Ihr Zugang wurde gesperrt.", true),
		("Bei der nächsten falschen Eingabe wird Ihr Zugang gesperrt.", false),
		("Noch 2 Versuche verbleibend. Danach wird die PIN gesperrt.", false),
		("Die Sperrung wurde durchgeführt.", true),
		("Ihre PIN ist gesperrt worden.", true),
		("Bei der nächsten falschen Eingabe ist Ihr Zugang gesperrt.", false),
		("Bei der nächsten Fehleingabe wird eine Sperre durchgeführt.", false),
		("PIN falsch. Bei weiterer Fehleingabe droht die Sperrung des Kontos.", false),
		("Ihr Zugang ist gesperrt und wird durch Ihre Bank entsperrt.", true),
	])
	func reads9931(text: String, blocked: Bool) {
		#expect(HelperError.reportsBlock(text) == blocked)
	}

	/// scripts/fake-fints-helper.sh, which a debug build runs in place of the helper, with the logins of its failures.
	static let fakeHelper = URL(filePath: #filePath).deletingLastPathComponent().appending(path: "../../scripts/fake-fints-helper.sh").standardized

	/// The fake helper without the wait of 3 seconds before it reports the declined approval. The app starts a helper with an
	/// empty environment, so `env` sets the variable.
	static let fakeConnector = FinTSConnector(helper: .init(executable: URL(filePath: "/usr/bin/env"),
		arguments: ["MONETEN_FAKE_APPROVAL_SECONDS=0", "/bin/sh", fakeHelper.path]), productID: "TESTPRODUCT", version: "0.0.1")

	static let blocked = SyncFailure.accessBlocked(BankMessage(code: "3938", text: "Ihr Zugang ist vorläufig gesperrt - Bitte PIN-Sperre aufheben."))
	static let deactivated = SyncFailure.appBlocked(BankMessage(code: "9010", text: "Kundenprodukt wurde vom Benutzer deaktiviert"))

	@Test("The fake helper of a debug build fails the refresh of each login of an error with that error", arguments: [
		("gesperrt", blocked),
		("deaktiviert", deactivated),
		("ohnetan", .noTANMethodOfBank(BankMessage(code: "9955", text: "Ein-Schritt-TAN-Verfahren nicht zugelassen"), nextStep: "Set up the DKB app as the approval method on the website of DKB first, then choose “Edit Login Data...”.")),
		("falschetan", .tanRejected(BankMessage(code: "9941", text: "TAN ungültig"))),
		("abgelehnt", .approvalDeclined(BankMessage(code: "9941", text: "Freigabe abgelehnt"))),
		("ersetzt", .loginReplaced(BankMessage(code: "9940", text: "Bitte melden Sie sich im Online-Banking an oder kontaktieren den Support."))),
	])
	func fakeHelper(login: String, expected: SyncFailure) async throws {
		let access = Access(source: Self.access.source, bankName: "Musterbank", loginName: login)
		await #expect(throws: expected) {
			_ = try await Self.fakeConnector.refresh(RefreshRequest(access: access, accounts: [Self.giro]), Session())
		}
	}

	@Test("The fake helper of a debug build fails the setup login of a blocked access, or of an app that the user blocked, and lists no accounts",
		arguments: [("gesperrt", blocked), ("deaktiviert", deactivated)])
	func fakeHelperBlockedSetup(login: String, expected: SyncFailure) async throws {
		let access = Access(source: Self.access.source, bankName: "Musterbank", loginName: login)
		await #expect(throws: expected) {
			_ = try await Self.fakeConnector.listAccounts(of: access, state: nil, session: Session())
		}
	}

	@Test("A run that fails after a notice of the bank keeps the notice with the failure")
	func noticeBeforeFailure() async throws {
		let error = await failure(of: #"""
			read cmd
			echo '{"type":"notice","text":"Wartungsarbeiten bis 5 Uhr"}'
			echo '{"type":"failed","code":"9800","text":"Dialog abgebrochen"}'
			"""#)
		let failure = try #require(error as? FailureWithNotices)
		#expect(failure.failure as? SyncFailure == .bank(BankMessage(code: "9800", text: "Dialog abgebrochen")))
		#expect(failure.notices == [BankMessage(text: "Wartungsarbeiten bis 5 Uhr")])
	}

	@Test("A login of the setup that fails after a notice of the bank keeps the notice with the failure")
	func noticeBeforeFailedSetupLogin() async throws {
		let error = await #expect(throws: FailureWithNotices.self) {
			try await connector(#"""
				read cmd
				echo '{"type":"notice","text":"Wartungsarbeiten bis 5 Uhr"}'
				echo '{"type":"failed","code":"9800","text":"Dialog abgebrochen"}'
				"""#).listAccounts(of: Self.access, state: nil, session: Session())
		}
		#expect(error?.failure as? SyncFailure == .bank(BankMessage(code: "9800", text: "Dialog abgebrochen")))
		#expect(error?.notices == [BankMessage(text: "Wartungsarbeiten bis 5 Uhr")])
	}

	@Test("A login of the setup that ends without accounts after a notice of the bank keeps the notice with the failure")
	func noticeBeforeSetupLoginWithoutAnswer() async throws {
		let error = await #expect(throws: FailureWithNotices.self) {
			try await connector(#"""
				read cmd
				echo '{"type":"notice","text":"Wartungsarbeiten bis 5 Uhr"}'
				"""#).listAccounts(of: Self.access, state: nil, session: Session())
		}
		#expect(error?.failure as? SyncFailure == HelperFailure.noAnswer)
		#expect(error?.notices == [BankMessage(text: "Wartungsarbeiten bis 5 Uhr")])
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
		_ = try await connector(#"read cmd; printf '%s\n' "${HOME-none} ${TMPDIR-none}" >> "$R"; echo '{"type":"banks","banks":[]}'"#).bankDirectory()
		#expect((try? String(contentsOf: record, encoding: .utf8)) == "none none\n")
		let arguments = FinTSConnector.Helper.bundled.arguments
		#expect(arguments.contains("-XX:ErrorFile=/dev/null"))
		#expect(arguments.contains("-Djava.net.useSystemProxies=true"))
		#expect(arguments.contains("-XX:+DisableAttachMechanism") && arguments.contains("-Xrs"))
		#expect(arguments.last == "FinTSHelper")
	}

	@Test("Reads the bank directory of the helper")
	func bankDirectory() async throws {
		let directory = try await connector(#"""
			read cmd; printf '%s\n' "$cmd" >> "$R"
			echo '{"type":"banks","banks":[{"code":"12030000","name":"Deutsche Kreditbank Berlin","city":"Berlin","bic":"BYLADEM1001","url":"https://fints.dkb.de/fints"},{"code":"10010424","name":"Aareal Bank","city":"Wiesbaden"}]}'
			"""#).bankDirectory()
		#expect(directory.bank(code: "12030000") == BankDirectory.Entry(code: "12030000", city: "Berlin",
			bank: FinTSBank(name: "Deutsche Kreditbank Berlin", bic: "BYLADEM1001", url: URL(string: "https://fints.dkb.de/fints"))))
		#expect(directory.bank(code: "10010424") == BankDirectory.Entry(code: "10010424", city: "Wiesbaden", bank: FinTSBank(name: "Aareal Bank", bic: nil, url: nil)))
		#expect(recorded == [["type": "banks"]])
		await #expect(throws: HelperFailure.unreadable) { try await connector(#"read cmd; echo '{"type":"notice","text":"x"}'"#).bankDirectory() }
		await #expect(throws: SyncFailure.bank(BankMessage(text: "hbci4java has no bank directory"))) {
			try await connector(#"read cmd; echo '{"type":"failed","text":"hbci4java has no bank directory"}'"#).bankDirectory()
		}
	}

	@Test("Sends the installed bank list in every command, read anew before each start of the helper")
	func sendsBankList() async throws {
		let list = Mutex<Data?>(Data("12030000=Musterbank|Berlin|BYLADEM1001|00||https://fints.example.com/fints|300|300|".utf8))
		let connector = connector(#"""
			read cmd; printf '%s\n' "$cmd" >> "$R"
			case "$cmd" in
			*'"type":"banks"'*) echo '{"type":"banks","banks":[]}' ;;
			*) echo '{"type":"result","account":"DE02120300000000202051","balance":{"amount":"1","currency":"EUR"},"errors":[]}' ;;
			esac
			"""#, bankList: { list.withLock { $0 } })
		_ = try await connector.bankDirectory()
		_ = try await connector.refresh(RefreshRequest(access: Self.access, accounts: [Self.giro], enforced: false), Session())
		list.withLock { $0 = nil }
		_ = try await connector.bankDirectory()
		let sent = recorded
		#expect(sent.count == 3)
		#expect(sent.map { $0["type"] } == ["banks", "refresh", "banks"])
		#expect(sent[0]["bankList"] == "12030000=Musterbank|Berlin|BYLADEM1001|00||https://fints.example.com/fints|300|300|")
		#expect(sent[1]["bankList"] == sent[0]["bankList"])
		#expect(sent[2]["bankList"] == nil)
	}

	/// Waits until the helper wrote `{"type":"ready"}` into `record`, which a script does once its signal
	/// handler is in place, so a cancel tests the handler also when the helper starts late.
	func helperReady() async throws {
		for _ in 0..<6000 where !recorded.contains(["type": "ready"]) {
			try await Task.sleep(for: .milliseconds(10))
		}
		try #require(recorded.contains(["type": "ready"]))
	}

	/// Waits until the condition holds, for at most five seconds.
	func until(_ condition: () -> Bool) async {
		for _ in 0..<500 where !condition() {
			try? await Task.sleep(for: .milliseconds(10))
		}
	}

	@Test("A helper that writes its currencies in lower case gives upper-case codes to the rows, the balance, the account, and the exchange rate")
	func lowerCaseCurrency() throws {
		let line = #"{"type":"result","account":"DE02120300000000202051","balance":{"amount":"10.00","currency":"eur"},"transactions":{"rows":[{"type":"row","booked":"2026-11-03","amount":"-89","currency":"eur","purpose":"Abschlag November","pending":false},{"type":"row","booked":"2026-11-04","amount":"-5","purpose":"Kiosk","pending":false}]},"errors":[]}"#
		let result = try JSONDecoder().decode(AccountResult.self, from: Data(line.utf8))
		let rows = try #require(result.transactions?.rows).map { try $0.transaction(of: Self.giro) }
		#expect(rows.map(\.currency) == ["EUR", "EUR"])
		#expect(try AccountResult.money("10.00", "eur").currency == "EUR")
		// The account of an accounts line.
		let accounts = #"{"type":"accounts","accounts":[{"number":"202051","iban":"DE02120300000000202051","kind":"1","currency":"usd"}]}"#
		guard case let .accounts(found) = try JSONDecoder().decode(HelperMessage.self, from: Data(accounts.utf8)) else { throw HelperFailure.unreadable }
		#expect(found.map(\.currency) == ["USD"])
		// 100,00 € plus 10,00 $ accrued interest at 1.25 USD for 1 EUR are 108,00 €.
		let position = #"{"name":"Anleihe","quantity":"100","nominal":true,"currency":"eur","value":{"amount":"100.00","currency":"eur"},"accrued":{"amount":"10.00","currency":"usd"},"rate":{"base":"eur","quoted":"usd","rate":"1.25"}}"#
		let holding = try JSONDecoder().decode(AccountResult.Position.self, from: Data(position.utf8)).holding(of: Self.giro)
		#expect(holding.value(in: "EUR") == Money(minorUnits: 10_800, currency: "EUR"))
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
