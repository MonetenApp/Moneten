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
- [ ] 1.12 Toolbar. Built in part: lock, view switch, back, forward, and search; no print menu and no action button yet. Finish it and verify it with a test or in the app.
- [ ] 1.13 The action button follows the view. Build it and verify it with a test or in the app.
- [x] 1.14 Back and forward. Verified by ⌘[ and ⌘] and the toolbar arrows.
- [x] 1.15 Filter bar. Verified by the debug harness snapshot in the first build. As measured in the light window of MoneyMoney, a slate band lies behind the title and the chart, the filter bar is light gray with a line between the filters, and the checkboxes are white with a gray border. Verified by window snapshots of the debug harness in light and dark mode.
- [x] 1.16 Keep the filter bar with the pin. Verified by the pin keeps the filters; without it every filter except the period resets.
- [x] 1.17 Status line. Verified by the debug harness snapshot in the first build.
- [ ] 1.18 Copy the sum from the status line. Built in part: the sum text can be selected. Finish it and verify it with a test or in the app.
- [ ] 1.19 The Account menu follows the selection. Built in part: the settings command follows the selection. Finish it and verify it with a test or in the app.
- [ ] 1.20 Context menu on sidebar rows. Built in part: accounts, groups, and categories have menus with a subset of the commands. Finish it and verify it with a test or in the app.
- [x] 1.21 Empty state. Verified by "There are no accounts yet" with the import and add buttons.
- [x] 1.22 Open the main window again. Verified by "Main Window" with ⌘0.
- [x] 1.23 Full screen. Verified by the standard window command.
- [ ] 1.24 Remember the window state. Built in part: SwiftUI restores the window frame. Finish it and verify it with a test or in the app.
- [x] 1.25 Standard editing commands. Verified by the standard Edit menu of SwiftUI.
- [ ] 1.26 Usable with the keyboard and with VoiceOver. Build it and verify it with a test or in the app.
- [ ] 1.27 About and help commands. Built in part: help points to the project on GitHub. Finish it and verify it with a test or in the app.
- [ ] 1.28 Stay responsive with a large database. Built in part: PerformanceTests measure 10 ms for a search and 3 ms for a category view at 50,000 transactions; `scripts/perf-check.sh` measures the views in the app, and most scenarios still block the main thread longer than half a second on a busy Mac. Finish it and verify it with that check.
- [x] 1.29 Look of the sidebar and the selection: the Liquid Glass sidebar of macOS instead of MoneyMoney's opaque gray (user decision), and a slate accent color. Verified by sidebar and window snapshots of the debug harness in light and dark mode.

## 2. Integration

- [ ] 2.1 Check every scenario of the spec in a release build and record the result in the pull request.

## Workflow follow-up

- Archive the change with `openspec archive add-main-window` when every task is checked.
