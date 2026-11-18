# Design

## Context

This change is part of the first build of the app. The build is a Swift package with the modules `Domain`, `Storage`, `Import`, and `App`, as [ADR 0010](../../../docs/decisions/0010-swift-package-and-macos-15.md) describes. Everything runs on the Mac, with no server ([ADR 0002](../../../docs/decisions/0002-local-first-no-server.md)).

The app keeps all accounts, categories, and transactions of the open database in one in-memory `Ledger` (module `Domain`). Every change goes to the database through `Store` (module `Storage`) and then to the ledger. Views read the ledger. This keeps filters, sums, and charts fast for some ten thousand transactions without queries per keystroke.

## Decisions

The first build follows the spec where the task list marks a task as checked. Open tasks keep the behavior of the spec as the target.

### Edited transactions keep the values of their source

"Edit Transaction..." changes the booking date, the value date, the name, the purpose, and the amount. The first change copies the delivered values of these five fields into `Transaction.original`, and migration `v24` adds its column. A merge finds a row by `sourceValues`, which is `original` for an edited row, so a refresh does not add the transaction again. When a source with IDs delivers changed values, `original` takes them, a field that the user left alone takes them too, and an edited field keeps what the user wrote. A deleted edited row records the delivered values in `DeletedTransaction`. An edit back to the delivered values clears `original`.

A part of a split transaction offers only its category and its comment, so the parts always add up to the amount of the split transaction. A split undoes itself when the delivered amount differs from `original`, also when the user edited the amount. The amount field shows the magnitude next to the type. Every import refuses an amount whose minor units do not fit into `Int64` with room for the opposite sign (`Money(fitting:currency:)`), so every stored transaction amount has a magnitude. The plain `Money(_:currency:)` wraps such an amount around into another one, which the CSV, CAMT, MT940, and FinTS paths passed on before.

A row that the user typed in has no source: it is not fetched and has no source ID and no file identity. `Transaction.edit` writes its values directly and records no `original`, so a file finds the row by the corrected values, and a deleted row records them.

Every gate of `reconcile` that reads the day of a stored row reads `sourceValues`: the pairing, the drop of a pending row, and the protection of a future pending row from a file. An edit that moves such a row into the past therefore keeps it until the booking date of its source.

Only an edited row carries the copy, so the migration rewrites no row. An edited amount counts in every sum, so the computed balance can then differ from the bank balance, which the calibration notice shows.

### Details stand in the help tag and in the sheet

`Transaction.details` lists the details that the source delivered, in the order of the help tag: transaction type, return reason, end-to-end reference, mandate reference, creditor ID, value date, IBAN, and BIC. A detail without a value is left out. The help tag of the purpose shows the whole purpose and below it one line "Label: value" for each detail. `DetailsHelp` builds that text when the pointer enters the purpose. Until then, the help tag is the purpose alone, so a cell that SwiftUI builds while the list scrolls looks up no labels. The transaction sheet shows the same details in its section "Details". The row keeps its height of 55 points, so the table never measures a row again on a change of the selection. `Transaction` has no receipt date yet. The original amount in a foreign currency and a deviating originator or recipient come with task 1.18 of `add-fints-banking`, which adds them to `Transaction`.

Two values stand in the row without a line of their own. A card payment abroad shows its original amount at the start of the amount line, in small text with the marks of the region and the code of its currency, such as "−12.345,00 USD" (`Format.foreignAmount`). It gives way to the amount in a narrow column. A comment follows the yellow icon on the line of the name, on one line, and gives way to the name.

### New marks stay while the view is open

Opening the view of an account counts its new transactions as seen: `Store.markSeen` writes it, then the ledger takes it, so the number on the sidebar row goes. `NewMarks` in `Domain` keeps the IDs of the rows that were new when the view opened, and the row draws the mark when `NewMarks.shows` holds. An account without new transactions leaves `NewMarks` as it is, so opening it redraws no date cell. A row that a refresh adds while the view is open is still new and draws the mark from its own flag.

A change of the view, the lock, closing the main window, and quitting the app end the visit. `NewMarks.leave(account:in:)` empties the marks and returns the rows that are still new in the account of the visit, which are the rows that a refresh added during it. The app writes them through `Store.markSeen` like the rows of the opening, so a row counts as seen after the first visit in which it stood in the list. The lock and the end of the app write only the store: the lock removes the table in the drawing that it starts, so a change of the rows or their marks must not come with it (issue #151), and `closeDatabase` empties the ledger and the marks one drawing later anyway. Opening the main window again, and the unlock, start a new visit of the selected account. Checking a row ends its mark, as `Transaction.markChecked()` ends the mark of a row that is still new.

The original amount and its help tag share one amount format with the list: `Format.amount` in `Domain` writes the number with the decimal places of the currency and a minus sign, and `Format.foreignAmount` adds the code. The help tag names the label "Original amount" only while the pointer is on the amount, as `DetailsHelp` does for the purpose.

### Copied rows are text with tabs

Copy of selected rows writes one line per row in the order of the list, joined with line breaks and without a header. `TransactionCopy.text` in `Domain` builds the text, so its rules have tests. The six fields are the booking date, the name as the row shows it, the purpose, the IBAN, the BIC, and the amount, separated by tabs. Whitespace inside a field, also a line break, becomes one space, so a field never breaks the line or the columns. The purpose ends with each detail that has a value, after a comma: the comment, the transaction type, the return reason, the end-to-end reference, the mandate reference, and the creditor ID. The date is the short date of the region with a four-digit year. The amount has the decimal places of its currency, thousands separators, a hyphen as the minus sign, and no currency, so a spreadsheet reads it as a number. A no-break space as thousands separator, also the narrow one of France, becomes a plain space. A decimal mark other than a comma or a point, or a thousands separator other than a comma, a point, an apostrophe, or a space, falls back to the point and the comma. A text field that starts with "=", "+", "-", "@", or one of the full-width signs "＝", "＋", "－", "＠" gets an apostrophe in front, so that a spreadsheet does not read it as a formula. `SpreadsheetFormula.escaped` in `Domain` holds this rule for Copy and for the CSV export, so the two cannot drift apart. The amount never gets one, because a withdrawal starts with a minus sign.

The table has `onCopyCommand`, on the table and not on its rows. When the user selected text in a row, the field editor of that text is the first responder and copies only the selected text. The command of the table then does not run.

### Services come from the text field

The selectable texts of a row are AppKit text fields. A double click starts their field editor, which is a text view, selects the word, and becomes the first responder. A right click on the selected text then opens the context menu of the text view, not the menu of the table. macOS adds the Services that accept text to that menu. Without selected text, the right click opens the menu of the table. The app adds no code for this, and the debug harness command `textmenu` checks it.

## Risks / Trade-offs

Tasks marked as built in part may differ from the spec in the way their note says.
