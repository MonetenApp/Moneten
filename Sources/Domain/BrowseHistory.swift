/// Back and Forward through the views, as in a browser. `back` and `forward` end with the entry that the next
/// step opens. Its own type, so that a removed entry can leave both lists and the tests can check that.
public struct BrowseHistory<Entry: Equatable & Sendable>: Equatable, Sendable {
	public private(set) var back: [Entry] = []
	public private(set) var forward: [Entry] = []

	public init() {}

	/// Notes the step from `current` to `next` by hand, which drops the forward steps.
	public mutating func leave(_ current: Entry?, for next: Entry?) {
		guard let current, current != next else { return }
		back.append(current)
		forward.removeAll()
	}

	/// The entry that "Back" opens. `current` moves to the forward steps.
	public mutating func goBack(from current: Entry?) -> Entry? {
		guard let previous = back.popLast() else { return nil }
		if let current { forward.append(current) }
		return previous
	}

	/// The entry that "Forward" opens. `current` moves to the back steps.
	public mutating func goForward(from current: Entry?) -> Entry? {
		guard let next = forward.popLast() else { return nil }
		if let current { back.append(current) }
		return next
	}

	/// Removes an entry that no longer exists, such as a removed saved search, from both lists. Neighbors that
	/// become equal merge, and a step to `current` goes too, so each step of "Back" and "Forward" opens another view.
	public mutating func forget(_ entry: Entry, current: Entry?) {
		back = Self.steps(back, without: entry, current: current)
		forward = Self.steps(forward, without: entry, current: current)
	}

	private static func steps(_ steps: [Entry], without entry: Entry, current: Entry?) -> [Entry] {
		var kept: [Entry] = []
		for step in steps where step != entry && step != kept.last { kept.append(step) }
		while let last = kept.last, last == current { kept.removeLast() }
		return kept
	}
}
