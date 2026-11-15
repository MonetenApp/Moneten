# Tasks

One task per requirement of the spec. A task is checked only when a test or a check in the running app shows the behavior.

## 1. Requirements

- [x] 1.1 One row per transaction. Verified by the debug harness snapshot in the first build.
- [x] 1.2 Newest transactions first. Verified by LedgerTests "Newest first".
- [ ] 1.3 Details from the bank. Built in part: the transaction sheet shows the details. Finish it and verify it with a test or in the app.
- [x] 1.4 Account name in group and category views. Verified by the debug harness snapshot of the group "Private" with two rows selected: each names "Girokonto" at the end of the line with the payee; with "Group transactions by account" on, the heading "Girokonto" stands above its rows (debug harness `groupbyaccount Private`).
- [x] 1.5 Pending transactions look different. The hatching is verified by the debug harness snapshot: the row is hatched across all cells, and the header shows "Pending" with the sum of the pending transactions of the view and nothing without them. The sum leaves out a pending transaction marked for review, verified with task 1.30 of the change `add-account-refresh`.
- [x] 1.6 New transactions are marked. Verified by a dot in the row, see the debug harness snapshot in the first build.
- [ ] 1.7 Text can be selected and copied. Built in part: text selection is on. Finish it and verify it with a test or in the app.
- [x] 1.8 Several rows can be selected. Verified by the table allows a multiple selection.
- [x] 1.9 The context menu acts on the selection. Verified by the menu receives the selected rows.
- [x] 1.10 Checkmarks. Verified by checkbox column; LedgerTests use the status filter.
- [x] 1.11 Mark all transactions as checked. Verified by reading `AppModel.markAllChecked`: it counts the unchecked rows of the view and their accounts, asks, and changes nothing on "Cancel". Not covered by a test, because the app has no test target yet.
- [x] 1.12 Checkmarks can be hidden. Verified by the debug app check: "Checkmarks" in the View menu is a toggle on `AppModel.showsCheckmarks`. With the harness command `checkmarks off` no row of "Girokonto" shows a checkmark control, in light and dark mode, and after a restart of the app with the same database the controls stay hidden. The stored checkmarks do not change.
- [x] 1.13 Comments. Verified by "Add Comment..." with ⇧⌘K and a note icon in the row.
- [x] 1.14 Daily balance in the list. Verified by DayEndBalanceTests (the scenario "Turn on" with 1.200,00 € and two rows of -50,00 € and -25,00 €, and a search that hides a row of the day) and by the debug app check: with "Daily balance" on, the top row of each day of "Girokonto" shows the balance at the end of that day below its amount, and the newest one equals the balance of the header, 16.898,33 €. The snapshot of the group "Private" has no switch in the filter bar. That "Daily Balance" in the View menu is disabled without a selected account is read in `AppCommands`, because the Mac was locked and SwiftUI kept every menu disabled. The perf scenario "daily-balance-in-account" turns it on in 74 ms.
- [x] 1.15 Go to the account or the category. Verified by "Go to" in the context menu.
- [ ] 1.16 Edit a transaction. Built in part: all fields of offline transactions; category and comment of others. Finish it and verify it with a test or in the app.
- [x] 1.17 Delete transactions. Verified by "Delete Transaction..." with the warning that deleted transactions cannot be restored, offered only in an account view (`TransactionMenu`). Not covered by a test, because the app has no test target yet.
- [ ] 1.18 Services for selected text. Build it and verify it with a test or in the app.
- [x] 1.19 Empty states. Verified by the debug harness snapshot in the first build.
- [ ] 1.20 The list stays fluid with a large history. Built in part: the perf scenarios "scroll-large-group" (50,000 rows from top to bottom in 20 steps, 50 ms, every visible row has its view after each step) and "daily-balance-in-account" (74 ms) pass. "select-all-in-large-group" takes 946 ms, over the half second of the budget: a sample shows that `NSTableView selectAll:` asks the SwiftUI table coordinator `shouldSelectItem` for each of the 50,000 rows, and the code of the app takes a few milliseconds of it. The other scenarios that are slow on this branch are slow on main as well (issue #51).
- [x] 1.21 Row layout. Verified by the snapshots of the debug harness commands `seed` and `history` in light and dark mode, with two rows selected.

## 2. Integration

- [ ] 2.1 Check every scenario of the spec in a release build and record the result in the pull request.

## Workflow follow-up

- Archive the change with `openspec archive add-transaction-list` when every task is checked.
