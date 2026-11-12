# Spec Delta

## Purpose

Every bank access needs a secret, for example a PIN, a password, or a token. This capability defines how the app asks for such a secret, how long it keeps it, when it saves it, and how the user removes it. The same rules apply to FinTS, to extensions, and to the subscription.

## ADDED Requirements

### Requirement: PIN sheet names the access

The app SHALL ask for a PIN or password in a sheet that shows the name of the account, the name of the bank, and the user ID of the access. The sheet uses the word that the bank uses for the secret. It has "Cancel" and a button to confirm.

#### Scenario: Refresh without a known PIN

- **GIVEN** the account "Giro" at "Musterbank" with the user ID "erika77" and no available PIN
- **WHEN** the user refreshes "Giro"
- **THEN** a sheet asks for the PIN and shows "Giro", "Musterbank", and "erika77"

#### Scenario: Extension with a password

- **GIVEN** an extension calls its secret "password"
- **WHEN** the app needs the secret of an access of that extension
- **THEN** the sheet asks for the password

### Requirement: Hidden entry

The app SHALL hide the characters of a PIN or password while the user types it, and it SHALL not offer the entry to the password manager of macOS. The value cannot be copied from the field.

#### Scenario: Typing a PIN

- **WHEN** the user types "12345" into the PIN sheet
- **THEN** the field shows five dots
- **AND** "Copy" is disabled for the field

### Requirement: Check a PIN against the rules of the bank

The app SHALL check a PIN against the rules that the bank publishes for it before it sends the PIN, and it SHALL name the broken rule. The rules cover digits only, the minimum length, and the maximum length.

#### Scenario: Letters in a numeric PIN

- **GIVEN** "Musterbank" accepts only digits in the PIN
- **WHEN** the user enters "12a45" and confirms
- **THEN** the app says that the PIN must be numeric and sends nothing to the bank

#### Scenario: PIN too long

- **GIVEN** "Musterbank" accepts at most 5 digits
- **WHEN** the user enters "123456"
- **THEN** the app says that the PIN is too long and that the maximum is 5 digits

### Requirement: Save a PIN only on request

The app SHALL save a PIN only when the user turns on the option to save it for that access. The option is off when the sheet first appears for an access.

#### Scenario: Option left off

- **WHEN** the user enters the PIN, leaves the save option off, and confirms
- **THEN** the app does not store the PIN in the database

#### Scenario: Option turned on

- **WHEN** the user enters the PIN, turns on the save option, and confirms, and the bank accepts the PIN
- **THEN** the app stores the PIN for that access
- **AND** the next refresh after a restart of the app does not ask for the PIN

### Requirement: A PIN is saved only after the bank accepted it

The app SHALL store a PIN that the user asked to save only after a login with that PIN succeeded.

#### Scenario: Wrong PIN with the save option on

- **WHEN** the user turns on the save option, enters a wrong PIN, and the bank rejects it
- **THEN** the app stores no PIN for that access

### Requirement: Saved PINs live in the encrypted database

The app SHALL keep a saved PIN only inside the encrypted database. The Keychain and the settings files of the app hold no PIN. A backup of the database contains the saved PINs and protects them with the database password.

#### Scenario: Look in the Keychain

- **GIVEN** an access with a saved PIN
- **WHEN** the user searches the Keychain for entries of the app
- **THEN** no entry contains the PIN

#### Scenario: Restore on another Mac

- **GIVEN** a backup of a database with a saved PIN
- **WHEN** the user restores the backup on another Mac and unlocks it with the database password
- **THEN** a refresh of that access does not ask for the PIN

### Requirement: An unsaved PIN stays in memory until the app locks or quits

The app SHALL keep a PIN that is not saved in memory after a successful login and reuse it for that access. The app forgets it when the app locks and when the app quits.

#### Scenario: Second refresh in one session

- **GIVEN** the user entered the PIN of "Giro" without saving it
- **WHEN** the user refreshes "Giro" again ten minutes later
- **THEN** the app does not ask for the PIN

#### Scenario: After a lock

- **GIVEN** the user entered the PIN of "Giro" without saving it
- **WHEN** the app locks, the user unlocks it, and refreshes "Giro"
- **THEN** the app asks for the PIN again

### Requirement: Remove a saved PIN

The app SHALL offer the button "Remove saved PIN" in the account settings of an account whose access has a saved PIN. The button deletes the saved PIN of the access, which affects all accounts of that access. The button is disabled when no PIN is saved.

#### Scenario: Remove

- **GIVEN** the access of "Giro" and "Savings" has a saved PIN
- **WHEN** the user clicks "Remove saved PIN" in the settings of "Giro" and clicks "OK"
- **THEN** the next refresh of "Savings" after a restart asks for the PIN

#### Scenario: Nothing saved

- **WHEN** the user opens the settings of an account whose access has no saved PIN
- **THEN** "Remove saved PIN" is disabled

### Requirement: TANs are never saved

The app SHALL not store a TAN in the database, in the Keychain, in a settings file, or in a log.

#### Scenario: After a login with a TAN

- **GIVEN** the user entered the TAN 123456 for a login
- **WHEN** the user exports all data of the app and saves the log
- **THEN** neither file contains 123456 as a TAN

### Requirement: Secrets stay inside the encrypted database

The app SHALL never write a PIN, a password, a TAN, or a session secret to a log, a crash report, a notification, an export file, a settings file, or the pasteboard.

#### Scenario: Failed login in the log

- **GIVEN** the user entered the PIN "48151" for the access of "Girokonto"
- **WHEN** the bank rejects the login and the app records the error
- **THEN** the record names the bank and the error
- **AND** the record does not contain "48151"

#### Scenario: Full export

- **WHEN** the user exports all data to a file
- **THEN** the file contains no PIN and no password

### Requirement: No automatic retry after a wrong PIN

The app SHALL, when a bank rejects a PIN, stop the login, delete the saved PIN of that access, forget the PIN in memory, and not send the same PIN again. It shows the message of the bank and warns that more wrong attempts can block the access.

#### Scenario: Saved PIN no longer valid

- **GIVEN** the user changed the PIN on the bank website and the app still has the old PIN saved
- **WHEN** the automatic refresh logs in and the bank rejects the PIN
- **THEN** the app sends no second login with that PIN
- **AND** the account shows an error with the message of the bank
- **AND** the next manual refresh asks for the PIN

#### Scenario: Typing error

- **WHEN** the user enters a wrong PIN in the sheet
- **THEN** the sheet appears again with an empty field and the warning about blocked access

#### Scenario: Blocked access

- **GIVEN** the app has the PIN of "Musterbank" saved
- **WHEN** the bank answers a login with 9930 "Zugang gesperrt"
- **THEN** the app deletes the saved PIN and forgets the PIN in memory
- **AND** no PIN sheet opens

### Requirement: Cancel the PIN sheet

The app SHALL, when the user cancels the PIN sheet, skip the accounts of that access for the running refresh and continue with the other accesses. A canceled sheet is not an error of the bank.

#### Scenario: Cancel one of two

- **GIVEN** a manual refresh of all accounts needs the PINs of "Musterbank" and "Beispielbank"
- **WHEN** the user cancels the sheet for "Musterbank" and enters the PIN for "Beispielbank"
- **THEN** the accounts of "Beispielbank" are refreshed
- **AND** the accounts of "Musterbank" keep their last state

### Requirement: One PIN sheet at a time

The app SHALL show only one PIN sheet at a time when several accesses need a PIN, and show the next one after the user answered the first.

#### Scenario: Three accesses without a PIN

- **GIVEN** three accesses with no available PIN
- **WHEN** the user chooses "Refresh All Accounts"
- **THEN** the app shows the sheet for the first access
- **AND** it shows the sheet for the second access after the user confirmed or canceled the first

### Requirement: Automatic refresh skips an access without a PIN

The app SHALL not show a PIN sheet for an automatic refresh. It skips an access whose PIN is neither saved nor in memory, marks the accounts of that access in the sidebar as waiting for the PIN, and refreshes them at the next manual refresh.

#### Scenario: PIN not saved, app was locked

- **GIVEN** the access of "Giro" has no saved PIN and the app was locked and unlocked since the last refresh
- **WHEN** the automatic refresh runs
- **THEN** no sheet appears
- **AND** the sidebar row of "Giro" shows that the PIN is needed
- **AND** "Refresh All Accounts" asks for the PIN of "Giro"

### Requirement: One set of rules for all access kinds

The app SHALL apply the same rules to the secrets of extensions and of the subscription as to FinTS PINs. A secret is saved only on request, a saved secret lives in the encrypted database, and an unsaved secret is forgotten when the app locks or quits.

#### Scenario: Extension password not saved

- **GIVEN** an account of an extension whose password the user did not save
- **WHEN** the app locks, the user unlocks it, and refreshes the account
- **THEN** the app asks for the password again

#### Scenario: Extension password saved

- **GIVEN** the user saved the password of an extension access
- **WHEN** the user clicks "Remove saved PIN" in the settings of an account of that access
- **THEN** the saved password is deleted
