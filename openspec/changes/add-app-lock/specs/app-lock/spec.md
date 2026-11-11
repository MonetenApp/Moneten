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

The app SHALL store the database password in the Keychain of the user when the first of the three unlock settings is turned on, and it SHALL delete the password from the Keychain when the last of them is turned off. The entry stays on this Mac and is not synced to other devices.

#### Scenario: Turn on the first setting

- **GIVEN** all three unlock settings are off
- **WHEN** the user turns on "Unlock with Touch ID" and enters the database password
- **THEN** the Keychain holds the database password

#### Scenario: Turn off the last setting

- **GIVEN** only "Unlock with Touch ID" is on
- **WHEN** the user turns it off
- **THEN** the Keychain holds no database password
- **AND** the next launch asks for the password

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

The app SHALL ask for the database password before it changes one of the settings on the "Security" tab. A wrong password leaves the setting unchanged.

#### Scenario: Turn off the inactivity lock

- **GIVEN** "Lock after 10 minutes of inactivity" is on
- **WHEN** a person turns the setting off and cannot enter the database password
- **THEN** the setting is still on

#### Scenario: Correct password

- **WHEN** the user turns on "Lock when main window is closed" and enters the database password
- **THEN** the setting is on

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
