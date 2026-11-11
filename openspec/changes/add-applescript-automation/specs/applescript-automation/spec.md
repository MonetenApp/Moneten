# Spec Delta

## Purpose

Other programs and users' scripts read data from the app and hand payment data to it through AppleScript. This capability defines the ten scripting commands, their parameters, results, and errors. The command and parameter names equal those of MoneyMoney, so that an existing script works after the application name in it is changed.

## ADDED Requirements

### Requirement: Scripting dictionary

The app SHALL publish a scripting dictionary with the commands `export accounts`, `export categories`, `export transactions`, `export portfolio`, `create bank transfer`, `create batch transfer`, `create direct debit`, `create batch direct debit`, `add transaction`, and `set transaction`.

#### Scenario: Dictionary in Script Editor

- **WHEN** the user opens the dictionary of the app in Script Editor
- **THEN** the dictionary lists the ten commands with a description of each parameter

#### Scenario: Existing script

- **GIVEN** a script that was written for the reference product and whose only command is `export accounts`
- **WHEN** the user sets the application name in its `tell` line to "Moneten" and runs it
- **THEN** the script returns the list of accounts without any other change

### Requirement: Export accounts

The app SHALL return an XML property list of all accounts and account groups for `export accounts`, in sidebar order. Each entry has the keys `uuid`, `name`, `group`, `indentation`, `accountNumber`, `bankCode`, `owner`, `currency`, `type`, `portfolio`, `balance` with one amount for each currency, `refreshTimestamp`, `attributes`, and `icon`. `accountNumber` holds the IBAN when the account has one, and `bankCode` holds the BIC. A group has the sum of its accounts in `balance`.

#### Scenario: One group with one account

- **GIVEN** the group "Private" with the account "Giro" that has a balance of 1.234,56 €
- **WHEN** a script runs `export accounts`
- **THEN** the result has two entries, "Private" with `group` true and `indentation` 0, and "Giro" with `group` false, `indentation` 1, and the balance 1234.56 in EUR

### Requirement: Export categories

The app SHALL return an XML property list of all categories and category groups for `export categories`, in sidebar order. Each entry has the keys `uuid`, `name`, `group`, `indentation`, `default`, `currency`, and `rules`.

#### Scenario: Look up a category UUID

- **GIVEN** the category "Food" inside the group "Household"
- **WHEN** a script runs `export categories`
- **THEN** the result has an entry with `name` "Food", `indentation` 1, and a UUID that `set transaction` accepts

#### Scenario: Default category

- **WHEN** a script reads the entry of "Uncategorized"
- **THEN** its key `default` is true

### Requirement: Export transactions to a file

The app SHALL write the requested transactions to a temporary file for `export transactions` and return the path of the file. The parameter `as` names the format with one of `csv`, `ofx`, `sta`, `xls`, `numbers`, or `camt.053`. The parameter `from date` is required and has the form YYYY-MM-DD. The parameter `to date` is optional.

#### Scenario: One year as CSV

- **WHEN** a script runs `export transactions from account "DE02120300000000202051" from date "2026-01-01" to date "2026-12-31" as "csv"`
- **THEN** the result is the path of a CSV file with the transactions of that account from 2026

#### Scenario: Unknown format

- **WHEN** a script runs `export transactions from date "2026-01-01" as "pdf"`
- **THEN** the command fails with an error that lists the available formats

#### Scenario: Missing start date

- **WHEN** a script runs `export transactions as "csv"`
- **THEN** the command fails because `from date` is required

### Requirement: Temporary export files

The app SHALL keep the file of an export command readable until the app quits, and delete it at the next start.

#### Scenario: Open the file later

- **GIVEN** a script received the path of an export file ten minutes ago
- **WHEN** the script opens the file while the app still runs
- **THEN** the file is there

#### Scenario: After a restart

- **WHEN** the app quits and starts again
- **THEN** the file no longer exists

### Requirement: Export transactions as a property list

The app SHALL return an XML property list as the result of `export transactions` when the format is `plist`, and create no file. The list has the keys `creator` and `transactions`.

#### Scenario: Read with another language

- **WHEN** a Python program runs `osascript` with `tell application "Moneten" to export transactions from date "2026-10-10" as "plist"` and parses the output as a property list
- **THEN** the program can read `transactions` as an array

### Requirement: Keys of an exported transaction

The app SHALL give each transaction in the property list the keys `id`, `accountUuid`, `booked`, `bookingDate`, `valueDate`, `name`, `accountNumber`, `bankCode`, `amount`, `currency`, `purpose`, `bookingText`, `endToEndReference`, `mandateReference`, `creditorId`, `returnReason`, `checkmark`, `category`, `categoryId`, `categoryUuid`, and `comment`. A key without a value is left out.

#### Scenario: Booked transaction

- **GIVEN** a booked withdrawal of 89,00 € to "Stadtwerke Musterstadt" on 3 November 2026 in the category "Housing"
- **WHEN** a script exports it as `plist`
- **THEN** the entry has `booked` true, `amount` -89.0, `currency` "EUR", `name` "Stadtwerke Musterstadt", a date value in `bookingDate`, and the UUID of "Housing" in `categoryUuid`

#### Scenario: No comment

- **WHEN** a transaction has no comment
- **THEN** its entry has no key `comment`

### Requirement: Select what to export

The app SHALL limit `export transactions` with `from account` to an account or an account group and with `from category` to a category or a category group. Both together select transactions that fit both. Without both, the command exports the transactions of all accounts.

#### Scenario: Group

- **GIVEN** the group "Private" with two accounts
- **WHEN** a script runs `export transactions from account "Private" from date "2026-01-01" as "plist"`
- **THEN** the result holds the transactions of both accounts

#### Scenario: Nested category

- **WHEN** a script runs `export transactions from category "Household\\Food" from date "2026-01-01" as "plist"`
- **THEN** the result holds only transactions of the category "Food" in the group "Household"

#### Scenario: Account and category

- **WHEN** a script gives `from account "Giro"` and `from category "Food"`
- **THEN** the result holds the transactions of "Giro" that are in "Food"

### Requirement: Account lookup

The app SHALL find the account of a command by trying the given text as a UUID, an IBAN, an account number, an account name, and a group name, in this order. A text that fits no account, or a name that fits more than one, makes the command fail with an error that says which.

#### Scenario: IBAN with spaces

- **WHEN** a script gives `from account "DE02 1203 0000 0000 2020 51"`
- **THEN** the app finds the account with the IBAN DE02120300000000202051

#### Scenario: Unknown account

- **WHEN** a script gives `from account "Does not exist"`
- **THEN** the command fails with an error that names "Does not exist"

#### Scenario: Two accounts with the same name

- **GIVEN** two accounts named "Giro"
- **WHEN** a script gives `from account "Giro"`
- **THEN** the command fails and asks for the IBAN or the UUID

### Requirement: Export portfolio

The app SHALL return an XML property list of the positions of portfolio accounts for `export portfolio as "plist"`. `from account` limits the result to an account or a group, and `from asset class` to an asset class by UUID or name. Without both, the result covers all portfolios. Only the format `plist` is accepted.

#### Scenario: One portfolio

- **GIVEN** a portfolio with the account number 4711951502 and 2 positions
- **WHEN** a script runs `export portfolio from account "4711951502" as "plist"`
- **THEN** the result has 2 positions, each with the name, the ISIN, the quantity, the price, and the value of the security

#### Scenario: Other format

- **WHEN** a script runs `export portfolio as "csv"`
- **THEN** the command fails with an error that says that only `plist` is supported

### Requirement: Create bank transfer

The app SHALL open a payment window that is filled with the given values for `create bank transfer`. All parameters are optional. They are `from account`, `to`, `iban`, `bic`, `amount` in euro, `purpose`, `endtoend reference`, `purpose code`, `instrument code` with `TRF` as the default or `INST` for an instant payment, and `scheduled date`.

#### Scenario: Filled window

- **WHEN** a script runs `create bank transfer from account "DE02120300000000202051" to "Erika Mustermann" iban "DE02120300000000202051" amount 100.00 purpose "Rechnung 4711"`
- **THEN** a payment window opens with these values
- **AND** nothing is sent to the bank until the user confirms in the window

#### Scenario: Instant payment

- **WHEN** a script adds `instrument code "INST"`
- **THEN** the window opens with the action "New instant payment"

#### Scenario: No parameters

- **WHEN** a script runs `create bank transfer`
- **THEN** an empty payment window opens

### Requirement: Save a payment to the outbox

The app SHALL save the payment as a draft in the outbox and open no window when a payment command has the parameter `into "outbox"`. A draft with missing or invalid values is still saved, and the outbox marks it as incomplete.

#### Scenario: Silent draft

- **WHEN** a script runs `create bank transfer to "Max Mustermann" iban "DE02120300000000202051" amount 25.00 purpose "Beitrag" into "outbox"`
- **THEN** the outbox has a new draft with these values
- **AND** no window opens

### Requirement: Automation never sends a payment

The app SHALL not transmit any payment to a bank as the direct result of a scripting command. Every payment that a command creates needs the confirmation of the user and the bank's approval step in the app.

#### Scenario: Script loops over invoices

- **WHEN** a script creates 20 drafts with `into "outbox"`
- **THEN** the bank receives nothing until the user sends the drafts in the app

### Requirement: Create direct debit

The app SHALL open a filled direct debit window for `create direct debit`. All parameters are optional. They are `from account`, `for`, `iban`, `bic`, `amount`, `purpose`, `endtoend reference`, `purpose code`, `instrument code` with `CORE` as the default or `B2B`, `sequence code` with `RCUR` as the default, `FNAL`, or `OOFF`, `mandate reference`, `mandate date`, `scheduled date`, and `into`.

#### Scenario: Recurring core debit

- **WHEN** a script runs `create direct debit from account "DE02120300000000202051" for "Max Mustermann" iban "DE02120300000000202051" amount 100.00 purpose "Beitrag" mandate reference "M-0001" mandate date "2026-02-01" scheduled date "2026-12-01"`
- **THEN** a direct debit window opens with these values, the kind core, and the sequence first or recurring

#### Scenario: Invalid sequence code

- **WHEN** a script gives `sequence code "ABCD"`
- **THEN** the command fails with an error that lists `RCUR`, `FNAL`, and `OOFF`

### Requirement: Create batch orders from a file

The app SHALL open the batch window for the SEPA XML file that `create batch transfer from` or `create batch direct debit from` names, as the menu commands for a SEPA XML file do. The command fails when the file does not exist, cannot be read, or is not a SEPA XML file of the right kind.

#### Scenario: Batch transfer file

- **GIVEN** a SEPA XML file with 12 credit transfers
- **WHEN** a script runs `create batch transfer from POSIX file "/Users/erika/Documents/Sammler.xml"`
- **THEN** the batch transfer window opens with 12 positions

#### Scenario: Debit file given to the transfer command

- **WHEN** the file holds direct debits
- **THEN** the command fails with an error that says that the file contains direct debits

### Requirement: Add a transaction to an offline account

The app SHALL add a transaction to an offline account for `add transaction`. The parameters `to account`, `on date`, `to`, and `amount` are required. `purpose` and `category` are optional. Without `category` the app applies the categorization rules. The command fails for an account with a bank access.

#### Scenario: Cash expense

- **WHEN** a script runs `add transaction to account "Wallet" on date "2026-11-09" to "Bäckerei Gutbrot" amount -4.20 purpose "Brötchen" category "Household\\Food"`
- **THEN** the offline account "Wallet" has a new transaction of -4,20 € on 9 November 2026 in the category "Food"

#### Scenario: No category given

- **GIVEN** the category "Food" has the rule `"Bäckerei"`
- **WHEN** a script adds a transaction to "Bäckerei Gutbrot" without `category`
- **THEN** the transaction is in "Food"

#### Scenario: Online account

- **WHEN** a script names an account that has a bank access
- **THEN** the command fails with an error that says that the account is not an offline account

### Requirement: Set checkmark, category, and comment

The app SHALL change the transaction with the given `id` for `set transaction`. `checkmark to` takes "on" or "off". `category to` takes a UUID or a category name with a backslash between nested names. `comment to` takes a text, and an empty text removes the comment. A category that a script sets counts as assigned by hand.

#### Scenario: Checkmark

- **GIVEN** a transaction with the ID 8534 from a property list export
- **WHEN** a script runs `set transaction id 8534 checkmark to "on"`
- **THEN** the transaction shows a checkmark in the list

#### Scenario: Category survives rules

- **WHEN** a script runs `set transaction id 8534 category to "Household\\Food"` and a refresh runs afterwards
- **THEN** the transaction stays in "Food"

#### Scenario: Unknown ID

- **WHEN** a script runs `set transaction id 99999999 comment to "x"`
- **THEN** the command fails with an error that says that no transaction has this ID

### Requirement: Category lookup

The app SHALL find the category of a command by trying the given text as a UUID and then as a name or a path of names with backslashes. A text that fits no category, or a name that fits more than one, makes the command fail with an error that says which.

#### Scenario: Same name in two groups

- **GIVEN** a category "Insurance" in the group "Car" and one in the group "Home"
- **WHEN** a script gives `category "Insurance"`
- **THEN** the command fails and asks for the path or the UUID

### Requirement: Dates in commands

The app SHALL accept a date parameter as text in the form YYYY-MM-DD or as an AppleScript date value. Any other text makes the command fail with an error that shows the expected form.

#### Scenario: German date text

- **WHEN** a script gives `from date "01.01.2026"`
- **THEN** the command fails and names the form YYYY-MM-DD

#### Scenario: Date value

- **WHEN** a script gives `from date (current date) - 30 * days`
- **THEN** the command uses the day 30 days ago

### Requirement: Errors reach the calling script

The app SHALL report every failure of a command as an AppleScript error with a message in the language of the interface. The app shows no dialog for it. A command that needs a locked database to be open fails with an error that says that the database is locked.

#### Scenario: Locked database

- **GIVEN** the app is locked
- **WHEN** a script runs `export accounts`
- **THEN** the script receives an error that says that the database is locked
- **AND** the app returns no data

#### Scenario: Error text in osascript

- **WHEN** `osascript` runs a failing command
- **THEN** the message appears on standard error and the exit status is not 0

### Requirement: Turn automation off

The app SHALL offer the setting "Allow automation with AppleScript", which is on by default. While it is off, every command fails with an error that names the setting.

#### Scenario: Setting off

- **GIVEN** the setting is off
- **WHEN** a script runs `export transactions from date "2026-01-01" as "plist"`
- **THEN** the script receives an error that says that automation is turned off in the settings

### Requirement: Commands for features that are not available

The app SHALL fail a command with a clear error when the feature behind it is not part of the installed version, and name the feature.

#### Scenario: Direct debits not built yet

- **GIVEN** a version of the app without direct debits
- **WHEN** a script runs `create direct debit`
- **THEN** the script receives an error that says that this version does not support direct debits
