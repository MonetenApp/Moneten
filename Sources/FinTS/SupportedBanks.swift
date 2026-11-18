import Foundation

/// "Supported Banks": the banks and services that the app reaches, with the access method of each
/// ("List of supported banks"). It reads the bank directory and the services of the installed extensions.
public struct SupportedBanks: Sendable {
	/// The access method of every bank of the bank directory that has a FinTS address.
	public static var fintsMethod: String { String(localized: "FinTS/HBCI with TAN method") }

	/// A service that an installed extension declares. Its access method is the name of the extension.
	public struct Service: Sendable, Equatable, Identifiable {
		public let name: String
		public let extensionName: String

		public var id: String { extensionName + "\u{1}" + name }

		public init(name: String, extensionName: String) {
			self.name = name
			self.extensionName = extensionName
		}
	}

	let directory: BankDirectory?
	let services: [Service]

	/// `services` holds the services of the extensions that may run, as "Other" in "Add Account" lists them.
	/// `directory` is nil when the bank directory did not load, and the list then has only the services.
	public init(directory: BankDirectory?, services: [Service]) {
		self.directory = directory
		self.services = services.sorted { a, b in
			let order = a.name.localizedStandardCompare(b.name)
			return order == .orderedSame ? a.extensionName.localizedStandardCompare(b.extensionName) == .orderedAscending : order == .orderedAscending
		}
	}

	/// The note of a bank in the list: the note of a merged bank, then what the bank requires or offers before the first
	/// login, then the help of the login name. The note before the first login comes before the help, so that a customer
	/// of DEGIRO sees that flatexDEGIRO Bank serves only flatex accounts with FinTS.
	public static func note(of bank: BankDirectory.Entry) -> String? {
		bank.mergerNote ?? bank.loginNote ?? bank.loginHint?.help
	}

	/// The services and banks that match every word of `query` in their names, and for a bank also in its
	/// place or Bankleitzahl, as the first step of "Add Account" finds them. An empty query lists all.
	public func matching(_ query: String) -> (services: [Service], banks: [BankDirectory.Entry]) {
		let terms = query.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map { BankDirectory.spellings(String($0)) }
		let services = services.filter { service in
			let text = [service.name, service.extensionName].flatMap { BankDirectory.spellings($0) }
			return terms.allSatisfy { spellings in spellings.contains { term in text.contains { $0.contains(term) } } }
		}
		return (services, directory?.reachable(query) ?? [])
	}
}
