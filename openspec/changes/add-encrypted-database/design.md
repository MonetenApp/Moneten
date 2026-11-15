# Design

## Context

This change is part of the first build of the app. The build is a Swift package with the modules `Domain`, `Storage`, `Import`, and `App`, as [ADR 0010](../../../docs/decisions/0010-swift-package-and-macos-15.md) describes. Everything runs on the Mac, with no server ([ADR 0002](../../../docs/decisions/0002-local-first-no-server.md)).

The app keeps all accounts, categories, and transactions of the open database in one in-memory `Ledger` (module `Domain`). Every change goes to the database through `Store` (module `Storage`) and then to the ledger. Views read the ledger. This keeps filters, sums, and charts fast for some ten thousand transactions without queries per keystroke.

## Decisions

- `Sources/Storage/Vault.swift` opens and creates the database. It uses the GRDB fork with SQLCipher ([ADR 0005](../../../docs/decisions/0005-grdb-and-sqlcipher.md)). The password goes to `PRAGMA key`, so SQLCipher derives the key with its defaults ([ADR 0009](../../../docs/decisions/0009-database-password-as-in-moneymoney.md)).
- Without a password, a random 256-bit value in the Keychain is the passphrase. An empty file `Database/NoPassword` records this state. It holds no secret.
- A wrong password shows as SQLite error 26 at the first read, and the vault turns it into "Incorrect password!".
- The vault opens the database away from the main thread. The window shows "Opening database..." and, when the layout changes, "Upgrading database...".
- An upgrade of the layout first copies the database to `Moneten-Backup.sqlite`. It then upgrades the temporary copy `Moneten-Upgrade.sqlite`, checks that every step of the layout is applied, runs `PRAGMA quick_check` and `PRAGMA foreign_key_check` on it, and only then puts it in place of the database. A failure removes the temporary copy and leaves the database as it was.
- Each open runs `PRAGMA quick_check`. A page that SQLCipher cannot authenticate counts as damage. A failed check writes the empty file `Database/RepairAtNextStart` and reports the damage. The next open with the key checks again: a file that passes, such as a backup the user put in place, needs no repair. Otherwise the vault copies the damaged file to `Moneten-Damaged-<time>.sqlite`, writes the schema and the rows of every table into a new file, reading each table `NOT INDEXED`, and puts that file in place. A damaged index is repaired this way. A damaged table page cannot be read, so the repair fails and the app asks for a backup copy.
- An upgrade records the version of the app in `PRAGMA user_version` as major × 1,000,000 + minor × 1,000 + patch. An older version that finds a step of the layout it does not know names that version as the lowest one that opens the database.
- The vault starts a new database only when the database folder holds no files other than `.DS_Store`. It checks write permission for the file and for the folder before it opens anything.
- Every Keychain and file failure is thrown as a `Vault.Failure` with a message for the user. A password change that worked but left the random key, or a Keychain entry that did not follow, is reported with the note that the password is changed.
- A new database removes the Keychain entries that a database at the same path left, such as one the user renamed after a lost password.
- A password change runs `PRAGMA rekey` through GRDB after the current password opened a second connection. The same change runs `PRAGMA rekey` on `Moneten-Backup.sqlite` and on each `Moneten-Damaged-<time>.sqlite` that the current password opens, and checks that the new password opens the copy. A copy that fails is removed, because it would still open with the earlier password. Working files that an interrupted upgrade or repair left behind are removed. A copy that the current password does not open is left alone, because the earlier password does not open it either. A copy that could not be removed is reported with the note that the password is changed.

## Risks / Trade-offs

- An ad hoc build cannot read the Keychain key of an earlier build. A database without a password then needs the earlier build. ADR 0010 records this.
