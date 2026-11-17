import CryptoKit
import Foundation
import Testing
@testable import FinTS

/// The signature check and the update of the bank data files (add-software-update, group 6). Every key
/// here is a throwaway key of the test, or the public test key of Fixtures/update.
@Suite("Bank data files")
struct BankDataTests {
	/// A bank list as `scripts/bank-data.py build` writes it, with its header.
	static func list(serial: Int = 20261117084700, hbci4java: String = "4.1.17", address: String = "https://fints.example.com/fints") -> Data {
		Data("""
			# Bank list of Moneten, signed with the update key.\r
			# serial=\(serial)\r
			# hbci4java=\(hbci4java)\r
			12030000=Musterbank|Berlin|BYLADEM1001|00||\(address)|300|300|\r
			76030080=Beispielbank|Nürnberg|CSDBDE71XXX|00||https://fints.example.org/fints|300|300|\r

			""".utf8)
	}

	static let list = list()

	let key = Curve25519.Signing.PrivateKey()
	var publicKey: Data { key.publicKey.rawRepresentation }

	func signed(_ data: Data, with key: Curve25519.Signing.PrivateKey? = nil) throws -> Data {
		try (key ?? self.key).signature(for: data)
	}

	// MARK: 6.1 The signature

	@Test("A bank list with a good signature of the update key passes the check")
	func goodSignature() throws {
		#expect(BankData.verify(file: Self.list, signature: try signed(Self.list), publicKey: publicKey))
	}

	@Test("A bank list signed with another key fails the check")
	func otherKey() throws {
		let other = Curve25519.Signing.PrivateKey()
		#expect(!BankData.verify(file: Self.list, signature: try signed(Self.list, with: other), publicKey: publicKey))
	}

	@Test("A bank list with one changed byte fails the check")
	func changedByte() throws {
		let signature = try signed(Self.list)
		var changed = Self.list
		changed[changed.startIndex + 80] ^= 0x01
		#expect(!BankData.verify(file: changed, signature: signature, publicKey: publicKey))
	}

	@Test("A signature with one changed byte, a short signature, and a key that is not 32 bytes fail the check")
	func brokenInputs() throws {
		var signature = try signed(Self.list)
		#expect(!BankData.verify(file: Self.list, signature: signature.prefix(63), publicKey: publicKey))
		#expect(!BankData.verify(file: Self.list, signature: signature, publicKey: publicKey.prefix(31)))
		signature[signature.startIndex] ^= 0x01
		#expect(!BankData.verify(file: Self.list, signature: signature, publicKey: publicKey))
	}

	static let fixtures = URL(filePath: #filePath).deletingLastPathComponent().appending(path: "../..")

	/// The files of Fixtures/bank-data come from `scripts/bank-data.py sign` with the test key of
	/// Fixtures/update, so the script of the workflow and the check of the app agree on the format.
	@Test("The check accepts a file that scripts/bank-data.py signed, and refuses it after one changed byte")
	func signedByScript() throws {
		let folder = Self.fixtures.appending(path: "Fixtures/bank-data")
		let file = try Data(contentsOf: folder.appending(path: "blz.properties"))
		let signature = try #require(BankData.signature(fromFile: try Data(contentsOf: folder.appending(path: "blz.properties.sig"))))
		let testKey = try #require(Data(base64Encoded: "KCVfr5htNQFhNzFn1PReJQq2egc+Ny8yWsVLI1FEs/g="))
		#expect(BankData.verify(file: file, signature: signature, publicKey: testKey))
		#expect(BankData.isReadableBankList(file))
		#expect(BankData.Header(file) == BankData.Header(Self.list))
		var changed = file
		changed[changed.startIndex + 30] ^= 0x01
		#expect(!BankData.verify(file: changed, signature: signature, publicKey: testKey))
	}

	@Test("The version of hbci4java that the app compares with is the one that dependencies.lock pins")
	func bundledVersion() throws {
		let lock = try String(contentsOf: Self.fixtures.appending(path: "Tools/FinTSProbeJava/dependencies.lock"), encoding: .utf8)
		let line = try #require(lock.split(separator: "\n").first { $0.hasPrefix("com.github.hbci4j:hbci4j-core:") })
		#expect(line.split(separator: " ")[0].split(separator: ":")[2] == BankData.bundledHBCI4Java)
	}

	@Test("A bank list reads when every entry is a Bankleitzahl with the eight fields of hbci4java")
	func readable() {
		#expect(BankData.isReadableBankList(Self.list))
		#expect(BankData.isReadableBankList(Data("# comment\n12030000=Musterbank|Berlin|BYLADEM1001|00||https://fints.example.com/fints|300|300|\n".utf8)))
		#expect(!BankData.isReadableBankList(Data()))
		#expect(!BankData.isReadableBankList(Data("# only a comment\n".utf8)))
		#expect(!BankData.isReadableBankList(Data("1203000=Musterbank|Berlin|BYLADEM1001|00||https://fints.example.com/fints|300|300|\n".utf8)))
		#expect(!BankData.isReadableBankList(Data("1203000a=Musterbank|Berlin|BYLADEM1001|00||https://fints.example.com/fints|300|300|\n".utf8)))
		#expect(!BankData.isReadableBankList(Data("12030000=Musterbank|Berlin|BYLADEM1001\n".utf8)))
		#expect(!BankData.isReadableBankList(Data("12030000=Muster\\u0062ank|Berlin|BYLADEM1001|00||https://fints.example.com/fints|300|300|\n".utf8)))
		#expect(!BankData.isReadableBankList(Data([0x31, 0x32, 0xff, 0xfe])))
	}

	@Test("The header holds the serial and the version of hbci4java, and only before the first entry")
	func header() throws {
		let header = try #require(BankData.Header(Self.list))
		#expect(header.serial == 20261117084700)
		#expect(header.hbci4java == [4, 1, 17])
		#expect(header.isAtLeast([4, 1, 17]) && header.isAtLeast([4, 1, 9]) && !header.isAtLeast([4, 1, 18]) && !header.isAtLeast([4, 2]))
		#expect(BankData.Header(Data("# serial=20261117084700\n12030000=x|||||||\n".utf8)) == nil)
		#expect(BankData.Header(Data("12030000=x|||||||\n# serial=20261117084700\n# hbci4java=4.1.17\n".utf8)) == nil)
		#expect(BankData.Header(Data("# serial=2026\n# hbci4java=4.1.17\n".utf8)) == nil)
		#expect(BankData.Header(Data("# serial=20261117084700\n# hbci4java=4..17\n".utf8)) == nil)
	}

	// MARK: 6.2 The update

	/// A folder of the test with a server folder that a file URL serves, as the release `bank-data` would.
	struct Setup {
		let root = FileManager.default.temporaryDirectory.appending(path: "bank-data-\(UUID().uuidString)")
		var server: URL { root.appending(path: "server", directoryHint: .isDirectory) }
		var folder: URL { root.appending(path: "Bank Data", directoryHint: .isDirectory) }

		init() throws {
			try FileManager.default.createDirectory(at: server, withIntermediateDirectories: true)
		}

		func serve(_ list: Data, signature: Data) throws {
			try list.write(to: server.appending(path: "blz.properties"))
			try Data((signature.base64EncodedString() + "\n").utf8).write(to: server.appending(path: "blz.properties.sig"))
		}

		func updater(_ publicKey: Data, build: String = "120", bundled: String = "4.1.17") -> BankDataUpdater {
			BankDataUpdater(folder: folder, source: server, publicKey: publicKey, build: build, bundled: bundled)
		}
	}

	static let start = Date(timeIntervalSince1970: 1_800_000_000)
	static func day(_ n: Double) -> Date { start.addingTimeInterval(n * 86_400) }

	@Test("A good file is installed, and the connector gets it as the bank list")
	func installsGoodFile() async throws {
		let setup = try Setup()
		try setup.serve(Self.list, signature: try signed(Self.list))
		let updater = setup.updater(publicKey)
		#expect(updater.bankList() == nil)
		#expect(await updater.updateIfDue(now: Self.start) == .installed)
		#expect(updater.bankList() == Self.list)
	}

	@Test("A file with a wrong signature is rejected, and the current file stays")
	func keepsCurrentFile() async throws {
		let setup = try Setup()
		try setup.serve(Self.list, signature: try signed(Self.list))
		let updater = setup.updater(publicKey)
		#expect(await updater.updateIfDue(now: Self.start) == .installed)

		let moved = Self.list(serial: 20261118084700, address: "https://fints.moved.example/fints")
		try setup.serve(moved, signature: try signed(Self.list))
		#expect(await updater.updateIfDue(now: Self.day(1)) == .rejected(.signature))
		#expect(updater.bankList() == Self.list)

		try setup.serve(moved, signature: try signed(moved, with: Curve25519.Signing.PrivateKey()))
		#expect(await updater.updateIfDue(now: Self.day(2)) == .rejected(.signature))
		#expect(updater.bankList() == Self.list)

		try setup.serve(moved, signature: try signed(moved))
		#expect(await updater.updateIfDue(now: Self.day(3)) == .installed)
		#expect(updater.bankList() == moved)
	}

	@Test("A signed list with an older serial, or the same serial with other bytes, is refused")
	func replay() async throws {
		let setup = try Setup()
		let newer = Self.list(serial: 20261120000000, address: "https://fints.moved.example/fints")
		try setup.serve(newer, signature: try signed(newer))
		let updater = setup.updater(publicKey)
		#expect(await updater.updateIfDue(now: Self.start) == .installed)

		let older = Self.list(serial: 20261110000000)
		try setup.serve(older, signature: try signed(older))
		#expect(await updater.updateIfDue(now: Self.day(1)) == .rejected(.older))
		#expect(updater.bankList() == newer)

		let sameSerial = Self.list(serial: 20261120000000, address: "https://fints.other.example/fints")
		try setup.serve(sameSerial, signature: try signed(sameSerial))
		#expect(await updater.updateIfDue(now: Self.day(2)) == .rejected(.older))
		#expect(updater.bankList() == newer)

		try setup.serve(newer, signature: try signed(newer))
		#expect(await updater.updateIfDue(now: Self.day(3)) == .unchanged)
	}

	@Test("A signed list from an older jar of hbci4java than the one of the build is refused")
	func olderThanJar() async throws {
		let setup = try Setup()
		let old = Self.list(serial: 20261120000000, hbci4java: "4.1.16")
		try setup.serve(old, signature: try signed(old))
		#expect(await setup.updater(publicKey).updateIfDue(now: Self.start) == .rejected(.older))
		#expect(setup.updater(publicKey).bankList() == nil)
	}

	@Test("After a build change the app looks at once, keeps the floor of the serial, and refuses a list older than its new jar")
	func buildChange() async throws {
		let setup = try Setup()
		try setup.serve(Self.list, signature: try signed(Self.list))
		#expect(await setup.updater(publicKey, build: "120").updateIfDue(now: Self.start) == .installed)

		// The same jar: the installed list stays in use, and the look at once finds the same file.
		let same = setup.updater(publicKey, build: "121")
		#expect(same.bankList() == Self.list)
		#expect(await same.updateIfDue(now: Self.start.addingTimeInterval(60)) == .unchanged)

		// A replay of an older list stays refused after the build change.
		let older = Self.list(serial: 20261101000000)
		try setup.serve(older, signature: try signed(older))
		let next = setup.updater(publicKey, build: "122")
		#expect(await next.updateIfDue(now: Self.start.addingTimeInterval(120)) == .rejected(.older))
		#expect(next.bankList() == Self.list)

		// A newer jar: the installed list from 4.1.17 is no longer used, and a download from it is refused.
		let newerJar = setup.updater(publicKey, build: "123", bundled: "4.1.18")
		#expect(newerJar.bankList() == nil)
		let republished = Self.list(serial: 20261201000000)
		try setup.serve(republished, signature: try signed(republished))
		#expect(await newerJar.updateIfDue(now: Self.start.addingTimeInterval(180)) == .rejected(.older))
		#expect(newerJar.bankList() == nil)

		let fromNewJar = Self.list(serial: 20261202000000, hbci4java: "4.1.18")
		try setup.serve(fromNewJar, signature: try signed(fromNewJar))
		#expect(await newerJar.updateIfDue(now: Self.day(2)) == .installed)
		#expect(newerJar.bankList() == fromNewJar)
	}

	@Test("A signed file that is no bank list, or a list without its header, is rejected")
	func rejectsUnreadableList() async throws {
		let setup = try Setup()
		let other = Data("{\"not\": \"a bank list\"}".utf8)
		try setup.serve(other, signature: try signed(other))
		let updater = setup.updater(publicKey)
		#expect(await updater.updateIfDue(now: Self.start) == .rejected(.unreadable))
		let headless = Data("12030000=Musterbank|Berlin|BYLADEM1001|00||https://fints.example.com/fints|300|300|\r\n".utf8)
		try setup.serve(headless, signature: try signed(headless))
		#expect(await updater.updateIfDue(now: Self.day(1)) == .rejected(.unreadable))
		#expect(updater.bankList() == nil)
	}

	@Test("A file larger than the limit is rejected without being read to its end")
	func rejectsLargeFile() async throws {
		let setup = try Setup()
		let large = Data(count: BankDataUpdater.listLimit + 1)
		try setup.serve(large, signature: try signed(large))
		#expect(await setup.updater(publicKey).updateIfDue(now: Self.start) == .rejected(.tooLarge))
	}

	@Test("The app looks at most once in 24 hours, also after a failed look")
	func onceADay() async throws {
		let setup = try Setup()
		let updater = setup.updater(publicKey)
		#expect(await updater.updateIfDue(now: Self.start) == .unreachable)
		try setup.serve(Self.list, signature: try signed(Self.list))
		#expect(await updater.updateIfDue(now: Self.start.addingTimeInterval(3_600)) == .notDue)
		#expect(await updater.updateIfDue(now: Self.start.addingTimeInterval(86_399)) == .notDue)
		#expect(await updater.updateIfDue(now: Self.day(1)) == .installed)
		#expect(await updater.updateIfDue(now: Self.day(2)) == .unchanged)
		#expect(updater.bankList() == Self.list)
	}

	@Test("A clock that went back makes the app look again")
	func clockBack() async throws {
		let setup = try Setup()
		try setup.serve(Self.list, signature: try signed(Self.list))
		let updater = setup.updater(publicKey)
		#expect(await updater.updateIfDue(now: Self.start) == .installed)
		#expect(await updater.updateIfDue(now: Self.start.addingTimeInterval(-3_600)) == .unchanged)
	}

	@Test("An installed file that was changed on disk is not used")
	func changedOnDisk() async throws {
		let setup = try Setup()
		try setup.serve(Self.list, signature: try signed(Self.list))
		let updater = setup.updater(publicKey)
		#expect(await updater.updateIfDue(now: Self.start) == .installed)
		var changed = Self.list
		changed[changed.startIndex + 120] ^= 0x01
		try changed.write(to: setup.folder.appending(path: "Current/blz.properties"))
		#expect(updater.bankList() == nil)
	}

	@Test("An update key of another build refuses the installed files")
	func otherKeyRefusesInstalled() async throws {
		let setup = try Setup()
		try setup.serve(Self.list, signature: try signed(Self.list))
		#expect(await setup.updater(publicKey).updateIfDue(now: Self.start) == .installed)
		#expect(setup.updater(Curve25519.Signing.PrivateKey().publicKey.rawRepresentation).bankList() == nil)
	}

	@Test("An install removes the staging folders that an earlier install left behind")
	func leftoverStaging() async throws {
		let setup = try Setup()
		let leftover = setup.folder.appending(path: "New-\(UUID().uuidString)")
		try FileManager.default.createDirectory(at: leftover, withIntermediateDirectories: true)
		try setup.serve(Self.list, signature: try signed(Self.list))
		#expect(await setup.updater(publicKey).updateIfDue(now: Self.start) == .installed)
		#expect(try FileManager.default.contentsOfDirectory(atPath: setup.folder.path).sorted() == ["Current", "check.json"])
	}

	@Test("The signature file holds the 64 bytes in Base64, with or without a line break")
	func signatureFile() {
		let raw = Data(repeating: 7, count: 64)
		#expect(BankData.signature(fromFile: Data(raw.base64EncodedString().utf8)) == raw)
		#expect(BankData.signature(fromFile: Data((raw.base64EncodedString() + "\n").utf8)) == raw)
		#expect(BankData.signature(fromFile: Data(Data(count: 63).base64EncodedString().utf8)) == nil)
		#expect(BankData.signature(fromFile: Data("not base64".utf8)) == nil)
	}
}

/// Answers the requests of a `BankDataUpdater` over https with made-up responses, by URL.
final class BankDataStub: URLProtocol, @unchecked Sendable {
	struct Response { var status = 200; var headers: [String: String] = [:]; var body = Data() }
	nonisolated(unsafe) static var responses: [URL: Response] = [:]
	nonisolated(unsafe) static var requests: [URLRequest] = []
	static let lock = NSLock()

	override class func canInit(with request: URLRequest) -> Bool { true }
	override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
	override func stopLoading() {}
	override func startLoading() {
		let response = Self.lock.withLock {
			Self.requests.append(request)
			return Self.responses[request.url!]
		}
		guard let response else { return client!.urlProtocol(self, didFailWithError: URLError(.cannotFindHost)) }
		let http = HTTPURLResponse(url: request.url!, statusCode: response.status, httpVersion: "HTTP/1.1", headerFields: response.headers)!
		if (300..<400).contains(response.status), let location = response.headers["Location"].flatMap(URL.init(string:)) {
			client!.urlProtocol(self, wasRedirectedTo: URLRequest(url: location), redirectResponse: http)
		}
		client!.urlProtocol(self, didReceive: http, cacheStoragePolicy: .notAllowed)
		client!.urlProtocol(self, didLoad: response.body)
		client!.urlProtocolDidFinishLoading(self)
	}
}

/// The download over https: the status, the announced length, the redirects, and the headers.
@Suite("Bank data over https", .serialized)
struct BankDataHTTPTests {
	let base = URL(string: "https://bank-data-\(UUID().uuidString.lowercased()).example/download/")!
	let folder = FileManager.default.temporaryDirectory.appending(path: "bank-data-\(UUID().uuidString)")
	let key = Curve25519.Signing.PrivateKey()

	var updater: BankDataUpdater {
		BankDataUpdater(folder: folder, source: base, publicKey: key.publicKey.rawRepresentation, build: "120", bundled: "4.1.17",
			protocolClasses: [BankDataStub.self])
	}

	func serve(_ url: URL, _ response: BankDataStub.Response) {
		BankDataStub.lock.withLock { BankDataStub.responses[url] = response }
	}

	func serveSigned(at folder: URL) throws {
		let list = BankDataTests.list
		serve(folder.appending(path: "blz.properties"), .init(body: list))
		serve(folder.appending(path: "blz.properties.sig"), .init(body: Data(try key.signature(for: list).base64EncodedString().utf8)))
	}

	@Test("A good file over https is installed, and the request carries only the user agent Moneten")
	func installs() async throws {
		try serveSigned(at: base)
		#expect(await updater.updateIfDue(now: BankDataTests.start) == .installed)
		let request = try #require(BankDataStub.lock.withLock { BankDataStub.requests.last { $0.url?.host() == base.host() } })
		#expect(request.url?.query == nil)
		#expect(request.value(forHTTPHeaderField: "Cookie") == nil)
		#expect(request.value(forHTTPHeaderField: "User-Agent") == "Moneten")
	}

	@Test("A status other than 200 keeps the installed files")
	func status() async throws {
		serve(base.appending(path: "blz.properties"), .init(status: 404))
		#expect(await updater.updateIfDue(now: BankDataTests.start) == .unreachable)
		#expect(updater.bankList() == nil)
	}

	@Test("An announced length above the limit is refused before the body")
	func announcedLength() async throws {
		serve(base.appending(path: "blz.properties"), .init(headers: ["Content-Length": "100000000"], body: BankDataTests.list))
		#expect(await updater.updateIfDue(now: BankDataTests.start) == .rejected(.tooLarge))
	}

	@Test("A redirect to another https host is followed, as GitHub sends the assets of a release")
	func redirectToHTTPS() async throws {
		let assets = URL(string: "https://assets-\(UUID().uuidString.lowercased()).example/")!
		for name in ["blz.properties", "blz.properties.sig"] {
			serve(base.appending(path: name), .init(status: 302, headers: ["Location": assets.appending(path: name).absoluteString]))
		}
		try serveSigned(at: assets)
		#expect(await updater.updateIfDue(now: BankDataTests.start) == .installed)
	}

	@Test("A redirect to http is not followed")
	func redirectToHTTP() async throws {
		let plain = URL(string: "http://assets-\(UUID().uuidString.lowercased()).example/")!
		for name in ["blz.properties", "blz.properties.sig"] {
			serve(base.appending(path: name), .init(status: 302, headers: ["Location": plain.appending(path: name).absoluteString]))
		}
		try serveSigned(at: plain)
		#expect(await updater.updateIfDue(now: BankDataTests.start) == .unreachable)
		#expect(BankDataStub.lock.withLock { BankDataStub.requests.contains { $0.url?.host() == plain.host() } } == false)
	}

	@Test("A source over http that is not this Mac is never asked")
	func plainSource() async throws {
		let source = URL(string: "http://bank-data-\(UUID().uuidString.lowercased()).example/")!
		let updater = BankDataUpdater(folder: folder, source: source, publicKey: key.publicKey.rawRepresentation, build: "120", bundled: "4.1.17",
			protocolClasses: [BankDataStub.self])
		#expect(await updater.updateIfDue(now: BankDataTests.start) == .unreachable)
		#expect(BankDataStub.lock.withLock { BankDataStub.requests.contains { $0.url?.host() == source.host() } } == false)
	}
}
