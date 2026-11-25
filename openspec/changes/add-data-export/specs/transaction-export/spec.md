# Spec Delta

## Purpose

Users take their data out of the app, for a spreadsheet, for another program, or to leave. This capability defines the export of transactions to files from the transaction list, and the complete export of all data to one documented file that the app can read again without loss.

## ADDED Requirements

### Requirement: Export command

The app SHALL offer "Export Transactions..." in the Account menu and in the context menus of an account, an account group, and a category. The Account menu exports the transactions of the selected view. The context menu of an account exports every transaction of that account, regardless of row selection, search, or filters. For selected rows, the context menu of the list offers "Export Transaction..." or "Export Transactions...".

#### Scenario: Account

- **GIVEN** the account "Giro" is selected and no row is selected
- **WHEN** the user chooses "Export Transactions..."
- **THEN** the export covers the transactions of "Giro"

#### Scenario: Category

- **WHEN** the user opens the context menu of the category "Food" and chooses "Export Transactions..."
- **THEN** the export covers the transactions of "Food" from all accounts

#### Scenario: Context menu of the open account

- **GIVEN** "Giro" has 500 transactions, a search shows 41, and 1 row is selected
- **WHEN** the user exports from the context menu of "Giro"
- **THEN** the file holds all 500 transactions

### Requirement: Only the selection

The app SHALL export only the visible selected rows from the Account menu or the transaction list context menu when at least one selected row is visible.

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

#### Scenario: Search hides the selection

- **GIVEN** 1 row is selected and a search hides it and shows 41 other rows
- **WHEN** the user exports from the Account menu
- **THEN** the file holds the 41 visible rows

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

The app SHALL write CSV files in UTF-8 with a byte order mark and with a semicolon between fields. Dates are Gregorian, in the order of day, month, and year of the system locale, and decimal marks use the system locale. Dates and amounts use ASCII digits. Amounts have the decimal places of their currency, with at least two, and no thousands separator. A field that contains a semicolon, a quotation mark, or a line break is put in quotation marks, and a quotation mark inside it is doubled.

#### Scenario: Purpose with a semicolon

- **WHEN** a transaction has the purpose `Miete; Nebenkosten "Mai"`
- **THEN** the field is written as `"Miete; Nebenkosten ""Mai"""`

#### Scenario: Purpose with several lines

- **WHEN** a purpose has two lines
- **THEN** the field is in quotation marks and a spreadsheet program reads it as one cell

#### Scenario: Arabic dates without direction marks

- **WHEN** the user exports 3 November 2026 with ar_EG formats
- **THEN** Date is "03/11/2026" without the direction marks U+200E, U+200F, and U+061C of the Arabic date format
- **AND** the import of the app reads the exported file back with the same days and amounts, after the user chooses day first, because "03/11/2026" fits both orders

#### Scenario: Currency with three decimal places

- **WHEN** the user exports -12345 minor units in KWD with German formats
- **THEN** Amount is "-12,345"

#### Scenario: Egyptian Arabic formats

- **WHEN** the user exports -8900 minor units in EUR on 3 November 2026 with ar_EG formats
- **THEN** Date and Amount use only ASCII digits, with the local date order and decimal mark

#### Scenario: Gregorian dates in a region with another calendar

- **WHEN** the user exports 3 November 2026 with th_TH formats
- **THEN** Date is "03/11/2026" with ASCII digits and without an era
- **AND** with en_TH formats, which macOS gives this app for English and the region Thailand, Date is "03/11/2026"
- **AND** with ja_JP formats and the Japanese calendar, Date is "2026/11/03"

### Requirement: Spreadsheet formula protection

The app SHALL prefix a text field with an apostrophe when its first character is a tab, a carriage return, or a line feed, or when its first character after leading whitespace is `=`, `+`, `-`, `@`, or one of the full-width signs `＝`, `＋`, `－`, `＠`. The Amount column stays numeric. CSV quoting follows this prefix. A text field that the app imports again from such a file keeps the apostrophe, while dates and amounts never get one and come back unchanged.

#### Scenario: Formula in bank text

- **GIVEN** Name is `=HYPERLINK("http://x.example","Klick")` and Amount is -89,00
- **WHEN** the user exports it
- **THEN** the Name cell starts with an apostrophe and contains the unchanged formula as text
- **AND** Amount is "-89,00" without an apostrophe

#### Scenario: Other formula prefixes

- **WHEN** a text field starts with `+1+1`, `-1+1`, `@SUM(1)`, a tab, a carriage return, or a line feed
- **THEN** its cell starts with an apostrophe

#### Scenario: Full-width formula signs

- **WHEN** a text field starts with `＝HYPERLINK(1)`, `＋1+1`, `－1+1`, or `＠SUM(1)`
- **THEN** its cell starts with an apostrophe

#### Scenario: Formula after leading whitespace

- **WHEN** the Name is " =1+1"
- **THEN** the Name cell is "' =1+1"

#### Scenario: Import of an exported file

- **GIVEN** the export of a transaction on 03.11.2026 with the Name "＝1+1", the Purpose " - Miete", and the Amount -89,00 in de_DE formats
- **WHEN** the user imports that file into an account
- **THEN** the Name is "'＝1+1" and the Purpose is "' - Miete"
- **AND** the booking date is 03.11.2026 and the amount is -89,00 €

### Requirement: Formula protection inside a text field

The app SHALL put an apostrophe after a comma, a tab, a carriage return, or a line feed inside a text field when the text that follows it, up to the next of these characters, has `=`, `+`, `-`, `@`, `＝`, `＋`, `－`, or `＠` as its first character after leading whitespace. A spreadsheet that splits the file at commas, at tabs, or at line breaks then starts no cell with a formula sign. Ordinary text without such a sign stays unchanged, and Copy of rows does not add these apostrophes.

#### Scenario: Formula after a comma

- **WHEN** the Purpose is "Ref,+HYPERLINK(1)"
- **THEN** the Purpose cell is "Ref,'+HYPERLINK(1)"

#### Scenario: Formula after a tab

- **WHEN** the Name is "Ref\t=1+1"
- **THEN** the Name cell is "Ref\t'=1+1"

#### Scenario: Formula after a comma and a space

- **WHEN** the Booking text is "Gutschrift, -1+1"
- **THEN** the Booking text cell is "Gutschrift,' -1+1"

#### Scenario: Ordinary text

- **WHEN** the Purpose is "Abschlag November, Kd-Nr 123"
- **THEN** the Purpose cell is "Abschlag November, Kd-Nr 123"

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

#### Scenario: Private export file

- **WHEN** the user saves a CSV export or replaces an existing CSV file
- **THEN** only the current user can read or write the file

#### Scenario: Unreadable stored holding

- **GIVEN** the first stored holding has an unreadable quantity
- **WHEN** the user exports all data
- **THEN** the app shows "Could not export to file."
- **AND** the message says "The database contains unreadable data: at holdings[0], the stored holding cannot be read."
- **AND** an existing export stays unchanged

#### Scenario: Export survives a restart

- **WHEN** the app finishes a CSV or complete export
- **THEN** it has requested a full drive-cache sync of the file before replacing the destination, with file-system sync as a fallback
- **AND** it attempts to sync the folder after replacing the destination when the folder can be opened for sync

#### Scenario: Write-only folder

- **GIVEN** the destination folder has mode 0300
- **WHEN** the user saves an export
- **THEN** the export succeeds with mode 0600 even if the folder cannot be synced

### Requirement: Progress of an export

The app SHALL show progress for an export that takes longer than a moment, and let the user cancel it. Encoding, writing, and syncing keep the interface responsive. Cancellation before the destination is replaced leaves no new file and preserves an existing destination. CSV export commands stay unavailable until the current export finishes, including cancellation cleanup.

#### Scenario: Large export

- **WHEN** the user exports 200,000 transactions
- **THEN** the app shows "Exporting..." with a cancel button until the file is complete

#### Scenario: Slow storage

- **GIVEN** syncing the temporary file takes 2 seconds
- **WHEN** the user exports transactions
- **THEN** "Exporting..." appears with "Cancel" while syncing continues
- **AND** canceling during sync preserves an existing file and removes the temporary file

#### Scenario: Cancel and retry

- **GIVEN** a CSV export is syncing its temporary file
- **WHEN** the user cancels it
- **THEN** another CSV export cannot start until the canceled writer finishes
- **AND** after cleanup a new export has its own working progress and cancellation

### Requirement: One transaction file operation at a time

The app SHALL keep transaction import and CSV export commands unavailable while either operation runs, including cancellation cleanup.

#### Scenario: Import keeps its progress and cancel control

- **GIVEN** the app is reading a CSV file with 300,000 transactions
- **WHEN** the user attempts a CSV export
- **THEN** no export starts and the import keeps its progress and cancel control
- **AND** the same rule prevents a transaction import while a CSV export runs
- **AND** both commands become available after the operation and its cleanup end

### Requirement: Complete export

The app SHALL offer "Export All Data..." in the File menu. The command writes one JSON file with all accounts, account groups, transactions with their categories, comments, checkmarks, and splits, categories with their rules, balance history, and settings that describe the data. Every capability that stores user data adds its data to this file.

#### Scenario: Database with three accounts

- **GIVEN** a database with 3 accounts, 2 groups, 25 categories with 10 rules, and 12,000 transactions
- **WHEN** the user chooses "Export All Data..." and saves the file
- **THEN** the file contains all of these objects

#### Scenario: Saved CSV profiles

- **GIVEN** the database holds the profiles "Broker CSV" and "Bank CSV"
- **WHEN** the user exports all data and imports the file into an empty database
- **THEN** both profiles keep their settings, stored versions and unknown fields
- **AND** a file without the optional "csvProfiles" key imports with no profiles

#### Scenario: Saved searches

- **GIVEN** the saved search "Tax payments" with the search text "Finanzamt", the period "30 Days", and the amount from -500 to -100
- **WHEN** the user exports all data and imports the file into an empty database
- **THEN** the sidebar section "Searches" shows "Tax payments" with the same search text, period, and amount range
- **AND** a file without the optional "savedSearches" key imports with no saved searches

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

#### Scenario: A changed required key raises the version

- **GIVEN** a version of the app that reads up to format version 2, where the error of a refresh holds the key `message`
- **AND** a newer version of the app that stores the error of a refresh as `failure` without `message`
- **WHEN** the newer version exports an account whose last refresh failed
- **THEN** the file has format version 3
- **AND** the older version refuses the file as needing a newer version of the app, not as damaged

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

The app SHALL refuse "Import All Data..." when the database holds an account, a category that the user created, a transaction, a saved CSV profile, or a saved search, and say that the import works only in an empty database.

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

#### Scenario: Category or account group contains itself

- **WHEN** category 0 has its own identifier as parent, or categories 0 and 1 refer to each other as parents
- **THEN** the app refuses the file as damaged and names category 0
- **AND** the database stays unchanged
- **AND** the same refusal applies to account groups 0 and 1

#### Scenario: Day exceeds the ISO form

- **WHEN** a booking day, value day, or portfolio day is "01-01-9223372036854775807"
- **THEN** the app refuses the file as damaged and names the object
- **AND** the database stays unchanged

#### Scenario: Portfolio value in a foreign currency

- **GIVEN** a portfolio in EUR
- **WHEN** its daily value is "100" in JPY
- **THEN** the app refuses the file as damaged and names the daily value
- **AND** the database stays unchanged

#### Scenario: Invalid currency code

- **WHEN** a currency code is "not a currency", "eur", or "EU1"
- **THEN** the app refuses the file as damaged and names the object
- **AND** a currency code consists of exactly three uppercase ASCII letters

#### Scenario: Nonpositive format version

- **WHEN** the file has format version 0 or -1
- **THEN** the app refuses the file as damaged and names the version
- **AND** the database stays unchanged

### Requirement: Private complete export file

The app SHALL create the complete export with read and write permission for its owner only.

#### Scenario: Export to a shared folder

- **WHEN** the user exports all data to a folder that other local users can read
- **THEN** the file has mode 0600 before it contains financial data
- **AND** replacing an existing file also gives the export mode 0600

### Requirement: Unreadable stored holding

The app SHALL fail a complete export when a stored holding cannot be read, and name its position instead of omitting it.

#### Scenario: Broken quantity

- **GIVEN** holding 0 has the unreadable quantity "broken"
- **WHEN** the user exports all data
- **THEN** the app reports the unreadable holding at position 0 and writes no export

#### Scenario: Decimal precision limit

- **GIVEN** a holding has the quantity "1.123456789012345678901234567890123456789"
- **WHEN** the user imports the complete export
- **THEN** the app refuses the file and names holdings[0] and says that the value cannot be represented without rounding
- **AND** the database stays empty

#### Scenario: Exact decimal values

- **GIVEN** a holding has the quantity "0.12345678901234567890123456789012345678" or "123456789012345678901234567890123456789"
- **WHEN** the user exports all data and imports it into an empty database
- **THEN** the quantity stays unchanged
