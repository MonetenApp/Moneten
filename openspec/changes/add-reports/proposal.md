# Proposal: Create reports for accounts and categories

## Why

Some answers must leave the app. A user needs the balances of all accounts on one page for a loan application or a year-end overview. A user needs the sums of all categories for a period for a tax adviser or a household meeting. Reports produce these as paper, as a PDF file, or as a CSV file.

## What Changes

- "Account Balance Report..." lists the balances of chosen accounts for today or for a past date, and it can compare them with a second date.
- "Category Report..." lists the sums of chosen categories for a period, and it can compare them with a second period.
- Both reports have a title, optional extra information, and a preview.
- Both reports can be created as a printout, a PDF file, or a CSV file.

## Capabilities

### New Capabilities

- `reports`: the account balance report and the category report, their options, and their output formats.

### Modified Capabilities

None.

## Impact

- Milestone: later
- Issues: none yet
- Modules: `Domain` owns the report data. `App` owns the report window, the layout, and the output.
- Depends on the change `add-charts` for the computed daily balances, and on the change `add-categories` for the category sums.
- Depends on the change `add-portfolio-analysis` for the recorded values of securities accounts.
- Depends on the change `add-printing` for the page setup.
- Decisions: none apply.

## Reference behavior

### Observed in MoneyMoney 2.5.3

- The menu "Reporting" has "Account Balance Report..." and "Category Report...". The toolbar has a menu "Print reports". The dashboard has "Print Accounts...". See [analysis](../../../docs/research/moneymoney-analysis.md#reports-u-s-c).
- Both reports open a window "Reporting" with a list of checkboxes under "Selection", the buttons "Select all" and "Select none", a "Title", "Create as" with "Printout", "PDF file", and "CSV file", and the buttons "Preview", "Cancel", and "Print" or "Save".
- The account balance report has "Amounts" with "Current balance" or "Daily balance from" a date, "Compare with" a second "Daily balance from" date, "With absolute and relative change", and "Additional information" with "Bank details", "Account owner", and "Today's date". Its title starts as "Account overview". The analysis page lists these controls only in a short form. They were read from the open window.
- The category report has a "Period" with a start date, an end date, and a menu, "Compare with period", "With absolute and relative change", "Additional information" with "Total sum" and "Today's date", "Restrict to" with "All accounts" as the first value, and "Hide zero-sum categories". Its title starts as "Categories".
- Print and export of reports arrived in version 2.3.12, the restriction to an account or group in 2.3.26, and "Hide zero-sum categories" in 2.4.10.
- A report with several currencies shows the comparison for each currency (version history, 2.4.65).
- Without a selection the app says "Please select at least one account." or "Please select at least one category."
- For a securities account the report notes when no balance is available before a date (interface string).

### Decided for Moneten

- "Current balance" is the balance that the bank reported last. "Daily balance from" uses the computed balance at the end of that date. The exact source in MoneyMoney was not observed.
- The window opens with the accounts or categories of the current sidebar selection checked.
- The app remembers the options of each report for the next time.
- The CSV file has the same rows and columns as the printout, with a semicolon as the separator and UTF-8 text. The layout of MoneyMoney's files was not observed.
- The relative change is empty when the comparison value is zero.
