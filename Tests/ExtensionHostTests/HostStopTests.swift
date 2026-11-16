@testable import ExtensionHost
import Foundation
import Testing

/// The host process has no String Catalog, so it sends the reason of a stop or a refusal, and the app words it.
@Suite struct HostStopTests {
	let listed = HostRefusal.notListed(extensionName: "Demo", host: "tracker.example")

	@Test("A call that fails with the last refusal sends the refusal and the position of the error")
	func refusal() {
		let error = ScriptError("Demo.lua:3: Demo may not contact tracker.example, because its manifest does not list that host.")
		let event = HostStop.event(for: error, lastRefusal: listed)
		guard case let .stopped(stop) = event else { Issue.record("\(event)"); return }
		#expect(stop == .refused(listed, position: "Demo.lua:3: "))
		#expect(stop.message == error.message)
	}

	@Test("The host finds the refusal by its script text, which the language of the interface does not change")
	func refusalByScriptText() {
		let error = ScriptError("Demo.lua:3: " + listed.scriptText)
		let event = HostStop.event(for: error, lastRefusal: listed)
		guard case let .stopped(stop) = event else { Issue.record("\(event)"); return }
		#expect(stop == .refused(listed, position: "Demo.lua:3: "))
		#expect("\(listed)" == listed.scriptText)
		#expect(stop.message == "Demo.lua:3: " + listed.message)
	}

	@Test("A script that caught the refusal and failed otherwise keeps its message")
	func caughtRefusal() {
		let event = HostStop.event(for: ScriptError("Demo.lua:9: attempt to index a nil value"), lastRefusal: listed)
		guard case let .failed(message) = event else { Issue.record("\(event)"); return }
		#expect(message == "Demo.lua:9: attempt to index a nil value")
	}

	@Test("The memory limit of Lua is sent as a reason")
	func memoryLimit() {
		let event = HostStop.event(for: ScriptError(.memoryLimit(megabytes: 16)), lastRefusal: nil)
		guard case let .stopped(stop) = event else { Issue.record("\(event)"); return }
		#expect(stop.message == "The extension needs more than 16 MB of memory.")
	}

	@Test("The line for the processor limit carries the reason, not its text")
	func processorLine() throws {
		let line = try JSONEncoder().encode(HostEvent.stopped(.processorTime(extensionName: "Demo", seconds: 2)))
		#expect(!String(decoding: line, as: UTF8.self).contains("processor time"))
		guard case let .stopped(stop) = try JSONDecoder().decode(HostEvent.self, from: line) else { Issue.record("not a stop"); return }
		#expect(stop.message == "Demo used more than 2 seconds of processor time, so Moneten stopped it.")
	}
}
