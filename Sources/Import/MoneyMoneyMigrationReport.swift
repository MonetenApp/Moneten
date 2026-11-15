import Domain
import Foundation

extension MoneyMoneyMigration {
	/// An account of the export with what the source says about it.
	public struct SourceAccount: Sendable, Equatable {
		public var accountID: UUID
		public var transactions = 0
		public var balance: Money?
	}

	/// What the app holds after the migration, for each account of the source next to the numbers of the source.
	public struct Report: Sendable, Equatable {
		public struct Row: Sendable, Equatable {
			public var name: String
			public var transactions: Int
			public var sourceTransactions: Int
			/// Without pending transactions, because the source reports its balance without them.
			public var balance: Money
			public var sourceBalance: Money?

			public var matches: Bool {
				transactions == sourceTransactions && (sourceBalance == nil || sourceBalance == balance)
			}
		}

		public var rows: [Row]
		public var notes: [String]

		/// The report as plain text for a file, with amounts in the format of `locale`.
		public func text(locale: Locale = .current) -> String {
			func amount(_ money: Money) -> String {
				money.decimal.formatted(Decimal.FormatStyle(locale: locale).precision(.fractionLength(money.decimalPlaces))) + " " + money.currency
			}
			func count(_ n: Int) -> String { n == 1 ? "1 transaction" : "\(n) transactions" }
			var lines = ["Report of the migration from MoneyMoney", "", "Accounts"]
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
	/// Compares the accounts of `ledger`, the ledger after the import, with the export.
	public func report(after ledger: Ledger) -> MoneyMoneyMigration.Report {
		let rows = sources.compactMap { source -> MoneyMoneyMigration.Report.Row? in
			guard let account = ledger.account(source.accountID) else { return nil }
			let transactions = ledger.transactions(ofAccount: account.id)
			let booked = transactions.reduce(account.initialBalanceMinor) { sum, t in
				!t.isPending && t.currency == account.currency ? sum + t.amountMinor : sum
			}
			return .init(name: account.name, transactions: transactions.count, sourceTransactions: source.transactions,
				balance: account.reportedBalance ?? Money(minorUnits: booked, currency: account.currency), sourceBalance: source.balance)
		}
		return .init(rows: rows, notes: notes)
	}
}
