# Spec Delta

## Purpose

Printing puts the content of a view on paper or into a PDF. This capability defines the print commands of all views, the options for printed transaction lists, and the layout of the pages.

## ADDED Requirements

### Requirement: Page setup

The app SHALL open the page setup of macOS with "Page Setup…" in the File menu or the shortcut ⇧⌘P. The chosen paper size, orientation, and scale apply to all later printouts of the app.

#### Scenario: Landscape

- **WHEN** the user chooses "Page Setup…", selects landscape, and confirms
- **THEN** the next printout of a transaction list is in landscape

### Requirement: One print command per view

The app SHALL offer one print command with the shortcut ⌘P in the Account menu and in the context menu. The command takes its name from the view and the selection, and it is disabled when the view has nothing to print.

#### Scenario: Account view

- **WHEN** the user selects an account with transactions
- **THEN** the command reads "Print Transactions..."

#### Scenario: One selected row

- **GIVEN** one selected transaction
- **WHEN** the user opens the context menu of that row
- **THEN** the command reads "Print Transaction..."

#### Scenario: Empty view

- **WHEN** the user selects "Outbox" with no drafts
- **THEN** "Print Outbox..." is disabled

### Requirement: Standard print dialog

The app SHALL print through the print dialog of macOS with its preview, its printer choice, and its functions to save or send a PDF.

#### Scenario: Save as PDF

- **WHEN** the user chooses "Print Transactions..." and then the function to save as PDF in the dialog
- **THEN** macOS writes a PDF file with the same pages as the preview

### Requirement: A printed list shows what the view shows

The app SHALL print the rows that the view lists at that moment, with the search text and all filters applied.

#### Scenario: Filtered list

- **GIVEN** the account "Giro" with the period October 2026 and the search text "Stadtwerke" showing 2 transactions
- **WHEN** the user prints
- **THEN** the printout contains these 2 transactions and no others

### Requirement: A selection prints alone

The app SHALL print only the selected rows when more than one row is selected, and it SHALL say in the header that the printout is a selection.

#### Scenario: Five selected rows

- **GIVEN** a list of 200 transactions with 5 selected
- **WHEN** the user presses ⌘P
- **THEN** the printout contains the 5 selected transactions

### Requirement: Columns of a printed transaction list

The app SHALL print each transaction with its booking date, its counterparty, its purpose, and its amount with the currency. A view with several accounts also prints the account of each transaction.

#### Scenario: Group view

- **GIVEN** the account group "Private" with the accounts "Giro" and "Savings"
- **WHEN** the user prints its transactions
- **THEN** each printed row names its account

### Requirement: Option to print category names

The app SHALL print the category of each transaction when "Print category names" is on in the print dialog.

#### Scenario: Categories on

- **WHEN** the user turns on "Print category names" and prints
- **THEN** each row shows its category, for example "Groceries"

#### Scenario: Categories off

- **WHEN** "Print category names" is off
- **THEN** no row shows a category

### Requirement: Option to print comments

The app SHALL print the comment of each transaction below its purpose when "Print comments" is on.

#### Scenario: Transaction with a comment

- **GIVEN** a transaction with the comment "Warranty until 2028"
- **WHEN** the user prints with "Print comments" turned on
- **THEN** the row shows "Warranty until 2028"

### Requirement: Option to print only the first purpose line

The app SHALL print only the first line of each purpose when "Print first purpose line only" is on. Otherwise the app prints every line of the purpose.

#### Scenario: Paper-saving printout

- **GIVEN** a transaction with a purpose of four lines
- **WHEN** the user prints with "Print first purpose line only" turned on
- **THEN** the row shows the first line of the purpose

#### Scenario: Full purpose

- **WHEN** the option is off
- **THEN** the row shows all four lines

### Requirement: Print order

The app SHALL print the list with the newest transaction first for "Print newest transactions first" and with the oldest transaction first for "Print oldest transactions first".

#### Scenario: Oldest first

- **GIVEN** transactions from 01.10.2026 to 31.10.2026
- **WHEN** the user chooses "Print oldest transactions first"
- **THEN** the first printed row is from 01.10.2026

### Requirement: Option to print the current balance

The app SHALL print the current balance of the account with its date at the end of the list when "Print current balance" is on. The option is available for the view of a single account.

#### Scenario: Balance line

- **GIVEN** the account "Giro" with a balance of 1.200,00 € reported on 09.11.2026
- **WHEN** the user prints with "Print current balance" turned on
- **THEN** the printout ends with the account balance of 1.200,00 € at 09.11.2026

### Requirement: Option to print the daily balance

The app SHALL print the computed balance at the end of each day between the rows when "Print daily balance" is on. The option is available for the view of a single account.

#### Scenario: Daily balances

- **GIVEN** the account "Giro" with transactions on 02.11.2026 and 03.11.2026
- **WHEN** the user prints with "Print daily balance" turned on
- **THEN** the printout shows one balance line for 02.11.2026 and one for 03.11.2026

### Requirement: Option to print the sums of deposits and withdrawals

The app SHALL print the sum of all deposits and the sum of all withdrawals of the printed rows at the end of the list when "Print sum of deposits/withdrawals" is on. Each currency has its own sums.

#### Scenario: Sums

- **GIVEN** printed rows with deposits of 3.000,00 € and withdrawals of -2.150,00 €
- **WHEN** the option is on
- **THEN** the printout ends with "Sum of deposits" 3.000,00 € and "Sum of withdrawals" -2.150,00 €

### Requirement: Print options are part of the preview and are remembered

The app SHALL update the preview in the print dialog when the user changes a print option, and it SHALL start the next print dialog with the options of the last printout.

#### Scenario: Toggle an option

- **WHEN** the user turns on "Print comments" in the print dialog
- **THEN** the preview shows the comments at once

#### Scenario: Next printout

- **GIVEN** the user printed with "Print oldest transactions first"
- **WHEN** the user opens the print dialog again
- **THEN** "Print oldest transactions first" is chosen

### Requirement: Header and page numbers

The app SHALL print a header on each list printout with the name of the account, account group, or category, the period of the printed rows, and the search text when a search is active. Each page has a page number in the form "Page 1 of 3".

#### Scenario: Three pages

- **GIVEN** the account "Giro" and the period 01.10.2026 to 31.10.2026 with rows for three pages
- **WHEN** the user prints
- **THEN** each page names "Giro" and the period 01.10.2026 to 31.10.2026
- **AND** the pages are numbered "Page 1 of 3", "Page 2 of 3", and "Page 3 of 3"

### Requirement: Rows stay whole across pages

The app SHALL print every row of a list exactly once and SHALL move a row that does not fit at the end of a page to the next page as a whole.

#### Scenario: Row at a page break

- **GIVEN** a list whose 40th row would cross the end of the first page
- **WHEN** the user prints
- **THEN** the 40th row is the first row of the second page and no row is missing

### Requirement: Print a single transaction

The app SHALL print one transaction with "Print Transaction..." on one page with all details that the list can show for it, including the account, the category, and the comment.

#### Scenario: Proof of payment

- **GIVEN** a selected transfer of -350,00 € to "Erika Mustermann"
- **WHEN** the user chooses "Print Transaction..."
- **THEN** the page shows the account, the booking date, the value date, the recipient with IBAN, the amount, the full purpose, and the end-to-end reference

### Requirement: Print portfolio items

The app SHALL print the positions of a securities account or group with "Print Portfolio Items...", and one position with "Print Portfolio Item...". The printout has the name, the quantity, the purchase price, the last quote, the value, and the profit or loss of each position, and the total value.

#### Scenario: Whole portfolio

- **GIVEN** a securities account with 8 positions
- **WHEN** the user chooses "Print Portfolio Items..."
- **THEN** the printout lists the 8 positions and their total value

### Requirement: Print statements

The app SHALL print the pages of the selected PDF statements unchanged with "Print Statement..." or "Print Statements...".

#### Scenario: Two statements

- **GIVEN** 2 selected statements with 3 pages each
- **WHEN** the user chooses "Print Statements..."
- **THEN** the print dialog shows 6 pages in the order of the statements

### Requirement: Print the payment views

The app SHALL print the list of each payment view with its own command. These are "Print Outbox..." for drafts, "Print Payments..." for sent payments, "Print Scheduled Payments...", "Print Templates...", and "Print Direct Debit Mandates...". A printed row has the same fields as the row in the view.

#### Scenario: Scheduled payments

- **GIVEN** the view "Scheduled" with 2 standing orders and 1 scheduled transfer
- **WHEN** the user chooses "Print Scheduled Payments..."
- **THEN** the printout lists the 3 payments with recipient, amount, and next execution date, and their sum

#### Scenario: Filter by kind

- **GIVEN** the view "Scheduled" with the kind "Standing Orders"
- **WHEN** the user opens the Account menu
- **THEN** the command reads "Print Standing Orders..." and prints only the standing orders

### Requirement: Print a single payment, template, or mandate

The app SHALL print one selected entry of a payment view on one page with all its fields. The command names the kind of entry, for example "Print Transfer...", "Print Standing Order...", "Print Scheduled Transfer...", "Print SRZ Order...", "Print Direct Debit...", "Print Transfer Template...", or "Print Direct Debit Mandate...".

#### Scenario: Standing order

- **GIVEN** a selected standing order of 850,00 € to "Max Mustermann" on the first day of each month
- **WHEN** the user chooses "Print Standing Order..."
- **THEN** the page shows the source account, the recipient with IBAN, the amount, the purpose, the interval, and the first and the next execution date

### Requirement: A batch payment prints as a list

The app SHALL print a batch transfer or a direct debit batch as a list with one row for each position and the sum of all positions.

#### Scenario: Batch with twelve positions

- **GIVEN** a sent batch transfer with 12 positions
- **WHEN** the user prints it
- **THEN** the printout has 12 rows with recipient, IBAN, amount, and purpose, and the total amount

### Requirement: Printouts are readable on paper

The app SHALL print dark text on a white page in the light and in the dark appearance. Hatching and colored backgrounds of the list are not printed. A pending transaction is marked with a word.

#### Scenario: Print in dark mode

- **GIVEN** the app runs in dark mode
- **WHEN** the user prints a transaction list
- **THEN** the pages have a white background and dark text
