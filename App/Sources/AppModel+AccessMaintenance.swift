import Domain
import Foundation

/// "Look for New Accounts..." and "Edit Login Data..." on an account with a bank access (add-account-setup).
extension AppModel {
	/// The access of the account, when the account has one.
	func access(of account: UUID) -> Access? {
		ledger.account(account)?.accessID.flatMap { accesses[$0] }
	}

	/// "Edit Login Data..." applies to a FinTS access. An extension asks for its login data in its own
	/// dialog at each session.
	func canEditLoginData(of account: UUID) -> Bool {
		if case .fints? = access(of: account)?.source { true } else { false }
	}

	/// "Look for New Accounts...": a FinTS access logs in with the PIN of the access and opens the account
	/// selection with the accounts that the app does not have yet. An extension runs its setup again, which
	/// adds only the accounts that the app does not have. The new accounts go into the group of `account`.
	func lookForNewAccounts(account id: UUID) {
		guard let access = access(of: id) else { return }
		let group = ledger.account(id)?.groupID
		switch access.source {
		case .fints:
			addAccount(group: group, purpose: .newAccounts(access))
		case let .extension(package):
			// The setup of the extension is an access of its own for the coordinator, which would not wait for the refresh.
			guard !sync.isBusy(access.id) else {
				alert = AlertMessage(title: "Moneten is refreshing \(access.bankName).", message: "Look for new accounts again when the refresh has ended.")
				return
			}
			do {
				addExtensionAccess(package: try extensions.verifiedPackage(package), service: access.bankName, fixture: extensions.fixtures[package], groupID: group)
			} catch {
				alert = AlertMessage(title: "Could not look for new accounts.", message: error.message)
			}
		case .finAPI:
			break
		}
	}

	/// "Edit Login Data...": the login step with the stored login name and an empty PIN.
	func editLoginData(account id: UUID) {
		guard canEditLoginData(of: id), let access = access(of: id) else { return }
		addAccount(group: ledger.account(id)?.groupID, purpose: .editLogin(access))
	}
}
