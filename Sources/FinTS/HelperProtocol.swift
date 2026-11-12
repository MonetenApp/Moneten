import Domain
import Foundation

/// The first line to the helper. Tools/FinTSHelper/FinTSHelper.java describes the protocol.
struct Command: Encodable {
	let type: String
	let bankCode: String
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

struct Answer: Encodable {
	var type = "answer"
	let id: Int
	let value: String
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
	case bank(FinTSBank?)
	case accounts([FinTSAccount])
	/// A result that does not read fails only its account.
	case result(account: String, Result<AccountResult, any Error>)
	case accountFailed(account: String, HelperError)
	case state(Data)
	case failed(HelperError)

	private enum Key: String, CodingKey {
		case type, id, done, of, text, name, bic, url, accounts, account, data, host, chain
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
		case "bank":
			let name = try c.decodeIfPresent(String.self, forKey: .name)
			let bic = try c.decodeIfPresent(String.self, forKey: .bic)
			let url = try c.decodeIfPresent(String.self, forKey: .url).flatMap { URL(string: $0) }
			self = .bank(name.map { FinTSBank(name: $0, bic: bic, url: url) })
		case "accounts": self = .accounts(try c.decode([AccountLine].self, forKey: .accounts).map(\.account))
		case "result": self = .result(account: try c.decode(String.self, forKey: .account), Result { try AccountResult(from: decoder) })
		case "accountFailed": self = .accountFailed(account: try c.decode(String.self, forKey: .account), try HelperError(from: decoder))
		case "state": self = .state(try c.decode(Data.self, forKey: .data))
		case "failed": self = .failed(try HelperError(from: decoder))
		case let type: throw DecodingError.dataCorruptedError(forKey: .type, in: c, debugDescription: "unknown message \(type)")
		}
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
	let methods: [Method]?
	let media: [String]?
	let image: Data?
	/// The flicker code as hbci4java renders it from the HHDuc of the bank.
	let flicker: String?

	struct Method: Decodable {
		let id: String
		let name: String
	}

	/// The request for the session. A PIN request after a rejection carries the answer of the bank, so
	/// the broker never answers it from memory and shows the sheet again. 9930 means a blocked access,
	/// and the app never asks for its PIN again (task 1.24).
	func request() throws -> UserRequest {
		if kind == "pin" {
			guard let rejected else { return .pin(PINRequest()) }
			if rejected.code == "9930" { throw SyncFailure.accessBlocked(rejected.message) }
			return .pin(PINRequest(rejected: rejected.message))
		}
		let challenge: Challenge
		switch kind {
		case "tanMethod": challenge = .chooseTANMethod((methods ?? []).map { TANMethod(id: $0.id, name: $0.name) }, current: nil)
		case "tanMedium": challenge = .chooseTANMedium(media ?? [])
		case "tan":
			if let code = flicker.flatMap(FlickerCode.init(hex:)) {
				challenge = .flickerCode(prompt: prompt ?? "", code: code)
			} else {
				challenge = .enterTAN(prompt: prompt ?? "", image: image.map(ChallengeImage.init))
			}
		case "approve": challenge = .approveInApp(prompt: prompt ?? "", app: method, image: nil, step: nil)
		default: throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "unknown request \(kind)"))
		}
		return .secondFactor(SecondFactorRequest(purpose: purpose == "login" ? .login : .download, system: .fintsServer, challenge: challenge))
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
		case (_, "9078"): .notRegistered
		// Sparkassen send 9931 for a wrong login name or PIN, so only 9930 counts as blocked.
		case (_, "9942"), (_, "9340"), (_, "9931"): .pinRejected(message)
		case (_, "9930"): .accessBlocked(message)
		default: .bank(message)
		}
	}
}

/// The balance and the transactions of one account. A failed request of the two is in `errors`.
struct AccountResult: Decodable {
	let balance: Balance?
	let transactions: Transactions?
	let errors: [HelperError]

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

	/// The outcome of the account and the errors of a request that failed beside one that worked.
	func outcome(of accountID: UUID) throws -> (AccountOutcome, [BankMessage]) {
		guard balance != nil || transactions != nil else {
			return (.failed(errors.first?.failure ?? .bank(BankMessage(text: "The bank sent nothing for this account."))), [])
		}
		let money = try balance.map { try Self.money($0.amount, $0.currency) }
		let fetched = try transactions.map { t in
			FetchedTransactions(rows: try t.rows.map { try $0.transaction(of: accountID) }, from: try t.from.map(Self.day))
		}
		let result = RefreshResult(balance: money, balanceDate: try balance?.date.map { try Self.day($0).date() }, transactions: fetched,
			isComplete: transactions != nil && transactions?.from == nil)
		return (.fetched(result), errors.map(\.message))
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
	func transaction(of accountID: UUID) throws -> Transaction {
		guard let booked else { throw HelperFailure.noBookingDate }
		let money = try AccountResult.money(amount, currency ?? "EUR")
		return Transaction(accountID: accountID, bookingDate: try AccountResult.day(booked), valueDate: try value.map(AccountResult.day), amountMinor: money.minorUnits,
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

	var account: FinTSAccount {
		FinTSAccount(number: number, subnumber: subnumber, iban: iban, bic: bic, productName: product, kind: FinTSAccount.kind(of: kind), owner: owner,
			currency: currency ?? "EUR")
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
