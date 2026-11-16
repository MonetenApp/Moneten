/// The guard against a replayed update feed (spec: "Check the update feed"). The update key signs
/// every feed, also the old ones, so someone who serves an older signed feed could offer a version
/// that a newer feed took out. The app keeps the newest build of the feeds it read as a floor and
/// refuses a feed whose newest build is below it.
public enum FeedFloor {
	public enum Result: Sendable, Equatable {
		/// The feed may be read. `floor` is the floor to keep from now on.
		case accepted(floor: Int?)
		/// The feed is older than one that the app read before.
		case refused(newest: Int, floor: Int)
	}

	/// The result for a feed with the items `builds`, after the app read feeds up to `floor`. A feed
	/// without items offers nothing, so it keeps the floor.
	public static func check(builds: [Int], floor: Int?) -> Result {
		guard let newest = builds.max() else { return .accepted(floor: floor) }
		if let floor, newest < floor { return .refused(newest: newest, floor: floor) }
		return .accepted(floor: max(newest, floor ?? newest))
	}
}
