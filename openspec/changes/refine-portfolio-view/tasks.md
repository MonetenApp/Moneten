# Tasks

A task is checked only when a test or a check in the running app shows the behavior. Screenshots come from the debug harness with the login "depot" of `scripts/fake-fints-helper.sh`, in light and dark mode.

## 1. Part 1: rows, header, sorting, opening (#610)

- [x] 1.1 Test first, then `PortfolioSort`: each header line sorts by its own value in both directions, a position without the value comes last both times, and equal values keep the order by name. PortfolioRowsTests "Each header line sorts by its own value, ascending on the first click and descending on the next", "A position without the value comes last in both directions, and equal values keep the order by name", and "A click on a header line sorts ascending, a second click on it descending, and a click on another line ascending".
- [x] 1.2 `PositionColumns` and `HoldingsHeader`: the header of two lines above the table with the widths of the table, and the table without its own header. A click on a line sorts, and the line shows the direction. `AppModel.portfolioSort` keeps the order between portfolio views. The harness command `holdingsort` and the screenshots sorted by "Value" and "Last quote".
- [x] 1.3 Rows of the draft: the day over the ribbon, the name in bold over "ISIN" and "WKN", the quantity over "shares" or "nominal", the purchase price over the last quote, the value over the profit or loss in one line. The old day and its last quote in the warning color. FormatTests "A quantity of units shows as a plain number over shares, a nominal amount with its currency over nominal", and the screenshots.
- [x] 1.4 The inset of 20 points for the rows, the header, and the filter bar. Screenshots: the day, "Quote date", and "Asset class:" start 20 points from the edge of the list.
- [x] 1.5 `AssetClassColors` with the default colors of the design, and the ribbon in the color of its class. Screenshots.
- [x] 1.6 The WKN only when the source sends it: checked in the bytecode of hbci4java 4.1.17 (design), and a row of the fake bank without a WKN shows none. Screenshots.
- [x] 1.7 `AppModel.openedPosition` and `PositionClickWatcher`: a click opens, a second click or a click on another position closes, a click with ⌘ or ⇧ leaves it alone. The harness command `holdingclick` opens, closes, and opens a position again, and moves the open position to another row.
- [x] 1.8 A perf scenario in `App/Sources/PerfCheck.swift` for a new order of many positions, which must move the rows in place: "sort-many-positions".
- [x] 1.9 Light and dark screenshots for the pull request.

## 2. Part 2: comments (#611)

- [ ] 2.1 Test first, then `Holding.identify`: a refresh keeps the comment of the stored position, and a security that comes back has none. AssetClassTests or a new suite.
- [ ] 2.2 `Storage`: migration `v36`, `HoldingRecord`, `Store.setComment(_:ofHolding:)`, and `Ledger.setComment(_:of:)`. HoldingStoreTests.
- [ ] 2.3 The complete export carries the comment, and `docs/export-format.md` describes it. AllDataTests.
- [ ] 2.4 The search finds a position by its comment. PortfolioRowsTests.
- [ ] 2.5 "Add Comment..." and "Edit Comment..." in the context menu and ⇧⌘K, with the sheet of a transaction. A harness check.
- [ ] 2.6 The comment mark after the name with its tooltip, and the comment line of an open position. Screenshots of an open row.

## 3. Part 3: filters (#612)

- [ ] 3.1 The owner confirms that the pin, and not a saved search, keeps the two filters (proposal).
- [ ] 3.2 Test first, then `TransactionFilter.gain` and `TransactionFilter.quote` in `positions(of:)`: a profit of 0 is neither a gain nor a loss, and "Outdated" takes old days and quotes of 0. PortfolioRowsTests.
- [ ] 3.3 The lines below the list and "n of m Portfolio Items" in the status line. PortfolioRowsTests and screenshots.
- [ ] 3.4 Both filters in the filter bar, kept between portfolio views and saved by the pin. The harness command `filterbar`.

## 4. Part 4: asset classes as categories (#613)

- [ ] 4.1 `Storage`: migration `v37` with the colors of the classes, and the complete export. HoldingStoreTests and AllDataTests.
- [ ] 4.2 "Asset Class Settings..." with a color for each class and "Restore Default Colors". Screenshots in light and dark mode with white text on every ribbon.
- [ ] 4.3 Test first, then the sections of "Group by asset class" with the count, the value, and the profit or loss of each class. PortfolioRowsTests.
- [ ] 4.4 The grouped list with its headings in the cells, the switch in the filter bar, and the pin. A perf scenario for the grouped list.
- [ ] 4.5 ⌘K opens the class picker in a portfolio view, and a drop on a heading assigns the class. Harness checks.
- [ ] 4.6 Test first, then `Allocation`: the shares by class and by currency, rounded to two places. PortfolioRowsTests.
- [ ] 4.7 The allocation button above "D" and "M", its popover, and a click on a class that sets the filter "Asset class". Screenshots.
