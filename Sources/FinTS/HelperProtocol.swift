import Domain
import Foundation

/// The first line to the helper. Tools/FinTSHelper/FinTSHelper.java describes the protocol.
struct Command: Encodable {
	let type: String
	var bankCode: String?
	var url: String?
	var user: String?
	var product: String?
	var version: String?
	/// The passport of hbci4java from the last state, in Base64.
	var state: String?
	var accounts: [Period]?

	/// One account of a refresh and the first day to fetch. No day asks for the full history.
	struct Period: Encodable, Equatable {
		let id: String
		let from: String?
	}
}

/// The answer of the user to a request of the helper. `method` in place of `value` changes the TAN
/// method of a challenge on screen, and the helper then requests a new challenge with that method.
/// `skip` cancels a challenge for older transactions, and the helper then fetches the last 90 days.
struct Answer: Encodable {
	var type = "answer"
	let id: Int
	var value: String?
	var method: String?
	var skip: Bool?
}

/// A line from the helper.
enum HelperMessage: Decodable {
	case ask(id: Int, Ask)
	/// hbci4java went on after a decoupled approval, so the bank has it.
	case withdraw(id: Int)
	/// hbci4java sent a message to the bank, or received its answer. It only restarts the timeout.
	case alive
	/// The certificates of a server, leaf first, for macOS to decide on.
	case trust(id: Int, host: String, chain: [Data])
	case progress(done: Int, of: Int)
	case notice(String)
	case banks([BankDirectory.Entry])
	case accounts([FinTSAccount])
	/// A result that does not read fails only its account.
	case result(account: String, Result<AccountResult, any Error>)
	case accountFailed(account: String, HelperError)
	case state(Data)
	case failed(HelperError)

	private enum Key: String, CodingKey {
		case type, id, done, of, text, banks, accounts, account, data, host, chain
	}

	/// The rejection of the PIN or the block of the access in this message, for the whole access or
	/// for one account.
	var rejection: SyncFailure? {
		let failure: SyncFailure?
		switch self {
		case let .failed(error), let .accountFailed(_, error): failure = error.failure
		case let .result(_, .success(result)): failure = result.shownError?.failure
		case let .ask(_, ask):
			do {
				_ = try ask.request(server: nil)
				failure = nil
			} catch {
				failure = error as? SyncFailure
			}
		default: failure = nil
		}
		return failure?.rejectsPIN == true ? failure : nil
	}

	init(from decoder: Decoder) throws {
		let c = try decoder.container(keyedBy: Key.self)
		switch try c.decode(String.self, forKey: .type) {
		case "ask": self = .ask(id: try c.decode(Int.self, forKey: .id), try Ask(from: decoder))
		case "withdraw": self = .withdraw(id: try c.decode(Int.self, forKey: .id))
		case "alive": self = .alive
		case "trust": self = .trust(id: try c.decode(Int.self, forKey: .id), host: try c.decode(String.self, forKey: .host), chain: try c.decode([Data].self, forKey: .chain))
		case "progress": self = .progress(done: try c.decode(Int.self, forKey: .done), of: try c.decode(Int.self, forKey: .of))
		case "notice": self = .notice(try c.decode(String.self, forKey: .text))
		case "banks": self = .banks(try c.decode([BankLine].self, forKey: .banks).map(\.entry))
		case "accounts": self = .accounts(try c.decode([AccountLine].self, forKey: .accounts).map(\.account))
		case "result": self = .result(account: try c.decode(String.self, forKey: .account), Result { try AccountResult(from: decoder) })
		case "accountFailed": self = .accountFailed(account: try c.decode(String.self, forKey: .account), try HelperError(from: decoder))
		case "state": self = .state(try c.decode(Data.self, forKey: .data))
		case "failed": self = .failed(try HelperError(from: decoder))
		case let type: throw DecodingError.dataCorruptedError(forKey: .type, in: c, debugDescription: "unknown message \(type)")
		}
	}
}

/// A bank of the bank directory in the banks message.
private struct BankLine: Decodable {
	let code: String
	let name: String
	let city: String?
	let bic: String?
	let url: String?

	var entry: BankDirectory.Entry {
		BankDirectory.Entry(code: code, city: city ?? "", bank: FinTSBank(name: name, bic: bic, url: url.flatMap { URL(string: $0) }))
	}
}

/// A request of hbci4java for the user.
struct Ask: Decodable {
	let kind: String
	let purpose: String?
	let prompt: String?
	/// The name of the TAN method of an approval, for example "SecureGo plus".
	let method: String?
	let rejected: HelperError?
	/// The PIN rules of the bank parameters, on a PIN request.
	let rules: Rules?
	/// The methods to choose from, and on a challenge the methods that the user can change to.
	let methods: [Method]?
	/// The ID of the method of a challenge.
	let current: String?
	let media: [String]?
	let image: Data?
	/// The flicker code as hbci4java renders it from the HHDuc of the bank.
	let flicker: String?
	/// The challenge comes while the refresh asks for the full history of an account, so the bank may ask
	/// for it because of transactions older than 90 days.
	let history: Bool?

	struct Rules: Decodable {
		let minLength: Int?
		let maxLength: Int?
	}

	struct Method: Decodable {
		let id: String
		let name: String
		/// The method needs a TAN medium.
		let medium: Bool?
		/// "sms", "push", or "qr", which the helper reads from the bank parameters of the method.
		let delivery: String?

		var method: TANMethod {
			let delivery: TANMethod.Delivery = switch delivery {
			case "sms": .smsCode
			case "push": .pushNotification
			case "qr": .qrCode
			default: .tan
			}
			return TANMethod(id: id, name: name, needsMedium: medium ?? false, delivery: delivery)
		}
	}

	/// The request for the session. A PIN request after a rejection carries the answer of the bank, so
	/// the broker never answers it from memory and shows the sheet again. A code of a blocked access
	/// stops the run, and the app never asks for its PIN again (task 1.24). A flicker code that does not
	/// read fails the access, because the user cannot produce a TAN without it. `server` is the FinTS
	/// address of the bank, whose rules some requests follow.
	func request(server: URL?) throws -> UserRequest {
		if kind == "pin" {
			let rules = CooperativeBanks.pinRules(minLength: rules?.minLength, maxLength: rules?.maxLength, server: server)
			guard let rejected else { return .pin(PINRequest(rules: rules)) }
			if case let .accessBlocked(message) = rejected.failure { throw SyncFailure.accessBlocked(message) }
			return .pin(PINRequest(rejected: rejected.message, rules: rules))
		}
		let offered = (methods ?? []).map(\.method)
		let challenge: Challenge
		switch kind {
		case "tanMethod": return secondFactor(.chooseTANMethod(offered, current: nil), methods: [])
		case "tanMedium":
			let media = media ?? []
			challenge = media.isEmpty && FinTSServer.isApoBank(server) ? .nameTANMedium(.apoTANDevice) : .chooseTANMedium(media)
		case "tan":
			if let flicker {
				guard let code = FlickerCode(hex: flicker) else { throw SyncFailure.invalidChallenge }
				challenge = .flickerCode(prompt: prompt ?? "", code: code)
			} else {
				challenge = .enterTAN(prompt: prompt ?? "", image: image.map(ChallengeImage.init))
			}
		case "approve": challenge = .approveInApp(prompt: prompt ?? "", app: method, image: nil, step: nil)
		default: throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "unknown request \(kind)"))
		}
		return secondFactor(challenge, methods: offered)
	}

	private func secondFactor(_ challenge: Challenge, methods: [TANMethod]) -> UserRequest {
		.secondFactor(SecondFactorRequest(purpose: purpose == "login" ? .login : .download, system: .fintsServer, challenge: challenge, methods: methods,
			method: current, olderTransactions: history == true))
	}
}

/// An error of the bank, or of the helper with `kind` "network", "certificate", "unsupported", "invalidChallenge",
/// "noTANMethod", or "approvalDeclined".
///
/// The codes are those of the FinTS return codes of the Deutsche Kreditwirtschaft
/// (FinTS_Rueckmeldungscodes_2019-07-22): 9942 and 9340 a wrong PIN, 9930 a blocked PIN, 9933 a blocked
/// access, 3938 an access that is blocked until the PIN block is lifted, 9941 and 9948 an invalid
/// TAN, and 9943 a TAN that was used before. 9931 means "Sperrung des Kontos nach Fehlversuchen", a block, but
/// Sparkassen send it also for a wrong login name or PIN, "Anmeldename oder PIN ist falsch". So 9931 counts as a
/// block only when its text reports a block that happened (`reportsBlock`), and as a wrong PIN otherwise, also when
/// the text only warns of a block to come: the app forgets the PIN and sends it never again on its own, and the next
/// PIN sheet shows the warning.
/// 3931 names a blocked PIN or a TAN generator that needs a synchronization, so it keeps the text of the bank.
/// 9951, a two-step dialog that timed out, and 9955, "Ein-Schritt-TAN-Verfahren nicht zugelassen", mean a
/// declined approval or a missing TAN method only with the evidence of the helper, which then sends the kind.
struct HelperError: Decodable, Equatable {
	let kind: String?
	let code: String?
	let text: String

	var message: BankMessage { BankMessage(code: code, text: text) }

	/// Whether the text of a 9931 reports a block that happened: it has a phrase of a finished block and no phrase of
	/// attempts that remain, of a block to come, or of a denial. Every other text is a wrong PIN, which the project owner
	/// chose as the safe side: at worst a blocked access gets one more PIN sheet, and the app never sends a PIN on its own.
	static func reportsBlock(_ text: String) -> Bool {
		func has(_ patterns: [String]) -> Bool {
			patterns.contains { text.range(of: $0, options: [.regularExpression, .caseInsensitive]) != nil }
		}
		return has(finishedBlocks) && !has(noFinishedBlock)
	}

	/// The phrases of a block that happened: the block itself, or the access, the PIN, or the account with at most four
	/// words before "gesperrt" or "blockiert", as in "Zugang wegen ungültiger PIN gesperrt" or "Ihr Zugang wurde gesperrt".
	private static let finishedBlocks = [
		#"teilnehmersperre"#,
		#"sperre (wurde )?durchgeführt"#,
		#"sperrung (ist|wurde) (erfolgt|durchgeführt)"#,
		#"sperrung (des|der) (kontos|zugangs|pin|teilnehmers)"#,
		#"\b(zugang|pin|konto|kennung|teilnehmer)(\s+[\p{L}\d]+){0,4}\s+(gesperrt|blockiert)\b"#,
	]

	/// The phrases of attempts that remain, of a block to come, or of a denial, which make any text a wrong PIN.
	private static let noFinishedBlock = [
		#"noch (\d+|ein|einen|zwei|drei) (fehl)?versuch"#,
		#"verbleibend"#,
		#"\b(weitere[nr]?|nächste[nrm]?|erneute[nrm]?) (falsche[nrm]? )?(fehl|eingabe|versuch)"#,
		#"bis zur sperr"#,
		#"(führt|führen) zur sperr"#,
		#"\b(wird|werden|droht|drohen)\b[^.!?]*(gesperrt|blockiert|\bsperr)"#,
		#"nicht (gesperrt|blockiert)"#,
		#"\bkein\p{L}* (gesperrt|sperr)"#,
	]

	var failure: SyncFailure {
		switch (kind, code) {
		case ("network", _), ("certificate", _): .network(text)
		case ("unsupported", _): .unsupported(text)
		case ("invalidChallenge", _): .invalidChallenge
		case ("noTANMethod", _): .noTANMethod(message)
		case ("approvalDeclined", _): .approvalDeclined(message)
		case (_, "9078"): .notRegistered
		case (_, "9931"): Self.reportsBlock(text) ? .accessBlocked(message) : .pinRejected(message)
		case (_, "9942"), (_, "9340"): .pinRejected(message)
		case (_, "9930"), (_, "9933"), (_, "3938"): .accessBlocked(message)
		case (_, "9941"), (_, "9943"), (_, "9948"): .tanRejected(message)
		default: .bank(message)
		}
	}
}

/// The balance and the transactions of one account. A failed request of the two is in `errors`. A
/// securities account has no transactions, and its balance is the value of its holdings.
struct AccountResult: Decodable {
	let balance: Balance?
	let transactions: Transactions?
	let errors: [HelperError]
	/// The balance is the value of a securities account.
	let securities: Bool?
	/// The positions of a securities account. Nil when the answer of the bank had no statement.
	let holdings: [Position]?

	struct Balance: Decodable {
		let amount: String
		let currency: String
		let date: String?
	}

	struct Transactions: Decodable {
		let from: String?
		let rows: [Row]
	}

	struct Row: Decodable {
		/// Nil when hbci4java read no date, as for a CAMT entry with a date and time only.
		let booked: String?
		let value: String?
		let amount: String
		let currency: String?
		let name: String?
		let iban: String?
		let bic: String?
		let purpose: String?
		let endToEnd: String?
		let mandate: String?
		let creditor: String?
		let bookingText: String?
		let pending: Bool
	}

	/// The outcome of the account, and the error of a balance request that failed beside transactions
	/// that worked. The error of a transaction request that failed beside a balance is the error of the account.
	/// The error that the account fails with when its transactions are missing: a rejection of the PIN
	/// or a block first, because it decides about the PIN, and otherwise the first error. The session
	/// learns about the PIN from this error too, so the account always shows why the PIN went.
	var shownError: HelperError? {
		guard transactions == nil else { return nil }
		return errors.first { $0.failure.rejectsPIN } ?? errors.first
	}

	func outcome(of account: AccountRequest) throws -> (AccountOutcome, [BankMessage]) {
		guard balance != nil || transactions != nil else {
			return (.failed(shownError?.failure ?? .bank(BankMessage(text: String(localized: "The bank sent nothing for this account.")))), [])
		}
		let money = try balance.map { try Self.money($0.amount, $0.currency) }
		let fetched = try transactions.map { t in
			FetchedTransactions(rows: try t.rows.map { try $0.transaction(of: account) }, from: try t.from.map(Self.day))
		}
		let transactionFailure = shownError?.failure
		// Older transactions may be missing when the answer starts after the last successful fetch: the 90 days of a
		// normal refresh after a long pause, or a canceled challenge for older transactions. The start that the
		// request asked for is no measure, because it reaches 14 days or a pending row back. A mark from before
		// is the account's own, and the merge keeps it until a full history.
		let missesOlder = fetched?.from.map { from in account.lastFetched.map { $0 < from } ?? true } ?? false
		let result = RefreshResult(balance: money, balanceDate: try balance?.date.map { try Self.day($0).date() }, transactions: fetched,
			isComplete: transactions != nil && transactions?.from == nil, transactionFailure: transactionFailure, isPortfolio: securities == true,
			holdings: try holdings?.map { try $0.holding(of: account) }, missesOlder: missesOlder)
		let notices = errors.map { BankMessage(code: $0.code, text: $0.text, accountName: account.name) }
		return (.fetched(result), transactionFailure == nil ? notices : [])
	}

	/// An amount above `Money.maxMinorUnits` fails the account, so that no sum of stored amounts can overflow.
	static func money(_ amount: String, _ currency: String) throws -> Money {
		guard let money = Money(fitting: try decimal(amount), currency: currency) else { throw HelperFailure.tooLarge }
		return money
	}

	/// A plain decimal text of the helper, as `BigDecimal.toPlainString` writes it, with every decimal place. The
	/// whole text must match, because `Decimal(string:)` alone reads the start of "12.3.4" as 12.3 and "-" as 0.
	static func decimal(_ text: String) throws -> Decimal {
		guard text.wholeMatch(of: /-?[0-9]+(\.[0-9]+)?/) != nil, let decimal = Decimal(string: text, locale: Locale(identifier: "en_US_POSIX"))
		else { throw HelperFailure.unreadable }
		return decimal
	}

	static func day(_ text: String) throws -> Day {
		guard let day = Day(string: text) else { throw HelperFailure.unreadable }
		return day
	}
}

extension AccountResult {
	/// A position of MT535 as the helper sends it. Amounts are plain decimal text, and a price or purchase
	/// price in "%" is a percentage of the nominal amount.
	struct Position: Decodable {
		let name: String?
		let isin: String?
		let wkn: String?
		let quantity: String?
		let nominal: Bool?
		/// The currency of the security.
		let currency: String?
		let price: Amount?
		let value: Amount?
		let accrued: Amount?
		let purchase: Amount?
		let rate: Rate?

		struct Amount: Decodable {
			let amount: String
			let currency: String?
			let day: String?
		}

		struct Rate: Decodable {
			let base: String
			let quoted: String
			let rate: String
		}

		/// The position in the app. Its name is the name of the bank, or else its ISIN or WKN. A nominal amount is in
		/// the currency of the security. Without one its currency stays unknown: the value of the bank may already be
		/// converted into another currency, so it does not tell the currency of the nominal amount.
		func holding(of account: AccountRequest) throws -> Holding {
			guard let quantity else { throw HelperFailure.unreadable }
			let value = try value.map { try AccountResult.money($0.amount, $0.currency ?? account.currency) }
			let exchangeRate = try rate.map { ExchangeRate(base: $0.base, quoted: $0.quoted, rate: try AccountResult.decimal($0.rate)) }
			let holding = Holding(accountID: account.accountID, security: Security(name: name ?? isin ?? wkn ?? "", isin: isin, securityNumber: wkn),
				quantity: try AccountResult.decimal(quantity), isNominal: nominal == true, nominalCurrency: nominal == true ? currency : nil,
				quote: try price.map(Self.quote), marketValue: value, accruedInterest: try accrued.map { try AccountResult.money($0.amount, $0.currency ?? account.currency) },
				purchasePrice: try purchase.map(Self.quote), exchangeRate: exchangeRate)
			// A quantity times a price beyond the limit fails the account, as an amount beyond it does.
			guard holding.amountsFit(in: account.currency) else { throw HelperFailure.tooLarge }
			return holding
		}

		private static func quote(_ a: Amount) throws -> Quote {
			Quote(amount: try AccountResult.decimal(a.amount), currency: a.currency == "%" ? nil : a.currency, day: try a.day.map(AccountResult.day))
		}
	}
}

extension AccountResult.Row {
	func transaction(of account: AccountRequest) throws -> Transaction {
		guard let booked else { throw HelperFailure.noBookingDate }
		let money = try AccountResult.money(amount, currency ?? account.currency)
		return Transaction(accountID: account.accountID, bookingDate: try AccountResult.day(booked), valueDate: try value.map(AccountResult.day), amountMinor: money.minorUnits,
			currency: money.currency, name: name ?? "", purpose: purpose ?? "", counterpartyIBAN: iban, counterpartyBIC: bic, bookingText: bookingText,
			endToEndReference: endToEnd, mandateReference: mandate, creditorID: creditor, isPending: pending)
	}
}

private struct AccountLine: Decodable {
	let number: String
	let subnumber: String?
	let iban: String?
	let bic: String?
	let product: String?
	let kind: String?
	let owner: String?
	let currency: String?
	/// The helper knows a securities account also by its jobs, when the bank gives it no securities account type.
	let securities: Bool?

	var account: FinTSAccount {
		FinTSAccount(number: number, subnumber: subnumber, iban: iban, bic: bic, productName: product,
			kind: securities == true ? .portfolio : FinTSAccount.kind(of: kind), owner: owner, currency: currency ?? "EUR")
	}
}

/// Failures of the helper itself, as the app shows them.
enum HelperFailure {
	static let unreadable = SyncFailure.network(String(localized: "The FinTS helper sent a line that Moneten cannot read."))
	static let noAnswer = SyncFailure.network(String(localized: "The FinTS helper ended without an answer."))
	static let noProductID = SyncFailure.unsupported(String(localized: "This build of Moneten has no FinTS product ID, and banks accept only registered apps."))
	static let insecure = SyncFailure.unsupported(String(localized: "The bank offers no encrypted FinTS address."))
	static let noBookingDate = SyncFailure.unsupported(String(localized: "The bank sent a transaction without a booking date, so nothing of this account was stored."))
	static let tooLarge = SyncFailure.unsupported(String(localized: "The bank sent an amount that is too large, so nothing of this account was stored."))
	static let clash = SyncFailure.unsupported(String(localized: "Two accounts of this access are the same account at the bank."))
	static let damaged = SyncFailure.unsupported(String(localized: "The files of the FinTS helper do not match the signature of Moneten. Download Moneten again and replace this copy."))
	static let timeout = SyncFailure.network(String(localized: "The connection to the FinTS server of the bank timed out. Try again later."))
	static let lineTooLong = SyncFailure.network(String(localized: "The FinTS helper sent a message larger than \(HelperProcess.lineLimit >> 20) MiB, which Moneten does not read."))

	static func stopped(_ status: Int32, signal: Bool) -> SyncFailure {
		.network(signal ? String(localized: "The FinTS helper stopped unexpectedly (signal \(status)).")
			: String(localized: "The FinTS helper stopped unexpectedly (status \(status))."))
	}

	static func notStarted(_ error: Error) -> SyncFailure {
		.network(String(localized: "The FinTS helper could not start: \(error.localizedDescription)"))
	}
}
