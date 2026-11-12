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

/// The dialog of an access after the user chose a TAN method or a TAN medium, while the app waits for
/// the next request of the bank.
public struct ChallengeRequest: Identifiable, Equatable, Sendable {
	public let id = UUID()
	public let access: Access
	public let progress: ChallengeProgress
}

/// Shows the requests of all connectors to the user, one dialog at a time and in the order they came.
///
/// An automatic refresh never reaches the queue: it gets the PIN in memory, and every other request
/// fails at once with `SyncFailure.needsUser`. A PIN that the user entered is kept in memory for its
/// access until the app locks or quits, or until a refresh with it ends without success. A PIN that
/// the user asked to save goes into the `SavedPINStore` when a refresh with it finished, so only a PIN
/// that the bank accepted is saved. The saved PINs join the memory when the database opens.
///
/// A PIN request that carries the rejection of the bank is never answered from memory. The broker
/// forgets the PIN, deletes the saved one, and shows the sheet again, or fails an automatic refresh with
/// `SyncFailure.pinRejected`. So a connector must set `PINRequest.rejected` on every PIN request that
/// follows a rejection, or else throw `SyncFailure.pinRejected` itself. A plain PIN request is answered
/// from memory, which would send the wrong PIN again.
///
/// After the user chose a TAN method or a TAN medium, the dialog of the access stays open as
/// `requesting` with what the app requests from the bank, until the next request of that access or
/// until the access goes on or ends. The dialogs of other accesses wait for it.
@MainActor
@Observable
public final class SessionBroker {
	/// The dialog on screen.
	public private(set) var current: Prompt?
	/// The dialog that shows the progress after a TAN method or medium, while no request is on screen.
	public private(set) var requesting: ChallengeRequest?
	/// The accesses whose PIN is saved in the database, for "Remove saved PIN".
	public private(set) var savedPINs: Set<UUID> = []
	private var queue: [Prompt] = []
	/// The prompts that waited behind the dialog of another access.
	private var waited: Set<UUID> = []
	private var continuations: [UUID: CheckedContinuation<UserAnswer, Error>] = [:]
	private var expiry: Task<Void, Never>?
	private var pins: [UUID: Secret] = [:]
	/// The accesses whose PIN the user asked to save, until a refresh with it finished.
	private var toSave: Set<UUID> = []
	/// The TAN method that the user chose in the running refresh of an access, for the progress after the medium.
	private var chosenMethods: [UUID: TANMethod] = [:]
	private var store: (any SavedPINStore)?

	/// Reports each change of the dialogs of an access, for its `SyncState`.
	var onEvent: (UUID, SyncEvent) -> Void = { _, _ in }
	/// The user canceled the dialog of an access.
	var onUserCancel: (UUID) -> Void = { _ in }
	/// A saved PIN could not be written or deleted when a refresh ended.
	public var onStoreFailure: (Error) -> Void = { _ in }

	public init() {}

	func ask(_ request: UserRequest, for access: Access, accountNames: [String], attended: Bool) async throws -> UserAnswer {
		if case let .pin(pinRequest) = request {
			if let rejected = pinRequest.rejected {
				forgetRejectedPIN(of: access.id)
				guard attended else { throw SyncFailure.pinRejected(rejected) }
			} else if let pin = pins[access.id] {
				return .pin(pin)
			}
		}
		guard attended else { throw SyncFailure.needsUser(request.kind) }
		try Task.checkCancellation()
		let prompt = Prompt(id: UUID(), access: access, accountNames: accountNames, request: request)
		let answer = try await withTaskCancellationHandler {
			try await withCheckedThrowingContinuation { continuation in
				continuations[prompt.id] = continuation
				let waiting = current != nil || (requesting.map { $0.access.id != access.id } ?? false)
				if waiting { waited.insert(prompt.id) }
				onEvent(access.id, .ask(request.kind, waiting: waiting))
				queue.append(prompt)
				showNext()
			}
		} onCancel: {
			// The connector withdrew the request, for example because the bank reported the approval.
			Task { @MainActor in self.close(prompt.id, with: .failure(CancellationError()), event: .answered) }
		}
		if case let .pin(secret, save) = answer {
			pins[access.id] = secret
			if save { toSave.insert(access.id) } else { toSave.remove(access.id) }
		}
		return answer
	}

	/// The user answered the dialog `id`. A second click after the dialog closed does nothing, so it
	/// never answers the next dialog in the queue. A TAN method or medium keeps the dialog open with
	/// its progress.
	public func answer(_ answer: UserAnswer, to id: UUID) {
		guard let current, current.id == id else { return }
		if case let .secondFactor(request) = current.request, let progress = progress(after: answer, to: request, of: current.access.id) {
			requesting = ChallengeRequest(access: current.access, progress: progress)
		}
		close(id, with: .success(answer), event: .answered)
	}

	/// The user canceled the dialog `id`. The refresh of its access stops.
	public func cancel(_ id: UUID) {
		guard let current, current.id == id else { return }
		close(id, with: .failure(CancellationError()), event: nil)
		onUserCancel(current.access.id)
	}

	/// The user canceled the dialog while it shows the progress. The refresh of its access stops.
	public func cancelRequest() {
		guard let requesting else { return }
		self.requesting = nil
		onUserCancel(requesting.access.id)
		showNext()
	}

	/// Takes the saved PINs of the database that opened, so that a refresh after a restart does not ask.
	public func open(_ store: any SavedPINStore) throws {
		let saved = try store.savedPINs()
		self.store = store
		pins.merge(saved) { _, saved in saved }
		savedPINs = Set(saved.keys)
	}

	/// Forgets every PIN in memory and the store of saved PINs, when the app locks.
	public func forgetPINs() {
		pins = [:]
		toSave = []
		savedPINs = []
		store = nil
	}

	/// Keeps the PIN that the setup of a new access logged in with, so that its first refresh does not
	/// ask again. The bank accepted it, so it is saved at once when the user asked to save it.
	public func remember(_ pin: Secret, for access: UUID, save: Bool) throws {
		pins[access] = pin
		if save { try writeSavedPIN(pin, of: access) }
	}

	/// "Remove saved PIN": deletes the saved PIN of an access, for all its accounts, and forgets it, so the
	/// next refresh asks.
	public func removeSavedPIN(of access: UUID) throws {
		try store?.removeSavedPIN(of: access)
		savedPINs.remove(access)
		pins[access] = nil
	}

	/// Forgets the PIN of one access, for example when the access goes with its last account. The
	/// database deletes a saved PIN together with its access.
	public func forgetPIN(of access: UUID) {
		pins[access] = nil
		toSave.remove(access)
		savedPINs.remove(access)
	}

	/// The refresh of an access ended with `event`. After a finished refresh the bank has accepted the
	/// PIN, so a PIN that the user asked to save goes into the database now. After any other end, a PIN
	/// that is not saved is forgotten, so a typing error is never sent again on its own. A saved PIN
	/// stays, unless the bank rejected it.
	func refreshEnded(_ access: UUID, with event: SyncEvent) {
		endRequest(of: access)
		chosenMethods[access] = nil
		let save = toSave.remove(access) != nil
		switch event {
		case .finish:
			guard save, let pin = pins[access] else { return }
			do { try writeSavedPIN(pin, of: access) } catch { onStoreFailure(error) }
		case .fail(.pinRejected):
			forgetRejectedPIN(of: access)
		default:
			if !savedPINs.contains(access) { pins[access] = nil }
		}
	}

	/// The access went on or ended, so its dialog no longer waits for a challenge.
	func endRequest(of access: UUID) {
		guard requesting?.access.id == access else { return }
		requesting = nil
		showNext()
	}

	private func writeSavedPIN(_ pin: Secret, of access: UUID) throws {
		try store?.savePIN(pin, for: access)
		if store != nil { savedPINs.insert(access) }
	}

	/// The bank rejected the PIN: it leaves the memory and the database ("No automatic retry after a wrong PIN").
	private func forgetRejectedPIN(of access: UUID) {
		pins[access] = nil
		toSave.remove(access)
		guard savedPINs.contains(access) else { return }
		do {
			try store?.removeSavedPIN(of: access)
			savedPINs.remove(access)
		} catch {
			onStoreFailure(error)
		}
	}

	/// What the app requests from the bank after `answer`: the list of media for a method that needs a
	/// medium, and otherwise the challenge of the method. Nil for an answer that ends the dialog.
	private func progress(after answer: UserAnswer, to request: SecondFactorRequest, of access: UUID) -> ChallengeProgress? {
		switch answer {
		case let .tanMethod(id):
			let offered = if case let .chooseTANMethod(methods, _) = request.challenge { methods } else { request.methods }
			guard let method = offered.first(where: { $0.id == id }) else { return .challenge(.tan) }
			chosenMethods[access] = method
			return method.needsMedium ? .tanMedia : .challenge(method.delivery)
		case .tanMedium:
			return .challenge(chosenMethods[access]?.delivery ?? .tan)
		case .pin, .tan:
			return nil
		}
	}

	/// Shows the next prompt. While the progress of an access shows, only a prompt of that access can follow.
	private func showNext() {
		guard current == nil else { return }
		let next = if let requesting { queue.firstIndex { $0.access.id == requesting.access.id } } else { queue.indices.first }
		guard let next else { return }
		let prompt = queue.remove(at: next)
		requesting = nil
		current = prompt
		if waited.remove(prompt.id) != nil { onEvent(prompt.access.id, .dialogOpened) }
		if case let .secondFactor(request) = prompt.request {
			// The validity starts when the dialog opens, not while it waits behind another one.
			expiry = Task { [weak self] in
				try? await Task.sleep(for: request.validity)
				guard !Task.isCancelled else { return }
				self?.close(prompt.id, with: .failure(SyncFailure.challengeExpired), event: .answered)
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
