import Domain
import Testing

@Suite("Refusing an older update feed")
struct FeedFloorTests {
	@Test("The first feed sets the floor to its newest build")
	func firstFeed() {
		#expect(FeedFloor.check(builds: [100, 120, 110], floor: nil) == .accepted(floor: 120))
	}

	@Test("A replayed older feed is refused, so a withdrawn build 110 is never offered after 120")
	func replayedFeed() {
		#expect(FeedFloor.check(builds: [100, 110], floor: 120) == .refused(newest: 110, floor: 120))
	}

	@Test("The same feed again keeps the floor")
	func sameFeed() {
		#expect(FeedFloor.check(builds: [120, 100], floor: 120) == .accepted(floor: 120))
	}

	@Test("A newer feed raises the floor")
	func newerFeed() {
		#expect(FeedFloor.check(builds: [130, 120], floor: 120) == .accepted(floor: 130))
	}

	@Test("A feed without items offers nothing and keeps the floor")
	func emptyFeed() {
		#expect(FeedFloor.check(builds: [], floor: 120) == .accepted(floor: 120))
		#expect(FeedFloor.check(builds: [], floor: nil) == .accepted(floor: nil))
	}
}
