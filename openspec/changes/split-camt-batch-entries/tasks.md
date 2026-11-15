# Tasks

The parts of `add-split-transactions` (its `SplitPart`, `Store.replaceParts(of:with:)`, and the part rows of the ledger) must be on main before task 2.1.

## 1. Reader

- [ ] 1.1 Write FileImportTests tests for the scenarios "Rent and electricity in one batch", "Details that do not add up", and "Details without amounts": the first expects one transaction of -150,00 € with the positions -100,00 € "Vermieter A" "Miete November" and -50,00 € "Vermieter B" "Miete Garage", the other two expect no positions.
- [ ] 1.2 Read the amount of each transaction detail in `CAMTParser` and return the positions in `TransactionFileImporter.Parsed` until the tests of 1.1 pass.

## 2. Parts

- [ ] 2.1 Write a LedgerTests test: a part with a name and a purpose gives a part row with that name and purpose, and the search for "Garage" finds it. Add `name` and `purpose` to `SplitPart` with a new migration in `Sources/Storage/Schema.swift`, and to the field table of `SplitPart` in `docs/data-model.md`, until it passes.
- [ ] 2.2 Write ReconcileTests tests for the scenarios "Rent and electricity in one batch" with the rule `name:"Vermieter A"`, "Parts first, total later", "Total first, parts later", and "Total already split by the user". Each merges the delivery twice and expects nothing to write the second time.
- [ ] 2.3 Add the positions to `Delivery.file` and `split` to `Reconciliation`, and change `reconcile` in `Sources/Domain/Reconcile.swift` until the tests of 2.2 pass.
- [ ] 2.4 Write a MergeTests test that imports the batch through `Store.merge`, reads it back with `Store.loadLedger()`, and expects the two parts with their names, purposes, and categories. Write `split` in `Store.merge` until it passes.

## 3. App

- [ ] 3.1 Count the split rows in the result message of the import ("Split one transaction into its payments.") and check the scenario "Total first, parts later" in a debug build with made-up data. Attach light and dark screenshots.
