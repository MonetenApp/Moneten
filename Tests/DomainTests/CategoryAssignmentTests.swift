import Foundation
import Testing
@testable import Domain

/// The scenarios of "Restrict a category to an account" and "Assign a category with the keyboard" in
/// openspec/changes/add-categories/specs/categories/spec.md.
@Suite("Assign a category")
struct CategoryAssignmentTests {
	let company = AccountGroup(name: "Company", position: 0)
	let business: Account
	let savings: Account
	let privat = Account(position: 1, name: "Private", kind: .giro, source: .offline)
	let living = Domain.Category(position: 0, name: "Living", isGroup: true)
	let groceries: Domain.Category
	let drugstore: Domain.Category
	let office: Domain.Category
	let travel: Domain.Category
	let getraenke = Domain.Category(position: 3, name: "Getränke")
	let uncategorized = Domain.Category(position: 9, name: "Uncategorized", isDefault: true)

	init() {
		business = Account(groupID: company.id, position: 0, name: "Business", kind: .giro, source: .offline)
		savings = Account(groupID: company.id, position: 1, name: "Reserve", kind: .savings, source: .offline)
		groceries = Domain.Category(parentID: living.id, position: 0, name: "Groceries")
		drugstore = Domain.Category(parentID: living.id, position: 1, name: "Drugstore")
		office = Domain.Category(position: 1, name: "Office", restrictedToID: business.id)
		travel = Domain.Category(position: 2, name: "Business travel", restrictedToID: company.id)
	}

	var ledger: Ledger {
		Ledger(groups: [company], accounts: [business, savings, privat],
			categories: [uncategorized, getraenke, travel, office, drugstore, groceries, living])
	}

	func row(_ account: Account) -> Transaction {
		Transaction(accountID: account.id, bookingDate: Day(year: 2026, month: 11, day: 3), amountMinor: -4_200, name: "Bürobedarf Beispiel")
	}

	@Test("A category restricted to an account takes only the rows of that account")
	func restrictedToAccount() {
		#expect(ledger.canAssign(office, to: [row(privat)]) == false)
		#expect(ledger.canAssign(office, to: [row(business)]) == true)
		#expect(ledger.canAssign(office, to: [row(business), row(privat)]) == false)
	}

	@Test("A category restricted to an account group takes the rows of every account in the group")
	func restrictedToGroup() {
		#expect(ledger.canAssign(travel, to: [row(business), row(savings)]) == true)
		#expect(ledger.canAssign(travel, to: [row(savings), row(privat)]) == false)
	}

	@Test("A category without a restriction takes any row, and a category group takes none")
	func unrestrictedAndGroup() {
		#expect(ledger.canAssign(groceries, to: [row(privat), row(business)]) == true)
		#expect(ledger.canAssign(uncategorized, to: [row(privat)]) == true)
		#expect(ledger.canAssign(living, to: [row(privat)]) == false)
	}

	@Test("Typing narrows the categories in sidebar order and leaves out the groups")
	func matching() {
		let l = ledger
		#expect(l.categories(matching: "groc").map(\.name) == ["Groceries"])
		#expect(l.categories(matching: "GROC").map(\.name) == ["Groceries"])
		#expect(l.categories(matching: " groc ").map(\.name) == ["Groceries"])
		#expect(l.categories(matching: "o").map(\.name) == ["Groceries", "Drugstore", "Office", "Uncategorized"])
		#expect(l.categories(matching: "liv").map(\.name) == [])
		#expect(l.categories(matching: "uncat").map(\.name) == ["Uncategorized"])
	}

	@Test("Umlauts match their spelled-out form both ways")
	func matchingUmlauts() {
		#expect(ledger.categories(matching: "geträ").map(\.name) == ["Getränke"])
		#expect(ledger.categories(matching: "getrae").map(\.name) == ["Getränke"])
	}

	@Test("An empty search lists every category")
	func matchingEmpty() {
		#expect(ledger.categories(matching: "").map(\.name) == ["Groceries", "Drugstore", "Office", "Business travel", "Getränke", "Uncategorized"])
	}

	@Test("The picker leaves out the categories that the accounts of the selection cannot take")
	func matchingForAccounts() {
		let l = ledger
		#expect(l.categories(matching: "", assignableTo: [privat.id]).map(\.name) == ["Groceries", "Drugstore", "Getränke", "Uncategorized"])
		#expect(l.categories(matching: "", assignableTo: [business.id]).map(\.name) == ["Groceries", "Drugstore", "Office", "Business travel", "Getränke", "Uncategorized"])
		#expect(l.categories(matching: "", assignableTo: [business.id, savings.id]).map(\.name) == ["Groceries", "Drugstore", "Business travel", "Getränke", "Uncategorized"])
		#expect(l.categories(matching: "o", assignableTo: [savings.id, privat.id]).map(\.name) == ["Groceries", "Drugstore", "Uncategorized"])
	}
}
