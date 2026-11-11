# Spec Delta

## Purpose

The main window is the frame for everything else in the app. This capability defines the sidebar, the toolbar, navigation between views, the filter bar frame, the status line, the menus that follow the selection, and the state that the window remembers.

## ADDED Requirements

### Requirement: One main window with a sidebar and a content view

The app SHALL show one main window with a sidebar on the left and one content view on the right. Selecting a row in the sidebar shows the view of that row in the content view.

#### Scenario: Select an account

- **GIVEN** the sidebar shows the account "Girokonto"
- **WHEN** the user clicks "Girokonto"
- **THEN** the content view shows the transactions of "Girokonto"

#### Scenario: Select a group

- **GIVEN** the account group "Private" with 2 accounts
- **WHEN** the user clicks "Private"
- **THEN** the content view shows the transactions of both accounts

### Requirement: Look of the sidebar and the selection

The app SHALL draw the sidebar with the system sidebar material of macOS, Liquid Glass from macOS 26 on, with no fill of its own. Selected rows and controls use a muted slate blue instead of the system blue.

#### Scenario: Selected row

- **GIVEN** the system accent color is "Multicolor"
- **WHEN** the user selects a transaction
- **THEN** the row is slate blue with white text

### Requirement: Sidebar rows in a fixed order

The app SHALL show the sidebar rows in this order from top to bottom. "Dashboard". The section "Accounts" with account groups and accounts. The section "Payments" with "Outbox", "Scheduled", and "Templates". The section "Documents" with "Statements". The section "Searches" with the saved searches. The section "Categories" with category groups and categories, ending with "Uncategorized".

#### Scenario: All features installed

- **GIVEN** a version of the app that has all features
- **WHEN** the user opens the main window
- **THEN** "Dashboard" is the first row and "Uncategorized" is the last row
- **AND** "Payments" stands between the accounts and "Documents"

### Requirement: Rows appear with their feature

The app SHALL show a sidebar row, a toolbar control, and a menu command only when the feature behind it is part of the installed version.

#### Scenario: Version without payments

- **GIVEN** a version of the app without payment features
- **WHEN** the user opens the main window
- **THEN** the sidebar has no "Payments" section
- **AND** the toolbar has no "Bank transfer" button

### Requirement: Collapse and expand

The app SHALL let the user collapse and expand each sidebar section and each group, and it SHALL remember that state when the app restarts.

#### Scenario: Hidden categories stay hidden

- **WHEN** the user collapses the section "Categories" and restarts the app
- **THEN** the section "Categories" is still collapsed

### Requirement: Account rows show name, balance, and currency

The app SHALL show for each account in the sidebar its name and its balance with the currency. A negative balance is marked. The row shows no balance when the settings of the account hide it.

#### Scenario: Account in euros

- **GIVEN** the account "Girokonto" with a balance of 1.234,56 €
- **WHEN** the user looks at the sidebar
- **THEN** the row reads "Girokonto" with "1.234,56 €"

#### Scenario: Account in another currency

- **GIVEN** the account "Dollar-Konto" with a balance of 500,00 US dollars
- **WHEN** the user looks at the sidebar
- **THEN** the row shows the balance with the currency US dollar

### Requirement: A collapsed group stands for its accounts

The app SHALL show on a collapsed account group the sum of its accounts, when the settings of the group allow the sum, and the markers of its accounts. Markers are the error indicator and the count of new transactions.

#### Scenario: Error inside a collapsed group

- **GIVEN** the group "Private" is collapsed and one of its accounts had a failed refresh
- **WHEN** the user looks at the sidebar
- **THEN** the row "Private" shows the error indicator

### Requirement: Error indicator on an account row

The app SHALL show an error indicator in the sidebar row of an account whose last refresh failed. A click on the indicator opens the details of the error.

#### Scenario: Failed refresh

- **GIVEN** the last refresh of "Girokonto" failed because the bank rejected the PIN
- **WHEN** the user clicks the error indicator in the row of "Girokonto"
- **THEN** the app shows the message of the bank and the time of the failure

### Requirement: Count of new transactions on an account row

The app SHALL show the number of new transactions next to an account in the sidebar. The number disappears when the user has opened the account.

#### Scenario: Three new transactions

- **GIVEN** a refresh brought 3 new transactions for "Girokonto"
- **WHEN** the user looks at the sidebar
- **THEN** the row "Girokonto" shows the number 3
- **AND** the number is gone after the user has opened "Girokonto" and selected another row

### Requirement: Reorder rows by dragging

The app SHALL let the user drag a row to another position inside its own section, and it SHALL remember the order. A row cannot be dropped into another section.

#### Scenario: Move an account up

- **GIVEN** the accounts "Girokonto" and "Tagesgeld" in this order
- **WHEN** the user drags "Tagesgeld" above "Girokonto" and restarts the app
- **THEN** "Tagesgeld" stands above "Girokonto"

#### Scenario: Wrong section

- **WHEN** the user drags the account "Girokonto" onto the section "Categories"
- **THEN** the app does not accept the drop

### Requirement: Add menu below the sidebar

The app SHALL show a menu button below the sidebar with the commands "Add account", "Add account group", "Add category", "Add category group", and "Add template group".

#### Scenario: Add a category group

- **WHEN** the user chooses "Add category group" from the menu button
- **THEN** a new category group appears in the section "Categories" with its name ready for editing

### Requirement: Refresh button below the sidebar

The app SHALL show a button "Refresh accounts" below the sidebar that starts a refresh of all accounts and shows that a refresh is running.

#### Scenario: Start a refresh

- **WHEN** the user clicks "Refresh accounts"
- **THEN** the refresh of all accounts starts
- **AND** the button shows activity until the refresh has ended

### Requirement: Toolbar

The app SHALL show a toolbar with these controls from left to right. The lock button. The view switch with "Show list only", "Show bar chart", and "Show pie chart". The print menu. The action button. "Previous view" and "Next view". The search field.

#### Scenario: Account view

- **WHEN** the user selects an account
- **THEN** all toolbar controls are visible and the view switch is enabled

#### Scenario: View without charts

- **WHEN** the user selects "Outbox"
- **THEN** the view switch is disabled

### Requirement: The action button follows the view

The app SHALL name the action button in the toolbar after the main action of the current view. It reads "Bank transfer" in account, category, and dashboard views, "Batch transfer" in the outbox, "Standing order" in the scheduled view, and "Add template" in the templates view.

#### Scenario: Outbox

- **WHEN** the user selects "Outbox"
- **THEN** the action button reads "Batch transfer"

#### Scenario: Account

- **WHEN** the user selects the account "Girokonto" and clicks the action button
- **THEN** a payment window opens with "Girokonto" as the source account

### Requirement: Back and forward

The app SHALL keep a history of the views that the user visited in this session. "Back" (⌘[) and "Previous view" in the toolbar return to the view before. "Forward" (⌘]) and "Next view" go the other way. Each command is disabled when there is no view in its direction.

#### Scenario: Go back

- **GIVEN** the user opened "Girokonto" and then the category "Groceries"
- **WHEN** the user presses ⌘[
- **THEN** the content view shows "Girokonto" and the sidebar selects it
- **AND** "Forward" is enabled

#### Scenario: Nothing to go forward to

- **GIVEN** the user has not gone back
- **WHEN** the user opens the View menu
- **THEN** "Forward" is disabled

### Requirement: Filter bar

The app SHALL show a filter bar above the list with the filters that the current view defines. Each filter is a menu that shows its current value, and "Show All" is the value of a filter that is not set.

#### Scenario: Account view

- **WHEN** the user selects an account
- **THEN** the filter bar shows "Period", "Status", "Amount", and "Category", each with "Show All"

#### Scenario: Category view

- **WHEN** the user selects a category
- **THEN** the filter bar shows "Account" in the place of "Category"

### Requirement: Keep the filter bar with the pin

The app SHALL show a pin in the filter bar with the tooltip "Save filter bar". While the pin is on, the filters keep their values when the user changes the view. While the pin is off, a view change sets every filter except "Period" back to "Show All".

#### Scenario: Pin on

- **GIVEN** the pin is on and "Status" is "Unchecked" in the view of "Girokonto"
- **WHEN** the user selects "Tagesgeld"
- **THEN** "Status" is still "Unchecked"

#### Scenario: Pin off

- **GIVEN** the pin is off, "Status" is "Unchecked", and "Period" is "90 Days"
- **WHEN** the user selects "Tagesgeld"
- **THEN** "Status" is "Show All"
- **AND** "Period" is still "90 Days"

### Requirement: Status line

The app SHALL show a status line below the list with the number of rows that the list shows and their sum. The wording follows the kind of row, for example transactions, portfolio items, or scheduled payments.

#### Scenario: Transactions

- **GIVEN** an account view that shows 3 transactions of -20,00 €, -5,50 €, and 100,00 €
- **WHEN** the user looks at the status line
- **THEN** it reads "3 Transactions" and the sum 74,50 €

#### Scenario: One row

- **GIVEN** a list with one transaction
- **WHEN** the user looks at the status line
- **THEN** it reads "1 Transaction"

### Requirement: Copy the sum from the status line

The app SHALL let the user copy the sum in the status line to the pasteboard.

#### Scenario: Copy

- **GIVEN** the status line shows the sum 74,50 €
- **WHEN** the user copies the sum and pastes it into a text document
- **THEN** the text document shows 74,50

### Requirement: The Account menu follows the selection

The app SHALL name the print, remove, refresh, and settings commands of the Account menu after the selected sidebar row, and it SHALL disable the commands that do not apply to that row. The settings command has the shortcut ⌘I, the print command ⌘P, and the refresh command ⇧⌘R.

#### Scenario: Category selected

- **WHEN** the user selects the category "Groceries" and opens the Account menu
- **THEN** the menu shows "Remove Category..." and "Category Settings..."
- **AND** "Import Transactions..." is disabled

#### Scenario: Account group selected

- **WHEN** the user selects the account group "Private"
- **THEN** the menu shows "Remove Account Group...", "Refresh Accounts", and "Account Group Settings..."

#### Scenario: Shortcut

- **WHEN** the user selects the account "Girokonto" and presses ⌘I
- **THEN** the settings of "Girokonto" open

### Requirement: Context menu on sidebar rows

The app SHALL offer a context menu on each sidebar row with the add commands for the section of the row and the commands that apply to the row.

#### Scenario: Account row

- **WHEN** the user opens the context menu of the account "Girokonto"
- **THEN** the menu offers "Add Account...", "Add Account Group", "Print Transactions...", "Import Transactions...", "Export Transactions...", "Remove...", "Refresh Account", and "Settings..."

#### Scenario: Category row

- **WHEN** the user opens the context menu of the category "Groceries"
- **THEN** the menu offers "Add Category", "Add Category Group", "Print Transactions...", "Export Transactions...", "Remove...", and "Settings..."

### Requirement: Empty state

The app SHALL show the text "There are no accounts yet" and a button that starts "Add Account..." in the content view while the database has no account.

#### Scenario: First launch

- **WHEN** the user opens the main window of a new database
- **THEN** the content view shows the text and the button
- **AND** a click on the button opens the add account assistant

### Requirement: Open the main window again

The app SHALL keep running when the user closes the main window. "Main Window" (⌘0) in the Window menu and a click on the Dock icon show the main window again.

#### Scenario: Closed window

- **GIVEN** the user closed the main window
- **WHEN** the user presses ⌘0
- **THEN** the main window is visible with the view it showed before

### Requirement: Full screen

The app SHALL offer "Enter Full Screen" in the View menu for the main window and "Exit Full Screen" while the window is in full screen.

#### Scenario: Enter and leave

- **WHEN** the user chooses "Enter Full Screen" and later "Exit Full Screen"
- **THEN** the main window fills the screen and then returns to its earlier size and position

### Requirement: Remember the window state

The app SHALL remember the size and position of the main window, the width of the sidebar, the selected sidebar row, and the view mode, and it SHALL restore them at the next launch.

#### Scenario: Restart

- **GIVEN** the user made the sidebar wider, selected "Tagesgeld", and chose "Show bar chart"
- **WHEN** the user quits and starts the app
- **THEN** the sidebar has the same width, "Tagesgeld" is selected, and the bar chart is visible

#### Scenario: Selected row no longer exists

- **GIVEN** the remembered row belongs to an account that was removed
- **WHEN** the app starts
- **THEN** the app selects the first row of the sidebar

### Requirement: Standard editing commands

The app SHALL support the Edit menu commands Undo, Redo, Cut, Copy, Paste, and Select All in every text field. In a list, Select All selects all rows and Copy copies the selected rows as text.

#### Scenario: Undo in a text field

- **GIVEN** the user typed a new name into the name field of a category
- **WHEN** the user presses ⌘Z
- **THEN** the field shows the earlier name

#### Scenario: Copy rows

- **WHEN** the user selects 2 transactions and presses ⌘C
- **THEN** the pasteboard holds one line of text for each of the 2 transactions

### Requirement: Usable with the keyboard and with VoiceOver

The app SHALL make every control of the main window reachable with the keyboard, and it SHALL give every control without a text label an Accessibility description. Each row of a list can be read as one text that holds the values of the row.

#### Scenario: Toolbar button without text

- **WHEN** a VoiceOver user moves to the lock button
- **THEN** VoiceOver reads "Lock Moneten"

#### Scenario: Transaction row

- **WHEN** a VoiceOver user moves to a transaction row
- **THEN** VoiceOver reads the date, the amount, the counterparty, the purpose, and the category of that row

### Requirement: About and help commands

The app SHALL offer "About Moneten" in the application menu, with the version, the license, and a link to the source code. The Help menu offers "Help and FAQ..." (⌘?) and "Supported Banks...", and each opens the matching page of the project in the browser.

#### Scenario: About

- **WHEN** the user chooses "About Moneten"
- **THEN** a window shows the version number and names the GNU General Public License

### Requirement: Stay responsive with a large database

The app SHALL show the first rows of a view within half a second and scroll without visible lag when the database holds 50,000 transactions.

#### Scenario: Large group

- **GIVEN** a database with 50,000 transactions in 10 accounts
- **WHEN** the user selects a group that contains all 10 accounts
- **THEN** the first rows are visible within half a second
- **AND** scrolling to the oldest transaction shows no blank rows
