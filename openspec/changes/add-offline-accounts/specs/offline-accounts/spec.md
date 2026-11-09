# Spec Delta

## Purpose

An offline account holds money that the app cannot fetch from a bank, for example cash. This capability defines how the user creates such an account, how manual transactions are added and changed, and how the balance follows from them.

## ADDED Requirements

### Requirement: Create an offline account

The app SHALL create an account without bank access when the user chooses "Offline account / Cash" in the add account assistant. The user gives the account a name, an account type, and a currency. The app asks for no login data.

#### Scenario: Cash account

- **WHEN** the user chooses "Offline account / Cash", enters the name "Wallet", and finishes the assistant
- **THEN** the sidebar shows the account "Wallet" with a balance of 0,00 €

#### Scenario: Other currency

- **WHEN** the user creates an offline account with the currency USD
- **THEN** all amounts of that account are in USD

### Requirement: An offline account has no bank functions

The app SHALL leave an offline account out of every refresh and SHALL disable the commands that need a bank for it. These are the refresh command, "Edit Login Data...", "Look for New Accounts...", and the statement download.

#### Scenario: Refresh all accounts

- **GIVEN** one account with bank access and the offline account "Wallet"
- **WHEN** the user chooses "Refresh All Accounts"
- **THEN** the app contacts the bank only for the account with bank access
- **AND** "Wallet" shows no error

#### Scenario: Statements

- **WHEN** the user opens the statement settings
- **THEN** the offline account cannot be turned on for the statement download

### Requirement: Add a transaction by hand

The app SHALL open a window for a new transaction with "Add Transaction..." or the shortcut ⌘+ in the view of an offline account. The window has a date, a name, an amount with the choice between "Debit" and "Credit", a purpose, and a category. The date is today unless the user changes it.

#### Scenario: Cash payment

- **GIVEN** the offline account "Wallet"
- **WHEN** the user presses ⌘+, enters "Bäckerei Gutbrot", 4,80 as a debit, and the category "Groceries", and confirms
- **THEN** the list of "Wallet" shows a transaction of -4,80 € with today's date in "Groceries"

#### Scenario: Earlier date

- **WHEN** the user sets the date to 28.10.2026 and confirms
- **THEN** the transaction stands at 28.10.2026 in the list

#### Scenario: No category chosen

- **WHEN** the user confirms a new transaction without a category
- **THEN** the app stores the transaction without a manual category, so that the categorization rules can sort it

### Requirement: Manual transactions are validated

The app SHALL refuse a manual transaction with an amount of zero, with text in the amount field that is not a number, or with no date. The window stays open and names the field to correct.

#### Scenario: Amount of zero

- **WHEN** the user enters the amount 0,00 and confirms
- **THEN** the app says that the amount should not be zero and stores nothing

### Requirement: Suggestions while typing

The app SHALL suggest completions from earlier transactions while the user types the name of a manual transaction. A chosen suggestion fills the name, and it fills the purpose and the category while those fields are still empty.

#### Scenario: Known counterparty

- **GIVEN** an earlier transaction with the name "Bäckerei Gutbrot", the purpose "Brot", and the category "Groceries"
- **WHEN** the user types "Bäck" in the name field and chooses the suggestion "Bäckerei Gutbrot"
- **THEN** the window shows the name "Bäckerei Gutbrot", the purpose "Brot", and the category "Groceries"

### Requirement: A selected transaction is the template

The app SHALL fill the window for a new transaction with the name, the amount, the purpose, and the category of the transaction that is selected when the user calls "Add Transaction...". The date is today.

#### Scenario: Repeat a payment

- **GIVEN** a selected transaction of -12,00 € to "Kiosk am Markt" with the category "Leisure"
- **WHEN** the user presses ⌘+
- **THEN** the window shows "Kiosk am Markt", 12,00 as a debit, "Leisure", and today's date

### Requirement: Edit and delete manual transactions

The app SHALL let the user change every field of a manual transaction with "Edit Transaction..." and remove it with "Delete Transaction...", with the same confirmation as for other transactions.

#### Scenario: Correct an amount

- **GIVEN** a manual transaction of -4,80 €
- **WHEN** the user changes the amount to 5,80 as a debit
- **THEN** the row shows -5,80 € and the balance of the account drops by 1,00 €

### Requirement: The balance follows the transactions

The app SHALL compute the balance of an offline account as the sum of all its transactions, and it SHALL update the balance in the sidebar and in the view as soon as a transaction is added, changed, deleted, or imported.

#### Scenario: Three transactions

- **GIVEN** an offline account with the transactions 100,00 €, -4,80 €, and -12,00 €
- **WHEN** the user looks at the sidebar
- **THEN** the balance is 83,20 €

#### Scenario: Delete a transaction

- **WHEN** the user deletes the transaction of -12,00 €
- **THEN** the balance is 95,20 €

### Requirement: Hint for the first transaction

The app SHALL show a hint in an offline account without transactions. The hint asks the user to add at least the initial deposit with "Add Transaction", or the initial payout for a loan account.

#### Scenario: New cash account

- **WHEN** the user opens a new offline account of the type "Giro account"
- **THEN** the view asks the user to add at least the initial deposit

#### Scenario: New loan account

- **WHEN** the user opens a new offline account of the type "Loan account"
- **THEN** the view asks the user to add at least the initial payout

### Requirement: Create an offsetting entry

The app SHALL offer "Create Offsetting Entry" in the context menu of a transaction, with one entry for each offline account other than the account of the transaction. A choice adds a transaction to that offline account with the same date, purpose, and comment, the opposite sign, and the name of the source account as the counterparty.

#### Scenario: Cash withdrawal

- **GIVEN** a transaction of -200,00 € "Geldautomat" in the account "Giro" and the offline account "Wallet"
- **WHEN** the user chooses "Create Offsetting Entry" and then "Wallet"
- **THEN** "Wallet" gets a transaction of 200,00 € with the same date and the counterparty "Giro"
- **AND** the transaction in "Giro" is unchanged

#### Scenario: Several transactions

- **GIVEN** 3 selected transactions
- **WHEN** the user chooses "Create Offsetting Entry" and then "Wallet"
- **THEN** "Wallet" gets 3 new transactions

#### Scenario: No offline account

- **GIVEN** no offline account exists
- **WHEN** the user opens "Create Offsetting Entry"
- **THEN** the submenu shows only the disabled line "No offline accounts available"

### Requirement: Manual transactions behave like fetched ones

The app SHALL treat a manual transaction like a fetched one in every other function. It can carry a category, a checkmark, and a comment. It appears in search results, category views, charts, reports, printouts, and exports.

#### Scenario: Search

- **GIVEN** a manual transaction with the name "Flohmarkt" in the offline account "Wallet"
- **WHEN** the user selects the group that contains "Wallet" and searches for "Flohmarkt"
- **THEN** the list shows the manual transaction

### Requirement: An offline account can be closed

The app SHALL let the user mark an offline account as closed in the account settings, with the same effect as for an account with bank access.

#### Scenario: Close a cash account

- **GIVEN** the offline account "Old wallet" with a balance of 15,00 €
- **WHEN** the user turns on "The account has been closed" in its settings
- **THEN** the account is treated as closed and its transactions stay in the database

### Requirement: Manual transactions in an account with bank access

The app SHALL also offer "Add Transaction..." in the view of a single account with bank access. A transaction that the user added there stays through every refresh, counts in the computed daily balance and in the charts, and leaves the balance that the bank reports unchanged.

#### Scenario: Bank delivers no transactions

- **GIVEN** a fixed term deposit for which the bank delivers a balance and no transactions
- **WHEN** the user adds a manual transaction of 10.000,00 € with the date of the deposit
- **THEN** the account has a bar chart that starts at that date
- **AND** the next refresh keeps the manual transaction
