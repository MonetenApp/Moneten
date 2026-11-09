# Tasks

One task per requirement of the spec. A task is checked only when a test or a check in the running app shows the behavior.

## 1. Requirements

- [x] 1.1 All personal data is in one encrypted database. Verified by VaultTests "The file shows no readable data".
- [x] 1.2 The database password is the key. Verified by VaultTests "The database password is the key".
- [x] 1.3 Offer a password at first launch. Verified by the debug harness snapshot in the first build.
- [ ] 1.4 A database without a password uses a random key. Built in part: the key is in the Keychain and a marker file records the state; an ad hoc rebuild cannot read the key, see ADR 0010. Finish it and verify it with a test or in the app.
- [ ] 1.5 Set a password later. Built in part: the sheet calls Vault.setPassword, which re-encrypts and removes the Keychain key. Finish it and verify it with a test or in the app.
- [x] 1.6 The new password is entered twice. Verified by the debug harness snapshot in the first build.
- [x] 1.7 Show the strength of a new password. Verified by the form shows the grade while the user types.
- [x] 1.8 Warn that a forgotten password cannot be recovered. Verified by the debug harness snapshot in the first build.
- [x] 1.9 Change the password. Verified by VaultTests "Change the password".
- [ ] 1.10 A failed password change leaves the database usable. Build it and verify it with a test or in the app.
- [x] 1.11 No way around the password. Verified by VaultTests "Many wrong attempts change nothing".
- [ ] 1.12 Show progress while the database opens. Built in part: "Opening database..." only. Finish it and verify it with a test or in the app.
- [ ] 1.13 Check the integrity of the database when it opens. Built in part: PRAGMA quick_check runs at every open; no repair at the next start. Finish it and verify it with a test or in the app.
- [ ] 1.14 Upgrade the database safely. Built in part: a backup copy is written before a migration; no check of a temporary copy. Finish it and verify it with a test or in the app.
- [ ] 1.15 Refuse a database from a newer version. Built in part: the migrator refuses a superseded database; the message does not name the versions. Finish it and verify it with a test or in the app.
- [ ] 1.16 Only one running copy uses the database. Build it and verify it with a test or in the app.
- [ ] 1.17 Detect a change of the database on disk. Build it and verify it with a test or in the app.
- [ ] 1.18 Explain every problem with the database file. Built in part: messages for an empty file, a folder, and a write-protected file; VaultTests "A file with no content is an error". Finish it and verify it with a test or in the app.
- [ ] 1.19 Mention the automatic backup copy when the database cannot be opened. Build it and verify it with a test or in the app.
- [ ] 1.20 Do not open a database file from the Finder. Build it and verify it with a test or in the app.

## 2. Integration

- [ ] 2.1 Check every scenario of the spec in a release build and record the result in the pull request.

## Workflow follow-up

- Archive the change with `openspec archive add-encrypted-database` when every task is checked.
