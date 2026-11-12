import Foundation
import Testing
@testable import Domain

/// The states of a refresh, from openspec/changes/add-account-refresh/design.md.
@Suite("Sync model")
struct SyncModelTests {
	static let summary = SyncSummary(finishedAt: Date(timeIntervalSince1970: 0), fetched: [], failures: [:])
	static let pinWaiting = SyncState.needsUser(.pin, waiting: true, during: .connecting)
	static let tanDuringFetch = SyncState.needsUser(.secondFactor, waiting: false, during: .fetching(done: 1, of: 3))

	static let states: [(String, SyncState)] = [
		("idle", .idle), ("connecting", .connecting), ("fetching", .fetching(done: 1, of: 3)),
		("pinWaiting", pinWaiting), ("tanDuringFetch", tanDuringFetch),
		("finished", .finished(summary)), ("failed", .failed(.offline)), ("cancelled", .cancelled),
	]

	static let events: [(String, SyncEvent)] = [
		("start", .start), ("progress", .progress(.fetching(done: 2, of: 3))), ("ask", .ask(.secondFactor, waiting: false)),
		("dialogOpened", .dialogOpened), ("answered", .answered), ("finish", .finish(summary)), ("fail", .fail(.offline)), ("cancel", .cancel),
	]

	/// Every allowed transition. Every other pair of state and event is refused.
	static let allowed: [String: SyncState] = [
		"idle start": .connecting,
		"finished start": .connecting,
		"failed start": .connecting,
		"cancelled start": .connecting,
		"connecting progress": .fetching(done: 2, of: 3),
		"fetching progress": .fetching(done: 2, of: 3),
		"connecting ask": .needsUser(.secondFactor, waiting: false, during: .connecting),
		"fetching ask": .needsUser(.secondFactor, waiting: false, during: .fetching(done: 1, of: 3)),
		"pinWaiting dialogOpened": .needsUser(.pin, waiting: false, during: .connecting),
		"pinWaiting answered": .connecting,
		"tanDuringFetch answered": .fetching(done: 1, of: 3),
		"connecting finish": .finished(summary),
		"fetching finish": .finished(summary),
		"connecting fail": .failed(.offline),
		"fetching fail": .failed(.offline),
		"pinWaiting fail": .failed(.offline),
		"tanDuringFetch fail": .failed(.offline),
		"connecting cancel": .cancelled,
		"fetching cancel": .cancelled,
		"pinWaiting cancel": .cancelled,
		"tanDuringFetch cancel": .cancelled,
	]

	@Test("Every allowed transition, and every other one is refused")
	func transitions() {
		var seen = 0
		for (stateName, state) in Self.states {
			for (eventName, event) in Self.events {
				let key = "\(stateName) \(eventName)"
				#expect(state.next(event) == Self.allowed[key], "\(key)")
				if Self.allowed[key] != nil { seen += 1 }
			}
		}
		#expect(seen == Self.allowed.count)
	}

	@Test("A refresh is running only between its start and its end")
	func running() {
		#expect(Self.states.filter { $0.1.isRunning }.map(\.0) == ["connecting", "fetching", "pinWaiting", "tanDuringFetch"])
	}

	@Test("A secret never prints its value")
	func secret() {
		let pin = Secret("48151")
		var dumped = ""
		dump(UserAnswer.pin(pin), to: &dumped)
		for text in ["\(pin)", String(describing: pin), String(reflecting: pin), "\(UserAnswer.tan(pin))", dumped] {
			#expect(!text.contains("48151"), "\(text)")
		}
		#expect(pin.value == "48151")
	}

	@Test("Each failure says what the user can do")
	func messages() {
		#expect(SyncFailure.needsUser(.secondFactor).message.contains("Refresh Account"))
		#expect(SyncFailure.needsUser(.pin).message.contains("PIN"))
		#expect(SyncFailure.pinRejected(BankMessage(code: "9942", text: "PIN falsch")).message.contains("PIN falsch"))
		#expect(SyncFailure.pinRejected(BankMessage(text: "PIN falsch")).message.contains("block"))
		#expect(SyncFailure.tanRejected(BankMessage(text: "TAN ungültig")).message == "The bank did not accept the entered TAN: TAN ungültig")
		#expect(SyncFailure.bank(BankMessage(code: "9942", text: "Zugang vorübergehend gesperrt")).message == "Zugang vorübergehend gesperrt")
		#expect(SyncFailure.challengeExpired.message == "The two-factor authentication timed out.")
		#expect(SyncFailure.notFetched.message == "Canceled because of the previous error.")
		#expect(SyncFailure.notSaved("disk I/O error").message == "The fetched transactions could not be saved: disk I/O error")
		#expect(SyncFailure.notRegistered.message.contains("does not know Moneten"))
	}

	@Test("A flicker code starts with the sync pattern and swaps the half bytes")
	func flicker() throws {
		let code = try #require(FlickerCode(hex: "1a"))
		let frames = code.frames
		// "0FFF1A": the bytes 0F, FF, 1A give the half bytes F, 0, F, F, A, 1, two frames each.
		#expect(frames.count == 12)
		#expect(frames[0] == [true, true, true, true, true])
		#expect(frames[1] == [false, true, true, true, true])
		#expect(frames[2] == [true, false, false, false, false])
		#expect(frames[8] == [true, false, true, false, true])
		#expect(frames[10] == [true, true, false, false, false])
		#expect(FlickerCode(hex: "1") == nil)
		#expect(FlickerCode(hex: "XY") == nil)
	}
}
