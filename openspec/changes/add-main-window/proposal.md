# Proposal: Build the main window with sidebar, toolbar, filter bar, and status line

## Why

Users need one window that shows every account, every category, and everything that belongs to them. People who switch from MoneyMoney know where each thing is. The shell must put the same things in the same places, so that every later feature has a home and nobody has to learn the app again.

## What Changes

- One main window with a sidebar on the left and one content view on the right.
- The sidebar has the rows "Dashboard", "Accounts", "Payments", "Documents", and "Categories" in a fixed order. A row appears when its feature is part of the installed version.
- Two buttons below the sidebar add things and refresh all accounts.
- The toolbar has the lock button, the view switch, the print menu, one action button that depends on the view, back and forward, and the search field.
- A filter bar above the list shows the filters of the current view. A pin keeps the filters when the view changes.
- A status line below the list shows the count and the sum of what the list shows.
- The Account menu and the context menu of a sidebar row follow the selection.
- The window remembers its size, its position, the width of the sidebar, and which rows are collapsed.

## Capabilities

### New Capabilities

- `main-window`: the frame of the app. It covers the sidebar, the toolbar, navigation between views, the filter bar frame, the status line, the menus that follow the selection, and the state of the window.

### Modified Capabilities

None.

## Impact

- Milestone: v0.1
- Issues: #5
- Modules: `App` owns the window, the sidebar, the toolbar, and the menus.
- Depends on the change `add-encrypted-database`.
- These changes fill the frame and own their own behavior. `add-transaction-list` owns the content of the list. `add-transaction-search-and-filters` owns the search and what each filter does. `add-charts` owns what the three view modes show. `add-account-management` and `add-categories` own the rows of their sections. `add-account-refresh` owns the refresh and the error details. `add-app-lock` owns the lock. `add-dashboard`, the payment changes, and `add-bank-statements` own the views of their rows.
- Decisions: [ADR 0001](../../../docs/decisions/0001-native-mac-app-in-swift.md).

## Reference behavior

### Observed in MoneyMoney 2.5.3

- The layout of the main window, the order of the sidebar rows, the two buttons below the sidebar, the toolbar, the filter bar, and the status line are described in the [analysis](../../../docs/research/moneymoney-analysis.md#main-window-u).
- The action button in the toolbar reads "Bank transfer", "Batch transfer", "Standing order", or "Add template", depending on the view.
- The view switch is disabled on the dashboard and in the outbox, scheduled, and templates views.
- The menus, their shortcuts, and the way the Account menu follows the selection are listed in the [analysis](../../../docs/research/moneymoney-analysis.md#menus-and-keyboard-shortcuts-u). The context menus of the sidebar rows are listed in the [analysis](../../../docs/research/moneymoney-analysis.md#context-menus-u).
- Back and forward between views work through arrows in the toolbar (version history, 2.4.10).
- A pin in the filter bar keeps the filters between views (version history, 2.4.9).
- The sum in the status line can be copied to the pasteboard (version history, 2.2.15).
- A collapsed account group shows the balance and the markers of its accounts (version history, 2.1.2).
- The sidebar shows the currency of an account (version history, 2.2.10).
- A hidden category tree stays hidden after a restart (version history, 2.3.23).
- The window size is stored and restored (version history, 2.2.2).
- An account with a failed refresh shows the error text in its sidebar row.
- The interface strings include "There are no accounts yet" and "No accounts present.".
- The controls of the main window carry Accessibility descriptions, and each list row can be read as text.

### Decided for MonetenMoneten

- The sidebar keeps the system material of macOS instead of the opaque gray of MoneyMoney (ADR 0012).
- Selections and controls use a muted slate blue. MoneyMoney uses the system blue.
- A sidebar row and a toolbar control appear only when their feature is part of the installed version. Version 0.1 has no "Dashboard", "Payments", or "Documents" row.
- The number of new transactions next to an account in the sidebar comes from names in the program file. How MoneyMoney draws it was not observed.
- Without the pin, a view change sets all filters except "Period" back to "Show All". MoneyMoney's behavior without the pin was not observed.
- The window opens with the row that was selected when the app quit. MoneyMoney's start view was not observed.
- Copy on selected list rows copies them as text, one line for each row. The Edit menu of MoneyMoney was observed only without a selection.
- A row cannot be dragged into another section. Dragging in MoneyMoney was not tested, because it changes data.
- The numbers for speed with 50,000 transactions come from issue #5 and are a target of this project.
- The application menu has no license key, imprint, or license agreement command. "About MonetenMoneten" shows the version, the license, and a link to the source code.
- "Help and FAQ..." and "Supported Banks..." open pages of the project. The Help menu has one "Supported Banks..." command and no split by country.
- The app keeps running when the main window closes. This follows from "Main Window" in the Window menu and from the lock setting for a closed main window. It was not tested.
