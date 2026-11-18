# Spec Delta

## Purpose

The lock keeps the finances closed while the Mac itself is unlocked. This capability defines when the app locks, what a locked app shows and does, and how the user unlocks it with the password, Touch ID, or an Apple Watch.

## ADDED Requirements

### Requirement: Ask for the password at launch

The app SHALL show a lock screen at launch when a database password is set and "Unlock automatically at application start" is off. The lock screen has the field "Database password" and shows no data. The correct password opens the main window.

#### Scenario: Launch with a password

- **GIVEN** a database with a password and all unlock settings off
- **WHEN** the user starts the app and enters the password
- **THEN** the main window shows the accounts

#### Scenario: Wrong password at launch

- **WHEN** the user enters a wrong password on the lock screen
- **THEN** the app shows "Incorrect password!", clears the field, and stays locked

### Requirement: Lock by command

The app SHALL lock when the user chooses "Lock Moneten" in the application menu, presses ⌃⌘L, or clicks the lock button in the toolbar.

#### Scenario: Shortcut

- **GIVEN** the app is unlocked and shows an account
- **WHEN** the user presses ⌃⌘L
- **THEN** the main window shows the lock screen at once

### Requirement: A locked app shows no data

The app SHALL, while it is locked, show no account names, balances, transactions, or counterparties in any window, menu, or title. Windows that show data are hidden until the user unlocks the app. Commands that need data are disabled.

#### Scenario: Other windows

- **GIVEN** the account settings window and the log window are open
- **WHEN** the app locks
- **THEN** both windows are hidden
- **AND** they are visible again after the user unlocks the app

#### Scenario: Payment window in progress

- **GIVEN** a payment window with the recipient "Erika Mustermann" and the amount 120,00 €
- **WHEN** the app locks and the user unlocks it again
- **THEN** the payment window is back with the same entries
- **AND** the app sent nothing while it was locked

### Requirement: Locking closes the database

The app SHALL discard the database key from memory when it locks. Nothing can read or write the database until the user unlocks the app.

#### Scenario: Script access while locked

- **GIVEN** the app is locked
- **WHEN** a script asks the app to export transactions
- **THEN** the app answers with an error that says the database is locked
- **AND** the script receives no data

### Requirement: Lock when the main window closes

The app SHALL lock when the user closes the main window, if the setting "Lock when main window is closed" is on. The setting is off by default.

#### Scenario: Setting on

- **GIVEN** "Lock when main window is closed" is on
- **WHEN** the user closes the main window and opens it again with "Main Window"
- **THEN** the main window shows the lock screen

#### Scenario: Setting off

- **GIVEN** "Lock when main window is closed" is off
- **WHEN** the user closes the main window and opens it again
- **THEN** the main window shows the last view

### Requirement: Lock after inactivity

The app SHALL lock after the number of minutes without activity that the user sets under "Lock after ... minutes of inactivity", if that setting is on. Activity is keyboard or pointer input in the app. Time that the Mac sleeps counts as time without activity. The setting is on by default with 10 minutes.

#### Scenario: Default

- **GIVEN** a new installation
- **WHEN** the user opens Settings, Security
- **THEN** "Lock after inactivity" shows "10 minutes"

#### Scenario: Idle time passes

- **GIVEN** the setting is on with 10 minutes
- **WHEN** the user does not use the app for 10 minutes
- **THEN** the app is locked

#### Scenario: Activity resets the time

- **GIVEN** the setting is on with 10 minutes
- **WHEN** the user scrolls the transaction list after 9 minutes and waits 5 more minutes
- **THEN** the app is still unlocked

#### Scenario: Sleep

- **GIVEN** the setting is on with 10 minutes
- **WHEN** the Mac sleeps for 30 minutes and wakes up
- **THEN** the app is locked

### Requirement: Unlock automatically at launch

The app SHALL open the database at launch without a prompt when "Unlock automatically at application start" is on. This setting applies to the launch only. After a lock during the session, the app asks the user to unlock it.

#### Scenario: Launch

- **GIVEN** "Unlock automatically at application start" is on
- **WHEN** the user starts the app
- **THEN** the main window shows the accounts without a prompt

#### Scenario: Lock during the session

- **GIVEN** "Unlock automatically at application start" is on and the Touch ID and Apple Watch settings are off
- **WHEN** the user locks the app with ⌃⌘L
- **THEN** the lock screen asks for the database password

#### Scenario: Settings file changed outside the app

- **GIVEN** only "Unlock with Touch ID" is on
- **WHEN** a program changes the settings file of the app outside the app to turn on "Unlock automatically at application start", and the user starts the app
- **THEN** the lock screen asks for the database password

### Requirement: Unlock with Touch ID

The app SHALL offer Touch ID on the lock screen when "Unlock with Touch ID" is on. A recognized finger unlocks the app. When the user cancels the Touch ID request, the lock screen offers the password field.

#### Scenario: Finger recognized

- **GIVEN** "Unlock with Touch ID" is on and the app is locked
- **WHEN** the user opens the main window and puts a registered finger on the sensor
- **THEN** the app is unlocked

#### Scenario: Cancel

- **WHEN** the user cancels the Touch ID request
- **THEN** the lock screen shows the password field and a way to ask for Touch ID again

### Requirement: Unlock with Apple Watch

The app SHALL offer unlocking with an Apple Watch on the lock screen when "Unlock with Apple Watch" is on. A confirmation on the watch unlocks the app. With both settings on, the request names both, as in "Open with Touch ID or Apple Watch".

#### Scenario: Confirm on the watch

- **GIVEN** "Unlock with Apple Watch" is on, the app is locked, and the user wears an unlocked watch
- **WHEN** the user confirms the request with a double click on the side button of the watch
- **THEN** the app is unlocked

#### Scenario: No watch nearby

- **GIVEN** "Unlock with Apple Watch" is on and no watch is in range
- **WHEN** the lock screen appears
- **THEN** the app shows that no Apple Watch was detected nearby and offers the password field

### Requirement: The password always unlocks

The app SHALL accept the database password on the lock screen in every state, also when Touch ID or the Apple Watch is on, not available, or failed.

#### Scenario: Touch ID locked by macOS

- **GIVEN** macOS has locked Touch ID after too many failed attempts
- **WHEN** the lock screen appears
- **THEN** the app explains that Touch ID is locked and offers the password field
- **AND** the correct password unlocks the app

### Requirement: Unlock settings keep the password in the Keychain

The app SHALL store the database password in a Keychain entry of its own for each unlock setting that is turned on, and it SHALL delete exactly that entry when the setting is turned off. The entry holds only the password. Whether a setting is on is kept in the database. Only the launch reads the entry of "Unlock automatically at application start". The entries stay on this Mac and are not synced to other devices.

#### Scenario: Turn on the first setting

- **GIVEN** all three unlock settings are off
- **WHEN** the user turns on "Unlock with Touch ID" and enters the database password
- **THEN** the Keychain holds the database password

#### Scenario: Turn off the last setting

- **GIVEN** only "Unlock with Touch ID" is on
- **WHEN** the user turns it off
- **THEN** the Keychain holds no database password
- **AND** the next launch asks for the password

#### Scenario: Turn off the automatic unlock

- **GIVEN** "Unlock automatically at application start" and "Unlock with Touch ID" are on
- **WHEN** the user turns off "Unlock automatically at application start"
- **THEN** the next launch asks for the password or Touch ID
- **AND** Touch ID still unlocks the app

#### Scenario: Settings file changed after a setting was turned off

- **GIVEN** "Unlock with Apple Watch" is on and the user turned off "Unlock with Touch ID"
- **WHEN** a program changes the settings file of the app outside the app to turn on "Unlock with Touch ID"
- **THEN** the lock screen offers only the Apple Watch
- **AND** the confirmation on the watch unlocks the app with the entry of the Apple Watch

#### Scenario: Another data folder leaves the settings alone

- **GIVEN** "Unlock automatically at application start" and "Unlock with Touch ID" are on for the database in the data folder "Moneten"
- **WHEN** the user starts the app once with the data folder "Moneten-Test", creates a new database there, and quits
- **AND** the user starts the app with the data folder "Moneten"
- **THEN** the main window shows the accounts without a prompt
- **AND** "Unlock with Touch ID" is still on

### Requirement: The database holds the state of each unlock setting

The app SHALL keep whether each unlock setting is on in the encrypted database, where another program cannot write it. Turning a setting off writes "off" there before the app deletes the Keychain entry of the setting.

#### Scenario: Another program creates the entry of a setting that is off

- **GIVEN** "Unlock automatically at application start" is off
- **WHEN** another program creates the Keychain entry "Moneten database password for automatic unlock" for this database with the text "geraten"
- **AND** the user starts the app and unlocks it with the database password
- **THEN** "Unlock automatically at application start" is still off
- **AND** the Keychain holds no entry "Moneten database password for automatic unlock"
- **AND** the next launch asks for the database password

#### Scenario: The Keychain refuses to delete the entry

- **GIVEN** "Unlock automatically at application start" is on
- **WHEN** the user turns it off and the Keychain refuses to delete its entry
- **THEN** the setting shows off, and the app says that the password could not be deleted from the Keychain
- **AND** the next launch asks for the database password

### Requirement: An entry of a setting that is off never unlocks

The app SHALL unlock with a password from the Keychain only when the database has every unlock setting on that the request offered. Otherwise it closes the database again, asks for the database password, and offers only the settings that are on. Each unlock deletes the Keychain entries of the settings that are off.

#### Scenario: The entry of a setting that is off opens the database at launch

- **GIVEN** "Unlock automatically at application start" is off
- **AND** another program created the Keychain entry "Moneten database password for automatic unlock" for this database with the database password
- **WHEN** the user starts the app
- **THEN** the lock screen asks for the database password and says that the Keychain holds a password for an unlock setting that is off
- **AND** the Keychain holds no entry "Moneten database password for automatic unlock"

#### Scenario: The entry of Touch ID while Touch ID is off

- **GIVEN** "Unlock with Touch ID" is off
- **AND** another program created the Keychain entry "Moneten database password for Touch ID" for this database with the database password
- **WHEN** the user starts the app and confirms a Touch ID request with a registered finger
- **THEN** the app stays locked and asks for the database password
- **AND** the Keychain holds no entry "Moneten database password for Touch ID"

#### Scenario: An Apple Watch that is off next to Touch ID that is on

- **GIVEN** "Unlock with Touch ID" is on and "Unlock with Apple Watch" is off
- **AND** another program created the Keychain entry "Moneten database password for Apple Watch" for this database with the text "geraten"
- **WHEN** the user starts the app, and the request offers "Touch ID or Apple Watch" and the user confirms it on the watch
- **THEN** the app stays locked and asks for the database password
- **AND** the Keychain holds no entry "Moneten database password for Apple Watch"
- **AND** the lock screen offers Touch ID alone, and a registered finger unlocks the app

#### Scenario: Automatic unlock with an entry of a setting that is off

- **GIVEN** "Unlock automatically at application start" is on and "Unlock with Touch ID" is off
- **AND** another program created the Keychain entry "Moneten database password for Touch ID" for this database
- **WHEN** the user starts the app
- **THEN** the main window shows the accounts without a prompt
- **AND** the Keychain holds no entry "Moneten database password for Touch ID"

### Requirement: A database without the unlock state has every unlock setting off

The app SHALL treat every unlock setting of a database that holds no state for it as off, whatever entries the Keychain holds.

#### Scenario: A database from before this state

- **GIVEN** a database that a build before this change created, with "Unlock automatically at application start" on and its Keychain entry
- **WHEN** the user starts the app of this change
- **THEN** the lock screen asks for the database password
- **AND** after the unlock "Unlock automatically at application start" shows off and its Keychain entry is gone
- **AND** the user turns it on again on the "Security" tab, and the next launch opens without a prompt

### Requirement: A secret goes only into a Keychain entry of the app

The app SHALL write a password or a key into the Keychain only as a new entry that it creates, and it SHALL first remove an entry of the same name for the same database. The new entry has the access list that macOS gives a new entry, so another program cannot read it without a prompt of macOS. An entry that another program created never receives the secret, whatever its access list allows.

#### Scenario: Another program created the entry before

- **GIVEN** another program created the Keychain entry "Moneten database password for Touch ID" for this database with an access list that lets every app read it
- **WHEN** the user turns on "Unlock with Touch ID" and enters the database password
- **THEN** that entry is gone
- **AND** the Keychain holds the database password in a new entry whose access list names only the app

#### Scenario: Password change with an entry of another program

- **GIVEN** "Unlock automatically at application start" is on and another program replaced its entry with one that lets every app read it
- **WHEN** the user changes the database password to "neu-und-noch-laenger"
- **THEN** the Keychain holds "neu-und-noch-laenger" in a new entry whose access list names only the app

#### Scenario: The Keychain refuses the new entries after the old ones are gone

- **GIVEN** "Unlock automatically at application start" and "Unlock with Touch ID" are on
- **WHEN** the user changes the database password and the Keychain removes each entry but refuses each new one
- **THEN** the app shows that the Keychain did not accept the new password
- **AND** both settings are off, and no entry holds the earlier password

#### Scenario: A locked Keychain at an unlock

- **GIVEN** "Unlock with Touch ID" is on, and its entry holds an earlier password of a database that the user restored from a backup
- **WHEN** the user unlocks with the password, and the Keychain is locked and the user cancels the prompt that unlocks it
- **THEN** the app shows that the password could not be stored in the Keychain
- **AND** "Unlock with Touch ID" is still on

#### Scenario: The Keychain refuses a new entry at an unlock

- **GIVEN** "Unlock with Touch ID" is on, and its entry holds an earlier password of a database that the user restored from a backup
- **WHEN** the user unlocks with the password and the Keychain removes the entry but refuses the new one
- **THEN** the app shows that the password could not be stored in the Keychain
- **AND** "Unlock with Touch ID" is off, and the lock screen no longer offers Touch ID

### Requirement: Keychain entries stay in the login keychain

The app SHALL add, read, and delete its Keychain entries only in the login keychain of the user, the file `~/Library/Keychains/login.keychain-db`. It SHALL NOT use the default keychain or the keychain search list of the user, because another program of the user can change both without a prompt. No environment variable changes the keychain file of a release build. When the app cannot open the login keychain, it stores no secret in any keychain and shows that the login keychain cannot be opened.

#### Scenario: Another program made its own keychain the default

- **GIVEN** "Unlock automatically at application start" is on with the database password "korrekt-pferd-batterie", and its entry in the login keychain holds the earlier password "alt-und-lang-genug" of a database that the user restored from a backup
- **AND** another program created the keychain "andere.keychain-db", made it the default keychain and the first one of the search list, and put the entry "Moneten database password for automatic unlock" with "falsches-passwort" into it
- **WHEN** the user unlocks with "korrekt-pferd-batterie"
- **THEN** the entry in the login keychain holds "korrekt-pferd-batterie"
- **AND** the entry in "andere.keychain-db" still holds "falsches-passwort", and that keychain holds no other entry of the app

#### Scenario: An entry in another keychain never counts

- **GIVEN** "Unlock automatically at application start" is on, its entry is gone from the login keychain, and another program put an entry with the database password into its own default keychain
- **WHEN** the app launches
- **THEN** the app asks for the database password

#### Scenario: A new database while another keychain is the default

- **GIVEN** another program made the keychain "andere.keychain-db" the default keychain
- **WHEN** the user creates a new database without a password
- **THEN** the login keychain holds the random key of the database
- **AND** "andere.keychain-db" holds no entry of the app

#### Scenario: An environment variable names another keychain file

- **GIVEN** another program ran `launchctl setenv MONETEN_KEYCHAIN_PATH /Users/Shared/andere.keychain-db`, and that file is a keychain without an entry of the app
- **WHEN** the user starts the app and creates a new database without a password
- **THEN** the login keychain holds the random key of the database
- **AND** "andere.keychain-db" holds no entry of the app

#### Scenario: The login keychain cannot be opened

- **GIVEN** the file `~/Library/Keychains/login.keychain-db` is missing
- **WHEN** the user turns on "Unlock automatically at application start" and enters the database password
- **THEN** the setting is still off
- **AND** the app shows that the login keychain cannot be opened
- **AND** no keychain holds the database password

### Requirement: A run of the debug harness keeps to its own data folder and keychain file

The app SHALL, in a Debug or Perf build, exit with status 2 at launch, before it opens a data folder or a keychain, when the debug harness drives the run and the run does not name both a data folder and a keychain file of its own, and when any run names a keychain file of its own but no data folder of its own. An unlock in a run that opens the real database with a throwaway keychain file would turn off the unlock settings of the real database, and the crash reports would lose their key.

#### Scenario: A harness run without a data folder of its own

- **GIVEN** a Debug build of the app, whose real database has "Unlock automatically at application start" on
- **WHEN** a check starts it with `MONETEN_DEBUG_DIR=/tmp/harness/debug` and `MONETEN_KEYCHAIN_PATH=/tmp/harness/run.keychain-db`, without `MONETEN_DATA_DIR`
- **THEN** the app exits with status 2 and names `MONETEN_DATA_DIR` on standard error
- **AND** no file in `~/Library/Application Support/Moneten` changed, and "Unlock automatically at application start" is still on

#### Scenario: A harness run without a keychain file of its own

- **GIVEN** a Debug build of the app
- **WHEN** a check starts it with `MONETEN_DEBUG_DIR=/tmp/harness/debug` and `MONETEN_DATA_DIR=/tmp/harness/data`, without `MONETEN_KEYCHAIN_PATH`
- **THEN** the app exits with status 2 and names `MONETEN_KEYCHAIN_PATH` on standard error
- **AND** the login keychain holds no new entry of the app, and `/tmp/harness/data` holds no database

#### Scenario: A debug build started by hand with a keychain file but without a data folder

- **GIVEN** a Debug build of the app, whose real database has "Unlock with Touch ID" on
- **WHEN** the developer starts it with `MONETEN_KEYCHAIN_PATH=/tmp/check/run.keychain-db`, without `MONETEN_DEBUG_DIR` and `MONETEN_DATA_DIR`
- **THEN** the app exits with status 2 and names `MONETEN_DATA_DIR` on standard error
- **AND** no file in `~/Library/Application Support/Moneten` changed, and "Unlock with Touch ID" is still on

#### Scenario: A debug build without the harness

- **GIVEN** a Debug build of the app
- **WHEN** the developer starts it without `MONETEN_DEBUG_DIR`, `MONETEN_DATA_DIR`, and `MONETEN_KEYCHAIN_PATH`
- **THEN** the app opens the real database with the login keychain

### Requirement: Report a Keychain failure

The app SHALL leave an unlock setting off when it cannot store the password or the configuration in the Keychain, and it tells the user that the Keychain did not accept the entry.

#### Scenario: Keychain refuses the entry

- **WHEN** the user turns on "Unlock automatically at application start" and the Keychain returns an error
- **THEN** the setting is still off
- **AND** the app shows that the password could not be stored in the Keychain

### Requirement: The Keychain entry follows a password change

The app SHALL replace the password in the Keychain when the user changes the database password while an unlock setting is on.

#### Scenario: Change with Touch ID on

- **GIVEN** "Unlock with Touch ID" is on
- **WHEN** the user changes the database password and locks the app
- **THEN** Touch ID still unlocks the app

### Requirement: Explain why Touch ID is not available

The app SHALL explain why Touch ID cannot be used when the user turns on "Unlock with Touch ID" on a Mac without a sensor, or before Touch ID is set up in macOS. The message for the second case names the place in the system settings. The setting stays off in both cases.

#### Scenario: Mac without a sensor

- **WHEN** the user turns on "Unlock with Touch ID" on a Mac without a fingerprint sensor
- **THEN** the app shows that this Mac has no Touch ID sensor
- **AND** the setting is off

#### Scenario: Touch ID not set up

- **WHEN** the user turns on the setting and no finger is registered in macOS
- **THEN** the app asks the user to set up Touch ID first and names "System Settings → Touch ID & Password"

### Requirement: No Touch ID request while the lid is closed

The app SHALL NOT start a Touch ID request while the lid of a MacBook is closed and no external Touch ID sensor is connected. The lock screen offers the password field and the Apple Watch instead.

#### Scenario: Closed lid with an external display

- **GIVEN** a MacBook with a closed lid on an external display and "Unlock with Touch ID" on
- **WHEN** the lock screen appears
- **THEN** no Touch ID request appears
- **AND** the lock screen shows the password field

### Requirement: Explain why the Apple Watch is not available

The app SHALL explain why the Apple Watch cannot be used when the user turns on "Unlock with Apple Watch" before unlocking with Apple Watch is set up in macOS. The message names the place in the system settings, and the setting stays off.

#### Scenario: Not set up in macOS

- **WHEN** the user turns on "Unlock with Apple Watch" and macOS has no watch approved for unlocking
- **THEN** the app asks the user to set this up in the system settings first
- **AND** the setting is off

### Requirement: Clear a typed password after five minutes

The app SHALL remove a database password that the user typed and did not submit from the password field after five minutes without input.

#### Scenario: Half-typed password

- **GIVEN** the lock screen with 8 typed characters in the password field
- **WHEN** nobody touches the Mac for five minutes
- **THEN** the password field is empty

### Requirement: Security settings need the password

The app SHALL ask for the database password before it changes one of the settings on the "Security" tab. A wrong password leaves the setting unchanged. The app keeps "Lock when main window is closed" and "Lock after inactivity" in the encrypted database, so a change of the settings file of the app outside the app neither opens the database nor weakens the lock.

#### Scenario: Turn off the inactivity lock

- **GIVEN** "Lock after 10 minutes of inactivity" is on
- **WHEN** a person turns the setting off and cannot enter the database password
- **THEN** the setting is still on

#### Scenario: Correct password

- **WHEN** the user turns on "Lock when main window is closed" and enters the database password
- **THEN** the setting is on

#### Scenario: Settings file changed outside the app

- **GIVEN** "Lock after 10 minutes of inactivity" and "Lock when main window is closed" are on
- **WHEN** a program changes the settings file of the app outside the app to turn both settings off
- **THEN** the app still locks after 10 minutes without activity
- **AND** the app still locks when the user closes the main window

### Requirement: A locked app does no work with the data

The app SHALL NOT refresh accounts, download statements, run rules, or serve automation requests while it is locked. Work that became due while the app was locked starts after the user unlocks it.

#### Scenario: Automatic refresh becomes due

- **GIVEN** "Automatically refresh accounts" is on and the app is locked
- **WHEN** the time for the next refresh comes
- **THEN** the app contacts no bank
- **AND** the refresh starts after the user unlocks the app

### Requirement: Help for a forgotten password

The app SHALL show "Forgot your password?" on the lock screen. It explains that the password cannot be recovered and leads to the instructions for resetting the database.

#### Scenario: Open the help

- **WHEN** the user clicks "Forgot your password?" on the lock screen
- **THEN** the app explains that there is no way to recover the password
- **AND** the app shows how to reset the database and start empty

### Requirement: Lock needs a database password

The app SHALL disable the lock command, the lock button, and the settings on the "Security" tab while no database password is set, and it SHALL point to "Set Database Password..." in their place.

#### Scenario: No password set

- **GIVEN** a database without a password
- **WHEN** the user opens the "Security" settings
- **THEN** the lock and unlock settings are disabled
- **AND** the tab offers "Set Database Password..."
