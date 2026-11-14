# Tasks

One task per requirement of the spec. A task is checked only when a test or a check in the running app shows the behavior.

## 1. Requirements

- [x] 1.1 Import command. Verified by "Import Transactions..." in the Account menu.
- [x] 1.2 Offline and online accounts. Verified by imports into the selected account of any kind.
- [x] 1.3 Format detection. Verified by FileImportTests.
- [x] 1.4 Unsupported files. Verified by the message lists the supported formats.
- [x] 1.5 Empty and oversized files. Verified by FileImportTests "An empty file is rejected"; files over 100 MB are refused.
- [x] 1.6 CSV structure detection. Verified by FileImportTests "CSV with a preamble, semicolons, and German numbers".
- [ ] 1.7 CSV date detection. Built in part: German and ISO dates; no detection of American dates. Finish it and verify it with a test or in the app.
- [ ] 1.8 CSV amount detection. Built in part: verified by FileImportTests "CSV with separate debit and credit columns", including a marker column with S and H, "Amounts with thousands separators in German and English notation", "A CSV amount without decimals takes the decimal mark of the file", and "A CSV file with an amount that cannot be read without doubt is rejected with its line". A trailing sign and a currency code in the amount are not read yet. Finish it and verify it with a test.
- [x] 1.9 CSV columns by header keywords. Verified by FileImportTests "CSV with commas, ISO dates...".
- [ ] 1.10 CSV preview. Build it and verify it with a test or in the app.
- [ ] 1.11 CSV profiles. Build it and verify it with a test or in the app.
- [ ] 1.12 Categories from a CSV file. Build it and verify it with a test or in the app.
- [ ] 1.13 CAMT import. Built in part: the fields of each entry except the return reason, verified by FileImportTests "camt.053 with a debit and a pending credit". The reader makes one transaction per entry, which 2.3 shows for a batch. The reader does not read the return reason, and a transaction has no field for it. Finish it in 2.4 and 2.5.
- [x] 1.14 MT940 import. Verified by FileImportTests "MT940 with a structured field 86".
- [x] 1.15 Several files at once. Verified by the open panel allows several files.
- [ ] 1.16 File belongs to another account. Build it and verify it with a test or in the app.
- [x] 1.17 Existing transactions are skipped. Verified by LedgerTests "Identical rows inside one file stay separate...".
- [x] 1.18 Identical rows inside one file. Verified by LedgerTests "Identical rows inside one file stay separate...".
- [x] 1.19 Result message. Verified by imported and skipped counts.
- [ ] 1.20 Errors name the file and the place. Built in part: file name and line for CSV and MT940. Finish it and verify it with a test or in the app.
- [ ] 1.21 Warnings for a file. Build it and verify it with a test or in the app.
- [x] 1.22 Imported transactions are complete transactions. Verified by rules run on imported rows.
- [x] 1.23 Balances and charts after an import. Verified by the ledger and the charts update at once.
- [ ] 1.24 Progress and cancel. Build it and verify it with a test or in the app.
- [ ] 1.25 Status of a CAMT entry. Built in part: a PDNG entry stays pending, verified by FileImportTests "camt.053 with a debit and a pending credit". The reader imports an INFO entry and a FUTR entry as booked. Change it in 2.1 and 2.2.
- [ ] 1.26 MT940 dates. Built in part: two-digit years are 2000 to 2099, but the booking year moves only between December and January. Change it in 2.6 and 2.7.

## 2. Changes to the first build

- [ ] 2.1 Write FileImportTests tests for the scenarios "Future entry" and "Entry for information": a FUTR entry is pending on its booking date, and an INFO entry is left out. Write the ReconcileTests test "Pending entry booked by a later file": a file with a PDNG row of -89,00 € to "Stadtwerke Musterstadt" on 1 November 2026, then a file with the booked row of -89,00 € to "Stadtwerke Musterstadt", gives one booked transaction.
- [ ] 2.2 Change the CAMT reader in `Sources/Import/TransactionFileImporter.swift` until the tests of 2.1 pass.
- [ ] 2.3 Write the FileImportTests test for the scenario "Batch entry": an entry of -150,00 € with two details gives one transaction of -150,00 €.
- [ ] 2.4 Write a FileImportTests test with a camt.053 entry that carries the return reason AC04 and expect `returnReason` "AC04" on the transaction. Write a MergeTests test that stores that transaction through `Store`, reads it back with `Store.loadLedger()`, and expects `returnReason` "AC04". Write a ReconcileTests test in which a booked row with the return reason AC04 books a stored pending row, and expect `returnReason` "AC04" on the booked row.
- [ ] 2.5 Add `returnReason` to `Transaction` with a new migration in `Sources/Storage/Schema.swift`, copy it in `Transaction(arriving:in:fetched:)` and `takingBankFields(of:)` in `Sources/Domain/Reconcile.swift`, and read it from `RtrInf/Rsn/Cd` in the CAMT reader until the tests of 2.4 pass.
- [ ] 2.6 Write FileImportTests tests for the scenarios of "MT940 dates": the value dates 260102, 251120, 260630, and 800101 with their booking dates.
- [ ] 2.7 Change `parse61` in `Sources/Import/TransactionFileImporter.swift` to the six-month rule until the tests of 2.6 pass.

## 3. Integration

- [ ] 3.1 Check every scenario of the spec in a release build and record the result in the pull request.

## Workflow follow-up

- Archive the change with `openspec archive add-file-import` when every task is checked.
