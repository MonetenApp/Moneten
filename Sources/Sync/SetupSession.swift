import Domain
import Foundation

/// The session of the "Add Account" assistant for the first login of a new access.
///
/// It answers the PIN request with the PIN of the login step, and ends the login when the bank rejects
/// that PIN, so that the assistant shows the message of the bank in its login step and the bank gets
/// no second attempt ("Report a failed login without leaving the assistant"). A PIN that breaks a rule
/// of the bank ends the login in the same way, before the PIN is sent. Every other request opens the
/// dialogs of the broker, one at a time together with the dialogs of running refreshes.
public struct SetupSession: SyncSession {
	let broker: SessionBroker
	let access: Access
	let pin: Secret

	public init(broker: SessionBroker, access: Access, pin: Secret) {
		self.broker = broker
		self.access = access
		self.pin = pin
	}

	public func ask(_ request: UserRequest) async throws -> UserAnswer {
		guard case let .pin(pinRequest) = request else {
			return try await broker.ask(request, for: access, accountNames: [], attended: true)
		}
		if let rejected = pinRequest.rejected { throw SyncFailure.pinRejected(rejected) }
		if let broken = pinRequest.rules.check(pin.value, secretName: pinRequest.secretName) { throw BrokenPINRule(text: broken) }
		return .pin(pin)
	}

	/// Runs the login with this session. When the login ends, also with an error, or is canceled, for
	/// example by the lock, the dialog of the access no longer waits for a challenge, so its progress
	/// closes at once, also while the connector still ends.
	@MainActor
	public func logIn<T: Sendable>(_ login: @MainActor (SetupSession) async throws -> T) async throws -> T {
		let broker = broker, access = access.id
		defer { broker.endRequest(of: access) }
		return try await withTaskCancellationHandler {
			try await login(self)
		} onCancel: {
			Task { @MainActor in broker.endRequest(of: access) }
		}
	}

	public func report(_ progress: SyncProgress) async {}
}

/// The PIN of the login step breaks a rule of the bank. The text names the rule.
struct BrokenPINRule: LocalizedError {
	let text: String

	var errorDescription: String? { text }
}
