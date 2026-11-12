import Domain
import Foundation
import Testing
@testable import Storage

/// login-credentials "Saved PINs live in the encrypted database": a saved PIN stays in the database
/// file, which SQLCipher encrypts with the database password, and nowhere else.
@Suite("Saved PINs in the database")
struct SavedPINTests {
	let root = FileManager.default.temporaryDirectory.appendingPathComponent("MonetenTests-\(UUID().uuidString)")
	var folder: DataFolder { DataFolder(root: root.appendingPathComponent("Mac A")) }
	static let password = "korrekt-pferd-batterie-heftklammer"
	static let access = Access(source: .fints(bankCode: "12030000", url: URL(string: "https://fints.musterbank.example/fints")!), bankName: "Musterbank",
		loginName: "erika77")
	static let giro = Account(position: 0, name: "Girokonto", kind: .giro, source: .bank, iban: "DE02120300000000202051", accessID: access.id,
		remoteID: "DE02120300000000202051")

	@Test("A saved PIN comes back after the database opens again, until it is removed")
	func roundTrip() throws {
		let vault = Vault(folder: folder)
		let store = try vault.create(password: Self.password, starterCategories: [])
		try store.add(Self.access, state: AccessState(Data([1])), accounts: [Self.giro])
		#expect(try store.savedPINs().isEmpty)
		try store.savePIN(Secret("48151"), for: Self.access.id)
		try store.close()

		let reopened = try vault.open(password: Self.password)
		#expect(try reopened.savedPINs() == [Self.access.id: Secret("48151")])
		#expect(try reopened.state(of: Self.access.id) == AccessState(Data([1])))
		try reopened.savePIN(Secret("16234"), for: Self.access.id)
		#expect(try reopened.savedPINs() == [Self.access.id: Secret("16234")])
		try reopened.removeSavedPIN(of: Self.access.id)
		try reopened.close()

		#expect(try vault.open(password: Self.password).savedPINs().isEmpty)
	}

	@Test("A saved PIN goes with its access and its last account")
	func goesWithAccess() throws {
		let store = try Vault(folder: folder).create(password: Self.password, starterCategories: [])
		try store.add(Self.access, state: nil, accounts: [Self.giro])
		try store.savePIN(Secret("48151"), for: Self.access.id)
		try store.deleteAccount(Self.giro.id)
		#expect(try store.savedPINs().isEmpty)
	}

	@Test("No byte of the database file or of its backup shows the PIN, and the backup opens on another Mac with the database password")
	func encrypted() throws {
		let store = try Vault(folder: folder).create(password: Self.password, starterCategories: [])
		try store.add(Self.access, state: nil, accounts: [Self.giro])
		try store.savePIN(Secret("48151"), for: Self.access.id)
		let other = DataFolder(root: root.appendingPathComponent("Mac B"))
		try other.createFolders()
		try store.backup(to: other.databaseFile)
		try store.close()

		let files = try FileManager.default.subpathsOfDirectory(atPath: root.path).map { root.appendingPathComponent($0) }
			.filter { !$0.hasDirectoryPath && (try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true }
		#expect(files.count >= 2)
		for file in files {
			let bytes = try Data(contentsOf: file)
			#expect(bytes.range(of: Data("48151".utf8)) == nil, "\(file.lastPathComponent) shows the PIN")
			#expect(bytes.range(of: Data("4\u{0}8\u{0}1\u{0}5\u{0}1".utf8)) == nil, "\(file.lastPathComponent) shows the PIN in UTF-16")
		}

		let restored = try Vault(folder: other).open(password: Self.password)
		#expect(try restored.savedPINs() == [Self.access.id: Secret("48151")])
	}
}
