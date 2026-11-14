# Spec Delta

## Purpose

A file import fills an account with transactions that no bank connection delivers, for example older history or data from another finance program. This capability defines which files the app reads, how it detects their format, how the user checks and corrects a CSV import, how duplicates are handled, and what the app reports.

## ADDED Requirements

### Requirement: Import command

The app SHALL offer "Import Transactions..." in the Account menu and in the context menu of an account. The command opens a file dialog in which the user can select several files. The command is disabled while an account group, a category, or a portfolio is selected.

#### Scenario: Import into the selected account

- **GIVEN** the account "Giro" is selected
- **WHEN** the user chooses "Import Transactions..." and selects `umsaetze-2024.csv`
- **THEN** the app imports the file into "Giro"

#### Scenario: Group selected

- **WHEN** an account group is selected
- **THEN** "Import Transactions..." is disabled

### Requirement: Offline and online accounts

The app SHALL import files into accounts with a bank access and into offline accounts alike.

#### Scenario: Older history for an online account

- **GIVEN** a FinTS account whose bank delivered transactions back to 1 August 2026
- **WHEN** the user imports a CSV file with the transactions of 2025
- **THEN** the account shows the transactions of 2025 below the fetched ones

### Requirement: Format detection

The app SHALL detect the format of a file from its content. In this version the formats are CSV, camt.052, camt.053, and MT940. The file name and its extension do not decide.

#### Scenario: CAMT file named .txt

- **WHEN** the user selects `export.txt` whose content is a camt.053 document
- **THEN** the app imports it as camt.053

### Requirement: Unsupported files

The app SHALL refuse a file in a format that it does not support, with a message that names the detected kind of file when it is known and lists the supported formats.

#### Scenario: PDF file

- **WHEN** the user selects `kontoauszug.pdf`
- **THEN** the app says that files in this format cannot be imported and lists CSV, MT940, and SEPA camt.052 and camt.053

### Requirement: Empty and oversized files

The app SHALL refuse a file that contains no transactions with a message that says so, and a file larger than 100 MB with a message that names the limit.

#### Scenario: Header only

- **WHEN** the user imports a CSV file that has a header row and no other row
- **THEN** the app says that the file is empty and does not contain any transactions

#### Scenario: Too large

- **WHEN** the user selects a file of 150 MB
- **THEN** the app says that the file is too large and that the maximum is 100 MB

### Requirement: CSV structure detection

The app SHALL detect the delimiter of a CSV file among semicolon, comma, and tab, the text encoding among UTF-8, UTF-16, ISO-8859-1, and Windows-1252, quoted fields with doubled quotation marks, and the header row. Lines before the header row, which many banks add, are skipped.

#### Scenario: Bank export with a preamble

- **GIVEN** a file in ISO-8859-1 with 4 lines of account information, then a header row, then rows separated by semicolons
- **WHEN** the user imports the file
- **THEN** the preview shows the header row as column titles and "Bäckerei Gutbrot" with the correct umlaut

#### Scenario: Delimiter inside quotes

- **WHEN** a field is `"Miete; Nebenkosten"` in a file separated by semicolons
- **THEN** the app reads it as one field with the text "Miete; Nebenkosten"

### Requirement: CSV date detection

The app SHALL detect the date format of each date column from all its values, including day first and month first orders, two-digit and four-digit years, and ISO dates. When the values fit more than one order, the app marks the choice in the preview so that the user confirms or changes it.

#### Scenario: Clear European dates

- **WHEN** a column holds "31.10.2026" and "03.11.2026"
- **THEN** the app reads day, month, year

#### Scenario: Ambiguous dates

- **WHEN** every value of a column is like "03/04/2026" and "05/06/2026"
- **THEN** the preview marks the date format as uncertain and offers day first and month first

### Requirement: CSV amount detection

The app SHALL read amounts with a decimal comma or a decimal point, with or without thousands separators, with a leading or trailing sign, and with a currency symbol or code. The app also reads files with separate columns for debit and credit and files with a column that marks debit or credit. An amount that fits both decimal marks with different values, such as "1,234", takes the decimal mark that the other amounts of the dated rows show.

#### Scenario: German format

- **WHEN** an amount column holds "-1.234,56"
- **THEN** the app reads a withdrawal of 1.234,56 €

#### Scenario: Debit and credit columns

- **GIVEN** the columns "Soll" and "Haben"
- **WHEN** a row has "89,00" under "Soll" and nothing under "Haben"
- **THEN** the app reads a withdrawal of 89,00 €

#### Scenario: Marker column

- **WHEN** a row has the amount "89,00" and "S" in a debit and credit marker column
- **THEN** the app reads a withdrawal of 89,00 €

#### Scenario: Amount without decimals takes the decimal mark of the file

- **GIVEN** a CSV file with the amount "-4.50" in one dated row
- **WHEN** another dated row has the amount "1,234"
- **THEN** the app reads a deposit of 1.234,00 €

#### Scenario: Row without a date does not decide the decimal mark

- **GIVEN** a CSV file with the amounts "1,234" and "4.50" in dated rows
- **WHEN** a total row without a date has the amount "0,00"
- **THEN** the app reads a deposit of 1.234,00 € and a deposit of 4,50 €

#### Scenario: Ambiguous amount fails the file

- **GIVEN** a CSV file whose only amount is "1,234" in line 2
- **WHEN** the user imports the file
- **THEN** the app imports nothing and says that the amount in line 2 cannot be read

### Requirement: CSV columns by header keywords

The app SHALL assign CSV columns to transaction fields by common header keywords in German and English, without regard to case, spaces, and umlauts. The fields are booking date, value date, amount, currency, counterparty name, counterparty account or IBAN, counterparty bank code or BIC, purpose, booking text, category, and comment.

#### Scenario: German headers

- **WHEN** a file has the headers "Buchungstag", "Wertstellung", "Auftraggeber/Empfänger", "Verwendungszweck", "Betrag", and "Währung"
- **THEN** the preview assigns them to booking date, value date, name, purpose, amount, and currency

#### Scenario: English headers

- **WHEN** a file has the headers "Date", "Payee", "Memo", and "Amount"
- **THEN** the preview assigns them to booking date, name, purpose, and amount

### Requirement: CSV preview

The app SHALL show a preview before it imports a CSV file. The preview shows the first rows as the app reads them, the field that each column is assigned to, the date format, the decimal separator, and the encoding. The user can change each of these, and the preview updates at once.

#### Scenario: Correct a column

- **GIVEN** the preview assigned the column "Text" to no field
- **WHEN** the user assigns "Text" to the purpose
- **THEN** the preview rows show the content of "Text" as the purpose

#### Scenario: Required fields missing

- **WHEN** no column is assigned to the booking date or to the amount
- **THEN** the "Import" button is disabled and the preview says which field is missing

### Requirement: CSV profiles

The app SHALL let the user save the settings of the preview as a named profile. When a later file has the same header row, the app applies the profile and imports without showing the preview first. The user can still open the preview, and can rename and delete profiles.

#### Scenario: Second file of the same bank

- **GIVEN** the user saved the profile "Broker CSV" for a file with 9 named columns
- **WHEN** the user imports another file with the same header row
- **THEN** the app imports it with "Broker CSV" and names the profile in the result message

#### Scenario: Header changed

- **WHEN** the bank adds a column and the header row no longer matches the profile
- **THEN** the app shows the preview again with the profile as the starting point

### Requirement: Categories from a CSV file

The app SHALL assign the category from a category column to each imported transaction when a category with that name or path exists. With the option "Auto-create categories" the app creates the missing categories and reports their number. Without the option, a transaction with an unknown category is treated as one without a category.

#### Scenario: Create missing categories

- **GIVEN** the category "Food" exists and "Pets" does not
- **WHEN** the user imports rows with the categories "Food" and "Pets" with "Auto-create categories" on
- **THEN** the app creates "Pets", assigns both categories, and reports "Created one new category."

#### Scenario: Option off

- **WHEN** the same file is imported with the option off
- **THEN** the "Pets" rows pass the categorization rules like any new transaction

### Requirement: CAMT import

The app SHALL import camt.052 and camt.053 files with the booking date, the value date, the amount, the currency, the counterparty with IBAN and BIC, the purpose, the booking text, the end-to-end reference, the mandate reference, the creditor ID, the return reason, and the state booked or pending of each entry. An entry with several transaction details becomes one transaction for each detail.

#### Scenario: Statement with three entries

- **WHEN** the user imports a camt.053 file with 3 booked entries
- **THEN** the account has 3 new booked transactions with their references in the details

#### Scenario: Pending entry

- **WHEN** a camt.052 file holds an entry with the status pending
- **THEN** the app imports it as a pending transaction

### Requirement: MT940 import

The app SHALL import MT940 files, with the usual extension `.sta`, including the structured purpose fields of German banks for the counterparty name, the account, the bank code, the booking text, and the SEPA references.

#### Scenario: Structured purpose

- **WHEN** an MT940 entry carries the end-to-end reference "E2E-1" and the mandate reference "M-0001" in its purpose fields
- **THEN** the imported transaction shows both references in its details and not inside the purpose text

### Requirement: Several files at once

The app SHALL import all files that the user selected in the dialog one after the other and report the result for each file by name. A file that fails does not stop the others.

#### Scenario: Twelve monthly files

- **WHEN** the user selects 12 MT940 files and one of them is damaged
- **THEN** the app imports 11 files and names the damaged file with the reason

### Requirement: File belongs to another account

The app SHALL compare the IBAN or account number inside a CAMT or MT940 file with the selected account. When it belongs to another account of the app, the app asks whether to import into that account. When no account has it, the app asks whether to import into the selected account or into a new offline account.

#### Scenario: Wrong account selected

- **GIVEN** the account "Savings" is selected and the file names the IBAN of the account "Giro"
- **WHEN** the user imports the file
- **THEN** the app asks whether to import into "Giro" and imports there after the user agrees

#### Scenario: Unknown IBAN

- **WHEN** the file names an IBAN that no account has
- **THEN** the app offers "Import into the selected account" and "Create offline account"

### Requirement: Existing transactions are skipped

The app SHALL not import a transaction that the account already holds, and it SHALL not change the stored transaction. The result message states the number of skipped transactions.

#### Scenario: Overlap with fetched transactions

- **GIVEN** the account holds the transactions of October 2026 from a refresh
- **WHEN** the user imports a file with the transactions of September and October 2026
- **THEN** only the September transactions are added
- **AND** the message says how many existing transactions were skipped, for example "Skipped 42 already existing transactions."

#### Scenario: Same file twice

- **WHEN** the user imports a file a second time
- **THEN** the app reports "Imported no new transactions." and the number of skipped ones

### Requirement: Identical rows inside one file

The app SHALL keep rows that are identical inside one file as separate transactions, because they are separate bookings.

#### Scenario: Two equal purchases

- **WHEN** a file holds two rows with the same date, amount, name, and purpose
- **THEN** the account has two transactions after the first import and still two after a second import of the file

### Requirement: Result message

The app SHALL report after an import how many new transactions were imported, for example "Imported 128 new transactions." or "Imported one new transaction.", together with the numbers of skipped transactions and of created categories.

#### Scenario: Mixed result

- **WHEN** an import adds 128 transactions, skips 3, and creates 2 categories
- **THEN** the message states all three numbers

### Requirement: Errors name the file and the place

The app SHALL report a file that it cannot read with the file name, the line or element, and the reason. The app imports nothing from that file.

#### Scenario: Bad amount in line 17

- **WHEN** line 17 of `umsaetze.csv` has the text "abc" in the amount column
- **THEN** the app reports an error in the file `umsaetze.csv`, line 17, with the reason that the amount cannot be read
- **AND** the account has no new transaction from this file

#### Scenario: Broken XML

- **WHEN** a CAMT file is not well-formed XML
- **THEN** the app reports the file and the position of the first error

### Requirement: Warnings for a file

The app SHALL import a file that has values it can read around, and list them as warnings with the file name after the import. Examples are an unknown currency code that falls back to the account currency and a value date that is not a date.

#### Scenario: Unreadable value date

- **WHEN** one row has "n/a" as the value date and a valid booking date
- **THEN** the app imports the row without a value date and lists a warning for that line

### Requirement: Imported transactions are complete transactions

The app SHALL treat an imported transaction like a fetched one. It can be searched, categorized, split, commented, checked, exported, and deleted.

#### Scenario: Search finds an imported row

- **GIVEN** the user imported a row with the purpose "Gehalt 03/2024"
- **WHEN** the user types "Gehalt 03" in the search field
- **THEN** the list shows the imported transaction

#### Scenario: Delete an imported row

- **WHEN** the user deletes an imported transaction and imports the same file again
- **THEN** the transaction comes back, because the account no longer holds it

### Requirement: Balances and charts after an import

The app SHALL recompute the balance of an offline account and the balance history of every account after an import, so that charts include the imported transactions.

#### Scenario: Offline account

- **GIVEN** an offline account with a balance of 0,00 €
- **WHEN** the user imports 3 transactions that sum to 250,00 €
- **THEN** the account shows a balance of 250,00 €

#### Scenario: Chart of an online account

- **WHEN** the user imports the transactions of 2025 into an online account
- **THEN** the bar chart shows balances for 2025

### Requirement: Progress and cancel

The app SHALL show progress while it imports and let the user cancel. A canceled import leaves no transaction of the file that was being read.

#### Scenario: Cancel a large file

- **WHEN** the user cancels while the app reads the third of five files
- **THEN** the transactions of the first two files stay, and nothing of the third file is stored
