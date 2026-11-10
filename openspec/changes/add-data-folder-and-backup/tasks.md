# Tasks

One task per requirement of the spec. A task is checked only when a test or a check in the running app shows the behavior.

## 1. Requirements

- [x] 1.1 One data folder with three subfolders. Verified by DataFolder.createFolders.
- [x] 1.2 Only the user can read the data folder. Verified by folders are created with permissions 700.
- [x] 1.3 Show the data folder in the Finder. Verified by "Show Database in Finder..." in the Help menu.
- [x] 1.4 The data folder is separate from the application file. Verified by ~/Library/Application Support/MonetenMoneten.
- [x] 1.5 A copy of the data folder is a complete backup. Verified by VaultTests "A backup opens with the same password".
- [x] 1.6 Back up the database while the app runs. Verified by "Backup Database..." in the Tools menu.
- [x] 1.7 Explain what the backup command covers. Verified by the save panel explains it.
- [x] 1.8 A backup opens with the password of its time. Verified by VaultTests "A backup opens with the same password".
- [ ] 1.9 Warn about a backup without a password. Built: a warning before the save panel offers "Set Database Password...", "Back Up Anyway", and "Cancel". Verify it in the app.
- [ ] 1.10 Restore a database file. Build it and verify it with a test or in the app.
- [ ] 1.11 Move to another Mac. Build it and verify it with a test or in the app.
- [ ] 1.12 No synchronization between copies. Build it and verify it with a test or in the app.
- [ ] 1.13 Reset after a lost password. Built in part: explained under "Forgot your password?". Finish it and verify it with a test or in the app.

## 2. Integration

- [ ] 2.1 Check every scenario of the spec in a release build and record the result in the pull request.

## Workflow follow-up

- Archive the change with `openspec archive add-data-folder-and-backup` when every task is checked.
