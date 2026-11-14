/// A notice that a bank sent with a refresh, such as planned maintenance, for the window "Notice". A notice
/// about one account, such as a balance that the bank could not send, has the account and the code of the bank.
public struct BankNotice: Hashable, Sendable {
	public let bankName: String
	public let accountName: String?
	public let code: String?
	public let text: String

	init(bankName: String, accountName: String? = nil, code: String? = nil, text: String) {
		self.bankName = bankName
		self.accountName = accountName
		self.code = code
		self.text = text
	}
}

/// The notices that wait for the window "Notice", the oldest first.
public struct BankNotices: Sendable {
	public private(set) var waiting: [BankNotice] = []
	/// Every notice that waited or that the setup showed. A bank can send the same notice in each dialog, and it shows once.
	private var known: Set<BankNotice> = []
	/// A notice came that the window has not brought forward yet. An automatic refresh opens no window,
	/// so its notices wait for the user.
	private var news = false

	public init() {}

	public mutating func add(_ messages: [BankMessage], from bankName: String) {
		for notice in Self.notices(messages, from: bankName) {
			if known.insert(notice).inserted {
				waiting.append(notice)
				news = true
			}
		}
	}

	/// The notices that the assistant "Add Account" showed after the login. They never wait.
	public mutating func markShown(_ messages: [BankMessage], from bankName: String) {
		known.formUnion(Self.notices(messages, from: bankName))
	}

	/// The user is there: a refresh that the user started ended, or the main window came forward. Returns
	/// whether the window "Notice" comes forward, which it does once for each new notice.
	public mutating func bringForward() -> Bool {
		defer { news = false }
		return news
	}

	private static func notices(_ messages: [BankMessage], from bankName: String) -> [BankNotice] {
		messages.map { BankNotice(bankName: bankName, accountName: $0.accountName, code: $0.code, text: $0.text) }
	}

	/// The user closed the window, which showed every waiting notice.
	public mutating func dismiss() {
		waiting = []
		news = false
	}
}
