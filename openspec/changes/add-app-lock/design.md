# Design

## Context

This change is part of the first build of the app. The build is a Swift package with the modules `Domain`, `Storage`, `Import`, and `App`, as [ADR 0010](../../../docs/decisions/0010-swift-package-and-macos-15.md) describes. Everything runs on the Mac, with no server ([ADR 0002](../../../docs/decisions/0002-local-first-no-server.md)).

The app keeps all accounts, categories, and transactions of the open database in one in-memory `Ledger` (module `Domain`). Every change goes to the database through `Store` (module `Storage`) and then to the ledger. Views read the ledger. This keeps filters, sums, and charts fast for some ten thousand transactions without queries per keystroke.

## Decisions

The first build follows the spec where the task list marks a task as checked. Open tasks keep the behavior of the spec as the target.

### Settings that a program outside the app can change

The settings file of the app in `~/Library/Preferences` is not protected: any program of the user can write it, and macOS does not ask. A setting there must therefore never open the database or weaken the lock.

- Each unlock setting keeps the database password in a Keychain entry of its own: "Moneten database password for automatic unlock", "Moneten database password for Touch ID", and "Moneten database password for Apple Watch". `Vault.PasswordEntry` names them, and its raw values are the keys of the user defaults. Only the change on the "Security" tab writes an entry, after the password check, through `Vault.setUnlockMethod(_:on:password:)`. Turning a setting off deletes exactly its entry. A shared entry would let a program turn a setting back on without the password: with Touch ID off and the Apple Watch on, it would only have to write `unlockWithTouchID` into the settings file.
- The user default of each unlock setting only mirrors the state of its toggle. `Vault.launchPassword()` reads only the entry of the automatic unlock, so a password stored for Touch ID never opens the database at launch. `Vault.usableMethods(switchedOn:)` keeps only the methods whose entry exists, so a forged default turns nothing on. `Vault.unlockPassword(offered:)` reads the entry of a method that the request offered. A request that offers both Touch ID and the Apple Watch cannot tell which one the user confirmed, so it reads the entry of the first offered method that has one. A default of the automatic unlock without its entry is turned off at the launch, so the toggle shows the truth.
- A new database deletes the three entries, because its unlock settings start off and an entry is what turns a setting on. This replaces "a stored password stays" of the design of add-encrypted-database. The random key of a renamed database stays.
- The entry "Moneten database password", which builds before this change shared between all three settings, is deleted at each launch. A user of such a build turns the settings on again.
- The login Keychain of macOS is a file-based Keychain, and it ignores `kSecAttrAccessible` (security review F5). Any process of the user can read an entry after macOS asks, and the app cannot narrow that with an accessibility class. The protection therefore rests on the checks of the app and on the separate entries. Moving the entries to the data protection Keychain, which needs a team signature and an access group, is out of scope for this change.
- An unlock with the password replaces an entry that holds another password, as before, but never creates one. A forged default could otherwise turn into an entry at the next unlock.
- "Lock when main window is closed" and "Lock after inactivity" live in the table `lockSetting` of the encrypted database, one row that `Store.lockSettings()` reads and `Store.saveLockSettings(_:)` writes. A database without the row has the defaults: off, and 10 minutes. The settings matter only while the database is open, so the app reads them at each unlock. The complete export leaves them out.
- No data moves from the user defaults: no release has the old layout.
- Debug and Perf builds keep the inactivity lock off with `MONETEN_DEBUG_NO_IDLE_LOCK=1`, which the scripts of the debug harness set. Release builds do not read the variable.

## Risks / Trade-offs

Tasks marked as built in part may differ from the spec in the way their note says.
