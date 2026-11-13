import ExtensionHost
import Foundation
import Testing
@testable import ext

extension ExtTool {
	@Suite struct CommandTests {
		@Test func helpAndVersion() throws {
			let help = try ext(["--help"])
			#expect(help.status == 0)
			#expect(help.output.contains("record <script> <fixture>"))
			let version = try ext(["--version"])
			#expect(version.status == 0)
			#expect(version.output == "ext 0.1.0, API version 1\n")
		}

		@Test(arguments: [["bogus"], [], ["run"], ["test", "A.lua", "f.json"], ["run", "A.lua", "--update"], ["run", "--service"], ["record", "A.lua", "f.json", "--loud"], ["run", "--service=", "A.lua"]])
		func wrongArguments(_ arguments: [String]) throws {
			let run = try ext(arguments)
			#expect(run.status == 64)
			#expect(run.errors.split(separator: "\n").count == 1)
		}

		@Test func missingScript() throws {
			let run = try ext(["run", "/nonexistent/Demo.lua"])
			#expect(run.status == 64)
			#expect(run.errors == "/nonexistent/Demo.lua: Demo.lua is missing or cannot be read.\n")
		}

		static let demo = """
			WebBanking{version = 1, services = {"Premium Account"}}
			function SupportsBank(protocol, bankCode) return bankCode == "Premium Account" end
			function InitializeSession(protocol, bankCode, username, customer, password)
				print("login " .. username)
				if password ~= "secret" then return LoginFailed end
			end
			function ListAccounts() return {{name = "Giro", accountNumber = "0202051", currency = "EUR", type = AccountTypeGiro}} end
			function RefreshAccount(account, since)
				return {balance = 12.5, transactions = {{name = "Erika Mustermann", amount = -89, bookingDate = 1793876400, purpose = "Rent"}}}
			end
			function EndSession() print("bye") end
			"""

		@Test func runPrintsJSONAndSendsPrintToStandardError() throws {
			let folder = try files(["Demo.lua": Self.demo])
			let run = try ext(["run", "Demo.lua"], environment: ["EXT_USERNAME": "erika", "EXT_PASSWORD": "secret"], folder: folder)
			#expect(run.status == 0)
			#expect(run.errors == "login erika\nbye\n")
			let document = try #require(try JSONSerialization.jsonObject(with: Data(run.output.utf8)) as? [String: Any])
			let accounts = try #require(document["accounts"] as? [[String: Any]])
			#expect(accounts.count == 1)
			#expect((accounts[0]["transactions"] as? [[String: Any]])?.first?["amount"] as? Int == -89)
			#expect(FileManager.default.fileExists(atPath: folder.appending(path: "Demo.storage.json").path))
		}

		@Test func loginDataFromTheTerminal() throws {
			let folder = try files(["Demo.lua": Self.demo])
			let run = try ext(["run", "Demo.lua"], input: "erika\nsecret\n", folder: folder)
			#expect(run.status == 0)
			#expect(run.errors.hasPrefix("Username: Password: login erika"))
		}

		@Test func rejectedLogin() throws {
			let folder = try files(["Demo.lua": Self.demo])
			let run = try ext(["run", "Demo.lua"], environment: ["EXT_USERNAME": "erika", "EXT_PASSWORD": "wrong"], folder: folder)
			#expect(run.status == 2)
			#expect(run.errors == "login erika\nThe service rejected the login data.\n")
			#expect(run.output.isEmpty)
		}

		@Test func scriptError() throws {
			let folder = try files(["Demo.lua": Self.demo.replacingOccurrences(of: "function ListAccounts() return", with: "function ListAccounts() error(\"no list\") return")])
			let run = try ext(["run", "Demo.lua"], environment: ["EXT_USERNAME": "erika", "EXT_PASSWORD": "secret"], folder: folder)
			#expect(run.status == 2)
			#expect(run.errors.hasSuffix("Demo.lua:7: no list\n"))
		}

		@Test func failedRecordingKeepsTheFixture() throws {
			let folder = try files(["Demo.lua": Self.demo, "good.json": "{\"exchanges\": []}"])
			let run = try ext(["record", "Demo.lua", "good.json"], environment: ["EXT_USERNAME": "erika", "EXT_PASSWORD": "wrong"], folder: folder)
			#expect(run.status == 2)
			#expect(run.errors == "login erika\nThe service rejected the login data.\n")
			#expect(try String(contentsOf: folder.appending(path: "good.json"), encoding: .utf8) == "{\"exchanges\": []}")
		}

		@Test func hostOutsideTheManifest() throws {
			let folder = try files([
				"Broker.lua": """
					WebBanking{version = 1, services = {"Broker"}}
					function SupportsBank() return true end
					function InitializeSession() Connection():get("https://tracker.example/pixel") end
					""",
				"Broker.json": #"{"hosts": ["api.broker.example"]}"#,
			])
			let run = try extOffline(["run", folder.appending(path: "Broker.lua").path, "--storage", folder.appending(path: "s.json").path],
				environment: ["EXT_USERNAME": "erika", "EXT_PASSWORD": "secret"])
			#expect(run.status == 2)
			#expect(run.errors.contains("Broker may not contact tracker.example, because its manifest does not list that host."))
		}

		@Test func choiceOfTheService() throws {
			let folder = try files(["Broker.lua": """
				WebBanking{version = 1, services = {"Broker", "Broker Business"}}
				function SupportsBank(protocol, bankCode) print("SupportsBank " .. bankCode) return true end
				function InitializeSession() end
				function ListAccounts() return {} end
				"""])
			let run = try ext(["run", "Broker.lua"], input: "2\n", environment: ["EXT_USERNAME": "erika", "EXT_PASSWORD": "secret"], folder: folder)
			#expect(run.status == 0)
			#expect(run.errors.hasPrefix("Broker has several services:\n1 Broker\n2 Broker Business\nNumber: SupportsBank Broker Business\n"))
		}

		@Test func challengesInTheTerminal() throws {
			let folder = try files(["Bank.lua": """
				WebBanking{version = 1, services = {"Bank"}}
				function SupportsBank() return true end
				function InitializeSession2(protocol, bankCode, step, credentials)
					if step == 1 then return {title = "Enter the code from the SMS.", label = "Code"} end
					if step == 2 then
						print("code " .. credentials[1])
						return {tanMethods = {{name = "pushTAN"}, {name = "mobileTAN"}}}
					end
					print("method " .. credentials[1].name)
				end
				function ListAccounts() return {} end
				"""])
			let run = try ext(["run", "Bank.lua"], input: "481516\n2\n", environment: ["EXT_USERNAME": "erika", "EXT_PASSWORD": "secret"], folder: folder)
			#expect(run.status == 0)
			#expect(run.errors.contains("Enter the code from the SMS.\nCode: code 481516\n"))
			#expect(run.errors.contains("1 pushTAN\n2 mobileTAN\nNumber: method mobileTAN\n"))
		}

		@Test func decoupledApprovalWaitsUntilTheScriptReturns() throws {
			let folder = try files(["Bank.lua": """
				WebBanking{version = 1, services = {"Bank"}}
				function SupportsBank() return true end
				function InitializeSession2(protocol, bankCode, step, credentials)
					if step == 1 then
						LocalStorage.polls = (LocalStorage.polls or 0) + 1
						if LocalStorage.polls < 2 then return {challenge = "Confirm in your banking app.", poll = true} end
					end
				end
				function ListAccounts() return {} end
				"""])
			let run = try ext(["run", "Bank.lua", "--fresh"], environment: ["EXT_USERNAME": "erika", "EXT_PASSWORD": "secret"], folder: folder)
			#expect(run.status == 0)
			#expect(run.errors.contains("Confirm in your banking app.\nWaiting for approval\n"))
		}

		@Test func localStorageSurvivesAndFreshStartsEmpty() throws {
			let folder = try files(["Demo.lua": """
				WebBanking{version = 1, services = {"Demo"}}
				function SupportsBank() return true end
				function InitializeSession()
					print(LocalStorage.deviceId and "found" or "empty")
					LocalStorage.deviceId = LocalStorage.deviceId or MM.uuid()
				end
				function ListAccounts() return {} end
				"""])
			let login = ["EXT_USERNAME": "erika", "EXT_PASSWORD": "secret"]
			#expect(try ext(["run", "Demo.lua"], environment: login, folder: folder).errors == "empty\n")
			#expect(try ext(["run", "Demo.lua"], environment: login, folder: folder).errors == "found\n")
			#expect(try ext(["run", "--fresh", "Demo.lua"], environment: login, folder: folder).errors == "empty\n")
			#expect(try ext(["run", "Demo.lua", "--storage", "other.json"], environment: login, folder: folder).errors == "empty\n")
		}
	
		/// A recording without requests: the key and the UUID of the script are withheld, and the replay
		/// gives values of the same length.
		@Test func recordingWithholdsRandomValuesAndReplays() throws {
			let folder = try files(["Demo.lua": """
				WebBanking{version = 1, services = {"Demo"}}
				function SupportsBank() return true end
				function InitializeSession() print(#MM.random(32) .. " " .. #MM.uuid()) end
				function ListAccounts() return {} end
				"""])
			let login = ["EXT_USERNAME": "erika", "EXT_PASSWORD": "geheim123"]
			let record = try ext(["record", "Demo.lua", "fixture.json"], environment: login, folder: folder)
			#expect(record.status == 0, "\(record.errors)")
			#expect(record.errors.contains(RecordCommand.hiddenLogin + "\n"))
			let fixture = try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: folder.appending(path: "fixture.json")))
			#expect(fixture.random == [.withheldBytes(32), .withheldUUID])
			#expect(try ext(["test", "Demo.lua", "fixture.json", "expected.json", "--update"], folder: folder).status == 0)
			let test = try ext(["test", "Demo.lua", "fixture.json", "expected.json"], folder: folder)
			#expect(test.output == "PASS 0 accounts, 0 transactions\n")
			#expect(test.errors == "32 36\n")
		}

		@Test func storageFileOnlyForItsOwner() throws {
			let folder = try files(["Demo.lua": Self.demo])
			#expect(try ext(["run", "Demo.lua"], environment: ["EXT_USERNAME": "erika", "EXT_PASSWORD": "secret"], folder: folder).status == 0)
			let attributes = try FileManager.default.attributesOfItem(atPath: folder.appending(path: "Demo.storage.json").path)
			#expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)
		}

		@Test(arguments: [("/b/Demo.lua", "/b/Demo.storage.json"), ("/b/My.Bank", "/b/My.Bank.storage.json"), ("/b/Demo", "/b/Demo.storage.json")])
		func storageFileNextToTheScript(script: String, storage: String) {
			#expect(RunCommand.defaultStorage(of: URL(filePath: script)).path == storage)
		}

		@Test func trustWithABrokenCertificate() throws {
			let folder = try files(["Demo.lua": Self.demo, "broken.pem": "-----BEGIN CERTIFICATE-----\nnot*base64\n-----END CERTIFICATE-----\n"])
			let run = try ext(["run", "Demo.lua", "--trust", "broken.pem"], environment: ["EXT_USERNAME": "erika", "EXT_PASSWORD": "secret"], folder: folder)
			#expect(run.status == 64)
			#expect(run.errors == "broken.pem holds a certificate whose Base64 is broken.\n")
		}

		/// In a terminal, a TAN does not show while the author types it. Python gives `ext` a pseudo-terminal
		/// and types the TAN only after the prompt, so that the terminal would echo it if it could.
		@Test func answerDoesNotEchoInATerminal() throws {
			let folder = try files(["Bank.lua": """
				WebBanking{version = 1, services = {"Bank"}}
				function SupportsBank() return true end
				function InitializeSession2(protocol, bankCode, step, credentials)
					if step == 1 then return {title = "Enter the code from the SMS.", label = "Code"} end
				end
				function ListAccounts() return {} end
				"""])
			let typing = """
				import os, pty, select, sys
				pid, fd = pty.fork()
				if pid == 0:
				    os.execv(sys.argv[1], [sys.argv[1], "run", "Bank.lua"])
				out = b""
				def read(until):
				    global out
				    while until not in out:
				        ready, _, _ = select.select([fd], [], [], 30)
				        if not ready: return
				        try: chunk = os.read(fd, 1024)
				        except OSError: return
				        if not chunk: return
				        out += chunk
				read(b"Code: ")
				os.write(fd, b"481516\\n")
				read(b"accounts")
				read(b"\\x00")
				os.waitpid(pid, 0)
				sys.stdout.buffer.write(out)
				"""
			let run = try launch(URL(filePath: "/usr/bin/python3"), ["-c", typing, extBinary.path], environment: ["EXT_USERNAME": "erika", "EXT_PASSWORD": "secret"],
				folder: folder)
			#expect(run.output.contains("Code: "))
			#expect(run.output.contains("accounts"))
			#expect(!run.output.contains("481516"))
		}
	}
}
