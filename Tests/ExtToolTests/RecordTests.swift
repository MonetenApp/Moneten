import ExtensionHost
import Foundation
import Testing

/// The made-up bank of `LocalBank/server.py` on https://bank.localhost, with a certificate of its own.
/// It listens on port 443 of every interface, because the host only sends to the HTTPS port, and
/// it answers only the loopback address.
final class LocalBank {
	let folder: URL
	let certificate: URL
	private let process = Process()

	/// macOS lets a user open port 443 on every interface, but not on the loopback address alone.
	/// The host refuses `localhost`, so the bank has a name with a dot. macOS 26 resolves each name
	/// under `localhost` to the loopback address; on macOS 15, CI adds `bank.localhost` to /etc/hosts.
	static var canStart: Bool {
		(try? launch(URL(filePath: "/usr/bin/python3"), ["-c", "import socket; socket.getaddrinfo('bank.localhost', 443, socket.AF_INET); s = socket.socket(); s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1); s.bind(('0.0.0.0', 443))"]).status) == 0
	}

	init() throws {
		folder = try temporaryFolder()
		certificate = folder.appending(path: "cert.pem")
		let key = folder.appending(path: "key.pem")
		let made = try launch(URL(filePath: "/usr/bin/openssl"), ["req", "-x509", "-newkey", "rsa:2048", "-nodes", "-days", "2", "-subj", "/CN=bank.localhost",
			"-addext", "subjectAltName=DNS:bank.localhost", "-addext", "extendedKeyUsage=serverAuth", "-keyout", key.path, "-out", certificate.path])
		guard made.status == 0 else { throw CocoaError(.fileWriteUnknown, userInfo: [NSLocalizedDescriptionKey: made.errors]) }
		let output = Pipe()
		process.executableURL = URL(filePath: "/usr/bin/python3")
		process.arguments = [repository.appending(path: "Tests/ExtToolTests/LocalBank/server.py").path, certificate.path, key.path]
		process.standardOutput = output
		try process.run()
		_ = output.fileHandleForReading.availableData
	}

	deinit {
		process.terminate()
		process.waitUntilExit()
	}
}

extension ExtTool {
	/// On CI the suite always runs, so that the only test of a whole recording cannot skip unseen.
	@Suite(.enabled(if: LocalBank.canStart || ProcessInfo.processInfo.environment["CI"] != nil)) struct RecordTests {
		let login = ["EXT_USERNAME": "erika", "EXT_PASSWORD": "geheim123"]

		func script(_ name: String = "Local.lua") throws -> URL {
			let folder = try temporaryFolder()
			let script = folder.appending(path: name)
			try FileManager.default.copyItem(at: repository.appending(path: "Tests/ExtToolTests/LocalBank/\(name)"), to: script)
			return script
		}

		/// The verifier of PKCE stands in no address, only its hash does, and the nonce of `MM.uuid()` stands
		/// in one. The replay needs both, so the fixture keeps both, and `ext test` replays the login offline.
		@Test func oauthLoginWithPKCEAndANonceReplays() throws {
			let bank = try LocalBank()
			let script = try script("OAuth.lua")
			let fixture = script.deletingLastPathComponent().appending(path: "fixture.json")
			let expected = script.deletingLastPathComponent().appending(path: "expected.json")
			let record = try ext(["record", script.path, fixture.path, "--trust", bank.certificate.path], input: "y\n", environment: login)
			#expect(record.status == 0, "\(record.errors)")
			#expect(record.errors.contains("ext keeps 1 more random value, such as a PKCE verifier, because the replay needs it.\n"))
			let recording = try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: fixture))
			let kept = recording.random?.filter { if case .bytes = $0 { true } else if case .uuid = $0 { true } else { false } }
			#expect(kept?.count == 2)
			let text = try String(contentsOf: fixture, encoding: .utf8)
			for secret in ["geheim123", "auth-7f3a9c21e5", "oauth-5d4c3b2a1908"] { #expect(!text.contains(secret), "\(secret) is in the fixture") }
			#expect(try extOffline(["test", script.path, fixture.path, expected.path, "--update"]).status == 0)
			#expect(try extOffline(["test", script.path, fixture.path, expected.path]).output == "PASS 1 account, 0 transactions\n")
		}

		@Test func refusedRecordingKeepsTheFixture() throws {
			let bank = try LocalBank()
			let folder = try files(["Echo.lua": """
				WebBanking{version = 1, services = {"Echo"}}
				function SupportsBank() return true end
				function InitializeSession(protocol, bankCode, username, customer, password)
					Connection():get("https://bank.localhost/logout?from=" .. password .. "-10-10")
				end
				function ListAccounts() return {} end
				""", "good.json": "{\"exchanges\": []}"])
			let record = try ext(["record", "Echo.lua", "good.json", "--trust", bank.certificate.path], input: "y\n",
				environment: ["EXT_USERNAME": "erika", "EXT_PASSWORD": "2025"], folder: folder)
			#expect(record.status == 2)
			#expect(record.errors.contains("The password is short or only digits, and a request holds it inside a longer value"))
			#expect(try String(contentsOf: folder.appending(path: "good.json"), encoding: .utf8) == "{\"exchanges\": []}")
		}

		@Test func recordLeavesNoSecretAndReplaysOffline() throws {
			let bank = try LocalBank()
			let script = try script()
			let fixture = script.deletingLastPathComponent().appending(path: "fixture.json")
			let expected = script.deletingLastPathComponent().appending(path: "expected.json")
			let record = try ext(["record", script.path, fixture.path, "--trust", bank.certificate.path], input: "y\n", environment: login)
			#expect(record.status == 0, "\(record.errors)")
			#expect(record.errors.contains("Recorded 5 requests.\nReplaced 1 username, 1 password, 1 cookie, 1 token.\n"))
			#expect(record.errors.hasSuffix("Replace them with invented data before you share or commit \(fixture.path).\n"))
			let text = try String(contentsOf: fixture, encoding: .utf8)
			for secret in ["geheim123", "Z2VoZWltMTIz", "abc123def456", "tok-9f8e7d6c5b4a", "erika"] {
				#expect(!text.contains(secret), "\(secret) is in the fixture")
			}
			for placeholder in ["username={{username}}&password={{password}}", "SESSION={{cookie1}}", "Bearer {{token1}}", "sid=%7B%7Bcookie1%7D%7D", "\"host\" : \"allowed\""] {
				#expect(text.contains(placeholder), "\(placeholder) is missing")
			}

			let update = try extOffline(["test", script.path, fixture.path, expected.path, "--update"])
			#expect(update.status == 0, "\(update.errors)")
			#expect(update.output == "Wrote \(expected.path) with 1 account, 2 transactions.\n")
			#expect(try extOffline(["test", script.path, fixture.path, expected.path]).output == "PASS 1 account, 2 transactions\n")
		}

		@Test func runKeepsLocalStorageNextToTheScript() throws {
			let bank = try LocalBank()
			let script = try script()
			func name(_ arguments: [String]) throws -> String? {
				let run = try ext(["run", script.path, "--trust", bank.certificate.path] + arguments, input: "y\n", environment: login)
				let document = try JSONSerialization.jsonObject(with: Data(run.output.utf8)) as? [String: [[String: Any]]]
				return document?["accounts"]?.first?["name"] as? String
			}
			#expect(try name([]) == "Giro 1")
			#expect(try name([]) == "Giro 2")
			#expect(try name(["--fresh"]) == "Giro 1")
			#expect(FileManager.default.fileExists(atPath: script.deletingLastPathComponent().appending(path: "Local.storage.json").path))
		}

		@Test func withoutTheCertificateTheConnectionFails() throws {
			let bank = try LocalBank()
			let script = try script()
			let run = try ext(["run", script.path], input: "y\n", environment: login)
			#expect(run.status == 2)
			#expect(run.output.isEmpty)
			_ = bank
		}
	}
}
