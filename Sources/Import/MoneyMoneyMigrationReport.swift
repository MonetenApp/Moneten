import Domain
import Foundation

extension MoneyMoneyMigration {
	/// An account of the export with what the source says about it.
	public struct SourceAccount: Sendable, Equatable {
		public var accountID: UUID
		/// The transactions of the export for this account.
		public var rows: [Transaction] = []
		public var balance: Money?
	}

	/// What the app holds after the migration, for each account of the source next to the numbers of the source.
	public struct Report: Sendable, Equatable {
		public struct Row: Sendable, Equatable {
			public var name: String
			/// The transactions of the source that the account holds, recognized as a second run recognizes them, and
			/// the migrated transactions that the source no longer has.
			public var transactions: Int
			public var sourceTransactions: Int
			/// Without pending transactions, because the source reports its balance without them, and without
			/// transactions that a file or a bank added.
			public var balance: Money
			public var sourceBalance: Money?

			public var matches: Bool {
				transactions == sourceTransactions && (sourceBalance == nil || sourceBalance == balance)
			}
		}

		public var rows: [Row]
		public var notes: [String]

		/// The report as plain text for a file, with amounts in the format of `locale`.
		/// "1 transaction" or "1,234 transactions" in the format of `locale`.
		public static func count(_ n: Int, locale: Locale = .current) -> String {
			n == 1 ? "1 transaction" : "\(n.formatted(.number.locale(locale))) transactions"
		}

		/// The footer of the list of accounts.
		public static let balanceRule = "Balances count only the transactions from MoneyMoney and leave out pending ones, as MoneyMoney shows them."

		public func text(locale: Locale = .current) -> String {
			func count(_ n: Int) -> String { Self.count(n, locale: locale) }
			func amount(_ money: Money) -> String {
				money.decimal.formatted(Decimal.FormatStyle(locale: locale).precision(.fractionLength(money.decimalPlaces))) + " " + money.currency
			}
			var lines = ["Report of the migration from MoneyMoney", "", "Accounts", Self.balanceRule]
			for row in rows {
				let source = "MoneyMoney: \(count(row.sourceTransactions))" + (row.sourceBalance.map { ", balance \(amount($0))" } ?? "")
				lines.append("\(row.name): \(count(row.transactions)), balance \(amount(row.balance)). \(source). \(row.matches ? "Matches." : "Differs.")")
			}
			if !notes.isEmpty {
				lines += ["", "Notes"] + notes
			}
			return lines.joined(separator: "\n") + "\n"
		}
	}
}

extension MoneyMoneyMigration.Plan {
	/// Compares the accounts of `ledger`, the ledger after the import, with the export. A row that a file or a bank
	/// added to the account is no row of the source, so it counts neither in the number nor in the balance, by the
	/// rule of the initial balance.
	public func report(after ledger: Ledger) -> MoneyMoneyMigration.Report {
		let rules = Categorizer(ledger: ledger)
		let rows = sources.compactMap { source -> MoneyMoneyMigration.Report.Row? in
			guard let account = ledger.account(source.accountID) else { return nil }
			let stored = ledger.transactions(ofAccount: account.id)
			let missing = reconcile(.migration(source.rows), into: account, stored: stored, deleted: [], rules: rules, now: Date()).added.count
			// A row that the source deleted after an earlier run stays in the app, so the account holds one more.
			let exported = Set(source.rows.compactMap(\.sourceID))
			let gone = stored.filter { MoneyMoneyMigration.isOfSource($0.sourceID) && !exported.contains($0.sourceID!) }.count
			let booked = stored.reduce(account.initialBalanceMinor) { sum, t in
				!t.isPending && t.currency == account.currency && MoneyMoneyMigration.isOfSource(t.sourceID) ? sum + t.amountMinor : sum
			}
			return .init(name: account.name, transactions: source.rows.count - missing + gone, sourceTransactions: source.rows.count,
				balance: account.reportedBalance ?? Money(minorUnits: booked, currency: account.currency), sourceBalance: source.balance)
		}
		return .init(rows: rows, notes: notes)
	}
}
