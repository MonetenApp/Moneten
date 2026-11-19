import Testing
@testable import Domain

@Suite("Back and Forward")
struct BrowseHistoryTests {
	/// Walks from the first entry through the others by hand, as a click in the sidebar does.
	func walk(_ entries: [String]) -> BrowseHistory<String> {
		var history = BrowseHistory<String>()
		for (current, next) in zip(entries, entries.dropFirst()) { history.leave(current, for: next) }
		return history
	}

	@Test("After A, S, and B, removing S lets Back open A and leaves B as the only forward step")
	func removedEntryBetween() {
		var history = walk(["A", "S", "B"])
		history.forget("S", current: "B")
		#expect(history.back == ["A"])
		#expect(history.goBack(from: "B") == "A")
		#expect(history.forward == ["B"])
		#expect(history.back.isEmpty)
	}

	@Test("Back and Forward hold only views that exist, so a removed search alone leaves both disabled")
	func onlyRemovedEntries() {
		var history = walk(["S", "B"])
		_ = history.goBack(from: "B")
		history.leave("S", for: "C")
		history.forget("S", current: "C")
		#expect(history.back.isEmpty && history.forward.isEmpty)
	}

	@Test("Removing a search between two visits of one view merges them, so each step opens another view")
	func neighborsMerge() {
		var history = walk(["A", "B", "S", "B", "S", "A"])
		history.forget("S", current: "A")
		#expect(history.back == ["A", "B"])
		#expect(history.goBack(from: "A") == "B")
		#expect(history.goBack(from: "B") == "A")
		#expect(history.forward == ["A", "B"])
		var ahead = history
		#expect(ahead.goForward(from: "A") == "B")
		history.forget("B", current: "A")
		#expect(history.back.isEmpty && history.forward.isEmpty)
	}

	@Test("After A, S, A, and Back to S, removing the open S lets Back open A and leaves Forward disabled")
	func removedOpenEntryBetweenEqualViews() {
		var history = walk(["A", "S", "A"])
		#expect(history.goBack(from: "A") == "S")
		// Removing the open search leaves no open view.
		history.forget("S", current: nil)
		#expect(history.back == ["A"] && history.forward.isEmpty)
		#expect(history.goBack(from: nil) == "A")
		#expect(history.back.isEmpty && history.forward.isEmpty)
	}

	@Test("Without an open view, Back and Forward keep their steps when they lead to different views")
	func noOpenViewKeepsDifferentSteps() {
		var history = walk(["A", "S", "B"])
		#expect(history.goBack(from: "B") == "S")
		history.forget("S", current: nil)
		#expect(history.back == ["A"] && history.forward == ["B"])
	}

	@Test("A step by hand drops the forward steps, and a step to the open view is no step")
	func stepByHand() {
		var history = walk(["A", "B", "C"])
		_ = history.goBack(from: "C")
		history.leave("B", for: "B")
		#expect(history.forward == ["C"])
		history.leave("B", for: "D")
		#expect(history.back == ["A", "B"] && history.forward.isEmpty)
	}
}
