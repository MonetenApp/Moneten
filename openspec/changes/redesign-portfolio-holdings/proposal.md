# Proposal: Show positions in clear columns with their asset class

## Why

The list of positions shows every field, but a reader has to work to see what matters. "40 shares" repeats what the column header says, every quote carries its day although almost all days are the same, and the words "Profit" and "Loss" in every row push the numbers aside. A user also cannot see or filter what kind of asset a position is, although the bank often sends the class of the security.

## What Changes

- Every position has one of eight asset classes: "Stocks", "Funds", "Bonds", "Real estate", "Commodities", "ETFs", "Cryptocurrencies", and "Others".
- The class comes from the bank. A FinTS bank that sends the classification code of the security (CFI, ISO 10962) gives the class. A position without a class from its source is "Others". The app never guesses a class from the name.
- The user can choose the class of a position with the submenu "Asset Class" in its context menu. The choice wins over the class of the source and survives every refresh. "Automatic" removes the choice.
- The name column shows a small tag with the class next to the ISIN. The filter bar above the positions gets the filter "Asset class".
- The quantity shows as a plain number, such as "646". A nominal amount keeps its currency, such as "5.000,00 €".
- The day of the last quote shows only when it is older than the newest quote day of the portfolio, in the warning color. A quote of 0 shows "–".
- The value is semibold. The profit or loss shows a profit in green with "+" and a loss in red with "−", and the percentage below the amount, without the words "Profit" and "Loss" in the row. The header of the view keeps its text.
- The asset class requirements of the change `add-portfolio-analysis` move here, with the owner's decisions of 26 November 2026. That change keeps the pie chart, the history chart, the export, and manual positions.

The work comes in two parts. Part 1 builds the data: the asset class of a position, the class from FinTS, its storage, and the complete export. Part 2 builds the view: the columns, the tag, the filter, and the context menu.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `securities-accounts`: adds asset classes to positions, where the class comes from, the user's choice, the tag, and the filter. Changes the content of a row, the quantity, and the profit or loss of the change `add-securities-accounts`, which introduces the capability.

## Impact

- Milestone: v0.1
- Issues: none yet.
- Modules: `Domain` owns `AssetClass` and the class of a `Holding`. `FinTS` and `Tools/FinTSHelper` read the classification code of MT535 and map it to a class. `Storage` keeps the class of the source and the user's choice, and the complete export carries both. `App` owns the columns, the tag, the filter, and the context menu.
- Depends on the change `add-securities-accounts` for positions and the portfolio view, `add-main-window` for the filter bar, and `add-data-export` for the complete export.
- Decisions: [ADR 0014](../../../docs/decisions/0014-fints-through-hbci4java.md) for the FinTS helper, [ADR 0004](../../../docs/decisions/0004-moneymoney-compatible-extension-api.md) for the fields of an extension result.

## Reference behavior

### Observed in MoneyMoney 2.5.3

- The portfolio view has a filter "Asset class" with "Show All" and one entry for each class. See [analysis](../../../docs/research/moneymoney-analysis.md#portfolio-u-s-c).
- The asset classes are "Stocks", "Funds", "Bonds", "Real estate", "Commodities", "ETFs", "Cryptocurrencies", and "Others". The class for cryptocurrencies is predefined (version history, 2.4.6).
- The context menu of a position has "Assign Asset Class". See [analysis](../../../docs/research/moneymoney-analysis.md#context-menus-u).
- A position shows its fields in one line, with the quantity as a number of shares, the day of each quote, and the labels "Profit" and "Loss" (owner review, 26 November 2026, and strings).
- Strings show "Unassigned" for a security without a class.
- The [web banking API](https://moneymoney.app/api/webbanking/) gives a security no asset class, so an extension cannot send one.

### Decided for Moneten

- The list keeps its separate columns, with headers, instead of one line for each position. The owner reviewed each column on 26 November 2026.
- The quantity shows without the word "shares", because the column header names it.
- The day of the last quote shows only when it is older than the newest quote day of the portfolio. A day that equals the others tells nothing.
- The row shows a profit or loss by its color and its sign, without a word. The header of the view keeps "Profit" and "Loss".
- The class comes from the bank first. A position without one is "Others", not "Unassigned", so every position has exactly one of the eight classes and the filter needs no extra entry.
- The app never guesses a class from the name of a security. A name such as "Musterwelt ETF" stays "Others" until the bank or the user gives a class.
- The class belongs to the position, not to the security across all portfolios. The change `add-portfolio-analysis` had planned the other way; the owner decided for the position on 26 November 2026.
- The submenu is called "Asset Class", and "Automatic" removes the user's choice. MoneyMoney's way to remove an assignment was not observed.
