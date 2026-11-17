import Foundation
@testable import Storage
import StorageTestSupport
import Testing

/// Tests of `Keychain` against a keychain file that each test creates and deletes, never the login Keychain.
@Suite("Keychain")
struct KeychainTests {
	static let service = "Moneten database password for Touch ID"
	static let account = "/Users/beispiel/Library/Application Support/Moneten/Database/Moneten.sqlite"

	@Test("A write never puts the value into an entry that another program created, so the access list of that entry is gone")
	func writeReplacesPlantedEntry() throws {
		let file = try KeychainFile()
		try file.plant(service: Self.service, account: Self.account, value: "gepflanzt")
		#expect(try file.readers(service: Self.service, account: Self.account) == nil)

		let keychain = Keychain(service: Self.service, file: file.keychain)
		try keychain.write("korrekt-pferd-batterie", account: Self.account)

		#expect(try keychain.read(account: Self.account) == "korrekt-pferd-batterie")
		#expect(try file.readers(service: Self.service, account: Self.account)?.count == 1)
	}

	@Test("A second write replaces the value of the entry that the first one created, and a delete removes it")
	func writeTwiceAndDelete() throws {
		let keychain = Keychain(service: Self.service, file: try KeychainFile().keychain)
		try keychain.write("alt-und-lang-genug", account: Self.account)
		try keychain.write("neu-und-noch-laenger", account: Self.account)
		#expect(try keychain.read(account: Self.account) == "neu-und-noch-laenger")
		#expect(try keychain.contains(account: Self.account))
		try keychain.delete(account: Self.account)
		#expect(try keychain.read(account: Self.account) == nil)
		#expect(try !keychain.contains(account: Self.account))
	}
}
