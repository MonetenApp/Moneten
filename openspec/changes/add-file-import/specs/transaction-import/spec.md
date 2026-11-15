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

The app SHALL detect the date format of the date columns from all their values, including day first and month first orders, two-digit and four-digit years, and ISO dates. The booking date and the value date share one format. A date with dots always reads day first. The app warns when the file mixes month-first dates with dotted dates. When the values fit more than one order, the app marks the choice in the preview so that the user confirms or changes it.

#### Scenario: Clear European dates

- **WHEN** a column holds "31.10.2026" and "03.11.2026"
- **THEN** the app reads day, month, year

#### Scenario: The other date column decides

- **GIVEN** a CSV file with a booking date column and a value date column
- **WHEN** a row has the booking date "10/30/2026" and the value date "11/01/2026"
- **THEN** the app reads the value date as 1 November 2026

#### Scenario: A value that fits no order decides nothing

- **GIVEN** a CSV file with the booking dates "10/01/2026" and "10/02/2026"
- **WHEN** their value dates are "10/30/2026" and "pending"
- **THEN** the app reads the booking dates as 1 October and 2 October 2026

#### Scenario: A date with dots stays day first

- **GIVEN** a CSV file with the booking dates "01.11.2026" and "02.11.2026"
- **WHEN** their value dates are "11.13.2026" and "03.11.2026"
- **THEN** the app reads the booking dates as 1 November and 2 November 2026, the second value date as 3 November 2026, and warns that the value date in line 2 cannot be read

#### Scenario: Month-first and dotted dates in one file

- **WHEN** a row has the booking date "12/31/2026" and the value date "01.05.2027"
- **THEN** the app reads 31 December 2026 and 1 May 2027
- **AND** the app warns that the file mixes date forms

#### Scenario: Ambiguous dates

- **WHEN** every value of a column is like "03/04/2026" and "05/06/2026"
- **THEN** the preview marks the date format as uncertain and offers day first and month first

### Requirement: CSV amount detection

The app SHALL read amounts with a decimal comma or a decimal point, with or without thousands separators, with a leading or trailing sign, and with a currency symbol or code. The app also reads files with separate columns for debit and credit and files with a column that marks debit or credit. An amount that fits both decimal marks with different values, such as "1,234", takes the decimal mark that the other amounts of the dated rows show.

#### Scenario: Currency in the amount

- **GIVEN** the account "Giro" in euros and a CSV file without a currency column
- **WHEN** a row has the amount "-$12.50"
- **THEN** the app reads a withdrawal of 12.50 US dollars

#### Scenario: German format

- **WHEN** an amount column holds "-1.234,56"
- **THEN** the app reads a withdrawal of 1.234,56 €

#### Scenario: Debit and credit columns

- **GIVEN** the columns "Soll" and "Haben"
- **WHEN** a row has "89,00" under "Soll" and nothing under "Haben"
- **THEN** the app reads a withdrawal of 89,00 €

#### Scenario: Empty amount cells are zero

- **WHEN** a CSV file has the header "Datum;Betrag" and the rows "01.11.2026;-1,00" and "02.11.2026;"
- **THEN** the app reads a withdrawal of 1,00 € and a transaction of 0,00 €

#### Scenario: Empty debit and credit cells are zero

- **WHEN** a CSV file has the header "Datum;Soll;Haben" and the rows "01.11.2026;1,00;" and "02.11.2026;;"
- **THEN** the app reads a withdrawal of 1,00 € and a transaction of 0,00 €

#### Scenario: Debit column alone

- **WHEN** a CSV file has the header "Datum;Soll" and the row "01.11.2026;1,00"
- **THEN** the app reads a withdrawal of 1,00 €

#### Scenario: Credit column alone

- **WHEN** a CSV file has the header "Datum;Haben" and the row "01.11.2026;1,00"
- **THEN** the app reads a deposit of 1,00 €

#### Scenario: Marker column

- **WHEN** a row has the amount "89,00" and "S" in a debit and credit marker column
- **THEN** the app reads a withdrawal of 89,00 €

#### Scenario: Marker column wins over the sign

- **WHEN** a row has the amount "89,00-" and "H" in a debit and credit marker column
- **THEN** the app reads a deposit of 89,00 €

#### Scenario: Amounts out of scope fail the file

- **WHEN** a row has the amount "(12.50)", "($12.50)", or "¥1200"
- **THEN** the app imports nothing and says that the amount in the line of that row cannot be read

#### Scenario: Amount without decimals takes the decimal mark of the file

- **GIVEN** a CSV file with the amount "-4.50" in one dated row
- **WHEN** another dated row has the amount "1,234"
- **THEN** the app reads a deposit of 1.234,00 €

#### Scenario: Row without a date does not decide the decimal mark

- **GIVEN** a CSV file with the amounts "1,234" and "4.50" in dated rows
- **WHEN** a total row without a date has the amount "0,00"
- **THEN** the app reads a deposit of 1.234,00 € and a deposit of 4,50 €

#### Scenario: Amounts with both decimal marks do not decide

- **GIVEN** a CSV file with the amounts "4.50" in line 2 and "-89,00" in line 3
- **WHEN** line 4 has the amount "1,234"
- **THEN** the app imports nothing and says that the amount in line 4 cannot be read

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

### Requirement: CSV data boundary

The app SHALL apply this rule: A keyword header within the first 100 nonblank rows wins; without one, data starts after the nearest title row above the first transaction; dated rows above it are skipped with a warning.

A title row has at least two text labels and no dates or amounts; after a dated preamble it names the date column. A transaction has a numeric date candidate; empty, missing, ambiguous, or invalid amounts stay for validation.

#### Scenario: Numbered labels in a keyword header

- **GIVEN** "01.11.2026;Anfangssaldo;100,00", "Datum;Name;Betrag;1. Verwendungszweck", and "02.11.2026;Kiosk;-2,00;Brot"
- **WHEN** the file is imported
- **THEN** the amount is -200 minor units and line 1 has a skipped-row warning
- **AND** replacing "Name" with "2. Name" gives the same amount and warning

#### Scenario: Opening and closing balances before a header

- **GIVEN** "01.11.2026;Anfangssaldo;100,00", "30.11.2026;Endsaldo;98,00", "Datum;Name;Betrag", and "02.11.2026;Kiosk;-2,00"
- **WHEN** the file is imported
- **THEN** the amounts are [-200] minor units
- **AND** lines 1 and 2 each have a skipped-row warning

#### Scenario: Header words in a transaction

- **GIVEN** "Tag;Wer;Zweck;Wieviel", followed by 101 rows of "01.11.2026;Kiosk;Brot;1.00"
- **WHEN** the next rows are "02.11.2026;Datum;Betrag;2.00" and "03.11.2026;Bakery;Cake;3.00"
- **THEN** mapping the first and fourth columns to date and amount reads 101 amounts of 100, then 200 and 300 minor units

#### Scenario: Spaces before a transaction date

- **GIVEN** "Tag;Wer;Zweck;Wieviel", " 01.11.2026;Datum;Betrag; -1.00", and "02.11.2026;Kiosk;Brot;-2.00"
- **WHEN** the first and fourth columns are mapped to date and amount
- **THEN** the amounts are [-100, -200] minor units and no row is skipped
- **AND** a tab before the first date has the same outcome

#### Scenario: A balance before the column headings

- **GIVEN** "01.11.2026;Anfangssaldo;100,00", "Datum;Name;Betrag", and "02.11.2026;Kiosk;-2,00"
- **WHEN** the file is imported
- **THEN** only the Kiosk transaction is imported, as -200 minor units
- **AND** line 1 has a skipped-row warning

#### Scenario: Account metadata before the column headings

- **GIVEN** "Konto;12345678;Stand;30.11.2026", "Buchungstag;Empfänger;Betrag", and "01.11.2026;Kiosk;-4,20"
- **WHEN** the file is imported
- **THEN** the columns are assigned and the Kiosk transaction is imported as -420 minor units
- **AND** line 1 has a skipped-row warning
- **AND** the same amount and warning hold when the first row is "Kontostand;30.11.2026;1.234,56"

#### Scenario: Titles after a long preamble

- **GIVEN** 150 rows of "Preamble", then "Tag;Wer;Wieviel" and "01.11.2026;Kiosk;1.00"
- **WHEN** the preview opens
- **THEN** its titles are "Tag", "Wer", and "Wieviel"

#### Scenario: A filled subtotal follows a short transaction

- **GIVEN** "Tag;Wer;Wieviel", "01.11.2026;Kiosk", "Zwischensumme;EUR;Saldo;0,00", and "02.11.2026;Bakery;;4.50"
- **WHEN** the user maps the first column to the booking date and the fourth to the amount
- **THEN** both transactions read as [0, 450] minor units
- **AND** the titles are "Tag", "Wer", "Wieviel" and a blank fourth title

#### Scenario: Headerless rows before a note

- **GIVEN** "01.11.2026;Kiosk;", "Hinweis;Export vorläufig;", and "02.11.2026;Bakery;4.50"
- **WHEN** the first and third columns are mapped to date and amount
- **THEN** the amounts are [0, 450] minor units
- **AND** replacing the first empty amount with "abc" fails on line 1 instead of discarding that row
- **AND** a missing first amount cell followed by the fully filled note "Hinweis;Export;vorläufig" still reads as zero, including after blank lines

#### Scenario: Unfamiliar date label after a dated preamble

- **GIVEN** "15.11.2026;Kontoauszug", "Wann;Wer;Wieviel", and "03.11.2026;Kiosk;-4,20"
- **WHEN** the first and third columns are mapped to date and amount
- **THEN** only -420 minor units is imported and line 1 has a skipped-row warning

#### Scenario: Metadata before a dated preamble

- **GIVEN** "Konto;Giro;EUR", "15.11.2026;Umsatzanzeige", "Tag;Wer;Wieviel", and "03.11.2026;Kiosk;-4,20"
- **WHEN** the first and third columns are mapped to date and amount
- **THEN** the titles are "Tag", "Wer", and "Wieviel", and only -420 minor units is imported
- **AND** the skipped dated preamble is reported on line 2
- **AND** replacing the first metadata row with "Hinweis;Export;vorläufig" still imports only -420 and reports the skipped dated preamble on line 2

#### Scenario: Malformed first numeric dates

- **GIVEN** unfamiliar headings or no headings, a first row with "01.11.2026x", "2026-11-", "01/11", "20261101", ".11.2026", or "/11/2026" as its date and -1.50 as its amount, then a valid row of -2.00
- **WHEN** date and amount are mapped
- **THEN** the first row fails date validation and nothing is imported from the file
- **AND** counterparty and purpose values "Datum" and "Betrag" cannot hide that invalid row as a header

#### Scenario: A complete note after a short row

- **GIVEN** "Tag;Wer;Wieviel", "01.11.2026;Kiosk", "Hinweis;Export;vorläufig", and "02.11.2026;Bakery;4.50"
- **WHEN** the first and third columns are mapped to date and amount
- **THEN** the earlier heading stays in use and the amounts are [0, 450] minor units
- **AND** the same holds when the amount is mapped to a fourth column without a title and the note has four filled cells

#### Scenario: Ambiguous first amount before a subtotal

- **GIVEN** "Tag;Wer;Wieviel", "01.11.2026;Kiosk;1,234", "Zwischensumme;;0,00", and "02.11.2026;Bakery;4.50"
- **WHEN** the first and third columns are mapped to date and amount
- **THEN** the amounts are [123400, 450] minor units

#### Scenario: Blank rows do not consume the keyword window

- **GIVEN** 100 blank lines, "Datum;Betrag", and "01.11.2026;-1,00"
- **WHEN** the file is imported
- **THEN** the columns are assigned and the amount is -100 minor units

#### Scenario: Keyword header outside the window

- **GIVEN** 100 nonblank rows of "Preamble", then "Datum;Betrag" and "01.11.2026;-1,00"
- **WHEN** the preview opens
- **THEN** the titles are "Datum" and "Betrag" and the columns need manual assignment

### Requirement: CSV preview

The app SHALL show a preview before it imports a CSV file. The preview shows the first rows as the app reads them, the field that each column is assigned to, the date format, the decimal separator, and the encoding. The user can change each of these, and the preview updates at once.

#### Scenario: Correct a column

- **GIVEN** the preview assigned the column "Text" to no field
- **WHEN** the user assigns "Text" to the purpose
- **THEN** the preview rows show the content of "Text" as the purpose

#### Scenario: Required fields missing

- **WHEN** no column is assigned to the booking date or to the amount
- **THEN** the "Import" button is disabled and the preview says which field is missing

#### Scenario: Reread a confirmed CSV for a target currency

- **GIVEN** "03/04/2026;Kiosk;1,234", with or without the titles "Date;Name;Amount"
- **AND** the user maps the columns, chooses month-day-year and a decimal point, and confirms a preview of 123400 EUR minor units on March 4
- **WHEN** the import reads the file again for a JPY target account
- **THEN** it keeps that date and those column/decimal settings and reads 1234 JPY minor units without requiring a header row

### Requirement: CSV profiles

The app SHALL let the user save the settings of the preview as a named profile. When a later file has the same header row, delimiter and detected date order, the app applies the profile and imports without showing the preview first. The user can still open the preview, and can rename and delete profiles.

#### Scenario: Second file of the same bank

- **GIVEN** the user saved the profile "Broker CSV" for a file with 9 named columns
- **WHEN** the user imports another file with the same header row
- **THEN** the app imports it with "Broker CSV" and names the profile in the result message

#### Scenario: Header changed

- **WHEN** the bank adds a column and the header row no longer matches the profile
- **THEN** the app shows the preview again with the profile as the starting point

#### Scenario: Repeated amount titles move

- **GIVEN** a profile maps the two "Betrag" columns of "Datum;Betrag;Betrag" to debit and credit
- **WHEN** the header becomes "Datum;Extra;Betrag;Betrag" and the row is "01.11.2026;Note;10,00;0,00"
- **THEN** the preview maps debit to column 2 and credit to column 3, counting from zero, and reads -1000 minor units
- **AND** a changed number of repeated titles leaves the file without a suggested profile

#### Scenario: A profile meets a different text encoding

- **GIVEN** a Windows-1252 profile with ASCII titles and mapped date, name, purpose, amount and category columns
- **WHEN** a UTF-8 file with the same titles contains "Bäckerei", "Frühstück", "Büro" and -4,20
- **THEN** quiet import opens the preview, which uses UTF-8 and retains the profile's mappings, date order, decimal mark and category option
- **AND** the preview reads those texts unchanged and the amount as -420 minor units
- **AND** a moved header and a profile picked in the preview preserve the detected encoding in the same way
- **AND** ASCII rows such as "Datum;Name;Betrag" and "02.11.2026;Kiosk;-2,00" still import quietly with that profile, while a requested preview shows UTF-8

#### Scenario: Profile signature differs

- **GIVEN** a month-first profile for "Date;Name;Amount"
- **WHEN** the file is "Date,Name,Amount" with the row "03/11/2026,Kiosk,-4.20"
- **THEN** the preview opens with the detected day-first order and reads 3 November 2026
- **AND** a different detected date order also opens the preview when the delimiter stays the same
- **AND** a legacy profile without a saved delimiter opens the preview before reuse

#### Scenario: Empty titles do not count as repeated titles

- **GIVEN** a profile for "Datum;Name;Betrag;"
- **WHEN** the header changes to "Datum;;Name;Betrag;"
- **THEN** the preview starts from the profile with name at column 2 and amount at column 3

#### Scenario: Profiles belong to the encrypted database

- **GIVEN** a profile whose header includes the made-up IBAN DE02120300000000202051
- **WHEN** it is saved, renamed or deleted
- **THEN** only the open encrypted database changes
- **AND** another database has none of its profiles

#### Scenario: A newer profile is kept by an older reader

- **GIVEN** one saved profile lacks "createsCategories", another has an unknown column field, and a third cannot be decoded
- **WHEN** the profiles are loaded and a readable profile is saved or deleted
- **THEN** the missing category option defaults to off and the unknown column field is ignored
- **AND** the unreadable profile stays stored unchanged
- **AND** a profile with a negative known column position, such as -1, stays stored but is not applied
- **AND** saving or renaming a readable profile preserves unknown fields, including "futureField" with the value 7 and unknown column mappings

#### Scenario: Result describes the confirmed settings

- **WHEN** a preview saves a new profile "Broker CSV" during an import
- **THEN** the result says the file "used the settings saved as profile" "Broker CSV"
- **AND** the same wording applies when an existing profile was changed before import

### Requirement: Categories from a CSV file

The app SHALL assign the category from a category column to each imported transaction when a category with that name or path exists. With the option "Auto-create categories" the app creates the missing categories and reports their number. Without the option, a transaction with an unknown category is treated as one without a category.

#### Scenario: Create missing categories

- **GIVEN** the category "Food" exists and "Pets" does not
- **WHEN** the user imports rows with the categories "Food" and "Pets" with "Auto-create categories" on
- **THEN** the app creates "Pets", assigns both categories, and reports "Created one new category."

#### Scenario: Option off

- **WHEN** the same file is imported with the option off
- **THEN** the "Pets" rows pass the categorization rules like any new transaction

#### Scenario: Category path from a Moneten CSV export

- **GIVEN** the category "Food" is under the group "Living"
- **WHEN** a Moneten CSV export names it "Living - Food" and is imported again
- **THEN** the row receives the existing "Food" category with either setting of "Auto-create categories"
- **AND** if "Pets" is missing, "Living - Pets" with auto-create on creates "Pets" under "Living"
- **AND** an existing category whose literal name is "Living - Food" takes precedence over interpreting that text as a path
- **AND** a group whose literal name is "Living - Food" cannot mask the assignable category at that exported path
- **AND** explicit paths "Long - Term › Pets" and "Long - Term\\Pets" keep "Long - Term" as one group name with either auto-create setting
- **AND** auto-create of the exported path "Long - Term - Pets" reuses the existing "Long - Term" group instead of creating extra groups

#### Scenario: Imported category is restricted to another account

- **GIVEN** "Office" is restricted to "Business" or its "Work" account group
- **WHEN** a row of -420 minor units names "Office" while being imported into "Private"
- **THEN** the row stays without a category and passes the rules
- **AND** importing into "Business" assigns "Office" as set by hand
- **AND** a category that could not be saved leaves the row without that category

#### Scenario: Bounded category creation

- **WHEN** a file names 2,000 or 50,000 distinct missing categories with "Auto-create categories" on
- **THEN** it creates at most 1,000 categories, counting groups
- **AND** existing categories still match after the limit is reached
- **AND** rows beyond the limit pass the rules without a file category
- **AND** the result says "Auto-create categories is limited to 1,000 new categories per file. Remaining unknown categories were left to the rules."
- **AND** a path is created only when all its missing levels fit within the remaining limit

#### Scenario: Bounded paths that cannot be created

- **GIVEN** "Food" is a category and a file names "Food › X0" through "Food › X299999"
- **WHEN** the user imports it with "Auto-create categories" on
- **THEN** the first 1,000 blocked paths use the category creation budget
- **AND** the result lists only "Food › X0" through "Food › X9", then "and 990 more."
- **AND** it reports the 1,000 limit and creates no category

#### Scenario: Skipped rows and failed storage leave no new categories

- **GIVEN** rows whose category cells name new categories
- **WHEN** every row is skipped as already imported
- **THEN** the result reports 0 new categories and no new category remains
- **AND** a failed transaction merge leaves no new category or transaction from that file

#### Scenario: Dash paths and duplicate leaf names

- **WHEN** "Miete - Nebenkosten" is imported with auto-create on and neither category exists
- **THEN** it creates the group "Miete" and its category "Nebenkosten"
- **AND** when "Other" exists under "Work" and "Living", a bare "Other" chooses the case-folded full path that sorts first, "Living › Other", regardless of load order
- **AND** a top-level category "Other" takes precedence over either nested "Other"
- **AND** equal case-folded paths choose the lowest UUID string, with assignable categories before groups

### Requirement: CAMT import

The app SHALL import camt.052 and camt.053 files with the booking date, the value date, the amount, the currency, the counterparty with IBAN and BIC, the purpose, the booking text, the end-to-end reference, the mandate reference, the creditor ID, and the return reason of each entry.

#### Scenario: Statement with three entries

- **WHEN** the user imports a camt.053 file with 3 booked entries
- **THEN** the account has 3 new booked transactions with their references in the details

### Requirement: CAMT entry with several payments

The app SHALL import a CAMT entry that bundles several payments as one transaction with the amount of the entry. When its transaction details name different counterparties, the transaction has no counterparty name, IBAN, or BIC, and no end-to-end reference, mandate reference, or creditor ID. Its purpose joins the purposes of all details.

#### Scenario: Batch entry

- **GIVEN** a camt.053 entry of -150,00 € on 3 November 2026 with two transaction details, -100,00 € to "Hausverwaltung Muster" with the purpose "Miete November" and -50,00 € to "Stadtwerke Musterstadt" with the purpose "Abschlag Strom"
- **WHEN** the user imports the file
- **THEN** the account has one transaction of -150,00 € on 3 November 2026 with the purpose "Miete November Abschlag Strom"
- **AND** the transaction has no counterparty name and no IBAN, so the rule `name:"Stadtwerke"` does not match it

#### Scenario: Batch entry to one counterparty

- **GIVEN** a camt.053 entry of -120,00 € with two transaction details of -60,00 € each to "Stadtwerke Musterstadt" with the IBAN DE02120300000000202051
- **WHEN** the user imports the file
- **THEN** the account has one transaction of -120,00 € to "Stadtwerke Musterstadt" with the IBAN DE02120300000000202051

### Requirement: Status of a CAMT entry

The app SHALL import a CAMT entry with the status PDNG or FUTR as a pending transaction on the booking date of the entry. It SHALL skip an entry with the status INFO, because the bank booked nothing for it. Every other entry is a booked transaction. A later file or refresh books a pending transaction when it brings a booked transaction with the same amount and the same counterparty at most seven days apart.

#### Scenario: Pending entry

- **GIVEN** a camt.052 file for the IBAN DE02120300000000202051 with an entry of -89,00 € to "Stadtwerke Musterstadt" in the status PDNG, the booking date 1 November 2026, and the value date 2 November 2026
- **WHEN** the user imports the file
- **THEN** the account has a pending transaction of -89,00 € to "Stadtwerke Musterstadt" with the booking date 1 November 2026

#### Scenario: Pending entry booked by a later file

- **GIVEN** the account holds the pending transaction of -89,00 € from the camt.052 file of the scenario "Pending entry"
- **WHEN** the user imports a camt.053 file with the same entry of -89,00 € to "Stadtwerke Musterstadt" in the status BOOK on 1 November 2026
- **THEN** the account has one transaction of -89,00 € to "Stadtwerke Musterstadt", and it is booked

#### Scenario: Future entry

- **WHEN** a camt.052 file holds an entry of 1.250,00 € in the status FUTR with the booking date 30 November 2026
- **THEN** the app imports a pending transaction of 1.250,00 € with the booking date 30 November 2026

#### Scenario: Entry for information

- **GIVEN** a camt.052 file with a booked entry of -89,00 € and an entry of -20,00 € in the status INFO
- **WHEN** the user imports the file
- **THEN** the account has one new transaction, the one of -89,00 €

### Requirement: Future pending transactions from a file

The app SHALL keep a pending transaction from a file that no refresh has delivered while its booking date is today or later and no free delivered pending transaction pairs with it. Each delivered transaction takes one unpaired file transaction at most. A file transaction that only an already paired delivered transaction fits stays. After its booking date, a refresh that does not deliver it removes it.

#### Scenario: Scheduled rent before its date

- **GIVEN** on 15 November 2026 the user imported a camt.052 file with an entry of -800,00 € to "Vermieter A" in the status FUTR with the booking date 1 December 2026
- **WHEN** a successful refresh on 20 November 2026 does not deliver the entry
- **THEN** the account still has the pending transaction of -800,00 € to "Vermieter A" on 1 December 2026

#### Scenario: Scheduled rent after its date

- **GIVEN** the pending transaction of -800,00 € to "Vermieter A" on 1 December 2026 from the scenario "Scheduled rent before its date"
- **WHEN** a successful refresh on 5 December 2026 delivers neither the pending entry nor a booked one for it
- **THEN** the pending transaction is gone from the list

#### Scenario: One delivered rent row for two file rows

- **GIVEN** one file imported two pending transactions of -800,00 € to "Vermieter A", each with the IBAN DE02120300000000202051, the purpose "Miete Dezember", and the booking date 1 December 2026
- **WHEN** a successful refresh on 20 November 2026 delivers one pending transaction of -800,00 € to "Vermieter A" with the same IBAN, the purpose "MIETE DEZEMBER WHG 3 DAUERAUFTRAG", and the booking date 1 December 2026
- **THEN** one file transaction takes the bank's fields and counts as fetched
- **AND** the other stays pending and unfetched with the purpose "Miete Dezember"
- **AND** no transaction is removed

#### Scenario: Repeated refresh keeps the unpaired rent

- **GIVEN** the two file transactions from "One delivered rent row for two file rows" after one has taken the bank's fields
- **WHEN** the same refresh runs again on 21 November 2026
- **THEN** both transactions stay, totaling -1.600,00 €
- **AND** the unpaired file transaction keeps its fields and stays unfetched

#### Scenario: A later file does not make a payment fetched

- **GIVEN** a pending file transaction of -800,00 € to "Vermieter A" on 1 December 2026 with the purpose "Miete Dezember"
- **WHEN** a later file delivers the payment on the same day with the purpose "Miete Dezember Wohnung 3"
- **THEN** the file transaction is skipped, and one pending unfetched transaction stays
- **AND** a refresh on 20 November 2026 that delivers neither version keeps it

#### Scenario: Separate dates remain separate payments

- **GIVEN** a camt.052 file imported FUTR entries of -800,00 € to "Vermieter A" in the order 8 December, then 1 December 2026
- **WHEN** a refresh on 20 November 2026 delivers only the pending payment of 1 December with another purpose
- **THEN** both transactions stay, and only the transaction of 1 December counts as fetched
- **AND** the 8 December transaction keeps its date and fields
- **AND** the same holds for file transactions on 1 and 3 December 2026 in either stored order

### Requirement: The bank's version of a future pending transaction from a file

The app SHALL pair each free delivered pending transaction with at most one free future file transaction with the same amount and counterparty, at most seven days apart. The shared pending pairing rule chooses the partner. The file transaction keeps its identity and user fields and takes the bank's fields.

#### Scenario: The bank reports the scheduled rent as pending

- **GIVEN** on 15 November 2026 the user imported a camt.052 file with an entry of -800,00 € to "Vermieter A" with the IBAN DE02120300000000202051 and the purpose "Miete Dezember", in the status FUTR with the booking date 1 December 2026
- **WHEN** a successful refresh on 20 November 2026 delivers a pending transaction of -800,00 € to "Vermieter A" with the IBAN DE02120300000000202051, the purpose "MIETE DEZEMBER WHG 3 DAUERAUFTRAG", and the booking date 1 December 2026
- **THEN** the account has one pending transaction of -800,00 €, with the purpose "MIETE DEZEMBER WHG 3 DAUERAUFTRAG"

### Requirement: Pending file transactions already stored

The app SHALL skip a pending file transaction when one free stored pending row fits PendingMatch within seven days. Conflicting explicit identities never pair. The closest day wins; tied candidates use stable delivered booking day, creation time and UUID, then stored position. Each stored row absorbs one file row. Stored bank fields and fetched status stay. A relaxed file match fills empty user fields; identified repeats preserve cleared fields.

#### Scenario: The bank pending rent is one day earlier

- **GIVEN** a fetched pending row of -800,00 € to "Vermieter A" stored on 30 November 2026
- **WHEN** a camt.052 imports the same pending rent on 1 December
- **THEN** the file row is skipped and the stored 30 November row stays
- **AND** the planned balance counts -800,00 € once

#### Scenario: A weekly file uses a stored bank row once

- **GIVEN** one fetched pending rent of -800,00 € to "Vermieter A" on 1 December 2026
- **WHEN** a file brings the rents on 1 and 8 December
- **THEN** 1 December is skipped and 8 December is imported, totaling -1.600,00 €
- **AND** the result is the same in either delivery order

#### Scenario: Equidistant imported rents use stable booking-day order

- **GIVEN** one fetched pending rent of -800,00 € to "Vermieter A" on 1 December 2026
- **WHEN** a file brings pending rents on 30 November and 2 December, each one day away
- **THEN** the stable delivered booking-day key pairs 30 November first, so that row is skipped and 2 December is imported
- **AND** the stored bank row stays on 1 December and the total is -1.600,00 €, in every delivery and storage order

#### Scenario: The bank reported the scheduled rent before the import

- **GIVEN** a refresh on 18 November 2026 stored a pending transaction of -800,00 € to "Vermieter A" with the IBAN DE02120300000000202051, the purpose "MIETE DEZEMBER WHG 3 DAUERAUFTRAG", and the booking date 1 December 2026
- **WHEN** on 19 November 2026 the user imports a camt.052 FUTR entry of -800,00 € to "Vermieter A" with the same IBAN and booking day and the purpose "Miete Dezember"
- **THEN** the file entry is skipped, and the account has one pending transaction totaling -800,00 €
- **AND** a refresh on 20 November 2026 that delivers the bank transaction again keeps that one transaction

#### Scenario: A daily file repeats a payment after the bank takeover

- **GIVEN** the bank took over the FUTR transaction from "The bank reports the scheduled rent as pending" on 20 November 2026
- **WHEN** a daily camt.052 file on 21 November 2026 delivers that FUTR entry again with the purpose "Miete Dezember"
- **THEN** the file entry is skipped, and the account has one pending transaction totaling -800,00 €
- **AND** the next refresh keeps that one transaction

#### Scenario: Two file rows pair with one stored bank row

- **GIVEN** a fetched pending transaction of -800,00 € to "Vermieter A" on 1 December 2026 with the purpose "MIETE DEZEMBER WHG 3 DAUERAUFTRAG"
- **WHEN** a file delivers two pending transactions of -800,00 € to "Vermieter A" on 1 December 2026 with the purpose "Miete Dezember"
- **THEN** one file transaction is skipped and one is added, totaling -1.600,00 €
- **AND** two refreshes that each deliver the bank transaction keep both rows

#### Scenario: Keep the file transaction's user fields

- **GIVEN** the file transaction from "The bank reported the scheduled rent before the import" has the comment "Shared rent", the category "Housing" assigned by hand, and a checkmark
- **WHEN** the import skips that transaction in favor of the stored pending transaction
- **THEN** the stored transaction takes the comment when its own comment is empty, the category when it is uncategorized, and the checkmark when it is unchecked
- **AND** an existing comment "Bank note", category "Bills", or checkmark stays

### Requirement: Order-independent pending pairing

The app SHALL pair pending or stored-file-identified rows one to one in this order:

1. Original file identity or source ID.
2. Exact, then compatible booked fingerprint, including pending repeats.
3. Delivered pending row's end-to-end reference with equal amount and currency.
4. Fitting fetched pending or honored deleted row within seven days.
5. Nearest fitting unfetched pending file row within seven days.

Booked rows without file identity keep the existing booked-only rule.

#### Scenario: Candidate eligibility and ties

- **GIVEN** free delivered and stored candidates at the same level
- **WHEN** the app chooses a pair
- **THEN** current versions precede pending repeats of booked versions.
- **AND** identity matches prefer live rows to tombstones. Fingerprints rank exact, compatible, then absent. Remaining ties use day distance, stable delivered position, then stable stored position. Live positions use booking day, creation time, and UUID. Tombstone positions use persisted identity fields, optional-value presence, fetched flag, and deletion time as a tuple. Candidates are consumed greedily only when both sides are free.

- **AND** different real source IDs or nonempty end-to-end references never pair. Agreeing source IDs retain bank corrections and their existing date behavior. Different pending file fingerprints still stay separate.
- **AND** a pending-to-booked transition within seven days ignores different file fingerprints when amount and currency agree and either the reference agrees or the counterparty fits. A booked repeat can use its current fingerprint even when it differs from the retained original file fingerprint.
- **AND** pending fallback checks known counterparties by IBAN, otherwise by name. A file import bounds pending-to-pending pairs to seven days and uses nearest-day choice across fetched and unfetched rows outside the same-day fetched level.
- **AND** a refresh ranks fetched pending rows within seven days before unfetched rows. Unfetched refresh candidates must have a covered date today or later and no review mark.
- **AND** reference-only fallback excludes migration deliveries. Only a pending file delivery can find a historical booked version by reference alone. Booked fingerprint matches compare IBANs, not name order.
- **AND** a pending tombstone cannot block a booking. A source arriving booked reserves its pending tombstone against unrelated look-alikes.

- **AND** booking first prefers agreeing identities, then a unique fetched pending row. With no fetched partner, only nearest fitting file rows on or before the booked day participate, and an unresolved tie marks those rows and the delivery for review.

#### Scenario: Global nearest choice

- **GIVEN** file rents of -800,00 € to "Vermieter A" on 1 and 8 December 2026
- **WHEN** a refresh on 20 November delivers pending rents on 7 and 15 December in either order
- **THEN** the 8 December row takes the 7 December bank fields, the 1 December row stays unfetched, and 15 December is added
- **AND** three rows total -2.400,00 € in either stored order
- **AND** for file days 1 and 5 and bank days 4 and 10, day 4 takes day 5 and three rows remain

#### Scenario: Explicit identities disagree

- **GIVEN** a pending rent of -800,00 € on 1 December 2026 with end-to-end reference "RENT-A"
- **WHEN** a file imports an otherwise equal rent with reference "RENT-B"
- **THEN** both rows stay and total -1.600,00 €
- **AND** the same protection applies to a refresh and to different source IDs

#### Scenario: File identity survives a takeover and deletion

- **GIVEN** a FUTR rent of -800,00 € on 1 December 2026 with reference "RENT-A"
- **AND** a refresh takes it over with another purpose and no reference
- **WHEN** the user deletes it and the original file arrives again
- **THEN** the honored deleted row absorbs the file entry and no rent is added
- **AND** if the bank first books the rent, the reference stays and the original pending file entry is skipped without undoing the booking

#### Scenario: A changed bank purpose keeps its partner

- **GIVEN** file rents of -800,00 € on 1 and 8 December 2026 and the bank has taken over 1 December
- **WHEN** the bank delivers 1 December with a new purpose on 21 November
- **THEN** the fetched row takes the new purpose and 8 December stays unfetched
- **AND** the account still has two rows totaling -1.600,00 € in every input order

#### Scenario: Booking prefers the fetched pending row

- **GIVEN** file rents of -800,00 € on 1 and 8 December 2026 and the bank has taken over 1 December
- **WHEN** the booked rent arrives on 2 December
- **THEN** only the fetched row becomes booked and 8 December stays pending
- **AND** neither row is marked for review, in every input order

#### Scenario: An exact repeat preserves a cleared comment

- **GIVEN** an imported pending rent of -800,00 € on 1 December 2026 whose file comment was "Shared rent"
- **AND** the user clears the comment
- **WHEN** the exact same entry is imported again
- **THEN** the comment stays empty

#### Scenario: A bank-first import retains the file reference

- **GIVEN** a pending bank rent of -800,00 € on 1 December 2026 with purpose "BANK" and no reference
- **WHEN** the file rent with reference "RENT-A" is skipped on the same day
- **THEN** the stored row retains "RENT-A", also after booking and deletion
- **AND** a second file rent with reference "RENT-B" stays separate

#### Scenario: An identified booked repeat has another date

- **GIVEN** a pending file rent of -800,00 € on 1 December 2026 with reference "RENT-A" that the bank books on 2 December
- **WHEN** the original pending file rent arrives again
- **THEN** the agreeing identity finds the booked row and the payment counts once, still booked
- **AND** its booked tombstone also absorbs the original file
- **AND** the identity still finds the booked row if successive bank dates move it from 1 to 8 to 15 December
- **AND** pending-to-pending file pairs more than seven days apart still stay separate

#### Scenario: A booked payment does not absorb a different pending payment

- **GIVEN** a booked bank payment of -800,00 € on 1 December 2026 with purpose "BANK"
- **WHEN** a file delivers a pending rent on that day with purpose "Miete Dezember" and no agreeing identity
- **THEN** the new pending rent is added
- **AND** the same holds when the booked payment is a tombstone

#### Scenario: An agreeing identity preserves cleared user fields

- **GIVEN** a pending bank rent with reference "RENT-A", purpose "BANK", and cleared comment, category and checkmark
- **WHEN** the file repeats "RENT-A" with purpose "Miete Dezember", comment "Shared rent", category "Housing" and a checkmark
- **THEN** the stored comment, category and checkmark stay cleared

#### Scenario: Exact fingerprints keep their partners

- **GIVEN** two pending rents of -800,00 € to "Vermieter A" on 1 December 2026 with the same purpose but IBANs DE02120300000000202051 and DE89370400440532013000
- **WHEN** one delivered rent omits its IBAN and another retains the first IBAN
- **THEN** the exact fingerprint pairs first and the IBAN-less rent pairs with the other stored row
- **AND** both stored IDs and IBANs remain, with no added or dropped payment in any delivery or storage order
- **AND** this holds for fetched rows, file rows, file imports and refreshes

#### Scenario: A pending tombstone does not consume a booked correction

- **GIVEN** a deleted pending rent of -800,00 € on 1 December 2026 and a live booked rent on 2 December with source ID "BANK-X"
- **WHEN** the bank corrects the booked rent to 1 December
- **THEN** the live row is updated and one booked payment of -800,00 € remains
- **AND** a live source-ID partner also wins over a booked tombstone with that source ID
- **AND** an accompanying pending echo uses the tombstone without consuming the live booked correction

#### Scenario: A source ID wins before a shared reference

- **GIVEN** two fetched pending rents of -800,00 € on 1 December 2026 with source IDs "BANK-A" and "BANK-B" and reference "RECURRING-RENT"
- **WHEN** one delivered rent omits its source ID and the other retains "BANK-A"
- **THEN** the source-ID match pairs first and the other rent pairs with "BANK-B"
- **AND** both original rows remain in every input order

#### Scenario: A shared reference keeps counterparties and user fields separate

- **GIVEN** two pending rents of -800,00 € on 1 December 2026 with reference "RECURRING-RENT" but different known IBANs and comments "USER-A" and "USER-B"
- **WHEN** both rents arrive in either order
- **THEN** each stored row retains its own IBAN and comment
- **AND** exact fingerprints still win when both IBANs are absent but the purposes differ
- **AND** different known names keep their own comments when both purposes change

#### Scenario: A booked fingerprint stays available for its booked repeat

- **GIVEN** one pending and one booked rent of -800,00 € on 1 December 2026, with reference "RECURRING-RENT" only on the booked row
- **WHEN** a file delivers both forms with that reference
- **THEN** the exact booked fingerprint pairs first and the pending form uses the pending row
- **AND** one pending and one booked row remain

### Requirement: MT940 import

The app SHALL import MT940 files, with the usual extension `.sta`, including the structured purpose fields of German banks for the counterparty name, the account, the bank code, the booking text, and the SEPA references.

#### Scenario: Structured purpose

- **WHEN** an MT940 entry carries the end-to-end reference "E2E-1" and the mandate reference "M-0001" in its purpose fields
- **THEN** the imported transaction shows both references in its details and not inside the purpose text

### Requirement: MT940 dates

The app SHALL read a two-digit year in an MT940 file as a year from 2000 to 2099. The booking date of an MT940 line has a month and a day only, so the app takes its year from the value date. The year is one less when the booking month is more than six months after the value month, and one more when the value month is more than six months after the booking month.

#### Scenario: Booking in the year before

- **WHEN** an MT940 line has the value date 260102 and the booking date 1231
- **THEN** the app imports the transaction with the value date 2 January 2026 and the booking date 31 December 2025

#### Scenario: Booking in the year after

- **WHEN** an MT940 line has the value date 251120 and the booking date 0310
- **THEN** the app imports the transaction with the value date 20 November 2025 and the booking date 10 March 2026

#### Scenario: Same year

- **WHEN** an MT940 line has the value date 260630 and the booking date 0102
- **THEN** the app imports the transaction with the booking date 2 January 2026

#### Scenario: Two-digit year above 79

- **WHEN** an MT940 line has the value date 800101
- **THEN** the app imports the transaction with the value date 1 January 2080

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

#### Scenario: Equal numbers at different banks

- **GIVEN** the selected account has BIC AAAADEFFXXX and number 202051, and another account has BIC BBBBDEFFXXX and number 202051
- **WHEN** field 25 names BBBBDEFFXXX/202051
- **THEN** the app asks before importing into the other account
- **AND** a file with both AAAADEFFXXX/202051 and BBBBDEFFXXX/202051 is refused as statements of several accounts

#### Scenario: Repeated account identifiers

- **WHEN** field 25 repeats 12030000/0000202051 as 12030000/202051, or adds an unreadable EUR line to a valid account
- **THEN** the app treats the file as one account
- **AND** a CAMT file that repeats DE02120300000000202051 with spaces names one account too
- **AND** each file needs at most one account question, and later files of the same account and declared currency reuse the answer

#### Scenario: An open account replaces a closed match

- **GIVEN** "Old closed" and "New open" have IBAN DE02120300000000202051, and "Savings" is selected
- **WHEN** the file names that IBAN in the currency of both accounts
- **THEN** the question offers "New open"
- **AND** a match in the currency of the file still outranks an open match in another currency

#### Scenario: Statements of several accounts

- **WHEN** a camt.053 file holds a statement for "Giro" and one for "Savings"
- **THEN** the app imports nothing from the file and says that it holds the statements of several accounts

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

#### Scenario: Dismissal resumes the import that was presented

- **GIVEN** an import sheet was presented for a running import
- **WHEN** the sheet reports its dismissal
- **THEN** the callback resumes that presented run, even if the model no longer refers to it
- **AND** a later import can start after the user closes the result

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

#### Scenario: A dated row before inferred CSV titles

- **GIVEN** a CSV file without known header keywords has "15.11.2026;Umsatzanzeige" before the titles "Tag;Wer;Wieviel" and a transaction of -4,20 €
- **WHEN** the user assigns the booking date and amount columns and imports the file
- **THEN** the app imports -4,20 € and warns that the dated row in line 1 was skipped before the inferred titles

#### Scenario: Unreadable value date

- **WHEN** one row has "n/a" as the value date and a valid booking date
- **THEN** the app imports the row without a value date and lists a warning for that line

#### Scenario: Unknown currency code

- **GIVEN** the account "Giro" in euros
- **WHEN** line 2 of `umsaetze.csv` has "XYZ" in the currency column
- **THEN** the app imports the row in EUR
- **AND** the result lists a warning for `umsaetze.csv`, line 2, that names "XYZ" and EUR

#### Scenario: A file that adds no transaction

- **GIVEN** `umsaetze.csv` was imported once, with a warning for line 2
- **WHEN** the user imports `umsaetze.csv` again and every row is skipped
- **THEN** the result lists no warning for `umsaetze.csv`

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

The app SHALL show progress while it imports and let the user cancel. Cancellation during reading or storing leaves no transaction or new category of the current file. Files stored before cancellation stay. The app stops the following files and reports "Import canceled. N files were imported before.", with N replaced by the number of files stored.

#### Scenario: Cancel a large file

- **WHEN** the user cancels while the app reads the third of five files
- **THEN** the transactions of the first two files stay, and nothing of the third file is stored

#### Scenario: Cancel during category storage

- **GIVEN** the first file was imported and the second file has 2,000 transactions with 1,000 new categories
- **WHEN** the user cancels during category work for the second file
- **THEN** none of its transactions or new categories remain
- **AND** the third file is not stored
- **AND** the result starts with "Import canceled. 1 files were imported before."

#### Scenario: Cancel reading, then cancel storing

- **GIVEN** the first two files were read and the third file is still being read
- **WHEN** the user cancels reading and then cancels while the first file is stored
- **THEN** no transaction or new category of the first file remains
- **AND** the second file is not stored
- **AND** the result starts with "Import canceled. 0 files were imported before."

### Requirement: Persist the original file identity

The app SHALL create an original file identity only on file import and preserve it through takeover, booking, deletion, and complete export/import. Agreeing file identities find booked versions on another day. Different fingerprints follow the pending pairing rule's transition and repeat exceptions. Migration v18 adds nullable fileIdentity columns to transactions and tombstones. Existing NULL identities keep prior behavior.

#### Scenario: An unidentified file survives booking and deletion

- **GIVEN** a FUTR rent of -800,00 € on 1 December 2026 without a source ID or end-to-end reference
- **AND** the bank takes it over with purpose "BANK" and books it on 2 December
- **WHEN** the original file is imported again
- **THEN** its original file identity finds the booked rent and no row is added
- **AND** after deletion its honored tombstone skips that same file
- **AND** an unrelated bank payment with the same bank fields and NULL file identity does not absorb the file

#### Scenario: Different file fingerprints are different identities

- **GIVEN** an imported pending rent of -800,00 € on 1 December 2026 with purpose "Rent A"
- **WHEN** a file imports another rent on that day with purpose "Rent B"
- **THEN** their file identities differ and both rows stay, totaling -1.600,00 €
- **AND** matching source IDs or end-to-end references do not override this disagreement

#### Scenario: Open an existing v17 database

- **GIVEN** a v17 database with a transaction and a tombstone
- **WHEN** the database opens with v18
- **THEN** both rows retain their fields and have NULL fileIdentity
- **AND** a later reopen retains file identities that file imports have stored

#### Scenario: Fingerprint fields stay independent of user edits

- **GIVEN** an imported row with booking day, amount, currency, purpose, counterparty, source ID, and end-to-end reference
- **THEN** its versioned length-prefixed fingerprint includes those original fields, with folded purpose and normalized counterparty
- **WHEN** its pending state, local UUID, creation time, comment, checkmark, or category changes
- **THEN** its original file identity stays unchanged
- **AND** a refresh or migration cannot create a file identity

#### Scenario: Known names conflict despite an exact fingerprint

- **GIVEN** an unfetched pending rent of -800,00 € on 1 December 2026 to "Vermieter A", with purpose "RENT", reference "SHARED", and no IBAN
- **WHEN** a file or refresh delivers the same day, amount, purpose and reference for "Vermieter B", also without an IBAN
- **THEN** their known names conflict and the exact fingerprint cannot pair them
- **AND** both rows remain, totaling -1.600,00 €

#### Scenario: The fingerprint also checks the currency

- **GIVEN** a pending or booked payment of -800,00 USD on 1 December 2026
- **WHEN** a file or refresh delivers a pending payment of -800,00 EUR with the same day, purpose, and counterparty but no agreeing explicit identity
- **THEN** the currency mismatch prevents pairing, including exact fingerprint fallback
- **AND** both currency amounts remain separate

#### Scenario: A missing reference does not give away a current booked partner

- **GIVEN** fetched pending "PENDING" with comment "USER-A" and fetched booked "BOOKED" with comment "USER-B" and reference "SHARED", each -800,00 € on 1 December 2026
- **WHEN** a file delivers pending "CHANGED" with "SHARED" and the booked "BOOKED" repeat without its reference
- **THEN** the compatible current booked fingerprint pairs before the historical pending-to-booked reference lookup
- **AND** the other pending row remains pending, both comments stay, and two rows total -1.600,00 € in every input order

#### Scenario: No reference does not excuse a known name conflict

- **GIVEN** pending "RENT" of -800,00 € on 1 December 2026 for "Vermieter A", without an IBAN or end-to-end reference
- **WHEN** a file or refresh delivers the same fields for "Vermieter B"
- **THEN** their known counterparty conflict invalidates every weaker fingerprint and both rows stay
- **AND** unknown counterparties keep the existing fingerprint behavior

#### Scenario: A file booking changes its date or purpose

- **GIVEN** a CAMT PDNG rent of -800,00 € to "Vermieter A" on 1 December 2026 with reference "RENT-A"
- **WHEN** a CAMT BOOK rent arrives on 2 December with that reference, also with a changed purpose
- **THEN** one booked row remains and totals -800,00 €
- **AND** the original pending file and booked file are skipped on re-import and after deletion of the fetched booked row
- **AND** the same transition works without a reference when payee and amount fit within seven days
- **AND** conflicting explicit references or source IDs still keep payments separate

#### Scenario: A booked name changes its order

- **GIVEN** a booked payment of -49,99 € on 10 November 2026 named "MUSTERMANN, MAX", purpose "Kartenzahlung 1234", with no IBAN or file identity
- **WHEN** a file or refresh delivers that payment named "Max Mustermann"
- **THEN** the delivery is skipped as under the existing booked rule

#### Scenario: The bank moves its pending rent by one day

- **GIVEN** file rents of -800,00 € on 1 and 8 December 2026 and the bank has taken over 1 December
- **WHEN** the next refresh delivers the pending rent on 2 December
- **THEN** the fetched row moves to 2 December and the 8 December file row stays
- **AND** two rents total -1.600,00 € in every delivery and storage order

#### Scenario: A booking leaves later file rents alone

- **GIVEN** FUTR file rents of -800,00 € on 7 and 14 December 2026
- **WHEN** only the booked 7 December rent arrives
- **THEN** the 7 December row becomes booked and the 14 December row stays pending without a review mark
- **AND** two indistinguishable 7 December file rows cause only those two and the booked delivery to need review

#### Scenario: A bank pending echo does not undo a booking

- **GIVEN** a fetched booked rent of -800,00 € on 2 December 2026 with reference "RENT-A" and purpose "BOOKED RENT"
- **WHEN** a refresh delivers pending rent on 1 December with that reference and purpose "PENDING RENT"
- **THEN** the booked row stays booked with its date and purpose
- **AND** the pending delivery follows the existing add rule because a reference-only refresh cannot take a booked partner
- **AND** a file repeat with that reference is skipped without changing the booking, while a migration follows the existing add rule

#### Scenario: An imported booked name changes its order

- **GIVEN** a booked file payment of -49,99 € on 10 November 2026 named "MUSTERMANN, MAX", purpose "Kartenzahlung 1234", without an IBAN
- **WHEN** a file or refresh delivers that booked payment named "Max Mustermann"
- **THEN** the current booked fingerprint skips the repeat and one payment remains
