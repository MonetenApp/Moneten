import Foundation

/// The rows of a group under "Group transactions by account": the transactions of each account in the order of the
/// sidebar, with a heading above the first transaction of each account. The heading belongs to that row and is no row of
/// its own: a table of sections made SwiftUI visit each of 50,000 rows several times on every change of the view, and a
/// heading row of a flat table left the selections of AppKit and of SwiftUI apart once an arrow key reached it
/// (issue #519).
public struct GroupedTransactions: Sendable {
	public struct Heading: Sendable {
		public let account: Account
		/// The heading at the top. The others stand apart from the rows above them.
		public let isFirst: Bool
	}

	/// The transactions in the order of the table.
	public let transactions: [Transaction]
	/// The heading above a transaction, by the ID of the first transaction of each account.
	public let headings: [UUID: Heading]

	/// The transactions of each of `accounts`, in that order. Each account keeps the order of its transactions in
	/// `transactions`. An account without transactions gets no heading, and the transactions of an account that
	/// `accounts` leaves out are not shown.
	public init(_ transactions: [Transaction], groupedBy accounts: [Account]) {
		let byAccount = Dictionary(grouping: transactions, by: \.accountID)
		var ordered: [Transaction] = []
		ordered.reserveCapacity(transactions.count)
		var headings: [UUID: Heading] = [:]
		for account in accounts {
			guard let rows = byAccount[account.id], let first = rows.first else { continue }
			headings[first.id] = Heading(account: account, isFirst: ordered.isEmpty)
			ordered += rows
		}
		self.transactions = ordered
		self.headings = headings
	}
}
