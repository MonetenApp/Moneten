# Tasks

One task per requirement of the spec. A task is checked only when a test or a check in the running app shows the behavior.

## 1. Requirements

- [x] 1.1 One settings window. Verified by ⌘, with the tabs "Security" and "General".
- [x] 1.2 A tab appears with its settings. Verified in a debug build through the debug harness: ⌘, opens the window with the tabs "General" and "Security" in the order of the spec, and light and dark snapshots show every setting of both tabs whose capability this version has. Version 0.1 has no payments and no subscription, so "Payments" and "Subscription" do not appear. The two switches of `software-update` come with its tasks 2.7 and 2.8.
- [x] 1.3 Changes take effect at once. Verified by settings are read when they apply.
- [x] 1.4 Settings survive restarts and updates. Verified by stored in the user defaults.
- [x] 1.5 Settings hold no personal data. Verified by only switches and numbers.
- [x] 1.6 Report a setting that cannot be stored. Verified by `StoredSettingTests` (a forced key, an ignored write, a value that a launch argument overrides, and the defaults of the app for "Language") and in a debug build started with `-showMenuBarIcon NO`: turning on "Show Moneten icon in menu bar" shows "macOS did not keep this change" below it, and the switch stays off. Turning off the last unlock setting deletes the Keychain entry before the switch turns off, so a Keychain error leaves the switch on with the error; the harness showed the normal path, the entry gone and the switch off. The lock switch and the inactivity picker still write to the user defaults without the check, because pull request #269 moves them into the database.
- [x] 1.7 Explain settings with consequences. Verified by light and dark snapshots: "Automatically refresh accounts" explains that it follows "Refresh" in the account settings while Moneten runs and is unlocked, the unlock settings explain that "Unlock automatically at application start" opens Moneten without the password for anyone who uses the user account, and "Language" says that it needs a restart. The note of the "Payments" scenario comes with the payment features.
- [x] 1.8 Settings need an unlocked app. Verified by `scripts/check-debug-log.sh`: ⌘, opens the settings while the app is unlocked, a lock closes them, also while the password prompt of an unlock setting is open, the prompt does not come back after the unlock, ⌘, opens nothing while the app is locked, and the window closes again when it comes on screen while the app is locked. The harness also showed "Settings..." disabled in the application menu while locked.

## 2. Integration

- [ ] 2.1 Check every scenario of the spec in a release build and record the result in the pull request.

## Workflow follow-up

- Archive the change with `openspec archive add-app-settings` when every task is checked.
