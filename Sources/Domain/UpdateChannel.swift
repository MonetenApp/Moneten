/// The channels of the update feed. `scripts/release-notes.py appcast` puts a pre-release into the
/// channel `beta` and a stable version into no channel, which every installation reads.
public enum UpdateChannel {
	public static let beta = "beta"

	/// The channels that the updater reads besides the items without a channel. "Participate in beta
	/// tests and display pre-release versions" adds `beta`. Sparkle never offers a build below the
	/// installed one, so turning the setting off keeps an installed pre-release until a newer stable
	/// version is published (spec: "Pre-release versions on request").
	public static func allowed(preReleases: Bool) -> Set<String> {
		preReleases ? [beta] : []
	}
}
