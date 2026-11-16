import Foundation
import Testing
@testable import Domain

/// The scenarios of "Reorder rows by dragging" and "A collapsed group stands for its accounts" in
/// openspec/changes/add-main-window/specs/main-window/spec.md.
@Suite("Account tree")
struct AccountTreeTests {
	func moving(_ id: UUID, into parent: UUID?, at index: Int, in ledger: Ledger) -> Ledger {
		var l = ledger
		l.apply(ledger.move(treeItem: id, into: parent, at: index))
		return l
	}

	func rows(_ ledger: Ledger, in parent: UUID?) -> [String] {
		ledger.accountTree(in: parent).map { item in
			switch item {
			case let .group(g): "\(g.position) \(g.name)"
			case let .account(a): "\(a.position) \(a.name)"
			}
		}
	}

	@Test("Tagesgeld moves above Girokonto, and Girokonto below Tagesgeld")
	func moveAccountUp() {
		let giro = Account(position: 0, name: "Girokonto", kind: .giro, source: .offline)
		let savings = Account(position: 1, name: "Tagesgeld", kind: .savings, source: .offline)
		let before = Ledger(accounts: [giro, savings])

		#expect(rows(moving(savings.id, into: nil, at: 0, in: before), in: nil) == ["0 Tagesgeld", "1 Girokonto"])
		#expect(rows(moving(giro.id, into: nil, at: 2, in: before), in: nil) == ["0 Tagesgeld", "1 Girokonto"])
		#expect(before.move(treeItem: savings.id, into: nil, at: 2).isEmpty)
		#expect(before.move(treeItem: giro.id, into: nil, at: 1).isEmpty)
	}

	@Test("A group moves between accounts and keeps its accounts")
	func moveGroup() {
		let giro = Account(position: 0, name: "Girokonto", kind: .giro, source: .offline)
		let savings = Account(position: 1, name: "Tagesgeld", kind: .savings, source: .offline)
		let business = AccountGroup(name: "Business", position: 2)
		let card = Account(groupID: business.id, position: 0, name: "Firmenkarte", kind: .creditCard, source: .offline)
		let before = Ledger(groups: [business], accounts: [giro, savings, card])

		let after = moving(business.id, into: nil, at: 1, in: before)

		#expect(rows(after, in: nil) == ["0 Girokonto", "1 Business", "2 Tagesgeld"])
		#expect(rows(after, in: business.id) == ["0 Firmenkarte"])
	}

	@Test("An account moves into a group at a gap, and the rows left behind close up")
	func intoGroup() {
		let giro = Account(position: 0, name: "Girokonto", kind: .giro, source: .offline)
		let privat = AccountGroup(name: "Private", position: 1)
		let savings = Account(position: 2, name: "Tagesgeld", kind: .savings, source: .offline)
		let card = Account(groupID: privat.id, position: 0, name: "Kreditkarte", kind: .creditCard, source: .offline)
		let depot = Account(groupID: privat.id, position: 1, name: "Depot", kind: .portfolio, source: .offline)
		let before = Ledger(groups: [privat], accounts: [giro, savings, card, depot])

		let after = moving(giro.id, into: privat.id, at: 1, in: before)

		#expect(rows(after, in: privat.id) == ["0 Kreditkarte", "1 Girokonto", "2 Depot"])
		#expect(rows(after, in: nil) == ["0 Private", "1 Tagesgeld"])
		#expect(after.account(giro.id)?.groupID == privat.id)
		#expect(after.sum(ofGroup: privat.id).amounts.count == 1)
	}

	@Test("A group does not move into itself or into a group below it")
	func intoOwnTree() {
		let privat = AccountGroup(name: "Private", position: 0)
		let family = AccountGroup(name: "Family", parentID: privat.id, position: 0)
		let other = AccountGroup(name: "Business", position: 1)
		let l = Ledger(groups: [privat, family, other])

		#expect(l.move(treeItem: privat.id, into: privat.id, at: 0).isEmpty)
		#expect(l.move(treeItem: privat.id, into: family.id, at: 0).isEmpty)
		#expect(l.move(treeItem: privat.id, into: UUID(), at: 0).isEmpty)
		#expect(l.move(treeItem: UUID(), into: nil, at: 0).isEmpty)
		#expect(rows(moving(privat.id, into: other.id, at: 0, in: l), in: other.id) == ["0 Private"])
	}

	/// The sidebar gives a drop between rows to the `ForEach` of the parent it lands in, with the gap counted
	/// among the rows of that parent only: an expanded subgroup counts as one row, however many rows it shows.
	/// These are the gaps of a nested group "Private" with the rows "Girokonto", the expanded group "Family"
	/// with two accounts, and "Depot".
	@Test("Every gap of a nested group with an expanded subgroup puts the row where the drop line was")
	func gapsInNestedGroup() {
		let outer = AccountGroup(name: "Accounts", position: 0)
		let privat = AccountGroup(name: "Private", parentID: outer.id, position: 0)
		let giro = Account(groupID: privat.id, position: 0, name: "Girokonto", kind: .giro, source: .offline)
		let family = AccountGroup(name: "Family", parentID: privat.id, position: 1, isExpanded: true)
		let savings = Account(groupID: family.id, position: 0, name: "Tagesgeld", kind: .savings, source: .offline)
		let card = Account(groupID: family.id, position: 1, name: "Kreditkarte", kind: .creditCard, source: .offline)
		let depot = Account(groupID: privat.id, position: 2, name: "Depot", kind: .portfolio, source: .offline)
		let cash = Account(position: 1, name: "Bargeld", kind: .cash, source: .offline)
		let l = Ledger(groups: [outer, privat, family], accounts: [giro, savings, card, depot, cash])

		// A row from outside: each of the four gaps of "Private".
		let fromOutside = (0...3).map { rows(moving(cash.id, into: privat.id, at: $0, in: l), in: privat.id) }
		#expect(fromOutside == [
			["0 Bargeld", "1 Girokonto", "2 Family", "3 Depot"],
			["0 Girokonto", "1 Bargeld", "2 Family", "3 Depot"],
			["0 Girokonto", "1 Family", "2 Bargeld", "3 Depot"],
			["0 Girokonto", "1 Family", "2 Depot", "3 Bargeld"],
		])
		// "Girokonto" from the first row: the gaps before and after it leave it where it is.
		#expect(l.move(treeItem: giro.id, into: privat.id, at: 0).isEmpty)
		#expect(l.move(treeItem: giro.id, into: privat.id, at: 1).isEmpty)
		#expect(rows(moving(giro.id, into: privat.id, at: 2, in: l), in: privat.id) == ["0 Family", "1 Girokonto", "2 Depot"])
		#expect(rows(moving(giro.id, into: privat.id, at: 3, in: l), in: privat.id) == ["0 Family", "1 Depot", "2 Girokonto"])
		// The expanded group moves down past "Depot" and keeps its accounts.
		let groupDown = moving(family.id, into: privat.id, at: 3, in: l)
		#expect(rows(groupDown, in: privat.id) == ["0 Girokonto", "1 Depot", "2 Family"])
		#expect(rows(groupDown, in: family.id) == ["0 Tagesgeld", "1 Kreditkarte"])
		// A row of the subgroup to the gaps of the subgroup, and out of it to a gap of "Private".
		#expect(rows(moving(card.id, into: family.id, at: 0, in: l), in: family.id) == ["0 Kreditkarte", "1 Tagesgeld"])
		let out = moving(savings.id, into: privat.id, at: 3, in: l)
		#expect(rows(out, in: privat.id) == ["0 Girokonto", "1 Family", "2 Depot", "3 Tagesgeld"])
		#expect(rows(out, in: family.id) == ["0 Kreditkarte"])
		// A gap past the end, which the sidebar never gives, goes to the end.
		#expect(rows(moving(cash.id, into: privat.id, at: 9, in: l), in: privat.id).last == "3 Bargeld")
	}

	@Test("A collapsed group shows the error and the new transactions of the accounts in it and in its subgroups")
	func markers() {
		let privat = AccountGroup(name: "Private", position: 0, isExpanded: false)
		let family = AccountGroup(name: "Family", parentID: privat.id, position: 1)
		let error = RefreshError(message: "The PIN is wrong.", code: "9931", date: Date(timeIntervalSince1970: 1_800_000_000))
		let giro = Account(groupID: privat.id, position: 0, name: "Girokonto", kind: .giro, source: .bank, refreshError: error)
		let savings = Account(groupID: family.id, position: 0, name: "Tagesgeld", kind: .savings, source: .offline)
		let outside = Account(position: 1, name: "Bargeld", kind: .cash, source: .offline)
		let new = { (account: Account) in
			Transaction(accountID: account.id, bookingDate: Day(year: 2026, month: 11, day: 2), amountMinor: -1_000, name: "Bäckerei Muster", isNew: true)
		}
		let l = Ledger(groups: [privat, family], accounts: [giro, savings, outside], transactions: [new(giro), new(savings), new(savings), new(outside)])

		let markers = l.markers(ofGroup: privat.id)

		#expect(markers.newTransactions == 3)
		#expect(markers.failedAccounts.map(\.name) == ["Girokonto"])
		#expect(l.markers(ofGroup: family.id) == GroupMarkers(newTransactions: 2, failedAccounts: []))
	}
}
