# Design

## Context

This change is part of the first build of the app. The build is a Swift package with the modules `Domain`, `Storage`, `Import`, and `App`, as [ADR 0010](../../../docs/decisions/0010-swift-package-and-macos-15.md) describes. Everything runs on the Mac, with no server ([ADR 0002](../../../docs/decisions/0002-local-first-no-server.md)).

The app keeps all accounts, categories, and transactions of the open database in one in-memory `Ledger` (module `Domain`). Every change goes to the database through `Store` (module `Storage`) and then to the ledger. Views read the ledger. This keeps filters, sums, and charts fast for some ten thousand transactions without queries per keystroke.

## Decisions

The first build follows the spec where the task list marks a task as checked. Open tasks keep the behavior of the spec as the target.

The filter bar is one `TransactionFilter` for the window, not one for each view. A view change keeps it, with or without the pin. The alternative, a reset on every view change without the pin, would drop the filters a user set on purpose each time the user moves to the next account. Only the filter that the new view does not show returns to "Show All": the category filter on opening a category, the account filter on opening an account or a group. `Ledger.transactions(in:filter:)` applies both filters in every view, so a kept filter without its menu would empty the list with no control to clear it.

The pin saves the filter bar, as its tooltip says. Turning it on writes the period choice, the status, the amount, and the category and account filters to `UserDefaults`, and every later change of these while the pin is on writes them again. At launch, a pin that is on restores them. A period of a month, a quarter, or a year comes back as that month, quarter, or year, and "30 Days", "90 Days", and "12 Months" count from the day of the launch. A category or an account that no longer exists comes back as "Show All". The search text is not saved.

Turning the pin off goes through `AppModel.choose(period: .all)`, so the period menu, the list, and the charts all show "Show All". It then sets the other filters to "Show All" and clears the search text. The filter bar then shows nothing hidden, and one control clears it.

Selecting a saved search puts its search text and filters into the search field and the filter bar, like a choice by hand. Leaving it keeps them by the rule for every view. While the pin is on, this change is saved like any other.

The custom amount range compares the signed `amountMinor` with the signed ends, both ends included. This keeps a range in one direction, so the sum of the filtered list does not mix deposits and withdrawals.

## Risks / Trade-offs

Tasks marked as built in part may differ from the spec in the way their note says.

A pin that is on brings back a period of a month or a year that lies far back after a long time. The menu then shows that month or year, and one click on another period changes it.
