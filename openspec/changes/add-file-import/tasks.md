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
- [x] 1.21 Warnings for a file. Verified by FileImportTests "A CSV row with an unknown currency or an unreadable value date is imported with a warning for its line", "A CAMT entry with an unreadable value date is imported with a warning for its line", "A CSV warning or error names the line of the file where its row starts, after a cell with a line break", and "A CAMT value date with a time is read, and one that cannot be read is imported with a warning". In the app, the import result lists each warning with the file name, and a file that adds no transaction lists none.
- [x] 1.22 Imported transactions are complete transactions. Verified by rules run on imported rows.
- [x] 1.23 Balances and charts after an import. Verified by the ledger and the charts update at once.
- [ ] 1.24 Progress and cancel. Build it and verify it with a test or in the app.
- [ ] 1.25 Status of a CAMT entry. Built in part: a PDNG entry stays pending and an INFO entry is left out, verified by FileImportTests "camt.053 with a debit and a pending credit" and "An entry for information is left out, and a future entry is booked until a refresh keeps future pending rows from a file", and ReconcileTests "Pending entry booked by a later file". A FUTR entry is still booked, so that a refresh does not drop it (FileImportTests "Scheduled rent from a FUTR entry stays after a refresh that does not deliver it"). Make it pending once 2.8 and 2.9 are built.
- [x] 1.26 MT940 dates. Verified by FileImportTests "An MT940 booking date takes the year of the value date, moved by the six-month rule".
- [x] 1.27 CAMT entry with several payments. Verified by FileImportTests "Batch entry" and "Batch entry to one counterparty".
- [x] 1.28 Future pending transactions from a file. Verified by ReconcileTests "A future pending row from a file survives a refresh".
- [x] 1.29 The bank's version of a future pending transaction from a file. Verified by ReconcileTests "The bank reports the scheduled rent as pending", "The bank reported the scheduled rent before the import", "A bank row that is the version of one future file row does not remove a second one", and "A stored bank row that moves to the day of a future file row removes the file row in the same refresh".

## 2. Changes to the first build

- [ ] 2.1 Write FileImportTests tests for the scenarios "Future entry" and "Entry for information": a FUTR entry is pending on its booking date, and an INFO entry is left out. Write the ReconcileTests test "Pending entry booked by a later file": a file with a PDNG row of -89,00 € to "Stadtwerke Musterstadt" on 1 November 2026, then a file with the booked row of -89,00 € to "Stadtwerke Musterstadt", gives one booked transaction.
- [ ] 2.2 Change the CAMT reader in `Sources/Import/TransactionFileImporter.swift` until the tests of 2.1 pass. The INFO part and the ReconcileTests test of 2.1 are done. The FUTR part waits until 2.9 is built, because a refresh drops a pending FUTR row before that.
- [x] 2.3 Write the FileImportTests tests for the scenarios "Batch entry" and "Batch entry to one counterparty". The first expects one transaction of -150,00 € with the purpose "Miete November Abschlag Strom", the name "", and no IBAN, BIC, end-to-end reference, mandate reference, or creditor ID. The second expects one transaction of -120,00 € to "Stadtwerke Musterstadt" with the IBAN DE02120300000000202051. Then change the CAMT reader in `Sources/Import/TransactionFileImporter.swift` until both pass.
- [ ] 2.4 Write a FileImportTests test with a camt.053 entry that carries the return reason AC04 and expect `returnReason` "AC04" on the transaction. Write a MergeTests test that stores that transaction through `Store`, reads it back with `Store.loadLedger()`, and expects `returnReason` "AC04". Write a ReconcileTests test in which a booked row with the return reason AC04 books a stored pending row, and expect `returnReason` "AC04" on the booked row.
- [ ] 2.5 Add `returnReason` to `Transaction` with a new migration in `Sources/Storage/Schema.swift`, copy it in `Transaction(arriving:in:fetched:)` and `takingBankFields(of:)` in `Sources/Domain/Reconcile.swift`, and read it from `RtrInf/Rsn/Cd` in the CAMT reader until the tests of 2.4 pass. Add `returnReason` to the field table of `Transaction` in `docs/data-model.md`.
- [x] 2.6 Write FileImportTests tests for the scenarios of "MT940 dates": the value dates 260102, 251120, 260630, and 800101 with their booking dates.
- [x] 2.7 Change `parse61` in `Sources/Import/TransactionFileImporter.swift` to the six-month rule until the tests of 2.6 pass.
- [x] 2.8 Write the ReconcileTests tests "A future pending row from a file survives a refresh", "The bank reports the scheduled rent as pending", and "The bank reported the scheduled rent before the import". Each stores a pending row of -800,00 € to "Vermieter A" on 1 December 2026 with the IBAN DE02120300000000202051, the purpose "Miete Dezember", and `isFetched` false. Each `.refresh` delivery covers the days from 1 November 2026 on. Each `now` is at noon in the current time zone, so `Day(now)` gives the named day.
  - First test: a delivery without the row. With `now` on 20 November 2026 and on 1 December 2026, `dropped` is empty. With `now` on 5 December 2026, `dropped` holds the row. A stored pending row with `isFetched` true on 1 December 2026 is dropped with `now` on 20 November 2026.
  - Second test, step 1: with `now` on 20 November 2026, the delivery brings a pending row of -800,00 € to "Vermieter A" on 1 December 2026 with the IBAN DE02120300000000202051 and the purpose "MIETE DEZEMBER WHG 3 DAUERAUFTRAG". Expect `added` and `dropped` empty, `skipped` 1, and `updated` to hold one row with the ID of the stored row, pending, with the delivered purpose and `isFetched` true. Apply the result to the stored rows.
  - Second test, step 2: with `now` on 2 December 2026, the delivery brings only a booked row of -800,00 € to "Vermieter A" on 2 December 2026 with the same IBAN and purpose. Expect `booked` to hold one row with the ID of the stored row and `needsReview` false, and `added`, `marked`, and `dropped` empty.
  - Second test, two file rows: with a second stored row like the first on 3 December 2026, step 1 gives `updated` with the row of 1 December 2026 and `dropped` with the row of 3 December 2026.
  - Third test, step 1: the stored rows also hold the delivered row of step 1 of the second test, with its own ID and `isFetched` true. With `now` on 20 November 2026, the delivery brings that row again. Expect `dropped` to hold the file row, `added` empty, and `skipped` 1. Apply the result to the stored rows.
  - Third test, step 2: with `now` on 2 December 2026, the delivery brings the booked row of step 2 of the second test. Expect `booked` to hold one row with the ID of the bank's pending row, and `added`, `marked`, and `dropped` empty.
  - Third test, deleted bank row: with the bank's pending row in `deleted` instead of in the stored rows, step 1 gives `added`, `updated`, and `dropped` empty, and `skipped` 1.
  - Fourth test "A bank row that is the version of one future file row does not remove a second one": stored file rows like the first on 1 and 8 December 2026. With `now` on 20 November 2026, a delivery of the row of 1 December 2026 gives `dropped` and `added` empty and `updated` with the row of 1 December 2026. A second refresh of the same row on 21 November 2026 gives `dropped` and `updated` empty.
  - Fifth test "A stored bank row that moves to the day of a future file row removes the file row in the same refresh": a stored pending bank row with the source ID "bank-7" on 29 November 2026 and the file row of 1 December 2026. A delivery of "bank-7" on 1 December 2026 gives `dropped` with the file row, and the same delivery again gives `dropped` and `updated` empty.
- [x] 2.9 Change `reconcile` in `Sources/Domain/Reconcile.swift` until the tests of 2.8 pass. A future file row is a row of `released` without an outcome in `bookings.ofPending`, whose booking date the delivery covers, without `needsReview`, with `isFetched` false, and with a booking date on or after `Day(now)`.
  - After `bookings` is built, find for each future file row, in the order of `released`, the first delivered pending row that no other future file row took and that `PendingMatch.fits`. Every delivered pending row counts, with or without a partner, except one whose partner is a `.deleted` slot: the user deleted the bank's version, and the file row then is the only copy. A delivered row whose partner is a `.live` slot fits only a future file row on the booking date of the delivered row, so the first payment of a weekly order does not remove the next one. Each delivered row takes one future file row at most.
  - In the loop over the delivered rows, in the last `else` branch, before `Transaction(arriving:in:fetched:)`: a delivered row without a partner that took a future file row adds nothing. The file row takes its bank fields through `takingBankFields(of:)`, gets `isFetched` true, runs through `rules.categorize`, and goes into `updated`. `skipped` counts the delivered row. A delivered row with a partner keeps its branch unchanged.
  - In the `case nil` branch of the loop over `released`: keep a future file row that no delivered row fits. Leave out one that a delivered row without a partner took. Drop one that a delivered row with a `.live` partner took, because the bank's version is stored already. Drop one that only a taken delivered row fits.

## 3. Integration

- [ ] 3.1 Check every scenario of the spec in a release build and record the result in the pull request.

## Workflow follow-up

- Archive the change with `openspec archive add-file-import` when every task is checked.
