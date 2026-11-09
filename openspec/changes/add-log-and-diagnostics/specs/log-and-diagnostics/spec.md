# Spec Delta

## Purpose

The log lets the user and helpers see what the app did when something goes wrong. This capability defines what the app records, what the log must never contain, how the user reads and shares the log, and how the app reports errors.

## ADDED Requirements

### Requirement: Log window

The app SHALL open a log window when the user chooses "Log Window" in the Window menu or presses ⌘L. The window lists the log entries in the order of time with the newest entry at the bottom, and each entry starts with its date and time.

#### Scenario: Open the log

- **WHEN** the user presses ⌘L after a refresh
- **THEN** the log window shows the entries of that refresh with their times
- **AND** the newest entry is visible

#### Scenario: New entries while the window is open

- **GIVEN** the log window is open and scrolled to the end
- **WHEN** a refresh writes new entries
- **THEN** the entries appear in the window at once

### Requirement: What the log records

The app SHALL record the start of the app with its version and the version of macOS, the database file that it loaded, each refresh with its start, its end, and its result for each access, each connection with the name of the server, the messages and return codes of the bank, each error, and each update of the app or of its data files.

#### Scenario: Launch

- **WHEN** the user starts the app and opens the log
- **THEN** the first entries name the version of the app, the version of macOS, and the path of the database file

#### Scenario: Bank message

- **GIVEN** a bank answers a login with the code 9340 and a text
- **WHEN** the user opens the log
- **THEN** an entry holds the code 9340 and the text of the bank

### Requirement: The log never contains secrets

The app SHALL NOT write a PIN, a TAN, a password, a cookie, an access token, or key material into the log. No setting turns this rule off. The rule also covers the output of extensions and of the FinTS part.

#### Scenario: Login with full detail

- **GIVEN** full detail is on and the user logs in with the PIN "48151"
- **WHEN** a person searches the log window and the log file for "48151"
- **THEN** the text is not found

#### Scenario: Extension prints a token

- **GIVEN** an extension writes a line with a session token to its output
- **WHEN** the line reaches the log
- **THEN** the token is replaced by a placeholder

### Requirement: Personal data appears as placeholders

The app SHALL replace IBANs, account numbers, user IDs, names, amounts, and purpose texts in the log with placeholders that name the kind of value. This is the normal state of the log.

#### Scenario: Refresh of an account

- **GIVEN** an account with the IBAN DE02120300000000202051 and a new transaction of -89,00 € to "Stadtwerke Musterstadt"
- **WHEN** the user opens the log after the refresh
- **THEN** the entries show that 1 transaction arrived
- **AND** the log contains neither the IBAN, nor the amount, nor the name

### Requirement: Full detail for one refresh

The app SHALL let the user turn on full detail for the next refresh of one access. Before it does so, the app warns that the log will then hold names, account numbers, and amounts. Full detail ends by itself when that refresh has ended.

#### Scenario: Turn on full detail

- **WHEN** the user turns on full detail for the access of "Girokonto" and confirms the warning
- **THEN** the entries of the next refresh of that access show the messages of the bank with their real values
- **AND** the refresh after that shows placeholders again

#### Scenario: Other accesses

- **GIVEN** full detail is on for the access of "Girokonto"
- **WHEN** all accounts are refreshed
- **THEN** the entries of every other access show placeholders

### Requirement: Full detail never reaches the disk

The app SHALL keep entries with full detail in memory only. The log file on disk always holds the version with placeholders, and the entries with full detail are gone when the app quits or locks.

#### Scenario: Quit after a refresh with full detail

- **GIVEN** a refresh ran with full detail
- **WHEN** the user quits the app and a person reads the log file on disk
- **THEN** the file holds placeholders for that refresh

### Requirement: Clear the log

The app SHALL offer "Clear" in the log window. It removes all entries from the window and from the log file.

#### Scenario: Clear

- **WHEN** the user clicks "Clear"
- **THEN** the log window is empty
- **AND** the log file holds no earlier entries

### Requirement: Copy the log

The app SHALL offer "Copy to Pasteboard" in the log window. It copies the selected entries, or all entries when nothing is selected, as text.

#### Scenario: Copy a selection

- **WHEN** the user selects 5 entries and clicks "Copy to Pasteboard"
- **THEN** the pasteboard holds the text of these 5 entries

### Requirement: Save the log

The app SHALL offer "Save..." in the log window. It writes the entries as a text file to a place that the user picks.

#### Scenario: Save

- **WHEN** the user clicks "Save..." and confirms the save panel
- **THEN** the chosen folder holds a text file with all entries of the log window

### Requirement: Warn before a log with personal data leaves the app

The app SHALL warn the user when a log that is copied or saved contains entries with full detail. The warning offers the version with placeholders as the first choice.

#### Scenario: Save after full detail

- **GIVEN** the log window holds entries with full detail
- **WHEN** the user clicks "Save..."
- **THEN** the app warns that the log contains personal data
- **AND** the user can save the version with placeholders or the full version

### Requirement: Search the log

The app SHALL offer a search field in the log window that shows only the entries that contain the search text.

#### Scenario: Search for an error

- **WHEN** the user types "9340" into the search field
- **THEN** the log window shows only the entries that contain "9340"

### Requirement: The log has a size limit

The app SHALL keep the log of earlier sessions up to 10 MB and up to 30 days and remove the oldest entries beyond these limits.

#### Scenario: Old entries

- **GIVEN** the log file holds entries from 45 days ago
- **WHEN** the user starts the app
- **THEN** the entries that are older than 30 days are gone

### Requirement: Error messages show when the error happened

The app SHALL show the date and the time of the event in every message about a failed refresh, a failed payment, or another failed bank dialog.

#### Scenario: Error from the morning

- **GIVEN** a refresh failed today at 07:15
- **WHEN** the user opens the error details of the account at 18:00
- **THEN** the message says that the event occurred today at 07:15

### Requirement: Go from an error to the log

The app SHALL offer "View Log..." in a message about a failed bank dialog. The command opens the log window and shows the entries of that dialog.

#### Scenario: View the log of a failed refresh

- **WHEN** the user clicks "View Log..." in the error details of "Girokonto"
- **THEN** the log window opens and shows the entries of the failed refresh of "Girokonto"

### Requirement: Report an internal error

The app SHALL, when an unexpected internal error occurs, show a message with the technical error text that the user can copy, and it SHALL offer "Report an Issue...". The app completes or undoes the database change that was in progress.

#### Scenario: Unexpected error during an import

- **GIVEN** an internal error occurs while the app imports a file with 200 transactions
- **WHEN** the app shows the message
- **THEN** the user can copy the technical error text
- **AND** the account holds either all 200 transactions or none of them

### Requirement: Report an issue

The app SHALL offer "Report an Issue..." in the Help menu. The command opens the page for a new issue of the project in the browser and fills in the version of the app and the version of macOS. The app attaches no log and sends no other data.

#### Scenario: Open the issue page

- **WHEN** the user chooses "Report an Issue..." in version 0.3.1 on macOS 15.2
- **THEN** the browser opens the new issue page of the project
- **AND** the draft names version 0.3.1 and macOS 15.2
- **AND** the draft contains no log entry

### Requirement: Nothing is sent without the user

The app SHALL NOT send logs, crash reports, or usage data to the project or to anyone else on its own.

#### Scenario: Crash

- **GIVEN** the app quit unexpectedly
- **WHEN** the user starts it again
- **THEN** the app sends no report
- **AND** the log holds an entry about the unexpected end of the last session
