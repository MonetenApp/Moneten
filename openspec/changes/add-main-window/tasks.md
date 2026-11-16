# Tasks

One task per requirement of the spec. A task is checked only when a test or a check in the running app shows the behavior.

## 1. Requirements

- [x] 1.1 One main window with a sidebar and a content view. Verified by the debug harness snapshot in the first build.
- [x] 1.2 Sidebar rows in a fixed order. Verified by accounts, then categories with "Uncategorized" last; see the sidebar snapshot of the debug harness.
- [x] 1.3 Rows appear with their feature. Verified by no payments, documents, or dashboard rows in this build.
- [x] 1.4 Collapse and expand. Verified by the state is stored with each group and category.
- [x] 1.5 Account rows show name, balance, and currency. Verified by sidebar snapshot of the debug harness.
- [ ] 1.6 A collapsed group stands for its accounts. Build it and verify it with a test or in the app.
- [ ] 1.7 Error indicator on an account row. Build it and verify it with a test or in the app.
- [x] 1.8 Count of new transactions on an account row. Verified by sidebar snapshot of the debug harness.
- [ ] 1.9 Reorder rows by dragging. Build it and verify it with a test or in the app.
- [x] 1.10 Add menu below the sidebar. Verified by the plus menu below the sidebar.
- [ ] 1.11 Refresh button below the sidebar. Build it and verify it with a test or in the app.
- [x] 1.12 Toolbar. Lock, view switch, "Previous view", "Next view", and the search field, from left to right in one group of the toolbar (#279). The print menu comes with the change `add-printing` and the action button with the payment changes, as the requirement "Rows appear with their feature" says, and this build has no view without charts. Verified by the order of the items in `MainView` and the toolbar of the running debug build, which holds the group of four controls left of the search field. The screen was locked, so the items were not seen.
- [ ] 1.13 The action button follows the view. Waits for the payment changes (`add-sepa-transfers`, milestone v0.2): this build has no payment feature, so the toolbar has no action button (requirement "Rows appear with their feature").
- [x] 1.14 Back and forward. Verified by ⌘[ and ⌘] and the toolbar arrows; the View menu items are disabled like the arrows when there is no view in their direction (`NavigationHistory` is observable).
- [x] 1.15 Filter bar. Verified by the debug harness snapshot in the first build. As measured in the light window of MoneyMoney, a slate band lies behind the title and the chart, the filter bar is light gray with a line between the filters, and the checkboxes are white with a gray border. Verified by window snapshots of the debug harness in light and dark mode.
- [x] 1.16 The filter bar across views and the pin. Verified by task 1.13 of the change `add-transaction-search-and-filters`, which builds these requirements and is checked.
- [x] 1.17 Status line. The number and the sum are verified by the debug harness snapshot in the first build. The sum leaves out a pending transaction marked for review and the number counts it, verified with task 1.30 of the change `add-account-refresh`.
- [x] 1.18 Copy the sum from the status line. "Copy Sum" in the context menu of the sum puts the number on the pasteboard (#279). Verified by `CopySumTests`: 74,50 € copies as "74,50", a negative sum keeps a plain minus and no thousands separators, an empty sum is zero in the currency of the view, and several currencies give one line each. The harness cannot open the context menu, so the click was not seen.
- [ ] 1.19 The Account menu follows the selection. Built in part: the settings command follows the selection. Finish it and verify it with a test or in the app.
- [ ] 1.20 Context menu on sidebar rows. Built in part: accounts, groups, and categories have menus with a subset of the commands. Finish it and verify it with a test or in the app.
- [x] 1.21 Empty state. Verified by "There are no accounts yet" with the import and add buttons.
- [x] 1.22 Open the main window again. Verified by "Main Window" with ⌘0.
- [x] 1.23 Full screen. Verified by the standard window command.
- [x] 1.24 Remember the window state. SwiftUI restores the window frame and the width of the sidebar, the view mode is a setting, and the selected row is the setting `selectedSidebarRow` (#279). Verified in the debug build after "Quit" and a new start: the sidebar kept 360 and then 410 points (harness command `sidebarwidth`), "Girokonto" stayed selected with the pie chart, and a stored row of a removed account selected the first row, the group "Private".
- [x] 1.25 Standard editing commands. Verified by the standard Edit menu of SwiftUI.
- [ ] 1.26 Usable with the keyboard and with VoiceOver. Built; not yet observed with VoiceOver. Every icon control of the main window has an Accessibility label: the toolbar (#279), the error indicator, the count of new transactions, and the refresh button below the sidebar (#276), and the add menu, the pin of the filter bar, the refresh button of the account header, the comment and review icons, the dot of a new transaction, and the category ribbon of a row, which reads the category also where an uncategorized row shows none (#283). The cells of a transaction row hold the date, the category, the counterparty, the purpose, the amount, and the checkmark, and the decorative row chrome is hidden. The screen was locked during the runs, so neither VoiceOver nor the Accessibility tree of the window could be read, and Full Keyboard Access was not tried.
- [ ] 1.27 About and help commands. Built in part (#279): "About Moneten" shows the version, the license, and a link to the source code, verified by a snapshot of the panel in the debug build, and "Help and FAQ..." (⌘?) opens the README of the project, verified by the Help menu of the debug build. "Supported Banks..." comes with PR #263.
- [ ] 1.28 Stay responsive with a large database. Built in part: PerformanceTests measure 10 ms for a search and 3 ms for a category view at 50,000 transactions; `scripts/perf-check.sh` measures the views in the app, and most scenarios still block the main thread longer than half a second on a busy Mac. Finish it and verify it with that check.
- [x] 1.29 Look of the sidebar and the selection: the Liquid Glass sidebar of macOS instead of MoneyMoney's opaque gray (user decision), and a slate accent color. Verified by sidebar and window snapshots of the debug harness in light and dark mode.

## 2. Integration

- [ ] 2.1 Check every scenario of the spec in a release build and record the result in the pull request.

## Workflow follow-up

- Archive the change with `openspec archive add-main-window` when every task is checked.
