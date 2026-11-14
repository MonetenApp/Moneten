# Design

## Context

This change is part of the first build of the app. The build is a Swift package with the modules `Domain`, `Storage`, `Import`, and `App`, as [ADR 0010](../../../docs/decisions/0010-swift-package-and-macos-15.md) describes. Everything runs on the Mac, with no server ([ADR 0002](../../../docs/decisions/0002-local-first-no-server.md)).

The app keeps all accounts, categories, and transactions of the open database in one in-memory `Ledger` (module `Domain`). Every change goes to the database through `Store` (module `Storage`) and then to the ledger. Views read the ledger. This keeps filters, sums, and charts fast for some ten thousand transactions without queries per keystroke.

## Decisions

The first build follows the spec where the task list marks a task as checked. Open tasks keep the behavior of the spec as the target.

- `TransactionFileImporter.parse` (module `Import`) returns every CAMT and MT940 row as booked. For a CAMT entry with the status PDNG, INFO, or FUTR it uses the value date as the booking date.
- The CAMT reader collects the transaction details of an entry and builds one transaction per detail. The entry gives the dates.
- `parse61` takes the booking year from the value year and corrects it by the six-month rule of the spec. It replaces the check for December and January only.

## Risks / Trade-offs

Tasks marked as built in part may differ from the spec in the way their note says.
