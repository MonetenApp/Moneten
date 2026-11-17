import Domain
import Testing

@Suite("Release notes of the update window")
struct ReleaseNotesTests {
	private func item(_ version: String, build: Int) -> ReleaseNoteItem {
		ReleaseNoteItem(build: build, version: version, date: Day(year: 2026, month: 11, day: build), entries: ["Entry of \(version)."])
	}

	@Test("Two skipped versions show newest first, without the installed one")
	func skipped() {
		let feed = [item("0.1.3", build: 13), item("0.1.2", build: 12), item("0.1.1", build: 11), item("0.1.0", build: 10)]
		let notes = releaseNotes(installedBuild: 11, offered: feed[0], feed: feed)
		#expect(notes.map(\.version) == ["0.1.3", "0.1.2"])
	}

	@Test("A stable version after pre-releases shows only its own notes")
	func stableAfterPreReleases() {
		let feed = [item("0.2.0", build: 22), item("0.2.0-beta.1", build: 21), item("0.1.3", build: 13)]
		let notes = releaseNotes(installedBuild: 13, offered: feed[0], feed: feed)
		#expect(notes.map(\.version) == ["0.2.0"])
	}

	@Test("An offered pre-release shows the earlier pre-releases too")
	func preReleaseOffered() {
		let feed = [item("0.2.0-beta.2", build: 22), item("0.2.0-beta.1", build: 21), item("0.1.3", build: 13)]
		let notes = releaseNotes(installedBuild: 13, offered: feed[0], feed: feed)
		#expect(notes.map(\.version) == ["0.2.0-beta.2", "0.2.0-beta.1"])
	}

	@Test("A pre-release after a stable version leaves out the pre-releases that the stable version lists")
	func preReleaseAfterStable() {
		let feed = [item("0.2.1-beta.1", build: 23), item("0.2.0", build: 22), item("0.2.0-beta.1", build: 21), item("0.1.3", build: 13)]
		let notes = releaseNotes(installedBuild: 13, offered: feed[0], feed: feed)
		#expect(notes.map(\.version) == ["0.2.1-beta.1", "0.2.0"])
	}

	@Test("A version above the offered one is not listed")
	func aboveOffered() {
		let feed = [item("0.2.0-beta.1", build: 21), item("0.1.3", build: 13), item("0.1.2", build: 12)]
		let notes = releaseNotes(installedBuild: 11, offered: feed[1], feed: feed)
		#expect(notes.map(\.version) == ["0.1.3", "0.1.2"])
	}

	@Test("A feed that failed to load gives the offered version alone")
	func feedFailed() {
		let offered = item("0.1.3", build: 13)
		#expect(releaseNotes(installedBuild: 11, offered: offered, feed: []) == [offered])
	}

	@Test("The entries are the lines of the list, without the marker")
	func entries() {
		let description = "- Larger display of photoTAN images.\n- [Creating transfers](https://example.com) from a QR code.\n"
		#expect(ReleaseNoteItem.entries(of: description) == [
			"Larger display of photoTAN images.", "[Creating transfers](https://example.com) from a QR code.",
		])
	}

	@Test("A description without a list has no entries", arguments: ["", "   \n", "<p>Notes</p>", "Some text\n- Entry"])
	func noEntries(description: String) {
		#expect(ReleaseNoteItem.entries(of: description).isEmpty)
	}

	@Test("A pre-release is a version with a hyphen")
	func preRelease() {
		#expect(item("0.2.0-beta.1", build: 1).isPreRelease)
		#expect(!item("0.2.0", build: 1).isPreRelease)
	}
}
