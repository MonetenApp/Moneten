# Proposal: Analyze a portfolio by asset class and over time

## Why

A list of positions answers what the user owns. It does not answer how the money is spread across kinds of assets or how the portfolio developed. Asset classes, a pie chart, and a history chart answer both, and an export hands the positions to a spreadsheet or a tax tool.

## What Changes

- Each security can carry one of eight predefined asset classes. The user assigns the class.
- The portfolio view gets a filter for the asset class and a pie chart of the value by asset class.
- A bar chart shows the history of the portfolio value from the daily records.
- The user can export positions as a CSV file.
- An offline account of the type "Portfolio" can hold positions that the user enters or imports.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `securities-accounts`: adds asset classes, the portfolio charts, the export of positions, and manual positions. The change `add-securities-accounts` introduces the capability.

## Impact

- Milestone: later
- Issues: none yet
- Modules: `Domain` owns asset classes and the history of the portfolio value. `Storage` keeps the class of each security. `App` owns the charts, the filter, and the export.
- Depends on the change `add-securities-accounts` for positions and the daily record, `add-charts` for the view switch and the chart behavior that all views share, `add-main-window` for the filter bar and its pin, `add-offline-accounts` for accounts without a bank access, `add-printing` for "Print Portfolio Items...", and `add-applescript-automation` for the scripted export.
- Decisions: none apply.

## Reference behavior

### Observed in MoneyMoney 2.5.3

- The portfolio view has a filter "Asset class" with "Show All" and one entry for each class, a chart area with the switch between "Daily balance" and "Monthly average balance", and a menu that selects what the chart shows. See [analysis](../../../docs/research/moneymoney-analysis.md#portfolio-u-s-c).
- The context menu of a position has "Assign Asset Class" and "Export Portfolio Position...". The sidebar menu of a portfolio has "Export Portfolio Positions...". See [analysis](../../../docs/research/moneymoney-analysis.md#context-menus-u).
- The asset classes are "Stocks", "Funds", "Bonds", "Real estate", "Commodities", "ETFs", "Cryptocurrencies", and "Others". The class for cryptocurrencies is predefined (version history, 2.4.6).
- A security can be assigned an asset class, and the classes are shown in a pie chart (version history, 2.2.14).
- The app stores the portfolio value once a day and draws a bar chart from these records (version history, 2.2.14). The Y axis is scaled so that small changes are readable (version history, 2.2.15).
- Strings show "Unassigned", "An asset class filter is active; some entries might be hidden.", "No portfolio items; no bar chart.", "No portfolio items; no pie chart.", a note that the app records a daily snapshot of the portfolio values, and a note that there have been no recordings before a date.
- Portfolios can be exported as a CSV file (version history, 2.5.0).
- Strings show "New portfolio item" and "Import Portfolio Positions...".

### Decided for Moneten

- A security has no asset class until the user assigns one. MoneyMoney may guess a class. That was not observed.
- The assignment belongs to the security, identified by its ISIN, and applies to that security in every portfolio.
- The chart menu offers "Account balance", "Absolute change", and "Relative change". Only "Account balance" was observed. The other two labels exist as strings.
- The columns of the CSV export are defined here. MoneyMoney's columns were not observed.
- Manual positions in an offline portfolio and the import of positions are inferred from two strings. The fields and the file format are defined here.
- The history has no value for a day on which no refresh ran. The chart carries the last known value forward.
