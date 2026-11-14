# Spec Delta

## Purpose

Accounts and account groups are the frame for everything else in the app. This capability defines what an account is, how the user changes its settings, how accounts are grouped, closed, and removed.

## ADDED Requirements

### Requirement: Account types

The app SHALL give every account one of the types "Giro account", "Savings account", "Fixed term deposit", "Loan account", "Credit card", "Portfolio", or "Other". The bank or the extension sets the type when the account is added. A later refresh does not change the type, except that a refresh that fetches the value of a securities account makes the account a "Portfolio".

#### Scenario: Type from the bank

- **WHEN** the bank reports a savings account during setup
- **THEN** the new account has the type "Savings account"

#### Scenario: Refresh reports another type

- **GIVEN** the user changed the type of an account to "Fixed term deposit"
- **WHEN** a refresh reports the account as a savings account
- **THEN** the account keeps the type "Fixed term deposit"

#### Scenario: Refresh fetches the value of a securities account

- **GIVEN** the user changed the type of "Depot" to "Savings account"
- **WHEN** a refresh fetches the value of "Depot" as a securities account
- **THEN** "Depot" has the type "Portfolio"

### Requirement: Derive a missing account type

The app SHALL derive the type of a new account from its number and its name when the source reports no type. An account number with 16 characters, or with masked digits, makes the account a "Credit card". An account that gives no hint gets the type "Other".

#### Scenario: Masked card number

- **WHEN** an extension reports an account with the number "4111 xxxx xxxx 1111" and no type
- **THEN** the new account has the type "Credit card"

#### Scenario: No hint

- **WHEN** an extension reports an account with the number "K-2231" and the name "Wallet" and no type
- **THEN** the new account has the type "Other"

### Requirement: Change the account type

The app SHALL let the user change the type of an account under "Account type" among "Giro account", "Savings account", "Fixed term deposit", "Loan account", "Credit card", and "Other". The type "Portfolio" cannot be chosen and cannot be changed, because it decides that the account shows securities.

#### Scenario: Correct a wrong type

- **GIVEN** the bank reported a fixed term deposit as "Other"
- **WHEN** the user selects "Fixed term deposit" under "Account type" and clicks "OK"
- **THEN** the account has the type "Fixed term deposit"

#### Scenario: Portfolio

- **WHEN** the user opens the settings of a portfolio
- **THEN** the settings show the type "Portfolio" without a menu

### Requirement: Account settings window

The app SHALL open the settings of the selected account with "Account Settings..." in the Account menu, with "Settings..." in the context menu, and with ⌘I. The window has the title "Settings for" followed by the account name, the tabs for the account and "Account owner", and the buttons "Cancel" and "OK".

#### Scenario: Confirm changes

- **WHEN** the user changes the name to "Household" and clicks "OK"
- **THEN** the sidebar shows "Household"

#### Scenario: Discard changes

- **WHEN** the user changes the name and the account type and clicks "Cancel"
- **THEN** the account keeps its old name and type

### Requirement: Account name

The app SHALL name a new account with the product name that the bank reports, or with the account type when the bank reports none, and it SHALL let the user change the name. Two accounts can have the same name. An empty name is not accepted.

#### Scenario: Name from the bank

- **WHEN** the bank reports the product name "Giro Direkt" for a new account
- **THEN** the account appears as "Giro Direkt"

#### Scenario: Empty name

- **WHEN** the user clears the name field and clicks "OK"
- **THEN** the app keeps the window open and asks for a name

### Requirement: Account color

The app SHALL draw an account in the sidebar and in the header as a small square in its color. The user can choose the color in the account settings. Without a chosen color, all accounts of one bank share a color, and an account without a bank takes a color for its type. A migration takes the color of the account's icon in the other program, not the picture.

#### Scenario: Two accounts of one bank

- **GIVEN** the accounts "Giro" and "Savings" with the same bank code and no chosen color
- **WHEN** the user looks at the sidebar
- **THEN** both squares have the same color

### Requirement: Bank details of an account

The app SHALL show in the account settings the IBAN and the BIC of the account, or the account number and the Bankleitzahl when it has no IBAN, and the "Bank name". The IBAN is shown in groups of four characters. The user can change the bank name and cannot change the other values there.

#### Scenario: Account with an IBAN

- **WHEN** the user opens the settings of the account with the IBAN DE02120300000000202051
- **THEN** the settings show "DE02 1203 0000 0000 2020 51" and the BIC "BYLADEM1001" as fixed text

#### Scenario: Card account without an IBAN

- **WHEN** the user opens the settings of a credit card that the bank reports with a card number only
- **THEN** the settings show the number under "Credit card number" in place of the IBAN

#### Scenario: Portfolio

- **WHEN** the user opens the settings of a portfolio
- **THEN** the settings show the number under "Portfolio number"

### Requirement: Account currency

The app SHALL store the currency that the source reports for an account and show every amount of that account in that currency. The sidebar shows the currency next to the balance.

#### Scenario: Dollar account

- **GIVEN** a foreign currency account in US dollars with a balance of 1.500,00
- **WHEN** the user looks at the sidebar
- **THEN** the row of the account shows the balance as an amount in US dollars
- **AND** the transactions of the account show amounts in US dollars

### Requirement: Account owner

The app SHALL show the name of the account owner on the tab "Account owner" under "Name of Account Owner". The name comes from the bank at setup, and the user can change it.

#### Scenario: Name from the bank

- **WHEN** the bank reports the owner "Erika Mustermann" at setup
- **THEN** "Name of Account Owner" shows "Erika Mustermann"

#### Scenario: Name corrected by hand

- **WHEN** the user changes the name to "Erika Mustermann-Schmidt" and clicks "OK"
- **THEN** the app stores "Erika Mustermann-Schmidt" as the owner of the account

### Requirement: Balance comes from the bank

The app SHALL show for each account the balance that the source reported last, together with the date of that balance. The app does not compute this balance from the transaction list, so it can differ from the list while transactions are pending.

#### Scenario: Balance with its date

- **GIVEN** the bank reported a balance of 2.340,15 € on 7 November 2026
- **WHEN** the user selects the account
- **THEN** the account view shows 2.340,15 € with the date 07.11.2026

#### Scenario: Deleting a transaction does not change the balance

- **GIVEN** an account with a reported balance of 2.340,15 €
- **WHEN** the user deletes a transaction of 40,00 € from the list
- **THEN** the account still shows 2.340,15 €

### Requirement: Several balances and bonus points

The app SHALL show every balance when a source reports several balances in different currencies for one account, and it SHALL show the number of bonus points under "Bonus points" when a source reports one.

#### Scenario: Wallet with two currencies

- **WHEN** a source reports the balances 120,00 € and 35,00 US dollars for one account
- **THEN** the account view shows both balances

#### Scenario: Card with a bonus program

- **WHEN** a source reports 12,400 bonus points for a credit card
- **THEN** the account view shows "Bonus points" with 12,400

### Requirement: Initial balance

The app SHALL keep an "Initial balance" for each account. At setup the app sets it to the balance that the bank reports, less the booked transactions of the first refresh in the account currency up to the day of that balance. Pending transactions do not count, because the bank balance does not hold them yet. The user can change the initial balance in the account settings.

#### Scenario: Determined at setup

- **GIVEN** the bank reports a balance of 1.000,00 € and the first refresh brings booked transactions with a sum of 250,00 € and one pending transaction of -30,00 €
- **WHEN** the first refresh ends
- **THEN** "Initial balance" shows 750,00 €

#### Scenario: Changed by hand

- **WHEN** the user enters 800,00 under "Initial balance" and clicks "OK"
- **THEN** the app stores 800,00 € as the initial balance of the account

### Requirement: Mark an account as closed

The app SHALL offer the option "The account has been closed" in the account settings. A closed account keeps its transactions, is left out of every refresh, and is left out of the dashboard and of the sum of its group. The sidebar still lists it, without its balance.

#### Scenario: Close an account

- **WHEN** the user turns on "The account has been closed" and clicks "OK"
- **THEN** the account stays in the sidebar with all its transactions and without its balance
- **AND** the sum of its group no longer contains its balance
- **AND** "Refresh All Accounts" does not contact the bank for this account

#### Scenario: Offline account

- **WHEN** the user turns on the option for an offline account
- **THEN** the offline account is closed in the same way

### Requirement: Clearing entry for a closed account

The app SHALL insert a transaction named "Clearing entry" when an account with a balance other than zero is marked as closed. The entry has the date of that day and the amount that brings the balance to zero. Its text says that the app inserted it because the account was closed. The user can edit it like a manual transaction.

#### Scenario: Balance left on the account

- **GIVEN** an account with a balance of 12,34 €
- **WHEN** the user marks it as closed
- **THEN** the list shows a new transaction "Clearing entry" of -12,34 €
- **AND** the account shows a balance of 0,00 €

#### Scenario: Balance already zero

- **GIVEN** an account with a balance of 0,00 €
- **WHEN** the user marks it as closed
- **THEN** the app inserts no transaction

### Requirement: Reopen a closed account

The app SHALL reopen an account when the user turns off "The account has been closed". The app then removes the clearing entry that it inserted, unless the user changed that entry, and includes the account in refreshes again.

#### Scenario: Unchanged clearing entry

- **GIVEN** a closed account with a clearing entry of -12,34 € that the user did not edit
- **WHEN** the user turns off the option and clicks "OK"
- **THEN** the clearing entry is gone and the balance is 12,34 € again

#### Scenario: Edited clearing entry

- **GIVEN** the user changed the purpose of the clearing entry
- **WHEN** the user reopens the account
- **THEN** the entry stays in the list

### Requirement: Create and rename account groups

The app SHALL create an account group with "Add Account Group". The new group appears in the sidebar with the name "New group" in edit mode. The user can rename a group in the sidebar and in its settings.

#### Scenario: New group

- **WHEN** the user chooses "Add Account Group" and types "Business"
- **THEN** the sidebar shows an empty group "Business"

#### Scenario: Empty group selected

- **WHEN** the user selects a group with no accounts
- **THEN** the content view says that the account group is empty

### Requirement: Move accounts into and out of groups

The app SHALL let the user drag an account or a group onto a group, out of a group, and to another position in the "Accounts" section. An account belongs to at most one group. A group can contain accounts and groups.

#### Scenario: Move into a group

- **WHEN** the user drags the account "Giro" onto the group "Private"
- **THEN** "Giro" is listed under "Private"

#### Scenario: Move out of a group

- **WHEN** the user drags "Giro" from "Private" to the top level of "Accounts"
- **THEN** "Giro" is listed outside every group

#### Scenario: Group into itself

- **WHEN** the user drags the group "Private" onto a group inside "Private"
- **THEN** the app does not accept the drop

### Requirement: Group view

The app SHALL show, when a group is selected, the transactions of all accounts in the group and in its subgroups in one list, and the sum of their balances. A group with accounts in several currencies shows one sum for each currency.

#### Scenario: Two euro accounts

- **GIVEN** the group "Private" with "Giro" at 1.000,00 € and "Savings" at 5.000,00 €
- **WHEN** the user selects "Private"
- **THEN** the list contains the transactions of both accounts
- **AND** the view shows a balance of 6.000,00 €

#### Scenario: Mixed currencies

- **GIVEN** a group with one account at 1.000,00 € and one account at 500,00 US dollars
- **WHEN** the user selects the group
- **THEN** the view shows 1.000,00 € and 500,00 US dollars as two sums

### Requirement: Account group settings

The app SHALL open the settings of the selected group with "Account Group Settings..." and ⌘I. The settings hold the name of the group and the option "Display balance in sidebar", which is on for a new group.

#### Scenario: Hide the sum

- **GIVEN** the group "Private" shows 6.000,00 € in the sidebar
- **WHEN** the user turns off "Display balance in sidebar" for "Private"
- **THEN** the sidebar row of "Private" shows only the name
- **AND** the rows of its accounts still show their balances

### Requirement: Collapsed groups keep their information

The app SHALL show on the row of a collapsed group the sum of the group, when the group displays its balance, and the markers of the accounts inside, which are the count of new transactions and the error indicator.

#### Scenario: Error inside a collapsed group

- **GIVEN** the group "Business" is collapsed and one of its accounts failed to refresh
- **WHEN** the user looks at the sidebar
- **THEN** the row of "Business" shows the error indicator

### Requirement: Remove an account

The app SHALL ask before it removes an account. The question names the account, says that all its transactions are removed as well and cannot be restored, and gives the hint that the account can be marked as closed instead. Statement files of the account stay in the data folder.

#### Scenario: Confirm removal

- **GIVEN** the account "Old Giro" with 800 transactions and 12 statement files
- **WHEN** the user chooses "Remove Account..." and confirms
- **THEN** "Old Giro" and its 800 transactions are gone from the app
- **AND** the 12 statement files are still in the "Statements" folder

#### Scenario: Cancel removal

- **WHEN** the user chooses "Remove Account..." and cancels
- **THEN** nothing changes

#### Scenario: Last account of an access

- **GIVEN** "Old Giro" is the only account of its bank access and the access has a saved PIN
- **WHEN** the user removes "Old Giro"
- **THEN** the app also deletes the saved PIN and the other login data of that access

### Requirement: Remove an account group

The app SHALL ask before it removes an account group and say that the accounts and transactions are kept. After the removal the accounts and subgroups of the group are in the group above it, or at the top level.

#### Scenario: Group with two accounts

- **GIVEN** the top level group "Private" with the accounts "Giro" and "Savings"
- **WHEN** the user chooses "Remove Account Group..." and confirms
- **THEN** "Private" is gone
- **AND** "Giro" and "Savings" are at the top level of "Accounts" with all their transactions
