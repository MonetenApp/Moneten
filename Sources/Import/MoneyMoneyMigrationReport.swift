import Domain
import Foundation

extension MoneyMoneyMigration {
	/// An account of the export with what the source says about it.
	public struct SourceAccount: Sendable, Equatable {
		public var sourceID: String
		public var name: String
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
			/// Without pending transactions, because the source reports its balance without them. For a migrated
			/// account also without transactions that a file or a bank added. An account that the app had before
			/// keeps its own balance, see `comparesBalance`.
			public var balance: Money
			public var sourceBalance: Money?
			/// False for an account that the app had before the migration: its balance follows its bank or its own rows.
			public var comparesBalance = true

			public var matches: Bool {
				transactions == sourceTransactions && (!comparesBalance || sourceBalance == nil || sourceBalance == balance)
			}
		}

		public var rows: [Row]
		public var notes: [String]

		/// "1 transaction" or "1,234 transactions" in the language of the interface and the format of `locale`.
		public static func count(_ n: Int, locale: Locale = .current) -> String {
			n == 1 ? String(localized: "1 transaction", locale: locale) : String(localized: "\(n) transactions", locale: locale)
		}

		/// The footer of the list of accounts.
		public static var balanceRule: String {
			String(localized: "Balances count only the transactions from MoneyMoney and leave out pending ones, as MoneyMoney shows them. An account that Moneten had before keeps its own balance, and only its transactions are compared.")
		}

		/// The report as plain text for a file, with amounts in the format of `locale`.
		public func text(locale: Locale = .current) -> String {
			func count(_ n: Int) -> String { Self.count(n, locale: locale) }
			func amount(_ money: Money) -> String { Format.foreignAmount(money, locale: locale) }
			var lines = [String(localized: "Report of the migration from MoneyMoney"), "", String(localized: "Accounts"), Self.balanceRule]
			for row in rows {
				let own = String(localized: "\(row.name): \(count(row.transactions)), balance \(amount(row.balance)).")
				let source = row.sourceBalance.map { String(localized: "MoneyMoney: \(count(row.sourceTransactions)), balance \(amount($0)).") }
					?? String(localized: "MoneyMoney: \(count(row.sourceTransactions)).")
				lines.append([own, source, row.matches ? String(localized: "Matches.") : String(localized: "Differs.")].joined(separator: " "))
			}
			if !notes.isEmpty {
				lines += ["", String(localized: "Notes")] + notes
			}
			return lines.joined(separator: "\n") + "\n"
		}
	}
}

extension MoneyMoneyMigration.Plan {
	public enum Review: Sendable, Equatable {
		case nothingNew
		case importChanges
		case report(MoneyMoneyMigration.Report)
	}

	public func review(in ledger: Ledger) -> Review {
		guard isEmpty else { return .importChanges }
		return notes.isEmpty ? .nothingNew : .report(report(after: ledger))
	}

	/// Compares the accounts of `ledger`, the ledger after the import, with the export. A row that a file or a bank
	/// added to the account is no row of the source, so it counts neither in the number nor in the balance, by the
	/// rule of the initial balance. A row of the source whose ID a bank took over still counts, by its fingerprint.
	public func report(after ledger: Ledger) -> MoneyMoneyMigration.Report {
		let rules = Categorizer(ledger: ledger)
		let byAccount = Dictionary(grouping: ledger.transactions, by: \.accountID)
		let byTarget = Dictionary(grouping: sources, by: \.accountID)
		var missingRows: Set<UUID> = []
		var goneByTarget: [UUID: Int] = [:]
		var mergeNotes: [String] = []
		for source in sources {
			let merged = byTarget[source.accountID] ?? []
			guard merged.first?.sourceID == source.sourceID, let account = ledger.account(source.accountID) else { continue }
			let delivered = merged.flatMap(\.rows)
			let stored = byAccount[account.id] ?? []
			missingRows.formUnion(reconcile(.migration(delivered), into: account, stored: stored, deleted: [], rules: rules, now: Date()).added.map(\.id))
			let exported = Set(delivered.compactMap(\.sourceID))
			let gone = stored.filter { MoneyMoneyMigration.isOfSource($0.sourceID) && !exported.contains($0.sourceID!) }.count
			goneByTarget[account.id] = gone
			if merged.count > 1 {
				let names = merged.map { "\"\($0.name)\"" }.joined(separator: ", ")
				var note = String(localized: "\(merged.count) source accounts, \(names), were merged into \"\(account.name)\". Each line shows the source balance; only transactions are compared.")
				if gone > 0 {
					note += " " + (gone == 1 ? String(localized: "The target also holds 1 migrated transaction no longer in the source export.")
						: String(localized: "The target also holds \(gone) migrated transactions no longer in the source export."))
				}
				mergeNotes.append(note)
			}
		}
		let rows = sources.compactMap { source -> MoneyMoneyMigration.Report.Row? in
			guard let account = ledger.account(source.accountID) else { return nil }
			let stored = byAccount[account.id] ?? []
			let missing = source.rows.filter { missingRows.contains($0.id) }.count
			let shared = (byTarget[account.id]?.count ?? 0) > 1
			let gone = shared ? 0 : goneByTarget[account.id, default: 0]
			func sum(_ rows: [Transaction]) -> Int128 {
				rows.reduce(0) { !$1.isPending && $1.currency == account.currency ? $0 + Int128($1.amountMinor) : $0 }
			}
			let migrated = account.source == .migrated && !shared
			var balance = account.reportedBalance ?? Money(minorUnits: Int64(clampingSum: Int128(account.initialBalanceMinor) + sum(stored)), currency: account.currency)
			if migrated && account.kind != .portfolio {
				// A row without the ID of the source that matches a booked row of the export by its fingerprint is a row
				// of the source whose ID a bank took over. Rows that a stored row of the source holds are no match, and
				// neither is a pending row, which the balance of the source leaves out. A booked form of an ID
				// (`moneymoney-booked:`) counts neither here nor in the initial balance.
				let ofSource = stored.filter { MoneyMoneyMigration.isOfSource($0.sourceID) }
				let others = stored.filter { !MoneyMoneyMigration.isOfSource($0.sourceID) && $0.sourceID?.hasPrefix(Transaction.bookedMigrationIDPrefix) != true }
				let claimed = Set(ofSource.compactMap(\.sourceID))
				let open = source.rows.filter { !$0.isPending && !claimed.contains($0.sourceID ?? "") }
				let added = reconcile(.file(others), into: account, stored: open, deleted: [], rules: rules, now: Date()).added
				balance = Money(minorUnits: Int64(clampingSum: Int128(account.initialBalanceMinor) + sum(ofSource) + sum(others) - sum(added)), currency: account.currency)
			}
			if shared, let sourceBalance = source.balance { balance = sourceBalance }
			return .init(name: source.name, transactions: source.rows.count - missing + gone, sourceTransactions: source.rows.count,
				balance: balance, sourceBalance: source.balance, comparesBalance: migrated)
		}
		return .init(rows: rows, notes: mergeNotes + notes)
	}
}
