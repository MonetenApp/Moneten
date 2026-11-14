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
struct Answer: Encodable {
	var type = "answer"
	let id: Int
	var value: String?
	var method: String?
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
				_ = try ask.request()
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
	/// the broker never answers it from memory and shows the sheet again. 9930 means a blocked access,
	/// and the app never asks for its PIN again (task 1.24). A flicker code that does not read fails the
	/// access, because the user cannot produce a TAN without it.
	func request() throws -> UserRequest {
		if kind == "pin" {
			let rules = PINRules(minLength: rules?.minLength, maxLength: rules?.maxLength)
			guard let rejected else { return .pin(PINRequest(rules: rules)) }
			if rejected.code == "9930" { throw SyncFailure.accessBlocked(rejected.message) }
			return .pin(PINRequest(rejected: rejected.message, rules: rules))
		}
		let offered = (methods ?? []).map(\.method)
		let challenge: Challenge
		switch kind {
		case "tanMethod": return secondFactor(.chooseTANMethod(offered, current: nil), methods: [])
		case "tanMedium": challenge = .chooseTANMedium(media ?? [])
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
			method: current))
	}
}

/// An error of the bank, or of the helper with `kind` "network", "certificate", or "unsupported".
struct HelperError: Decodable, Equatable {
	let kind: String?
	let code: String?
	let text: String

	var message: BankMessage { BankMessage(code: code, text: text) }

	var failure: SyncFailure {
		switch (kind, code) {
		case ("network", _), ("certificate", _): .network(text)
		case ("unsupported", _): .unsupported(text)
		case ("invalidChallenge", _): .invalidChallenge
		case (_, "9078"): .notRegistered
		// Sparkassen send 9931 for a wrong login name or PIN, so only 9930 counts as blocked.
		case (_, "9942"), (_, "9340"), (_, "9931"): .pinRejected(message)
		case (_, "9930"): .accessBlocked(message)
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
			return (.failed(shownError?.failure ?? .bank(BankMessage(text: "The bank sent nothing for this account."))), [])
		}
		let money = try balance.map { try Self.money($0.amount, $0.currency) }
		let fetched = try transactions.map { t in
			FetchedTransactions(rows: try t.rows.map { try $0.transaction(of: account) }, from: try t.from.map(Self.day))
		}
		let transactionFailure = shownError?.failure
		let result = RefreshResult(balance: money, balanceDate: try balance?.date.map { try Self.day($0).date() }, transactions: fetched,
			isComplete: transactions != nil && transactions?.from == nil, transactionFailure: transactionFailure, isPortfolio: securities == true)
		return (.fetched(result), transactionFailure == nil ? errors.map(\.message) : [])
	}

	static func money(_ amount: String, _ currency: String) throws -> Money {
		guard let decimal = Decimal(string: amount, locale: Locale(identifier: "en_US_POSIX")) else { throw HelperFailure.unreadable }
		return Money(decimal, currency: currency)
	}

	static func day(_ text: String) throws -> Day {
		guard let day = Day(string: text) else { throw HelperFailure.unreadable }
		return day
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
	static let unreadable = SyncFailure.network("The FinTS helper sent a line that Moneten cannot read.")
	static let noAnswer = SyncFailure.network("The FinTS helper ended without an answer.")
	static let noProductID = SyncFailure.unsupported("This build of Moneten has no FinTS product ID, and banks accept only registered apps.")
	static let insecure = SyncFailure.unsupported("The bank offers no encrypted FinTS address.")
	static let noBookingDate = SyncFailure.unsupported("The bank sent a transaction without a booking date, so nothing of this account was stored.")
	static let clash = SyncFailure.unsupported("Two accounts of this access are the same account at the bank.")
	static let timeout = SyncFailure.network("The connection to the FinTS server of the bank timed out. Try again later.")

	static func stopped(_ status: Int32, signal: Bool) -> SyncFailure {
		.network("The FinTS helper stopped unexpectedly (\(signal ? "signal" : "status") \(status)).")
	}

	static func notStarted(_ error: Error) -> SyncFailure {
		.network("The FinTS helper could not start: \(error.localizedDescription)")
	}
}
