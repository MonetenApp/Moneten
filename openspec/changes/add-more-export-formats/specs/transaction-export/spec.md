# Spec Delta

## ADDED Requirements

### Requirement: More formats in the save panel

The app SHALL offer the formats CSV, OFX, MT940, SEPA camt.053, Excel, and Numbers in the "Format" menu of the export save panel, and remember the last chosen format.

#### Scenario: Choose MT940

- **WHEN** the user selects "MT940" in the "Format" menu
- **THEN** the proposed file name ends with `.sta` and the options for MT940 appear

#### Scenario: Last format

- **GIVEN** the user exported as Excel yesterday
- **WHEN** the user opens the export save panel today
- **THEN** "Excel" is selected

### Requirement: OFX export

The app SHALL write OFX files in version 1.6 with the account type, the account identification, the balance, and one statement transaction for each exported transaction with date, amount, name, memo, and a stable transaction ID.

#### Scenario: Credit card account

- **WHEN** the user exports a credit card account as OFX
- **THEN** the file holds a credit card statement and not a bank statement

#### Scenario: Stable IDs

- **WHEN** the user exports the same transaction on two days
- **THEN** both files carry the same transaction ID for it

### Requirement: MT940 export

The app SHALL write MT940 files with the extension `.sta`, with one statement for the exported rows, amounts with exactly two decimals, the structured purpose fields that German banks use, and no unneeded line breaks, so that accounting programs for tax advisers read the file.

#### Scenario: SEPA references

- **GIVEN** a transaction with the end-to-end reference "E2E-1" and the creditor ID "DE98ZZZ09999999999"
- **WHEN** the user exports it as MT940
- **THEN** both values are in the structured purpose fields of its entry

#### Scenario: Whole amount

- **WHEN** a transaction has the amount 100 €
- **THEN** the entry holds "100,00"

### Requirement: MT940 options

The app SHALL offer two options for an MT940 export. The account is identified by IBAN or by Bankleitzahl and account number. Interim balances are written or left out.

#### Scenario: Bankleitzahl and account number

- **WHEN** the user chooses the identification by Bankleitzahl for an account with the Bankleitzahl 12030000 and the account number 202051
- **THEN** the account line of the file holds "12030000/202051"

#### Scenario: Without interim balances

- **WHEN** the user turns interim balances off for an export over three months
- **THEN** the file has one opening balance and one closing balance

### Requirement: CAMT export

The app SHALL write camt.053 files in the version camt.053.001.08 with one entry for each exported booked transaction, including the counterparty, IBAN, BIC, purpose, booking text, and SEPA references.

#### Scenario: Valid document

- **WHEN** the user exports an account as SEPA camt.053
- **THEN** the file validates against the schema of camt.053.001.08

### Requirement: Balances in bank formats

The app SHALL write an opening balance and a closing balance in MT940, camt.053, and OFX files that fit the exported rows. The opening balance is the balance of the account before the first exported transaction, and the closing balance is the opening balance plus the exported amounts.

#### Scenario: Selected rows

- **GIVEN** an account with a balance of 1.000,00 € before 3 November 2026, and the user selects two transactions of that day of -100,00 € and -50,00 €
- **WHEN** the user exports the selection as camt.053
- **THEN** the opening balance is 1.000,00 € and the closing balance is 850,00 €

#### Scenario: Gap in the balance history

- **WHEN** the app cannot determine the balance before the first exported row
- **THEN** the app says so before it writes the file and lets the user enter the opening balance or cancel

### Requirement: Pending transactions in bank formats

The app SHALL leave pending transactions out of MT940 and camt.053 files and say how many it left out.

#### Scenario: Two pending rows

- **GIVEN** 20 exported rows of which 2 are pending
- **WHEN** the user exports as MT940
- **THEN** the file holds 18 entries and the app reports that 2 pending transactions were not exported

### Requirement: Account groups in MT940 and OFX

The app SHALL export an account group as MT940 or OFX into one file with one statement for each account of the group, in sidebar order.

#### Scenario: Group with two accounts

- **WHEN** the user exports a group with the accounts "Giro" and "Savings" as MT940
- **THEN** the file holds two statements, the first for "Giro" and the second for "Savings", each with its own balances

### Requirement: Exports that a format cannot describe

The app SHALL refuse an export that the chosen format cannot describe, for example a category with transactions from several accounts as camt.053, and name a format that can.

#### Scenario: Category as CAMT

- **GIVEN** the category "Food" with transactions from three accounts
- **WHEN** the user chooses "SEPA camt.053"
- **THEN** the app says that this format needs a single account and suggests CSV or Excel

### Requirement: Excel and Numbers export

The app SHALL write Excel files as `.xlsx` and Numbers files with the same columns as the CSV export. Dates are date cells and amounts are number cells, so that the user can sort and sum without conversion. Comments are included.

#### Scenario: Sum in a spreadsheet

- **WHEN** the user opens an exported `.xlsx` file and sums the column Amount
- **THEN** the sum equals the sum that the status line of the app showed for the exported rows

#### Scenario: Open in Numbers

- **WHEN** the user exports as Numbers
- **THEN** the file opens in Numbers with one table and a header row

### Requirement: Account identification for exports

The app SHALL let the user enter, in the settings of an account without an IBAN or account number, an account number for MT940 exports and an IBAN for CAMT exports. An export in a bank format without any identification is refused with a hint to these fields.

#### Scenario: Account from an extension

- **GIVEN** an account from an extension that has only an email address as its number
- **WHEN** the user exports it as MT940 without an export account number
- **THEN** the app asks the user to enter one in the account settings

### Requirement: Property list format

The app SHALL provide the transactions as an XML property list for automation. The format is not listed in the save panel.

#### Scenario: Not in the menu

- **WHEN** the user opens the "Format" menu of the save panel
- **THEN** the menu has no entry for a property list

### Requirement: Send transactions to another app

The app SHALL offer "Send Transaction to" or "Send Transactions to" with the name of the target app in the context menu of the transaction list for each installed integration. The command hands the selected transactions, or the listed ones when none is selected, to that app. Without an installed integration the menu has no such entry.

#### Scenario: One integration

- **GIVEN** the integration for the app "Invoices" is installed and 4 transactions are selected
- **WHEN** the user chooses "Send Transactions to Invoices..."
- **THEN** "Invoices" opens and receives the 4 transactions

#### Scenario: Target app fails to open

- **WHEN** the target app cannot be opened
- **THEN** the app reports that the transactions could not be sent and names the app
