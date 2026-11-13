import Domain
import Foundation
import Observation

/// The bank of the first step of "Add Account", found by name, Bankleitzahl, or IBAN. The result
/// always belongs to the entry of this moment: a new entry drops the result of the last one, and a
/// lookup that ends after the entry changed changes nothing. So the login never goes to the bank of
/// an earlier entry.
@MainActor
@Observable
public final class BankLookup {
	public enum State: Equatable {
		case none
		case searching
		/// The banks that match a name or the start of a Bankleitzahl, best first, for the user to choose.
		case matches([BankDirectory.Entry])
		case found(BankDirectory.Entry)
		case failed(String)
	}

	public var entry = "" {
		didSet { if entry != oldValue { state = .none } }
	}
	public private(set) var state = State.none
	@ObservationIgnored private let load: @Sendable () async throws -> BankDirectory
	@ObservationIgnored private var directory: BankDirectory?
	@ObservationIgnored private var loading: Task<BankDirectory, any Error>?

	/// `load` returns the bank directory. The lookup asks for it once and keeps it.
	public init(load: @escaping @Sendable () async throws -> BankDirectory) {
		self.load = load
	}

	/// The bank of the entry, once the lookup found a bank with a FinTS address.
	public var bank: BankDirectory.Entry? {
		if case let .found(bank) = state { bank } else { nil }
	}

	/// Takes a bank of the matches. The entry becomes its Bankleitzahl, so it names the bank on its own.
	public func choose(_ bank: BankDirectory.Entry) {
		entry = bank.code
		state = Self.usable(bank)
	}

	/// Looks up the bank of the entry. While the user types, `showingErrors` is false, so that half an
	/// IBAN is not an error.
	public func lookUp(showingErrors: Bool) async {
		let entry = entry
		let text = entry.filter { !$0.isWhitespace }
		let isSearch = text.allSatisfy(\.isNumber) ? !text.isEmpty && text.count < 8 : !Self.startsLikeIBAN(text)
		var code: String?
		if !isSearch {
			do {
				code = try BankEntry.bankCode(of: entry)
			} catch {
				state = showingErrors ? .failed(error.message) : .none
				return
			}
		}
		let result: State
		do {
			let directory = try await directory()
			if let code {
				result = directory.bank(code: code).map(Self.usable) ?? .failed("The Bankleitzahl is invalid.")
			} else {
				// A search of the whole directory takes about 10 ms, too long for the main thread. The start of
				// a Bankleitzahl is one word also when it is typed in groups, such as "760 30".
				let query = text.allSatisfy(\.isNumber) ? text : entry
				let matches = await Task.detached(priority: .userInitiated) { directory.search(query) }.value
				result = matches.isEmpty ? .failed("No bank matches “\(entry.trimmingCharacters(in: .whitespaces))”.") : .matches(matches)
			}
		} catch {
			result = .failed((error as? SyncFailure)?.message ?? error.localizedDescription)
		}
		guard entry == self.entry else { return }
		state = result
	}

	private func directory() async throws -> BankDirectory {
		if let directory { return directory }
		state = .searching
		let task = loading ?? Task { [load] in try await load() }
		loading = task
		defer { if loading == task { loading = nil } }
		let directory = try await task.value
		self.directory = directory
		return directory
	}

	/// Two letters and a digit start an IBAN. Any other text with a letter is a name.
	private static func startsLikeIBAN(_ text: String) -> Bool {
		let start = Array(text.prefix(3))
		return start.count == 3 && start[0].isLetter && start[1].isLetter && start[2].isNumber
	}

	private static func usable(_ bank: BankDirectory.Entry) -> State {
		bank.bank.url == nil ? .failed("\(bank.bank.name) does not provide a FinTS/HBCI server. An extension can add support for the bank.") : .found(bank)
	}
}
