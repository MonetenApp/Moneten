# Design

## Context

This change is part of the first build of the app. The build is a Swift package with the modules `Domain`, `Storage`, `Import`, and `App`, as [ADR 0010](../../../docs/decisions/0010-swift-package-and-macos-15.md) describes. Everything runs on the Mac, with no server ([ADR 0002](../../../docs/decisions/0002-local-first-no-server.md)).

The app keeps all accounts, categories, and transactions of the open database in one in-memory `Ledger` (module `Domain`). Every change goes to the database through `Store` (module `Storage`) and then to the ledger. Views read the ledger. This keeps filters, sums, and charts fast for some ten thousand transactions without queries per keystroke.

## Decisions

The first build follows the spec where the task list marks a task as checked. Open tasks keep the behavior of the spec as the target.

### Edited transactions keep the values of their source

"Edit Transaction..." changes the booking date, the value date, the name, the purpose, and the amount. The first change copies the delivered values of these five fields into `Transaction.original`, and migration `v24` adds its column. A merge finds a row by `sourceValues`, which is `original` for an edited row, so a refresh does not add the transaction again. When a source with IDs delivers changed values, `original` takes them, a field that the user left alone takes them too, and an edited field keeps what the user wrote. A deleted edited row records the delivered values in `DeletedTransaction`. An edit back to the delivered values clears `original`.

A part of a split transaction offers only its category and its comment, so the parts always add up to the amount of the split transaction. A split undoes itself when the delivered amount differs from `original`, also when the user edited the amount. The amount field shows the magnitude next to the type. The one amount without a magnitude in `Int64`, which a complete import accepts, shows without a field and stays as it is.

Only an edited row carries the copy, so the migration rewrites no row. An edited amount counts in every sum, so the computed balance can then differ from the bank balance, which the calibration notice shows.

## Risks / Trade-offs

Tasks marked as built in part may differ from the spec in the way their note says.
