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

	/// A drop on the row of a group and a drop in a gap are the two drop targets of the section "Accounts".
	@Test("A drop on a group row puts the row at the end of the group, and a drop in a gap at that gap")
	func dropTargets() {
		let giro = Account(position: 0, name: "Girokonto", kind: .giro, source: .offline)
		let privat = AccountGroup(name: "Private", position: 1)
		let savings = Account(groupID: privat.id, position: 0, name: "Tagesgeld", kind: .savings, source: .offline)
		let card = Account(groupID: privat.id, position: 1, name: "Kreditkarte", kind: .creditCard, source: .offline)
		let l = Ledger(groups: [privat], accounts: [giro, savings, card])

		let onGroup = l.destination(of: .group(privat.id))
		#expect(onGroup.parent == privat.id && onGroup.index == 2)
		let into = moving(giro.id, into: onGroup.parent, at: onGroup.index, in: l)
		#expect(rows(into, in: privat.id) == ["0 Tagesgeld", "1 Kreditkarte", "2 Girokonto"])
		#expect(rows(into, in: nil) == ["0 Private"])
		// The gap beside the group row: after "Private" at the top level, where "Girokonto" stays out of the group.
		let beside = l.destination(of: .gap(parent: nil, index: 2))
		#expect(beside.parent == nil && beside.index == 2)
		#expect(rows(moving(giro.id, into: beside.parent, at: beside.index, in: l), in: nil) == ["0 Private", "1 Girokonto"])
		// An empty group takes the row at its first gap.
		let empty = AccountGroup(name: "Business", position: 2)
		let withEmpty = Ledger(groups: [privat, empty], accounts: [giro, savings, card])
		#expect(withEmpty.destination(of: .group(empty.id)).index == 0)
	}

	@Test("A collapsed group shows the error and the new transactions of the accounts in it and in its subgroups")
	func markers() {
		let privat = AccountGroup(name: "Private", position: 0, isExpanded: false)
		let family = AccountGroup(name: "Family", parentID: privat.id, position: 1)
		let error = RefreshError(failure: .pinRejected(BankMessage(code: "9931", text: "The PIN is wrong.")), date: Date(timeIntervalSince1970: 1_800_000_000))
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

	/// The scenarios of "Remove an account group" in openspec/changes/add-account-management/specs/account-management/spec.md.
	@Test("A removed nested group leaves its accounts and subgroups in its place in the group above it, with their transactions")
	func removeNestedGroup() {
		let privat = AccountGroup(name: "Private", position: 0)
		let giro = Account(groupID: privat.id, position: 0, name: "Giro", kind: .giro, source: .offline)
		let cards = AccountGroup(name: "Cards", parentID: privat.id, position: 1)
		let savings = Account(groupID: privat.id, position: 2, name: "Savings", kind: .savings, source: .offline)
		let visa = Account(groupID: cards.id, position: 0, name: "Visa", kind: .creditCard, source: .offline)
		let oldCards = AccountGroup(name: "Old cards", parentID: cards.id, position: 1)
		let master = Account(groupID: oldCards.id, position: 0, name: "Mastercard", kind: .creditCard, source: .offline)
		let bookings = (1...3).map { Transaction(accountID: visa.id, bookingDate: Day(year: 2026, month: 11, day: $0), amountMinor: -1_250, name: "Bäckerei Muster") }
		var l = Ledger(groups: [privat, cards, oldCards], accounts: [giro, savings, visa, master], transactions: bookings)

		let change = l.removal(ofGroup: cards.id)
		l.remove(group: cards.id, moving: change)

		#expect(rows(l, in: privat.id) == ["0 Giro", "1 Visa", "2 Old cards", "3 Savings"])
		#expect(rows(l, in: oldCards.id) == ["0 Mastercard"])
		#expect(rows(l, in: nil) == ["0 Private"])
		#expect(l.group(cards.id) == nil)
		#expect(l.transactions.filter { $0.accountID == visa.id }.count == 3)
		// Only the rows whose parent or position changed are written.
		#expect(Set(change.accounts.map(\.name)) == ["Visa", "Savings"])
		#expect(change.groups.map(\.name) == ["Old cards"])
	}

	@Test("A removed top level group leaves its accounts at the top level in its place")
	func removeTopLevelGroup() {
		let bargeld = Account(position: 0, name: "Bargeld", kind: .cash, source: .offline)
		let privat = AccountGroup(name: "Private", position: 1)
		let depot = Account(position: 2, name: "Depot", kind: .portfolio, source: .offline)
		let giro = Account(groupID: privat.id, position: 0, name: "Giro", kind: .giro, source: .offline)
		let savings = Account(groupID: privat.id, position: 1, name: "Savings", kind: .savings, source: .offline)
		var l = Ledger(groups: [privat], accounts: [bargeld, depot, giro, savings])

		l.remove(group: privat.id, moving: l.removal(ofGroup: privat.id))

		#expect(rows(l, in: nil) == ["0 Bargeld", "1 Giro", "2 Savings", "3 Depot"])
		#expect(l.groups.isEmpty)
	}

	@Test("Removing a group takes only the parent and the position from the change, so a refresh that stored an account meanwhile keeps its balance")
	func removeGroupKeepsRefresh() {
		let privat = AccountGroup(name: "Private", position: 0)
		let giro = Account(groupID: privat.id, position: 0, name: "Giro", kind: .giro, source: .bank)
		var l = Ledger(groups: [privat], accounts: [giro])
		let change = l.removal(ofGroup: privat.id)
		var refreshed = giro
		refreshed.bankBalanceMinor = 123_45
		l.upsert(refreshed)

		l.remove(group: privat.id, moving: change)

		#expect(l.account(giro.id)?.bankBalanceMinor == 123_45)
		#expect(l.account(giro.id)?.groupID == nil)
	}

	@Test("An unknown group gives no change")
	func removeUnknownGroup() {
		#expect(Ledger().removal(ofGroup: UUID()).isEmpty)
	}
}
