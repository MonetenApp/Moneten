import AppKit
import Domain
import CoreGraphics
import Foundation
import ImageIO

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
		/// Accounts of an earlier run with the newer balance from MoneyMoney and the initial balance that follows,
		/// or the color of their icon.
		public var updatedAccounts: [Account] = []
		/// Stored transactions that this run books, marks for review, or gives changed bank fields or a source ID,
		/// as a refresh would. User fields stay.
		public var updatedTransactions: [Transaction] = []
		/// Categories of an earlier run without a color of their own, with the color of MoneyMoney.
		public var updatedCategories: [Domain.Category] = []
		/// Deleted rows that take another source ID: the ID of the row of the source that they keep out, or none when
		/// the source no longer has their row. So a later run counts a deleted row of the source exactly while the source has it.
		public var relinkedDeletedRows: [DeletedTransaction.Relink] = []
		/// Accounts and transactions that the ledger already holds, and transactions the user deleted.
		public var skippedAccounts = 0
		public var skippedTransactions = 0
		public var portfolioAccounts: [String] = []
		public var notes: [String] = []
		/// Each account of the export, in its order, for the report.
		public var sources: [SourceAccount] = []

		public var isEmpty: Bool {
			groups.isEmpty && accounts.isEmpty && categories.isEmpty && transactions.isEmpty && updatedAccounts.isEmpty && updatedTransactions.isEmpty
				&& updatedCategories.isEmpty && relinkedDeletedRows.isEmpty
		}
	}

	public enum Failure: Error, CustomStringConvertible {
		case unreadable(String)
		/// An amount above `Money.maxMinorUnits`, named by what holds it, such as "The amount of transaction 4711".
		case tooLarge(String)

		public var description: String {
			switch self {
			case let .unreadable(what): "The export of \(what) could not be read."
			case let .tooLarge(what): "\(what) is too large."
			}
		}
	}

	public let calendar: Calendar

	public init(calendar: Calendar = .current) {
		self.calendar = calendar
	}

	/// Builds the plan. Objects that the ledger already holds are skipped, and changes the user made since
	/// then stay. Transactions are recognized by `reconcile`, the rule of refreshes and files, so a row that
	/// a refresh stored or whose ID a source took over is not added twice. `deleted` are all deleted rows,
	/// and none of them comes back, except the booked version of a deleted pending row.
	public func plan(accounts accountsData: Data, categories categoriesData: Data, transactions transactionsData: Data, into ledger: Ledger,
		deleted: [DeletedTransaction] = []) throws -> Plan {
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
		try mapAccounts(rawAccounts, ledger: ledger, plan: &plan, map: &accountMap)
		var categoryMap: [String: UUID?] = [:]
		mapCategories(rawCategories, ledger: ledger, plan: &plan, map: &categoryMap)

		var rows: [Transaction] = []
		var sourceRows: [String: [Transaction]] = [:]
		for raw in rawTransactions {
			guard let accountSource = raw["accountUuid"] as? String, let accountID = accountMap[accountSource] else { continue }
			let id = (raw["id"] as? Int).map { "\(Transaction.migrationIDPrefix)\($0)" }
			let currency = (raw["currency"] as? String) ?? "EUR"
			guard let amount = Money(limited: Decimal((raw["amount"] as? Double) ?? 0), currency: currency) else {
				throw Failure.tooLarge((raw["id"] as? Int).map { "The amount of transaction \($0)" } ?? "The amount of a transaction")
			}
			let booking = (raw["bookingDate"] as? Date).map { Day($0, calendar: calendar) } ?? Day.today(calendar: calendar)
			let pending = !((raw["booked"] as? Bool) ?? true)
			var categoryID: UUID?
			if let c = raw["categoryUuid"] as? String, let mapped = categoryMap[c] { categoryID = mapped }
			let t = Transaction(accountID: accountID, bookingDate: booking,
				valueDate: (raw["valueDate"] as? Date).map { Day($0, calendar: calendar) },
				amountMinor: amount.minorUnits, currency: currency,
				name: Self.string(raw["name"]) ?? "", purpose: Self.string(raw["purpose"]) ?? "",
				counterpartyIBAN: Self.string(raw["accountNumber"]), counterpartyBIC: Self.string(raw["bankCode"]),
				bookingText: Self.string(raw["bookingText"]), endToEndReference: Self.string(raw["endToEndReference"]),
				mandateReference: Self.string(raw["mandateReference"]), creditorID: Self.string(raw["creditorId"]),
				comment: Self.string(raw["comment"]), isChecked: (raw["checkmark"] as? Bool) ?? false, isPending: pending,
				categoryID: categoryID, categorizedBy: categoryID == nil ? .none : .manual, isNew: false, sourceID: id)
			rows.append(t)
			sourceRows[accountSource, default: []].append(t)
		}

		let delivered = Dictionary(grouping: rows, by: \.accountID)
		for i in plan.sources.indices { plan.sources[i].rows = sourceRows[plan.sources[i].sourceID] ?? [] }

		// `reconcile` decides which rows are new. A new row keeps what MoneyMoney says: its category, comment,
		// and checkmark, and no new mark. Only the review mark comes from `reconcile`.
		let stored = Dictionary(grouping: ledger.transactions, by: \.accountID)
		let tombstones = Dictionary(grouping: deleted, by: \.accountID)
		let rules = Categorizer(ledger: ledger)
		var added: [UUID: ReviewReason?] = [:]
		var relinked: [UUID: [DeletedTransaction.Relink]] = [:]
		for account in ledger.accounts + plan.accounts {
			guard let rows = delivered[account.id] else { continue }
			let r = reconcile(.migration(rows), into: account, stored: stored[account.id] ?? [], deleted: tombstones[account.id] ?? [],
				rules: rules, now: Date())
			for t in r.added { added.updateValue(t.review, forKey: t.id) }
			plan.updatedTransactions += r.booked + r.updated + r.marked
			plan.skippedTransactions += r.skipped
			relinked[account.id] = r.relinked
		}
		for var t in rows {
			guard let review = added[t.id] else { continue }
			t.review = review
			plan.transactions.append(t)
		}
		Self.setInitialBalances(of: &plan, ledger: ledger, stored: stored, deleted: tombstones, relinked: relinked, exported: Set(accountMap.values),
			delivered: delivered.mapValues { Set($0.compactMap(\.sourceID)) })
		if !rawCategories.contains(where: { ($0["default"] as? Bool) != true && Self.string($0["rules"]) != nil }) {
			plan.notes.append("The export contains no categorization rules. Copy them from the category settings of MoneyMoney into the category settings of Moneten.")
		}
		let accountNumbers = Set(rawAccounts.filter { ($0["uuid"] as? String).flatMap { accountMap[$0] } != nil }
			.flatMap { [Self.string($0["accountNumber"]), Self.string($0["iban"])] }.compactMap { $0 }.map(TextFolding.accountKey)
			+ rows.compactMap(\.counterpartyIBAN).map(TextFolding.accountKey))
		let exportedRules = rawCategories.reduce(into: [String: String]()) { rules, item in
			if let source = item["uuid"] as? String { rules[source] = Self.string(item["rules"]) ?? "" }
		}
		let unchangedCategories = ledger.categories.filter { c in
			guard let source = c.sourceID else { return false }
			return exportedRules[source] == c.rule
		}
		for c in plan.categories + unchangedCategories {
			if let error = c.ruleError {
				plan.notes.append("The rule of \"\(c.name)\" cannot be read at position \(error.position + 1): \(error.message) \"\(c.name)\" receives no transaction through its rule until you correct the rule in its settings.")
			}
			plan.notes += Self.ruleNotes(c, accountNumbers: accountNumbers)
		}
		plan.notes += Self.groupSumNotes(rawAccounts)
		if !plan.portfolioAccounts.isEmpty {
			plan.notes.append("Portfolio accounts were taken over with their balance. Their positions follow when securities accounts are supported.")
		}
		plan.notes += Self.notMigratedNotes
		let budgets = rawCategories.filter(Self.hasBudget).count
		if budgets == 1 {
			plan.notes.append("1 category has a budget in MoneyMoney. Moneten did not take the budget over.")
		} else if budgets > 1 {
			plan.notes.append("\(budgets) categories have a budget in MoneyMoney. Moneten did not take the budgets over.")
		}
		if (rawAccounts + rawCategories).contains(where: { $0["icon"] is Data }) {
			plan.notes.append("Moneten takes the color of each icon of MoneyMoney and shows its own icons instead of the pictures.")
		}
		return plan
	}

	// ISO 13616, SWIFT IBAN Registry release 103 (September 2026).
	// https://www.swift.com/sites/default/files/files/iban-registry_4.pdf
	private static let ruleIBANLengths = [
		"AD": 24, "AE": 23, "AL": 28, "AT": 20, "AZ": 28, "BA": 20, "BE": 16,
		"BG": 22, "BH": 22, "BI": 27, "BR": 29, "BY": 28, "CH": 21, "CR": 22,
		"CY": 28, "CZ": 24, "DE": 22, "DJ": 27, "DK": 18, "DO": 28, "EE": 20,
		"EG": 29, "ES": 24, "FI": 18, "FK": 18, "FO": 18, "FR": 27, "GB": 22,
		"GE": 22, "GI": 23, "GL": 18, "GR": 27, "GT": 28, "HN": 28, "HR": 21,
		"HU": 28, "IE": 22, "IL": 23, "IQ": 23, "IS": 26, "IT": 27, "JO": 30,
		"KW": 30, "KZ": 20, "LB": 28, "LC": 32, "LI": 21, "LT": 20, "LU": 20,
		"LV": 21, "LY": 25, "MC": 27, "MD": 24, "ME": 22, "MK": 19, "MN": 20,
		"MR": 27, "MT": 31, "MU": 30, "NI": 28, "NL": 18, "NO": 15, "OM": 23,
		"PK": 24, "PL": 28, "PS": 29, "PT": 25, "QA": 29, "RO": 24, "RS": 22,
		"RU": 33, "SA": 24, "SC": 31, "SD": 18, "SE": 24, "SI": 19, "SK": 24,
		"SM": 27, "SO": 23, "ST": 25, "SV": 28, "TL": 23, "TN": 24, "TR": 26,
		"UA": 29, "VA": 22, "VG": 24, "XK": 20, "YE": 30,
	]

	private static func ruleNotes(_ category: Domain.Category, accountNumbers: Set<String>) -> [String] {
		guard !category.isGroup, !category.isDefault, let tokens = try? RuleToken.positioned(in: category.rule) else { return [] }
		let chars = Array(category.rule)
		var notes: [String] = []
		for (i, entry) in tokens.enumerated() {
			if i > 0, case .field = tokens[i - 1].token { continue }
			let prefix = "The rule of \"\(category.name)\""
			switch entry.token {
			case let .word(term), let .quoted(term):
				let number = TextFolding.accountKey(term)
				let groups = term.split(separator: " ", omittingEmptySubsequences: false)
				let grouped = groups.count == 1 || (groups.dropLast().allSatisfy { $0.count == 4 } && (1...4).contains(groups.last!.count))
				let iban = term.utf8.allSatisfy { $0 < 128 } && grouped
					&& Self.ruleIBANLengths[String(number.prefix(2))] == number.count && Self.isIBAN(number)
				let knownNumber = !number.isEmpty && number.allSatisfy { $0.isASCII && $0.isNumber } && accountNumbers.contains(number)
				if iban || knownNumber {
					notes.append("\(prefix) has an account term at position \(entry.position + 1) that does not search account fields. Use remote_account:\(number) to search the account of the counterparty.")
				}
			case .and, .or, .not:
				let length = entry.token == .or ? 2 : 3
				let word = String(chars[entry.position...].prefix(length))
				if ["and", "or", "not"].contains(word.lowercased()), word != word.uppercased() {
					notes.append("\(prefix) reads \"\(word)\" at position \(entry.position + 1) as an operator. Write \"\(word)\" in quotation marks to search the word itself.")
				}
			case let .constant(value):
				let word = String(chars[entry.position...].prefix(value ? 4 : 5))
				notes.append("\(prefix) reads \"\(word)\" at position \(entry.position + 1) as a constant that matches \(value ? "every transaction" : "no transaction"). Write \"\(word)\" in quotation marks to search the word itself.")
			default: break
			}
		}
		return notes
	}

	/// The initial balance makes the booked rows of the source end at the balance of the source. A later run
	/// moves it by what changed in the source since the run before, so a row that the user imported or deleted
	/// keeps moving the balance, and so does an initial balance that the user typed.
	///
	/// A row that the user deleted counts as a row of the source while it carries a migration ID. It takes the ID
	/// of the row of the source that it keeps out, also one that it matched by its fingerprint. The export holds every
	/// transaction of an exported account, so a deleted row whose ID it leaves out is gone from the source: it counts
	/// before this run and not after, and the store forgets its source ID, so no later run counts it again.
	/// A deleted row in another currency never moves the balance, like a stored one.
	private static func setInitialBalances(of plan: inout Plan, ledger: Ledger, stored: [UUID: [Transaction]],
		deleted: [UUID: [DeletedTransaction]], relinked: [UUID: [DeletedTransaction.Relink]], exported: Set<UUID>,
		delivered: [UUID: Set<String>]) {
		let added = Dictionary(grouping: plan.transactions, by: \.accountID)
		for i in plan.accounts.indices {
			guard let balance = plan.accounts[i].bankBalanceMinor else { continue }
			plan.accounts[i].initialBalanceMinor = initialBalance(balance, of: plan.accounts[i], rows: added[plan.accounts[i].id] ?? [])
		}
		let changed = Dictionary(uniqueKeysWithValues: plan.updatedTransactions.map { ($0.id, $0) })
		for old in ledger.accounts where old.source == .migrated && old.kind != .portfolio {
			let tombstones = exported.contains(old.id) ? deleted[old.id] ?? [] : []
			var after = tombstones
			for r in relinked[old.id] ?? [] {
				if let i = after.firstIndex(of: r.row) { after[i].sourceID = r.sourceID }
			}
			for i in after.indices where isCounted(after[i]) && after[i].sourceID.map((delivered[old.id] ?? []).contains) == false {
				after[i].sourceID = nil
			}
			plan.relinkedDeletedRows += zip(tombstones, after).compactMap { $0.sourceID == $1.sourceID ? nil : DeletedTransaction.Relink(row: $0, sourceID: $1.sourceID) }
			let k = plan.updatedAccounts.firstIndex { $0.id == old.id }
			var a = k.map { plan.updatedAccounts[$0] } ?? old
			guard let balance = a.bankBalanceMinor else { continue }
			let before = stored[old.id] ?? []
			let deletedBefore = tombstones.filter { isCounted($0) && $0.currency == old.currency }.reduce(Int64(0)) { $0.addingClamped($1.amountMinor) }
			let deletedAfter = after.filter { isCounted($0) && $0.currency == old.currency }.reduce(Int64(0)) { $0.addingClamped($1.amountMinor) }
			let target = initialBalance(balance, of: a, rows: before.map { changed[$0.id] ?? $0 } + (added[old.id] ?? [])).subtractingClamped(deletedAfter)
			a.initialBalanceMinor = old.bankBalanceMinor.map {
				old.initialBalanceMinor.addingClamped(target).subtractingClamped(initialBalance($0, of: old, rows: before).subtractingClamped(deletedBefore))
			} ?? target
			if let k {
				plan.updatedAccounts[k] = a
			} else if a != old {
				plan.updatedAccounts.append(a)
			}
		}
	}

	/// The balance before the booked rows of the source in the account currency. A row of the source carries a
	/// migration ID. A row that the user imported carries none, and a row that a file or a bank booked while the
	/// source has it pending carries the booked form of the ID, so both count on top. `v13` in `Schema` repairs stored
	/// values by the same rule, so this filter is spelled out here and in its SQL.
	private static func initialBalance(_ balance: Int64, of account: Account, rows: [Transaction]) -> Int64 {
		rows.reduce(balance) { sum, t in
			!t.isPending && t.currency == account.currency && isOfSource(t.sourceID) ? sum.subtractingClamped(t.amountMinor) : sum
		}
	}

	static func isOfSource(_ sourceID: String?) -> Bool {
		sourceID?.hasPrefix(Transaction.migrationIDPrefix) == true
	}

	private static func isCounted(_ deleted: DeletedTransaction) -> Bool {
		!deleted.isPending && isOfSource(deleted.sourceID)
	}

	private func mapAccounts(_ raw: [[String: Any]], ledger: Ledger, plan: inout Plan, map: inout [String: UUID]) throws {
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
			// MoneyMoney puts the IBAN into `accountNumber` and the BIC into `bankCode`.
			let number = Self.string(item["accountNumber"])
			let bankCode = Self.string(item["bankCode"])
			let iban = Self.string(item["iban"]) ?? number.flatMap { Self.isIBAN($0) ? $0 : nil }
			let bic = Self.string(item["bic"]) ?? bankCode.flatMap { Self.isBIC($0) ? $0 : nil }
			var balanceMinor: Int64?
			var currency = (item["currency"] as? String) ?? "EUR"
			if let balance = item["balance"] as? [[Any]], let first = balance.first, first.count >= 2,
				let amount = first[0] as? Double, let c = first[1] as? String {
				currency = c
				guard let money = Money(limited: Decimal(amount), currency: c) else { throw Failure.tooLarge("The balance of the account \"\(name)\"") }
				balanceMinor = money.minorUnits
			}
			let balanceDate = (item["balanceDate"] as? Date) ?? (item["refreshTimestamp"] as? Date)
			let color = (item["icon"] as? Data).flatMap(Self.iconColor)
			defer { if let id = map[source] { plan.sources.append(SourceAccount(sourceID: source, name: name, accountID: id, balance: balanceMinor.map { Money(minorUnits: $0, currency: currency) })) } }
			// The MoneyMoney identifier decides. IBAN or account number match only accounts without one,
			// so that two MoneyMoney accounts with the same IBAN stay apart.
			if var existing = ledger.accounts.first(where: { $0.sourceID == source }) ?? ledger.accounts.first(where: { a in
				a.sourceID == nil && (
					(iban != nil && a.iban.map(TextFolding.accountKey) == iban.map(TextFolding.accountKey))
						|| (bankCode != nil && number != nil && a.bankCode == bankCode && a.accountNumber == number))
			}) {
				map[source] = existing.id
				plan.skippedAccounts += 1
				var changed = false
				if existing.source == .migrated, let balanceMinor, existing.bankBalanceMinor != balanceMinor || existing.bankBalanceDate != balanceDate {
					existing.bankBalanceMinor = balanceMinor
					existing.bankBalanceDate = balanceDate
					changed = true
				}
				// An account of an earlier run gets the color of its MoneyMoney icon, unless the user chose one.
				if let color, existing.color == nil {
					existing.color = color
					changed = true
				}
				if changed { plan.updatedAccounts.append(existing) }
				continue
			}
			let isPortfolio = (item["portfolio"] as? Bool) == true
			if isPortfolio { plan.portfolioAccounts.append(name) }
			let account = Account(groupID: parent, position: position, name: name,
				kind: isPortfolio ? .portfolio : Self.kind(item["type"] as? String),
				source: .migrated, currency: currency, iban: iban, bic: bic,
				accountNumber: number, bankCode: bankCode, owner: Self.string(item["owner"]),
				bankBalanceMinor: balanceMinor, bankBalanceDate: balanceDate,
				comment: Self.string(item["comment"]), sourceID: source, color: color)
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
				// The default category of MoneyMoney maps to the default category: its transactions get no category.
				map[source] = .some(nil)
				continue
			}
			let indentation = (item["indentation"] as? Int) ?? 0
			let parent = indentation > 0 ? parents[indentation - 1] : nil
			let position = positions[parent, default: 0]
			positions[parent] = position + 1
			let isGroup = (item["group"] as? Bool) == true
			if isGroup, Self.string(item["rules"]) != nil {
				plan.notes.append("The rule of the group \"\(name)\" was not taken over, because a group holds no transactions. Move it to a category below the group.")
			}
			let color = (item["icon"] as? Data).flatMap(Self.iconColor)
			if let existing = known.first(where: { $0.sourceID == source || ($0.name == name && $0.parentID == parent && !$0.isDefault) }) {
				map[source] = existing.id
				if isGroup { parents[indentation] = existing.id }
				// A category of an earlier run gets the color of MoneyMoney, unless the user chose one.
				if let color, existing.color == nil, !plan.categories.contains(where: { $0.id == existing.id }),
					!plan.updatedCategories.contains(where: { $0.id == existing.id }) {
					var updated = existing
					updated.color = color
					plan.updatedCategories.append(updated)
				}
				continue
			}
			// A group holds no transactions of its own, so the app gives it no rule.
			let c = Domain.Category(parentID: parent, position: position, name: name, isGroup: isGroup, color: color,
				currency: (item["currency"] as? String) ?? "EUR", rule: isGroup ? "" : Self.string(item["rules"]) ?? "", sourceID: source)
			plan.categories.append(c)
			map[source] = c.id
			if isGroup { parents[indentation] = c.id }
		}
	}

	/// The color of a MoneyMoney category or account, such as "#4A90E2". The export has no color, but
	/// MoneyMoney draws the icon of a category or an account in its color, so this is the mean of the
	/// opaque colored pixels of the icon, or of its opaque pixels when the icon is gray. Nil for an
	/// empty or unreadable icon.
	static func iconColor(_ data: Data) -> String? {
		guard let source = CGImageSourceCreateWithData(data as CFData, nil), let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
			let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
		let width = min(image.width, 64), height = min(image.height, 64)
		guard width > 0, height > 0 else { return nil }
		var pixels = [UInt8](repeating: 0, count: width * height * 4)
		let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
			guard let context = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
				space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
			context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
			return true
		}
		guard drawn else { return nil }
		var colored = (0.0, 0.0, 0.0, 0.0), opaque = (0.0, 0.0, 0.0, 0.0)
		for i in stride(from: 0, to: pixels.count, by: 4) where pixels[i + 3] >= 128 {
			let alpha = Double(pixels[i + 3])
			let r = Double(pixels[i]) * 255 / alpha, g = Double(pixels[i + 1]) * 255 / alpha, b = Double(pixels[i + 2]) * 255 / alpha
			opaque = (opaque.0 + r, opaque.1 + g, opaque.2 + b, opaque.3 + 1)
			let high = max(r, g, b), low = min(r, g, b)
			// Outlines, shadows, and highlights are dark or gray. They would pull the color toward gray.
			if high > 40, (high - low) / high > 0.25 { colored = (colored.0 + r, colored.1 + g, colored.2 + b, colored.3 + 1) }
		}
		let sum = colored.3 > 0 ? colored : opaque
		guard sum.3 > 0 else { return nil }
		func byte(_ v: Double) -> Int { min(255, max(0, Int((v / sum.3).rounded()))) }
		return String(format: "#%02X%02X%02X", byte(sum.0), byte(sum.1), byte(sum.2))
	}

	/// The scripting dictionary of MoneyMoney has no command that exports these.
	static let notMigratedNotes = [
		"Login data was not migrated, because the AppleScript export of MoneyMoney does not contain it. Connect a migrated account to its bank with \"Add Account...\" and enter the login data there.",
		"Transfer templates were not migrated, because the AppleScript export of MoneyMoney does not contain them. Use \"Export Transfer Templates...\" in MoneyMoney to keep them.",
		"Standing orders were not migrated, because the AppleScript export of MoneyMoney does not contain them. Your bank keeps them, so they continue as before.",
		"Statements were not migrated, because the AppleScript export of MoneyMoney does not contain them. Use \"Show in Finder...\" on \"Statements\" in MoneyMoney to find the statement files and copy them to keep them.",
	]

	/// The key layout of a budget in `export categories` was not recorded with the real export. A
	/// `budget` counts when it is a number other than zero, or a dictionary whose `amount` is one. A
	/// dictionary without `amount` counts when it has such a number. A budget of zero counts as none.
	static func hasBudget(_ item: [String: Any]) -> Bool {
		// A cast to Double also accepts a Boolean, so a flag such as a rollover would count as 1. A list such as
		// [[200.0, "EUR"]] is the form of a balance in the same export.
		func amount(_ value: Any?) -> Double? {
			if let list = value as? [Any] { return amount((list.first as? [Any])?.first) }
			guard let n = value as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID() else { return nil }
			return n.doubleValue
		}
		switch item["budget"] {
		case let budget as [String: Any]:
			if let value = budget["amount"] { return amount(value).map { $0 != 0 } ?? false }
			return budget.values.contains { amount($0).map { $0 != 0 } ?? false }
		case let value: return amount(value).map { $0 != 0 } ?? false
		}
	}

	/// Lists the groups whose balance in MoneyMoney differs from the sum of their accounts.
	/// MoneyMoney leaves closed accounts out of the sum of their group, and the export does not say
	/// which accounts are closed.
	static func groupSumNotes(_ raw: [[String: Any]]) -> [String] {
		func balances(_ item: [String: Any]) -> [String: Decimal] {
			var r: [String: Decimal] = [:]
			for case let entry as [Any] in (item["balance"] as? [Any]) ?? [] where entry.count >= 2 {
				if let amount = entry[0] as? Double, let currency = entry[1] as? String {
					r[currency, default: 0] += Money(Decimal(amount), currency: currency).decimal
				}
			}
			return r
		}
		var notes: [String] = []
		for (i, item) in raw.enumerated() where (item["group"] as? Bool) == true {
			let indentation = (item["indentation"] as? Int) ?? 0
			var sum: [String: Decimal] = [:]
			for child in raw[(i + 1)...] {
				if ((child["indentation"] as? Int) ?? 0) <= indentation { break }
				if (child["group"] as? Bool) == true { continue }
				for (c, v) in balances(child) { sum[c, default: 0] += v }
			}
			let shown = balances(item)
			let currencies = Set(shown.keys).union(sum.keys)
			if currencies.contains(where: { shown[$0, default: 0] != sum[$0, default: 0] }) {
				notes.append("The group \"\(item["name"] as? String ?? "")\" has a different balance in MoneyMoney than the sum of its accounts. MoneyMoney leaves closed accounts out of the sum, and its export does not say which accounts are closed. Turn on \"The account has been closed\" in the settings of each closed account of this group.")
			}
		}
		return notes
	}

	static func isIBAN(_ value: String) -> Bool {
		let s = value.replacingOccurrences(of: " ", with: "").uppercased()
		guard s.count >= 15, s.count <= 34, s.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber) }),
			s.prefix(2).allSatisfy(\.isLetter), s.dropFirst(2).prefix(2).allSatisfy(\.isNumber) else { return false }
		var remainder = 0
		for ch in s.dropFirst(4) + s.prefix(4) {
			let digits = ch.isNumber ? String(ch) : String(Int(ch.asciiValue!) - 55)
			for d in digits { remainder = (remainder * 10 + Int(String(d))!) % 97 }
		}
		return remainder == 1
	}

	static func isBIC(_ value: String) -> Bool {
		let s = value.uppercased()
		guard s.count == 8 || s.count == 11, s.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber) }) else { return false }
		return s.prefix(6).allSatisfy(\.isLetter)
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

/// Sends the export commands only to the running MoneyMoney process.
public enum MoneyMoneyExporter {
	public enum Failure: Error, CustomStringConvertible, Equatable {
		case notInstalled
		case notRunning
		case locked
		case notAllowed
		case failed(String)

		public var description: String {
			switch self {
			case .notInstalled:
				"MoneyMoney is not installed on this Mac. You can import transactions from CSV, CAMT, or MT940 files into an account instead."
			case .notRunning:
				"MoneyMoney is not running. Open MoneyMoney and unlock it, then choose \"Check again\"."
			case .locked:
				"MoneyMoney is locked. Unlock MoneyMoney with its database password, then choose \"Check again\"."
			case .notAllowed:
				"macOS does not allow Moneten to read data from MoneyMoney. Allow it in System Settings → Privacy & Security → Automation → Moneten, then choose \"Check again\"."
			case let .failed(message):
				"MoneyMoney did not answer: \(message)"
			}
		}

		static func of(code: Int, message: String) -> Failure {
			switch code {
			case -1743: .notAllowed
			case -2720: .locked
			case -600, -609: .notRunning
			default: message.localizedCaseInsensitiveContains("locked") ? .locked : .failed(message.trimmingCharacters(in: .whitespacesAndNewlines))
			}
		}
	}

	// MoneyMoney.sdef defines these export events and their parameters.
	enum Command: UInt32, Sendable {
		case accounts = 0x65787061
		case categories = 0x65787063
		case transactions = 0x65787074
	}

	public static func exportAccounts() async throws -> Data { try await run(.accounts) }
	public static func exportCategories() async throws -> Data { try await run(.categories) }
	public static func exportTransactions() async throws -> Data { try await run(.transactions) }

	static func run(_ command: Command, bundleIdentifier: String = "com.moneymoney-app.retail", applicationURL: URL? = nil,
		send: @escaping @Sendable (NSAppleEventDescriptor) throws -> NSAppleEventDescriptor = { try $0.sendEvent(options: .waitForReply, timeout: 120) }) async throws -> Data {
		guard (applicationURL ?? NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier)) != nil else { throw Failure.notInstalled }
		return try await withCheckedThrowingContinuation { continuation in
			DispatchQueue.global(qos: .userInitiated).async {
				do {
					guard let application = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).first(where: { !$0.isTerminated }) else {
						throw Failure.notRunning
					}
					let event = NSAppleEventDescriptor(eventClass: 0x4d4f4e59, eventID: command.rawValue,
						targetDescriptor: NSAppleEventDescriptor(processIdentifier: application.processIdentifier), returnID: -1, transactionID: 0)
					if command == .transactions {
						event.setParam(NSAppleEventDescriptor(string: "1990-01-01"), forKeyword: 0x66726474)
						event.setParam(NSAppleEventDescriptor(string: "plist"), forKeyword: 0x66726d74)
					}
					let reply = try send(event)
					if let code = reply.paramDescriptor(forKeyword: 0x6572726e)?.int32Value, code != 0 {
						throw Failure.of(code: Int(code), message: reply.paramDescriptor(forKeyword: 0x65727273)?.stringValue ?? "Error \(code)")
					}
					guard let text = reply.paramDescriptor(forKeyword: 0x2d2d2d2d)?.stringValue else { throw Failure.failed("The export returned no property list.") }
					continuation.resume(returning: Data(text.utf8))
				} catch let failure as Failure {
					continuation.resume(throwing: failure)
				} catch {
					let error = error as NSError
					continuation.resume(throwing: Failure.of(code: error.code, message: error.localizedDescription))
				}
			}
		}
	}
}
