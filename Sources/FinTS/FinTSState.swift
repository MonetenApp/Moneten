import Domain
import Foundation

/// The state of a FinTS access: the passport that the helper returned last, and the accounts whose older
/// transactions may be missing ("The first refresh asks for the full history"). The mark lives here, in the
/// state that the database already keeps for the access, so it stays through a lock and a restart.
///
/// Without a mark the state is the passport alone, as before. The helper writes the passport as a Java object
/// stream, which starts with the bytes AC ED and never reads as JSON. With a mark the state is JSON that holds
/// the passport, so a state of an earlier build still reads.
struct FinTSState: Codable, Equatable {
	/// The passport of the helper, nil before the first login.
	var passport: Data?
	/// The account numbers or IBANs, as the helper knows them, sorted.
	var olderMayBeMissing: [String]

	init(passport: Data?, olderMayBeMissing: some Sequence<String>) {
		self.passport = passport
		self.olderMayBeMissing = Set(olderMayBeMissing).sorted()
	}

	init(_ state: AccessState?) {
		guard let data = state?.data else {
			self.init(passport: nil, olderMayBeMissing: [])
			return
		}
		if let decoded = try? JSONDecoder().decode(FinTSState.self, from: data) {
			self = decoded
		} else {
			self.init(passport: data, olderMayBeMissing: [])
		}
	}

	/// The state to store, nil when there is nothing to keep.
	var accessState: AccessState? {
		if olderMayBeMissing.isEmpty { return passport.map(AccessState.init) }
		// Encoding a struct of data and strings does not fail.
		return (try? JSONEncoder().encode(self)).map(AccessState.init)
	}
}

extension FinTSConnector {
	/// The account numbers or IBANs of the accounts of a FinTS access whose older transactions may be missing,
	/// so that the account view says it also after a lock or a restart.
	public static func accountsMissingOlder(in state: AccessState?) -> Set<String> {
		Set(FinTSState(state).olderMayBeMissing)
	}

	/// The state of a new login of an access ("Edit Login Data..."), with the marks of `old`, because the accounts
	/// and their transactions stay.
	public static func state(_ new: AccessState?, keepingMarksOf old: AccessState?) -> AccessState? {
		FinTSState(passport: FinTSState(new).passport, olderMayBeMissing: FinTSState(old).olderMayBeMissing).accessState
	}
}
