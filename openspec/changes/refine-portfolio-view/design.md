# Design

## Context

The change `redesign-portfolio-holdings` (#605, #607, #609) built the list of positions in `App/Sources/Views/HoldingsView.swift` as a SwiftUI `Table` with six columns and native headers, a tag with the asset class next to the ISIN, and the day of a quote only when it is old. The owner approved draft 5 of the next step on 27 November 2026. The draft is an HTML page with made-up data on the owner's Mac. Its measures are in this design, so no part needs the file.

This change modifies requirements of changes that are not archived yet:

- Of `redesign-portfolio-holdings`: "Position row content", "Quantities as units or as a nominal amount", "Profit or loss", and "Filter by asset class". It removes "Asset class tag" and "Day of an old quote".
- Of `add-securities-accounts`, which `redesign-portfolio-holdings` does not touch: "Order of positions", "Search positions", and "Sum of the selected positions".
- Of `add-portfolio-analysis`: it takes over "Pie chart by asset class" and "The charts follow the asset class filter" as the allocation popover and removes both from that change. The allocation counts every position of the view, the opposite of the removed requirement, because the popover is an overview of the whole portfolio.
- Of `defer-v0.1-follow-ups`: it takes over "Comment on a position" with its scenario "Quantity changed", which moves into "A comment survives a refresh", and removes it from that change, so that the capability gets the requirement once.

OpenSpec applies the delta of a change to the specs when it archives the change, so the order is `add-securities-accounts`, `redesign-portfolio-holdings`, `defer-v0.1-follow-ups`, and then this change. `add-portfolio-analysis` has the milestone "later" and adds only requirements that this change does not touch.

The view modes of `add-charts` ("Three view modes") stay for every other view. "View modes of a portfolio view" in this change is the exception for portfolios.

## Scope

Four parts, one pull request each, in this order. Parts 2 to 4 each change `HoldingsView.swift`, so they wait for part 1.

- Part 1 (#610): the rows, the inset, the ribbon in the default color of its class, the security number, the header, the sorting, and the opening of a position. The opening has no visible effect yet, because no position has a comment before part 2.
- Part 2 (#611): the comment, its storage and export, the sheet, the comment mark, the comment line of an open position, and the search.
- Part 3 (#612): the filters "Profit/Loss" and "Quote", their lines, the count of the status line, the filters across views, and the pin.
- Part 4 (#613): the editable colors, the grouping, ⌘K, the drop on a heading, the allocation, and the view modes of a portfolio view.

## Decisions

### The table stays, with a header of its own (part 1)

The list stays a SwiftUI `Table`. It gives the selection with ⌘ and ⇧, the keyboard, the context menu of the selection, VoiceOver, and the `NSTableView` that the debug harness and `App/Sources/PerfCheck.swift` look for by its column "Quantity". A list of own rows would have to build all of that again.

The native header has one line and cannot show "Purchase price" over "Last quote". So the table hides its header with `.tableColumnHeaders(.hidden)`, as the transaction table does, and `HoldingsHeader` draws the header above it in SwiftUI. Header and table share one set of column widths, `PositionColumns`: every column except "Name" has a fixed width, and "Name" takes the rest. The header lays out its cells with the same widths and the same gap between cells as the table, 17 points. The columns cannot be resized or moved, because the header could not follow.

A classic scroll bar, which macOS shows with a mouse attached and the default setting "Automatically based on mouse or trackpad", takes its width from the table but not from the header. The view of the table reports the width of its scroll view less the width of its clip view, 0 with an overlay scroll bar, and the header adds it as trailing padding. The view reports it again when the clip view changes its frame and when the preferred style of the scroll bars changes, so the right columns stay under their headers.

Measures of the draft, in points:

| Part | Measure |
|---|---|
| Columns | 92, the rest, 70, 104, 132, with a gap of 16 (the table gives 17), and 20 at the right end. The first column is 95 since part 4, as the date column of a transaction. |
| Inset | 20 from the left edge for the day, the name of the header, and the first filter of the filter bar |
| Row | 9 above the first line, 10 below the second, 6 between the lines |
| Fonts | 11.5 for the text, 12.5 bold for the name, 14 semibold for the value, 10.5 for the second lines and the header |
| Ribbon | The category ribbon of a transaction: 113 wide and 14 high from the left edge of the row, with a notch of 7, its text 10 bold with a spacing of 0.2 and 4 from the edge (part 4, the owner's request of 27 November 2026) |

The table starts its first cell 6 points from the edge of the row (`DateCell.cellInset`), so the first cell adds 14 points before the day, and the ribbon reaches back to the edge with a negative padding, as `CategoryRibbon` does. Since part 4 both use one view, `Ribbon`, with one size, one font, and one fill, and the first column of the positions is as wide as the date column of a transaction, 95 points, so the ribbon ends in the gap before the name and the name starts 118 points from the edge, as in the transaction list. The second lines use the color `Palette.detail` of the app, and the profit, the loss, and the old day use `Palette.green`, `Palette.red`, and `Palette.warning`, whose values are the light values of the draft. The dark values of the draft differ a little from the system colors that these colors keep in dark mode, which measured with enough contrast in #607.

Every modifier sits in a cell, never on a row (#519). The header is outside the table.

### Default colors of the asset classes (part 1, editable in part 4)

Part 1 gave each class a color of the draft. In part 4 the owner asked that the ribbon of a position look exactly like the category ribbon of a transaction, so the defaults are the first eight colors of `CategoryColors.palette`, one for each class in the order of the menu: blue, orange, green, pink, purple, teal, yellow, and indigo. They are system colors, a little lighter in dark mode, as the colors of the categories are.

Every ribbon mutes its color toward gray, `color.mix(with: Color(white: 0.6), by: 0.5)` as the category ribbon did before, and so do the dot of a class in its heading and its share in the allocation, so a class looks the same everywhere. `RibbonColor.fill(of:)` in `Domain` computes this mix in OKLab, the space in which SwiftUI mixes two colors, and `RibbonColor.text(on:)` takes white or near-black (#1D1D1F) for the text, whichever has the higher contrast ratio of WCAG on the muted fill. The settings accept any color, as the category settings do, so a light color that the user chose, such as #FFFFFF or #FFD60A, gets near-black text. The rule holds for the category ribbon too, and a muted mid-tone color such as the blue of the palette gets near-black text by it, where it had white text before.

`AssetClassColors` in `App/Sources/Views/Format.swift` holds the defaults next to `CategoryColors`. The color that the user chooses in part 4 wins over the default.

### The security number comes from the source (part 1)

The app already carries a national number in `Security.securityNumber`, and part 1 only shows it with the label "WKN". Nothing derives it, also not from the digits 4 to 9 of a German ISIN. The spec calls it the security number everywhere, also in the details of `defer-v0.1-follow-ups`, and "WKN" is only its label.

What hbci4java 4.1.17 delivers, read from the bytecode of `GVWPDepotList`, which parses field 35B of MT535 into `GVRWPDepotList.Entry.Gattung`:

- When the field starts with "ISIN ", hbci4java takes the rest of the first line as `isin`. When the second line starts with "/DE/", it takes the rest of that line as `wkn`. A number of another country, such as "/US/", stays out of `wkn` and becomes the start of `name`.
- When the field does not start with "ISIN ", hbci4java takes the first line from its fifth character as `wkn`, whatever its country code. "/US/123456789" gives `wkn` "123456789".
- The rest of the field is the name.

The helper sends `wkn` as hbci4java gives it (`position` in `Tools/FinTSHelper/FinTSHelper.java`), and `AccountResult.Position` maps it to `securityNumber`. So a FinTS position with an ISIN has a security number only when the bank sends a German one, and a position without an ISIN can have a foreign one. An extension sends `securityNumber`, which the web banking API ([ADR 0004](../../../docs/decisions/0004-moneymoney-compatible-extension-api.md)) defines as the WKN, and `ResultMapping` maps it the same way. The MoneyMoney migration takes over no positions.

The app shows every security number under "WKN". To show the label only for a German number, the app would need the country of the number, which hbci4java drops and an extension never sends, and hiding the number would lose what the source sent. `securityNumber` is also a key of `Holding.identify` for a position without an ISIN, so the helper keeps sending what hbci4java gives. A test of `FinTSConnectorTests` with a position without an ISIN and the `wkn` "123456789" pins this down.

### Sorting (part 1)

`PortfolioSort` in `Sources/Domain/PortfolioRows.swift` is a key and a direction. The keys are the seven header lines: the day of the quote, the name, the quantity, the purchase price, the last quote, the value, and the profit or loss. `PortfolioSort.sorted(_:currency:)` sorts the positions by the number of the key as the row shows it, with the value and the profit or loss in the currency of the account, and with nil for a missing value. A quote of 0 is the number 0. Positions with nil come last in both directions, and equal values keep the order by name in both directions. The sort is stable, so two positions of the same security in two portfolios keep the order of the ledger in both directions. Numbers in different currencies, and a percentage of a nominal amount next to a price, sort by their plain numbers, as a table of mixed rows does. Nil for the key means the order by name.

`AppModel.portfolioSort` keeps the choice while the user moves between portfolios. It is not saved, so the app starts with the order by name. `AppModel.sortPositions(by:)` computes the new order inside the change of `AppModel.replacingTable`, so a quick second click builds on the first, and the table starts over with the placeholder in between. In place, SwiftUI turns a new order into moves of rows and measures each moved row: the perf scenario "sort-many-positions" took 2.4 seconds to reverse 500 positions that way. A new table measures only the rows on screen.

A refresh of a sorted list can change the order without removing a row, such as new quotes in a list sorted by quote. `TransactionFilter.movesShownPositions(before:after:sort:currency:)`, next to `hidesShownPositions(before:after:)`, tells whether the positions that the list shows before and after the refresh stand in another order. When either rule holds, the refresh starts the table over, as a refresh that removes a shown position does (#135, #151).

### Opening a position (part 1, the comment line in part 2)

`AppModel.openedPosition` holds the table key and the ID of the open position, as `AppModel.revealedRow` holds its key, so a position of another view never shows as open, and nothing needs to clear it when the view changes. A plain click on a row opens its position, and a click on the open position closes it. A click with ⌘, ⇧, ⌃, or ⌥, a double click, and a click on a scroll bar open nothing. The table reports no click on a row that is selected already, so `PositionClickWatcher`, a view behind the table with its frame, watches the clicks of the window with a local monitor. It first checks that the click is inside its own frame, and it keeps a weak reference to its table, so a click elsewhere costs no search through the views. The keyboard moves the selection and leaves the open position alone.

Part 1 has no comments, so an open row looks like a closed one. The debug harness command `holdingclick <row>` hands a click to the watcher and to the window and logs the open position, so a check can see it, and `holdingsort <line>` does what a click on a line of the header does. Part 2 adds the comment line in the name cell: below the two lines, after a gap of 7 points, it shows the speech bubble and the comment, which runs over the columns to the right to the end of the value. The table measures a row with the ideal width of its cells and shows one line in a cell by default, so the line has a width of its own and no line limit. `CommentLine` gives the width: the width of the table less a classic scroll bar, the fixed columns before the name, and the insets. Only the open row reads it, so a new width of the window redraws that row and not the table. The table measures the new height of the row from its cells.

Part 1 opened a position on the mouse-down. Part 4 adds dragging positions onto a heading, and a drag would then open the position it starts on, so the opening moves to the mouse-up within the same row. The table tracks the mouse in a loop of its own until the button goes up or a drag starts, and a monitor of the window sees no event of that loop. So the watcher notes the row on the mouse-down and looks again when the run loop is back in its default mode: a drag that started in between counts in `AppModel.positionDrags` and opens nothing, a mouse-up over another row opens nothing, and when no loop took the mouse, a monitor waits for the mouse-up.

### Comments (part 2)

`Holding.comment` is an optional text. `Holding.identify` hands it from the stored position to the delivered one, as it hands `userAssetClass`, and clears it on every delivered position first, because no source sends a comment. A position whose quantity changes keeps its ID, so it keeps its comment. Migration `v36` adds the column `holding.comment`. `Store.setComment(_:ofHolding:)` and `Ledger.setComment(_:of:)` change it, in this order, through `AppModel`. The complete export writes the optional key `comment` of a holding, which does not change the format version (see [the export format](../../../docs/export-format.md)). `Holding.matches(_:)` also looks at the comment.

The menu command "Add Comment..." with ⇧⌘K opens the comment sheet of the selected position in a portfolio view, and of the selected transactions elsewhere. The sheet is the one of a transaction. A comment belongs to one position, so the command and the item of the context menu act only while one position is selected or clicked; with several, the context menu has no item and the command is disabled. `AppModel.selectedPositions` holds the selected positions for the command. A new comment that takes a position out of a search that found it by its old comment starts the table over, as a new asset class does. The speech bubble uses the note color of the draft, `Palette.note`.

### Filters (part 3)

`TransactionFilter` gets `gain`, with `.all`, `.gains`, and `.losses`, and `quote`, with `.all` and `.outdated`. `positions(of:)` applies both. The sign of a profit or loss comes from `Format.gainSign(_:)` of the amount as the row shows it, so a profit that rounds to 0,00 € is neither a gain nor a loss, and a position without a purchase price has no gain. "Outdated" uses `Holding.oldQuoteDays(in:)` of all positions of the view, and a quote whose amount is 0. `positionHints` gets one line for each active filter, in the order of the bar. `hidesShownPositions(before:after:)` already compares the shown positions, so a refresh that turns a gain into a loss starts the table over.

`resetHidden(in:)` leaves both filters alone, so they stay between views. The pin saves them and "Group by asset class" with the other filters of `FilterBar`, and turning the pin off sets them back, as it sets back the other filters. The filter "Asset class" is never saved, because its entries are the classes of the view.

The status line shows "n of m Portfolio Items" while a filter hides positions. A selection of two or more shows "k of n", the selected of the n shown positions, as the status line does today. The spec states both in "Count of a filtered portfolio" and in the modified "Sum of the selected positions".

### Asset classes as categories (part 4)

Migration `v37` adds the table `assetClassColor` with the raw value of a class and a color as hex text, and the complete export carries it. "Asset Class Settings..." at the end of the submenu "Asset Class" opens a sheet with one row for each class: its ribbon, its name, and the color control of the category settings. No other menu has the command, because the classes have no row in the sidebar.

"Group by asset class" is a switch in the filter bar. The headings stand in the cells of the first row of each class, as the headings of "Group transactions by account" do (#519), so the table keeps one row for each position and the rows carry no modifier. The sort applies inside each section. A heading accepts a drop of positions, which calls `AppModel.setAssetClass(_:of:)`.

⌘K opens a picker of the classes in a portfolio view, the same command that opens the category picker elsewhere.

`Allocation` in `Sources/Domain/PortfolioRows.swift` sums the values of all positions of the view by class and by currency, whatever the filters and the search show, with the share of each class in two places, and never converts a currency. The shares of a bar add up to exactly 100 %: each is rounded down, and the hundredths that are left go to the largest remainders, the first class in the order of the menu on a tie. The popover shows one stacked bar for each currency. Its button sits above the switch "D" and "M" in `App/Sources/Views/ChartArea.swift`, so the history chart keeps its place.

In a portfolio view "Pie Chart" is disabled in the View menu and in the toolbar, and the mode "Pie Chart" of the account views shows the history chart there. The view does not change the mode that the app remembers for account views, so "Giro" still shows its pie chart.

## Risks / Trade-offs

- The columns of the positions can no longer be resized or moved, because the header is drawn outside the table. The draft has no resized columns, and the transaction table has hidden headers too.
- `PositionClickWatcher` reads the clicks of the window, which a future SwiftUI version could offer as a click action of a row. Until then it is the one place that knows about `NSTableView`. A click that the debug harness sends never passes the monitor of the window, so the harness hands it to the watcher directly, and only a click of a person checks the monitor.
- A bank that sends a foreign national number without an ISIN shows it under "WKN", because hbci4java keeps it as `wkn`. No recorded answer of a bank shows this. The bank tests of issue #11 can check it.
- OpenSpec applies this delta only after the changes that it modifies are archived, in the order of the context.
- Saved searches do not keep the portfolio filters, against the text of #612, because a saved search shows no positions. The owner confirms this before part 3.
