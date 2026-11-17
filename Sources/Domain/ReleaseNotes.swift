/// One version of the update feed, as the update window shows it.
public struct ReleaseNoteItem: Sendable, Equatable {
	/// The build number, which Sparkle compares. It only grows.
	public let build: Int
	/// The full version for display, such as 0.2.0-beta.1.
	public let version: String
	/// The date of the heading of the version in `CHANGELOG.md`.
	public let date: Day
	/// The entries of the version as inline Markdown. Empty when the description could not be read.
	public let entries: [String]

	public init(build: Int, version: String, date: Day, entries: [String]) {
		self.build = build
		self.version = version
		self.date = date
		self.entries = entries
	}

	/// The release workflow gives a pre-release a version with a hyphen, such as 0.2.0-beta.1.
	public var isPreRelease: Bool { version.contains("-") }

	/// The stable version that a pre-release leads to: 0.2.0 for 0.2.0-beta.1.
	var stableVersion: Substring { version.prefix { $0 != "-" } }

	/// The entries of a description that `scripts/release-notes.py appcast` wrote: one line "- entry"
	/// per entry. Any other line means the description is not ours, and nothing is shown of it.
	public static func entries(of description: String) -> [String] {
		let lines = description.split(whereSeparator: \.isNewline).filter { !$0.allSatisfy(\.isWhitespace) }
		guard lines.allSatisfy({ $0.hasPrefix("- ") }) else { return [] }
		return lines.map { String($0.dropFirst(2)) }
	}
}

/// The versions whose notes the update window shows, newest first: those above the installed build
/// up to the offered one. A stable offer leaves out pre-releases, and a pre-release of a listed
/// stable version is left out, because `release-notes.py cut` put its entries into that version.
/// An empty feed, after a failed load, gives the offered version alone.
public func releaseNotes(installedBuild: Int, offered: ReleaseNoteItem, feed: [ReleaseNoteItem]) -> [ReleaseNoteItem] {
	var items = feed.filter { $0.build > installedBuild && $0.build < offered.build }
	if !offered.isPreRelease { items.removeAll(where: \.isPreRelease) }
	items.append(offered)
	let stable = Set(items.filter { !$0.isPreRelease }.map(\.version))
	items.removeAll { $0.isPreRelease && stable.contains(String($0.stableVersion)) }
	return items.sorted { $0.build > $1.build }
}
