# Tasks

One task per requirement of the spec. A task is checked only when a test or a check in the running app shows the behavior.

## 1. Requirements

- [x] 1.1 One row per transaction. Verified by the debug harness snapshot in the first build.
- [x] 1.2 Newest transactions first. Verified by LedgerTests "Newest first".
- [ ] 1.3 Details from the bank. Built in part: the transaction sheet shows the details. Finish it and verify it with a test or in the app.
- [x] 1.4 Account name in group and category views. Verified by the debug harness snapshot in the first build.
- [ ] 1.5 Pending transactions look different. Built in part: italic with a "Pending" label instead of hatching; the header shows "Pending" with the sum of the pending transactions of the view and nothing without them, see the debug harness snapshot. Finish the hatching and verify it in the app.
- [x] 1.6 New transactions are marked. Verified by a dot in the row, see the debug harness snapshot in the first build.
- [ ] 1.7 Text can be selected and copied. Built in part: text selection is on. Finish it and verify it with a test or in the app.
- [x] 1.8 Several rows can be selected. Verified by the table allows a multiple selection.
- [x] 1.9 The context menu acts on the selection. Verified by the menu receives the selected rows.
- [x] 1.10 Checkmarks. Verified by checkbox column; LedgerTests use the status filter.
- [x] 1.11 Mark all transactions as checked. Verified by File menu command.
- [ ] 1.12 Checkmarks can be hidden. Build it and verify it with a test or in the app.
- [x] 1.13 Comments. Verified by "Add Comment..." with ⇧⌘K and a note icon in the row.
- [ ] 1.14 Daily balance in the list. Build it and verify it with a test or in the app.
- [x] 1.15 Go to the account or the category. Verified by "Go to" in the context menu.
- [ ] 1.16 Edit a transaction. Built in part: all fields of offline transactions; category and comment of others. Finish it and verify it with a test or in the app.
- [x] 1.17 Delete transactions. Verified by "Delete Transaction..." with the warning that deleted transactions cannot be restored.
- [ ] 1.18 Services for selected text. Build it and verify it with a test or in the app.
- [x] 1.19 Empty states. Verified by the debug harness snapshot in the first build.
- [ ] 1.20 The list stays fluid with a large history. Build it and verify it with a test or in the app.

## 2. Integration

- [ ] 2.1 Check every scenario of the spec in a release build and record the result in the pull request.

## Workflow follow-up

- Archive the change with `openspec archive add-transaction-list` when every task is checked.
