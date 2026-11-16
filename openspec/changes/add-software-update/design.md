# Design

## Context

See the proposal for why. `scripts/build-app.sh developer-id` archives the app and signs it, and the FinTS helper inside it, with the Developer ID certificate of Adanos Software GmbH in the Keychain ([ADR 0016](../../../docs/decisions/0016-developer-id-certificate-in-ci.md)). Until this change it signed through the cloud-managed certificate of Xcode, which cannot sign the Java runtime of the helper, so the helper was left out. The app has no update code yet. CI has one workflow, `.github/workflows/ci.yml`, which checks and tests pull requests. "About Moneten" in `App/Sources/Views/SettingsView.swift` shows the version and the build number. The build number is the number of commits on the branch, set by `scripts/build-app.sh`.

The app ships outside the App Store ([ADR 0006](../../../docs/decisions/0006-license-gpl-3.md)) and runs no server of the project ([ADR 0002](../../../docs/decisions/0002-local-first-no-server.md)). So the update feed and the downloads come from GitHub, and the app is not sandboxed.

## Goals / Non-Goals

**Goals:**

- One release command, a pushed tag, builds, signs, notarizes, and publishes a version and its update feed.
- The release notes are written once and reviewed in the pull request that makes the change.
- The update window follows the spec exactly, including the notes of skipped versions.

**Non-Goals:**

- Delta updates. Each update downloads the full disk image.
- Silent installs. The user always chooses "Install".
- Release notes in German. They come with add-localization-and-formatting.
- The bank list and the BIC directory themselves. The FinTS connector of issue #13 defines them. This design only fixes how they are signed and fetched.

## Decisions

### Sparkle 2 installs the updates

The app uses Sparkle 2 for the feed, the download, the check of the signature, and the installation. Sparkle is MIT licensed, so it fits the GPL. It checks two signatures before it installs: the EdDSA signature of the disk image, made with the update key of the project, and the code signature of the new app. With `SUVerifyUpdateBeforeExtraction`, which the signed feed below requires, Sparkle checks the disk image before it opens it. The EdDSA signature must match the key of the running app. Sparkle would also accept a disk image signed with the Developer ID of the running app instead of an EdDSA signature. The release workflow signs the disk image with the Developer ID too, so that Gatekeeper accepts the download. That opens no way past the update key: the signed feed names the EdDSA signature of each disk image, and nobody without the update key can change the feed. The new app inside must then have a valid code signature, of any identity (`SUUpdateValidator`). That is the requirement "Verify the update before installing it". So the EdDSA private key alone can sign an update that installs, and it is the most critical secret of the project.

A Debug build trusts a test key instead: the configuration Debug in `App/project.yml` sets its public key. Its private key is public on purpose, in `Fixtures/update`, so every contributor and the dry run can sign test feeds with it. That is safe because a Debug build looks for updates only in the feed that `MONETEN_FEED_URL` names, and a Release build never carries the test key. So the local test feeds and test disk images of the tasks are signed with the test key and never need the production key. `scripts/update-test-feed.sh` writes them with `release-notes.py appcast` and `sign_update`, as a release does.

A Release build carries the production key, which the owner commits in `App/project.yml` in place of the placeholder `none`. A build with the placeholder does not start Sparkle, and its update settings are off. `scripts/release.sh preflight` fails while the placeholder is there, the release workflow fails right after step 2 when the Info.plist of the exported app does not carry the committed production key or carries the test key, and step 5 fails when the private key of the secret does not belong to the public key in the app.

Sparkle 2.10.1 or later is a package of the app target in `App/project.yml`, not of the root package. Only `App` uses it, and the libraries stay free of it.

The feed is signed too. `SURequireSignedFeed` in the Info.plist makes Sparkle refuse a feed without a valid EdDSA signature of the update key. Sparkle starts the updater with it only together with `SUVerifyUpdateBeforeExtraction`, so the Info.plist sets both. Without more, Sparkle falls back after 20 days of failed feed signatures and then also accepts a disk image signed only by the Developer ID of the same team. `SUSignedFeedFailureExpirationInterval` is 0, so that fallback never starts. The update key also signed every older feed, so someone who serves an old feed could offer a version that a newer feed took out. So every feed has a revision, which `release-notes.py` raises by one with each write, a withdrawal too. The app keeps the highest revision that it read and refuses a feed with a lower one (`FeedRevision`). The newest build is no such measure: a withdrawal of the stable build 110 can keep the pre-release build 120, so a replay of the feed before it has the same newest build, and Sparkle drops the channels that the user did not choose only after the app checked the feed (`SUAppcastDriver.m`). Sparkle hands the app only the items, so each item carries the revision of the feed as `moneten:revision`, and a feed without items has none. So `remove` never takes out the last version: the fixed version is released first. A feed whose items lack a revision is refused. So nobody who can only edit a release page can change the notes or their links. The notes go into the feed as XML text, so an entry with `<` or `&` cannot break it.

Alternative: our own updater. Replacing a running, signed app bundle safely is the hard part, and Sparkle has solved it for many years. Rejected.

### Our own update window

`App` implements the user driver of Sparkle, the protocol through which Sparkle shows every window and message. The update window, the progress, and every message are SwiftUI views of our own. Sparkle keeps the feed, the download, and the installation.

The standard window of Sparkle does not fit the spec. It always offers "Skip This Version", it shows only the notes of the offered version, and its strings differ from those of the spec. Its notes view is a web view that renders HTML from the network. Our window renders a plain list instead.

### `CHANGELOG.md` is the only source of the release notes

The repository gets a `CHANGELOG.md`. Its format is strict, so that a script can read it:

```markdown
# Changelog

## Unreleased

- **Moneten now needs macOS 15 or later.**

## 0.2.0-beta.1 (2026-12-01)

- [Creating transfers](https://github.com/MonetenApp/Moneten/wiki/Transfers) from a QR code.

## 0.1.3 (2026-11-20)

- Larger display of photoTAN images.
- Fixed the sum of a split transaction.
```

- One heading of level 2 per version, with the version without the `v` of the tag and the release date in parentheses, for example `0.2.0-beta.1 (2026-12-01)`. The topmost section is "Unreleased".
- A section holds only a flat list of entries. An entry is one line of inline Markdown: bold, code, and links with `https`. No nested lists, no headings inside a section, and no HTML.
- A pull request with a change that users notice adds its entry under "Unreleased", in the language of the users, not of the code.

A script, `scripts/release-notes.py`, owns the format. These are its main commands, and `scripts/test-release-notes.py` tests them:

- `check` fails on any line that breaks the format, on an empty released section, and on a version that appears twice. `scripts/check.sh` and the specs job of CI run it on every pull request.
- `cut <version>` renames "Unreleased" to the version with the date of today and opens a new empty "Unreleased" section. For a stable version, it also moves the entries of its pre-releases (for 0.2.0, those of 0.2.0-beta.1 and 0.2.0-beta.2) into the new section, without duplicates, and leaves the pre-release sections as they are. So the notes of a stable version list everything since the last stable version.
- `section <version>` prints the entries of one version. The release workflow uses it as the text of the GitHub release.
- `appcast` writes the update feed, as described below.
- `remove <version>` takes the item of a version out of the feed, to withdraw it, and raises the revision. It first runs the checks of `check-feed` with the public update key, because the owner signs the result, and a new signature must never cover a forged item. It refuses to take out the last version. `scripts/release.sh withdraw` runs it, signs the result, checks it again with the committed update key, and only then uploads it.
- `check-feed` checks that the update key signed a feed and that every disk image in it lies in a release of the repository.
- `check-newer` checks that a feed has a higher revision than the current feed and lists every version of it, so a draft made before another release or a withdrawal never replaces the current feed.
- `check-release <version>` runs the checks of step 1 of the release workflow: a section for the version, and a build number and a version above every item of the current feed.

Alternatives: notes that GitHub generates from the titles of pull requests, which are written for developers. Notes typed into the release page, which no review sees and which drift from the feed. Both rejected.

### The feed is an asset of the newest stable release

The feed URL is `https://github.com/MonetenApp/Moneten/releases/latest/download/appcast.xml`. GitHub resolves "latest" to the newest stable release, so the feed lives there as a file named `appcast.xml`. The disk images are assets of their own releases. A stable version is created as a draft, gets its disk image and the new feed, and only then is published, so "latest" never points to a release without a feed. A pre-release replaces the feed on the newest stable release. Every other release, such as `bank-data`, is created with `make_latest` set to false, because GitHub marks a new release as latest by default and the feed URL would then break.

`release-notes.py appcast` reads the current feed, adds or replaces the item of the new version, and then rewrites the notes of every item from `CHANGELOG.md`. So it is idempotent, and a fix to an old entry reaches the feed with the next release. It fails when it cannot read the current feed, unless it gets the flag for the first release, so a failed run never starts an empty feed. `sign_update` of Sparkle then signs the feed with the update key, and `scripts/release.sh` runs both. The URL of each disk image names its own release, `releases/download/v0.1.3/...`, never `latest`. Each item carries:

- the build number as the version that Sparkle compares, and the full version for display, with `-beta.N` for a pre-release,
- the date of its changelog heading,
- the entries of its section as Markdown in the description,
- the minimum macOS version from the Info.plist of the build,
- the EdDSA signature and the size, from the `sign_update` tool of Sparkle,
- the channel `beta` for a pre-release,
- the revision of the feed: 1 for the first feed, and one above the current feed for every later one.

Alternative: GitHub Pages. That needs a second hosting setup, and a URL under `github.io` breaks when the repository moves to an organization. GitHub redirects URLs under `github.com` after a move. Rejected.

### Versions and build numbers

A release starts with a tag on `main`: `v0.1.3` for a stable version, `v0.2.0-beta.1` for a pre-release. The marketing version is the part before the hyphen. The part after it goes into the Info.plist key `MonetenPreRelease`, so "About Moneten" shows "0.2.0-beta.1 (412)" and the mark "Pre-release". The build number stays the number of commits on `main`. It only grows, so Sparkle never offers an older build, and a user who leaves the beta stays on 0.2.0-beta.1 until 0.2.0 has a higher build number. The release workflow checks out the full history, because a shallow clone counts wrong.

Alternative: the full version with the hyphen as `CFBundleShortVersionString`. Apple tools expect three numbers there. Rejected.

### Choosing the notes of skipped versions

Sparkle hands the user driver only the item it offers. The delegate of the updater also receives the whole feed after each load, and the window takes the other items from there.

The choice is a pure function in `Domain`, so tests prove it in milliseconds:

```swift
public struct ReleaseNoteItem: Sendable, Equatable {
	public let build: Int
	public let version: String
	public let date: Day
	public let isPreRelease: Bool
	public let entries: [String]
}

public func releaseNotes(installedBuild: Int, offered: ReleaseNoteItem, feed: [ReleaseNoteItem]) -> [ReleaseNoteItem]
```

It returns the items with a build number above the installed one and up to the offered one, newest first. When the offered item is stable, it leaves out pre-releases. It also leaves out a pre-release of a stable version that is in the list, such as 0.2.0-beta.1 when 0.2.0 is there, because `cut` put its entries into that stable version. When the feed failed to load, it returns the offered item alone.

The window renders each entry as `AttributedString` with inline Markdown. A link opens in the default browser, and only links with `https` are active. If the description of the offered item is empty or cannot be parsed, the window shows "Could not display release notes." and "Install" stays active.

### Settings, schedule, and the request

- "Show notification about new versions of Moneten" is the automatic check of Sparkle, on by default. With the setting on, the app starts a background check at every launch, and the scheduler of Sparkle checks every 24 hours. The Info.plist sets `SUEnableAutomaticChecks`, so Sparkle never asks for permission. With the setting off, Sparkle sends no request, except the one check at launch on an untested macOS.
- "Participate in beta tests and display pre-release versions" makes the delegate allow the channel `beta`. It is off by default.
- Silent installs and the system profile of Sparkle are off in the Info.plist.
- The app sets the user agent to the app version, the macOS version, and the processor type, for example "Moneten/0.1.3 (macOS 15.2; arm64)". Sparkle sends no other data. GitHub still sees the IP address of the request, as for any download.
- A Debug build reads the feed URL from the environment variable `MONETEN_FEED_URL`, so a local feed can test every window and failure. With that variable set, it checks every hour, the shortest interval that Sparkle allows.

### No restart during bank work

The delegate of the updater postpones the restart while `SyncCoordinator` refreshes, while a bank dialog is open, and later while a payment is in progress. It resumes the installation when that work ends. A refresh that starts later waits for the installation instead.

### Checks at launch

Before the database opens, `App` runs these checks in this order:

1. The application file is damaged: the code signature of the own bundle fails its check against the designated requirement of the running app, with every sealed resource. The app shows the message and opens no database. `AppSeal` in the `FinTS` library does the check, because the FinTS connector runs the same check before each start of its helper (task 3.2 of add-fints-banking).
2. More than one copy: Launch Services knows more than one app with the bundle identifier of Moneten, not counting copies on a disk image, on a read-only volume, or in the Trash. The warning names the folders. Debug and Perf builds skip this check, because a developer has many builds on the Mac.
3. Untested macOS: the major version of the running macOS is higher than the Info.plist key `MonetenTestedMacOS`. The checklist of each release in the release document has the item: set the key to the major version of macOS that the release candidate was tested on. The app then checks for an update, also with the automatic check off.

The warnings of checks 2 and 3 appear in the update window, so they need no unlocked database. They open after SwiftUI has built the scenes of the app, because a window that opens during that build stops the app.

The other cases come from Sparkle. A temporary or read-only location makes the install fail before it starts, and the window asks the user to move the app to the Applications folder. A newest version that needs a newer macOS comes back as "no update found" with the reason "system is too old" and the item, so the window can name its minimum macOS.

### The release workflow

A new workflow, `.github/workflows/release.yml`, runs on a pushed tag. Each step is a command of `scripts/release.sh`, so the owner can run every step on a Mac as well.

1. Check out the full history. Check that the tag matches a section of `CHANGELOG.md`, that the tagged commit is on `main`, that its build number is higher than every item of the current feed and not lower than an item of the same version, so a tag moved to an older commit cannot replace a build, and that its version is higher than every version in the feed, so a stable 0.1.4 never follows 0.2.0-beta.1 and a beta tester is never offered a lower version. The first release has no feed yet. Only an answer of GitHub that no stable release exists skips the feed check, so a network error never starts an empty feed.
2. Archive and export the app with `scripts/build-app.sh developer-id`. It signs the app, the extension host, and the FinTS helper with its Java runtime with the Developer ID certificate that the workflow imports into a temporary Keychain, with the hardened runtime and a secure timestamp ([ADR 0016](../../../docs/decisions/0016-developer-id-certificate-in-ci.md)). Only the java of the helper gets `allow-jit` ([ADR 0014](../../../docs/decisions/0014-fints-through-hbci4java.md)). Then check that the app carries the Developer ID, the hardened runtime, and the FinTS product ID, and, once the app has Sparkle, the production update key. The job that holds the Developer ID and the notary key installs no tool whose version floats: `scripts/build-tools.sh` downloads the pinned XcodeGen and the pinned Temurin JDK, whose `jlink` runtime ships inside the app, and checks the SHA-256 of each. The JDK line of `Tools/FinTSProbeJava/dependencies.lock` pins its build.
3. Notarize the app with `notarytool` and the App Store Connect API key, and staple the ticket.
4. Put the app on a disk image with a link to the Applications folder, sign the disk image with the Developer ID, notarize it, and staple it. Mount it and check the app on it: its signature, its version, that Gatekeeper accepts it as notarized, and that the java of the FinTS helper starts with the pinned runtime.
5. After the approval of the owner, sign the disk image with the EdDSA key, and write and sign the feed. The new feed keeps the items of the current feed, so the step first checks that the update key signed the current feed and that every disk image in it lies in a release of the repository, over https. A forged item can then never reach a feed that the update key signs.
6. Create the GitHub release as a draft with the disk image, the feed, the changelog heading as its title, for example "0.1.3 (2026-11-20)", and the text of `release-notes.py section`, marked as a pre-release for a beta.
7. The owner checks the draft and runs `scripts/release.sh publish <version>`. It checks the signature of the draft's feed, of the current feed, and of the published feed with the update key, so a feed that was changed after step 5 never goes out. It checks that the feed of the draft has a higher revision than the current feed and contains every version of it, so a release or a withdrawal in the meantime is never undone. For a stable version, it publishes the draft as the newest release, which already carries the feed. For a pre-release, it publishes the draft and replaces the feed on the newest stable release. It reads the text of every release in one listing and edits only the releases whose section in `CHANGELOG.md` changed, so the release pages and the feed stay the same. After a key change, a stable version also carries the frozen old feed, and a pre-release replaces only `appcast-2.xml` and never the frozen `appcast.xml`, see the risks.

Publishing is a command of the owner and not a step of the workflow, so that a person opens the notarized disk image before any user can get it.

A pull request that changes the packaging and a run by hand make a dry run, `scripts/release.sh dry-run`, which needs no secret: the app signed to run locally, an unsigned disk image with the same checks, and a feed signed with the test update key, which a Debug build reads. The check of step 5 must accept that feed and refuse it after one changed byte, under another key, and with a disk image over http. The path of a withdrawal must refuse an unsigned feed and a signed feed with a disk image over http. A run by hand with the input "notarize" also signs and notarizes with the environment `build`. A dry run signs nothing with the update key and publishes nothing. Only a tag hands its disk image to the job of step 5, as an artifact of the run that GitHub keeps for one day, so no build that was never released lies in the artifacts.

The secrets live in two GitHub environments. `build` holds the Developer ID certificate as a `.p12` file with its password, the App Store Connect API key for `notarytool`, and the FinTS product ID, and allows `main` and `v*` tags. `release` holds the EdDSA key, allows only `v*` tags, and needs the approval of the owner. The `v*` tags are protected. Third-party actions are pinned by commit. Only the owner of the repository can set the secrets. [docs/releasing.md](../../../docs/releasing.md) lists them, how the owner creates each one, and the steps for a release.

### Bank data files use the same key

The bank list and the BIC directory are assets of a release with the fixed tag `bank-data`, created with `make_latest` set to false, each with an EdDSA signature beside it. The app checks a file against the public update key in its Info.plist with CryptoKit before it uses it. The check is a function in the `FinTS` library that takes the file, the signature, and the public key as `Data`, with tests for a good signature, a wrong signature, and a changed file. `App` reads the key from the Info.plist and passes it. `Domain` stays free of CryptoKit. The FinTS connector of issue #13 owns the fetch and the use of the files.

## Risks / Trade-offs

- [The EdDSA private key is lost] → No update can be signed, and every user must download the next version by hand. Keep the key in the GitHub secret and in two offline backups that the owner holds.
- [The EdDSA private key leaks] → An attacker can sign a disk image that installs, if the app in it has any valid code signature, for example one of another Developer ID. The attacker can also sign a bank list that points the FinTS address of a bank to another server and so collects PINs. Keep the key only in the environment `release` and in the offline backups. After a leak, publish at once a recovery release that is signed with the old key, carries a new public key and a new feed URL, `appcast-2.xml`, and refuses every bank data file signed with the old key. The old `appcast.xml` stays signed with the old key and from then on offers only the recovery release. The recovery release carries the frozen `appcast.xml` and the first `appcast-2.xml`. Both get a revision above the last one of the old feed, because every installed copy keeps the highest revision that it read. Because the feed URL follows the newest stable release, step 7 copies that frozen `appcast.xml` to every later stable release next to `appcast-2.xml`, so an installation that was offline during the change still reaches the recovery release. Every later version is in the new feed, signed with the new key. Announce the change.
- [The Developer ID certificate leaks] → An attacker can sign apps and disk images in the name of the project and ship them outside the update. That alone does not pass Sparkle, because the signed feed names the EdDSA signature of each disk image. Keep the `.p12` file only in the environment `build` and in the offline backups. Revoke the certificate in the Apple Developer account, create a new one, and replace the secret. The App Store Connect API key only notarizes. It has the role Developer, which cannot create certificates. Revoke it in App Store Connect if it leaks.
- [Every shipped build contains the feed URL] → A rename or a move of the repository relies on the redirects of GitHub. Never reuse the old name.
- [A pull request forgets its changelog entry] → The pull request template asks for it, and the reviewer checks it. `release-notes.py check` cannot know whether users notice a change.
- [A broken release reaches every user within a day] → Ship to the beta channel first. Sparkle never downgrades, so the fix is a new version with a higher build number. Removing the item from the feed stops further installs.
- [The update window is our own code] → More code than the standard window. In return the window matches the spec and renders no HTML from the network.

## Migration Plan

Builds before the first release have no Sparkle and update by hand. The first notarized release is v0.1.0, and every later version updates itself. To withdraw a version, `scripts/release.sh withdraw` removes its item from the checked feed, and the owner publishes a fixed version with a higher build number.

## Open Questions

- Release notes in German follow the localization of add-localization-and-formatting. A second changelog file per language fits the format above.
