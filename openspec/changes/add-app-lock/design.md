# Design

## Context

This change is part of the first build of the app. The build is a Swift package with the modules `Domain`, `Storage`, `Import`, and `App`, as [ADR 0010](../../../docs/decisions/0010-swift-package-and-macos-15.md) describes. Everything runs on the Mac, with no server ([ADR 0002](../../../docs/decisions/0002-local-first-no-server.md)).

The app keeps all accounts, categories, and transactions of the open database in one in-memory `Ledger` (module `Domain`). Every change goes to the database through `Store` (module `Storage`) and then to the ledger. Views read the ledger. This keeps filters, sums, and charts fast for some ten thousand transactions without queries per keystroke.

## Decisions

The first build follows the spec where the task list marks a task as checked. Open tasks keep the behavior of the spec as the target.

### Settings that a program outside the app can change

The settings file of the app in `~/Library/Preferences` is not protected: any program of the user can write it, and macOS does not ask. A setting there must therefore never open the database or weaken the lock.

- "Unlock automatically at application start" keeps the database password in its own Keychain entry, "Moneten database password for automatic unlock". Only the change on the "Security" tab, after the password check, writes it, and only the launch reads it. "Unlock with Touch ID" and "Unlock with Apple Watch" share the entry "Moneten database password", which the launch never reads. `Vault.PasswordEntry` names the two entries. The user default of each unlock setting only shows the state of its toggle, and an unlock needs the entry as well. A default of the automatic unlock without its entry is turned off at the launch, so the toggle shows the truth.
- An unlock with the password replaces an entry that holds another password, as before, but never creates one. A forged default could otherwise turn into an entry at the next unlock.
- "Lock when main window is closed" and "Lock after inactivity" live in the table `lockSetting` of the encrypted database, one row that `Store.lockSettings()` reads and `Store.saveLockSettings(_:)` writes. A database without the row has the defaults: off, and 10 minutes. The settings matter only while the database is open, so the app reads them at each unlock. The complete export leaves them out.
- No data moves from the user defaults: no release has the old layout.
- Debug and Perf builds keep the inactivity lock off with `MONETEN_DEBUG_NO_IDLE_LOCK=1`, which the scripts of the debug harness set. Release builds do not read the variable.

## Risks / Trade-offs

Tasks marked as built in part may differ from the spec in the way their note says.
