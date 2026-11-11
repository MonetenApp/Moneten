# Proposal: Show transactions in a list with checkmarks and comments

## Why

The transaction list is where a user spends most of the time in a banking app. It answers what was paid, to whom, and when. It also carries the user's own bookkeeping, which are checkmarks for handled transactions and comments.

## What Changes

- Account, account group, and category views show one row for each transaction, newest first.
- A row shows the date, the counterparty, the purpose, the category, the amount, and the details that the bank delivered.
- Pending transactions look different, and the list shows their sum.
- The user can select text, select several rows, check transactions off, and write comments.
- A single account can show the daily balance inside the list.
- The context menu leads from a transaction to its account or its category.
- The user can edit and delete transactions, also in accounts with bank access.

## Capabilities

### New Capabilities

- `transaction-list`: the content and order of the list, selection, checkmarks, comments, the daily balance in the list, and editing and deleting transactions.

### Modified Capabilities

None.

## Impact

- Milestone: v0.1
- Issues: #5
- Modules: `Domain` owns the transaction type and its ordering. `Storage` owns the queries. `App` owns the list view.
- Depends on the change `add-main-window` for the window, the filter bar frame, and the status line.
- Depends on the change `add-account-refresh` for how transactions arrive and how a pending transaction becomes a booked one.
- Related changes own the other commands of the context menu. These are `add-categories`, `add-split-transactions`, `add-offline-accounts`, `add-transaction-search-and-filters`, `add-sepa-transfers`, `add-printing`, and `add-data-export`.
- Decisions: none apply.

## Reference behavior

### Observed in MoneyMoney 2.5.3

- A row carries the date, the amount, the counterparty, the purpose, the category, and labeled details such as the value date. See [analysis](../../../docs/research/moneymoney-analysis.md#account-and-account-group-u-w-c).
- The details come from the structured purpose. They are the booking text, the end-to-end reference, the mandate reference, and the creditor ID (version history, 2.2.11). The value date arrived in 2.3.0, and the deviating originator or recipient in 2.2.9. The interface also has labels for a receipt date and a return reason.
- Pending transactions are hatched ([help](https://moneymoney.app/help/)), and the list shows the sum of the pending amounts (version history, 2.2.0).
- Text in the list can be selected and copied (2.2.18). A double click selects a word and a triple click selects the field (2.4.3).
- Checkmarks arrived in 2.3.0. "Mark All Transactions as Checked" first states how many transactions in how many accounts it changes. "Checkmarks" in the View menu hides them (2.3.1).
- Comments use "Add Comment..." with ⇧⌘K, and a transaction with a comment shows a yellow icon (2.1.4, 2.2.1, 2.3.0).
- "Daily Balance" is a switch in the filter bar and a command in the View menu. Both exist only for a single account. See [analysis](../../../docs/research/moneymoney-analysis.md#main-window-u).
- The context menu has "Go to" with the account and the category (2.4.10), "Edit Transaction...", and in the view of a single account "Delete Transaction...". See [analysis](../../../docs/research/moneymoney-analysis.md#context-menus-u).
- Deleting asks "Delete selected transaction?" or names the count, and warns that deleted transactions cannot be restored ([delete transactions](https://moneymoney.app/help/delete-transactions/)).
- Range selection uses the Shift key and free selection uses the Command key (same page).
- The context menu shows the macOS Services for selected text (2.3.0).
- The context menu acts on the transactions that the user selected. A beta of 2.5.4 fixes a case where it did not ([beta notes](https://moneymoney.app/beta/)).
- A group view can "Group transactions by account" (interface string).

### Decided for Moneten

- A selected row in a group or category view names its account at the end of the payee line. MoneyMoney adds a third line, which makes the row taller.
- Transactions of one day keep the order in which the bank delivered them. MoneyMoney's order inside a day was not observed.
- A transaction counts as new until the user leaves the view in which it was shown. How MoneyMoney clears the mark was not observed.
- The status line shows the count and the sum of the selected rows. Only the sum of the whole list was observed.
- "Edit Transaction..." changes the booking date, the value date, the counterparty name, the purpose, and the amount. An edited transaction keeps the user's values after later refreshes. MoneyMoney offers the command for fetched transactions, but its fields were not observed.
- The option "Group transactions by account" sits in the settings of the account group. Its place in MoneyMoney was not observed.
- The list must stay fluid with 50,000 transactions. This target comes from issue #5.
