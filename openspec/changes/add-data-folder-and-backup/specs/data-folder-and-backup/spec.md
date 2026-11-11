# Spec Delta

## Purpose

The user owns the files of the app and must be able to protect them without help from a server. This capability defines where the files are, how the user finds them, and how backup, restore, moving to another Mac, and reset work.

## ADDED Requirements

### Requirement: One data folder with three subfolders

The app SHALL keep every file that it stores for the user in one data folder with the subfolders "Database", "Extensions", and "Statements". "Database" holds the encrypted database and its backup copies. "Extensions" holds the extension files. "Statements" holds the downloaded statements.

#### Scenario: Fresh installation

- **WHEN** the user starts the app for the first time
- **THEN** the data folder exists with the three subfolders

#### Scenario: Nothing outside the folder

- **GIVEN** an app with accounts, an installed extension, and downloaded statements
- **WHEN** the user looks for files of the app that hold financial data
- **THEN** all of them are inside the data folder

### Requirement: Only the user can read the data folder

The app SHALL create the data folder with permissions that give access to the user's own account only.

#### Scenario: Another account on the same Mac

- **GIVEN** a second user account on the Mac without administrator rights
- **WHEN** that user tries to open the data folder of the first user
- **THEN** macOS denies access

### Requirement: Show the data folder in the Finder

The app SHALL offer "Show Database in Finder..." in the Help menu. The command opens a Finder window that shows the data folder. The command also works while the app is locked.

#### Scenario: Open the folder

- **WHEN** the user chooses "Show Database in Finder..."
- **THEN** a Finder window shows the data folder with "Database", "Extensions", and "Statements"

#### Scenario: Locked app

- **GIVEN** the app is locked
- **WHEN** the user chooses "Show Database in Finder..."
- **THEN** the Finder window opens
- **AND** the app stays locked

### Requirement: The data folder is separate from the application file

The app SHALL keep the data folder outside the application file, so that an update, a reinstallation, or the removal of the application file leaves all data in place.

#### Scenario: Reinstall the app

- **GIVEN** an app with 3 accounts
- **WHEN** the user moves the application file to the Trash and installs the app again
- **THEN** the app shows the 3 accounts after the user has entered the database password

### Requirement: A copy of the data folder is a complete backup

The app SHALL make it possible to back up everything by copying the data folder while the app is closed. The app does not exclude the folder from Time Machine. A copy that is put back in place restores accounts, categories, rules, transactions, extensions, and statements.

#### Scenario: Restore the folder

- **GIVEN** a copy of the data folder from Monday with 120 transactions
- **WHEN** the user quits the app on Friday, replaces the data folder with the copy, and starts the app
- **THEN** the app shows the state of Monday with 120 transactions
- **AND** the next refresh fetches the transactions since Monday again

#### Scenario: Restore with Time Machine

- **GIVEN** Time Machine is on with no exclusions
- **WHEN** the user restores the data folder from last week with Time Machine while the app is closed
- **THEN** the app opens the state of last week

### Requirement: Back up the database while the app runs

The app SHALL offer "Backup Database..." in the Tools menu. The command asks where to save, suggests a file name with the current date, and writes a complete and consistent copy of the encrypted database to that place. The command is available only while the app is unlocked.

#### Scenario: Save a backup

- **WHEN** the user chooses "Backup Database..." on 9 November 2026 and confirms the save panel
- **THEN** the chosen folder holds a database file whose suggested name contains 2026-11-09
- **AND** the app confirms that the backup was saved

#### Scenario: Backup during a refresh

- **GIVEN** a refresh is running
- **WHEN** the user saves a backup
- **THEN** the backup opens later without an integrity error

#### Scenario: Target not writable

- **WHEN** the user picks a write-protected folder
- **THEN** the app shows that it could not create the backup
- **AND** the database in the data folder is unchanged

### Requirement: Explain what the backup command covers

The app SHALL state, before it saves a backup with "Backup Database...", that the copy holds the database only, that statements and extensions are not part of it, and that the command does not replace a regular backup of the Mac.

#### Scenario: Notice in the save panel

- **WHEN** the user chooses "Backup Database..."
- **THEN** the save panel shows the notice
- **AND** the notice links to the help page about backups

### Requirement: A backup opens with the password of its time

The app SHALL write backups that are encrypted with the database password that was valid when the backup was made. That password opens the backup on any Mac.

#### Scenario: Password changed after the backup

- **GIVEN** a backup made while the password was "alt-und-lang-genug"
- **WHEN** the user changes the password and later restores the backup
- **THEN** the app asks for a password and "alt-und-lang-genug" opens the restored database

### Requirement: Warn about a backup without a password

The app SHALL warn the user in "Backup Database..." while no database password is set. The warning says that such a copy can be opened only on this Mac and with this user account, and it offers "Set Database Password..." first.

#### Scenario: No password set

- **GIVEN** a database without a password
- **WHEN** the user chooses "Backup Database..."
- **THEN** the app shows the warning and offers to set a password
- **AND** the user can still save the backup

### Requirement: Restore a database file

The app SHALL open a database file that the user has put in place of the current one in the "Database" folder while the app was closed. When the password in the Keychain does not open that file, the app asks for the database password and replaces the Keychain entry after a successful unlock.

#### Scenario: Put a backup in place

- **GIVEN** a backup file from "Backup Database..." and a closed app
- **WHEN** the user replaces the database file in "Database" with the backup file and starts the app
- **THEN** the app opens the backup after the user has entered its password

#### Scenario: Keychain holds a newer password

- **GIVEN** "Unlock automatically at application start" is on and the restored file has an older password
- **WHEN** the user starts the app
- **THEN** the lock screen asks for the database password
- **AND** after a successful unlock, the automatic unlock works again at the next launch

### Requirement: Move to another Mac

The app SHALL open a data folder that the user has copied from another Mac to the same place on a new Mac, with the same database password and with all data.

#### Scenario: New Mac

- **GIVEN** the app is installed on a new Mac and was started once
- **WHEN** the user quits it, replaces its data folder with the folder from the old Mac, and starts it
- **THEN** the app asks for the database password of the old Mac
- **AND** the app shows the same accounts, categories, transactions, and statements

### Requirement: No synchronization between copies

The app SHALL treat each copy of the data folder as independent. It does not merge two copies and sends no data from one Mac to another.

#### Scenario: Two Macs in parallel

- **GIVEN** the same data folder was copied to two Macs
- **WHEN** the user assigns a category to a transaction on the first Mac
- **THEN** the transaction on the second Mac keeps its earlier category
- **AND** both Macs fetch the same new transactions from the bank on their own

### Requirement: Reset after a lost password

The app SHALL start with a new and empty database when the user has renamed or removed the "Database" folder while the app was closed. The app neither deletes nor changes the renamed folder. Statements and extensions stay in place.

#### Scenario: Rename the folder

- **GIVEN** a user who forgot the database password
- **WHEN** the user quits the app, renames "Database" to "Database_OLD", and starts the app
- **THEN** the app starts without asking for the old password and offers to set a new one
- **AND** "Database_OLD" still holds the old database
- **AND** the statements in "Statements" are still there

#### Scenario: Password remembered later

- **GIVEN** the renamed folder "Database_OLD"
- **WHEN** the user quits the app, removes the new "Database" folder, renames "Database_OLD" back to "Database", and starts the app
- **THEN** the old password opens the old data

### Requirement: Take over the data of the old app name

The app SHALL, on its first start after the rename from MonetenMoneten (ADR 0013), move the data folder, the database files, the Keychain entries, and the settings of the old name to the new name. It SHALL replace nothing that already exists under the new name, and it SHALL keep using the old folder when the move fails.

#### Scenario: Update from a build with the old name

- **GIVEN** a data folder "MonetenMoneten" with a database that the Keychain unlocks
- **WHEN** the user starts Moneten for the first time
- **THEN** the folder is named "Moneten" and the database file "Moneten.sqlite"
- **AND** the database opens with the key that the Keychain held under the old name
- **AND** the Keychain no longer holds the entry of the old name

#### Scenario: Data under both names

- **GIVEN** a data folder "Moneten" and a data folder "MonetenMoneten"
- **WHEN** the app starts
- **THEN** both folders stay unchanged and the app opens "Moneten"
