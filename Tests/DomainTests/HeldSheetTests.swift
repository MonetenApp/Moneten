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

	let girokonto = Account(position: 0, name: "Girokonto", kind: .giro, source: .offline)
	let haushalt = UUID()

	var changed: Settings {
		var a = girokonto
		a.name = "Haushaltskonto"
		return Settings(account: a, color: "#2E7D32")
	}

	@Test("The lock keeps the open account settings with a changed name and color, and the unlock gives them back once")
	func lockAndUnlock() {
		var held = HeldSheet<Sheet, Settings>()
		let sheet = Sheet.accountSettings(girokonto.id)
		held.record(Settings(account: girokonto, color: "#1565C0"), of: sheet)
		held.record(changed, of: sheet)
		held.lock(closing: sheet)
		#expect(held.unlock() == sheet)
		#expect(held.input(for: sheet) == changed)
		// The input goes back once. A later opening of the same settings starts from the account.
		#expect(held.input(for: sheet) == nil)
		#expect(held.unlock() == nil)
	}

	@Test("A sheet that opens without a lock before it starts from the stored values")
	func noLock() {
		var held = HeldSheet<Sheet, Settings>()
		let sheet = Sheet.accountSettings(girokonto.id)
		held.record(changed, of: sheet)
		#expect(held.input(for: sheet) == nil)
		#expect(held.unlock() == nil)
	}

	@Test("The lock keeps nothing when no sheet is open, also when a closed sheet left its input")
	func noSheetOpen() {
		var held = HeldSheet<Sheet, Settings>()
		held.record(changed, of: .accountSettings(girokonto.id))
		held.lock(closing: nil)
		#expect(held.unlock() == nil)
		#expect(held.input(for: .accountSettings(girokonto.id)) == nil)
	}

	@Test("The lock keeps nothing for an open sheet whose input it does not know")
	func otherSheetOpen() {
		var held = HeldSheet<Sheet, Settings>()
		held.record(changed, of: .accountSettings(girokonto.id))
		held.lock(closing: .groupSettings(haushalt))
		#expect(held.unlock() == nil)
	}

	@Test("Closing the database for good, as a quit or a database that changed on disk does, drops the held input")
	func drop() {
		var held = HeldSheet<Sheet, Settings>()
		let sheet = Sheet.accountSettings(girokonto.id)
		held.record(changed, of: sheet)
		held.lock(closing: sheet)
		held.drop()
		#expect(held.unlock() == nil)
		#expect(held.input(for: sheet) == nil)
	}

	@Test("A sheet that the unlock gave back but that never showed drops its input at the next drop")
	func dropAfterUnlock() {
		var held = HeldSheet<Sheet, Settings>()
		let sheet = Sheet.accountSettings(girokonto.id)
		held.record(changed, of: sheet)
		held.lock(closing: sheet)
		#expect(held.unlock() == sheet)
		held.drop()
		#expect(held.input(for: sheet) == nil)
	}

	@Test("The input of the first lock is not given to a second sheet, and the second lock keeps only its own sheet")
	func secondLock() {
		var held = HeldSheet<Sheet, Settings>()
		let account = Sheet.accountSettings(girokonto.id)
		let group = Sheet.groupSettings(haushalt)
		held.record(changed, of: account)
		held.lock(closing: account)
		#expect(held.unlock() == account)
		#expect(held.input(for: group) == nil)
		#expect(held.input(for: account) == changed)
		held.lock(closing: nil)
		#expect(held.unlock() == nil)
	}
}
