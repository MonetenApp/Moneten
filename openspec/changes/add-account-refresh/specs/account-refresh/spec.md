# Spec Delta

## Purpose

A refresh brings new balances and transactions from banks and services into the app. This capability defines when a refresh runs, how the app reports the result for each account, and how it merges what it fetched into the stored history without duplicates and without loss.

## ADDED Requirements

### Requirement: Refresh all accounts

The app SHALL refresh every account that has a bank access, is not closed, and does not have the interval "never", when the user chooses "Refresh All Accounts" in the File menu, presses ⌘R, or clicks the refresh button under the sidebar.

#### Scenario: Three banks

- **GIVEN** accounts at three banks and one offline account
- **WHEN** the user presses ⌘R
- **THEN** the app fetches the balances and transactions of the accounts at all three banks
- **AND** it contacts no bank for the offline account

### Requirement: Refresh one account or one group

The app SHALL refresh only the selected account with "Refresh Account", and all accounts of the selected group with "Refresh Accounts". Both commands are in the Account menu and the context menu and share the shortcut ⇧⌘R. The view of a single account also shows a refresh button next to the time of its last refresh.

#### Scenario: Single account

- **GIVEN** "Giro" and "Savings" belong to the same login
- **WHEN** the user selects "Giro" and presses ⇧⌘R
- **THEN** only "Giro" is refreshed

#### Scenario: Group

- **WHEN** the user selects the group "Private" and chooses "Refresh Accounts"
- **THEN** every account in "Private" and in its subgroups is refreshed

### Requirement: Cancel a refresh

The app SHALL stop a running refresh when the user chooses "Cancel Refresh". The command is enabled only while a refresh runs. Accounts that were complete keep their new data, and the other accounts keep their last state.

#### Scenario: Cancel

- **GIVEN** a refresh of ten accounts is running and four are complete
- **WHEN** the user chooses "Cancel Refresh"
- **THEN** the four accounts show their new transactions
- **AND** the six other accounts show their earlier state and no error

#### Scenario: Nothing to cancel

- **WHEN** no refresh is running
- **THEN** "Cancel Refresh" is disabled

### Requirement: Automatic refresh

The app SHALL refresh accounts by itself while it runs and is unlocked when the setting "Automatically refresh accounts" is on. The setting is on in a new installation. With the setting off, the app refreshes only on command.

#### Scenario: Setting on

- **GIVEN** the setting is on and "Giro" has the interval "every two hours"
- **WHEN** two hours passed since the last refresh of "Giro"
- **THEN** the app refreshes "Giro" without a command

#### Scenario: Setting off

- **GIVEN** the setting is off
- **WHEN** the app runs for a day
- **THEN** no account is refreshed until the user gives a refresh command

### Requirement: Refresh interval for each account

The app SHALL offer the setting "Refresh" in the account settings with the values "every two hours", "four times a day", "once a day", "once a week", "only manually", and "never". The automatic refresh fetches an account when the time of its interval passed since the latest of its last successful refresh, its last failed refresh, and the moment the user canceled its refresh. A new account starts with "every two hours".

#### Scenario: Once a day

- **GIVEN** the credit card "Card" has the interval "once a day" and was refreshed at 08:00
- **WHEN** the automatic refresh runs at 10:00 and at 12:00 on the same day
- **THEN** "Card" is not refreshed at these times
- **AND** it is refreshed by the first automatic run after 08:00 on the next day

#### Scenario: Failed refresh

- **GIVEN** "Giro" has the interval "every two hours", was refreshed at 08:00, and its refresh at 10:00 failed because the bank did not answer
- **WHEN** the automatic refresh runs at 11:00 and at 12:00
- **THEN** "Giro" is not fetched at these times
- **AND** it is fetched by the first automatic run after 12:00

#### Scenario: Canceled refresh

- **GIVEN** "Giro" has the interval "every two hours" and the user chooses "Cancel Refresh" during its refresh at 10:00
- **WHEN** the automatic refresh runs at 10:01
- **THEN** "Giro" is not fetched until the first automatic run after 12:00

### Requirement: Accounts that are refreshed only by hand

The app SHALL leave an account with the interval "only manually" out of the automatic refresh and include it in every manual refresh.

#### Scenario: Only manually

- **GIVEN** "Depot" has the interval "only manually"
- **WHEN** the automatic refresh runs
- **THEN** "Depot" is not refreshed
- **AND** "Refresh All Accounts" refreshes "Depot"

### Requirement: Accounts that are never refreshed with the others

The app SHALL leave an account with the interval "never" out of the automatic refresh and out of "Refresh All Accounts" and "Refresh Accounts". Only "Refresh Account" on that account refreshes it.

#### Scenario: Never

- **GIVEN** "Old card" has the interval "never"
- **WHEN** the user presses ⌘R
- **THEN** "Old card" is not refreshed

#### Scenario: Direct command

- **WHEN** the user selects "Old card" and chooses "Refresh Account"
- **THEN** "Old card" is refreshed

### Requirement: Refresh after launch and after wake

The app SHALL run the automatic refresh for all accounts that are due when the app was started and unlocked, and when the Mac wakes from sleep while the app is unlocked.

#### Scenario: Start in the morning

- **GIVEN** "Giro" has the interval "every two hours" and was last refreshed yesterday
- **WHEN** the user starts and unlocks the app
- **THEN** the app refreshes "Giro" without a command

### Requirement: No automatic refresh while the app is locked

The app SHALL start no refresh while it is locked. Accounts that became due in that time are refreshed after the user unlocks the app.

#### Scenario: Locked over lunch

- **GIVEN** the app locked at 12:00 and "Giro" became due at 12:30
- **WHEN** the user unlocks the app at 13:00
- **THEN** no bank was contacted between 12:00 and 13:00
- **AND** the app refreshes "Giro" after the unlock

### Requirement: No automatic refresh during Power Nap

The app SHALL start no refresh while the Mac is in Power Nap or in another state in which the display sleeps and no user is present.

#### Scenario: Lid closed at night

- **GIVEN** a MacBook with the lid closed that wakes for Power Nap
- **WHEN** an account becomes due during that time
- **THEN** the app contacts no bank until the user wakes the Mac

### Requirement: An automatic refresh never asks the user

The app SHALL open no dialog for an automatic refresh. When a bank asks for a TAN or another confirmation, the app ends that access, marks its accounts with a text that tells the user to run "Refresh Account" to give the authorization, and continues with the other accesses.

#### Scenario: Bank asks for a TAN after 90 days

- **GIVEN** the bank of "Giro" asks for a TAN at login
- **WHEN** the automatic refresh runs
- **THEN** no TAN dialog appears
- **AND** the sidebar row of "Giro" shows that an authorization is needed
- **AND** the TAN dialog appears when the user chooses "Refresh Account" on "Giro"

### Requirement: One session for the accounts of one login

The app SHALL refresh all due accounts of the same access in one session with one login, so that the bank asks for at most one confirmation for the login.

#### Scenario: Giro and savings at one bank

- **GIVEN** "Giro" and "Savings" use the same access
- **WHEN** the user presses ⌘R
- **THEN** the app logs in once at that bank and fetches both accounts

### Requirement: A failure affects only its own access

The app SHALL continue with the other accesses when one access fails. Inside a failed session the accounts that were not yet fetched are marked as canceled because of the earlier error.

#### Scenario: One bank is down

- **GIVEN** accounts at "Musterbank" and "Beispielbank", and the server of "Musterbank" does not answer
- **WHEN** the user presses ⌘R
- **THEN** the accounts of "Beispielbank" are refreshed
- **AND** the accounts of "Musterbank" show the connection error

#### Scenario: Error in the middle of a session

- **GIVEN** "Giro", "Savings", and "Card" use one access and the bank answers the request for "Savings" with an error
- **WHEN** the session ends
- **THEN** "Giro" has its new data, "Savings" shows the error of the bank, and "Card" shows that it was canceled because of the previous error

### Requirement: Show progress

The app SHALL show a progress indicator on the sidebar row of each account while that account is being refreshed, and a text for the current step in the status line, for example that it is getting the balance and transactions of an account.

#### Scenario: Refresh in progress

- **WHEN** the app fetches the transactions of "Giro"
- **THEN** the row of "Giro" shows a progress indicator
- **AND** the indicator disappears when "Giro" is complete

### Requirement: Show the time of the last refresh

The app SHALL show in the view of an account the date and time of its last successful refresh, with the words "Today" and "Yesterday" for these days.

#### Scenario: Refreshed this morning

- **GIVEN** "Giro" was last refreshed today at 09:41
- **WHEN** the user selects "Giro"
- **THEN** the view shows "Last updated: Today, 09:41"

### Requirement: Show an error on the account

The app SHALL show a short error text on the sidebar row of an account whose last refresh failed, in place of the balance, and an error indicator that opens a popover. The popover says that the last refresh was aborted, quotes the message, and shows the date and time of the event and a notice of the bank when there is one. The view of an account that has never refreshed shows the error text in place of "Not refreshed yet".

#### Scenario: First refresh failed

- **GIVEN** the first refresh of "Fondsdepot" failed with "Moneten can't read this securities account at this bank yet."
- **WHEN** the user selects "Fondsdepot"
- **THEN** the view shows "Moneten can't read this securities account at this bank yet." and the error indicator, and not "Not refreshed yet"

#### Scenario: Open the popover

- **GIVEN** the refresh of "Giro" failed on 09.11.2026 at 09:41 with the bank message "Zugang vorübergehend gesperrt"
- **WHEN** the user clicks the error indicator of "Giro"
- **THEN** the popover quotes "Zugang vorübergehend gesperrt" and shows 09.11.2026, 09:41

### Requirement: An error ends with the next success

The app SHALL remove the error of an account when a later refresh of that account succeeds, and show the balance again. The earlier transactions and the last known balance stay visible while the error is shown in the account view.

#### Scenario: Bank is back

- **GIVEN** "Giro" shows a connection error
- **WHEN** the next refresh of "Giro" succeeds
- **THEN** the row of "Giro" shows the balance and no error indicator

### Requirement: Keep the history for good

The app SHALL keep every fetched transaction until the user deletes it or removes the account. A refresh never removes a booked transaction because the bank no longer delivers it.

#### Scenario: Bank keeps 90 days

- **GIVEN** the app has transactions of "Giro" from the last three years and the bank delivers only the last 90 days
- **WHEN** a refresh ends
- **THEN** all transactions of the three years are still in the list

### Requirement: Do not store a transaction twice

The app SHALL recognize a fetched transaction that it already stored and not add it again. It uses the ID of the source when the source gives one. Otherwise it compares account, booking date, amount, counterparty account, end-to-end reference, and purpose, and ignores case and spacing in the purpose.

#### Scenario: Overlapping fetch

- **GIVEN** "Giro" has 40 transactions of the last 14 days
- **WHEN** a refresh delivers these 40 transactions again and 3 new ones
- **THEN** "Giro" has 3 more transactions than before

#### Scenario: Purpose delivered with other spacing

- **GIVEN** a stored transaction with the purpose "Rechnung 1001  Kundennr 4711"
- **WHEN** the bank delivers the same transaction with the purpose "RECHNUNG 1001 KUNDENNR 4711"
- **THEN** the app adds no transaction

### Requirement: Update a transaction that the source changed

The app SHALL update the stored transaction when a source that gives IDs delivers a known ID with changed details, and keep the category, the comment, and the checkmark of the user.

#### Scenario: Amount corrected by the broker

- **GIVEN** an extension delivered the transaction with the ID "tx-1001" and the amount -100,00 €, and the user gave it the comment "ETF savings plan"
- **WHEN** the extension delivers "tx-1001" with the amount -100,50 €
- **THEN** the list shows one transaction with -100,50 € and the comment "ETF savings plan"

### Requirement: Keep real identical transactions

The app SHALL keep both transactions when one fetch delivers two transactions of one account that are equal in every compared field, because both are real.

#### Scenario: Two coffees on one day

- **GIVEN** the bank delivers two card payments of -3,20 € to "Café Beispiel" with the same date and purpose in one answer
- **WHEN** the refresh ends
- **THEN** the list shows two transactions of -3,20 €
- **AND** the next refresh that delivers both again adds none

### Requirement: Replace a pending transaction by its booked version

The app SHALL replace a pending transaction by the booked transaction when exactly one pending transaction of the account matches it in amount and counterparty within a few days. The booked transaction takes over the comment, the checkmark, and a category that the user assigned by hand.

#### Scenario: Card payment gets booked

- **GIVEN** a pending transaction of -23,80 € to "Buchhandlung Beispiel" with the comment "Gift"
- **WHEN** the bank delivers a booked transaction of -23,80 € to "Buchhandlung Beispiel" two days later
- **THEN** the list shows one booked transaction with the comment "Gift"
- **AND** the pending row is gone

### Requirement: Do not guess between several pending transactions

The app SHALL keep all rows and mark them for review when more than one pending transaction matches a booked transaction, and it SHALL not move a comment or a category in that case.

#### Scenario: Two pending coffees, one booked

- **GIVEN** two pending transactions of -3,20 € to "Café Beispiel", one with the comment "with Max"
- **WHEN** the bank delivers one booked transaction of -3,20 € to "Café Beispiel"
- **THEN** the list shows the booked transaction and both pending transactions
- **AND** the three rows are marked for review

### Requirement: Remove a pending transaction that the bank dropped

The app SHALL remove a pending transaction when a successful refresh of its account no longer delivers it and no booked transaction replaced it.

#### Scenario: Hotel deposit released

- **GIVEN** a pending transaction of -200,00 € for a hotel deposit
- **WHEN** the next successful refresh delivers neither this pending transaction nor a booked one for it
- **THEN** the pending transaction is gone from the list

#### Scenario: Refresh failed

- **GIVEN** the same pending transaction
- **WHEN** the refresh of the account fails
- **THEN** the pending transaction stays in the list

### Requirement: Deleted transactions stay deleted

The app SHALL not add a transaction again that the user deleted, when a later refresh delivers it again.

#### Scenario: Deleted duplicate

- **GIVEN** the user deleted a transaction of -12,00 € from "Giro"
- **WHEN** the next refresh delivers that transaction again
- **THEN** the transaction does not return to the list

#### Scenario: Enforced refresh

- **WHEN** the user runs "Refresh Account (enforced)" after deleting the transaction
- **THEN** the transaction does not return to the list

### Requirement: Mark new transactions

The app SHALL mark each transaction that a refresh added as new and show the number of new transactions on the sidebar row of the account. A transaction counts as seen, and leaves that number, when the user opens the view of its account or chooses "Mark All Transactions as Checked".

#### Scenario: Three new transactions

- **WHEN** a refresh adds three transactions to "Giro" while another view is selected
- **THEN** the row of "Giro" shows the count 3
- **AND** the count disappears after the user selects "Giro"

### Requirement: Update the balance at every refresh

The app SHALL store the balance and its date at every successful refresh of an account, also when the refresh brought no new transaction.

#### Scenario: No new transaction

- **WHEN** a refresh of "Savings" delivers the balance 5.012,40 € and no new transaction
- **THEN** "Savings" shows 5.012,40 € with the date of that balance

### Requirement: Refresh after a payment

The app SHALL refresh an account after the bank accepted a payment from that account, so that the payment appears in the list.

#### Scenario: Transfer sent

- **WHEN** the bank accepts a transfer of 120,00 € from "Giro"
- **THEN** the app refreshes "Giro" without a command

### Requirement: Behavior without an Internet connection

The app SHALL say that there is no Internet connection when the user starts a refresh while the Mac is offline. An automatic refresh that finds no connection contacts nothing, shows no error, and runs again when the connection is back.

#### Scenario: Manual refresh offline

- **WHEN** the user presses ⌘R without an Internet connection
- **THEN** the app says that there is no Internet connection
- **AND** the accounts keep their last state without an error

#### Scenario: Automatic refresh offline

- **GIVEN** the Mac is offline when an account becomes due
- **WHEN** the connection returns
- **THEN** the app refreshes the account
