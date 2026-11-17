import CryptoKit
import Foundation
import Testing
@testable import FinTS

/// The signature check and the update of the bank data files (add-software-update, group 6). Every key
/// here is a throwaway key of the test, or the public test key of Fixtures/update.
@Suite("Bank data files")
struct BankDataTests {
	static let list = Data("""
		12030000=Musterbank|Berlin|BYLADEM1001|00||https://fints.example.com/fints|300|300|\r
		76030080=Beispielbank|Nürnberg|CSDBDE71XXX|00||https://fints.example.org/fints|300|300|\r

		""".utf8)

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
		changed[changed.startIndex + 20] ^= 0x01
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

	/// The files of Fixtures/bank-data come from `scripts/bank-data.py sign` with the test key of
	/// Fixtures/update, so the script of the workflow and the check of the app agree on the format.
	@Test("The check accepts a file that scripts/bank-data.py signed, and refuses it after one changed byte")
	func signedByScript() throws {
		let folder = URL(filePath: #filePath).deletingLastPathComponent().appending(path: "../../Fixtures/bank-data")
		let file = try Data(contentsOf: folder.appending(path: "blz.properties"))
		let signature = try #require(BankData.signature(fromFile: try Data(contentsOf: folder.appending(path: "blz.properties.sig"))))
		let testKey = try #require(Data(base64Encoded: "KCVfr5htNQFhNzFn1PReJQq2egc+Ny8yWsVLI1FEs/g="))
		#expect(BankData.verify(file: file, signature: signature, publicKey: testKey))
		#expect(BankData.isReadableBankList(file))
		var changed = file
		changed[changed.startIndex + 30] ^= 0x01
		#expect(!BankData.verify(file: changed, signature: signature, publicKey: testKey))
	}

	@Test("A bank list reads when every entry is a Bankleitzahl with the eight fields of hbci4java")
	func readable() {
		#expect(BankData.isReadableBankList(Self.list))
		#expect(BankData.isReadableBankList(Data("# comment\n12030000=Musterbank|Berlin|BYLADEM1001|00||https://fints.example.com/fints|300|300|\n".utf8)))
		#expect(!BankData.isReadableBankList(Data()))
		#expect(!BankData.isReadableBankList(Data("# only a comment\n".utf8)))
		#expect(!BankData.isReadableBankList(Data("1203000=Musterbank|Berlin|BYLADEM1001|00||https://fints.example.com/fints|300|300|\n".utf8)))
		#expect(!BankData.isReadableBankList(Data("12030000=Musterbank|Berlin|BYLADEM1001\n".utf8)))
		#expect(!BankData.isReadableBankList(Data("12030000=Muster\\u0062ank|Berlin|BYLADEM1001|00||https://fints.example.com/fints|300|300|\n".utf8)))
		#expect(!BankData.isReadableBankList(Data([0x31, 0x32, 0xff, 0xfe])))
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

		func updater(_ publicKey: Data, build: String = "120") -> BankDataUpdater {
			BankDataUpdater(folder: folder, source: server, publicKey: publicKey, build: build)
		}
	}

	@Test("A good file is installed, and the connector gets it as the bank list")
	func installsGoodFile() async throws {
		let setup = try Setup()
		try setup.serve(Self.list, signature: try signed(Self.list))
		let updater = setup.updater(publicKey)
		#expect(updater.bankList() == nil)
		#expect(await updater.updateIfDue(now: Date(timeIntervalSince1970: 1_800_000_000)) == .installed)
		#expect(updater.bankList() == Self.list)
	}

	@Test("A file with a wrong signature is rejected, and the current file stays")
	func keepsCurrentFile() async throws {
		let setup = try Setup()
		let start = Date(timeIntervalSince1970: 1_800_000_000)
		try setup.serve(Self.list, signature: try signed(Self.list))
		let updater = setup.updater(publicKey)
		#expect(await updater.updateIfDue(now: start) == .installed)

		var moved = Self.list
		moved.append(contentsOf: Data("10010010=Postbank|Berlin|PBNKDEFFXXX|00||https://fints.example.net/fints|300|300|\r\n".utf8))
		try setup.serve(moved, signature: try signed(Self.list))
		#expect(await updater.updateIfDue(now: start.addingTimeInterval(86_400)) == .rejected(.signature))
		#expect(updater.bankList() == Self.list)

		try setup.serve(moved, signature: try signed(moved, with: Curve25519.Signing.PrivateKey()))
		#expect(await updater.updateIfDue(now: start.addingTimeInterval(2 * 86_400)) == .rejected(.signature))
		#expect(updater.bankList() == Self.list)

		try setup.serve(moved, signature: try signed(moved))
		#expect(await updater.updateIfDue(now: start.addingTimeInterval(3 * 86_400)) == .installed)
		#expect(updater.bankList() == moved)
	}

	@Test("A signed file that is no bank list is rejected")
	func rejectsUnreadableList() async throws {
		let setup = try Setup()
		let other = Data("{\"not\": \"a bank list\"}".utf8)
		try setup.serve(other, signature: try signed(other))
		let updater = setup.updater(publicKey)
		#expect(await updater.updateIfDue(now: Date(timeIntervalSince1970: 1_800_000_000)) == .rejected(.unreadable))
		#expect(updater.bankList() == nil)
	}

	@Test("A file larger than the limit is rejected without being read to its end")
	func rejectsLargeFile() async throws {
		let setup = try Setup()
		let large = Data(count: BankDataUpdater.listLimit + 1)
		try setup.serve(large, signature: try signed(large))
		#expect(await setup.updater(publicKey).updateIfDue(now: Date(timeIntervalSince1970: 1_800_000_000)) == .rejected(.tooLarge))
	}

	@Test("The app looks at most once in 24 hours, also after a failed look")
	func onceADay() async throws {
		let setup = try Setup()
		let start = Date(timeIntervalSince1970: 1_800_000_000)
		let updater = setup.updater(publicKey)
		#expect(await updater.updateIfDue(now: start) == .unreachable)
		try setup.serve(Self.list, signature: try signed(Self.list))
		#expect(await updater.updateIfDue(now: start.addingTimeInterval(3_600)) == .notDue)
		#expect(await updater.updateIfDue(now: start.addingTimeInterval(86_399)) == .notDue)
		#expect(await updater.updateIfDue(now: start.addingTimeInterval(86_400)) == .installed)
		#expect(await updater.updateIfDue(now: start.addingTimeInterval(2 * 86_400)) == .unchanged)
		#expect(updater.bankList() == Self.list)
	}

	@Test("A clock that went back makes the app look again")
	func clockBack() async throws {
		let setup = try Setup()
		let start = Date(timeIntervalSince1970: 1_800_000_000)
		try setup.serve(Self.list, signature: try signed(Self.list))
		let updater = setup.updater(publicKey)
		#expect(await updater.updateIfDue(now: start) == .installed)
		#expect(await updater.updateIfDue(now: start.addingTimeInterval(-3_600)) == .unchanged)
	}

	@Test("Another build of the app ignores the installed files and looks at once")
	func otherBuild() async throws {
		let setup = try Setup()
		let start = Date(timeIntervalSince1970: 1_800_000_000)
		try setup.serve(Self.list, signature: try signed(Self.list))
		#expect(await setup.updater(publicKey, build: "120").updateIfDue(now: start) == .installed)

		let newer = setup.updater(publicKey, build: "121")
		#expect(newer.bankList() == nil)
		#expect(await newer.updateIfDue(now: start.addingTimeInterval(60)) == .installed)
		#expect(newer.bankList() == Self.list)
	}

	@Test("An installed file that was changed on disk is not used")
	func changedOnDisk() async throws {
		let setup = try Setup()
		try setup.serve(Self.list, signature: try signed(Self.list))
		let updater = setup.updater(publicKey)
		#expect(await updater.updateIfDue(now: Date(timeIntervalSince1970: 1_800_000_000)) == .installed)
		let installed = try #require(try FileManager.default.contentsOfDirectory(at: setup.folder, includingPropertiesForKeys: nil)
			.first { $0.lastPathComponent == "Current" })
		var changed = Self.list
		changed[changed.startIndex + 20] ^= 0x01
		try changed.write(to: installed.appending(path: "blz.properties"))
		#expect(updater.bankList() == nil)
	}

	@Test("An update key of another build refuses the installed files")
	func otherKeyRefusesInstalled() async throws {
		let setup = try Setup()
		try setup.serve(Self.list, signature: try signed(Self.list))
		#expect(await setup.updater(publicKey).updateIfDue(now: Date(timeIntervalSince1970: 1_800_000_000)) == .installed)
		#expect(setup.updater(Curve25519.Signing.PrivateKey().publicKey.rawRepresentation).bankList() == nil)
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
