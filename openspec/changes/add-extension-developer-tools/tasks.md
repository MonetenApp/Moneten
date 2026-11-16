# Tasks

One task per requirement of the spec. A task is checked only when a test or a run of `ext` shows the behavior.

## 1. The ext tool

- [x] 1.1 Run an extension outside the app. Verified by `CommandTests` runPrintsJSONAndSendsPrintToStandardError and choiceOfTheService.
- [x] 1.2 Login data in the terminal. Verified by `CommandTests` loginDataFromTheTerminal and the environment variables in every run test; the hidden password by a run in a terminal.
- [x] 1.3 Challenges in the terminal. Verified by `CommandTests` challengesInTheTerminal and decoupledApprovalWaitsUntilTheScriptReturns.
- [x] 1.4 Result as JSON. Verified by `CommandTests` runPrintsJSONAndSendsPrintToStandardError.
- [x] 1.5 Same limits as in the app. Verified by `CommandTests` hostOutsideTheManifest.
- [x] 1.6 LocalStorage of the tool. Verified by `CommandTests` localStorageSurvivesAndFreshStartsEmpty and `RecordTests` runKeepsLocalStorageNextToTheScript.
- [x] 1.7 Record a run. Verified by `RecordTests` recordLeavesNoSecretAndReplaysOffline against a made-up bank on https://bank.localhost.
- [x] 1.8 Recordings contain no secrets. Verified by `ScrubberTests` and `RecordTests`.
- [x] 1.9 Warning about personal data in a recording. Verified by `RecordTests` recordLeavesNoSecretAndReplaysOffline.
- [x] 1.10 Replay a recording as a test. Verified by `ReplayTests` exampleExtensionPasses and differenceExitsWithOne, and `JSONDiffTests`.
- [x] 1.11 No network during a replay. Verified by `ReplayTests` under a sandbox that refuses the network, and missingRequestNamesMethodAndURL.
- [x] 1.12 Repeatable replays. Verified by `ReplayTests` thirtyDaysFromTheRecordedClock in three time zones and recordedRandomValuesAndAnswers.
- [x] 1.13 Exit status. Verified by `CommandTests` wrongArguments, rejectedLogin, and scriptError, and `ReplayTests` differenceExitsWithOne.
- [x] 1.14 Help and version. Verified by `CommandTests` helpAndVersion.
- [x] 1.15 Example extension with a test. Verified by the step "Example extension" of CI and `scripts/check.sh`.

## 2. Catalog repository

- [x] 2.1 Author guide. The catalog repository builds it. Built by MonetenApp/moneten-extensions#2 (8f143f0) in [docs/guide](https://github.com/MonetenApp/moneten-extensions/tree/main/docs/guide): tutorial, reference, manifest, rules, submit, and from-moneymoney. The reference names the three final redirect addresses and the login host in `hosts`. Verified in the catalog repository by [tools/tests/test_guide.py](https://github.com/MonetenApp/moneten-extensions/blob/main/tools/tests/test_guide.py), which checks the links, the manifest examples, and that the tutorial steps make the tutorial package, and by the job "ext test", which replays the tutorial package with `ext`. Both jobs passed on 8f143f0.
- [ ] 2.2 Replay in the catalog checks. The catalog repository builds `ext` at a pinned commit and runs `ext test` for each package.

## 3. Release of the tool

- [x] 3.1 Version of a release. `ext --version` prints the commit of a release build and none for a build from source. Verified by `CommandTests` versionOfARelease and helpAndVersion, and by `scripts/release-ext.sh dry-run`, which checks the version line of the universal binary from the zip.
- [ ] 3.2 Signed release of the tool. A tag `ext-v<version>` builds, signs, notarizes, and publishes `ext` with its SHA-256, and fails early without the secrets or with a wrong tag. Built in `.github/workflows/release-ext.yml`. The dry run passes, and `scripts/release-ext.sh check-tag` refuses another version. Stays open until the first tag runs with the secrets of the environment `build`.
- [ ] 3.3 Install from the release. The author guide and `tools/ext.lock` of the catalog repository use the first release with its SHA-256.
