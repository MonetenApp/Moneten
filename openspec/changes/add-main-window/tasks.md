# Tasks

One task per requirement of the spec. A task is checked only when a test or a check in the running app shows the behavior.

## 1. Requirements

- [x] 1.1 One main window with a sidebar and a content view. Verified by the debug harness snapshot in the first build.
- [x] 1.2 Sidebar rows in a fixed order. Verified by accounts, then categories with "Uncategorized" last; see the sidebar snapshot of the debug harness.
- [x] 1.3 Rows appear with their feature. Verified by no payments, documents, or dashboard rows in this build.
- [x] 1.4 Collapse and expand. Verified by the state is stored with each group and category.
- [x] 1.5 Account rows show name, balance, and currency. Verified by sidebar snapshot of the debug harness.
- [x] 1.6 A collapsed group stands for its accounts. Verified by `AccountTreeTests` (the markers of the accounts in a group and its subgroups) and by a sidebar snapshot of the debug harness: the collapsed group "Private" shows the sum, the count of new transactions, and the error indicator of its failed account (#276).
- [x] 1.7 Error indicator on an account row. Verified by a sidebar snapshot of the debug harness after a failed refresh of the made-up bank: the row shows the message of the bank and the indicator, which opens the popover with the message, the code, and the time (`errorsnapshot`) (#276).
- [x] 1.8 Count of new transactions on an account row. Verified by sidebar snapshot of the debug harness.
- [ ] 1.9 Reorder rows by dragging. Built; the drag gesture is not yet observed. `AccountTreeTests` check `Ledger.move(treeItem:into:at:)`: "Tagesgeld" moves above "Girokonto", a group moves between accounts with its accounts, an account moves into a group at a gap, and a group does not move into itself or a group below it. They also put a row in each gap of a nested group with an expanded subgroup, which counts as one row of that group. That SwiftUI gives the drop index this way inside a nested `DisclosureGroup` is not observed. A drop on a group row and a drop in the gap beside it end in one place, `AppModel.dropTreeItem(on:)`, which takes the row from the drag and moves it once; the harness command `droptwice` delivers one drop to both targets and the row moved once, into the group. In the debug harness, `movetree` calls the model function of a drop between rows: "Kreditkarte" moved above the group "Private" and "Tagesgeld" above "Girokonto", and both stayed after a restart. Groups and accounts drag as their own type `io.github.moneten.account`, which the rows of the section "Categories" do not take. The harness cannot drag, so the drag gesture and the refused drop on "Categories" are not seen (#276).
- [x] 1.10 Add menu below the sidebar. Verified by the plus menu below the sidebar.
- [x] 1.11 Refresh button below the sidebar. Verified by a sidebar snapshot of the debug harness during a refresh: the button shows a spinner until the refresh has ended (#276).
- [ ] 1.12 Toolbar. Built in part: lock, view switch, back, forward, and search; no print menu and no action button yet. Finish it and verify it with a test or in the app.
- [ ] 1.13 The action button follows the view. Build it and verify it with a test or in the app.
- [x] 1.14 Back and forward. Verified by ⌘[ and ⌘] and the toolbar arrows; the View menu items are disabled like the arrows when there is no view in their direction (`NavigationHistory` is observable).
- [x] 1.15 Filter bar. Verified by the debug harness snapshot in the first build. As measured in the light window of MoneyMoney, a slate band lies behind the title and the chart, the filter bar is light gray with a line between the filters, and the checkboxes are white with a gray border. Verified by window snapshots of the debug harness in light and dark mode.
- [x] 1.16 The filter bar across views and the pin. Verified by task 1.13 of the change `add-transaction-search-and-filters`, which builds these requirements and is checked.
- [x] 1.17 Status line. The number and the sum are verified by the debug harness snapshot in the first build. The sum leaves out a pending transaction marked for review and the number counts it, verified with task 1.30 of the change `add-account-refresh`.
- [ ] 1.18 Copy the sum from the status line. Built in part: the sum text can be selected. Finish it and verify it with a test or in the app.
- [x] 1.19 The Account menu follows the selection. Verified by the harness command `menu Account` with an account, a group, a category, and "Uncategorized" selected: "Remove Account...", "Remove Account Group...", and "Remove Category..." with the refresh and settings commands named after the row, "Import Transactions..." disabled outside an account, and remove disabled for "Uncategorized". The print command comes with the change `add-printing` (requirement "Rows appear with their feature") (#276).
- [x] 1.20 Context menu on sidebar rows. Verified by the harness command `contextmenus`: accounts offer "Add Account...", "Add Account Group", "Import Transactions...", "Export Transactions...", "Remove...", "Refresh Account", and "Settings...", groups and categories their commands of the spec, and "Remove..." asks before it removes. "Print Transactions..." comes with the change `add-printing` (#276).
- [x] 1.21 Empty state. Verified by "There are no accounts yet" with the import and add buttons.
- [x] 1.22 Open the main window again. Verified by "Main Window" with ⌘0.
- [x] 1.23 Full screen. Verified by the standard window command.
- [ ] 1.24 Remember the window state. Built in part: SwiftUI restores the window frame. Finish it and verify it with a test or in the app.
- [x] 1.25 Standard editing commands. Verified by the standard Edit menu of SwiftUI.
- [ ] 1.26 Usable with the keyboard and with VoiceOver. Built; not yet observed with VoiceOver. Every icon control of the main window has an Accessibility label: the toolbar (#279), the error indicator, the count of new transactions, and the refresh button below the sidebar (#276), and the add menu, the pin of the filter bar, the refresh button of the account header, the comment and review icons, the dot of a new transaction, and the category ribbon of a row, which reads the category also where an uncategorized row shows none (#283). The cells of a transaction row hold the date, the category, the counterparty, the purpose, the amount, and the checkmark, and the decorative row chrome is hidden. The screen was locked during the runs, so neither VoiceOver nor the Accessibility tree of the window could be read, and Full Keyboard Access was not tried.
- [ ] 1.27 About and help commands. Built in part: help points to the project on GitHub. Finish it and verify it with a test or in the app.
- [ ] 1.28 Stay responsive with a large database. Built in part: PerformanceTests measure 10 ms for a search and 3 ms for a category view at 50,000 transactions; `scripts/perf-check.sh` measures the views in the app, and most scenarios still block the main thread longer than half a second on a busy Mac. Finish it and verify it with that check.
- [x] 1.29 Look of the sidebar and the selection: the Liquid Glass sidebar of macOS instead of MoneyMoney's opaque gray (user decision), and a slate accent color. Verified by sidebar and window snapshots of the debug harness in light and dark mode.
- [x] 1.30 Sums beyond the range of amounts (issue #324). `AmountOverflowTests` cover the balance, the group sum, the status line, the category amounts, the charts, the notice of new transactions, and the calibration with stored rows of 50.000.000.000.000.000,00 €. The suite crashed before `Int64.addingClamped(_:)` and passes after it.

## 2. Integration

- [ ] 2.1 Check every scenario of the spec in a release build and record the result in the pull request.

## Workflow follow-up

- Archive the change with `openspec archive add-main-window` when every task is checked.
