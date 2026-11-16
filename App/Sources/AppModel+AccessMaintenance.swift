import Domain
import Foundation

/// "Look for New Accounts..." and "Edit Login Data..." on an account with a FinTS access (add-account-setup).
/// An extension asks for its login data in its own dialog at each session, and its setup under "Other" adds
/// only the accounts that the app does not have, so neither command applies to it.
extension AppModel {
	/// The FinTS access of the account, when the account has one.
	func fintsAccess(of account: UUID) -> Access? {
		guard let access = ledger.account(account)?.accessID.flatMap({ accesses[$0] }), case .fints = access.source else { return nil }
		return access
	}

	/// "Look for New Accounts...": the account selection with the accounts of the login that the app does not
	/// have yet. The new accounts go into the group of `account`.
	func lookForNewAccounts(account id: UUID) {
		guard let access = fintsAccess(of: id) else { return }
		addAccount(group: ledger.account(id)?.groupID, purpose: .newAccounts(access))
	}

	/// "Edit Login Data...": the login step with the stored login name and an empty PIN.
	func editLoginData(account id: UUID) {
		guard let access = fintsAccess(of: id) else { return }
		addAccount(group: ledger.account(id)?.groupID, purpose: .editLogin(access))
	}
}
