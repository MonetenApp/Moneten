# Spec Delta

## Purpose

Users take their data out of the app, for a spreadsheet, for another program, or to leave. This capability defines the export of transactions to files from the transaction list, and the complete export of all data to one documented file that the app can read again without loss.

## ADDED Requirements

### Requirement: Export command

The app SHALL offer "Export Transactions..." in the Account menu and in the context menus of an account, an account group, and a category. The command exports the transactions of the selected view. For selected rows, the context menu of the list offers "Export Transaction..." or "Export Transactions...".

#### Scenario: Account

- **GIVEN** the account "Giro" is selected and no row is selected
- **WHEN** the user chooses "Export Transactions..."
- **THEN** the export covers the transactions of "Giro"

#### Scenario: Category

- **WHEN** the user opens the context menu of the category "Food" and chooses "Export Transactions..."
- **THEN** the export covers the transactions of "Food" from all accounts

### Requirement: Only the selection

The app SHALL export only the selected rows when rows are selected in the transaction list.

#### Scenario: Three rows

- **GIVEN** an account with 500 transactions of which 3 are selected
- **WHEN** the user chooses "Export Transactions..." in the context menu
- **THEN** the file holds 3 transactions

### Requirement: Export follows search and filters

The app SHALL export the rows that the list shows when no row is selected. An active search and active filters limit the export in the same way as the list.

#### Scenario: Period filter

- **GIVEN** the period filter shows the current year and the list shows 212 of 4,600 transactions
- **WHEN** the user exports with no row selected
- **THEN** the file holds 212 transactions

### Requirement: Save panel with format choice

The app SHALL open a save panel for an export with a "Format" menu and a proposed file name that is built from the name of the account, group, or category and the period of the exported rows. In this version the format is CSV.

#### Scenario: Proposed name

- **GIVEN** the account "Giro" with exported rows from 1 January 2026 to 31 October 2026
- **WHEN** the save panel opens
- **THEN** the proposed name contains "Giro" and both dates, and ends with `.csv`

### Requirement: CSV columns

The app SHALL write a CSV file with a header row and these columns in this order. Date, Value date, Category, Name, Purpose, Account, Bank, Amount, Currency, Own account, Booking text, End-to-end reference, Mandate reference, Creditor ID, Comment, Checked, and Pending.

#### Scenario: Header row

- **WHEN** the user exports any transactions as CSV
- **THEN** the first line of the file holds the 17 column names in the given order

#### Scenario: One transaction

- **GIVEN** a checked withdrawal of 89,00 € to "Stadtwerke Musterstadt" with the IBAN DE02120300000000202051 on 3 November 2026 in the category "Housing" with the comment "Abschlag"
- **WHEN** the user exports it on a Mac with German formats
- **THEN** its line has "03.11.2026" under Date, "Housing" under Category, "Stadtwerke Musterstadt" under Name, the IBAN under Account, "-89,00" under Amount, "EUR" under Currency, "Abschlag" under Comment, and a mark under Checked

### Requirement: CSV format rules

The app SHALL write CSV files in UTF-8 with a byte order mark and with a semicolon between fields. Dates and numbers use the formats of the system. Amounts have two decimals and no thousands separator. A field that contains a semicolon, a quotation mark, or a line break is put in quotation marks, and a quotation mark inside it is doubled.

#### Scenario: Purpose with a semicolon

- **WHEN** a transaction has the purpose `Miete; Nebenkosten "Mai"`
- **THEN** the field is written as `"Miete; Nebenkosten ""Mai"""`

#### Scenario: Purpose with several lines

- **WHEN** a purpose has two lines
- **THEN** the field is in quotation marks and a spreadsheet program reads it as one cell

### Requirement: Categories in a CSV file

The app SHALL write the full path of the category with " - " between a category group and its category, and the name of the default category for a transaction without a category. A split transaction is written as one line for each part, with the amount and the category of the part.

#### Scenario: Nested category

- **WHEN** a transaction is in the category "Food" inside the group "Household"
- **THEN** the Category field is "Household - Food"

#### Scenario: Split transaction

- **GIVEN** a transaction of -100,00 € that is split into -60,00 € for "Food" and -40,00 € for "Pets"
- **WHEN** the user exports it
- **THEN** the file has two lines with the amounts -60,00 and -40,00 and their categories

### Requirement: Own account in group and category exports

The app SHALL write the IBAN of the account that a transaction belongs to in the column Own account, or the account number or name when the account has no IBAN.

#### Scenario: Group export

- **GIVEN** a group with the accounts "Giro" and "Savings"
- **WHEN** the user exports the group
- **THEN** each line names the IBAN of its own account, so that the lines of the two accounts can be told apart

### Requirement: Export failures

The app SHALL report a failed export with the reason, for example no write permission or a full disk, and leave no partly written file behind.

#### Scenario: Folder is write-protected

- **WHEN** the user saves the export into a folder without write permission
- **THEN** the app says that it could not export to the file and names the reason
- **AND** no file is created

### Requirement: Progress of an export

The app SHALL show progress for an export that takes longer than a moment, and let the user cancel it. A canceled export leaves no file.

#### Scenario: Large export

- **WHEN** the user exports 200,000 transactions
- **THEN** the app shows "Exporting..." with a cancel button until the file is complete

### Requirement: Complete export

The app SHALL offer "Export All Data..." in the File menu. The command writes one JSON file with all accounts, account groups, transactions with their categories, comments, checkmarks, and splits, categories with their rules, balance history, and settings that describe the data. Every capability that stores user data adds its data to this file.

#### Scenario: Database with three accounts

- **GIVEN** a database with 3 accounts, 2 groups, 25 categories with 10 rules, and 12,000 transactions
- **WHEN** the user chooses "Export All Data..." and saves the file
- **THEN** the file contains all of these objects

#### Scenario: Later capability

- **GIVEN** a version of the app that also stores transfer templates
- **WHEN** the user exports all data
- **THEN** the file also contains the templates

### Requirement: Secrets and files that the complete export leaves out

The app SHALL not write PINs, passwords, tokens, the database password, or the storage of extensions to the complete export. PDF statements are not part of the file. The export says in its summary what was left out.

#### Scenario: Saved PIN

- **GIVEN** a bank access with a saved PIN
- **WHEN** the user exports all data
- **THEN** the file names the bank, the user ID, and the access method of that access, and it does not contain the PIN

### Requirement: Warning before a complete export

The app SHALL warn before a complete export that the file is not encrypted and holds all financial data in readable form, and continue only after the user confirms.

#### Scenario: Confirm

- **WHEN** the user chooses "Export All Data..."
- **THEN** the app shows the warning with "Cancel" and "Export"
- **AND** the save panel opens only after "Export"

### Requirement: Documented and versioned format

The app SHALL write the complete export in a format that the project documents field by field, with a format version number in the file. Amounts are decimal text with a currency code. Dates are ISO 8601. Objects refer to each other by stable identifiers.

#### Scenario: Read with another program

- **WHEN** a developer opens the file and the documentation
- **THEN** every key in the file is described in the documentation for the stated format version

#### Scenario: No rounding

- **WHEN** a transaction has the amount -1.234,56 €
- **THEN** the file holds the text "-1234.56" and the currency "EUR"

### Requirement: Import a complete export

The app SHALL offer "Import All Data..." in the File menu, which reads a complete export into an empty database. After the import, the accounts, groups, categories, rules, transactions, comments, checkmarks, splits, and identifiers equal those of the exported database.

#### Scenario: Round trip

- **GIVEN** a complete export of a database
- **WHEN** the user imports it into an empty database and exports all data again
- **THEN** the second file equals the first, apart from the export date

#### Scenario: Accounts without login data

- **WHEN** the import finishes
- **THEN** each bank access exists with its bank and user ID, and the app asks for the PIN at the first refresh

### Requirement: Complete import needs an empty database

The app SHALL refuse "Import All Data..." when the database holds an account, a category that the user created, or a transaction, and say that the import works only in an empty database.

#### Scenario: Database in use

- **GIVEN** a database with one account
- **WHEN** the user chooses "Import All Data..."
- **THEN** the app refuses and changes nothing

### Requirement: Files the complete import cannot read

The app SHALL refuse a file with a newer format version and name the version of the app that is needed. The app SHALL refuse a damaged or incomplete file with the place of the first error. In both cases the database stays empty.

#### Scenario: Newer format

- **WHEN** the file has format version 5 and the app reads up to version 3
- **THEN** the app says that a newer version of the app is needed and imports nothing

#### Scenario: Truncated file

- **WHEN** the file ends in the middle of the transactions
- **THEN** the app reports the error and the database is still empty
