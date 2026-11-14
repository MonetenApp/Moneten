# Proposal: Show balance history and spending by category in charts

## Why

Charts turn a list of transactions into an answer. How did my balance develop this year? How much do I spend on groceries each month? A user sees that in one look at a chart and in minutes with a list.

## What Changes

- Every account and category view can show the list alone, a bar chart above the list, or a pie chart above the list.
- The bar chart of an account shows the daily balance or the monthly average balance over time.
- The app computes these balances from the initial balance and the transactions, pending ones included, and the user can calibrate them.
- The bar chart of a category shows its sum for each month, quarter, or year.
- The pie chart shows how deposits and withdrawals divide among the categories.
- A category can be left out of all charts, for example transfers between own accounts.

## Capabilities

### New Capabilities

- `charts`: the view modes, the balance bar chart with its calibration, the category bar chart, and the pie chart.

### Modified Capabilities

None.

## Impact

- Milestone: v0.1
- Issues: #21
- Modules: `Domain` owns the balance history and the aggregation by category. `App` owns the chart views.
- Depends on the change `add-main-window` for the view switch in the toolbar.
- Depends on the change `add-account-management` for the field "Initial balance" in the account settings, and on the change `add-categories` for "Show in diagrams" and the category colors.
- Depends on the change `add-transaction-search-and-filters` for the period filter.
- The charts of securities accounts belong to the change `add-portfolio-analysis`. The budget line belongs to the change `add-budgets`.
- Decisions: none apply.

## Reference behavior

### Observed in MoneyMoney 2.5.3

- The View menu has "List" (⌘1), "Bar Chart" (⌘2), and "Pie Chart" (⌘3), and the toolbar has the same three as a switch. The switch is disabled where a view has no chart. See [analysis](../../../docs/research/moneymoney-analysis.md#menus-and-keyboard-shortcuts-u).
- The chart area of an account has a switch between "Daily balance" and "Monthly average balance" (version history, 2.2.13). See [analysis](../../../docs/research/moneymoney-analysis.md#account-and-account-group-u-w-c).
- The chart area of a category has "Monthly view", "Quarterly view", and "Yearly view" (version history, 2.2.10). See [analysis](../../../docs/research/moneymoney-analysis.md#category-u-w).
- The daily balances are computed from the initial balance over the transactions, from the oldest to the newest. The balance from the bank is not used. The app finds an initial balance at account setup, and the user can set one in the account settings ([help](https://moneymoney.app/help/), version history 2.1.1).
- The account settings have "Initial balance" with a button "Calibrate". The calibration window explains the method and asks for the value that the chart uses for one date (interface strings).
- The app does not propose a calibration when the difference equals the pending transactions (version history, 2.4.37).
- With many transactions the chart averages values so that the bars do not become too narrow (version history, 2.1.0).
- A view without data says so, for example "No transactions; no bar chart." A group that contains an account without transactions shows no bar chart and names that account (interface strings, version history 2.4.37).
- A category with "Show in diagrams" turned off does not appear in other charts. The help recommends this for transfers between own accounts ([help](https://moneymoney.app/help/), version history 2.2.12).
- Without a visible category the view says "No visible categories; no pie chart."

### Decided for Moneten

- Bars, pies, the slate band, and the hover column follow the look measured in MoneyMoney's window.
- Text on the light slate band is dark with at least 4.5:1. MoneyMoney writes white on it, which reaches only 2:1.
- The pies stand 300 points apart instead of MoneyMoney's 225, so the names between them have room.
- The pie chart area shows one pie for withdrawals and one for deposits. The version history speaks of pie charts in the plural, but the drawing was not observed.
- A group with accounts in several currencies gets one bar chart for each currency. Issue #21 asks for one series per currency, and the app converts no currencies.
- The balance chart follows only the period filter. The category charts follow the period filter and the account filter. Which filters MoneyMoney applies to charts was not observed.
- Pending transactions count in the computed balances, the charts, and the sums from the moment they are stored, like booked ones. The money is already spent, so the chart shows it at once, and the bars do not jump when the bank books the transaction.
- The initial balance of a refreshed account is set once, at the first refresh with a bank balance, as in MoneyMoney. Later differences go to the calibration proposal. The value is the bank balance less every transaction of the account, pending ones included and with no date limit. The last bar then shows the same balance as the bank. Accounts that a bank refreshed before issue #109 have 0,00 € and get the value once, at their next refresh.
- Hovering shows the value of a bar or a slice, and a click on a bar sets the period filter to that bar. The click comes from issue #21. Neither was observed in MoneyMoney.
- The calibration asks for the balance at the end of today and changes the initial balance by the difference. MoneyMoney's window names a date, but which date was not observed. Its entry "Clearing entry for daily balance" is not specified here.
- The app remembers the view mode for account views and for category views separately.
