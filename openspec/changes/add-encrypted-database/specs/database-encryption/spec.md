# Spec Delta

## Purpose

The database holds everything the app knows about the user's money. This capability defines what the database protects, how the user's password becomes its key, and how the app opens, checks, and upgrades the file without losing data.

## ADDED Requirements

### Requirement: All personal data is in one encrypted database

The app SHALL store login data, balances, transactions, categories, rules, comments, templates, and payment records in one database file that is encrypted with 256-bit AES. Temporary files and journal files of the database are encrypted in the same way.

#### Scenario: The file shows no readable data

- **GIVEN** a database with an account that has the IBAN DE02120300000000202051 and a transaction with the counterparty "Stadtwerke Musterstadt"
- **WHEN** a person searches the bytes of the database file and of its journal file for these two texts
- **THEN** neither text is found

#### Scenario: A copy in a backup is protected

- **GIVEN** a Time Machine backup that contains the database file
- **WHEN** a person opens the copy without the database password
- **THEN** the copy cannot be read

### Requirement: The database password is the key

The app SHALL derive the key of the database from the database password with a key derivation function that is slow by design. The app writes neither the password nor the key into the database folder.

#### Scenario: Open on another Mac

- **GIVEN** a database with the password "korrekt-pferd-batterie-heftklammer"
- **WHEN** the user copies the database to another Mac and enters that password
- **THEN** the app opens the database with all data

#### Scenario: Wrong password

- **GIVEN** a database with the password "korrekt-pferd-batterie-heftklammer"
- **WHEN** a person enters "korrekt-pferd"
- **THEN** the app does not open the database and shows "Incorrect password!"

### Requirement: Offer a password at first launch

The app SHALL show the sheet "Set Database Password" when it starts for the first time, before the user adds an account. The user can set a password or skip the step.

#### Scenario: Set at first launch

- **WHEN** the user starts the app for the first time and enters the same password twice
- **THEN** the app creates the database with that password as its key
- **AND** the app asks for the password at the next launch

#### Scenario: Skip

- **WHEN** the user starts the app for the first time and skips the sheet
- **THEN** the app creates the database and opens the main window without a password

### Requirement: A database without a password uses a random key

The app SHALL, while no database password is set, encrypt the database with a random key that it keeps in the Keychain of the user. The app shows a hint in the sidebar that no password protects the data, and a click on the hint opens "Set Database Password...".

#### Scenario: Hint in the sidebar

- **GIVEN** a database without a password
- **WHEN** the user opens the main window
- **THEN** the sidebar shows the hint
- **AND** the app opens at launch without asking for a password

#### Scenario: File copied without the Keychain

- **GIVEN** a database without a password
- **WHEN** a person copies only the database file to another Mac
- **THEN** the copy cannot be opened there

### Requirement: Set a password later

The app SHALL offer "Set Database Password..." in the application menu and in the "Security" settings while no password is set. Setting a password encrypts the database with the new key and removes the random key from the Keychain.

#### Scenario: Set after some weeks of use

- **GIVEN** a database without a password that holds 3 accounts
- **WHEN** the user chooses "Set Database Password..." and enters a password twice
- **THEN** all 3 accounts and their transactions are still present
- **AND** the hint in the sidebar is gone
- **AND** the Keychain no longer holds a key for the database

### Requirement: The new password is entered twice

The app SHALL ask for a new password in the fields "New password" and "Repeat new password" and accept it only when both fields hold the same text. Any text that is not empty is a valid password.

#### Scenario: Fields differ

- **WHEN** the user enters "Sommer2026!" and then "Sommer2026"
- **THEN** the app shows that the new passwords differ
- **AND** the app sets no password

#### Scenario: Empty password

- **WHEN** the user leaves both fields empty
- **THEN** the button that confirms the sheet is disabled

### Requirement: Show the strength of a new password

The app SHALL show a grade for the strength of a new password while the user types it. The grades are "weak", "good", "strong", and "excellent". The grade informs the user and does not block a weak password.

#### Scenario: Short password

- **WHEN** the user types "abc123"
- **THEN** the sheet shows "weak"

#### Scenario: Long passphrase

- **WHEN** the user types "korrekt-pferd-batterie-heftklammer"
- **THEN** the sheet shows "excellent"

### Requirement: Warn that a forgotten password cannot be recovered

The app SHALL state, in the sheet that sets or changes the password, that nobody can recover a forgotten database password and that the data is lost without it. The user must confirm this statement before the app sets a first password.

#### Scenario: Confirm the warning

- **WHEN** the user enters a new password twice at first launch and has not confirmed the warning
- **THEN** the app does not set the password
- **AND** the app points to the warning

### Requirement: Change the password

The app SHALL offer "Change Database Password..." while a password is set. The sheet asks for the "Current password" and for the new password twice. The new password must differ from the current one. After the change, only the new password opens the database.

#### Scenario: Successful change

- **GIVEN** a database with the password "alt-und-lang-genug"
- **WHEN** the user enters "alt-und-lang-genug" as the current password and "neu-und-noch-laenger" twice as the new one
- **THEN** the app shows that the password has been changed
- **AND** at the next launch "neu-und-noch-laenger" opens the database and "alt-und-lang-genug" does not

#### Scenario: Wrong current password

- **WHEN** the user enters a wrong current password
- **THEN** the app shows "Incorrect password!" and changes nothing

#### Scenario: Same password again

- **WHEN** the user enters the current password as the new password
- **THEN** the app shows that the new password must not be identical to the old password

### Requirement: A failed password change leaves the database usable

The app SHALL keep the database readable with the earlier password when a password change fails, for example because the disk is full.

#### Scenario: Disk full during the change

- **GIVEN** a database with the password "alt-und-lang-genug"
- **WHEN** the change to a new password fails
- **THEN** the app shows that it could not change the password
- **AND** "alt-und-lang-genug" still opens the database with all data

### Requirement: No way around the password

The app SHALL NOT offer any way to open a database without its password. It has no password hint, no recovery key, and no reset that keeps the data. Wrong attempts neither erase data nor block later attempts.

#### Scenario: Many wrong attempts

- **GIVEN** a database with a password
- **WHEN** a person enters 20 wrong passwords
- **THEN** the database is unchanged
- **AND** the correct password opens it on the next attempt

### Requirement: Show progress while the database opens

The app SHALL tell the user what it does while it opens the database. It shows "Opening database..." while it opens and checks the file, and "Upgrading database..." while it upgrades the file after an update of the app.

#### Scenario: Large database after an update

- **GIVEN** a database with 50,000 transactions from an earlier version of the app
- **WHEN** the user starts the new version and enters the password
- **THEN** the app shows "Upgrading database..." until the main window appears

### Requirement: Check the integrity of the database when it opens

The app SHALL check the integrity of the database when it opens it. When the check fails, the app tells the user that the file is damaged, keeps the damaged file, and tries a repair at the next start. When the repair fails, the app asks the user to replace the file with a backup copy.

#### Scenario: Repair succeeds

- **GIVEN** a database file with a damaged page
- **WHEN** the user starts the app twice
- **THEN** the first start reports the damage and announces the repair
- **AND** the second start opens the repaired database
- **AND** a copy of the damaged file is still in the database folder

#### Scenario: Repair fails

- **GIVEN** a database file that cannot be repaired
- **WHEN** the user starts the app after the repair attempt
- **THEN** the app asks the user to replace the database file with a backup copy
- **AND** the app does not create a new empty database in its place

### Requirement: Upgrade the database safely

The app SHALL, when an update of the app needs a new database layout, first save a backup copy of the database in the database folder, then upgrade a temporary copy, check the layout and the integrity of that copy, and only then replace the database.

#### Scenario: Upgrade succeeds

- **GIVEN** a database from version 0.1
- **WHEN** the user starts version 0.2 for the first time
- **THEN** the database folder holds a backup copy with the state of version 0.1
- **AND** the app opens the upgraded database with all data

#### Scenario: Upgrade fails

- **GIVEN** a database from version 0.1 and too little free disk space
- **WHEN** the user starts version 0.2
- **THEN** the app shows that it could not upgrade the database
- **AND** the database of version 0.1 is unchanged and still opens with version 0.1

### Requirement: Refuse a database from a newer version

The app SHALL refuse to open a database that a newer version of the app has upgraded. The message names the lowest version that can open the database and the version that is running. The app does not change the file.

#### Scenario: Older app, newer database

- **GIVEN** a database that version 0.3 has upgraded
- **WHEN** the user starts version 0.2
- **THEN** the app shows that at least version 0.3 is needed and that version 0.2 is running
- **AND** the database file is unchanged

### Requirement: Only one running copy uses the database

The app SHALL refuse to open a database that another running copy of the app has open, and it tells the user that the database is in use.

#### Scenario: Second copy

- **GIVEN** the app is running and has the database open
- **WHEN** the user starts a second copy of the app from another folder
- **THEN** the second copy shows that the database is in use by another application
- **AND** the second copy writes nothing to the database

### Requirement: Detect a change of the database on disk

The app SHALL notice when the database file was replaced or changed outside the app while the app is running. It then stops writing, tells the user that the database has been changed on disk, and offers to load the database again.

#### Scenario: File restored from a backup while the app runs

- **GIVEN** the app is running
- **WHEN** a backup tool replaces the database file with an older copy
- **THEN** the app shows that the database has been changed on disk
- **AND** the app writes nothing until the user has loaded the database again

### Requirement: Explain every problem with the database file

The app SHALL show a separate message for each of these cases, with the path of the file and what the user can do. The database file has no content. The path of the database file is a folder. The file is write-protected. The user account has no write permission for the database folder. The app starts a new database only when the database folder holds no files.

#### Scenario: Write-protected file

- **GIVEN** a database file without write permission
- **WHEN** the user starts the app
- **THEN** the app shows that the database file is write-protected, with its path
- **AND** the app does not start with an empty database

#### Scenario: File without content

- **GIVEN** a database file with a size of 0 bytes
- **WHEN** the user starts the app
- **THEN** the app asks the user to replace the file with a backup copy

#### Scenario: Empty folder

- **GIVEN** a database folder without files
- **WHEN** the user starts the app
- **THEN** the app starts with a new database and offers to set a password

### Requirement: Mention the automatic backup copy when the database cannot be opened

The app SHALL, when it cannot open the database and an automatic backup copy from an earlier upgrade exists in the database folder, tell the user that this copy exists and how to restore it.

#### Scenario: Backup copy present

- **GIVEN** a damaged database and an automatic backup copy from the last upgrade
- **WHEN** the app cannot open the database
- **THEN** the message names the backup copy and says that renaming it restores the earlier state

### Requirement: Do not open a database file from the Finder

The app SHALL NOT load a database file that the user opens from the Finder or drops on the app. It tells the user to launch the app instead and continues with its own database.

#### Scenario: Double click on the database file

- **WHEN** the user opens a database file with the app from the Finder
- **THEN** the app shows that the database file must not be opened directly
- **AND** the app keeps using the database in its data folder
