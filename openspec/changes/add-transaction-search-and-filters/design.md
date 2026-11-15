# Design

## Context

This change is part of the first build of the app. The build is a Swift package with the modules `Domain`, `Storage`, `Import`, and `App`, as [ADR 0010](../../../docs/decisions/0010-swift-package-and-macos-15.md) describes. Everything runs on the Mac, with no server ([ADR 0002](../../../docs/decisions/0002-local-first-no-server.md)).

The app keeps all accounts, categories, and transactions of the open database in one in-memory `Ledger` (module `Domain`). Every change goes to the database through `Store` (module `Storage`) and then to the ledger. Views read the ledger. This keeps filters, sums, and charts fast for some ten thousand transactions without queries per keystroke.

## Decisions

The first build follows the spec where the task list marks a task as checked. Open tasks keep the behavior of the spec as the target.

The filter bar is one `TransactionFilter` for the window, not one for each view. A view change keeps it, with or without the pin. The alternative, a reset on every view change without the pin, would drop the filters a user set on purpose each time the user moves to the next account. Only the filter that the new view does not show returns to "Show All": the category filter on opening a category, the account filter on opening an account or a group. `Ledger.transactions(in:filter:)` applies both filters in every view, so a kept filter without its menu would empty the list with no control to clear it. One `didSet` on `AppModel.selection` applies this rule, so no path that changes the view can skip it: the sidebar, Back and Forward, a new account, group, or category, the launch, a migration, and a new extension access. A saved search shows both menus and resets no filter.

The pin saves the filter bar, as its tooltip says. Turning it on writes the period choice, the status, the amount, and the category and account filters to `UserDefaults`, and every later change of these while the pin is on writes them again. At launch, a pin that is on restores them. A period of a month, a quarter, or a year comes back as that month, quarter, or year, "30 Days", "90 Days", and "12 Months" count from the day of the launch, and a custom period comes back with its start date and end date. A category or an account that no longer exists comes back as "Show All". The search text is not saved.

Turning the pin off goes through `AppModel.choose(period: .all)`, so the period menu, the list, and the charts all show "Show All". It then sets the other filters to "Show All" and clears the search text. The filter bar then shows nothing hidden, and one control clears it.

Selecting a saved search puts its search text and filters into the search field and the filter bar, like a choice by hand. Leaving it keeps them by the rule for every view. While the pin is on, this change is saved like any other.

The custom amount range compares the signed `amountMinor` with the signed ends, both ends included. This keeps a range in one direction, so the sum of the filtered list does not mix deposits and withdrawals.

The search field reads its text with the parser of the rule language. A term with a field name, a regular expression, and an amount mean what they mean in a rule. A term without a field name works like a plain search word: it searches the folded text of every searched field and finds text inside words, also with a wildcard, so `"REWE"` finds "REWE-Markt", which a rule does not. Text that the parser rejects, such as an open quotation mark while the user types, searches its plain words. The parser reads the text for this in a lenient mode, in which an open quotation mark or regular expression ends at the end of the text, so the plain words follow the same operators, groups, and field forms as a rule. The words that the text excludes and the words of a regular expression with a special character are left out. "Search for" puts the name in quotation marks, so a name such as "Tom OR Jerry GbR" stays one phrase.

A regular expression reads the fields of a row as they are, which costs about 2 µs per row. Before that, the search looks for the longest run of plain characters of the pattern in the search text of the row, in lower case. Every match holds that run, so a row without it cannot match. The check only rules out a row whose search text is plain ASCII, because folding changes other text: "e" with a combining accent becomes "é". A pattern with an alternative or a group has no such run.

ICU never returns for some patterns, such as `/^+?49/`, and the search runs on the main thread. Each regular expression of a search therefore matches with progress reports and gives up after 100 ms of processor time on one text, and the rest of that search counts it as no match. Processor time, not clock time, so a busy Mac does not stop a normal search. A pattern that backtracks for tens of milliseconds on each row still holds the window for that long; only a search off the main thread that the next keystroke cancels would fix that, which the app does not have yet. The call over the joined values has a watch of its own, because `\s` matches the joining line break and can make only that call slow. When it gives up, the rows read each value. A pattern with two word boundaries gets no joined call, because ICU reads a boundary at the end of a text from the position of its last read, which a line break does not share. The reports cost one call for each character, which a second change pays for: when the match over the joined values lies inside one value and no value has a line end of its own, that match decides the row without a call for each value.

## Risks / Trade-offs

Tasks marked as built in part may differ from the spec in the way their note says.

A pin that is on brings back a period of a month or a year that lies far back after a long time. The menu then shows that month or year, and one click on another period changes it.
