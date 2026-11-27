# Proposal: Refine the portfolio view with ribbons, comments, filters, and an allocation

## Why

The change `redesign-portfolio-holdings` gave each position its columns and its asset class. In a walk-through on 27 November 2026 the owner found that the rows still read differently from the transaction rows: they touch the left edge of the window, the asset class is a small gray tag next to the ISIN, the header names only one of the two values of a column, and the WKN is missing. A position also cannot carry a note, the list cannot show only the gains or the outdated quotes, and the asset classes have no color and no overview. The owner approved draft 5 of the new view on 27 November 2026.

## What Changes

- **Rows in two lines (#610).** Each position is a row of five columns with two lines each: the day of the last quote over a ribbon with the asset class, the name in bold over the ISIN and the WKN, the quantity over "shares" or "nominal", the purchase price over the last quote, and the value over the profit or loss. The rows, the column header, and the filter bar start 20 points from the left edge.
- **Header and sorting (#610).** A column with two values has a header of two lines. A click on a line sorts the list by that value, and a second click reverses the order.
- **Open a position (#610, #611).** A click on a position opens it, and a second click or a click on another position closes it. An open position shows its comment over the full width of the row.
- **Security number (#610).** The row shows the security number that the source sends after the label "WKN". The app never derives it from the ISIN.
- **Comments (#611).** A position gets a comment, as a transaction does: "Add Comment..." and "Edit Comment..." with ⇧⌘K, a comment mark after the name, the search, and the complete export. The comment survives every refresh. The requirement "Comment on a position" and its scenario "Quantity changed" move here from the change `defer-v0.1-follow-ups`, which held them since v0.1.
- **Filters (#612).** The filter bar gets "Profit/Loss" with "Gains" and "Losses", and "Quote" with "Outdated". The status line counts the shown positions of all, such as "3 of 5 Portfolio Items".
- **Asset classes as categories (#613).** Each class has a color, with a default that the user can change. "Group by asset class" puts the positions under a heading for each class. ⌘K and a drop on a heading assign a class. A button next to the history chart opens the allocation of the portfolio by class. "Pie Chart" is disabled in a portfolio view.

The work comes in four parts, one for each issue. Part 1 (#610) builds the rows, the header, the sorting, and the opening of a position. Parts 2 to 4 follow after part 1 merges.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `securities-accounts`: changes the row, the quantity, the profit or loss, the day of the quote, the order, the search, the sum of the selected positions, and the filter "Asset class" of the changes `add-securities-accounts` and `redesign-portfolio-holdings`. Removes the asset class tag and the day of an old quote. Adds the ribbon, the security number, the header, the sorting, the opening of a position, comments, two filters with their lines and the pin, the colors of the classes, the grouping, the keyboard and drop assignment, the allocation, and the view modes of a portfolio view.

## Impact

- Milestone: v0.1
- Issues: #610, #611, #612, and #613, one for each part.
- Modules: `Domain` owns the order of the columns, the new filters and their lines, the comment of a `Holding`, the colors of the classes, the sections of the grouped list, and the allocation. `Storage` keeps the comment and the colors in new migrations, and the complete export carries both. `App` owns the rows, the header, the filter bar, the comment sheet, the class picker, the settings of the classes, and the allocation popover. `FinTS` and `ExtensionConnector` already deliver the WKN.
- Depends on the changes `redesign-portfolio-holdings` and `add-securities-accounts` for the portfolio view, `add-transaction-list` for the comment sheet and the category ribbon, `add-transaction-search-and-filters` for the filter bar, its lines, and its pin, `add-categories` for the color control, and `add-data-export` for the complete export.
- Takes over the pie chart of the change `add-portfolio-analysis` as the allocation popover. That change keeps the history chart, the export of positions, and manual positions.
- Takes over "Comment on a position" from the change `defer-v0.1-follow-ups`. The archive order is `add-securities-accounts`, `redesign-portfolio-holdings`, `defer-v0.1-follow-ups`, then this change.
- Decisions: [ADR 0014](../../../docs/decisions/0014-fints-through-hbci4java.md) for the WKN of FinTS, [ADR 0004](../../../docs/decisions/0004-moneymoney-compatible-extension-api.md) for the `securityNumber` of an extension, and [ADR 0012](../../../docs/decisions/0012-system-glass-for-window-chrome.md), because the filter bar and the header stay in the content area.

## Reference behavior

### Observed in MoneyMoney 2.5.3

- The context menu of a position has "Assign Asset Class" and "Add Comment...". See [analysis](../../../docs/research/moneymoney-analysis.md#context-menus-u).
- A transaction can carry a comment, and a transaction with a comment shows a yellow icon. See [analysis](../../../docs/research/moneymoney-analysis.md).
- The asset classes are shown in a pie chart (version history, 2.2.14).
- The category settings popover has a color control. See [analysis](../../../docs/research/moneymoney-analysis.md#category-u-w).
- Strings show "An asset class filter is active; some entries might be hidden."
- The [web banking API](https://moneymoney.app/api/webbanking/) gives a security the field `securityNumber`.

### Decided for Moneten

The owner decided these points on 27 November 2026:

- The asset classes stay the fixed list of eight. Each class has a default color, and the user can change it. The user cannot add, rename, or remove a class.
- The list offers both "Group by asset class" and the flat list.
- The allocation shows only after a click on its button, as a popover. The history chart stays above the list. The pie chart in place of the history chart that the change `add-portfolio-analysis` planned does not come.
- The security number comes only from the source: from FinTS through hbci4java, and from the `securityNumber` of an extension. The app never derives one from an ISIN, although a German ISIN contains the WKN.
- The day of the last quote shows in every row, at the left above the ribbon, and in the warning color when it is older than the newest quote day of the portfolio. The time of the quote does not show. This replaces the day of an old quote below the quote of `redesign-portfolio-holdings`.
- The asset class shows as a ribbon in the color of the class, as the category of a transaction does, and no longer as a tag next to the ISIN.
- A click on a position opens it, as the draft shows. A position opens only by a click, not by the keyboard.
- The quantity has the word "shares" in a second line below the number, for every kind of security, also for a fund, a fraction, or a cryptocurrency such as Bitcoin. This reverses the decision of 26 November 2026 in `redesign-portfolio-holdings` that the quantity shows without the word: the approved draft 5 of 27 November 2026 shows the word in the second line, where it names the unit of the number above.

These points were not observed and are decided here:

- The label of the security number is "WKN", for every source. The web banking API defines `securityNumber` as the WKN, and a German bank sends the WKN. A source can send a number of another country: hbci4java keeps the first number of a security without an ISIN whatever its country (design). The app shows it under the same label, because it cannot tell the country of every number, and it never hides a number that the source sends.
- The second line of the column header reads "Profit/Loss", the name of the column since `add-securities-accounts`. The header of the view keeps "Profit" and "Loss" for the total, as `redesign-portfolio-holdings` decided, and the rows keep no word.
- Each line of a two-line header sorts by its own value, so "Purchase price" and "Last quote" sort separately. A position without the value comes last in both directions, equal values keep the order by name, and a quote of 0 sorts as 0. The order stays while the app runs and starts by name after a restart.
- "Gains" shows a profit above 0,00 and "Losses" a loss below it. A position with a profit or loss that shows as 0,00, or without a purchase price, is in neither. "Outdated" takes the old quote days of the row and the quotes of 0, which the row shows as "–".
- The filters "Profit/Loss" and "Quote" and "Group by asset class" stay while the user moves between portfolios, and the pin of the filter bar saves them with the other filters and resets them when it is turned off. Issue #612 asks that saved searches keep them. A saved search shows transactions of all accounts and never positions, so this change keeps them with the pin instead. The owner confirms this choice before part 3 starts.
- A comment belongs to the position, as the user's asset class does. It survives every refresh and every change of the quantity, and it goes with the position when the position leaves the portfolio. A security that comes back starts without a comment.
- The settings of the asset classes open only with "Asset Class Settings..." at the end of the submenu "Asset Class" of a position. They list the eight classes with a color each and "Restore Default Colors". A chosen color is one color for light and dark mode, as the color of a category.
- The default colors reach a contrast of 4.5:1 for white text in both modes. The draft's colors of bonds, ETFs, and others are darkened for that, and every class has one color for both modes.
- The allocation lists the classes in the order of the menu, and a click on a class sets the filter "Asset class". It counts every position of the view, whatever the filters show, so it shows the whole portfolio also while a filter is on, unlike the pie chart of `add-portfolio-analysis` that followed the filter. It shows one bar for each currency of the values.
- In a portfolio view "Pie Chart" is disabled, because the allocation popover shows the split by class. The mode "Pie Chart" of the account views shows the history chart there.
