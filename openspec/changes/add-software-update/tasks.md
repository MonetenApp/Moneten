# Tasks

A task is checked only when the check that it names passes. Every task belongs to issue #25, except group 6, which belongs to issue #13. A test feed is an appcast file and signed disk images in a local folder, served by `python3 -m http.server`, and read by a Debug build through `MONETEN_FEED_URL`.

## 1. Changelog

- [ ] 1.1 Add `CHANGELOG.md` with an "Unreleased" section and the entries of the first release. Verify that the file renders on GitHub as a flat list per version.
- [ ] 1.2 Add release-notes.py to `scripts` with the command `check`. Verify that it passes on `CHANGELOG.md` and fails, with the line number, on a nested list, on HTML, on a link without `https`, on an empty released section, and on a version that appears twice.
- [ ] 1.3 Run `release-notes.py check` in `scripts/check.sh` and in the specs job of `.github/workflows/ci.yml`. Verify that a pull request with a broken entry fails CI.
- [ ] 1.4 Add the commands `cut <version>` and `section <version>`. Verify on a copy of `CHANGELOG.md` that `cut 0.1.0` adds the date of today and a new empty "Unreleased" section, that `cut 0.2.0` after 0.2.0-beta.1 and 0.2.0-beta.2 also holds their entries once each, and that `section 0.1.0` prints exactly its entries.
- [ ] 1.5 Explain the changelog entry in `CONTRIBUTING.md`, and create a pull request template that asks for it. Verify with `python3 scripts/check-docs.py`.

## 2. Sparkle and the release notes

- [ ] 2.1 Add Sparkle 2 to the app target in `App/project.yml`, and the Info.plist keys for the feed URL, the public EdDSA key, `SURequireSignedFeed`, `SUEnableAutomaticChecks`, no silent install, and no system profile. Pin Sparkle 2.10.1 or later. Read `MONETEN_FEED_URL` in Debug builds. Verify that `scripts/build-app.sh` and Periphery pass.
- [ ] 2.2 Write the tests for `releaseNotes(installedBuild:offered:feed:)` in `Domain` first: two skipped versions, a stable version after pre-releases, a pre-release offered, and a feed that failed to load. Then write the function. Verify with `scripts/test.sh`.
- [ ] 2.3 Write the user driver with the update window: the offered and the installed version, the release notes from task 2.2, "Install", and "Remind Me Later". Render each entry as inline Markdown, and open `https` links in the default browser. Verify against a test feed with versions 0.1.1 to 0.1.3, and add light and dark snapshots to the pull request (spec: "Update window", "Release notes match the release page", "Release notes of skipped versions", "Remind later").
- [ ] 2.4 Show "Could not display release notes." when the description is empty or cannot be parsed, with "Install" still active. Verify with a test feed item without a description.
- [ ] 2.5 Add "Check for Updates..." to the application menu, with "Checking for updates...", "You're up-to-date!", and the newest version. Verify against a test feed with and without a newer version (spec: "Check for updates on request").
- [ ] 2.6 Show a failed check with its reason and the release page, and stay silent for a failed automatic check. Verify with the network off, once by the menu command and once at launch (spec: "Report a failed check").
- [ ] 2.7 Bind "Show notification about new versions of Moneten" to the automatic check, with a check at launch and every 24 hours, and every hour in a Debug build with `MONETEN_FEED_URL`. Verify with the log of the test server in a Debug build: with the setting on, a request at launch and a second one an hour later; with the setting off, no request in that hour; after "Remind Me Later", the same version again at the second request (spec: "Check for updates automatically", "Remind later").
- [ ] 2.8 Bind "Participate in beta tests and display pre-release versions" to the channel `beta`. Verify the three scenarios of "Pre-release versions on request" against a test feed with 0.1.3, 0.2.0-beta.1, and 0.2.0.
- [ ] 2.9 Set the user agent to the app version, the macOS version, and the processor type. Verify in the log of the test server that the request has no other identifying header (spec: "Update requests send no personal data").
- [ ] 2.10 Show the download progress, install, and restart. Verify with two signed test builds that version 0.1.2 with 3 accounts becomes 0.1.3 and shows the 3 accounts after unlocking (spec: "Download and install").
- [ ] 2.11 Refuse a disk image with a wrong EdDSA signature, and an app whose code signature is broken. Verify with a changed byte in the test disk image, with a test disk image without EdDSA signature that holds a build signed to run locally, and with a correctly signed disk image that holds an app with a removed resource file (spec: "Verify the update before installing it").
- [ ] 2.12 Show a failed installation with the release page, and keep the running version. Verify with an Applications folder that the user must not write to (spec: "Report a failed installation").
- [ ] 2.13 Postpone the restart while `SyncCoordinator` refreshes or a bank dialog is open. Verify with `syncdemo` of the debug harness and a ready update (spec: "No update during a bank dialog"). The payment joins this check with add-sepa-transfers.

## 3. Checks at launch

- [ ] 3.1 Ask the user to move the app to the Applications folder when the install fails because of a temporary or read-only location. Verify by starting the app from a quarantined download in the Downloads folder (spec: "Ask to move the app to the Applications folder").
- [ ] 3.2 Warn about several copies and name their folders. Verify with a second copy in the Downloads folder, and that a mounted disk image and a copy in the Trash cause no warning (spec: "Warn about several copies").
- [ ] 3.3 Refuse to open the database when the own code signature fails its check, and show the message. Verify with a copy of the app that has a removed resource file (spec: "Report a damaged application file").
- [ ] 3.4 Name the minimum macOS of the newest version when Sparkle reports that the system is too old. Verify with a test feed item that needs macOS 99 (spec: "Respect the system requirements of a new version").
- [ ] 3.5 Add the Info.plist key `MonetenTestedMacOS`, warn on a newer major version of macOS, and check for an update also with the automatic check off. Verify with the key set to 14 on macOS 15 (spec: "Warn on an untested macOS").
- [ ] 3.6 Show the version, the build number, and the mark "Pre-release" in "About Moneten" from the key `MonetenPreRelease`. Verify in a build with the key set to `beta.1` (spec: "Mark pre-release versions").

## 4. Release pipeline

- [ ] 4.1 Let `scripts/build-app.sh developer-id` sign through cloud-managed signing with an App Store Connect API key that the environment names, without a certificate on the machine. Verify on a Mac without the Developer ID certificate in the keychain that `codesign -dv` shows "Developer ID Application", and that the build through the Xcode account still works.
- [ ] 4.2 Notarize and staple the app, then build, notarize, and staple the disk image. Verify with `spctl -a -vv` and `xcrun stapler validate` (spec: "Signed and notarized app").
- [ ] 4.3 Add the command `appcast` to release-notes.py: add or replace the item of a version with the output of `sign_update`, rewrite the notes of every item from `CHANGELOG.md`, and set the channel `beta` for a pre-release. Verify that two runs with the same input write the same file, that adding 0.1.4 keeps the items of 0.1.3 and older with their signatures, that `remove 0.1.4` takes out only that item, that a run without a readable current feed fails unless it gets the flag for the first release, and that a Debug build reads the signed feed and refuses it after one changed byte.
- [ ] 4.4 Add the workflow release.yml with the steps of the design, the environment `release`, protected `v*` tags, actions pinned by commit, and a run by hand that signs nothing with the EdDSA key and publishes nothing. Verify with a run by hand that the disk image passes `spctl` on another Mac, that a tag on a commit outside `main` and a build number not above the feed fail step 1, and after the first stable release that the feed URL answers during and after the publish of a second one.
- [ ] 4.5 Write the release document in `docs`: the secrets, how to tag a version and a pre-release, how to withdraw a version, and where the offline backups of the EdDSA key are kept. Verify with `python3 scripts/check-docs.py`.

## 5. Integration

- [ ] 5.1 Publish v0.1.0 and a later test build as a pre-release. On a test Mac with the default security settings, install v0.1.0 from the release page, turn on the beta setting, and let it update. Check every scenario of the spec that groups 1 to 4 cover, and record the result in the pull request. This is the "Done when" of issue #25.

## 6. Bank data files (issue #13)

- [ ] 6.1 Write the tests first: a bank list with a good EdDSA signature is accepted, one with a wrong signature or a changed byte is rejected. Then write the check with CryptoKit in the `FinTS` library, with the public key as a parameter that `App` reads from the Info.plist. Verify with `scripts/test.sh`.
- [ ] 6.2 Fetch the bank list and the BIC directory from the release `bank-data` at most once a day, keep the current files when the check fails, and write a log entry about the rejected file. Verify with a test server that serves a good and a wrong file (spec: "Bank data files update between releases").
- [ ] 6.3 Publish signed bank data files with a workflow that runs by hand, to the release `bank-data` with `make_latest` set to false. Verify that the app of task 6.2 accepts the published files, and that the feed URL still answers after the publish.

## Workflow follow-up

- Archive the change with `openspec archive add-software-update` when every task is checked. The change stays open until both #25 and the bank data tasks of #13 are done.
