# Tasks

One task per requirement of the spec. A task is checked only when a test or a check in the running app shows the behavior.

## 1. Requirements

- [x] 1.1 One data folder with three subfolders. Verified by DataFolder.createFolders.
- [x] 1.2 Only the user can read the data folder. Verified by folders are created with permissions 700.
- [x] 1.3 Show the data folder in the Finder. Verified by "Show Database in Finder..." in the Help menu.
- [x] 1.4 The data folder is separate from the application file. Verified by ~/Library/Application Support/Moneten.
- [x] 1.5 A copy of the data folder is a complete backup. Verified by VaultTests "A backup opens with the same password".
- [x] 1.6 Back up the database while the app runs. Verified by "Backup Database..." in the Tools menu.
- [x] 1.7 Explain what the backup command covers. Verified by the save panel explains it.
- [x] 1.8 A backup opens with the password of its time. Verified by VaultTests "A backup opens with the same password".
- [x] 1.9 Warn about a backup without a password. Verified by the debug harness command "backup": without a database password, "Backup Database..." first warns "No database password is set." with "Set Database Password...", "Back Up Anyway", and "Cancel". "Cancel" saves nothing, "Set Database Password..." opens its sheet, and "Back Up Anyway" saves the copy (2026-11-18).
- [x] 1.10 Restore a database file. Verified by OpeningTests "A restored backup with an older password replaces the newer password in the Keychain after the unlock", SentinelPINTests, which open a backup in a clean data folder with the password alone, and the debug harness: with "Unlock automatically at application start" on and another password in the Keychain, the lock screen explains it, and after the unlock the next launch opens without a prompt (#266).
- [x] 1.11 Move to another Mac. Verified by OpeningTests "A data folder copied to another Mac opens with the same password, and the two copies stay independent" (#266).
- [x] 1.12 No synchronization between copies. Verified by OpeningTests "A data folder copied to another Mac opens with the same password, and the two copies stay independent". The app has no code that sends data to another Mac (#266).
- [x] 1.13 Reset after a lost password. Verified by OpeningTests "Renaming the folder Database starts a new database, and renaming it back opens the old data with the old password" and "A new database keeps the Keychain entries that a renamed database still needs" "A new database with a password keeps the random key of a renamed database through its unlock", and "A backup of a renamed database that the user put into the new folder keeps the random key of the renamed one". The new database also turns the unlock settings off (#266).
- [ ] 1.14 Take over the data of the old app name. Built: DataFolderTests cover the folder and the files. Verify the Keychain entries and the settings in the app.
- [ ] 1.15 No environment variable moves the data folder of a release build (#422). Built: the home folder comes from the user database of macOS, and the app quits without one. DataFolderLocationTests check the library. DataFolderOfRunTests check that the app looks up the folder once per run, and UserHomeTests that a long user record still names the home folder. Verify the scenarios in a release build.

## 2. Integration

- [ ] 2.1 Check every scenario of the spec in a release build and record the result in the pull request. Checked in the Perf build on 2026-11-18 (owner decision): 18 of 24 scenarios passed, and "Notice in the save panel" failed (#481). Not checkable in the harness: "Open the folder" (a Finder window), "Restore with Time Machine", "Backup during refresh" (no bank refresh in the Perf build), and the two scenarios of the old app name (they apply only to the real folder in Application Support). Open: #481 and the owner's walk-through in a Release build.

## Workflow follow-up

- Archive the change with `openspec archive add-data-folder-and-backup` when every task is checked.
