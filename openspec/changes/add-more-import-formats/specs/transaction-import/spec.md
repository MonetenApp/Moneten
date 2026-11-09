# Spec Delta

## ADDED Requirements

### Requirement: QIF import

The app SHALL import QIF files with the date, the amount, the payee as the counterparty name, the memo as the purpose, the check number as a reference, and the cleared state as the checkmark of each record.

#### Scenario: Bank section

- **WHEN** the user imports a QIF file with a bank section of 40 records
- **THEN** the account has 40 new transactions with name, purpose, and amount

#### Scenario: Cleared record

- **WHEN** a record is marked as cleared
- **THEN** the imported transaction has a checkmark

### Requirement: QIF date formats

The app SHALL read the dates of a QIF file with the date format that the file states. When the file states none, the app detects the order of day and month from all records, and it reads the apostrophe form for years from 2000.

#### Scenario: File states its format

- **WHEN** a QIF file declares the date format day, month, year
- **THEN** the app reads "03/04/26" as 3 April 2026

#### Scenario: American file without a declaration

- **WHEN** a file has the dates "11/30'26" and "12/01'26"
- **THEN** the app reads 30 November 2026 and 1 December 2026

### Requirement: QIF categories

The app SHALL take the category of a QIF record, with a colon between a group and its category, and apply the rules of the option "Auto-create categories". A split record becomes a split transaction with one part for each split line.

#### Scenario: Nested category

- **GIVEN** "Auto-create categories" is on and no category "Household" exists
- **WHEN** a record has the category "Household:Food"
- **THEN** the app creates the group "Household" with the category "Food" and assigns the transaction to "Food"

#### Scenario: Split record

- **WHEN** a record of -100,00 € has two split lines of -60,00 € for "Food" and -40,00 € for "Pets"
- **THEN** the app imports one transaction of -100,00 € that is split into these two parts

### Requirement: QIF sections that are not transactions of the account

The app SHALL import the bank, cash, and credit card sections of a QIF file and skip investment sections and lists of categories, classes, and accounts. The result message says what was skipped.

#### Scenario: Investment section

- **WHEN** a file has a bank section and an investment section
- **THEN** the app imports the bank section and reports that the investment section was skipped

### Requirement: OFX and QFX import

The app SHALL import OFX and QFX files in the SGML form and in the XML form, with the posting date, the amount, the name, the memo, the transaction type as the booking text, and the transaction ID of each statement transaction.

#### Scenario: Credit card statement

- **WHEN** the user imports a QFX file with a credit card statement of 25 transactions
- **THEN** the selected credit card account has 25 new transactions

#### Scenario: Imported before

- **GIVEN** a transaction with the OFX transaction ID "20261103-0007" was imported last month
- **WHEN** a new file contains the same ID with a changed memo
- **THEN** the app skips it and counts it as existing

### Requirement: OFX files with several accounts

The app SHALL import from an OFX file only the statement whose account number fits the selected account. When the file holds statements for other accounts of the app, the app offers to import them into those accounts in the same step.

#### Scenario: Two statements

- **GIVEN** a file with statements for the accounts "Giro" and "Savings", and "Giro" is selected
- **WHEN** the user imports the file
- **THEN** the app asks whether to import the second statement into "Savings"
- **AND** no transaction of "Savings" lands in "Giro"

### Requirement: Tab-separated text

The app SHALL import tab-separated text files through the CSV preview, with the tab as the delimiter and the same detection of dates, amounts, and columns.

#### Scenario: Copied from a spreadsheet

- **WHEN** the user imports a text file with the columns date, amount, and purpose separated by tabs and no header row
- **THEN** the preview shows three columns and proposes the fields booking date, amount, and purpose from their content

### Requirement: CSV exports of other finance apps

The app SHALL ship profiles for the CSV exports of common finance apps and of its own CSV export. A file whose header row fits such a profile is imported without the preview, with all fields the file offers, including category, comment, and checkmark where present.

#### Scenario: Own CSV export

- **GIVEN** a CSV file that the app exported from the account "Giro"
- **WHEN** the user imports it into an empty offline account
- **THEN** all transactions arrive with their categories and comments, and no preview appears

#### Scenario: Unknown header

- **WHEN** a header row fits no built-in profile and no saved profile
- **THEN** the app shows the preview

### Requirement: Longer list of supported formats

The app SHALL list CSV, QIF, OFX, QFX, MT940, camt.052, camt.053, and tab-separated text in the message for a file that it cannot import, and offer the same formats in the file dialog.

#### Scenario: Spreadsheet file

- **WHEN** the user selects an `.xlsx` file
- **THEN** the message says that files in this format cannot be imported and lists the supported formats including QIF and OFX
