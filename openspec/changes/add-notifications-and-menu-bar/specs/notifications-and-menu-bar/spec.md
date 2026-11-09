# Spec Delta

## Purpose

The app tells the user about new transactions and new statements while they do something else. This capability defines the macOS notification, the sound, the Dock badge, and the optional menu bar icon with its popover.

## ADDED Requirements

### Requirement: One notification for a refresh with new transactions

The app SHALL show exactly one macOS notification when a refresh run has stored at least one new transaction and the setting "Show banner notification on new transactions" is on. The notification states the number of new transactions, for example "3 new transactions" or "1 new transaction", and lists the accounts that received them. The setting is on by default.

#### Scenario: New transactions in two accounts

- **GIVEN** the setting is on
- **WHEN** one refresh run stores 2 new transactions in "Girokonto" and 1 in "Kreditkarte"
- **THEN** the app shows one notification with "3 new transactions" that names "Girokonto" and "Kreditkarte"

#### Scenario: Nothing new

- **WHEN** a refresh run stores no new transaction
- **THEN** the app shows no notification

#### Scenario: Setting off

- **GIVEN** the setting "Show banner notification on new transactions" is off
- **WHEN** a refresh run stores 3 new transactions
- **THEN** the app shows no notification

### Requirement: Notify only about stored transactions

The app SHALL count in a notification only transactions that are stored in the database at the time the notification appears. A transaction that the app dropped as a duplicate does not count.

#### Scenario: Duplicate delivered again

- **GIVEN** the bank delivers 5 transactions of which 4 are already stored
- **WHEN** the refresh run ends
- **THEN** the notification reads "1 new transaction"

### Requirement: Notifications reveal no transaction details

The app SHALL NOT put amounts, counterparty names, purposes, or balances into a notification. While the app is locked, the notification also contains no account names.

#### Scenario: Unlocked

- **GIVEN** the app is unlocked
- **WHEN** a refresh stores a salary payment of 3.200,00 € from "Musterfirma GmbH" in "Girokonto"
- **THEN** the notification contains "1 new transaction" and "Girokonto"
- **AND** it contains neither "3.200,00" nor "Musterfirma GmbH"

#### Scenario: Locked during the refresh

- **GIVEN** a refresh is running and the app locks before the refresh ends
- **WHEN** the refresh stores 2 new transactions
- **THEN** the notification contains "2 new transactions" and no account name

### Requirement: Open the account from a notification

The app SHALL bring the main window to the front when the user clicks a notification about new transactions. It selects the account when one account received them, and the dashboard or, without a dashboard, the first of the accounts when several did. A locked app asks for the unlock first.

#### Scenario: One account

- **GIVEN** a notification about 2 new transactions in "Girokonto"
- **WHEN** the user clicks the notification
- **THEN** the main window comes to the front with "Girokonto" selected

#### Scenario: Locked app

- **GIVEN** the app is locked
- **WHEN** the user clicks the notification
- **THEN** the app shows the lock screen
- **AND** after the unlock it selects the account

### Requirement: Remove notifications that are out of date

The app SHALL remove its notification about new transactions from the Notification Center when the user has seen those transactions in the app.

#### Scenario: User opens the account first

- **GIVEN** a notification about 2 new transactions in "Girokonto" that the user did not click
- **WHEN** the user opens "Girokonto" in the app
- **THEN** the notification is no longer in the Notification Center

### Requirement: Sound on new transactions

The app SHALL play one sound for a refresh run that stored new transactions when the setting "Play sound on new transactions" is on. The setting is off by default and works with the banner on or off. The app plays one of three sounds, for a positive sum of the new transactions, for a negative sum, and for a sum of zero.

#### Scenario: Deposit

- **GIVEN** the setting is on
- **WHEN** a refresh run stores new transactions with the sum 3.200,00 €
- **THEN** the app plays the sound for a positive sum once

#### Scenario: Withdrawals in three accounts

- **GIVEN** the setting is on
- **WHEN** one refresh run stores new transactions in three accounts with the sum -410,00 €
- **THEN** the app plays the sound for a negative sum once, not three times

#### Scenario: Setting off

- **GIVEN** the setting is off
- **WHEN** a refresh run stores new transactions
- **THEN** the app plays no sound

### Requirement: Respect Focus

The app SHALL send its notifications as ordinary notifications, so that a Focus of macOS that silences the app holds back the banner. The app plays no sound for new transactions while such a Focus is active.

#### Scenario: Do Not Disturb

- **GIVEN** "Do Not Disturb" is active and does not allow the app
- **WHEN** a refresh run stores 3 new transactions
- **THEN** no banner appears and no sound plays
- **AND** the notification is in the Notification Center when the Focus ends

### Requirement: Dock badge with the number of new transactions

The app SHALL show the number of transactions that the user has not yet seen as a badge on its Dock icon. The badge disappears when the number is zero. The badge follows the macOS notification setting for badges of the app.

#### Scenario: Count goes up and down

- **GIVEN** no new transactions and no badge
- **WHEN** a refresh stores 4 new transactions
- **THEN** the Dock icon shows the badge 4
- **AND** when the user has seen all 4, the badge disappears

#### Scenario: Badges turned off in macOS

- **GIVEN** the user turned off badges for the app in the macOS notification settings
- **WHEN** a refresh stores 4 new transactions
- **THEN** the Dock icon shows no badge

### Requirement: Ask for permission and explain a refusal

The app SHALL ask macOS for the permission to send notifications the first time it needs it. When the permission is denied, the "General" tab says next to the banner setting that notifications are turned off in macOS and names the place in the System Settings where the user allows them.

#### Scenario: Permission denied

- **GIVEN** the user denied notifications for the app in macOS
- **WHEN** the user opens the "General" tab of the settings
- **THEN** a note next to "Show banner notification on new transactions" says that macOS blocks notifications and where to allow them

#### Scenario: Permission granted later

- **GIVEN** the note is shown
- **WHEN** the user allows notifications in the System Settings and returns to the app
- **THEN** the note disappears

### Requirement: Notification about new statements

The app SHALL show one notification when a refresh run has downloaded new PDF statements and the banner setting is on. The notification states the number, for example that 2 new PDF statements have been downloaded. A click opens the "Statements" view.

#### Scenario: Two statements

- **WHEN** a refresh run downloads 2 new statements
- **THEN** the app shows one notification that says 2 new PDF statements have been downloaded

#### Scenario: Click

- **WHEN** the user clicks that notification
- **THEN** the main window comes to the front with "Statements" selected

### Requirement: Menu bar icon

The app SHALL show an icon in the menu bar while it runs when the setting "Show MonetenMoneten icon in menu bar" is on. The setting is off by default. Turning it on or off takes effect at once.

#### Scenario: Turn on

- **WHEN** the user turns on "Show MonetenMoneten icon in menu bar"
- **THEN** the icon appears in the menu bar without a restart

#### Scenario: Turn off

- **WHEN** the user turns the setting off
- **THEN** the icon disappears from the menu bar

### Requirement: Menu bar popover

The app SHALL open a popover when the user clicks the menu bar icon. The popover lists the open accounts in the order of the sidebar with name and balance, marks each account that has new transactions with their number, and marks each account whose last refresh failed or waits for the user.

#### Scenario: Open the popover

- **GIVEN** "Girokonto" with 2.450,10 € and 2 new transactions, and "Tagesgeld" with 10.000,00 €
- **WHEN** the user clicks the menu bar icon
- **THEN** the popover lists "Girokonto" with 2.450,10 € and the count 2, and "Tagesgeld" with 10.000,00 €

#### Scenario: Account needs attention

- **GIVEN** the automatic refresh skipped "Kreditkarte" because it needs a TAN
- **WHEN** the user opens the popover
- **THEN** the row "Kreditkarte" carries the marker that the refresh waits for the user

### Requirement: Actions in the popover

The app SHALL offer in the popover a command that refreshes all accounts and a command that opens the main window. A click on an account row opens the main window with that account selected.

#### Scenario: Refresh from the menu bar

- **GIVEN** the main window is closed
- **WHEN** the user opens the popover and chooses the refresh command
- **THEN** the app refreshes all accounts and the popover shows the progress and then the new balances

#### Scenario: Open an account

- **WHEN** the user clicks the row "Girokonto" in the popover
- **THEN** the main window opens with "Girokonto" selected

### Requirement: Menu bar icon shows the state

The app SHALL show on the menu bar icon that new transactions exist, that a refresh is running, and that an account needs attention.

#### Scenario: New transactions

- **GIVEN** no new transactions
- **WHEN** a refresh stores 1 new transaction
- **THEN** the menu bar icon shows the marker for new transactions until the user has seen the transaction

### Requirement: The popover respects the lock

The app SHALL show no account names, balances, or counts in the popover while the app is locked. The popover then says that the app is locked and offers the unlock.

#### Scenario: Locked

- **GIVEN** the app is locked
- **WHEN** the user clicks the menu bar icon
- **THEN** the popover shows that the app is locked and a way to unlock
- **AND** it shows no account

### Requirement: Keep working with the main window closed

The app SHALL keep running when the user closes the main window. Automatic refresh, notifications, the Dock badge, and the menu bar icon keep working as long as the app is not locked.

#### Scenario: Window closed, app unlocked

- **GIVEN** the main window is closed, the app is unlocked, and the automatic refresh is on
- **WHEN** the next automatic refresh stores 1 new transaction
- **THEN** the app shows the notification "1 new transaction"

#### Scenario: Window closed with lock on close

- **GIVEN** the setting "Lock when main window is closed" is on
- **WHEN** the user closes the main window
- **THEN** the app locks and no automatic refresh runs, so no notification about new transactions appears
