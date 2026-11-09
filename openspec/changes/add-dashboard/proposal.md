# Proposal: Show all accounts at a glance on a dashboard

## Why

A user who opens the app wants one answer first. How much money is where, and what happened since the last look. The sidebar gives the balances, but not what is new. The dashboard puts every account with its balance and its newest transactions on one page.

## What Changes

- "Dashboard" becomes the first row of the sidebar.
- The dashboard shows one item for each open account with its icon, name, balance, and newest transactions. New and pending transactions are marked.
- The status line shows the total of all accounts and the time of the last refresh.
- A click on an item opens the account.

## Capabilities

### New Capabilities

- `dashboard`: the overview of all accounts with balances and newest transactions.

### Modified Capabilities

None.

## Impact

- Milestone: later
- Issues: none yet
- Modules: `App` owns the dashboard view. `Storage` provides the newest transactions for each account.
- Depends on the change `add-main-window` for the sidebar, the toolbar, and the navigation, `add-account-management` for accounts, groups, and the closed state, `add-account-refresh` for the new state of transactions and the refresh state of an account, `add-transaction-list` for how a pending transaction looks, `add-securities-accounts` for portfolio values, and `add-printing` for "Print Accounts...".
- Decisions: none apply.

## Reference behavior

### Observed in MoneyMoney 2.5.3

- "Dashboard" is the first row of the sidebar. On the dashboard the view switch is disabled, the transfer button is present, and the status line shows the sum of all accounts and the time of the last refresh. See [analysis](../../../docs/research/moneymoney-analysis.md#dashboard-s-c).
- The context menu of "Dashboard" has the add commands, "Print Accounts...", and "Mark All Transactions as Checked". See [analysis](../../../docs/research/moneymoney-analysis.md#context-menus-u).
- Pending transactions are highlighted in the overview (version history, 2.1.1).
- Accounts that are marked as closed do not appear in the overview (version history, 2.1.14).
- The transfer button is available on the overview page (version history, 2.0.20).
- Strings show the lines "1 more new transaction..." and one for several more new transactions, "Sum:", and "Last updated".

### Decided for MonetenMoneten

The content of the dashboard is drawn without Accessibility elements and macOS blocked screenshots. The layout of an item was not observed. Everything below is a decision.

- An item shows the icon, the name, the balance, and up to five of the newest transactions, each with date, counterparty, and amount.
- Items follow the order of the sidebar and stand under the names of their account groups.
- The line for more new transactions appears when an account has more new transactions than the item shows. A click on it opens the account.
- A portfolio item shows the portfolio value and no transactions.
- An account with a failed refresh shows the error on its item.
- The total keeps one sum for each currency. The app converts no currencies.
- The dashboard does not change the new state of a transaction. Opening the account does.
- At launch the app shows the dashboard when no other view was remembered.
- With no open account the dashboard shows "No accounts present.".
