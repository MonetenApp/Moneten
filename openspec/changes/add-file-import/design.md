# Design

## Context

This change is part of the first build of the app. The build is a Swift package with the modules `Domain`, `Storage`, `Import`, and `App`, as [ADR 0010](../../../docs/decisions/0010-swift-package-and-macos-15.md) describes. Everything runs on the Mac, with no server ([ADR 0002](../../../docs/decisions/0002-local-first-no-server.md)).

The app keeps all accounts, categories, and transactions of the open database in one in-memory `Ledger` (module `Domain`). Every change goes to the database through `Store` (module `Storage`) and then to the ledger. Views read the ledger. This keeps filters, sums, and charts fast for some ten thousand transactions without queries per keystroke.

## Decisions

The first build follows the spec where the task list marks a task as checked. Open tasks keep the behavior of the spec as the target.

- `TransactionFileImporter.parse` (module `Import`) returns a CAMT entry with the status PDNG or FUTR as pending, on the booking date of the entry, and leaves out an entry with the status INFO. A pending row from a file is booked by `reconcile` (module `Domain`) like one from a refresh: a later file or refresh brings the booked row with the same amount, and `Bookings` pairs it with the stored pending row. The booking date stays the date of the entry, so the booked version finds its pending row.
- The CAMT reader collects the transaction details of an entry. It builds one transaction per detail only when there are two or more details, each has `TxDtls/AmtDtls/TxAmt/Amt`, and their sum equals `Ntry/Amt`. Otherwise it builds one transaction with the entry amount, as the first build does. The entry gives the dates.
- The CAMT reader reads the return reason from `RtrInf/Rsn/Cd`. `Transaction` gets a field for it through a new migration in `Sources/Storage/Schema.swift`.
- `parse61` takes the booking year from the value year and corrects it by the six-month rule of the spec. It replaces the check for December and January only.

## Risks / Trade-offs

Tasks marked as built in part may differ from the spec in the way their note says.

- A batch entry that a CAMT file splits into its details does not match the single row of the same batch from a refresh or an MT940 file. A refresh that brings -150,00 € after a file brought -100,00 € and -50,00 € adds the -150,00 € as a new row, and the other way round. The user deletes the duplicate. A rule that matches the details of a split entry with one stored row of the entry amount on the same day would remove this. It is left for a later change, because no bank connector is built yet.
- A pending row that the bank never books stays pending until the user deletes it.
