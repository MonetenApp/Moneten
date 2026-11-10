# Tasks

One task per requirement of the spec. A task is checked only when a test or a check in the running app shows the behavior.

## 1. Requirements

- [x] 1.1 Ask for the password at launch. Verified by debug harness: a wrong password stays locked, the right one unlocks.
- [x] 1.2 Lock by command. Verified by ⌃⌘L, the menu command, and the toolbar button call AppModel.lock; checked with the debug harness.
- [x] 1.3 A locked app shows no data. Verified by the main window shows only the lock screen, see the debug harness snapshot in the first build.
- [x] 1.4 Locking closes the database. Verified by AppModel.lock closes the store and empties the ledger.
- [ ] 1.5 Lock when the main window closes. Built in part: setting and handler exist. Finish it and verify it with a test or in the app.
- [ ] 1.6 Lock after inactivity. Built in part: setting, activity monitor, and wake check exist; the setting is on with 10 minutes by default (Settings snapshot of a new installation). Finish it and verify the lock after the time in the app.
- [ ] 1.7 Unlock automatically at launch. Built in part: reads the password from the Keychain at launch. Finish it and verify it with a test or in the app.
- [ ] 1.8 Unlock with Touch ID. Built: its own setting "Unlock with Touch ID"; the lock screen asks at once and keeps "Open with Touch ID" for another try after a cancel. Verify it in the app with a registered finger.
- [ ] 1.9 Unlock with Apple Watch. Built: its own setting "Unlock with Apple Watch"; with both settings on, one request offers both and the button reads "Open with Touch ID or Apple Watch". Verified: without a watch in range the lock screen shows "No Apple Watch was detected nearby." and the password field, in the debug harness. Verify the confirmation on a watch.
- [ ] 1.10 The password always unlocks. Built in part: the password field is always on the lock screen. Finish it and verify it with a test or in the app.
- [ ] 1.11 Unlock settings keep the password in the Keychain. Built in part: turning a setting on asks for the password and stores it; turning both off deletes it. Finish it and verify it with a test or in the app.
- [ ] 1.12 Report a Keychain failure. Built in part: the settings show the Keychain error. Finish it and verify it with a test or in the app.
- [ ] 1.13 The Keychain entry follows a password change. Built in part: Vault.changePassword replaces a stored password. Finish it and verify it with a test or in the app.
- [ ] 1.14 Explain why Touch ID is not available. Built: separate messages for a Mac without a sensor, no registered finger with "System Settings → Touch ID & Password", a lockout after failed attempts, and a closed lid; the setting stays off. Verify each message in the app.
- [ ] 1.15 No Touch ID request while the lid is closed. Built: the lock screen starts a request only for methods that macOS reports as usable, so a closed lid leaves the password field and the Apple Watch. Verify it with a closed lid on an external display.
- [ ] 1.16 Explain why the Apple Watch is not available. Built: turning the setting on without a watch approved in macOS names "System Settings → Touch ID & Password" and leaves the setting off. Verify it in the settings.
- [ ] 1.17 Clear a typed password after five minutes. Built in part: the lock screen clears the field after 300 seconds. Finish it and verify it with a test or in the app.
- [ ] 1.18 Security settings need the password. Build it and verify it with a test or in the app.
- [ ] 1.19 A locked app does no work with the data. Built in part: nothing runs in the background yet. Finish it and verify it with a test or in the app.
- [x] 1.20 Help for a forgotten password. Verified by "Forgot your password?" on the lock screen.
- [x] 1.21 Lock needs a database password. Verified by lock command and button are disabled without a password.

## 2. Integration

- [ ] 2.1 Check every scenario of the spec in a release build and record the result in the pull request.

## Workflow follow-up

- Archive the change with `openspec archive add-app-lock` when every task is checked.
