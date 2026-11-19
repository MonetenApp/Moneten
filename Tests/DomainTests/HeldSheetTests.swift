import Domain
import Foundation
import Testing

@Suite("The input of an open sheet across a lock")
struct HeldSheetTests {
	enum Sheet: Equatable {
		case accountSettings(UUID)
		case groupSettings(UUID)
	}

	/// The input of the account settings as the sheet holds it: the edited account and the chosen color.
	struct Settings: Equatable {
		var account: Account
		var color: String
	}

	/// The database that was open at the lock, and one that a backup put in its place.
	let database = 1
	let replacement = 2

	let girokonto = Account(position: 0, name: "Girokonto", kind: .giro, source: .offline)
	let haushalt = UUID()

	var changed: Settings {
		var a = girokonto
		a.name = "Haushaltskonto"
		return Settings(account: a, color: "#2E7D32")
	}

	@Test("The lock keeps the open account settings with a changed name and color, and the unlock gives them back until the settings close")
	func lockAndUnlock() {
		var held = HeldSheet<Sheet, Settings, Int>()
		let sheet = Sheet.accountSettings(girokonto.id)
		held.record(Settings(account: girokonto, color: "#1565C0"), of: sheet)
		held.record(changed, of: sheet)
		held.lock(closing: sheet, database: database)
		#expect(held.unlock(database: database) == sheet)
		#expect(held.input(for: sheet) == changed)
		// The input goes back until the settings close. A later opening of the same settings starts from the account.
		held.close(sheet)
		#expect(held.input(for: sheet) == nil)
		#expect(held.unlock(database: database) == nil)
	}

	@Test("A sheet that SwiftUI shows twice after the unlock, the second time with new state, gets the input both times")
	func appearsTwice() {
		var held = HeldSheet<Sheet, Settings, Int>()
		let sheet = Sheet.accountSettings(girokonto.id)
		held.record(changed, of: sheet)
		held.lock(closing: sheet, database: database)
		_ = held.unlock(database: database)
		#expect(held.input(for: sheet) == changed)
		#expect(held.input(for: sheet) == changed)
	}

	@Test("Closing another sheet keeps the returning input, and closing its own sheet ends it")
	func closeOther() {
		var held = HeldSheet<Sheet, Settings, Int>()
		let sheet = Sheet.accountSettings(girokonto.id)
		held.record(changed, of: sheet)
		held.lock(closing: sheet, database: database)
		_ = held.unlock(database: database)
		held.close(.groupSettings(haushalt))
		#expect(held.returningInput == changed)
		held.close(sheet)
		#expect(held.returningInput == nil)
	}

	@Test("A sheet that opens without a lock before it starts from the stored values")
	func noLock() {
		var held = HeldSheet<Sheet, Settings, Int>()
		let sheet = Sheet.accountSettings(girokonto.id)
		held.record(changed, of: sheet)
		#expect(held.input(for: sheet) == nil)
		#expect(held.unlock(database: database) == nil)
	}

	@Test("The lock keeps nothing when no sheet is open, also when a closed sheet left its input")
	func noSheetOpen() {
		var held = HeldSheet<Sheet, Settings, Int>()
		held.record(changed, of: .accountSettings(girokonto.id))
		held.lock(closing: nil, database: database)
		#expect(held.unlock(database: database) == nil)
		#expect(held.input(for: .accountSettings(girokonto.id)) == nil)
	}

	@Test("The lock keeps nothing for an open sheet whose input it does not know")
	func otherSheetOpen() {
		var held = HeldSheet<Sheet, Settings, Int>()
		held.record(changed, of: .accountSettings(girokonto.id))
		held.lock(closing: .groupSettings(haushalt), database: database)
		#expect(held.unlock(database: database) == nil)
	}

	@Test("Closing the database for good, as after a change on disk, drops the held input")
	func drop() {
		var held = HeldSheet<Sheet, Settings, Int>()
		let sheet = Sheet.accountSettings(girokonto.id)
		held.record(changed, of: sheet)
		held.lock(closing: sheet, database: database)
		held.drop()
		#expect(held.unlock(database: database) == nil)
		#expect(held.input(for: sheet) == nil)
	}

	@Test("A sheet that the unlock gave back but that never showed drops its input at the next drop")
	func dropAfterUnlock() {
		var held = HeldSheet<Sheet, Settings, Int>()
		let sheet = Sheet.accountSettings(girokonto.id)
		held.record(changed, of: sheet)
		held.lock(closing: sheet, database: database)
		#expect(held.unlock(database: database) == sheet)
		held.drop()
		#expect(held.returningInput == nil)
		#expect(held.input(for: sheet) == nil)
	}

	@Test("The input of the first lock is not given to a second sheet, and the second lock keeps only its own sheet")
	func secondLock() {
		var held = HeldSheet<Sheet, Settings, Int>()
		let account = Sheet.accountSettings(girokonto.id)
		let group = Sheet.groupSettings(haushalt)
		held.record(changed, of: account)
		held.lock(closing: account, database: database)
		#expect(held.unlock(database: database) == account)
		#expect(held.input(for: group) == nil)
		#expect(held.input(for: account) == changed)
		held.close(account)
		held.lock(closing: nil, database: database)
		#expect(held.unlock(database: database) == nil)
	}

	@Test("A database that a backup replaced while the app was locked gets no input of the database before it")
	func replacedDatabase() {
		var held = HeldSheet<Sheet, Settings, Int>()
		let sheet = Sheet.accountSettings(girokonto.id)
		held.record(changed, of: sheet)
		held.lock(closing: sheet, database: database)
		#expect(held.unlock(database: replacement) == nil)
		#expect(held.input(for: sheet) == nil)
		// The input is gone, also for a later unlock of the first database.
		#expect(held.unlock(database: database) == nil)
	}

	@Test("An opening that is not an unlock of a known database, such as a launch or Try Again, drops the held input")
	func unknownDatabase() {
		var held = HeldSheet<Sheet, Settings, Int>()
		let sheet = Sheet.accountSettings(girokonto.id)
		held.record(changed, of: sheet)
		held.lock(closing: sheet, database: database)
		#expect(held.unlock(database: nil) == nil)
		#expect(held.unlock(database: database) == nil)
		// A lock whose database the app could not read keeps nothing either.
		held.record(changed, of: sheet)
		held.lock(closing: sheet, database: nil)
		#expect(held.unlock(database: nil) == nil)
	}

	@Test("The app can look at the returning input before the sheet shows, and the sheet still takes it")
	func peek() {
		var held = HeldSheet<Sheet, Settings, Int>()
		let sheet = Sheet.accountSettings(girokonto.id)
		held.record(changed, of: sheet)
		held.lock(closing: sheet, database: database)
		#expect(held.returningInput == nil)
		_ = held.unlock(database: database)
		#expect(held.returningInput == changed)
		#expect(held.input(for: sheet) == changed)
		held.close(sheet)
		#expect(held.returningInput == nil)
	}

	@Test("An optional input reads as nothing when no input returns, never as an input of nil")
	func optionalInput() {
		var held = HeldSheet<Sheet, any Sendable, Int>()
		let sheet = Sheet.groupSettings(haushalt)
		let group = AccountGroup(name: "Haushalt", position: 0)
		// A normal opening: nothing returns, so the sheet keeps the group that it loaded.
		let nothing = held.input(for: sheet, as: AccountGroup?.self)
		#expect(nothing == nil)
		held.record(Optional(group), of: sheet)
		held.lock(closing: sheet, database: database)
		_ = held.unlock(database: database)
		let returned = held.input(for: sheet, as: AccountGroup?.self)
		#expect(returned == .some(.some(group)))
	}

	@Test("An input of another type reads as nothing")
	func otherType() {
		var held = HeldSheet<Sheet, any Sendable, Int>()
		let sheet = Sheet.groupSettings(haushalt)
		held.record("Haushalt", of: sheet)
		held.lock(closing: sheet, database: database)
		_ = held.unlock(database: database)
		#expect(held.input(for: sheet, as: Int.self) == nil)
	}
}
