# Proposal: Keep all files in one data folder that the user can back up, move, and reset

## Why

The app runs no server, so the only copy of the user's financial history is on their Mac. The user must be able to find the files, back them up with the tools they already use, move them to a new Mac, and start over when the password is lost. All of that works best when everything sits in one folder with a clear layout.

## What Changes

- The app keeps its files in one data folder with the subfolders "Database", "Extensions", and "Statements".
- "Show Database in Finder..." in the Help menu opens that folder.
- A copy of the data folder is a complete backup. Putting the copy back restores the state, on the same Mac or on another one.
- "Backup Database..." in the Tools menu saves a copy of the encrypted database while the app runs.
- A database without a password cannot be opened on another Mac. The app says so in the backup command and offers to set a password first.
- A user who lost the password can rename the "Database" folder and start with an empty database.
- The app does not synchronize two copies of the data folder.

## Capabilities

### New Capabilities

- `data-folder-and-backup`: where the app keeps its files, how the user finds them, and how backup, restore, moving to another Mac, and reset work.

### Modified Capabilities

None.

## Impact

- Milestone: v0.1
- Issues: #4
- Modules: `Storage` owns the folder layout and the backup copy. `App` owns the two menu commands and their messages.
- Depends on the change `add-encrypted-database`. That change owns the automatic backup copy before an upgrade and the messages for a damaged or missing database file.
- Depends on the change `add-app-lock` for the lock screen link "Forgot your password?".
- The changes `add-web-banking-extensions` and `add-bank-statements` own what the folders "Extensions" and "Statements" contain.
- Decisions: [ADR 0002](../../../docs/decisions/0002-local-first-no-server.md), [ADR 0009](../../../docs/decisions/0009-database-password-as-in-moneymoney.md).

## Reference behavior

### Observed in MoneyMoney 2.5.3

- All data is in one folder with the subfolders "Database", "Extensions", and "Statements". "Database" holds accounts, categories, and transactions. "Statements" holds the downloaded PDF statements ([backup page](https://moneymoney.app/help/backup/), [security page](https://moneymoney.app/security/)).
- The Help menu has "Show Database in Finder..." and the Tools menu has "Backup Database...". See [analysis](../../../docs/research/moneymoney-analysis.md#menus-and-keyboard-shortcuts-u).
- The backup command explains that a copy of the database is saved and that this does not replace a regular backup (interface strings).
- A manual backup is a copy of the folder, made while the app is closed. A restore puts the folder back, also from Time Machine ([backup page](https://moneymoney.app/help/backup/)).
- Moving to another Mac means copying the folder to the same place there. There is no synchronization. Two Macs with copies are two separate installations ([transfer page](https://moneymoney.app/help/transfer-database/)).
- A user who forgot the password quits the app and renames the "Database" folder. The next launch starts empty and asks for no password. Renaming is recommended over deleting, so that the step can be undone ([forgot password page](https://moneymoney.app/forgot-password/)).
- The database is stored apart from the application file, so reinstalling the app keeps the accounts (interface strings).
- An automatic backup copy from before the last update can be restored by renaming it ([backup page](https://moneymoney.app/help/backup/)).

### Decided for MonetenMoneten

- The data folder is named "MonetenMoneten" and lies in the user's Library. The design fixes the exact path.
- Only the user's account can read the data folder.
- "Show Database in Finder..." also works while the app is locked, because the reset needs it. "Backup Database..." works only while the app is unlocked.
- The backup file gets a suggested name with the date. MoneyMoney's suggested name was not observed.
- The backup command warns when no database password is set, because such a copy cannot be opened on another Mac. This follows from [ADR 0009](../../../docs/decisions/0009-database-password-as-in-moneymoney.md).
- When a restored database has another password than the one in the Keychain, the app asks for the password and then updates the Keychain.
- There is no restore command in the app. A restore replaces files, as in MoneyMoney.
