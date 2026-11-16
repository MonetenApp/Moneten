# Design

## Context

This change is part of the first build of the app. The build is a Swift package with the modules `Domain`, `Storage`, `Import`, and `App`, as [ADR 0010](../../../docs/decisions/0010-swift-package-and-macos-15.md) describes. Everything runs on the Mac, with no server ([ADR 0002](../../../docs/decisions/0002-local-first-no-server.md)).

The app keeps all accounts, categories, and transactions of the open database in one in-memory `Ledger` (module `Domain`). Every change goes to the database through `Store` (module `Storage`) and then to the ledger. Views read the ledger. This keeps filters, sums, and charts fast for some ten thousand transactions without queries per keystroke.

## Decisions

- `Sources/Storage/Vault.swift` opens and creates the database. It uses the GRDB fork with SQLCipher ([ADR 0005](../../../docs/decisions/0005-grdb-and-sqlcipher.md)). The password goes to `PRAGMA key`, so SQLCipher derives the key with its defaults ([ADR 0009](../../../docs/decisions/0009-database-password-as-in-moneymoney.md)).
- Without a password, a random 256-bit value in the Keychain is the passphrase. An empty file `Database/NoPassword` records this state. It holds no secret.
- A wrong password shows as SQLite error 26 at the first read, and the vault turns it into "Incorrect password!".
- The vault opens the database away from the main thread. The window shows "Opening database..." and, when the layout changes, "Upgrading database...".
- The vault opens, repairs, upgrades, and re-keys the database in the fixed order of "Open, repair, upgrade, and re-key" below.
- An upgrade records the version of the app in `PRAGMA user_version` as major × 1,000,000 + minor × 1,000 + patch. An older version that finds a step of the layout it does not know names that version as the lowest one that opens the database.
- The vault starts a new database only when the database folder holds no files other than `.DS_Store`. It checks write permission for the file and for the folder before it opens anything.
- Every Keychain and file failure is thrown as a `Vault.Failure` with a message for the user. A password change that worked but left the random key, or a Keychain entry that did not follow, is reported with the note that the password is changed.
- A new database removes the Keychain entries that a database at the same path left, such as one the user renamed after a lost password.
- A password change runs `PRAGMA rekey` through GRDB after the current password opened a second connection.

## Open, repair, upgrade, and re-key

The vault in `Sources/Storage/Vault.swift` (module `Storage`) follows these steps in this order. Each step says what is on disk when the Mac stops at that step, and what the next start does. Every step that changes the database works on a separate file and puts it in place with one `rename`, so the database file is always either the old one or the new one.

### Files

The database folder holds these files. The vault touches no other file.

| File | What it is |
|---|---|
| `Moneten.sqlite` | The database |
| `NoPassword`, `RepairAtNextStart`, `RekeyCopies` | Markers. `RekeyCopies` lists the file names of the copies that a password change still has to re-key. It holds no key and no password. |
| `Moneten-Backup.sqlite` | The automatic backup copy from the last upgrade |
| `Moneten-Damaged-<yyyy-MM-ddTHHmmss>.sqlite` | A copy of a damaged database, with the time in UTC. Only this exact pattern counts. |
| `Moneten-Upgrade.sqlite`, `Moneten-Repair.sqlite`, `.<copy>.partial` | Work files. Only an interrupted run leaves them behind. |

SQLite keeps the side files `-journal`, `-wal`, and `-shm` next to a file. Before the vault makes a work file or a copy, it removes the work file and these three side files. An old journal next to a new file would otherwise be played back into it.

### Open

`open(password:)` and `openWithRandomKey()`:

1. **Check the file.** A missing file throws `fileIsMissing`, a folder `pathIsFolder`, and a file of 0 bytes `fileIsEmpty`. The connection opens with `mode=rw`, so SQLite cannot create the file either. Only `create` creates a database, and only in an empty folder. On disk: nothing changed.
2. **Connect** with the key and read the schema. SQLite plays back a hot journal of the database itself, which restores its last committed state. A wrong key throws `incorrectPassword`.
3. **Refuse a newer database.** A step of the layout that this version does not know throws `newerVersion`. When the table of the steps cannot be read, a `user_version` above the running version throws it too. This check comes before every step that writes, so an older version never changes a newer database, not even with a pending repair.
4. **Finish an interrupted re-key** when `RekeyCopies` exists. For each listed copy: the key of step 2 opens it, so it is done. Or the random key in the Keychain opens it, so the vault re-keys it to the key of step 2. Or neither opens it, so it still has the earlier key, and the vault removes it. A copy with any other error, and a copy that could not be re-keyed or removed, stays listed for the next start. The marker goes when the list is empty. On disk: the database is unchanged; a stop leaves the marker, and the next start repeats this step.
5. **Repair** when `RepairAtNextStart` exists.
   1. A file that passes `PRAGMA quick_check` now, such as a backup that the user put in place, needs no repair. The vault removes the marker. A marker that stays only adds one check at the next start.
   2. The vault closes the connection and copies the bytes of the damaged file to `.Moneten-Damaged-<time>.sqlite.partial`, then renames it to `Moneten-Damaged-<time>.sqlite`. A stop leaves the partial file, which the next copy removes.
   3. It writes the schema and the rows of every table into `Moneten-Repair.sqlite` and checks that file. It reads each table `NOT INDEXED`, because SQLite can scan an index that covers every column instead of the table.
   4. It renames `Moneten-Repair.sqlite` to `Moneten.sqlite`. Before the rename the database is still the damaged file and the marker is still there, so the next start repairs again. After the rename the next start finds an intact file and removes the marker.
   5. It removes the marker. This comes after the failure handling of steps 2 to 4, so a repair that worked is never reported as failed.

   A failure in steps 2 to 4 removes the repair file and the copy of the damaged file, which is still in place, and throws `repairFailed`.
6. **Check the integrity.** A failed `PRAGMA quick_check` writes `RepairAtNextStart` and throws `damaged`.
7. **Lay out a new database.** A database without tables, which only `create` makes, gets every step of the layout in place. There is nothing to lose.
8. **Upgrade** when a step of the layout is missing.
   1. The vault announces "Upgrading database...".
   2. It sets `PRAGMA journal_mode = DELETE` on the open connection. SQLite then writes the committed rows of a `Moneten.sqlite-wal` into the database and removes the WAL. When another program has the database open, SQLite refuses, and the vault throws `upgradeFailed` with the database unchanged.
   3. It makes the backup copy with the online backup API of SQLite from the open connection into `.Moneten-Backup.sqlite.partial`, and renames that to `Moneten-Backup.sqlite`. The backup API reads through the connection, so the copy holds every committed row. A stop leaves at most the partial file.
   4. It makes `Moneten-Upgrade.sqlite` the same way.
   5. It runs the missing steps of the layout on `Moneten-Upgrade.sqlite`, runs `PRAGMA quick_check`, records the version in `user_version`, and closes it. GRDB checks the foreign keys at the end of each step, because the connection has them on. A failure removes the work file and its side files and throws `upgradeFailed`. A stop leaves the work file, which the next upgrade removes in step 4.
   6. It closes the database and renames `Moneten-Upgrade.sqlite` to `Moneten.sqlite`. Before the rename the next start finds the old database and upgrades again. After it, the next start finds the new one.

### Create

`create` runs only when the database folder holds no files. When a step after the first write fails, it closes its connection first and then removes the new file and the `NoPassword` marker.

### Set the first password

`setPassword` changes the random key to a password:

1. List the copies. Each copy that the random key opens is to be re-keyed. A copy that the random key does not open stays as it is. A copy with another error is reported.
2. Write `RekeyCopies` with the names to re-key. A failure throws before anything changed.
3. Re-key the database. A failure throws, and the database keeps the random key.
4. Remove `NoPassword`.
5. Re-key each listed copy and check that the password opens it.
6. Write the copies that failed back into `RekeyCopies`, or remove the marker when none failed.
7. Remove the random key from the Keychain, but only when no copy still needs it. Otherwise the key stays and the error names the copies.

A stop before step 3: the next start opens with the random key, and step 4 of "Open" finds every listed copy done. A stop after step 3: `NoPassword` may still exist, the random key does not open the database, and the lock screen asks for the password. Step 4 of "Open" then re-keys each copy with the random key, and the vault removes the key once no copy needs it.

### Change the password

`changePassword`:

1. Check the current password on a second connection.
2. List the copies. Each copy that the current password opens is to be re-keyed. A copy that it does not open, such as one with an even older password, stays as it is. A copy with another error, such as `SQLITE_BUSY`, is reported as not updated.
3. Write `RekeyCopies` with the names to re-key, together with the names that an earlier change left. A failure throws before anything changed.
4. Re-key the database. A failure throws, and the current password still opens it.
5. Re-key each listed copy and check that the new password opens it. A copy that the current password opened and that could not be re-keyed is removed. A copy with any other error is reported as not updated.
6. Write the copies that are still not done back into `RekeyCopies`, or remove the marker.
7. Remove the work files, which hold the current key.
8. Store the new password in the Keychain when the Keychain held the old one. A failure reports the Keychain error and the copies that were not updated.

A stop before step 4: the next start opens with the current password and finds every listed copy done. A stop after step 4: only the new password opens the database, and step 4 of "Open" removes each listed copy that the new password does not open. So no copy stays readable with the earlier password once the database has the new one.

## Risks / Trade-offs

- An ad hoc build cannot read the Keychain key of an earlier build. A database without a password then needs the earlier build. ADR 0010 records this.
