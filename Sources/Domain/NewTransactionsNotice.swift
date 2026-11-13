import Foundation

/// The notification about the new transactions of one refresh run. It never holds an amount, a
/// counterparty, a purpose, or a balance, and while the app is locked no account name either.
public struct NewTransactionsNotice: Sendable, Equatable {
	/// The sound for the sum of the new transactions.
	public enum Tone: String, Sendable {
		case positive, negative, neutral
	}

	public let count: Int
	/// The accounts that received the transactions, in the order of the sidebar while the app is unlocked.
	public let accounts: [UUID]
	/// The names of `accounts`. Empty while the app is locked.
	public let accountNames: [String]
	public let tone: Tone

	public var title: String { count == 1 ? "1 new transaction" : "\(count) new transactions" }
	public var body: String { accountNames.joined(separator: ", ") }

	/// `stored` are the rows that the run added. With the `ledger` of an unlocked app only the rows that
	/// are still stored and still new count. Nil when nothing counts.
	public init?(stored: [Transaction], ledger: Ledger?) {
		let rows = ledger.map { ledger in stored.filter { ledger.transaction($0.id)?.isNew == true } } ?? stored
		guard !rows.isEmpty else { return nil }
		count = rows.count
		let received = Set(rows.map(\.accountID))
		if let ledger {
			let ordered = ledger.accountsInSidebarOrder.filter { received.contains($0.id) }
			accounts = ordered.map(\.id)
			accountNames = ordered.map(\.name)
		} else {
			var seen = Set<UUID>()
			accounts = rows.map(\.accountID).filter { seen.insert($0).inserted }
			accountNames = []
		}
		var sums: [String: Int64] = [:]
		for t in rows { sums[t.currency, default: 0] += t.amountMinor }
		let signs = Set(sums.values.map { $0.signum() })
		tone = signs == [1] || signs == [0, 1] ? .positive : signs == [-1] || signs == [-1, 0] ? .negative : .neutral
	}
}

extension Ledger {
	/// Every account from top to bottom, as the sidebar lists them.
	public var accountsInSidebarOrder: [Account] {
		func walk(_ parent: UUID?) -> [Account] {
			accountTree(in: parent).flatMap { item -> [Account] in
				switch item {
				case let .group(g): walk(g.id)
				case let .account(a): [a]
				}
			}
		}
		return walk(nil)
	}
}
