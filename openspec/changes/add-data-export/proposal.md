# Proposal: Export transactions as CSV and all data as JSON

## Why

The project promises that users can leave at any time with all their data, and come back. Users also need their transactions in a spreadsheet, for a tax adviser, or for another program. A CSV export covers the daily need. A complete JSON export keeps the promise.

## What Changes

- "Export Transactions..." exports the transactions of the selected account, group, or category, or only the selected rows, as a CSV file.
- The CSV file has a documented set of columns that includes the category, the comment, and the checkmark.
- A command "Export All Data..." writes every piece of user data to one documented JSON file.
- A command "Import All Data..." reads such a file into an empty database without loss.
- The app warns that the complete export is not encrypted.

## Capabilities

### New Capabilities

- `transaction-export`: exporting transactions to files from the transaction list, and the complete export and re-import of all data.

### Modified Capabilities

None.

## Impact

- Milestone: v0.1
- Issues: #8
- Modules: `Domain` owns the export model. `Storage` reads and writes it. `App` owns the commands and the save panel. The JSON format is documented in `docs/`.
- Depends on the changes `add-transaction-list` for the selection, `add-categories` and `add-categorization-rules` for the category data, and `add-encrypted-database` for the empty database.
- Every later change that stores user data must extend the complete export. The export requirement says so, and each such change needs a task for it.
- Decisions: [ADR 0002](../../../docs/decisions/0002-local-first-no-server.md).

## Reference behavior

### Observed in MoneyMoney 2.5.3

- "Export Transactions..." is in the Account menu and in the context menus of accounts, account groups, and categories. "Export Transaction..." is in the context menu of a transaction. See [analysis](../../../docs/research/moneymoney-analysis.md#context-menus-u).
- The export opens a save panel with a format choice. See [analysis](../../../docs/research/moneymoney-analysis.md#file-formats-s-w-c).
- When transactions are selected in the list, the export covers only the selection (version history, 2.2.1).
- The CSV export is itself an export script. Its published template writes the columns Date, Value date, Category, Name, Purpose, Account, Bank, Amount, and Currency, separated by semicolons, with dates and numbers in the local format, and with " - " between a category group and its category ([Export API page](https://moneymoney.app/api/export/)).
- Messages exist for progress ("Exporting...") and failure ("Could not export to file.").
- MoneyMoney has no complete export of all data. Its backup is a copy of the encrypted database.

### Decided for MonetenMoneten

- The complete JSON export and its import come from issue #8. They are new.
- The commands "Export All Data..." and "Import All Data..." are in the File menu.
- The CSV file has more columns than MoneyMoney's default, namely the own account, the booking text, the SEPA references, the comment, and the checkmark.
- The CSV file is UTF-8 with a byte order mark, so that spreadsheet programs read umlauts correctly.
- A split transaction is written as one line for each part. A column Pending marks transactions that the bank has not booked. Both were not observed in MoneyMoney.
- With no rows selected, the export covers the rows that the list shows, with the active search and filters. MoneyMoney's behavior with an active filter was not observed.
- The complete export leaves out PINs, passwords, tokens, the storage of extensions, and statement files.
- The import of a complete export works only into an empty database. Merging two databases is out of scope.
- Amounts in the JSON file are decimal text with a currency code, so that no rounding happens.
