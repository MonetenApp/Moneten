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

- [ ] 2.1 Author guide. The catalog repository builds it.
- [ ] 2.2 Replay in the catalog checks. The catalog repository builds `ext` at a pinned commit and runs `ext test` for each package.
