# Spec Delta

## Purpose

Import and export extensions are Lua scripts that add a file format to the app. An import extension turns a file into transactions. An export extension turns transactions into a file or hands them to another app. This capability defines both programming interfaces, which are compatible with the Import API and the Export API that MoneyMoney publishes, and where the formats appear in the app.

## ADDED Requirements

### Requirement: Registration with Importer

The app SHALL accept a script in the "Extensions" folder as an import extension when it calls `Importer{}` with a numeric `version`. The fields `format`, `fileExtension`, and `description` are optional. The app defines these values and `extensionName` as globals for the script.

#### Scenario: Valid registration

- **WHEN** a script starts with `Importer{version = 1.00, format = "Tab-separated values", fileExtension = "tsv"}`
- **THEN** the settings list the extension with version 1.00 as an import extension

#### Scenario: Missing version

- **WHEN** a script calls `Importer{format = "Tab-separated values"}`
- **THEN** the format is not offered and the log says that `version` is missing

### Requirement: Import formats in the import dialog

The app SHALL show the `format` label of each import extension in the format selection of "Import Transactions...". When the user selects it, the dialog accepts files with the `fileExtension` of the script.

#### Scenario: Select the format

- **GIVEN** an installed import extension with the format "Tab-separated values" and the file extension `tsv`
- **WHEN** the user opens "Import Transactions..." and selects "Tab-separated values"
- **THEN** the dialog lets the user choose `umsaetze.tsv`

### Requirement: ReadTransactions

The app SHALL call `ReadTransactions(account)` once for each chosen file. The script reads the file content from standard input with `io.read` or `io.lines`. The app opens and closes the file. The function returns an array of transaction tables or an error message.

#### Scenario: Three lines

- **GIVEN** a file with 3 lines in the form date, tab, amount, tab, purpose, and the template script from the documentation
- **WHEN** the user imports the file
- **THEN** the script reads 3 lines and returns 3 transactions
- **AND** the app reports "Imported 3 new transactions."

#### Scenario: Script reports an error

- **WHEN** `ReadTransactions` returns `"Line 2 has no amount."`
- **THEN** the app shows that the file could not be imported with the message "Line 2 has no amount."
- **AND** no transaction is stored

### Requirement: Account table for import extensions

The app SHALL pass the account that receives the import to `ReadTransactions` as a table with the fields `name`, `owner`, `accountNumber`, `subAccount`, `bankCode`, `currency`, `iban`, `bic`, and `type`. The values of `type` are `AccountTypeGiro`, `AccountTypeSavings`, `AccountTypeFixedTermDeposit`, `AccountTypeLoan`, `AccountTypeCreditCard`, `AccountTypeCash`, and `AccountTypeOther`.

#### Scenario: Cash account

- **GIVEN** the selected account is the offline account "Wallet" in EUR
- **WHEN** the app calls `ReadTransactions`
- **THEN** `account.name` is "Wallet", `account.currency` is "EUR", and `account.type` equals `AccountTypeCash`

### Requirement: Transaction tables from import extensions

The app SHALL read these fields of an imported transaction. `amount` and `bookingDate` are required. `name`, `accountNumber`, `bankCode`, `currency`, `valueDate`, `purpose`, `bookingText`, `endToEndReference`, `mandateReference`, `creditorId`, `returnReason`, `booked`, `category`, and `comment` are optional. Dates are POSIX time stamps.

#### Scenario: Category and comment

- **WHEN** a script returns `{bookingDate=1794182400, amount=-12.50, name="Bäckerei Gutbrot", category="Food", comment="Breakfast"}`
- **THEN** the transaction has the comment "Breakfast" and the category "Food", under the rules for categories from imported files

#### Scenario: Missing booking date

- **WHEN** one returned transaction has no `bookingDate`
- **THEN** the import fails with a message that names the position of that transaction, and nothing is stored

### Requirement: Booking codes from import extensions

The app SHALL read and store the optional fields `transactionCode`, `textKeyExtension`, `purposeCode`, `bookingKey`, `primanotaNumber`, and `batchReference` of an imported transaction.

#### Scenario: Purpose code

- **WHEN** a script returns a transaction with `purposeCode="SALA"`
- **THEN** the stored transaction has the purpose code SALA

### Requirement: Imported transactions follow the import rules

The app SHALL treat the transactions of an import extension like those of a built-in format. Transactions that already exist are skipped and counted, new ones pass the categorization rules, and the result message reports both numbers.

#### Scenario: Second import of the same file

- **GIVEN** a file with 3 transactions that was imported before
- **WHEN** the user imports it again through the same extension
- **THEN** the app reports that no new transactions were imported and that 3 existing ones were skipped

### Requirement: Registration with Exporter

The app SHALL accept a script as an export extension when it calls `Exporter{}` with a numeric `version`. The fields `format`, `fileExtension`, `bundleIdentifier`, `hidden`, `reverseOrder`, and `description` are optional. The app defines these values and `extensionName` as globals for the script.

#### Scenario: Valid registration

- **WHEN** a script starts with `Exporter{version = 1.00, format = "Custom CSV file", fileExtension = "csv", description = "Export transactions as custom CSV file"}`
- **THEN** the settings list the extension with its description as an export extension

### Requirement: Export formats in the export dialog

The app SHALL show the `format` label of each export extension in the format selection of "Export Transactions..." unless the script sets `hidden` to true. The saved file gets the `fileExtension` of the script.

#### Scenario: Visible format

- **GIVEN** an export extension with the format "Custom CSV file" and the file extension `csv`
- **WHEN** the user opens "Export Transactions..." and selects "Custom CSV file"
- **THEN** the suggested file name ends with `.csv`

#### Scenario: Hidden format

- **WHEN** a script registers with `hidden = true`
- **THEN** the format does not appear in the export dialog

### Requirement: Order of export calls

The app SHALL call `WriteHeader(account, startDate, endDate, transactionCount)` once, then `WriteTransactions(account, transactions)` once for each booking day with the transactions of that day, then `WriteTail(account)` once. The script writes with `io.write` to standard output. The app opens and closes the output file.

#### Scenario: Five transactions on two days

- **GIVEN** an export of 5 transactions, 3 booked on 3 November 2026 and 2 on 5 November 2026
- **WHEN** the export runs
- **THEN** the script receives `WriteHeader` with `transactionCount` 5, `startDate` on 3 November, and `endDate` on 5 November
- **AND** two calls of `WriteTransactions`, with 2 and then 3 transactions
- **AND** one call of `WriteTail`

#### Scenario: No transactions

- **WHEN** the export has no transactions
- **THEN** the script receives `WriteHeader` with `transactionCount` 0 and `WriteTail`, and no call of `WriteTransactions`

### Requirement: Order of exported transactions

The app SHALL pass the transactions in the order of the transaction list, newest first. With `reverseOrder` true the app passes the oldest first.

#### Scenario: Reverse order

- **GIVEN** a script with `reverseOrder = true` and transactions on 3 and 5 November 2026
- **WHEN** the export runs
- **THEN** the first call of `WriteTransactions` holds the transactions of 3 November

### Requirement: Account table for export extensions

The app SHALL pass the account as a table with the import fields and also `attributes` with the user-defined fields, `comment` with the notes, `balance`, and `balanceDate`. Each `type` constant has the English name of the account type as its value, and `MM.localizeText` translates it.

#### Scenario: Header with the balance

- **GIVEN** the account "Giro" with the balance 1.234,56 € from 9 November 2026
- **WHEN** the app calls `WriteHeader`
- **THEN** `account.balance` is 1234.56 and `account.balanceDate` is a time stamp on 9 November 2026

#### Scenario: Export of a group

- **GIVEN** an export of the account group "Private" with two accounts
- **WHEN** the app calls `WriteHeader`
- **THEN** `account.name` is "Private" and `account.accountNumber` is empty
- **AND** each transaction table carries `accountName` and `accountIban` of its own account

### Requirement: Transaction tables for export extensions

The app SHALL pass each transaction with the fields of the import structure and also `checkmark`, `category`, `comment`, and `id`. `category` holds the full path with a backslash between a group and its category. `id` is the stable number of the transaction in the database.

#### Scenario: Nested category

- **GIVEN** a checked transaction in the category "Food" inside the group "Household"
- **WHEN** the script reads the transaction
- **THEN** `transaction.category` is `Household\Food` and `transaction.checkmark` is true

#### Scenario: Uncategorized

- **WHEN** a transaction has no category
- **THEN** `transaction.category` is the name of the default category

### Requirement: Errors of an export extension

The app SHALL stop the export when an entry point returns an error message or the script stops with an error. The app shows that the export failed with the message and deletes the file that was partly written.

#### Scenario: Error in the middle

- **WHEN** the second call of `WriteTransactions` returns `"Unsupported currency USD."`
- **THEN** the app reports that it could not export to the file, with that message
- **AND** no file is left at the chosen place

### Requirement: Integrations through a bundle identifier

The app SHALL treat an export extension with `bundleIdentifier` as an integration for the app with that bundle identifier while that app is installed. When the user sends transactions to that app, the app writes them with the script to a temporary file and opens the file with the target app.

#### Scenario: Integration installed

- **GIVEN** an export extension with `bundleIdentifier = "com.example.invoices"`, and the app "Invoices" with that identifier is installed
- **WHEN** the user sends 2 selected transactions to "Invoices"
- **THEN** the script runs for the 2 transactions, and "Invoices" opens the file that the script wrote

#### Scenario: App not installed

- **WHEN** no installed app has the identifier
- **THEN** the extension adds no integration, and its format still appears in the export dialog unless it is hidden

### Requirement: Export extensions in automation

The app SHALL accept the `format` label of an installed export extension as the format of the automation command that exports transactions, also when the script sets `hidden` to true.

#### Scenario: Script format by name

- **GIVEN** an installed export extension with the format "Custom CSV file"
- **WHEN** a script runs `export transactions from date "2026-01-01" as "Custom CSV file"`
- **THEN** the command returns the path of a file that the extension wrote

### Requirement: Functions for import and export scripts

The app SHALL offer import and export scripts the functions `MM.localizeText`, `MM.localizeDate`, `MM.localizeNumber`, `MM.localizeAmount`, `MM.toEncoding`, and `MM.fromEncoding`, and the values `MM.productName` and `MM.productVersion`, with the same behavior as for web banking extensions. Output of `print` goes to the log, and `error` stops the script.

#### Scenario: File for a program without UTF-8

- **WHEN** an export script writes `MM.toEncoding("ISO-8859-1", "Müller")`
- **THEN** the file holds the name in ISO-8859-1 with one byte for the letter ü

#### Scenario: Localized date

- **GIVEN** the system uses German formats
- **WHEN** a script calls `MM.localizeDate(1794182400)`
- **THEN** the result is "09.11.2026"

### Requirement: Limits of import and export scripts

The app SHALL run import and export scripts without network access. `io` gives access to standard input for an import script and to standard output for an export script, and to no other file. The other limits of the Lua runtime for extensions apply.

#### Scenario: Network call

- **WHEN** an export script calls `Connection()`
- **THEN** the script stops with an error that says that `Connection` is not available

#### Scenario: Open another file

- **WHEN** an import script calls `io.open("/Users/erika/notes.txt")`
- **THEN** the call fails and the import ends with an error

### Requirement: Installation and trust of import and export scripts

The app SHALL install, list, warn about, verify, and remove import and export scripts by the same rules as web banking extensions. The list in the settings shows the kind of each extension.

#### Scenario: Unknown script

- **GIVEN** the user copied `Ledger.lua`, an export script that is not in the catalog, into the "Extensions" folder
- **WHEN** the user first selects its format in the export dialog
- **THEN** the app asks for confirmation before the script runs
