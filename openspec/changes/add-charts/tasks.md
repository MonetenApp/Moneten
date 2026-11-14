# Tasks

One task per requirement of the spec. A task is checked only when a test or a check in the running app shows the behavior.

## 1. Requirements

- [x] 1.1 Three view modes. Verified by ⌘1, ⌘2, ⌘3 and the toolbar switch.
- [x] 1.2 The view mode is remembered. Verified by stored in the user defaults.
- [x] 1.3 Balance bar chart of an account. Verified by BalanceChartTests "One month shows one bar for the balance at the end of each day" and "Overdrawn days point down from the zero line", and by the debug harness snapshot of the bar chart.
- [ ] 1.4 Balances are computed from the transactions. Built for the earlier rule, which left pending transactions out. Tasks 3.1 and 3.2 change it.
- [ ] 1.5 Initial balance of a refreshed account. Built for the earlier rule, which left pending rows and rows after the day of the balance out. Tasks 3.3 and 3.4 change it. Still verified by OpeningBalanceTests: after the first refresh a fetched account with more money out than in ends at its bank balance and is flat before its first row, a refresh whose transactions failed does not set it, and a bank without transactions gets its balance.
- [x] 1.6 Daily balance or monthly average balance. Verified by the debug harness snapshot in the first build.
- [x] 1.7 The balance chart follows the period. Verified by the debug harness snapshot in the first build.
- [x] 1.8 Long periods scroll. Verified by BalanceChartTests "Ten years of daily balances keep one bar per day" and snapshots of the debug harness: the daily chart of `history` opens at today with July to November visible, and 50,000 transactions of `bulk` stay under the perf budget of scripts/perf-check.sh. Scrolling with the trackpad still needs a check by hand.
- [x] 1.9 Balance chart of an account group. Verified by the debug harness snapshot in the first build. Portfolios count from their first recorded value on: PortfolioHistoryTests "A group shows the giro alone before the first portfolio record, and both with the last record carried forward after it", and the debug harness log `chart ... last=... total=...` of the group "Private" with "Depot", where the last bar equals the total of 53.500,94 €. The caption "Without portfolios" for a portfolio without any record was checked only before the history existed.
- [x] 1.10 No balance chart without transactions. Verified by "No transactions; no bar chart." for an account and, for a group, "The account “Festgeld” has no transactions; no bar chart." from `Ledger.accountsWithTransactions` (LedgerTests "The ledger knows which accounts have transactions, also after a delete"). Portfolios and closed accounts do not count.
- [x] 1.11 Calibrate the computed balance. Verified by "Calibrate" in the account settings.
- [ ] 1.12 Propose a calibration. Build it and verify it with a test or in the app.
- [x] 1.13 Bar chart of a category. Verified by the debug harness snapshot in the first build.
- [x] 1.14 The category chart follows the period and the account filter. Verified by the chart uses the filtered rows.
- [x] 1.15 Pie charts of deposits and withdrawals. Verified by the debug harness snapshot in the first build.
- [x] 1.16 Categories can be left out of charts. Verified by "Show in diagrams".
- [ ] 1.17 Values on hover. Built: balance and category bars show a light column and the date or period with the exact amount below the bars, see the debug harness command `barsnapshot`; a pie slice stands out and the text below the pie shows the category, the amount, and the share, see the debug harness command `piesnapshot`. Verify it with the pointer in the app.
- [ ] 1.18 A click on a bar selects its period. Built: a click on a balance bar sets its day, days, or month as the period of the list, and a click on a category bar its month, quarter, or year. The chart keeps its period, so the other bars stay; the debug harness command `period bar` shows this. Verify it with a click in the app.
- [x] 1.19 Charts stay current. Verified by charts read the ledger on every change.
- [x] 1.20 Charts follow the appearance. Verified by dark mode, see the debug harness snapshot in the first build.
- [x] 1.21 Bars as MoneyMoney draws them, measured in its window: balance bars of 4 points with a gap of 2, white on the slate band behind the title, over a dashed line at zero, month and year lines with labels and no amount axis; category bars of 40 points with a gap of 8 in the color of the category, darker below zero, a line at zero for empty periods, and the highest sum, zero, and the lowest sum at the leading edge. Verified by snapshots of the debug harness in light and dark mode and by BalanceChartTests "A category chart has a bar for every period".
- [x] 1.22 Readable text on the band: dark slate text, labels, and a darker red on the light slate, at least 4.5:1 in light, dark, and "Increase contrast". Verified by the computed ratios in Palette and snapshots of the debug harness in light and dark mode.
- [x] 1.23 Pie charts as MoneyMoney draws them, measured in its window: full pies of 110 points in a rim of 6, 300 points apart on the slate band (MoneyMoney 225), no title, category names outside with a line from the middle of each slice, none for slices below 3 %, names of one side pushed apart, and category, amount, and share below the pie under the pointer. Verified by snapshots of the debug harness in light and dark mode, with a group of eight categories and with a category group.
- [x] 1.24 The initial balance stays. Verified by OpeningBalanceTests: a later refresh with an older row, an import, and a deletion keep the initial balance, an entered value survives refreshes, and portfolios, migrated accounts, and offline accounts keep theirs, also a migrated account that a bank access connects. The scenario "Refresh whose transactions failed" is verified by OpeningBalanceTests "A balance whose transactions failed does not set the opening balance, so the next full refresh still does".
- [x] 1.25 Initial balance of an account from before. Verified by OpeningBalanceTests "An account fetched before the fix gets its opening balance once, at its next refresh, and one with a typed or migrated value keeps it", which opens a v10 database, and by the debug harness: a database of the build before the fix gets the value at its next refresh.

## 2. Integration

- [ ] 2.1 Check every scenario of the spec in a release build and record the result in the pull request.

## 3. Pending transactions count

- [ ] 3.1 Write the tests first. LedgerTests and BalanceChartTests: with an initial balance of 1.000,00 € and a pending transaction of -30,00 € in "Groceries" today, the computed balance and the bar of today are 970,00 €, and the withdrawals of the pie hold 30,00 € in "Groceries". Replacing that row by its booked version on the same day leaves every bar unchanged. Replace the test "Balances leave out pending transactions".
- [ ] 3.2 Count pending rows in `Ledger.computedBalance` and in the balance, category, and pie data of `Sources/Domain/Charts.swift`.
- [ ] 3.3 Write the tests first in OpeningBalanceTests: a bank balance of 2.500,00 € with booked rows of 700,00 € and a pending row of -30,00 € gives 1.830,00 €, and a row after the day of the balance counts, so the last bar equals the bank balance. Replace the test that leaves pending rows and later rows out.
- [ ] 3.4 Subtract every row, pending rows included and with no date limit, in `Account.deriveInitialBalance` in `Sources/Domain/Models.swift`. Leave out the rows that the merge drops, which `Sources/Domain/Reconcile.swift` still passes in.
- [ ] 3.5 Subtract pending rows as well when the migration sets the initial balance in `Sources/Import/MoneyMoneyMigration.swift`, with a test first.

## Workflow follow-up

- Archive the change with `openspec archive add-charts` when every task is checked.
