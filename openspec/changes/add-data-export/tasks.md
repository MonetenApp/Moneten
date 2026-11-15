# Tasks

One task per requirement of the spec. A task is checked only when a test or a check in the running app shows the behavior.

## 1. Requirements

- [ ] 1.1 Export command. Build it in 2.10 and verify it in the app.
- [x] 1.2 Only the selection. TransactionCSVTests.hiddenSelection checks visible selections, hidden selections, empty selections, and list order through the shared library function that the app calls.
- [x] 1.3 Export follows search and filters. Verified by the debug app check of 2.10: "Girokonto" exports 162 rows, and with the period "current month" 6 rows, the rows that the list shows.
- [ ] 1.4 Save panel with format choice. Build it in 2.10.
- [x] 1.5 CSV columns. Verified by TransactionCSVTests "The first line names the 17 columns in order" and "One transaction in German and in English formats".
- [x] 1.6 CSV format rules. Verified by TransactionCSVTests "A large amount has no thousands separator, and a pending row is marked", "A field with a semicolon, a quotation mark, or a line break is quoted, with the quotation mark doubled", and "The file starts with a byte order mark and is UTF-8".
- [ ] 1.7 Categories in a CSV file. Built and verified by TransactionCSVTests "The category is written with its group, and a row without one names the default category" and by the debug app check of 2.10, which writes "Living - Groceries". The scenario "Split transaction" waits for the change `add-split-transactions` (task 2.11).
- [x] 1.8 Own account in group and category exports. Verified by TransactionCSVTests "Own account is the IBAN, else the account number, else the name of the account".
- [x] 1.9 Export failures. Verified by the debug app check of 2.10: an export into /System says "Could not export to file." with the reason, and no file is created.
- [x] 1.10 Progress of an export. A debug harness check with a 2-second file sync delay captured the actual progress sheet in light and dark appearance while the destination was still absent. Cancel during sync preserved an existing file and removed the temporary file.
- [x] 1.11 Complete export. Verified by AllDataTests "A complete export imports into an empty database, and its export equals the first file apart from the export date", which holds groups, accounts of each kind, an access, categories with rules, transactions, deleted transactions, portfolio values, and positions, and by the debug app check of 2.7. The scenario "Later capability" applies to each later change.
- [x] 1.12 Secrets and files that the complete export leaves out. Verified by AllDataTests "The file names the bank, the user ID, and the connector of an access, and holds neither its PIN nor its state", and by the warning and the message after the export, which name what the file leaves out.
- [x] 1.13 Warning before a complete export. Verified by the debug app check of 2.7: "Export All Data..." shows the warning with "Cancel" and "Export", and only "Export" opens the save panel.
- [x] 1.14 Documented and versioned format. Verified by AllDataTests "Every key of an export is described in docs/export-format.md" and "Amounts are decimal text with a currency, and nothing is rounded".
- [x] 1.15 Import a complete export. Verified by AllDataTests "A complete export imports into an empty database..." and "An imported access has its bank and user ID, and no saved PIN and no state", and by the debug app check of 2.7: an access of the made-up bank exported and imported, and the first refresh of "Girokonto" asks for the PIN.
- [x] 1.16 Complete import needs an empty database. Verified by AllDataTests "The import refuses a database with an account and changes nothing, and replaces only the starter categories it is given" and "The import replaces account groups without accounts", and by the debug app check of 2.7, where a second import is refused.
- [x] 1.17 Files the complete import cannot read. Verified by AllDataTests "A file of a newer format version is refused and names the need for a newer app" and "A file that ends in the middle of the transactions, or has a broken amount, is refused with the place of the error". The database stays empty, because the file is read in full before the import writes.

## 2. Build

- [x] 2.1 Write AllDataTests for the scenario "Round trip": a database with two groups, a bank account with an access, a migrated account, an offline account, a portfolio with daily values and positions, categories with rules, transactions with categories, comments, checkmarks, pending rows, and source identifiers, and deleted transactions. Export it, import the file into an empty database, and export again. The second file equals the first apart from `exportedAt`, and the loaded ledgers are equal. Verified by AllDataTests "A complete export imports into an empty database, and its export equals the first file apart from the export date". After #198, the fixture also holds return reason "AC04", which the imported ledger preserves. AllDataTests "An export without returnReason imports its transactions with no return reason" verifies older files.
- [x] 2.2 Build `AllData` in `Sources/Domain/AllData.swift` with its JSON coding: format version 1, amounts as decimal text with a currency, days as `yyyy-MM-dd`, and times in ISO 8601. Verified by the tests of 2.1 and 2.4.
- [x] 2.3 Build `Store.exportAllData()` and `Store.importAllData(_:replacing:)` in `Sources/Storage/` until the test of 2.1 passes. The import writes in one transaction. Verified by the test of 2.1.
- [x] 2.4 Write AllDataTests for the scenarios "No rounding", "Saved PIN", "Accounts without login data", "Database in use", "Newer format", and "Truncated file", and make them pass. Verified by AllDataTests "Amounts are decimal text with a currency, and nothing is rounded", "The file names the bank, the user ID, and the connector of an access...", "An imported access has its bank and user ID...", "The import refuses a database with an account...", "A file of a newer format version is refused...", and "A file that ends in the middle of the transactions...".
- [x] 2.5 Write `docs/export-format.md` with every key of version 1, and a test that each key of the file of 2.1 is in it. Verified by AllDataTests "Every key of an export is described in docs/export-format.md", which found the undocumented key `waitsForUser`.
- [x] 2.6 Name the place of the first error in the message for a damaged file, as the scenario "Truncated file" asks. Verified by AllDataTests "A file that ends in the middle of the transactions, or has a broken amount, is refused with the place of the error": a cut file and a bad character name their line and column, and a bad amount, such as "1-2" or "12.345" in EUR, names `transactions[1]`.
- [x] 2.7 Add "Export All Data..." and "Import All Data..." to the File menu with the warning, the save and open panels, and the refusal of a database in use. Check them in the debug app with made-up data, and record the snapshots in the pull request. Verified by the debug app check: a database with the demo data exported with the harness command `exportall`, an empty database imported the file with `importall`, and its export equals the first file apart from `exportedAt` (175 transactions, 22 categories). A second `importall` was refused. The snapshots of the warning are in the pull request.
- [x] 2.8 Write TransactionCSVTests for the scenarios "Header row", "One transaction", "Purpose with a semicolon", "Purpose with several lines", "Nested category", and "Group export", with German and English formats. Verified by the seven TransactionCSVTests.
- [x] 2.9 Build `TransactionCSV` in the module `Domain` until the tests of 2.8 pass. Verified by the tests of 2.8.
- [ ] 2.10 Add "Export Transactions..." to the Account menu and to the context menus of accounts, groups, categories, and rows. Export the selected rows or the rows of the list, propose the file name, write through a temporary file, and show progress with "Cancel". Check it in the debug app. Built. Checked in the debug app with the harness command `exportcsv`, which writes through the same code without the save panel: an account, a category from all accounts, the period filter, the byte order mark, and a write-protected folder. Gate round 1 additionally checks visible selections through TransactionCSVTests.hiddenSelection, the full-account context export through the harness, and progress and cancellation with a 2-second sync delay. Not checked yet: actual menu clicks and the save panel with its "Format" menu and proposed name.
- [ ] 2.11 Write one line for each part of a split transaction when the change `add-split-transactions` stores splits, and add the splits to the complete export.

## 3. Integration

- [ ] 3.1 Check every scenario of the spec in a release build and record the result in the pull request.

## Gate round 1

- [x] Refuse category and account group parent loops before writing. AllDataTests.parentLoops checks self parents and A/B loops through both JSON and direct store import, names position 0, and compares all stored data before and after each refusal.
- [x] Bound ISO days before parsing. AllDataTests.boundedDays refuses "01-01-9223372036854775807" in booking dates, value dates, and portfolio days without changing the database.
- [x] Refuse portfolio values in a foreign currency. AllDataTests.portfolioCurrency refuses "100" JPY for a EUR portfolio and verifies an empty database.
- [x] Write complete exports with mode 0600 before writing financial data. AllDataTests.privateExportFile measures a new file and an existing file with mode 0644, checks the readable export, and verifies cleanup after a failed replacement. AllDataTests.longExportFilename checks a valid 235-byte target name.
- [x] Accept only three uppercase ASCII letters in currency codes. AllDataTests.currencyCodes checks seven invalid literal codes in twelve currency fields, including optional holding currencies and exchange rates, and accepts "ZZZ" as a syntactically valid code.
- [x] Refuse versions below 1 and unreadable stored holdings. AllDataTests.positiveVersion checks 0 and -1. AllDataTests.unreadableHolding checks a broken quantity, a positional error, and preservation of an existing export.

Each regression failed before its fix. The focused AllDataTests suite passes with 19 tests.

## Gate follow-ups on main after #197

- [x] Share the private export writer with CSV. ExportFileTests.privateExportFile and AllDataTests.privateExportFile measure mode 0600 through the shared writer on new and replaced files. The CSV check failed with 0644 before the fix.
- [x] Explain an unreadable database in the complete export alert. AllDataTests.exportErrorDescription asserts the literal message from the spec. The debug harness captures the same alert before and after the fix in light mode. The existing export stays unchanged.
- [x] Refuse decimal values that would be rounded, with their position. AllDataTests.decimalPrecision checks holding quantities, prices, purchase prices, and exchange rates. It verifies that the database stays empty and that a signed 38-digit quantity imports without rounding. AllDataTests.exactDecimalRoundTrip preserves five exactly represented values, including small fractions and 39-digit coefficients. The test imported a truncated value before the fix.
- [x] Sync both exports before reporting success. `scripts/check-export-sync.sh` observes full file sync before rename and directory sync after rename through the shared writer for new and replaced files. Before the fix it observed only renames.

- [ ] Verify the error alert in dark appearance. Two harness capture attempts produced unreadable images, so the dark check is inconclusive. The PR includes only the readable light snapshots.

## CSV gate round 1

- [x] Choose rows in Domain. TransactionCSVTests.hiddenSelection reproduces one hidden selection and 41 visible exported rows, visible and mixed selections, an empty list, and list order.
- [x] Protect formula-like text. TransactionCSVTests.formulaProtection checks six literal prefixes in Category, Name, Purpose, Account, Bank, Own account, Booking text, the SEPA references, and Comment. Amount stays "-89,00".
- [x] Specify currency precision. TransactionCSVTests.otherCurrencies checks KWD "-12,345" and JPY "-1000,00". This behavior already passed before the round.
- [x] Check the shared writer in StorageTests. ExportFileTests.privateExportFile checks mode 0600 for a new file and replacement of mode 0644. The standalone GUI permissions script is removed. The sync probe stays because storage results cannot prove sync order. Both scripts/check.sh and CI run scripts/check-export-sync.sh, which checks full sync, forced fsync fallback, rename, directory sync, and cancellation during sync.
- [x] Export the whole account from its context menu. The harness check writes all 162 demo rows with a row selected, a search, and a month filter. Before the fix it wrote only 1 selected row.
- [x] Keep CSV encoding and file I/O off the main actor. With the injected 2-second sync delay, the before snapshot arrived only after sync. After snapshots arrived while sync was pending and show the progress sheet in both appearances. Cancellation preserves an existing destination.
- [x] Allow a mode 0300 destination folder. ExportFileTests.writeOnlyFolder checks the literal contents and mode 0600. Directory sync is best effort because some destinations cannot open or sync a directory.
- [x] Use one digit set in ar_EG. TransactionCSVTests.arabicDigits checks the complete literal CSV row with ASCII digits in dates and amounts and the Arabic decimal mark.

The selection, formula, Arabic digit, cancellation, and write-only folder regressions failed before their fixes. The KWD and private-file checks confirmed behavior that already worked. The harness checks use only a private debug app and made-up data. Menu clicks, the save panel, 200,000 rows, and release-build integration remain unchecked.

## Review follow-up after CSV gate round 1

- [x] Keep one CSV export active through cancellation cleanup. The first Ponytail review found that an old canceled worker could clear the next export's task and progress. The harness regression first observed 2 writers after cancel and immediate retry, where 1 was expected. The shared entry points now refuse a second export while cleanup is pending, and every CSV export command observes and disables for that busy state. Retrying after cleanup shows progress and remains cancelable.

- [x] Preserve the locale calendar when choosing ASCII digits. TransactionCSVTests.localeCalendar first failed with th_TH "03/11/2026" and now checks "03/11/2569". The formatter changes only the numbering system.

## Workflow follow-up

- Archive the change with `openspec archive add-data-export` when every task is checked.
