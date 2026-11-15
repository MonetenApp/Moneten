import Domain
import Foundation

/// The session of the "Add Account" assistant for the first login of a new access.
///
/// It answers the PIN request with the PIN of the login step, and ends the login when the bank rejects
/// that PIN, so that the assistant shows the message of the bank in its login step and the bank gets
/// no second attempt ("Report a failed login without leaving the assistant"). A PIN that breaks a rule
/// of the bank ends the login in the same way, before the PIN is sent. Every other request opens the
/// dialogs of the broker, one at a time together with the dialogs of running refreshes.
///
/// For a login that the app has already, `replacing` names its access: a rejection or a block in the
/// setup deletes the saved PIN of that access and forgets its PIN in memory.
///
/// Without a PIN, the session logs in to an access that the app has with the PIN of the access, for "Look
/// for New Accounts...": the PIN in memory, the saved PIN, or the PIN sheet, as an attended refresh does. A PIN
/// that the user typed is kept, and saved on request, only when the login succeeded.
public struct SetupSession: SyncSession {
	let broker: SessionBroker
	let access: Access
	let pin: Secret?
	let replacing: UUID

	public init(broker: SessionBroker, access: Access, pin: Secret?, replacing: UUID? = nil) {
		self.broker = broker
		self.access = access
		self.pin = pin
		self.replacing = replacing ?? access.id
	}

	public func ask(_ request: UserRequest) async throws -> UserAnswer {
		guard case let .pin(pinRequest) = request, let pin else {
			return try await broker.ask(request, for: access, accountNames: [], attended: true)
		}
		if let rejected = pinRequest.rejected {
			await broker.forgetRejectedPIN(of: replacing)
			throw SyncFailure.pinRejected(rejected)
		}
		if let broken = pinRequest.rules.check(pin.value, secretName: pinRequest.secretName) { throw BrokenPINRule(text: broken) }
		return .pin(pin)
	}

	/// Runs the login with this session. When the login ends, also with an error, or is canceled, for
	/// example by the lock or by Cancel in its progress, the dialog of the access no longer waits for a
	/// challenge, so its progress closes at once, also while the connector still ends.
	@MainActor
	public func logIn<T: Sendable>(_ login: @escaping @MainActor @Sendable (SetupSession) async throws -> T) async throws -> T {
		let broker = broker, access = access.id, session = self
		let task = Task { @MainActor in try await login(session) }
		broker.logins[access] = { task.cancel() }
		var succeeded = false
		defer {
			broker.logins[access] = nil
			broker.endRequest(of: access)
			if pin == nil { broker.loginEnded(access, succeeded: succeeded) }
		}
		do {
			let result = try await withTaskCancellationHandler {
				try await task.value
			} onCancel: {
				task.cancel()
				Task { @MainActor in broker.endRequest(of: access) }
			}
			succeeded = true
			return result
		} catch {
			// A rejection or a block can come after notices of the bank, inside `FailureWithNotices`.
			let failure = FailureWithNotices.split(error).failure
			if (failure as? SyncFailure)?.rejectsPIN == true { broker.forgetRejectedPIN(of: replacing) }
			throw error
		}
	}

	public func report(_ progress: SyncProgress) async {}

	public func rejected(_ failure: SyncFailure) async {
		await broker.forgetRejectedPIN(of: replacing)
	}
}

/// The PIN of the login step breaks a rule of the bank. The text names the rule.
struct BrokenPINRule: LocalizedError {
	let text: String

	var errorDescription: String? { text }
}
