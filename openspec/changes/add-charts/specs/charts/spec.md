# Spec Delta

## Purpose

Charts show the history of a balance and the split of money among categories. This capability defines the three view modes, the balance bar chart and its calibration, the bar chart of a category, and the pie chart.

## ADDED Requirements

### Requirement: Three view modes

The app SHALL offer the view modes "List", "Bar Chart", and "Pie Chart" in the View menu with the shortcuts ⌘1, ⌘2, and ⌘3, and as a switch in the toolbar. "Bar Chart" and "Pie Chart" show the chart above the list. The View menu marks the active mode.

#### Scenario: Switch to the bar chart

- **GIVEN** the account "Giro" in the mode "List"
- **WHEN** the user presses ⌘2
- **THEN** a bar chart appears above the list, and "Bar Chart" has a checkmark in the View menu

#### Scenario: View without charts

- **WHEN** the user selects a view that has no charts, for example "Outbox"
- **THEN** the three modes are disabled in the View menu and in the toolbar

### Requirement: The view mode is remembered

The app SHALL remember the last view mode for account views and for category views separately, also after a restart.

#### Scenario: Back to an account

- **GIVEN** the user chose "Bar Chart" in an account and "Pie Chart" in a category
- **WHEN** the user selects another account
- **THEN** that account shows the bar chart

### Requirement: Balance bar chart of an account

The app SHALL draw the balance of an account over time as a bar chart, with one bar for each day and the oldest day on the left. A negative balance is drawn below the zero line.

#### Scenario: One month

- **GIVEN** the account "Giro" and the period October 2026
- **WHEN** the user chooses "Bar Chart"
- **THEN** the chart shows 31 bars, one for the balance at the end of each day

#### Scenario: Overdrawn days

- **GIVEN** the balance was -120,00 € from 27.10.2026 to 29.10.2026
- **WHEN** the user looks at the chart
- **THEN** the bars of these three days point down from the zero line

### Requirement: Look of the balance chart

The app SHALL draw the balance chart with every bar 4 points wide with a gap of 2 points, white on the slate band behind the title, and red below zero, over a dashed line at zero. A thin line and the name of the month, such as "Oct 26", mark the first day of each month; in the monthly average the year marks January. The chart has no amount axis.

#### Scenario: Month lines

- **GIVEN** the daily balance chart of "Giro" from September to November 2026
- **WHEN** the user looks at the chart
- **THEN** lines with "Oct 26" and "Nov 26" mark the first of October and of November

### Requirement: Readable text on the band

The app SHALL write the text on the slate band behind the title and the chart with a contrast of at least 4.5:1 in the light and the dark appearance, also with "Increase contrast". In the light appearance the text is dark slate, and negative amounts use a darker red.

#### Scenario: Header in the light appearance

- **GIVEN** the light appearance and the account "Giro" with a balance of -120,00 €
- **WHEN** the user looks at the header
- **THEN** the title is dark on the slate band and the balance is a dark red, each with at least 4.5:1

### Requirement: Balances are computed from the transactions

The app SHALL compute the balance of each day as the initial balance of the account plus all booked transactions up to the end of that day. Pending transactions do not enter this computation, and the balance that the bank reports enters it only through the initial balance. A portfolio is the exception: its balance on a day is its last recorded value on or before that day, as the capability `securities-accounts` defines, and nothing before its first record.

#### Scenario: Computed balance

- **GIVEN** an initial balance of 1.000,00 €, a transaction of -200,00 € on 01.10.2026, and a transaction of 50,00 € on 03.10.2026
- **WHEN** the app computes the balances
- **THEN** the balance is 800,00 € on 01.10.2026 and on 02.10.2026, and 850,00 € on 03.10.2026

#### Scenario: Pending transaction

- **GIVEN** a pending transaction of -30,00 € today
- **WHEN** the app computes the balance of today
- **THEN** the pending transaction does not change it

### Requirement: Initial balance of a refreshed account

The app SHALL set the initial balance of an account that a bank refreshes to the balance that the bank reported, less the booked transactions up to the end of the day of that balance. Pending transactions do not count. The days before the first transaction show the initial balance. A portfolio, an offline account, and a migrated account keep their initial balance, also when a bank access connects them later.

#### Scenario: First refresh

- **GIVEN** the bank reports a balance of 2.500,00 € and delivers booked transactions that add up to 700,00 €
- **WHEN** the first refresh of the new account ends
- **THEN** the initial balance is 1.800,00 €

#### Scenario: More money out than in

- **GIVEN** the bank reports a balance of 1.200,00 € today and delivers booked transactions of the last 90 days that add up to -1.350,00 €
- **WHEN** the user opens the bar chart of the account with the period "12 Months"
- **THEN** the last bar shows 1.200,00 €
- **AND** every bar before the first transaction shows 2.550,00 €

#### Scenario: Transactions after the day of the balance

- **GIVEN** the bank reports a balance of 500,00 € for 10.11.2026 and delivers booked transactions of -200,00 € on 01.11.2026 and of -30,00 € on 12.11.2026
- **WHEN** the refresh ends
- **THEN** the initial balance is 700,00 €, the bar of 10.11.2026 shows 500,00 €, and the bar of 12.11.2026 shows 470,00 €

### Requirement: The initial balance stays

The app SHALL set the initial balance of a refreshed account only once, at the first refresh that brings a bank balance. A refresh whose transactions failed does not set it. Later refreshes, imports, and deletions do not change it, and neither does a later bank balance. A value that the user enters stays. A difference between the computed balance and the bank balance that appears later is for the calibration to resolve.

#### Scenario: Later refresh with an older transaction

- **GIVEN** an account whose first refresh set an initial balance of 2.550,00 € with a bank balance of 1.200,00 €
- **WHEN** a refresh brings a bank balance of 800,00 € and booked transactions of -400,00 € today and of -70,00 € from before the first refresh
- **THEN** the initial balance stays 2.550,00 € and the last bar shows 730,00 €

#### Scenario: Deleted transaction

- **GIVEN** an account with a bank balance of 1.200,00 € and an initial balance of 2.550,00 €
- **WHEN** the user deletes a transaction of -950,00 €
- **THEN** the initial balance stays 2.550,00 € and the last bar shows 2.150,00 €

#### Scenario: Entered initial balance

- **GIVEN** an account whose first refresh set an initial balance of 2.550,00 €
- **WHEN** the user enters 3.000,00 under "Initial balance" and the next refresh ends
- **THEN** the initial balance is 3.000,00 €

### Requirement: Initial balance of an account from before

The app SHALL set the initial balance once, at the next refresh, for an account that a bank refreshed before the app set initial balances and whose initial balance is 0,00 €. An account with another initial balance keeps it. A user who wants 0,00 € enters it again after that refresh.

#### Scenario: Account from before

- **GIVEN** an account that a bank refreshed before the app set initial balances, with an initial balance of 0,00 €, a bank balance of 1.000,00 €, and booked transactions of -300,00 €
- **WHEN** its next refresh ends with a bank balance of 1.000,00 €
- **THEN** the initial balance is 1.300,00 €, and the refreshes after it do not change it

### Requirement: Daily balance or monthly average balance

The app SHALL let the user switch the balance chart between "Daily balance" and "Monthly average balance" with a column of the segments "D" and "M" at the bottom of the trailing edge of the chart. The category chart has its "M", "Q", and "Y" in the same place. The monthly average is the mean of the daily balances of a calendar month and is drawn as one bar for each month.

#### Scenario: Monthly average

- **GIVEN** an account with a balance of 1.000,00 € on 15 days of April and 2.000,00 € on the other 15 days
- **WHEN** the user switches to "Monthly average balance"
- **THEN** the bar of April shows 1.500,00 €

### Requirement: The balance chart follows the period

The app SHALL draw the balance chart for the time that the period filter selects. With "Show All" the chart starts at the oldest transaction or portfolio record of the view.

#### Scenario: Twelve months

- **WHEN** the user chooses "12 Months" in the "Period" menu
- **THEN** the chart shows the balances of the last 12 months

### Requirement: Long periods scroll

The app SHALL keep the width of every bar and let the user scroll a longer chart sideways with the trackpad. The chart opens at its newest bar on the right. The scale covers all bars of the period, so scrolling does not change it.

#### Scenario: Ten years of daily balances

- **GIVEN** an account with 10 years of history and the period "Show All"
- **WHEN** the user opens the bar chart
- **THEN** the chart shows the last days at the right edge with one bar for each day, and a swipe to the right on the trackpad shows earlier days

### Requirement: Balance chart of an account group

The app SHALL draw the balance chart of an account group as the sum of the balances of its accounts for each day. Accounts in different currencies are not added. The app draws one chart for each currency and shows one of them at a time, first the currency of most accounts, with a picker for the others. The category bars and the pie charts do the same with the transactions of each currency.

#### Scenario: Two euro accounts

- **GIVEN** the group "Private" with "Giro" at 1.000,00 € and "Savings" at 5.000,00 € on 01.10.2026
- **WHEN** the user opens the bar chart of "Private"
- **THEN** the bar of 01.10.2026 shows 6.000,00 €

#### Scenario: A group with a portfolio

- **GIVEN** the group "Private" with "Giro" at 1.000,00 € and the portfolio "Depot" at 20.000,00 €, whose first recorded value is from 01.11.2026
- **WHEN** the user opens the bar chart of "Private"
- **THEN** the title shows 21.000,00 €, and the bars from 01.11.2026 on include the recorded value of "Depot", so the last bar shows 21.000,00 €
- **AND** the bars before 01.11.2026 show "Giro" alone
- **AND** the chart says "Portfolios from 01.11.2026", with the help text that there have been no recordings of portfolio values before that day

#### Scenario: A group with a portfolio without a recorded value

- **GIVEN** the group "Private" with "Giro" at 1.000,00 € and a portfolio without any recorded value whose balance is 20.000,00 €
- **WHEN** the user opens the bar chart of "Private"
- **THEN** the title shows 21.000,00 €, the last bar shows 1.000,00 €, and the chart says "Portfolios not shown: 20.000,00 €"

#### Scenario: Portfolios with and without a recorded value

- **GIVEN** the group "Private" with "Giro", the portfolio "Depot" recorded since 01.11.2026, and a portfolio "Offline" of 5.000,00 € without any recorded value
- **WHEN** the user opens the bar chart of "Private"
- **THEN** the chart says "Portfolios from 01.11.2026 · Portfolios not shown: 5.000,00 €"

#### Scenario: Euro and dollar accounts

- **GIVEN** a group with one account in euros and one in US dollars
- **WHEN** the user opens the bar chart of the group
- **THEN** the chart area shows one chart for euros and one for US dollars

### Requirement: No balance chart without transactions

The app SHALL show a message in place of the balance chart when an account has no transactions. For a group, the message names the first account without transactions, and no chart is drawn.

#### Scenario: Empty account

- **WHEN** the user opens the bar chart of an account without transactions
- **THEN** the chart area says "No transactions; no bar chart."

#### Scenario: Group with one empty account

- **GIVEN** the group "Private" with "Giro" and the fixed term deposit "Festgeld" that has no transactions
- **WHEN** the user opens the bar chart of "Private"
- **THEN** the chart area says that the account "Festgeld" has no transactions and shows no bar chart

### Requirement: Calibrate the computed balance

The app SHALL open a calibration window from "Calibrate" in the account settings. The window explains that balances are computed from the transactions and that gaps or duplicates must be cleaned up first. It asks for the correct balance at the end of today. On confirmation the app changes the initial balance by the difference, so that every computed balance shifts by the same amount.

#### Scenario: Chart is 50 euros too high

- **GIVEN** the computed balance of today is 1.250,00 € and the initial balance is 300,00 €
- **WHEN** the user opens "Calibrate", enters 1.200,00, and confirms
- **THEN** the initial balance is 250,00 € and every bar is 50,00 € lower

#### Scenario: Set the initial balance directly

- **WHEN** the user changes "Initial balance" in the account settings from 300,00 to 0,00
- **THEN** every computed balance drops by 300,00 €

### Requirement: Propose a calibration

The app SHALL propose a calibration when the computed balance of an account differs from the balance that the bank reports. The app makes no proposal when the difference equals the sum of the pending transactions.

#### Scenario: Unexplained difference

- **GIVEN** the bank reports 1.200,00 €, the computed balance is 1.250,00 €, and there are no pending transactions
- **WHEN** a refresh ends
- **THEN** the app proposes to calibrate the account

#### Scenario: Difference from pending transactions

- **GIVEN** the bank reports 1.200,00 €, the computed balance is 1.250,00 €, and one pending transaction of -50,00 € exists
- **WHEN** a refresh ends
- **THEN** the app makes no proposal

### Requirement: Bar chart of a category

The app SHALL draw the sum of a category for each month, each quarter, or each year as a bar chart, with the switch "Monthly view", "Quarterly view", and "Yearly view". A sum above zero is drawn upward and a sum below zero downward. For a category group, a bar is the sum of all categories below the group.

#### Scenario: Monthly spending

- **GIVEN** "Groceries" with sums of -420,00 € in September 2026 and -480,00 € in October 2026
- **WHEN** the user opens the bar chart of "Groceries" in the "Monthly view"
- **THEN** the bars of September and October point down with 420,00 € and 480,00 €

#### Scenario: Yearly view

- **WHEN** the user switches to the "Yearly view"
- **THEN** the chart shows one bar for each calendar year

### Requirement: Look of the category chart

The app SHALL draw the category chart with each bar 40 points wide with a gap of 8 points and its period above it, in the color of the category and darker below zero. A period without transactions shows a line at zero. The highest sum, zero, and the lowest sum stand at the leading edge, and the chart scrolls like the balance chart.

#### Scenario: A month without spending

- **GIVEN** "Groceries" in orange with spending in July and September 2026 and none in August
- **WHEN** the user opens the "Monthly view"
- **THEN** the bars of July and September point down in a darker orange, and August shows a line at zero

### Requirement: The category chart follows the period and the account filter

The app SHALL draw the category bar chart and the pie chart from the transactions that pass the period filter and the account filter of the view.

#### Scenario: One account

- **GIVEN** the category view "Groceries" with the account filter "Credit card"
- **WHEN** the user looks at the bar chart
- **THEN** the bars count only the transactions of "Credit card"

### Requirement: Pie charts of deposits and withdrawals

The app SHALL show two pie charts in the mode "Pie Chart", one for the withdrawals and one for the deposits of the view. Each slice is one category in its color. Its name stands beside the pie, and the pointer shows its amount and share. In the view of a category group the slices are the categories directly below the group.

#### Scenario: Spending of one account

- **GIVEN** the account "Giro" with withdrawals of 600,00 € in "Rent", 300,00 € in "Groceries", and 100,00 € in "Leisure" in the period
- **WHEN** the user chooses "Pie Chart"
- **THEN** the pie of withdrawals shows "Rent" with 60 %, "Groceries" with 30 %, and "Leisure" with 10 %

#### Scenario: No transactions

- **WHEN** the view has no transactions in the period
- **THEN** the chart area says "No transactions; no pie chart."

### Requirement: Look of the pie charts

The app SHALL draw two full pie charts of 110 points, each in a rim of 6 points, side by side on the slate band with 300 points between their middles and no title. A thin line leads from the middle of each slice to its category name outside the pie, on the side of the slice. A slice below 3 % has no name, so that names do not overlap. Under the pointer a slice stands out, and the text below the pie shows its category, amount, and share.

#### Scenario: Names outside the pie

- **GIVEN** the pie of withdrawals with "Rent" at 60 %, "Groceries" at 38 %, and "Leisure" at 2 %
- **WHEN** the user moves the pointer onto the slice "Groceries"
- **THEN** lines lead from "Rent" and "Groceries" to their names outside the pie, "Leisure" has no name, and the text below the pie shows "Groceries", its amount, and "38 %"

### Requirement: Categories can be left out of charts

The app SHALL leave a category whose setting "Show in diagrams" is off out of the pie charts and out of the bar chart of every category group above it. The category's own view still shows its bar chart.

#### Scenario: Transfers between own accounts

- **GIVEN** the category "Transfers" with "Show in diagrams" turned off and withdrawals of 2.000,00 € in the period
- **WHEN** the user opens the pie chart of the account "Giro"
- **THEN** the pie has no slice for "Transfers" and the shares of the other categories add up to 100 %

#### Scenario: Nothing left to show

- **GIVEN** every category of the view has "Show in diagrams" turned off
- **WHEN** the user chooses "Pie Chart"
- **THEN** the chart area says "No visible categories; no pie chart."

### Requirement: Values on hover

The app SHALL show the date or period and the exact amount of a bar, or the category, the amount, and the share of a slice, while the pointer rests on it. A bar gets a light column through the chart, and its date and amount stand below the bars next to it.

#### Scenario: Hover over a bar

- **WHEN** the pointer rests on the bar of 15.10.2026 in a balance chart
- **THEN** the app shows 15.10.2026 and the balance of that day

### Requirement: A click on a bar selects its period

The app SHALL set the period filter to the time of a bar when the user clicks the bar, so that the list shows the transactions of that time.

#### Scenario: Click a month

- **GIVEN** the bar chart of "Groceries" in the "Monthly view"
- **WHEN** the user clicks the bar of October 2026
- **THEN** the list shows the transactions of "Groceries" from 01.10.2026 to 31.10.2026

### Requirement: Charts stay current

The app SHALL redraw a visible chart when a refresh, an import, an edit, a deletion, a split, or a change of category changes the data behind it.

#### Scenario: Import of old transactions

- **GIVEN** the bar chart of "Giro" is visible
- **WHEN** the user imports transactions for 2019
- **THEN** the chart shows the balances of 2019 without a restart

### Requirement: Charts follow the appearance

The app SHALL draw all charts with colors that are readable in the light and in the dark appearance of macOS, and it SHALL redraw them when the appearance changes.

#### Scenario: Switch to dark mode

- **GIVEN** a visible bar chart in light mode
- **WHEN** the user turns on dark mode in the system settings
- **THEN** the chart uses the dark background, and its bars and labels stay readable
