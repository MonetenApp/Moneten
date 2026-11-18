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
- [x] 2.2 Replay in the catalog checks. The catalog repository runs the signed release of `ext` that `tools/ext.lock` pins and runs `ext test` for each package. Built by [MonetenApp/moneten-extensions#10](https://github.com/MonetenApp/moneten-extensions/pull/10): the job "ext test" requires that the tag of the release names the pinned commit on `main`, checks the SHA-256 of the zip and the version line of `ext`, and replays every package and the tutorial package. [tools/ext_lock.py](https://github.com/MonetenApp/moneten-extensions/blob/26f465b6b75cf533e16cc16ef1fc556f5c937a60/tools/ext_lock.py) refuses a malformed lock. Verified in the catalog repository by [tools/tests/test_ext_lock.py](https://github.com/MonetenApp/moneten-extensions/blob/26f465b6b75cf533e16cc16ef1fc556f5c937a60/tools/tests/test_ext_lock.py) and [tools/tests/test_workflows.py](https://github.com/MonetenApp/moneten-extensions/blob/26f465b6b75cf533e16cc16ef1fc556f5c937a60/tools/tests/test_workflows.py), and by [run 44264294653](https://github.com/MonetenApp/moneten-extensions/actions/runs/44264294653), where "ext test" replayed 2 packages with ext 0.1.0 and none failed.

## 3. Release of the tool

- [x] 3.1 Version of a release. `ext --version` prints the commit of a release build and none for a build from source. Verified by `CommandTests` versionOfARelease and helpAndVersion, and by `scripts/release-ext.sh dry-run`, which checks the version line of the universal binary from the zip.
- [x] 3.2 Signed release of the tool. A tag `ext-v<version>` builds, signs, notarizes, and publishes `ext` with its SHA-256, and fails early without the secrets or with a wrong tag. Built in `.github/workflows/release-ext.yml`. The dry run passes, and `scripts/release-ext.sh check-tag` refuses another version. The first tag ran with the secrets of the environment `build` in [run 44262807544](https://github.com/MonetenApp/Moneten/actions/runs/44262807544) and published the release [ext-v0.1.0](https://github.com/MonetenApp/Moneten/releases/tag/ext-v0.1.0): `ext-0.1.0-macos.zip` with the SHA-256 `0e651a3247551bb11a94f9693136b88816a328b139cf626c7036aee740ab1ee7`, a universal binary signed with the Developer ID and notarized. `ext --version` prints "ext 0.1.0 (commit efda52da39625e4502541835e40b1b1bd7ee1dbe), API version 1".
- [x] 3.3 Install from the release. The author guide and `tools/ext.lock` of the catalog repository use the first release with its SHA-256. Built by [MonetenApp/moneten-extensions#10](https://github.com/MonetenApp/moneten-extensions/pull/10): `tools/ext.lock` pins ext 0.1.0 with its commit, the URL of its zip, and its SHA-256, and the install steps of the tutorial download the zip, check the SHA-256, unzip it, and run `./ext --version`, without Xcode.
