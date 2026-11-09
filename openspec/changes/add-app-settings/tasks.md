# Tasks

One task per requirement of the spec. A task is checked only when a test or a check in the running app shows the behavior.

## 1. Requirements

- [x] 1.1 One settings window. Verified by ⌘, with the tabs "Security" and "General".
- [ ] 1.2 A tab appears with its settings. Built in part: two tabs in this build. Finish it and verify it with a test or in the app.
- [x] 1.3 Changes take effect at once. Verified by settings are read when they apply.
- [x] 1.4 Settings survive restarts and updates. Verified by stored in the user defaults.
- [x] 1.5 Settings hold no personal data. Verified by only switches and numbers.
- [ ] 1.6 Report a setting that cannot be stored. Built in part: Keychain errors only. Finish it and verify it with a test or in the app.
- [ ] 1.7 Explain settings with consequences. Built in part: a note under the security settings. Finish it and verify it with a test or in the app.
- [ ] 1.8 Settings need an unlocked app. Build it and verify it with a test or in the app.

## 2. Integration

- [ ] 2.1 Check every scenario of the spec in a release build and record the result in the pull request.

## Workflow follow-up

- Archive the change with `openspec archive add-app-settings` when every task is checked.
