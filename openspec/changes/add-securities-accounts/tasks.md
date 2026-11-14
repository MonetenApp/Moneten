# Tasks

One task per requirement of the spec. A task is checked only when a test or a check in the running app shows the behavior. Issue #31 builds the v0.1 part that `design.md` names. "FinTSHelper self-test" is `scripts/build-fints-helper.sh`, which CI runs.

## 1. Requirements

- [ ] 1.1 Portfolio accounts show positions. Build `HoldingsView` in place of the transaction list for a portfolio and for a group of portfolios only.
- [ ] 1.2 Fetch positions through FinTS. Write the self-test of the positions in the result line and the test of the connector that maps them first.
- [ ] 1.3 Take positions from extensions. Deferred: map `securities` of an extension result to `Holding` in `ExtensionConnector`.
- [ ] 1.4 Position row content. Write the valuation tests first.
- [ ] 1.5 Position details. Deferred: needs the market and the time of the quote from the helper.
- [ ] 1.6 Quantities as units or as a nominal amount. Write the format tests first.
- [ ] 1.7 Quotes keep their decimal places. Write the tests of the valuation and of the storage first.
- [ ] 1.8 Value of a position. Write the valuation tests first.
- [ ] 1.9 Foreign currency positions. Write the valuation tests first.
- [ ] 1.10 Profit or loss. Write the valuation tests first.
- [ ] 1.11 Enter and edit the purchase price. Deferred.
- [ ] 1.12 A purchase price from the user survives a refresh. Deferred, with 1.11. The stable ID of 1.14 prepares it.
- [ ] 1.13 Comment on a position. Deferred. The stable ID of 1.14 prepares it.
- [ ] 1.14 A refresh replaces the positions. Write the reconcile and merge tests first.
- [ ] 1.15 A failed refresh keeps the last positions.
- [ ] 1.16 Empty portfolio.
- [ ] 1.17 Total value as the account balance.
- [ ] 1.18 Sum of the selected positions.
- [ ] 1.19 Total gain of a portfolio group.
- [ ] 1.20 Portfolio value in sums.
- [ ] 1.21 Daily record of the portfolio value.
- [ ] 1.22 Record the balance of a saved portfolio.
- [ ] 1.23 Record a missing portfolio balance at open.
- [ ] 1.24 Order of positions.
- [ ] 1.25 Search positions.
- [ ] 1.26 Remove a portfolio account. Deferred: the warning. The positions already go with their account.

## 2. Build

- [ ] 2.1 `Domain`: `Security`, `Quote`, `ExchangeRate`, `Holding`, and the valuation.
- [ ] 2.2 `Storage`: migration `v14` with the table `holding`, `HoldingRecord`, and the positions in `Store.loadLedger` and `Store.merge`.
- [ ] 2.3 `Tools/FinTSHelper`: the positions in the result line of a securities account.
- [ ] 2.4 `FinTS`: decode the positions and map them to `Holding`.
- [ ] 2.5 `scripts/fake-fints-helper.sh`: a depot with positions and an empty depot for the login "depot".
- [ ] 2.6 `App`: `HoldingsView` and the total gain in the header.

## 3. Integration

- [ ] 3.1 Check the positions of the Consorsbank depot of the bank test (issue #11) against the website of the bank: names, quantities, quotes, values, purchase prices, and gains, also of a position in a foreign currency.
- [ ] 3.2 Check a second broker, as the issue asks ("Holdings from two brokers match the brokers' own websites").
