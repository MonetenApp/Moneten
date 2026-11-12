import CLua
import Foundation

/// The global functions of the Web Banking API that the app calls. Payment functions are not part of
/// it, so no command can call them (ADR 0008, ADR 0015 decision 20).
public enum EntryPoint: String, Sendable, Codable, CaseIterable {
	case supportsBank = "SupportsBank"
	case initializeSession = "InitializeSession"
	case initializeSession2 = "InitializeSession2"
	case listAccounts = "ListAccounts"
	case refreshAccount = "RefreshAccount"
	case fetchStatements = "FetchStatements"
	case endSession = "EndSession"
}

/// The value of `protocol` in `SupportsBank` and the login functions.
public enum BankProtocol: String, Sendable, Codable {
	case webBanking = "ProtocolWebBanking"
	case finTS = "ProtocolFinTS"
}

/// The value of `session` in `InitializeSession2`. The app never passes "payment".
public enum SessionReason: String, Sendable, Codable {
	case refresh = "refresh"
	case newAccount = "new account"
	case statement = "statement"
	case tanMedia = "tan media"
}

/// One call of an entry point with its arguments, as the app sends it to the host process.
public enum EntryCall: Sendable, Codable, Equatable {
	case supportsBank(BankProtocol, bankCode: String)
	case initializeSession(BankProtocol, bankCode: String, username: String, customer: String, password: String, credential: String)
	case initializeSession2(BankProtocol, bankCode: String, step: Int, credentials: [LuaValue], interactive: Bool, reason: SessionReason)
	case listAccounts(known: [LuaValue])
	/// `known` holds the stored booked transactions of the account by `transactionId`, for `isKnownTransactionId`.
	case refreshAccount(account: LuaValue, since: Int64, known: [String: LuaValue], step: Int, credentials: [LuaValue], interactive: Bool)
	case endSession
	/// A global function without arguments, for the debug harness and the `ext` tool.
	case function(String)
}

enum EntryPoints {
	/// The globals of the API that only name a value. A script compares them, so each has its own text.
	static let constants: [String: String] = {
		var constants = ["LoginFailed": "LoginFailed"]
		for value in [BankProtocol.webBanking, .finTS] { constants[value.rawValue] = value.rawValue }
		for type in AccountType.allCases { constants[type.rawValue] = type.rawValue }
		return constants
	}()

	static func call(_ entry: EntryCall, in session: HostSession, lua: LuaState) throws(ScriptError) -> LuaValue {
		switch entry {
		case let .supportsBank(proto, bankCode):
			let answer = try lua.call(EntryPoint.supportsBank.rawValue, [.value(.string(proto.rawValue)), .value(.string(bankCode))])
			if case .string = answer {
				lua.stack.push(answer)
				lua.stack.setGlobal("url")
			}
			return answer
		case let .initializeSession(proto, bankCode, username, customer, password, credential):
			return try lua.call(EntryPoint.initializeSession.rawValue, [proto.rawValue, bankCode, username, customer, password, credential].map { .value(.string($0)) })
		case let .initializeSession2(proto, bankCode, step, credentials, interactive, reason):
			return try lua.call(EntryPoint.initializeSession2.rawValue, [.value(.string(proto.rawValue)), .value(.string(bankCode)), .value(.integer(Int64(step))),
				.value(.array(credentials)), .value(.boolean(interactive)), .value(.array([])), .value(.string(reason.rawValue))])
		case let .listAccounts(known):
			return try lua.call(EntryPoint.listAccounts.rawValue, [.value(.array(known))])
		case let .refreshAccount(account, since, known, step, credentials, interactive):
			session.knownTransactions = known
			defer { session.knownTransactions = [:] }
			return try lua.call(EntryPoint.refreshAccount.rawValue, [.value(account), .value(.integer(since)), .function(isKnownTransactionId),
				.value(.integer(Int64(step))), .value(.array(credentials)), .value(.boolean(interactive))])
		case .endSession:
			return try lua.call(EntryPoint.endSession.rawValue)
		case let .function(name):
			return try lua.call(name)
		}
	}

	/// `isKnownTransactionId(transactionId)`: the stored transaction, or `nil` when the identifier is
	/// empty, unknown, known only for a pending transaction, or stored more than once in the account.
	/// The app leaves the last three out of `known`.
	private static let isKnownTransactionId: clua_Function = { L in
		let stack = LuaStack(L!)
		let session = HostSession.current(L)
		guard lua_type(L, 1) == LUA_TSTRING, let stored = session.knownTransactions[stack.string(at: 1)] else {
			lua_pushnil(L)
			return 1
		}
		stack.push(stored)
		return 1
	}
}

/// The values of `type` in an account table.
public enum AccountType: String, Sendable, Codable, CaseIterable {
	case giro = "AccountTypeGiro"
	case savings = "AccountTypeSavings"
	case fixedTermDeposit = "AccountTypeFixedTermDeposit"
	case loan = "AccountTypeLoan"
	case creditCard = "AccountTypeCreditCard"
	case portfolio = "AccountTypePortfolio"
	case other = "AccountTypeOther"
}
