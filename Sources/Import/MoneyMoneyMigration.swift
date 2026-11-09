import Domain
import Foundation

/// Turns the AppleScript exports of MoneyMoney into accounts, categories, and transactions.
///
/// The exports are property lists. `export accounts` and `export categories` return flat lists in
/// sidebar order, where `indentation` gives the nesting and `group` marks a group.
/// `export transactions ... as "plist"` returns a dictionary with the key `transactions`.
public struct MoneyMoneyMigration: Sendable {
	public struct Plan: Sendable {
		public var groups: [AccountGroup] = []
		public var accounts: [Account] = []
		public var categories: [Domain.Category] = []
		public var transactions: [Transaction] = []
		/// Accounts and transactions that an earlier run already brought in.
		public var skippedAccounts = 0
		public var skippedTransactions = 0
		public var portfolioAccounts: [String] = []
		public var notes: [String] = []

		public var isEmpty: Bool { groups.isEmpty && accounts.isEmpty && categories.isEmpty && transactions.isEmpty }
	}

	public enum Failure: Error, CustomStringConvertible {
		case unreadable(String)

		public var description: String {
			switch self {
			case let .unreadable(what): "The export of \(what) could not be read."
			}
		}
	}

	public let calendar: Calendar

	public init(calendar: Calendar = .current) {
		self.calendar = calendar
	}

	/// Builds the plan. Objects that the ledger already holds from an earlier run are skipped,
	/// and changes the user made since then stay.
	public func plan(accounts accountsData: Data, categories categoriesData: Data, transactions transactionsData: Data, into ledger: Ledger) throws -> Plan {
		guard let rawAccounts = try PropertyListSerialization.propertyList(from: accountsData, format: nil) as? [[String: Any]] else {
			throw Failure.unreadable("accounts")
		}
		guard let rawCategories = try PropertyListSerialization.propertyList(from: categoriesData, format: nil) as? [[String: Any]] else {
			throw Failure.unreadable("categories")
		}
		guard let rawTransactionsRoot = try PropertyListSerialization.propertyList(from: transactionsData, format: nil) as? [String: Any],
			let rawTransactions = rawTransactionsRoot["transactions"] as? [[String: Any]] else {
			throw Failure.unreadable("transactions")
		}

		var plan = Plan()
		var accountMap: [String: UUID] = [:]
		mapAccounts(rawAccounts, ledger: ledger, plan: &plan, map: &accountMap)
		var categoryMap: [String: UUID?] = [:]
		mapCategories(rawCategories, ledger: ledger, plan: &plan, map: &categoryMap)

		let existingSourceIDs = Set(ledger.transactions.compactMap(\.sourceID))
		var sums: [UUID: Int64] = [:]
		for raw in rawTransactions {
			guard let accountSource = raw["accountUuid"] as? String, let accountID = accountMap[accountSource] else { continue }
			let id = (raw["id"] as? Int).map { "moneymoney:\($0)" }
			if let id, existingSourceIDs.contains(id) {
				plan.skippedTransactions += 1
				continue
			}
			let currency = (raw["currency"] as? String) ?? "EUR"
			let amount = Money(Decimal((raw["amount"] as? Double) ?? 0), currency: currency)
			let booking = (raw["bookingDate"] as? Date).map { Day($0, calendar: calendar) } ?? Day.today(calendar: calendar)
			var categoryID: UUID?
			if let c = raw["categoryUuid"] as? String, let mapped = categoryMap[c] { categoryID = mapped }
			let pending = !((raw["booked"] as? Bool) ?? true)
			let t = Transaction(accountID: accountID, bookingDate: booking,
				valueDate: (raw["valueDate"] as? Date).map { Day($0, calendar: calendar) },
				amountMinor: amount.minorUnits, currency: currency,
				name: Self.string(raw["name"]) ?? "", purpose: Self.string(raw["purpose"]) ?? "",
				counterpartyIBAN: Self.string(raw["accountNumber"]), counterpartyBIC: Self.string(raw["bankCode"]),
				bookingText: Self.string(raw["bookingText"]), endToEndReference: Self.string(raw["endToEndReference"]),
				mandateReference: Self.string(raw["mandateReference"]), creditorID: Self.string(raw["creditorId"]),
				comment: Self.string(raw["comment"]), isChecked: (raw["checkmark"] as? Bool) ?? false, isPending: pending,
				categoryID: categoryID, categorizedBy: categoryID == nil ? .none : .manual, isNew: false, sourceID: id)
			plan.transactions.append(t)
			if !pending { sums[accountID, default: 0] += t.amountMinor }
		}

		// The initial balance makes the computed balance end at the balance of the bank.
		for i in plan.accounts.indices {
			guard let balance = plan.accounts[i].bankBalanceMinor else { continue }
			plan.accounts[i].initialBalanceMinor = balance - sums[plan.accounts[i].id, default: 0]
		}
		plan.notes.append("MoneyMoney does not export its categorization rules. Copy them from the category settings of MoneyMoney into the category settings of MonetenMoneten.")
		if !plan.portfolioAccounts.isEmpty {
			plan.notes.append("Portfolio accounts were taken over with their balance. Their positions follow when securities accounts are supported.")
		}
		return plan
	}

	private func mapAccounts(_ raw: [[String: Any]], ledger: Ledger, plan: inout Plan, map: inout [String: UUID]) {
		var parents: [Int: UUID] = [:]
		var positions: [UUID?: Int] = [:]
		for item in raw {
			guard let source = item["uuid"] as? String, let name = item["name"] as? String else { continue }
			let indentation = (item["indentation"] as? Int) ?? 0
			let parent = indentation > 0 ? parents[indentation - 1] : nil
			let position = positions[parent, default: 0]
			positions[parent] = position + 1
			if (item["group"] as? Bool) == true {
				let id = ledger.groups.first(where: { $0.name == name && $0.parentID == parent })?.id
				if let id {
					parents[indentation] = id
				} else {
					let g = AccountGroup(name: name, parentID: parent, position: position)
					plan.groups.append(g)
					parents[indentation] = g.id
				}
				continue
			}
			let iban = Self.string(item["iban"])
			let number = Self.string(item["accountNumber"])
			let bankCode = Self.string(item["bankCode"])
			if let existing = ledger.accounts.first(where: { a in
				a.sourceID == source || (iban != nil && a.iban.map(TextFolding.accountKey) == iban.map(TextFolding.accountKey))
					|| (bankCode != nil && number != nil && a.bankCode == bankCode && a.accountNumber == number)
			}) {
				map[source] = existing.id
				plan.skippedAccounts += 1
				continue
			}
			var balanceMinor: Int64?
			var currency = (item["currency"] as? String) ?? "EUR"
			if let balance = item["balance"] as? [[Any]], let first = balance.first, first.count >= 2,
				let amount = first[0] as? Double, let c = first[1] as? String {
				currency = c
				balanceMinor = Money(Decimal(amount), currency: c).minorUnits
			}
			let isPortfolio = (item["portfolio"] as? Bool) == true
			if isPortfolio { plan.portfolioAccounts.append(name) }
			let account = Account(groupID: parent, position: position, name: name,
				kind: isPortfolio ? .portfolio : Self.kind(item["type"] as? String),
				source: .migrated, currency: currency, iban: iban, bic: Self.string(item["bic"]),
				accountNumber: number, bankCode: bankCode, owner: Self.string(item["owner"]),
				bankBalanceMinor: balanceMinor, bankBalanceDate: (item["balanceDate"] as? Date) ?? (item["refreshTimestamp"] as? Date),
				comment: Self.string(item["comment"]), sourceID: source)
			plan.accounts.append(account)
			map[source] = account.id
		}
	}

	private func mapCategories(_ raw: [[String: Any]], ledger: Ledger, plan: inout Plan, map: inout [String: UUID?]) {
		var parents: [Int: UUID] = [:]
		var positions: [UUID?: Int] = [:]
		let known = ledger.categories + plan.categories
		for item in raw {
			guard let source = item["uuid"] as? String, let name = item["name"] as? String else { continue }
			if (item["default"] as? Bool) == true {
				// The default category maps to "Uncategorized": its transactions get no category.
				map[source] = .some(nil)
				continue
			}
			let indentation = (item["indentation"] as? Int) ?? 0
			let parent = indentation > 0 ? parents[indentation - 1] : nil
			let position = positions[parent, default: 0]
			positions[parent] = position + 1
			let isGroup = (item["group"] as? Bool) == true
			if let existing = known.first(where: { $0.sourceID == source || ($0.name == name && $0.parentID == parent && !$0.isDefault) }) {
				map[source] = existing.id
				if isGroup { parents[indentation] = existing.id }
				continue
			}
			let c = Domain.Category(parentID: parent, position: position, name: name, isGroup: isGroup,
				currency: (item["currency"] as? String) ?? "EUR", rule: Self.string(item["rules"]) ?? "", sourceID: source)
			plan.categories.append(c)
			map[source] = c.id
			if isGroup { parents[indentation] = c.id }
		}
	}

	static func string(_ value: Any?) -> String? {
		guard let s = value as? String else { return nil }
		let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
		return t.isEmpty ? nil : t
	}

	static func kind(_ type: String?) -> AccountKind {
		switch type ?? "" {
		case "Giro account", "Girokonto": .giro
		case "Savings account", "Sparkonto", "Tagesgeld", "Tagesgeldkonto": .savings
		case "Fixed term deposit", "Festgeldkonto", "Festgeldanlage": .fixedTermDeposit
		case "Loan account", "Darlehenskonto": .loan
		case "Credit card", "Kreditkarte": .creditCard
		case "Cash account", "Bargeld": .cash
		case "Portfolio", "Depot": .portfolio
		default: .other
		}
	}
}

/// Runs the export commands of MoneyMoney through `osascript`.
public enum MoneyMoneyExporter {
	public enum Failure: Error, CustomStringConvertible {
		case notInstalled
		case locked
		case notAllowed
		case failed(String)

		public var description: String {
			switch self {
			case .notInstalled:
				"MoneyMoney is not installed on this Mac. You can import transactions from CSV, CAMT, or MT940 files instead."
			case .locked:
				"MoneyMoney is locked. Unlock MoneyMoney with its database password, then try again."
			case .notAllowed:
				"macOS does not allow MonetenMoneten to read data from MoneyMoney. Allow it in System Settings → Privacy & Security → Automation, then try again."
			case let .failed(message):
				"MoneyMoney did not answer: \(message)"
			}
		}
	}

	public static var isInstalled: Bool {
		FileManager.default.fileExists(atPath: "/Applications/MoneyMoney.app")
			|| FileManager.default.fileExists(atPath: NSHomeDirectory() + "/Applications/MoneyMoney.app")
	}

	public static func exportAccounts() async throws -> Data { try await run(#"tell application "MoneyMoney" to export accounts"#) }
	public static func exportCategories() async throws -> Data { try await run(#"tell application "MoneyMoney" to export categories"#) }
	public static func exportTransactions() async throws -> Data {
		try await run(#"tell application "MoneyMoney" to export transactions from date "1990-01-01" as "plist""#)
	}

	static func run(_ script: String) async throws -> Data {
		guard isInstalled else { throw Failure.notInstalled }
		return try await withCheckedThrowingContinuation { continuation in
			let process = Process()
			process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
			process.arguments = ["-e", script]
			let out = Pipe()
			let err = Pipe()
			process.standardOutput = out
			process.standardError = err
			let output = DataCollector()
			out.fileHandleForReading.readabilityHandler = { h in output.append(h.availableData) }
			process.terminationHandler = { p in
				out.fileHandleForReading.readabilityHandler = nil
				output.append(out.fileHandleForReading.readDataToEndOfFile())
				let message = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
				if p.terminationStatus == 0 {
					continuation.resume(returning: output.data)
				} else if message.contains("-2720") || message.localizedCaseInsensitiveContains("locked") {
					continuation.resume(throwing: Failure.locked)
				} else if message.contains("-1743") {
					continuation.resume(throwing: Failure.notAllowed)
				} else {
					continuation.resume(throwing: Failure.failed(message.trimmingCharacters(in: .whitespacesAndNewlines)))
				}
			}
			do { try process.run() } catch { continuation.resume(throwing: Failure.failed(error.localizedDescription)) }
		}
	}
}

final class DataCollector: @unchecked Sendable {
	private let lock = NSLock()
	private var buffer = Data()

	func append(_ d: Data) {
		lock.lock()
		buffer.append(d)
		lock.unlock()
	}

	var data: Data {
		lock.lock()
		defer { lock.unlock() }
		return buffer
	}
}
