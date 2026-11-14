# Design

## Context

This change is part of the first build of the app. The build is a Swift package with the modules `Domain`, `Storage`, `Import`, and `App`, as [ADR 0010](../../../docs/decisions/0010-swift-package-and-macos-15.md) describes. Everything runs on the Mac, with no server ([ADR 0002](../../../docs/decisions/0002-local-first-no-server.md)).

The app keeps all accounts, categories, and transactions of the open database in one in-memory `Ledger` (module `Domain`). Every change goes to the database through `Store` (module `Storage`) and then to the ledger. Views read the ledger. This keeps filters, sums, and charts fast for some ten thousand transactions without queries per keystroke.

## Decisions

The first build follows the spec where the task list marks a task as checked. Open tasks keep the behavior of the spec as the target.

The filter bar is one `TransactionFilter` for the window, not one for each view. A view change keeps it as it is, with or without the pin. Turning the pin off replaces it with the default filter, so every menu shows "Show All". The alternative, a reset on every view change without the pin, would drop the filters a user set on purpose each time the user moves to the next account.

The custom amount range compares the signed `amountMinor` with the signed ends, both ends included. This keeps a range in one direction, so the sum of the filtered list does not mix deposits and withdrawals.

## Risks / Trade-offs

Tasks marked as built in part may differ from the spec in the way their note says.

The change `add-main-window` still says that a view change without the pin resets every filter except the period. Its requirement for the pin needs the same update before the pin is built again, or the two changes contradict each other.
