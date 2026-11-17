import Domain
import Testing

@Suite("Refusing an older update feed")
struct FeedRevisionTests {
	@Test("The first feed sets the floor to its revision")
	func firstFeed() {
		#expect(FeedRevision.check(revisions: [5, 5], floor: nil) == .accepted(floor: 5))
	}

	/// Build 100 is installed and pre-release versions are off. Revision 5 listed the stable build 110
	/// and the beta build 120. Revision 6 took out build 110 and kept 120. A replay of revision 5 has
	/// the same newest build as revision 6, and Sparkle filters the channels only after this check,
	/// so only the revision tells the feeds apart.
	@Test("A replayed feed from before a withdrawal is refused, even with the same newest build")
	func replayAcrossChannels() {
		#expect(FeedRevision.check(revisions: [6], floor: nil) == .accepted(floor: 6))
		#expect(FeedRevision.check(revisions: [5, 5], floor: 6) == .refused(revision: 5, floor: 6))
	}

	@Test("The same feed again keeps the floor")
	func sameFeed() {
		#expect(FeedRevision.check(revisions: [6], floor: 6) == .accepted(floor: 6))
	}

	@Test("A newer feed raises the floor, also when its newest build is lower")
	func newerFeed() {
		#expect(FeedRevision.check(revisions: [7, 7], floor: 6) == .accepted(floor: 7))
	}

	@Test("A feed with an item without a revision is refused")
	func missingRevision() {
		#expect(FeedRevision.check(revisions: [7, nil], floor: 6) == .refused(revision: nil, floor: 6))
		#expect(FeedRevision.check(revisions: [nil], floor: nil) == .refused(revision: nil, floor: nil))
	}

	@Test("Items with different revisions count with the lowest one")
	func mixedRevisions() {
		#expect(FeedRevision.check(revisions: [7, 5], floor: 6) == .refused(revision: 5, floor: 6))
	}

	@Test("A feed without items offers nothing and keeps the floor")
	func emptyFeed() {
		#expect(FeedRevision.check(revisions: [], floor: 6) == .accepted(floor: 6))
		#expect(FeedRevision.check(revisions: [], floor: nil) == .accepted(floor: nil))
	}
}
