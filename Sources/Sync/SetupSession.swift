import Domain
import Foundation

/// The session of the "Add Account" assistant for the first login of a new access.
///
/// It answers the PIN request with the PIN of the login step, and ends the login when the bank rejects
/// that PIN, so that the assistant shows the message of the bank in its login step and the bank gets
/// no second attempt ("Report a failed login without leaving the assistant"). Every other request opens
/// the dialogs of the broker, one at a time together with the dialogs of running refreshes.
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
		return .pin(pin)
	}

	public func report(_ progress: SyncProgress) async {}
}
