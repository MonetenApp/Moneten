import Foundation
@testable import Storage
import StorageTestSupport
import Testing

/// Tests of `Keychain` against keychain files of `StorageTestSupport`, never the login Keychain.
@Suite("Keychain")
struct KeychainTests {
	static let service = "Moneten database password for Touch ID"
	static let account = "/Users/beispiel/Library/Application Support/Moneten/Database/Moneten.sqlite"

	@Test("A write never puts the value into an entry that another program created, so the access list of that entry is gone")
	func writeReplacesPlantedEntry() throws {
		let file = try KeychainFile()
		try file.plant(service: Self.service, account: Self.account, value: "gepflanzt")
		#expect(try file.readers(service: Self.service, account: Self.account) == nil)

		let keychain = Keychain(service: Self.service, path: file.path)
		try keychain.write("korrekt-pferd-batterie", account: Self.account)

		#expect(try keychain.read(account: Self.account) == "korrekt-pferd-batterie")
		#expect(try file.readers(service: Self.service, account: Self.account)?.count == 1)
	}

	@Test("A second write replaces the value of the entry that the first one created, and a delete removes it")
	func writeTwiceAndDelete() throws {
		let keychain = Keychain(service: Self.service, path: try KeychainFile().path)
		try keychain.write("alt-und-lang-genug", account: Self.account)
		try keychain.write("neu-und-noch-laenger", account: Self.account)
		#expect(try keychain.read(account: Self.account) == "neu-und-noch-laenger")
		#expect(try keychain.contains(account: Self.account))
		try keychain.delete(account: Self.account)
		#expect(try keychain.read(account: Self.account) == nil)
		#expect(try !keychain.contains(account: Self.account))
	}

	@Test("A keychain file that does not exist refuses every step, so nothing goes into another keychain")
	func missingFileFailsClosed() throws {
		try expectRefused(Keychain(service: "Moneten test without keychain file", path: KeychainFile.missingPath()))
	}

	@Test("Without a home folder in the user database every step refuses and names the login keychain")
	func unknownHomeFailsClosed() throws {
		let keychain = Keychain(service: "Moneten test without keychain file", path: nil)
		try expectRefused(keychain)
		let refusal = try #require(throws: Keychain.Failure.self) { try keychain.read(account: Self.account) }
		#expect(refusal.description.contains("~/Library/Keychains/login.keychain-db"))
	}

	@Test("A keychain file that was deleted after it was opened refuses every step")
	func removedFileFailsClosed() throws {
		let file = try KeychainFile()
		let keychain = Keychain(service: "Moneten test without keychain file", path: file.path)
		try keychain.write("korrekt-pferd-batterie", account: Self.account)
		try file.removeFile()
		try expectRefused(keychain)
	}

	private func expectRefused(_ keychain: Keychain) throws {
		#expect(throws: Keychain.Failure.self) { try keychain.read(account: Self.account) }
		#expect(throws: Keychain.Failure.self) { try keychain.contains(account: Self.account) }
		#expect(throws: Keychain.Failure.self) { try keychain.delete(account: Self.account) }
		#expect(throws: Keychain.Failure.self) { try keychain.write("korrekt-pferd-batterie", account: Self.account) }
	}
}
