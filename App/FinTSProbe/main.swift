// FinTSProbe fetches the accounts, balances, and transactions of one bank access through
// HBCI4Swift and prints what arrived. It is the prototype of issue #11 and only reads: it sends
// no payment, and it answers every Verification of Payee question with "abort".
//
// It is an app bundle that runs in the terminal, because HBCI4Swift loads its syntax files from
// Contents/Frameworks of the main bundle:
//
//   FINTS_PRODUCT_ID=<registered product ID> \
//   .build/xcode/Build/Products/Debug/FinTSProbe.app/Contents/MacOS/FinTSProbe \
//     --bank-code 12345678 --url https://bank.example/fints --user <login name> [--customer <ID>]
//     [--tan-method <code>] [--bic <BIC>] [--days 90] [--show-values] [--verbose]
//
// --bic fills in the BIC for accounts whose account information from the bank has none. The SEPA
// versions of the transaction orders need it.
//
// The PIN is read from the terminal without echo and is never printed. Without --show-values the
// output has no amounts and no full account numbers: IBANs and runs of six or more digits are masked,
// also in texts of the bank and in log lines of HBCI4Swift. Those texts can still hold names, so read
// the output once before you share it.

@preconcurrency import Foundation
@preconcurrency import HBCI4Swift

struct Options {
	var bankCode = ""
	var url = ""
	var user = ""
	var customer: String?
	var tanMethod: String?
	var bic: String?
	var days = 90
	var showValues = false
	var verbose = false

	init(_ arguments: [String]) throws {
		var rest = arguments[...]
		func value(_ name: String) throws -> String {
			guard let v = rest.popFirst() else { throw ProbeError.usage("\(name) needs a value") }
			return v
		}
		while let argument = rest.popFirst() {
			switch argument {
			case "--bank-code": bankCode = try value(argument)
			case "--url": url = try value(argument)
			case "--user": user = try value(argument)
			case "--customer": customer = try value(argument)
			case "--tan-method": tanMethod = try value(argument)
			case "--bic": bic = try value(argument)
			case "--days":
				guard let d = Int(try value(argument)), d > 0 else { throw ProbeError.usage("--days needs a number") }
				days = d
			case "--show-values": showValues = true
			case "--verbose": verbose = true
			default: throw ProbeError.usage("unknown argument \(argument)")
			}
		}
		if bankCode.isEmpty || url.isEmpty || user.isEmpty {
			throw ProbeError.usage("--bank-code, --url, and --user are required")
		}
	}
}

enum ProbeError: Error, CustomStringConvertible {
	case usage(String)
	case failed(String)

	var description: String {
		switch self {
		case .usage(let text): "\(text)\nSee the comment at the top of App/FinTSProbe/main.swift."
		case .failed(let text): text
		}
	}
}

/// Prints errors and warnings of HBCI4Swift, and its info lines with --verbose.
/// HBCI4Swift logs whole messages at info and debug level when something fails. A PIN/TAN message
/// carries the PIN in its signature, so lines with message segments or with the PIN never print.
final class ProbeLog: HBCILog {
	let verbose: Bool
	let secret: String

	init(verbose: Bool, secret: String) {
		self.verbose = verbose
		self.secret = secret
	}

	private func print(_ level: String, _ message: String?) {
		guard let message else { return }
		if message.contains("HNHBK") || message.contains("HNSHA") || message.contains("HNVSD") || message.contains(secret) {
			Swift.print("[\(level)] (message content left out)")
			return
		}
		Swift.print("[\(level)] \(maskedText(message))")
	}

	func logError(_ message: String?, file: String, function: String, line: Int) { print("error", message) }
	func logWarning(_ message: String?, file: String, function: String, line: Int) { print("warning", message) }
	func logInfo(_ message: String?, file: String, function: String, line: Int) { if verbose { print("info", message) } }
	func logDebug(_ message: String?, file: String, function: String, line: Int) {}
}

/// Asks for TANs in the terminal and refuses every payment question.
final class ProbeCallback: HBCICallback {
	func getTan(_ user: HBCIUser, challenge: String?, challenge_hhd_uc: String?, type: HBCIChallengeType) throws -> String {
		switch type {
		case .flicker: print("The bank sent a flicker code. This probe cannot show it. Use a TAN method without chipTAN optical.")
		case .photo: print("The bank sent a photoTAN image. This probe cannot show it.")
		case .none: break
		}
		print("Bank: \(maskedText(challenge ?? "(no text)"))")
		print("TAN: ", terminator: "")
		guard let tan = readLine(), !tan.isEmpty else { throw ProbeError.failed("no TAN entered") }
		return tan
	}

	func decoupledNotification(_ user: HBCIUser, challenge: String?) {
		print("Bank: \(maskedText(challenge ?? "Confirm the request in your banking app."))")
		print("Waiting for the confirmation in the app …")
	}

	func vopConfirmation(_ vopResult: HBCIVoPResult) -> HBCIVopConfirmationCallbackResult {
		.abort
	}
}

func readPIN() throws -> String {
	var buffer = [CChar](repeating: 0, count: 256)
	guard let pointer = readpassphrase("PIN: ", &buffer, buffer.count, RPP_REQUIRE_TTY),
	      let pin = String(validatingCString: pointer), !pin.isEmpty else {
		throw ProbeError.failed("no PIN entered")
	}
	for i in buffer.indices { buffer[i] = 0 }
	return pin
}

/// "DE89370400440532013000" becomes "DE89…00".
func masked(_ text: String?) -> String {
	guard let text, text.count > 6 else { return text == nil ? "-" : "…" }
	return "\(text.prefix(4))…\(text.suffix(2))"
}

func day(_ date: Date?) -> String {
	guard let date else { return "-" }
	return date.formatted(.iso8601.year().month().day())
}

func send(_ dialog: HBCIDialog, _ build: (HBCICustomMessage) -> HBCIOrder?) throws -> HBCIOrder? {
	guard let message = HBCICustomMessage.newInstance(dialog), let order = build(message) else { return nil }
	return try message.send() ? order : nil
}

func chooseTanMethod(_ methods: [HBCITanMethod], preset: String?) throws -> String {
	print("TAN methods of the bank:")
	for method in methods {
		print("  \(method.secfunc ?? "?")  \(method.name ?? "")  (\(method.zkaMethodName ?? "-"), process \(method.process?.rawValue ?? "-"), decoupled polls \(method.maxPollsDecoupled.map(String.init) ?? "-"))")
	}
	if let preset { return preset }
	if methods.count == 1, let only = methods[0].secfunc { return only }
	print("TAN method: ", terminator: "")
	guard let choice = readLine(), !choice.isEmpty else { throw ProbeError.failed("no TAN method chosen") }
	return choice
}

func summarize(_ items: [HBCIStatementItem], showValues: Bool) {
	func count(_ has: (HBCIStatementItem) -> Bool) -> Int { items.filter(has).count }
	let dates = items.compactMap(\.date).sorted()
	print("    transactions: \(items.count), \(day(dates.first)) to \(day(dates.last))")
	print("    with name \(count { $0.remoteName?.isEmpty == false }), IBAN \(count { $0.remoteIBAN != nil }), BIC \(count { $0.remoteBIC != nil }), purpose \(count { $0.purpose?.isEmpty == false }), value date \(count { $0.valutaDate != nil })")
	print("    with booking text \(count { $0.transactionText != nil }), end-to-end ID \(count { $0.endToEndId != nil }), mandate \(count { $0.mandateId != nil }), creditor ID \(count { $0.creditorId != nil }), cancellations \(count { $0.isCancellation == true })")
	print("    currencies: \(Set(items.compactMap(\.currency)).sorted().joined(separator: ", "))")
	guard showValues else { return }
	for item in items.prefix(5) {
		print("      \(day(item.date))  \(item.value?.stringValue ?? "-") \(item.currency ?? "")  \(item.remoteName ?? "")  \(item.purpose ?? "")")
	}
}

/// The first check of HBCI4Swift that stops a transaction order. The library logs these reasons
/// only at info level and with the full account number, so the probe repeats the checks.
func statementsProblem(_ user: HBCIUser, _ account: HBCIAccount, camt: Bool, order: HBCIOrder?, queued: Bool) -> String {
	let name = camt ? "CamtStatements" : "Statements"
	guard let segment = order?.segment else { return "the library has no \(name) segment the bank supports" }
	guard user.parameters.isOrderSupportedForAccount(name, number: account.number, subNumber: account.subNumber) else {
		return "the bank does not allow \(name) for this account"
	}
	// CAMT and the SEPA versions of MT940 address the account by IBAN and BIC.
	if camt || segment.version >= 7, account.iban == nil || account.bic == nil {
		return "version \(segment.version) needs IBAN and BIC, and the \(account.iban == nil ? "IBAN" : "BIC") is missing; try --bic"
	}
	if !queued { return "the library did not queue the order (version \(segment.version)); run again with --verbose" }
	return "the order was sent, but no statements came back (version \(segment.version)); run again with --verbose"
}

/// Masks IBANs and runs of six or more digits in texts of the bank and of HBCI4Swift.
func maskedText(_ text: String) -> String {
	text.replacing(/[A-Z]{2}\d{2}[A-Z0-9]{10,30}/, with: "IBAN…").replacing(/\d{6,}/, with: "…")
}

func run(_ options: Options) throws {
	guard let product = ProcessInfo.processInfo.environment["FINTS_PRODUCT_ID"], !product.isEmpty else {
		throw ProbeError.usage("set FINTS_PRODUCT_ID to the product ID from the FinTS registration")
	}
	let pin = try readPIN()
	HBCILogManager.setLog(ProbeLog(verbose: options.verbose, secret: pin))
	HBCIDialog.callback = ProbeCallback()

	let user = try HBCIUser(userId: options.user, customerId: options.customer ?? options.user, bankCode: options.bankCode,
	                        hbciVersion: "300", bankURLString: options.url)
	user.pin = pin
	user.setSecurityMethod(HBCISecurityMethodPinTan())
	let dialog = try HBCIDialog(user: user, product: product)

	print("1. Asking for the TAN methods")
	let methods = dialog.getTanMethods() ?? []
	_ = dialog.dialogEnd()
	if methods.isEmpty { throw ProbeError.failed("the bank sent no TAN methods") }
	let tanMethod = try chooseTanMethod(methods, preset: options.tanMethod)

	print("2. Synchronizing with TAN method \(tanMethod)")
	guard let sync = try dialog.syncInitWithTan(tanMethod), sync.isOk(), user.sysId != nil else {
		throw ProbeError.failed("synchronization failed")
	}
	_ = dialog.dialogEnd()

	print("3. Opening the dialog")
	guard try dialog.dialogInit() != nil else { throw ProbeError.failed("dialog initialization failed") }
	defer { _ = dialog.dialogEnd() }
	print("   bank: \(user.bankName ?? "-"), BPD \(user.parameters.bpdVersion), UPD \(user.parameters.updVersion)")

	let accounts = user.parameters.getAccounts()
	print("4. \(accounts.count) accounts")
	let from = Calendar.current.date(byAdding: .day, value: -options.days, to: Date())!
	for account in accounts {
		print("  \(masked(account.iban ?? account.number))  \(account.currency)  type \(account.type.map(String.init) ?? "-")  orders \(account.allowed.count)")
		print("    allowed: \(account.allowed.sorted().joined(separator: ", "))")
		print("    IBAN \(account.iban == nil ? "missing" : "yes"), BIC \(account.bic == nil ? (options.bic == nil ? "missing" : "missing, --bic used") : "yes")")
		if account.bic == nil, let bic = options.bic { account.bic = bic }

		let balance = try send(dialog) { message in
			guard let order = HBCIBalanceOrder(message: message, account: account), order.enqueue() else { return nil }
			return order
		} as? HBCIBalanceOrder
		if let booked = balance?.bookedBalance {
			print("    balance: \(options.showValues ? "\(booked.value.stringValue) \(booked.currency)" : booked.currency), \(day(booked.postingDate))")
		} else {
			print("    balance: not available")
		}

		let camt = user.parameters.isOrderSupportedForAccount("CamtStatements", number: account.number, subNumber: account.subNumber)
		var created: HBCIOrder?
		var queued = false
		let statements: [HBCIStatement]? = try camt
			? (send(dialog) { message in
				guard let order = HBCICamtStatementsOrder(message: message, account: account) else { return nil }
				created = order
				order.dateFrom = from
				queued = order.enqueue()
				return queued ? order : nil
			} as? HBCICamtStatementsOrder)?.statements
			: (send(dialog) { message in
				guard let order = HBCIStatementsOrder(message: message, account: account) else { return nil }
				created = order
				order.dateFrom = from
				queued = order.enqueue()
				return queued ? order : nil
			} as? HBCIStatementsOrder)?.statements
		guard let statements else {
			print("    transactions: not available (\(camt ? "CAMT" : "MT940")): \(statementsProblem(user, account, camt: camt, order: created, queued: queued))")
			continue
		}
		print("    format: \(camt ? "CAMT" : "MT940"), \(statements.count) statements, \(statements.filter { $0.isPreliminary == true }.count) preliminary")
		summarize(statements.flatMap(\.items), showValues: options.showValues)
	}
}

do {
	try run(Options(Array(CommandLine.arguments.dropFirst())))
} catch {
	print("FinTSProbe: \(error)")
	exit(1)
}
