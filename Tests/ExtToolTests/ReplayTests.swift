import Foundation
import Testing

extension ExtTool {
	@Suite struct ReplayTests {
		/// A fixture recorded on 9 November 2026 at 10:00 UTC, with its exchanges as (method, URL, body).
		func fixture(_ exchanges: [(String, String, String)], extra: [String: Any] = [:]) throws -> String {
			let object = ["format": 1, "service": "Bank", "startTime": 1_794_218_400, "timeZone": "Europe/Berlin",
				"exchanges": exchanges.map { method, url, body in ["request": ["method": method, "url": url], "response": ["status": 200, "body": body]] },
			].merging(extra) { $1 }
			return String(decoding: try JSONSerialization.data(withJSONObject: object), as: UTF8.self)
		}

		func script(_ body: String) -> String {
			"""
			WebBanking{version = 1, services = {"Bank"}}
			function SupportsBank() return true end
			function InitializeSession() end
			function ListAccounts() return {{name = "Giro", accountNumber = "1", currency = "EUR"}} end
			\(body)
			"""
		}

		@Test func missingRequestNamesMethodAndURL() throws {
			let folder = try files([
				"Bank.lua": script("""
					function RefreshAccount() Connection():get("https://bank.example/accounts/2") return {balance = 0, transactions = {}} end
					"""),
				"Bank.json": #"{"hosts": ["bank.example"]}"#,
				"fixture.json": try fixture([("GET", "https://bank.example/accounts/1", "{}")]),
				"expected.json": "{}",
			])
			let run = try extOffline(["test", folder.appending(path: "Bank.lua").path, folder.appending(path: "fixture.json").path, folder.appending(path: "expected.json").path])
			#expect(run.status == 2)
			#expect(run.errors.contains("The fixture has no response for GET https://bank.example/accounts/2."))
		}

		@Test func thirtyDaysFromTheRecordedClock() throws {
			let folder = try files([
				"Bank.lua": script("""
					function RefreshAccount()
						local from = os.date("%Y-%m-%d", MM.date(os.time(), "-30D"))
						local rows = JSON(Connection():get("https://bank.example/transactions?from=" .. from)):dictionary()
						return {balance = 0, transactions = rows}
					end
					"""),
				"Bank.json": #"{"hosts": ["bank.example"]}"#,
				"fixture.json": try fixture([("GET", "https://bank.example/transactions?from=2026-10-10",
					#"[{"name": "Erika Mustermann", "amount": -89, "bookingDate": 1793876400}]"#)]),
			])
			let arguments = [folder.appending(path: "Bank.lua").path, folder.appending(path: "fixture.json").path, folder.appending(path: "expected.json").path]
			let update = try extOffline(["test"] + arguments + ["--update"])
			#expect(update.status == 0)
			#expect(update.output == "Wrote \(arguments[2]) with 1 account, 1 transaction.\n")
			for zone in ["America/New_York", "Asia/Tokyo"] {
				let run = try launch(URL(filePath: "/usr/bin/sandbox-exec"), ["-p", "(version 1)(allow default)(deny network*)", extBinary.path, "test"] + arguments,
					environment: ["TZ": zone])
				#expect(run.output == "PASS 1 account, 1 transaction\n")
			}
		}

		@Test func recordedRandomValuesAndAnswers() throws {
			let random: [[String: String]] = [["uuid": "3f6c2a9e-8d41-4b7a-9c35-1e2f4a6b8c0d"], ["bytes": "AAECAw=="]]
			let folder = try files([
				"Bank.lua": """
					WebBanking{version = 1, services = {"Bank"}}
					function SupportsBank() return true end
					function InitializeSession2(protocol, bankCode, step, credentials)
						if step == 1 then return {challenge = "Code from the SMS", label = "Code"} end
						code = credentials[1]
					end
					function ListAccounts()
						return {{name = MM.uuid() .. " " .. MM.binToHex(MM.random(4)) .. " " .. MM.binToHex(MM.random(2)) .. " " .. code, accountNumber = "1", currency = "EUR"}}
					end
					function RefreshAccount() MM.sleep(100) return {balance = os.time() - 1794218400, transactions = {}} end
					""",
				"fixture.json": try fixture([], extra: ["random": random, "answers": [["login": ["{{username}}", "{{password}}"]], ["tan": "{{answer1}}"]]]),
			])
			let arguments = ["test", folder.appending(path: "Bank.lua").path, folder.appending(path: "fixture.json").path, folder.appending(path: "expected.json").path]
			let started = ContinuousClock.now
			#expect(try extOffline(arguments + ["--update"]).status == 0)
			#expect(ContinuousClock.now - started < .seconds(30))
			let expected = try String(contentsOf: folder.appending(path: "expected.json"), encoding: .utf8)
			#expect(expected.contains("\"name\" : \"3f6c2a9e-8d41-4b7a-9c35-1e2f4a6b8c0d 00010203 "))
			#expect(expected.contains(" {{answer1}}\""))
			#expect(expected.contains("\"balance\" : 100"))
			#expect(try extOffline(arguments).output == "PASS 1 account, 0 transactions\n")
		}

		@Test func fixtureWithoutTimeZoneReplaysInUTC() throws {
			let folder = try files([
				"Bank.lua": script("function RefreshAccount() return {balance = 0, transactions = {}, name = os.date(\"%H:%M\", os.time())} end"),
				"fixture.json": #"{"exchanges": []}"#,
			])
			let arguments = ["test", folder.appending(path: "Bank.lua").path, folder.appending(path: "fixture.json").path, folder.appending(path: "expected.json").path]
			let update = try launch(extBinary, arguments + ["--update"], environment: ["TZ": "Europe/Berlin"])
			#expect(update.status == 0)
			#expect(try String(contentsOf: folder.appending(path: "expected.json"), encoding: .utf8).contains("\"name\" : \"00:00\""))
			#expect(try launch(extBinary, arguments, environment: ["TZ": "UTC"]).output == "PASS 1 account, 0 transactions\n")
		}

		@Test(arguments: [nil, [["login": ["{{username}}", "{{password}}"]]]] as [[[String: [String]]]?])
		func unknownHostNamesMethodAndURL(answers: [[String: [String]]]?) throws {
			let folder = try files([
				"Bank.lua": script("function RefreshAccount() Connection():get(\"https://other.example/x\") return {balance = 0, transactions = {}} end"),
				"fixture.json": try fixture([("GET", "https://bank.example/", "{}")], extra: answers.map { ["answers": $0] } ?? [:]),
			])
			let run = try extOffline(["test", folder.appending(path: "Bank.lua").path, folder.appending(path: "fixture.json").path, folder.appending(path: "e.json").path, "--update"])
			#expect(run.status == 2)
			#expect(run.errors.contains("The fixture has no response for GET https://other.example/x."))
		}

		@Test func differenceExitsWithOne() throws {
			let example = repository.appending(path: "Extensions/Example").path
			let fixture = repository.appending(path: "Fixtures/example/fixture.json").path
			let expected = try String(contentsOf: repository.appending(path: "Fixtures/example/expected.json"), encoding: .utf8)
			let folder = try files(["expected.json": expected.replacingOccurrences(of: "\"amount\" : -89,", with: "\"amount\" : -98.00,")])
			let run = try extOffline(["test", example, fixture, folder.appending(path: "expected.json").path])
			#expect(run.status == 1)
			#expect(run.output == "/accounts/0/transactions/0/amount: expected -98, got -89\nFAIL 1 difference\n")
		}

		@Test func exampleExtensionPasses() throws {
			let run = try extOffline(["test", repository.appending(path: "Extensions/Example").path, repository.appending(path: "Fixtures/example/fixture.json").path,
				repository.appending(path: "Fixtures/example/expected.json").path])
			#expect(run.status == 0)
			#expect(run.output == "PASS 1 account, 4 transactions\n")
		}
	}
}
