/// The guard against a replayed update feed (spec: "Check the update feed"). The update key signs
/// every feed, also the old ones, so someone who serves an older signed feed could offer a version
/// that a newer feed took out. Every feed that `scripts/release-notes.py` writes, a withdrawal too,
/// carries a revision one above the feed before it, in each item, because Sparkle hands the app only
/// the items. The newest build is no such measure: a withdrawal of a stable build can keep a newer
/// beta build, and Sparkle drops the channels that the user did not choose only after this check.
/// The app keeps the highest revision that it read as a floor and refuses a feed below it.
public enum FeedRevision {
	public enum Result: Sendable, Equatable {
		/// The feed may be read. `floor` is the floor to keep from now on.
		case accepted(floor: Int?)
		/// The feed is older than one that the app read before, or an item has no revision.
		case refused(revision: Int?, floor: Int?)
	}

	/// The result for a feed whose items carry `revisions`, nil for an item without one, after the
	/// app read feeds up to `floor`. A feed without items offers nothing, so it keeps the floor.
	public static func check(revisions: [Int?], floor: Int?) -> Result {
		guard !revisions.isEmpty else { return .accepted(floor: floor) }
		let known = revisions.compactMap(\.self)
		// A signed feed has one revision in every item. The lowest one counts, so nothing passes by an item that has more.
		guard known.count == revisions.count, let revision = known.min() else { return .refused(revision: nil, floor: floor) }
		if let floor, revision < floor { return .refused(revision: revision, floor: floor) }
		return .accepted(floor: max(revision, floor ?? revision))
	}
}
