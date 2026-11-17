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
   4. It renames `Moneten-Repair.sqlite` to `Moneten.sqlite`, after `F_FULLFSYNC` on the file, and syncs the folder after the rename. Every rename of the vault does this, so a power loss cannot leave a renamed file without its data. Before the rename the database is still the damaged file and the marker is still there, so the next start repairs again. After the rename the next start finds an intact file and removes the marker.
   5. It removes the marker. This comes after the failure handling of steps 2 to 4, so a repair that worked is never reported as failed.

   A failure in steps 2 to 4 removes the repair file and the copy of the damaged file, which is still in place, and throws `repairFailed`.
6. **Check the integrity.** A failed `PRAGMA quick_check` writes `RepairAtNextStart` and throws `damaged`.
7. **Lay out a new database.** A database without tables, which only `create` makes, gets every step of the layout in place. There is nothing to lose.
8. **Upgrade** when a step of the layout is missing.
   1. The vault announces "Upgrading database...".
   2. It sets `PRAGMA journal_mode = DELETE` on the open connection. SQLite then writes the committed rows of a `Moneten.sqlite-wal` into the database and removes the WAL. When another program has the database open in WAL mode, SQLite refuses. The vault then sets `PRAGMA locking_mode = EXCLUSIVE` and takes the exclusive lock, which it keeps until step 6, so no other connection writes between the copy and the rename. When another program is reading or writing at that moment, SQLite refuses. Either refusal throws `upgradeFailed` with the database unchanged. A program that holds the database open without a transaction cannot be seen in this mode, and its later writes would go to the replaced file. The lock of "One running copy" keeps a second copy of the app away, and the watch of "Change on disk" stops a copy whose file was replaced.
   3. It makes the backup copy with the online backup API of SQLite from the open connection into `.Moneten-Backup.sqlite.partial`, and renames that to `Moneten-Backup.sqlite`. The backup API reads through the connection, so the copy holds every committed row. A stop leaves at most the partial file.
   4. It makes `Moneten-Upgrade.sqlite` the same way.
   5. It runs the missing steps of the layout on `Moneten-Upgrade.sqlite`, runs `PRAGMA quick_check`, records the version in `user_version`, and closes it. GRDB checks the foreign keys at the end of each step, because the connection has them on. A failure removes the work file and its side files and throws `upgradeFailed`. A stop leaves the work file, which the next upgrade removes in step 4.
   6. It closes the database and renames `Moneten-Upgrade.sqlite` to `Moneten.sqlite`. Before the rename the next start finds the old database and upgrades again. After it, the next start finds the new one.

### Create

`create` runs only when the database folder holds no files. A new database without a password always gets a new random key, which `Keychain.write` stores as a new entry and which replaces an entry "Moneten database key" of the same path. `create` never reads that entry: another program of the user can create it in advance, because the account is the path of the database file, and a key that it chose would encrypt the new database. When `write` replaced an entry, `create` logs that, without the value and without the path. A new database with a password leaves the random key of the path alone, so a database that the user renamed still opens with it when the user puts it back. An unlock with the password removes such a random key only when the new folder shows a first password that is not finished, as "Set the first password" describes. One limit follows: a database without a password that the user renamed no longer opens when a new database without a password was created at its path, because its key is gone. Before issue #399 the new database took the key of the renamed one, and a later `setPassword` on the new database removed that key anyway. A database at another path never opened with the key, because the Keychain keeps the key under the path of the file, and that stays. The app turns the unlock settings off. When a step after the first write fails, `create` closes its connection first and then removes the new file and the `NoPassword` marker.

### Set the first password

`setPassword` changes the random key to a password. It first reads the random key from the Keychain. Without it, a failed re-key could not be undone, so it throws `keyNotInKeychain` and changes nothing.

1. Remove the work files and their side files, also a side file whose work file is gone. They hold the random key, and `RekeyCopies` does not list them. A file that cannot be removed throws `workFilesNotRemoved` before anything changed.
2. List the copies. Each copy that the random key opens is to be re-keyed. A copy that the random key does not open stays as it is. A copy with another error, such as `SQLITE_BUSY`, stops the change with `copiesUnreadable` before anything changed, so that `RekeyCopies` lists every copy that still needs the random key.
3. Refuse when the store saw a change on disk, so that no copy is listed for a file that the app loads again. Then write `RekeyCopies` with the names to re-key. A failure throws before anything changed.
4. Re-key the database as "Re-key the database" below describes. A failure throws `passwordNotChanged`, and the database keeps the random key.
5. Re-key each listed copy and check that the password opens it.
6. Write the copies that failed back into `RekeyCopies`, or remove the marker when none failed.
7. Remove `NoPassword`.
8. Remove the random key from the Keychain, but only when no copy still needs it. Otherwise the key stays and the error names the copies.

A stop before step 4: the next start opens with the random key, and step 4 of "Open" finds every listed copy done. A stop after step 4: `NoPassword` may still exist, the random key does not open the database, and the lock screen asks for the password. Step 4 of "Open" then re-keys each copy with the random key, and the vault removes the key once no copy needs it.

The unlock with the password removes the random key only when the folder shows a first password that is not finished: `NoPassword` existed, or step 4 of "Open" found a copy in `RekeyCopies` that the random key opens. Then it re-keys each copy that the key opens and removes the key once no copy needs it. Otherwise the key may belong to a renamed database at the same path, and it stays. A copy that the key opens is no such sign, because it may be a backup of the renamed database that the user put into the new folder. A stop between step 7 and step 8 leaves no such sign, so the key stays in the Keychain. It opens no file of this folder.

### Change the password

`changePassword`:

1. Check the current password on a second connection.
2. Remove the work files and their side files, as step 1 of "Set the first password" does. They hold the current key.
3. List the copies. Each copy that the current password opens is to be re-keyed. A copy that it does not open, such as one with an even older password, stays as it is. A copy with another error, such as `SQLITE_BUSY`, stops the change with `copiesUnreadable`, before anything changed, because nobody could tell later whether it still opens with the current password.
4. Refuse when the store saw a change on disk. Then write `RekeyCopies` with the names to re-key, together with the names that an earlier change left. A failure throws before anything changed.
5. Re-key the database as "Re-key the database" below describes. A failure throws `passwordNotChanged`, the current password still opens it, and the Keychain entries keep the current password.
6. Re-key each listed copy and check that the new password opens it. A copy that the current password opened and that could not be re-keyed is removed. A copy with any other error is reported as not updated and stays listed, so step 4 of "Open" removes it at the next start when the new password does not open it.
7. Write the copies that are still not done back into `RekeyCopies`, or remove the marker.
8. Store the new password in the Keychain when the Keychain held the old one. A failure reports the Keychain error and the copies that were not updated.

A stop before step 5: the next start opens with the current password and finds every listed copy done. A stop after step 5: only the new password opens the database, and step 4 of "Open" removes each listed copy that the new password does not open. So no copy stays readable with the earlier password once the database has the new one.

### Re-key the database

SQLCipher re-keys the open connection in one write transaction. A failure before the commit, such as a full disk that takes no journal, rolls the file back, but the connection keeps writing with the new key and reading with the old one. The next save then puts pages with the new key into a file with the old key, and neither password opens it. A failed commit leaves the connection reading with the new key too, and SQLCipher offers no way back: a second `PRAGMA key` on a connection that has read is ignored.

So `rekeyDatabase` does this, all in one access to the queue of the store, so that no other write of the store, such as a refresh that waits, runs while the connection reads with one key and writes with the other:

1. Set `PRAGMA journal_mode = DELETE`. Only the rollback journal makes a reader of another program stop `BEGIN EXCLUSIVE`; in WAL a reader does not. The app never turns WAL on, and a file that another program left in WAL goes back to the rollback journal here. When another program has the file open in WAL, SQLite refuses the switch, and the change throws `passwordNotChanged` before any key changed.
2. Begin an exclusive transaction. Another program that reads the database stops the change here, before SQLCipher touches a key, and the vault throws `passwordNotChanged` without any recovery.
3. Inside the transaction, with the lock held, check the store for a change on disk as each write does. No other program can commit between this check and the re-key, so a commit that came in before the lock throws `DatabaseChangedOnDisk` and is never re-keyed.
4. Re-key. Only a failure of the disk itself reaches the commit.
5. Ask a fresh connection which key opens the file. The new key: the change is done.
6. The old key: re-key the open connection to the old key. That sets its writing key back to the key that it reads with and that the file has, even when the re-key itself fails again. A failed commit of the disk in step 4 can still have left the connection reading with the new key. Then it reads nothing, and the store refuses every write, so the app has to open the database again. Then restore `RekeyCopies` and throw `passwordNotChanged`.
7. Neither key, for example while another program holds a lock: the result is unknown. The store refuses every write, `RekeyCopies` stays, so the next open settles the copies with whichever key the database has, and the vault throws `unreadable`.

The connection goes back only to a key that a fresh connection proved. Every other result refuses all writes of the store. The app then closes the database and shows "The password change could not be completed." with "Load Database Again", because Moneten itself, and not another program, left the store unable to write.

A stop of the Mac during the re-key leaves the journal of the transaction, which holds the pages with the old key. The next open plays it back, so the old password opens the database.

## One running copy

`DataFolderLock` takes `flock(LOCK_EX | LOCK_NB)` on the data folder itself. The app takes it first in `AppModel.init`, before any service that writes into the data folder. The crash reports start once per run, when the copy first holds the lock: at the launch, or later through "Try Again". The lock adds no file, so the rules of the database folder stay as they are. The system releases the lock when the process ends in any way, also after a crash. A lock belongs to its open file, so two locks in one process exclude each other, which the tests use. A second copy of the app gets `inUse` and shows "The database is in use by another application. Quit the other copy of Moneten, then click Try Again." with "Try Again". It opens, creates, and writes nothing. The lock does not wait.

Each data folder has its own lock, so a debug build with `MONETEN_DATA_DIR` never blocks the real database.

## Change on disk

`DiskWatch` belongs to each `Store`. It records two things when the store opens: the device and inode of the database file, and `PRAGMA data_version`. SQLite moves that version only for a commit of another connection, also one in another process, and it also moves when an older copy is written over the file in place, because the bytes of the first page differ. Commits and rollbacks of the store itself leave it as it is. Another inode at the path, or another version, is a change on disk.

- `Store.write` is the only write path of the store. It checks at the start of each transaction, after SQLite took the write lock, so no other program can commit between the check and the commit. A change throws `DatabaseChangedOnDisk`, and nothing of the transaction is written.
- The commit hook checks the inode once more, for a write that bypassed `Store.write`. It reads no SQL, because SQLite forbids it there. A write to a file that was renamed away also fails in SQLite itself with `SQLITE_READONLY_DBMOVED`.
- Once a change was seen, the store refuses every write until it closes. Only a new store, which loads the file again, writes.
- `Store.isChangedOnDisk()` runs the same check outside a write.

The app checks when an entry of the database folder changes, which a replacement causes at once, every 20 seconds, and when the app becomes active. The check runs away from the main thread, because a long write holds the queue. On a change the app closes the database as the lock does and shows "The database has been changed on disk, outside of Moneten." with "Load Database Again", which opens the database as at the start, with the password when one is set.

## Opened from the Finder

The app declares no document type for the database file, so a double click on it opens the app that the Finder chose for `.sqlite` files. When the user opens such a file with the app anyway, through "Open With" or a drop on the app, macOS hands it to `application(_:open:)` of the app delegate. `DataFolder.isDatabaseFile` treats every file with the extension `sqlite`, in any case, as a database file. The app loads none of them. It opens the main window, shows the alert "Database file" with "Please don’t open the database file directly. Launch Moneten instead.", and keeps its own database in every phase. Other files are left alone. Files that arrive before the main window exists wait for it.

## Risks / Trade-offs

- An ad hoc build cannot read the Keychain key of an earlier build. A database without a password then needs the earlier build. ADR 0010 records this.
