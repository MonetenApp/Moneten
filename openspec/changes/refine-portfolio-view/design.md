# Design

## Context

The change `redesign-portfolio-holdings` (#605, #607, #609) built the list of positions in `App/Sources/Views/HoldingsView.swift` as a SwiftUI `Table` with six columns and native headers, a tag with the asset class next to the ISIN, and the day of a quote only when it is old. The owner approved draft 5 of the next step on 27 November 2026. The draft is an HTML page with made-up data on the owner's Mac. Its measures are in this design, so no part needs the file.

This change modifies requirements of two changes that are not archived yet: "Position row content", "Quantities as units or as a nominal amount", "Profit or loss", and "Filter by asset class" of `redesign-portfolio-holdings`, and "Order of positions" and "Search positions" of `add-securities-accounts`, which `redesign-portfolio-holdings` does not touch. It removes "Asset class tag" and "Day of an old quote" of `redesign-portfolio-holdings`. It takes over "Pie chart by asset class" and "The charts follow the asset class filter" of `add-portfolio-analysis` as the allocation popover and removes both from that change.

## Scope

Four parts, one pull request each, in this order. Parts 2 to 4 each change `HoldingsView.swift`, so they wait for part 1.

- Part 1 (#610): the rows, the inset, the ribbon in the default color of its class, the WKN, the header, the sorting, and the opening of a position. The opening has no visible effect yet, because no position has a comment before part 2.
- Part 2 (#611): the comment, its storage and export, the sheet, the comment mark, the comment line of an open position, and the search.
- Part 3 (#612): the filters "Profit/Loss" and "Quote", their lines, the count of the status line, and the pin.
- Part 4 (#613): the editable colors, the grouping, ⌘K, the drop on a heading, and the allocation.

## Decisions

### The table stays, with a header of its own (part 1)

The list stays a SwiftUI `Table`. It gives the selection with ⌘ and ⇧, the keyboard, the context menu of the selection, VoiceOver, and the `NSTableView` that the debug harness and `App/Sources/PerfCheck.swift` look for by its column "Quantity". A list of own rows would have to build all of that again.

The native header has one line and cannot show "Purchase price" over "Last quote". So the table hides its header with `.tableColumnHeaders(.hidden)`, as the transaction table does, and `HoldingsHeader` draws the header above it in SwiftUI. Header and table share one set of column widths, `PositionColumns`: every column except "Name" has a fixed width, and "Name" takes the rest. The header lays out its cells with the same widths and the same gap between cells as the table, 17 points, so header and cells stay in line at every window width. The columns cannot be resized or moved, because the header could not follow.

Measures of the draft, in points:

| Part | Measure |
|---|---|
| Columns | 92, the rest, 70, 104, 132, with a gap of 16 (the table gives 17), and 20 at the right end |
| Inset | 20 from the left edge for the day, the name of the header, and the first filter of the filter bar |
| Row | 9 above the first line, 10 below the second, 6 between the lines |
| Fonts | 11.5 for the text, 12.5 bold for the name, 14 semibold for the value, 10.5 for the second lines and the header, 9 bold with a spacing of 0.45 for the ribbon |
| Ribbon | 16 high from the left edge of the row to the end of the first column, with a notch of 7, its text 20 from the edge |

The table starts its first cell 6 points from the edge of the row (`DateCell.cellInset`), so the first cell adds 14 points before the day, and the ribbon reaches back to the edge with a negative padding, as `CategoryRibbon` does. The ribbon uses `RibbonShape` of the transaction list. The second lines use the color `Palette.detail` of the app, and the profit, the loss, and the old day use `Palette.green`, `Palette.red`, and `Palette.warning`, whose values are the light values of the draft. The dark values of the draft differ a little from the system colors that these colors keep in dark mode, which measured with enough contrast in #607.

Every modifier sits in a cell, never on a row (#519). The header is outside the table.

### Default colors of the asset classes (part 1, editable in part 4)

The draft gives four classes a color for light and dark mode. Part 1 uses them as the defaults and adds four in the same lightness, so that white text reads on each.

| Class | Light | Dark |
|---|---|---|
| Stocks | #2F6FD6 | #3F7FE0 |
| Funds | #7B4FC4 | #8B62D6 |
| Bonds | #B07C12 | #C08A1E |
| Real estate | #B0553A | #C4664A |
| Commodities | #5F8A2A | #6F9C34 |
| ETFs | #178A7D | #1F9C8E |
| Cryptocurrencies | #B8407A | #CC5590 |
| Others | #7A7A80 | #6E6E74 |

`AssetClassColors` in `App/Sources/Views/Format.swift` holds them next to `CategoryColors`. Part 4 adds the color that the user chooses, one value for both modes as the color of a category, which wins over the default.

### The WKN comes from the source (part 1)

The app already carries a national number in `Security.securityNumber`, and part 1 only shows it with the label "WKN". Nothing derives it, also not from the digits 4 to 9 of a German ISIN.

What hbci4java 4.1.17 delivers, read from the bytecode of `GVWPDepotList`, which parses field 35B of MT535 into `GVRWPDepotList.Entry.Gattung`:

- When the field starts with "ISIN ", hbci4java takes the rest of the first line as `isin`. When the second line starts with "/DE/", it takes the rest of that line as `wkn`. A number of another country, such as "/US/", stays out of `wkn` and becomes the start of `name`.
- When the field does not start with "ISIN ", hbci4java takes the first line from its fifth character as `wkn`, whatever its country code.
- The rest of the field is the name.

The helper sends `wkn` as hbci4java gives it (`position` in `Tools/FinTSHelper/FinTSHelper.java`), and `AccountResult.Position` maps it to `securityNumber`. So a FinTS position with an ISIN shows a WKN only when the bank sends a German number. An extension sends `securityNumber`, which the web banking API ([ADR 0004](../../../docs/decisions/0004-moneymoney-compatible-extension-api.md)) defines as the WKN, and `ResultMapping` maps it the same way. The MoneyMoney migration takes over no positions. Part 1 changes neither the helper nor a connector.

### Sorting (part 1)

`PortfolioSort` in `Sources/Domain/PortfolioRows.swift` is a key and a direction. The keys are the seven header lines: the day of the quote, the name, the quantity, the purchase price, the last quote, the value, and the profit or loss. `PortfolioSort.sorted(_:currency:)` sorts the positions by the number of the key as the row shows it, with the value and the profit or loss in the currency of the account, and with nil for a missing value. Positions with nil come last in both directions, and equal values keep the order of `Holding.isOrdered`, so the order never depends on the order in the database. Numbers in different currencies, and a percentage of a nominal amount next to a price, sort by their plain numbers, as a table of mixed rows does. Nil for the key means the order by name.

`AppModel.portfolioSort` keeps the choice while the user moves between portfolios. It is not saved, so the app starts with the order by name. A new order moves rows inside the same table and does not start the table over, because no row leaves it.

### Opening a position (part 1, the comment line in part 2)

`AppModel.openedPosition` holds the table key and the ID of the open position, as `AppModel.revealedRow` holds its key, so a position of another view never shows as open, and nothing needs to clear it when the view changes. A plain click on a row opens its position, and a click on the open position closes it. A click with ⌘ or ⇧ changes only the selection. The table reports no click on a row that is selected already, so `PositionClicks`, a view behind the table, watches the clicks of the window on the `NSTableView` and asks it for the row at the pointer. The keyboard moves the selection and leaves the open position alone.

Part 1 has no comments, so an open row looks like a closed one. The debug harness command `holdingclick <row>` clicks a row as a person does and logs the open position, so a check can see it. Part 2 adds the comment line in the name cell: below the two lines, after a gap of 7 points, it shows the speech bubble and the comment, and a negative trailing padding as wide as the four columns to the right lets the text run to the end of the row. The fixed widths of `PositionColumns` give that width without a geometry reader. The table measures the new height of the row from its cells.

### Comments (part 2)

`Holding.comment` is an optional text. `Holding.identify` hands it from the stored position to the delivered one, as it hands `userAssetClass`, and clears it on every delivered position first, because no source sends a comment. Migration `v36` adds the column `holding.comment`. `Store.setComment(_:ofHolding:)` and `Ledger.setComment(_:of:)` change it, in this order, through `AppModel`. The complete export writes the optional key `comment` of a holding, which does not change the format version (see [the export format](../../../docs/export-format.md)). `Holding.matches(_:)` also looks at the comment.

The menu command "Add Comment..." with ⇧⌘K opens the comment sheet of the selected position in a portfolio view, and of the selected transactions elsewhere. The sheet is the one of a transaction.

### Filters (part 3)

`TransactionFilter` gets `gain`, with `.all`, `.gains`, and `.losses`, and `quote`, with `.all` and `.outdated`. `positions(of:)` applies both. The sign of a profit or loss comes from `Format.gainSign(_:)` of the amount as the row shows it, so a profit that rounds to 0,00 € is neither a gain nor a loss. "Outdated" uses `Holding.oldQuoteDays(in:)` of all positions of the view, and a quote whose amount is 0. `positionHints` gets one line for each active filter, in the order of the bar. `hidesShownPositions(before:after:)` already compares the shown positions, so a refresh that turns a gain into a loss starts the table over. `resetHidden(in:)` leaves both filters alone, and the pin saves them with the other filters of `FilterBar`.

The status line shows "n of m Portfolio Items" while a filter hides positions, and "k of n" for a selection of two or more of the n shown positions.

### Asset classes as categories (part 4)

Migration `v37` adds the table `assetClassColor` with the raw value of a class and a color as hex text, and the complete export carries it. "Asset Class Settings..." opens a sheet with one row for each class: its ribbon, its name, and the color control of the category settings.

"Group by asset class" is a switch in the filter bar that the pin saves. The headings stand in the cells of the first row of each class, as the headings of "Group transactions by account" do (#519), so the table keeps one row for each position and the rows carry no modifier. The sort applies inside each section. A heading accepts a drop of positions, which calls `AppModel.setAssetClass(_:of:)`.

⌘K opens a picker of the classes in a portfolio view, the same command that opens the category picker elsewhere.

`Allocation` in `Sources/Domain/PortfolioRows.swift` sums the values of the positions of the view by class and by currency, with the share of each class rounded to two places, and never converts a currency. The popover shows one stacked bar for each currency. Its button sits above the switch "D" and "M" in `App/Sources/Views/ChartArea.swift`, so the history chart keeps its place.

## Risks / Trade-offs

- The columns of the positions can no longer be resized or moved, because the header is drawn outside the table. The draft has no resized columns, and the transaction table has hidden headers too.
- `PositionClicks` reads the clicks of the window, which a future SwiftUI version could offer as a click action of a row. Until then it is the one place that knows about `NSTableView`.
- A bank that sends a foreign national number without an ISIN shows it as a WKN, because hbci4java keeps it as `wkn`. No recorded answer of a bank shows this. The bank tests of issue #11 can check it.
- OpenSpec applies this delta only after `add-securities-accounts` and `redesign-portfolio-holdings` are archived, because it modifies their requirements.
- Saved searches do not keep the portfolio filters, against the text of #612, because a saved search shows no positions. The owner confirms this before part 3.
