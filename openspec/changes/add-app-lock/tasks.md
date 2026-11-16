# Tasks

One task per requirement of the spec. A task is checked only when a test or a check in the running app shows the behavior.

## 1. Requirements

- [x] 1.1 Ask for the password at launch. Verified by debug harness: a wrong password stays locked, the right one unlocks.
- [x] 1.2 Lock by command. Verified by ⌃⌘L, the menu command, and the toolbar button call AppModel.lock; checked with the debug harness.
- [x] 1.3 A locked app shows no data. Verified by the main window shows only the lock screen, see the debug harness snapshot in the first build.
- [x] 1.4 Locking closes the database. Verified by AppModel.lock closes the store and empties the ledger.
- [x] 1.5 Lock when the main window closes. Verified by the debug harness: with the setting on, "closemain" and "openmain" show the lock screen (phase locked). The setting is off by default (#269).
- [x] 1.6 Lock after inactivity. Verified by the debug harness: with "Lock after 1 minute of inactivity" and no input, the app locked 74 seconds after the unlock (the check runs every 20 seconds). The setting is on with 10 minutes by default (Settings snapshot of a new installation). The wake check compares the clock, so time asleep counts; a real sleep of the Mac was not part of the check (#269).
- [x] 1.7 Unlock automatically at launch. Verified by the debug harness: with the setting on and the password in the Keychain, the next launch opens the main window without a prompt. A Keychain error or a stored password that no longer opens the database leads to the lock screen with the reason, and the unlock with the password stores it again (#266). The launch reads only the Keychain entry of the automatic unlock, which only the settings write: AppLockStorageTests "A password stored for Touch ID does not unlock at launch", and the debug harness: with only Touch ID on, a settings file changed to turn on the automatic unlock leaves the lock screen and turns the toggle off (#269).
- [ ] 1.8 Unlock with Touch ID. Built: its own setting "Unlock with Touch ID"; the lock screen asks at once and keeps "Open with Touch ID" for another try after a cancel. Verify it in the app with a registered finger.
- [ ] 1.9 Unlock with Apple Watch. Built: its own setting "Unlock with Apple Watch"; with both settings on, one request offers both and the button reads "Open with Touch ID or Apple Watch". Verified: without a watch in range the lock screen shows "No Apple Watch was detected nearby." and the password field, in the debug harness. Verify the confirmation on a watch.
- [x] 1.10 The password always unlocks. Verified by the debug harness: with "Unlock with Apple Watch" on and no watch nearby, the lock screen shows "No Apple Watch was detected nearby." and the password field, and the password unlocks. A Keychain error or a stored password that no longer opens the database also leaves the password field with the reason (#266, #269).
- [x] 1.11 Unlock settings keep the password in the Keychain. Verified by the debug harness command "security", which runs the change of the password prompt: turning on "Unlock automatically at application start" stores the password, turning on Touch ID and then off the automatic unlock keeps it, and turning off the last setting deletes it (#269). Each setting has its own entry: AppLockStorageTests "Turning a method off deletes only its entry", "A forged setting turns nothing on", and "A wrong password changes no entry", and the debug harness: turning off the automatic unlock with Touch ID on keeps the entry of Touch ID, and the next launch asks (#269).
- [ ] 1.12 Report a Keychain failure. Built: a failed store leaves the setting off, and a failed delete leaves the last setting on, each with the error of the Keychain under the settings. The lock screen shows a Keychain error of the automatic unlock (#266, #269). Verify it in the app with a Keychain that refuses the entry.
- [x] 1.13 The Keychain entry follows a password change. Verified by OpeningTests "A restored backup with an older password replaces the newer password in the Keychain after the unlock", whose change of the password replaces the stored one. A change that the Keychain does not accept is reported, and the next unlock with the password stores it again (#266). Every entry follows: AppLockStorageTests "A password change replaces each stored entry, and an unlock replaces a stale entry but creates none" (#269).
- [ ] 1.14 Explain why Touch ID is not available. Built: separate messages for a Mac without a sensor, no registered finger with "System Settings → Touch ID & Password", a lockout after failed attempts, and a closed lid; the setting stays off. Verify each message in the app.
- [ ] 1.15 No Touch ID request while the lid is closed. Built: the lock screen starts a request only for methods that macOS reports as usable, so a closed lid leaves the password field and the Apple Watch. Verify it with a closed lid on an external display.
- [ ] 1.16 Explain why the Apple Watch is not available. Built: turning the setting on without a watch approved in macOS names "System Settings → Touch ID & Password" and leaves the setting off. Verify it in the settings.
- [ ] 1.17 Clear a typed password after five minutes. Built: the lock screen clears the field 300 seconds after the last change of its text. Verify it in the app; the debug harness cannot type into the lock screen.
- [x] 1.18 Security settings need the password. Verified by the debug harness command "security": a wrong password leaves "Lock when main window is closed" off and "Lock after inactivity" at 10 minutes, and the right one changes them. Every toggle and the picker of the tab open "Enter Database Password" first (settings snapshot) (#269). The lock settings live in the encrypted database: AppLockStorageTests "The lock settings stay in the encrypted database across a reopen", and the debug harness: with both lock settings on and the settings file changed to turn them off, closing the main window and 85 seconds without input each lock the app (#269).
- [x] 1.19 A locked app does no work with the data. Verified by AutoRefreshTests "A locked app runs nothing, and the unlock runs the accounts that became due meanwhile". The lock cancels refreshes, a rule run, a file import, and an export, and closes the database. Statements and automation requests do not exist yet (#269).
- [x] 1.20 Help for a forgotten password. Verified by "Forgot your password?" on the lock screen.
- [x] 1.21 Lock needs a database password. Verified by lock command and button are disabled without a password.

## 2. Integration

- [ ] 2.1 Check every scenario of the spec in a release build and record the result in the pull request.

## Workflow follow-up

- Archive the change with `openspec archive add-app-lock` when every task is checked.
