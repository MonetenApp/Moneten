# Tasks

One task per requirement of the spec. A task is checked only when a test or a check in the running app shows the behavior.

## 1. Requirements

- [ ] 1.1 Export command. Build it in 2.10 and verify it in the app.
- [ ] 1.2 Only the selection. Build it in 2.10.
- [ ] 1.3 Export follows search and filters. Build it in 2.10.
- [ ] 1.4 Save panel with format choice. Build it in 2.10.
- [ ] 1.5 CSV columns. Build it in 2.8 and 2.9.
- [ ] 1.6 CSV format rules. Build it in 2.8 and 2.9.
- [ ] 1.7 Categories in a CSV file. Build it in 2.8 and 2.9. The scenario "Split transaction" waits for the change `add-split-transactions`.
- [ ] 1.8 Own account in group and category exports. Build it in 2.8 and 2.9.
- [ ] 1.9 Export failures. Build it in 2.10.
- [ ] 1.10 Progress of an export. Build it in 2.10.
- [x] 1.11 Complete export. Verified by AllDataTests "A complete export imports into an empty database, and its export equals the first file apart from the export date", which holds groups, accounts of each kind, an access, categories with rules, transactions, deleted transactions, portfolio values, and positions, and by the debug app check of 2.7. The scenario "Later capability" applies to each later change.
- [x] 1.12 Secrets and files that the complete export leaves out. Verified by AllDataTests "The file names the bank, the user ID, and the connector of an access, and holds neither its PIN nor its state", and by the warning and the message after the export, which name what the file leaves out.
- [x] 1.13 Warning before a complete export. Verified by the debug app check of 2.7: "Export All Data..." shows the warning with "Cancel" and "Export", and only "Export" opens the save panel.
- [x] 1.14 Documented and versioned format. Verified by AllDataTests "Every key of an export is described in docs/export-format.md" and "Amounts are decimal text with a currency, and nothing is rounded".
- [x] 1.15 Import a complete export. Verified by AllDataTests "A complete export imports into an empty database..." and "An imported access has its bank and user ID, and no saved PIN and no state", so the first refresh asks for the PIN, and by the debug app check of 2.7.
- [x] 1.16 Complete import needs an empty database. Verified by AllDataTests "The import refuses a database with an account and changes nothing, and replaces only the starter categories it is given", and by the debug app check of 2.7, where a second import is refused.
- [x] 1.17 Files the complete import cannot read. Verified by AllDataTests "A file of a newer format version is refused and names the need for a newer app" and "A file that ends in the middle of the transactions is refused with the place of the error". The database stays empty, because the file is read in full before the import writes.

## 2. Build

- [x] 2.1 Write AllDataTests for the scenario "Round trip": a database with two groups, a bank account with an access, a migrated account, an offline account, a portfolio with daily values and positions, categories with rules, transactions with categories, comments, checkmarks, pending rows, and source identifiers, and deleted transactions. Export it, import the file into an empty database, and export again. The second file equals the first apart from `exportedAt`, and the loaded ledgers are equal. Verified by AllDataTests "A complete export imports into an empty database, and its export equals the first file apart from the export date".
- [x] 2.2 Build `AllData` in `Sources/Domain/AllData.swift` with its JSON coding: format version 1, amounts as decimal text with a currency, days as `yyyy-MM-dd`, and times in ISO 8601. Verified by the tests of 2.1 and 2.4.
- [x] 2.3 Build `Store.exportAllData()` and `Store.importAllData(_:replacing:)` in `Sources/Storage/` until the test of 2.1 passes. The import writes in one transaction. Verified by the test of 2.1.
- [x] 2.4 Write AllDataTests for the scenarios "No rounding", "Saved PIN", "Accounts without login data", "Database in use", "Newer format", and "Truncated file", and make them pass. Verified by AllDataTests "Amounts are decimal text with a currency, and nothing is rounded", "The file names the bank, the user ID, and the connector of an access...", "An imported access has its bank and user ID...", "The import refuses a database with an account...", "A file of a newer format version is refused...", and "A file that ends in the middle of the transactions...".
- [x] 2.5 Write `docs/export-format.md` with every key of version 1, and a test that each key of the file of 2.1 is in it. Verified by AllDataTests "Every key of an export is described in docs/export-format.md", which found the undocumented key `waitsForUser`.
- [x] 2.6 Name the place of the first error in the message for a damaged file, as the scenario "Truncated file" asks. Verified by AllDataTests "A file that ends in the middle of the transactions...": a bad amount names `transactions[1]`, a bad character names its line and column, and a cut file says that it ends early.
- [x] 2.7 Add "Export All Data..." and "Import All Data..." to the File menu with the warning, the save and open panels, and the refusal of a database in use. Check them in the debug app with made-up data, and record the snapshots in the pull request. Verified by the debug app check: a database with the demo data exported with the harness command `exportall`, an empty database imported the file with `importall`, and its export equals the first file apart from `exportedAt` (175 transactions, 22 categories). A second `importall` was refused. The snapshots of the warning are in the pull request.
- [ ] 2.8 Write TransactionCSVTests for the scenarios "Header row", "One transaction", "Purpose with a semicolon", "Purpose with several lines", "Nested category", and "Group export", with German and English formats.
- [ ] 2.9 Build `TransactionCSV` in the module `Domain` until the tests of 2.8 pass.
- [ ] 2.10 Add "Export Transactions..." to the Account menu and to the context menus of accounts, groups, categories, and rows. Export the selected rows or the rows of the list, propose the file name, write through a temporary file, and show progress with "Cancel". Check it in the debug app.
- [ ] 2.11 Write one line for each part of a split transaction when the change `add-split-transactions` stores splits, and add the splits to the complete export.

## 3. Integration

- [ ] 3.1 Check every scenario of the spec in a release build and record the result in the pull request.

## Workflow follow-up

- Archive the change with `openspec archive add-data-export` when every task is checked.
