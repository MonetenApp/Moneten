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
