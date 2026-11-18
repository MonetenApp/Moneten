import Foundation
import Testing
@testable import Domain

/// The scenarios "Empty name from an extension" and "Empty name in a migration" of "Account name", and "Empty group name"
/// and "Group stored without a name" of "Create and rename account groups", in openspec/changes/add-account-management/specs/account-management/spec.md.
@Suite("Account name")
struct AccountNameTests {
	@Test("An account that a source brings without a name, or with one of only white space, is named after its type",
		arguments: [(nil, AccountKind.giro, "Giro account"), ("", .savings, "Savings account"), ("  ", .creditCard, "Credit card"), ("\t\n", .other, "Other")] as [(String?, AccountKind, String)])
	func namedAfterType(given: String?, kind: AccountKind, expected: String) {
		#expect(Account.name(from: given, kind: kind) == expected)
	}

	@Test("Any other name of a source stays as it is, white space around it included, so a file read back gives the same name",
		arguments: ["Giro Direkt", " Haushalt ", "0"])
	func keptName(given: String) {
		#expect(Account.name(from: given, kind: .giro) == given)
	}

	/// The group settings enable OK only for an accepted name, also when the name is the one stored, so a group that a
	/// migration or an import stored with an empty name cannot be saved with it again.
	@Test("The group settings accept a name only when something is left without white space, also an unchanged stored one", arguments: [
		("", false), ("   ", false), ("\t\n", false), ("  Private ", true), ("Old cards", true),
	] as [(String, Bool)])
	func groupName(name: String, accepted: Bool) {
		#expect((Account.acceptedName(name) != nil) == accepted)
	}

	@Test("Saving the group settings with an empty name keeps the old name, and an unchanged name stays as it is stored")
	func groupSettings() {
		let opened = AccountGroup(name: " Private ", position: 0)
		for typed in ["", "   "] {
			var edited = opened
			edited.name = typed
			edited.showSum = false
			var current = opened
			current.takeSettings(from: edited, opened: opened)
			#expect(current.name == " Private ")
			#expect(!current.showSum)
		}
		var edited = opened
		edited.groupsByAccount.toggle()
		var current = opened
		current.takeSettings(from: edited, opened: opened)
		#expect(current.name == " Private ")
		edited.name = "  Business "
		current.takeSettings(from: edited, opened: opened)
		#expect(current.name == "Business")
	}
}
