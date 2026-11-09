# Spec Delta

## Purpose

A report puts balances or category sums on a page that leaves the app. This capability defines the account balance report and the category report, their options, and their output as a printout, a PDF file, or a CSV file.

## ADDED Requirements

### Requirement: Open a report

The app SHALL open the report window with "Account Balance Report..." and "Category Report..." in the menu "Reporting" and in the print menu of the toolbar. "Print Accounts..." on the dashboard opens the account balance report.

#### Scenario: From the menu

- **WHEN** the user chooses "Reporting" and then "Category Report..."
- **THEN** the app shows the window "Reporting" with the heading "Category report"

#### Scenario: From the dashboard

- **WHEN** the user chooses "Print Accounts..." in the context menu of "Dashboard"
- **THEN** the app shows the window "Reporting" with the heading "Account balance report"

### Requirement: Select what the report covers

The app SHALL list all accounts with their groups, or all categories with their groups, under "Selection" with one checkbox each. "Select all" and "Select none" set all checkboxes at once. The window opens with the current sidebar selection checked.

#### Scenario: Group selected in the sidebar

- **GIVEN** the account group "Private" with 3 accounts is selected in the sidebar
- **WHEN** the user opens the account balance report
- **THEN** the 3 accounts of "Private" are checked and all others are not

#### Scenario: Select none

- **WHEN** the user clicks "Select none"
- **THEN** no checkbox is checked

### Requirement: A report needs a selection

The app SHALL refuse to create a report with no checked entry. It asks the user to select at least one account or at least one category.

#### Scenario: Nothing checked

- **GIVEN** no category is checked in the category report
- **WHEN** the user clicks "Preview"
- **THEN** the app asks the user to select at least one category and creates nothing

### Requirement: Balance of today or of a past date

The app SHALL offer two choices under "Amounts" in the account balance report. "Current balance" reports the balance that the bank reported last for each account. "Daily balance from" with a date reports the computed balance at the end of that date.

#### Scenario: Current balance

- **GIVEN** "Giro" with a current balance of 1.200,00 € and "Savings" with 5.000,00 €
- **WHEN** the user creates the report with "Current balance"
- **THEN** the report lists "Giro" with 1.200,00 € and "Savings" with 5.000,00 €

#### Scenario: End of last year

- **WHEN** the user chooses "Daily balance from" and enters 31.12.2025
- **THEN** the report lists the computed balance of each account at the end of 31.12.2025

### Requirement: Compare balances with a second date

The app SHALL add a column with the computed balance of a second date when the user turns on "Daily balance from" under "Compare with". "With absolute and relative change" adds the columns "Absolute change" and "Relative change" and is available only with a comparison.

#### Scenario: Year over year

- **GIVEN** "Savings" with 5.000,00 € on 31.12.2025 and 4.000,00 € on 31.12.2024
- **WHEN** the user reports the balance from 31.12.2025, compares with 31.12.2024, and turns on "With absolute and relative change"
- **THEN** the row of "Savings" shows 5.000,00 €, 4.000,00 €, an absolute change of 1.000,00 €, and a relative change of 25 %

#### Scenario: No comparison

- **WHEN** "Compare with" is off
- **THEN** "With absolute and relative change" is disabled

#### Scenario: Comparison value of zero

- **GIVEN** an account with 0,00 € on the comparison date
- **WHEN** the report is created with changes
- **THEN** the relative change of that account is empty

### Requirement: Extra information in the account balance report

The app SHALL add the IBAN, the BIC, and the bank name of each account for "Bank details", the name of the owner for "Account owner", and the date of creation for "Today's date".

#### Scenario: Bank details

- **WHEN** the user turns on "Bank details" and creates the report
- **THEN** each account row shows its IBAN, its BIC, and the name of its bank

### Requirement: Totals for each currency

The app SHALL end the account balance report with one sum for each currency of the listed accounts. With a comparison, each currency has its own comparison sum and its own changes.

#### Scenario: Euro and dollar accounts

- **GIVEN** two euro accounts with 1.200,00 € and 5.000,00 € and one account with 300,00 USD
- **WHEN** the user creates the report
- **THEN** the report ends with the sums 6.200,00 € and 300,00 USD

### Requirement: Securities accounts in the account balance report

The app SHALL report a securities account with its recorded value for the chosen date. When no value was recorded on or before that date, the row has no amount and a note names the first date with a record.

#### Scenario: Date before the first record

- **GIVEN** a securities account whose value has been recorded since 01.03.2026
- **WHEN** the user reports the daily balance from 31.12.2025
- **THEN** the row of that account has no amount and notes that no balance is available before 01.03.2026

### Requirement: Period of the category report

The app SHALL report the sum of each selected category for a period with a start date and an end date. A menu next to the dates fills them with common periods such as the current month, the last quarter, or the last year.

#### Scenario: Last year

- **GIVEN** "Groceries" with a sum of -5.400,00 € in 2025
- **WHEN** the user sets the period to 01.01.2025 to 31.12.2025 and creates the report
- **THEN** the row of "Groceries" shows -5.400,00 €

#### Scenario: Preset

- **GIVEN** today is 09.11.2026
- **WHEN** the user chooses the last quarter in the menu
- **THEN** the dates read 01.07.2026 and 30.09.2026

### Requirement: Compare category sums with a second period

The app SHALL add a column with the sums of a second period when the user turns on "Compare with period". "With absolute and relative change" adds the columns "Absolute change" and "Relative change".

#### Scenario: Two years

- **GIVEN** "Groceries" with -5.400,00 € in 2025 and -5.000,00 € in 2024
- **WHEN** the user compares 2025 with 2024 and turns on the changes
- **THEN** the row shows -5.400,00 €, -5.000,00 €, an absolute change of -400,00 €, and a relative change of 8 %

### Requirement: Category groups in the report

The app SHALL list the selected categories in sidebar order with their nesting. A category group shows the sum of its selected categories.

#### Scenario: Group with two categories

- **GIVEN** the group "Living" with "Rent" at -9.600,00 € and "Electricity" at -840,00 € in the period
- **WHEN** the user creates the report with all three checked
- **THEN** the report shows "Living" with -10.440,00 € and, indented below it, "Rent" and "Electricity"

### Requirement: Restrict the category report to accounts

The app SHALL count only the transactions of one account or one account group when the user chooses it under "Restrict to". The first value is "All accounts".

#### Scenario: Business account only

- **GIVEN** "Office supplies" with -300,00 € in the account "Business" and -40,00 € in the account "Private" in the period
- **WHEN** the user restricts the report to "Business"
- **THEN** the row of "Office supplies" shows -300,00 €

### Requirement: Hide categories with a sum of zero

The app SHALL leave out every category whose sum is zero in the period and in the comparison period when "Hide zero-sum categories" is on.

#### Scenario: Unused category

- **GIVEN** the category "Pets" with no transactions in the period
- **WHEN** the user creates the report with "Hide zero-sum categories" turned on
- **THEN** the report has no row for "Pets"

### Requirement: Extra information in the category report

The app SHALL add a row with the sum of all listed categories for "Total sum", with one sum for each currency, and the date of creation for "Today's date".

#### Scenario: Total sum

- **GIVEN** a report with "Rent" at -9.600,00 € and "Salary" at 30.000,00 €
- **WHEN** "Total sum" is on
- **THEN** the report ends with a total of 20.400,00 €

### Requirement: Report title

The app SHALL print the text of the field "Title" as the heading of the report. The field starts with "Account overview" for the account balance report and with "Categories" for the category report.

#### Scenario: Own title

- **WHEN** the user enters the title "Household 2025" and creates the category report
- **THEN** the heading of the report is "Household 2025"

### Requirement: Output as printout, PDF file, or CSV file

The app SHALL create the report in the form that the user chooses under "Create as". "Printout" opens the print dialog. "PDF file" and "CSV file" ask where to save the file. The CSV file has the same rows and columns as the printout.

#### Scenario: PDF file

- **WHEN** the user chooses "PDF file", clicks "Save", and picks a folder
- **THEN** the folder contains a PDF file with the report

#### Scenario: CSV file

- **WHEN** the user creates the category report with a comparison as "CSV file"
- **THEN** the file has one line for each category with the name, the sum, the comparison sum, and the changes

### Requirement: Preview

The app SHALL show the finished report on screen when the user clicks "Preview", with the current options and without printing or saving.

#### Scenario: Check before printing

- **WHEN** the user clicks "Preview"
- **THEN** the app shows the report pages
- **AND** no file is written and nothing is sent to a printer

### Requirement: Report options are remembered

The app SHALL open each report with the options that the user chose the last time, except for the selection.

#### Scenario: Second report

- **GIVEN** the user created the last category report as "CSV file" with "Total sum" turned on
- **WHEN** the user opens the category report again
- **THEN** "CSV file" and "Total sum" are still chosen

### Requirement: Cancel creates nothing

The app SHALL close the report window without any output when the user clicks "Cancel".

#### Scenario: Cancel

- **WHEN** the user clicks "Cancel"
- **THEN** the window closes, and nothing is printed or saved
