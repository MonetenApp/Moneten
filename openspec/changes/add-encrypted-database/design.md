# Design

## Context

This change is part of the first build of the app. The build is a Swift package with the modules `Domain`, `Storage`, `Import`, and `App`, as [ADR 0010](../../../docs/decisions/0010-swift-package-and-macos-15.md) describes. Everything runs on the Mac, with no server ([ADR 0002](../../../docs/decisions/0002-local-first-no-server.md)).

The app keeps all accounts, categories, and transactions of the open database in one in-memory `Ledger` (module `Domain`). Every change goes to the database through `Store` (module `Storage`) and then to the ledger. Views read the ledger. This keeps filters, sums, and charts fast for some ten thousand transactions without queries per keystroke.

## Decisions

- `Sources/Storage/Vault.swift` opens and creates the database. It uses the GRDB fork with SQLCipher ([ADR 0005](../../../docs/decisions/0005-grdb-and-sqlcipher.md)). The password goes to `PRAGMA key`, so SQLCipher derives the key with its defaults ([ADR 0009](../../../docs/decisions/0009-database-password-as-in-moneymoney.md)).
- Without a password, a random 256-bit value in the Keychain is the passphrase. An empty file `Database/NoPassword` records this state. It holds no secret.
- A wrong password shows as SQLite error 26 at the first read, and the vault turns it into "Incorrect password!".
- Before a schema migration the vault writes `MonetenMoneten-Backup.sqlite`. After opening it runs `PRAGMA quick_check`.
- A password change runs `PRAGMA rekey` through GRDB after the current password opened a second connection.

## Risks / Trade-offs

- An ad hoc build cannot read the Keychain key of an earlier build. A database without a password then needs the earlier build. ADR 0010 records this.
