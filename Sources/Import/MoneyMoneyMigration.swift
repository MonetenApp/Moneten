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
		/// Accounts of an earlier run with the newer balance from MoneyMoney, or the color of their icon.
		public var updatedAccounts: [Account] = []
		/// Stored transactions that this run books, marks for review, or gives changed bank fields or a source ID,
		/// as a refresh would. User fields stay.
		public var updatedTransactions: [Transaction] = []
		/// Categories of an earlier run without a color of their own, with the color of MoneyMoney.
		public var updatedCategories: [Domain.Category] = []
		/// Accounts and transactions that the ledger already holds, and transactions the user deleted.
		public var skippedAccounts = 0
		public var skippedTransactions = 0
		public var portfolioAccounts: [String] = []
		public var notes: [String] = []

		public var isEmpty: Bool {
			groups.isEmpty && accounts.isEmpty && categories.isEmpty && transactions.isEmpty && updatedAccounts.isEmpty && updatedTransactions.isEmpty
				&& updatedCategories.isEmpty
		}
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
		mapAccounts(rawAccounts, ledger: ledger, plan: &plan, map: &accountMap)
		var categoryMap: [String: UUID?] = [:]
		mapCategories(rawCategories, ledger: ledger, plan: &plan, map: &categoryMap)

		var rows: [Transaction] = []
		for raw in rawTransactions {
			guard let accountSource = raw["accountUuid"] as? String, let accountID = accountMap[accountSource] else { continue }
			let id = (raw["id"] as? Int).map { "\(Transaction.migrationIDPrefix)\($0)" }
			let currency = (raw["currency"] as? String) ?? "EUR"
			let amount = Money(Decimal((raw["amount"] as? Double) ?? 0), currency: currency)
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
		}

		// `reconcile` decides which rows are new. A new row keeps what MoneyMoney says: its category, comment,
		// and checkmark, and no new mark. Only the review mark comes from `reconcile`.
		let delivered = Dictionary(grouping: rows, by: \.accountID)
		let stored = Dictionary(grouping: ledger.transactions, by: \.accountID)
		let tombstones = Dictionary(grouping: deleted, by: \.accountID)
		let rules = Categorizer(ledger: ledger)
		var added: [UUID: Bool] = [:]
		for account in ledger.accounts + plan.accounts {
			guard let rows = delivered[account.id] else { continue }
			let r = reconcile(.migration(rows), into: account, stored: stored[account.id] ?? [], deleted: tombstones[account.id] ?? [],
				rules: rules, now: Date())
			for t in r.added { added[t.id] = t.needsReview }
			plan.updatedTransactions += r.booked + r.updated + r.marked
			plan.skippedTransactions += r.skipped
		}
		let newAccounts = Dictionary(uniqueKeysWithValues: plan.accounts.map { ($0.id, $0) })
		var sums: [UUID: Int64] = [:]
		for var t in rows {
			guard let needsReview = added[t.id] else { continue }
			t.needsReview = needsReview
			plan.transactions.append(t)
			if newAccounts[t.accountID]?.isInBalance(t) == true { sums[t.accountID, default: 0] += t.amountMinor }
		}

		// The initial balance makes the computed balance end at the balance of the bank.
		for i in plan.accounts.indices {
			guard let balance = plan.accounts[i].bankBalanceMinor else { continue }
			plan.accounts[i].initialBalanceMinor = balance - sums[plan.accounts[i].id, default: 0]
		}
		if !rawCategories.contains(where: { Self.string($0["rules"]) != nil }) {
			plan.notes.append("The export contains no categorization rules. Copy them from the category settings of MoneyMoney into the category settings of Moneten.")
		}
		plan.notes += Self.groupSumNotes(rawAccounts)
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
				balanceMinor = Money(Decimal(amount), currency: c).minorUnits
			}
			let balanceDate = (item["balanceDate"] as? Date) ?? (item["refreshTimestamp"] as? Date)
			let color = (item["icon"] as? Data).flatMap(Self.iconColor)
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
				// The default category maps to "Uncategorized": its transactions get no category.
				map[source] = .some(nil)
				continue
			}
			let indentation = (item["indentation"] as? Int) ?? 0
			let parent = indentation > 0 ? parents[indentation - 1] : nil
			let position = positions[parent, default: 0]
			positions[parent] = position + 1
			let isGroup = (item["group"] as? Bool) == true
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
			let c = Domain.Category(parentID: parent, position: position, name: name, isGroup: isGroup, color: color,
				currency: (item["currency"] as? String) ?? "EUR", rule: Self.string(item["rules"]) ?? "", sourceID: source)
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
				"macOS does not allow Moneten to read data from MoneyMoney. Allow it in System Settings → Privacy & Security → Automation, then try again."
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
			// One thread reads the whole output, so the export arrives in order however large it is.
			DispatchQueue.global(qos: .userInitiated).async {
				let process = Process()
				process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
				process.arguments = ["-e", script]
				let out = Pipe()
				let err = Pipe()
				process.standardOutput = out
				process.standardError = err
				do { try process.run() } catch {
					continuation.resume(throwing: Failure.failed(error.localizedDescription))
					return
				}
				let output = out.fileHandleForReading.readDataToEndOfFile()
				let message = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
				process.waitUntilExit()
				if process.terminationStatus == 0 {
					continuation.resume(returning: output)
				} else if message.contains("-2720") || message.localizedCaseInsensitiveContains("locked") {
					continuation.resume(throwing: Failure.locked)
				} else if message.contains("-1743") {
					continuation.resume(throwing: Failure.notAllowed)
				} else {
					continuation.resume(throwing: Failure.failed(message.trimmingCharacters(in: .whitespacesAndNewlines)))
				}
			}
		}
	}
}
