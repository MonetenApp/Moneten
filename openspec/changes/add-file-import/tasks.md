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
- [ ] 1.27 CAMT entry with several payments. Built in part: one transaction per entry with the amount of the entry and the purposes of all details. The reader takes the name, IBAN, BIC, and references of the last detail. Change it in 2.3.
- [ ] 1.28 Future pending transactions from a file. Built the other way: a refresh drops every pending row that it does not deliver. Change it in 2.8 and 2.9.
- [ ] 1.29 The bank's version of a future pending transaction from a file. Not built: a refresh adds the bank's version and drops the row from the file, as it drops every pending row that it does not deliver. Build it in 2.8 and 2.9.

## 2. Changes to the first build

- [ ] 2.1 Write FileImportTests tests for the scenarios "Future entry" and "Entry for information": a FUTR entry is pending on its booking date, and an INFO entry is left out. Write the ReconcileTests test "Pending entry booked by a later file": a file with a PDNG row of -89,00 € to "Stadtwerke Musterstadt" on 1 November 2026, then a file with the booked row of -89,00 € to "Stadtwerke Musterstadt", gives one booked transaction.
- [ ] 2.2 Change the CAMT reader in `Sources/Import/TransactionFileImporter.swift` until the tests of 2.1 pass.
- [ ] 2.3 Write the FileImportTests tests for the scenarios "Batch entry" and "Batch entry to one counterparty". The first expects one transaction of -150,00 € with the purpose "Miete November Abschlag Strom", the name "", and no IBAN, BIC, end-to-end reference, mandate reference, or creditor ID. The second expects one transaction of -120,00 € to "Stadtwerke Musterstadt" with the IBAN DE02120300000000202051. Then change the CAMT reader in `Sources/Import/TransactionFileImporter.swift` until both pass.
- [ ] 2.4 Write a FileImportTests test with a camt.053 entry that carries the return reason AC04 and expect `returnReason` "AC04" on the transaction. Write a MergeTests test that stores that transaction through `Store`, reads it back with `Store.loadLedger()`, and expects `returnReason` "AC04". Write a ReconcileTests test in which a booked row with the return reason AC04 books a stored pending row, and expect `returnReason` "AC04" on the booked row.
- [ ] 2.5 Add `returnReason` to `Transaction` with a new migration in `Sources/Storage/Schema.swift`, copy it in `Transaction(arriving:in:fetched:)` and `takingBankFields(of:)` in `Sources/Domain/Reconcile.swift`, and read it from `RtrInf/Rsn/Cd` in the CAMT reader until the tests of 2.4 pass. Add `returnReason` to the field table of `Transaction` in `docs/data-model.md`.
- [ ] 2.6 Write FileImportTests tests for the scenarios of "MT940 dates": the value dates 260102, 251120, 260630, and 800101 with their booking dates.
- [ ] 2.7 Change `parse61` in `Sources/Import/TransactionFileImporter.swift` to the six-month rule until the tests of 2.6 pass.
- [ ] 2.8 Write the ReconcileTests tests "A future pending row from a file survives a refresh", "The bank reports the scheduled rent as pending", and "The bank reported the scheduled rent before the import". Each stores a pending row of -800,00 € to "Vermieter A" on 1 December 2026 with the IBAN DE02120300000000202051, the purpose "Miete Dezember", and `isFetched` false. Each `.refresh` delivery covers the days from 1 November 2026 on. Each `now` is at noon in the current time zone, so `Day(now)` gives the named day.
  - First test: a delivery without the row. With `now` on 20 November 2026 and on 1 December 2026, `dropped` is empty. With `now` on 5 December 2026, `dropped` holds the row. A stored pending row with `isFetched` true on 1 December 2026 is dropped with `now` on 20 November 2026.
  - Second test, step 1: with `now` on 20 November 2026, the delivery brings a pending row of -800,00 € to "Vermieter A" on 1 December 2026 with the IBAN DE02120300000000202051 and the purpose "MIETE DEZEMBER WHG 3 DAUERAUFTRAG". Expect `added` and `dropped` empty, `skipped` 1, and `updated` to hold one row with the ID of the stored row, pending, with the delivered purpose and `isFetched` true. Apply the result to the stored rows.
  - Second test, step 2: with `now` on 2 December 2026, the delivery brings only a booked row of -800,00 € to "Vermieter A" on 2 December 2026 with the same IBAN and purpose. Expect `booked` to hold one row with the ID of the stored row and `needsReview` false, and `added`, `marked`, and `dropped` empty.
  - Second test, two file rows: with a second stored row like the first on 3 December 2026, step 1 gives `updated` with the row of 1 December 2026 and `dropped` with the row of 3 December 2026.
  - Third test, step 1: the stored rows also hold the delivered row of step 1 of the second test, with its own ID and `isFetched` true. With `now` on 20 November 2026, the delivery brings that row again. Expect `dropped` to hold the file row, `added` empty, and `skipped` 1. Apply the result to the stored rows.
  - Third test, step 2: with `now` on 2 December 2026, the delivery brings the booked row of step 2 of the second test. Expect `booked` to hold one row with the ID of the bank's pending row, and `added`, `marked`, and `dropped` empty.
  - Third test, deleted bank row: with the bank's pending row in `deleted` instead of in the stored rows, step 1 gives `added`, `updated`, and `dropped` empty, and `skipped` 1.
- [ ] 2.9 Change `reconcile` in `Sources/Domain/Reconcile.swift` until the tests of 2.8 pass. A future file row is a row of `released` without an outcome in `bookings.ofPending`, whose booking date the delivery covers, without `needsReview`, with `isFetched` false, and with a booking date on or after `Day(now)`.
  - After `bookings` is built, find for each future file row, in the order of `released`, the first delivered pending row that no other future file row took and that `PendingMatch.fits`. Every delivered pending row counts, with or without a partner, except one whose partner is a `.deleted` slot: the user deleted the bank's version, and the file row then is the only copy. Each delivered row takes one future file row at most.
  - In the loop over the delivered rows, in the last `else` branch, before `Transaction(arriving:in:fetched:)`: a delivered row without a partner that took a future file row adds nothing. The file row takes its bank fields through `takingBankFields(of:)`, gets `isFetched` true, runs through `rules.categorize`, and goes into `updated`. `skipped` counts the delivered row. A delivered row with a partner keeps its branch unchanged.
  - In the `case nil` branch of the loop over `released`: keep a future file row that no delivered row fits. Leave out one that a delivered row without a partner took. Drop one that a delivered row with a `.live` partner took, because the bank's version is stored already. Drop one that only a taken delivered row fits.

## 3. Integration

- [ ] 3.1 Check every scenario of the spec in a release build and record the result in the pull request.

## Workflow follow-up

- Archive the change with `openspec archive add-file-import` when every task is checked.
