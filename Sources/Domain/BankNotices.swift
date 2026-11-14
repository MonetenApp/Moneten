/// A notice that a bank sent with a refresh, such as planned maintenance, for the window "Notice".
public struct BankNotice: Hashable, Sendable {
	public let bankName: String
	public let text: String
}

/// The notices that wait for the window "Notice", the oldest first.
public struct BankNotices: Sendable {
	public private(set) var waiting: [BankNotice] = []
	/// Every notice that waited. A bank can send the same notice in each dialog, and it shows once.
	private var known: Set<BankNotice> = []

	public init() {}

	public mutating func add(_ messages: [BankMessage], from bankName: String) {
		for message in messages {
			let notice = BankNotice(bankName: bankName, text: message.text)
			if known.insert(notice).inserted { waiting.append(notice) }
		}
	}

	/// The user closed the window, which showed every waiting notice.
	public mutating func dismiss() {
		waiting = []
	}
}
