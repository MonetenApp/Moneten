# Tasks

One task per requirement of the spec. A task is checked only when a test or a check in the running app shows the behavior.

## 1. Requirements

- [x] 1.1 All personal data is in one encrypted database. Verified by VaultTests "The file shows no readable data".
- [x] 1.2 The database password is the key. Verified by VaultTests "The database password is the key".
- [x] 1.3 Offer a password at first launch. Verified by the debug harness snapshot in the first build.
- [x] 1.4 A database without a password uses a random key. Verified by OpeningTests "A database without a password opens with the random key, and the file alone does not open elsewhere" and the sidebar hint, which opens "Set Database Password...". An ad hoc rebuild cannot read the key, see ADR 0010 (#266).
- [x] 1.5 Set a password later. Verified by OpeningTests "Setting a password later keeps the data and removes the random key from the Keychain" with 3 accounts. A key or marker that could not be removed is reported, and the app still knows that the password is set (#266).
- [x] 1.6 The new password is entered twice. Verified by the debug harness snapshot in the first build.
- [x] 1.7 Show the strength of a new password. Verified by the form shows the grade while the user types.
- [x] 1.8 Warn that a forgotten password cannot be recovered. Verified by the debug harness snapshot in the first build.
- [x] 1.9 Change the password. Verified by VaultTests "Change the password".
- [ ] 1.10 A failed password change leaves the database usable. Build it and verify it with a test or in the app.
- [x] 1.11 No way around the password. Verified by VaultTests "Many wrong attempts change nothing".
- [x] 1.12 Show progress while the database opens. Verified by the debug harness: a database of layout v16 with 50,000 transactions shows "Upgrading database..." on the lock screen after the password, then the main window (#266).
- [x] 1.13 Check the integrity of the database when it opens. Verified by OpeningTests "A damaged index is reported, the next open repairs it, and a copy of the damaged file stays", "A damaged table that the repair cannot read asks for a backup copy and creates no new database", and "A backup that the user put in place of a damaged database needs no repair", and by the debug harness with a damaged page (#266).
- [x] 1.14 Upgrade the database safely. Verified by OpeningTests "An upgrade keeps a backup copy of the old state and opens the upgraded database with all data" and "A failed upgrade leaves the database unchanged and removes the temporary copy" (#266).
- [x] 1.15 Refuse a database from a newer version. Verified by OpeningTests "A database that a newer version upgraded is refused with both versions, and the file stays unchanged". A database upgraded before this change has no recorded version, and the message then names only the running version (#266).
- [ ] 1.16 Only one running copy uses the database. Build it and verify it with a test or in the app.
- [ ] 1.17 Detect a change of the database on disk. Build it and verify it with a test or in the app.
- [x] 1.18 Explain every problem with the database file. Verified by OpeningTests "Each problem with the database file has its own message with the path": an empty file, a folder, a write-protected file, a folder without write permission, and a folder with files but no database, which starts no new database (#266).
- [x] 1.19 Mention the automatic backup copy when the database cannot be opened. Verified by OpeningTests "A failure to open names the automatic backup copy and how to restore it" (#266).
- [ ] 1.20 Do not open a database file from the Finder. Build it and verify it with a test or in the app.

## 2. Integration

- [ ] 2.1 Check every scenario of the spec in a release build and record the result in the pull request.

## Workflow follow-up

- Archive the change with `openspec archive add-encrypted-database` when every task is checked.
