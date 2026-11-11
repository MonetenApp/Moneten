# Proposal: Show securities accounts with their positions

## Why

For many users, securities hold most of their wealth. A banking app that shows only current accounts shows half of the picture. Users of MoneyMoney expect to see each position with its value and its gain without a login at the broker.

## What Changes

- An account of the type "Portfolio" shows a list of positions in place of a transaction list.
- The app fetches positions through FinTS and takes the positions that extensions return, including crypto and other assets.
- Each position shows its name, value, quantity, purchase price, last quote, and profit or loss as an amount and as a percentage.
- The user can enter or correct the purchase price when the bank sends none.
- The value of a portfolio counts in the sums of the sidebar and in the balance chart of its account group. For that the app records the value once a day.

## Capabilities

### New Capabilities

- `securities-accounts`: portfolio accounts, their positions, the valuation of positions, and how the portfolio value enters sums and charts.

### Modified Capabilities

None.

## Impact

- Milestone: v0.2
- Issues: #31
- Modules: `Domain` owns the types for securities, quotes, and holdings and the valuation rules. `FinTSConnector` fetches and parses holdings. `ExtensionConnector` maps the securities of an extension. `Storage` keeps positions and the daily value. `App` owns the portfolio view.
- Depends on the change `add-fints-banking` for the bank dialog, `add-account-refresh` for when a refresh runs and how errors show, `add-web-banking-extensions` for the securities that an extension returns, `add-account-management` for the account type, and `add-main-window` for the sidebar and the status line.
- Decisions: [ADR 0003](../../../docs/decisions/0003-fints-through-hbci4swift.md), [ADR 0004](../../../docs/decisions/0004-moneymoney-compatible-extension-api.md).

## Reference behavior

### Observed in MoneyMoney 2.5.3

- A portfolio view lists one row for each position with the name, the value, the quantity, the purchase price, the last quote, and the profit or loss as an amount and a percentage. The status line shows the number of portfolio items and their sum. See [analysis](../../../docs/research/moneymoney-analysis.md#portfolio-u-s-c).
- The context menu of a position has "Add Comment...", "Edit Purchase Price...", and commands for the asset class, printing, and export. See [analysis](../../../docs/research/moneymoney-analysis.md#context-menus-u).
- Strings show the detail fields "Quantity", "Last quote", "Market", "Market value", "Trade date", "Purchase price", "Purchase rate", "Purchase amount", and "Purchase date", the labels "Profit" and "Loss", and the empty states "No portfolio items found." and "No matching portfolio items found."
- The securities structure of the [web banking API](https://moneymoney.app/api/webbanking/) has a name, ISIN, security number, a quantity that is a number of units or a nominal amount with a currency, a price and a purchase price each with an optional currency and exchange rate, the value in the account currency, the value in the original currency, the market, and the time of the quote.
- The securities are fetched through HBCI (version history, 2.1.5). A quantity keeps its decimal places (version history, 2.1.10).
- The user can enter a purchase price to compute the profit or loss (version history, 2.1.12), also as a total purchase amount (version history, 2.2.16). The percentage is shown (version history, 2.2.1).
- Quotes in a foreign currency are converted to euro, and a purchase price that was computed with an unsuitable exchange rate can be corrected with "Edit Purchase Price..." (version history, 2.3.0).
- A group that holds only portfolios shows the total gain of its securities in the upper right corner (version history, 2.2.14).
- An empty portfolio is shown as empty (version history, 2.5.2).
- The app stores the portfolio value once a day (version history, 2.2.14).
- Removing a portfolio account warns that all portfolio items are removed and that the portfolio history cannot be restored (strings).

### Decided for Moneten

- The daily record of the portfolio value is part of this change, because issue #31 asks that securities count in the balance chart. The charts of the portfolio itself come with the change `add-portfolio-analysis`.
- The app uses only exchange rates that the bank or the extension delivers. It fetches no exchange rates itself. A value that cannot be converted stays in its own currency, and sums keep one total for each currency. This follows the `Totals` type in [data model](../../../docs/data-model.md).
- A purchase price that the user enters wins over the value from the bank until the user removes it. MoneyMoney's rule was not observed.
- Positions are sorted by name. The order in MoneyMoney was not observed.
- The search field filters positions by name, ISIN, and security number. Which fields MoneyMoney searches was not observed.
- When a refresh fails, the app keeps the positions of the last successful refresh and shows their date. MoneyMoney's behavior was not observed.
- A position without a purchase price shows no profit or loss and is left out of the total gain.
