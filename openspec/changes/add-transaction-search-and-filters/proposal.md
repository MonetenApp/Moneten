# Proposal: Search and filter transactions

## Why

Users look up single payments often, for a tax return, a dispute, or a warranty. With several years of history in one database, the answer must appear while the user types, together with the sum of what was found.

## What Changes

- The search field filters the current list while the user types and shows the count and the sum of the results.
- The search covers all text of a transaction and its comment, finds text inside words, and finds exact amounts.
- "Search for" in the context menu lists all transactions with the same counterparty.
- The filter bar filters by period, status, amount, and category or account.
- The period filter applies to all accounts and categories at once.
- The pin keeps the other filters when the user changes the view.
- A search with its filters can be saved under a name.

## Capabilities

### New Capabilities

- `transaction-search-and-filters`: the live search, the filters for transactions, how they combine, and saved searches.

### Modified Capabilities

None.

## Impact

- Milestone: v0.1
- Issues: #20
- Modules: `Storage` owns the search index and the queries. `Domain` owns text folding and the filter model. `App` owns the search field and the filter bar.
- Depends on the change `add-main-window` for the search field, the filter bar frame, the pin control, and the status line.
- Depends on the change `add-transaction-list` for the list.
- Depends on the change `add-categorization-rules` for the expression language.
- The filters of the portfolio, outbox, scheduled, and statements views belong to the changes for those views.
- Decisions: none apply.

## Reference behavior

### Observed in MoneyMoney 2.5.3

- Results appear while the user types, and the sum stands in the bar at the bottom ([feature page](https://moneymoney.app/)).
- The search finds text at the start, in the middle, and at the end of a word, and it finds exact amounts with decimals (version history, 2.2.15).
- The search finds umlauts in both Unicode forms (version history, 2.4.27).
- "Find in Transactions..." has the shortcut ⌘F. See [analysis](../../../docs/research/moneymoney-analysis.md#menus-and-keyboard-shortcuts-u).
- The context menu of a transaction starts with "Search for" and the counterparty name. See [analysis](../../../docs/research/moneymoney-analysis.md#context-menus-u).
- The filter bar has "Period", "Status", "Amount", and "Category" in account views, and "Account" in place of "Category" in category views. All values are listed in the [analysis](../../../docs/research/moneymoney-analysis.md#main-window-u).
- "Custom..." opens a date range for the period and a range with "min. amount" and "max. amount" for the amount (interface strings and popovers).
- A changed period applies to all accounts and categories (version history, 2.2.3).
- The pin with the tooltip "Save filter bar" keeps the filter bar between views (version history, 2.4.9).
- For each kind of filter there is a line that says the filter is active and that some entries might be hidden (interface strings).

### Decided for Moneten

- Several words in the search field must all occur. The search field also accepts the expression language of the categorization rules. Neither was observed in MoneyMoney.
- The search folds case and umlauts in the same way as the rules.
- "Search for" keeps the current view and searches inside it. The scope in MoneyMoney was not observed.
- Without the pin, the status, amount, category, and account filters return to "Show All" when the user changes the view. Only the effect of the pin itself is documented.
- A category filter on a category group includes the categories below it.
- The line about an active filter stands below the last row of the list. Its place in MoneyMoney was not observed.
- Saved searches come from issue #20. MoneyMoney has none.
- The target of 100 milliseconds for 50,000 transactions comes from issue #20.
