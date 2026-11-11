import Domain
import Foundation
import Observation

/// A request for the user, on screen or waiting in the queue.
public struct Prompt: Identifiable, Equatable, Sendable {
	public let id: UUID
	public let access: Access
	/// The accounts of the refresh, for the PIN sheet.
	public let accountNames: [String]
	public let request: UserRequest
}

/// Shows the requests of all connectors to the user, one dialog at a time and in the order they came.
///
/// An automatic refresh never reaches the queue: its requests fail at once with `SyncFailure.needsUser`.
/// A PIN that the user entered is kept in memory for its access until the app locks or quits, or
/// until the bank rejects it.
@MainActor
@Observable
public final class SessionBroker {
	/// The dialog on screen.
	public private(set) var current: Prompt?
	private var queue: [Prompt] = []
	/// The prompts that waited behind the dialog of another access.
	private var waited: Set<UUID> = []
	private var continuations: [UUID: CheckedContinuation<UserAnswer, Error>] = [:]
	private var expiry: Task<Void, Never>?
	private var pins: [UUID: Secret] = [:]

	/// Reports each change of the dialogs of an access, for its `SyncState`.
	var onEvent: (UUID, SyncEvent) -> Void = { _, _ in }
	/// The user canceled the dialog of an access.
	var onUserCancel: (UUID) -> Void = { _ in }

	public init() {}

	func ask(_ request: UserRequest, for access: Access, accountNames: [String], attended: Bool) async throws -> UserAnswer {
		guard attended else { throw SyncFailure.needsUser(request.kind) }
		if case .pin = request, let pin = pins[access.id] { return .pin(pin) }
		try Task.checkCancellation()
		let prompt = Prompt(id: UUID(), access: access, accountNames: accountNames, request: request)
		let answer = try await withTaskCancellationHandler {
			try await withCheckedThrowingContinuation { continuation in
				continuations[prompt.id] = continuation
				let waiting = current != nil
				if waiting { waited.insert(prompt.id) }
				onEvent(access.id, .ask(request.kind, waiting: waiting))
				queue.append(prompt)
				showNext()
			}
		} onCancel: {
			// The connector withdrew the request, for example because the bank reported the approval.
			Task { @MainActor in self.close(prompt.id, with: .failure(CancellationError()), event: .answered) }
		}
		if case let .pin(secret) = answer { pins[access.id] = secret }
		return answer
	}

	/// The user answered the dialog on screen.
	public func answer(_ answer: UserAnswer) {
		guard let current else { return }
		close(current.id, with: .success(answer), event: .answered)
	}

	/// The user canceled the dialog on screen. The refresh of its access stops.
	public func cancel() {
		guard let current else { return }
		close(current.id, with: .failure(CancellationError()), event: nil)
		onUserCancel(current.access.id)
	}

	/// Forgets every PIN in memory, when the app locks.
	public func forgetPINs() {
		pins = [:]
	}

	func forgetPIN(of access: UUID) {
		pins[access] = nil
	}

	private func showNext() {
		guard current == nil, !queue.isEmpty else { return }
		let prompt = queue.removeFirst()
		current = prompt
		if waited.remove(prompt.id) != nil { onEvent(prompt.access.id, .dialogOpened) }
		if case let .secondFactor(request) = prompt.request {
			// The validity starts when the dialog opens, not while it waits behind another one.
			expiry = Task { [weak self] in
				try? await Task.sleep(for: request.validity)
				guard !Task.isCancelled else { return }
				self?.close(prompt.id, with: .failure(SyncFailure.challengeExpired), event: nil)
			}
		}
	}

	private func close(_ id: UUID, with result: Result<UserAnswer, Error>, event: SyncEvent?) {
		guard let continuation = continuations.removeValue(forKey: id) else { return }
		let access = current?.id == id ? current?.access : queue.first { $0.id == id }?.access
		queue.removeAll { $0.id == id }
		waited.remove(id)
		if current?.id == id {
			current = nil
			expiry?.cancel()
			expiry = nil
		}
		if let event, let access { onEvent(access.id, event) }
		continuation.resume(with: result)
		showNext()
	}
}
