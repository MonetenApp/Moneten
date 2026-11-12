import Domain
import Foundation
import Observation

/// The bank of "IBAN or Bankleitzahl", the first step of "Add Account". The result always belongs to
/// the entry of this moment: a new entry drops the result of the last one, and a lookup that ends after
/// the entry changed changes nothing. So the login never goes to the bank of an earlier entry.
@MainActor
@Observable
public final class BankLookup {
	public enum State: Equatable {
		case none
		case searching
		case found(bankCode: String, FinTSBank)
		case failed(String)
	}

	public var entry = "" {
		didSet { if entry != oldValue { state = .none } }
	}
	public private(set) var state = State.none
	@ObservationIgnored private let find: (String) async throws -> FinTSBank?

	/// `find` returns the bank of a Bankleitzahl, or nil when the bank directory does not know it.
	public init(find: @escaping (String) async throws -> FinTSBank?) {
		self.find = find
	}

	/// The Bankleitzahl and the bank of the entry, once the lookup found a bank with a FinTS address.
	public var bank: (code: String, bank: FinTSBank)? {
		if case let .found(code, bank) = state { (code, bank) } else { nil }
	}

	/// Looks up the bank of the entry. While the user types, `showingErrors` is false, so that half an
	/// IBAN is not an error.
	public func lookUp(showingErrors: Bool) async {
		let entry = entry
		let code: String
		do {
			code = try BankEntry.bankCode(of: entry)
		} catch {
			state = showingErrors ? .failed(error.message) : .none
			return
		}
		state = .searching
		let result: State
		do {
			result = switch try await find(code) {
			case let bank? where bank.url != nil: .found(bankCode: code, bank)
			case let bank?: .failed("\(bank.name) does not provide a FinTS/HBCI server. An extension can add support for the bank.")
			case nil: .failed("The Bankleitzahl is invalid.")
			}
		} catch {
			result = .failed((error as? SyncFailure)?.message ?? error.localizedDescription)
		}
		guard entry == self.entry else { return }
		state = result
	}
}
