# Proposal: Keep all data in a database that the user's password encrypts

## Why

The app holds login data, balances, and years of transactions. Anyone who gets the file, from a stolen Mac or from a backup, must not be able to read it. A user who switches from MoneyMoney expects the model they know, in which their own password is the key and nobody else can open the data.

## What Changes

- All data of the app lives in one database file that is encrypted with 256-bit AES.
- The database password is the key. The app offers to set it at first launch. The user can set it later and change it at any time.
- Until a password is set, the app uses a random key from the Keychain and shows a hint in the sidebar.
- There is no way to recover a forgotten password. The app says so before the user sets one.
- The app checks the database when it opens it, upgrades it safely after an update, and refuses a database from a newer version of the app.
- Each problem with the database file gets its own message that tells the user what to do. No such problem makes the app overwrite data.

## Capabilities

### New Capabilities

- `database-encryption`: what the database protects, how the password becomes the key, how the password is set and changed, and how the app opens, checks, and upgrades the database file.

### Modified Capabilities

None.

## Impact

- Milestone: v0.1
- Issues: #2, #4, #26
- Modules: `Storage` owns the database file, the key, the checks, and the upgrade. `App` owns the password sheets, the sidebar hint, and the messages.
- The change `add-app-lock` depends on this change. It owns locking, unlocking, and the copy of the password in the Keychain.
- The change `add-data-folder-and-backup` depends on this change. It owns the folder layout, the backup command, and the reset.
- The change `add-login-credentials` stores saved PINs in this database.
- Decisions: [ADR 0005](../../../docs/decisions/0005-grdb-and-sqlcipher.md), [ADR 0009](../../../docs/decisions/0009-database-password-as-in-moneymoney.md).

## Reference behavior

### Observed in MoneyMoney 2.5.3

- The database is encrypted and protected by a password, and the password is the key of the database. The security page says the database is as safe as the password ([security page](https://moneymoney.app/security/)).
- A user who has not set a password can set one at any time ([security page](https://moneymoney.app/security/)).
- The menu and the settings offer "Set Database Password..." and "Change Database Password...". The settings explain that the password encrypts login credentials, account balances, and account transactions. See [analysis](../../../docs/research/moneymoney-analysis.md#settings-u).
- The password sheets have the fields "Current password", "New password", and "Repeat new password". The interface strings include the messages that the new passwords differ, that the new password must not equal the old one, that the password has been changed, and that the password could not be changed.
- The interface strings include the grades "weak", "good", "strong", and "excellent". They point to a strength display. The display itself was not observed.
- There is no way around a forgotten password. The only way forward is to reset the database ([forgot password page](https://moneymoney.app/forgot-password/)).
- The app shows "Opening database..." and "Upgrading database..." at launch.
- The app keeps an automatic backup copy of the database from before an update, and that copy can be restored by renaming it ([backup page](https://moneymoney.app/help/backup/)).
- The interface strings include one message for each of these cases. The integrity check failed and a repair follows at the next start. The integrity check failed and a backup is needed. The database is from a newer version, with the version that is needed. The database is in use by another application. The database was changed on disk outside the app. The file is missing or empty, is a folder, or is write-protected. The folder lacks write permission. The user opened the database file directly.
- The strings for the upgrade name a temporary file, a schema check, and an integrity check before the old file is replaced.
- The database encryption moved to SQLCipher 4 (version history, 2.4.44).

### Decided for Moneten

- Without a password the app uses a random key in the Keychain and shows a hint in the sidebar. This follows [ADR 0009](../../../docs/decisions/0009-database-password-as-in-moneymoney.md). How MoneyMoney protects a database without a password was not observed.
- The key derivation uses the parameters in ADR 0009. MoneyMoney's parameters were not observed.
- The app accepts every password that is not empty. The strength display informs and does not block.
- The user must confirm the warning about a lost password before the app sets a password.
- A password that is set cannot be removed again. It can only be changed.
- After a wrong password the app neither erases data nor adds a waiting time beyond the key derivation.
- When the database was changed on disk, the app stops writing and offers to load the database again. MoneyMoney shows the message. What it does next was not observed.
- The app keeps the damaged file when a repair runs, and it keeps the old file until an upgrade has passed all checks. The strings of MoneyMoney suggest the same order. The exact steps were not observed.
- An empty database folder starts a new database. A folder that holds a database file with no content is an error.
