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

### Requirement: Neutral content colors

The app SHALL draw the content view in fixed neutral grays in the light and the dark appearance: the list, the band behind the title and the chart, the filter bar, the status line, and the lines between the rows. These colors do not change with the desktop picture. Text that steps back, such as an empty state or a filter line, has a contrast of at least 4.5:1 on each of these backgrounds, also with "Increase contrast". The sidebar, the toolbar, and the window frame keep the system materials.

#### Scenario: Dark list with a blue desktop picture

- **GIVEN** the dark appearance and a blue desktop picture
- **WHEN** the user looks at the transactions of "Girokonto"
- **THEN** the list is #161618, the band is #1D1D1F, and the filter bar is #1A1A1C

#### Scenario: Light list

- **GIVEN** the light appearance
- **WHEN** the user looks at the positions of the portfolio "Depot"
- **THEN** the list is #FFFFFF, the band is #F5F5F7, and the filter bar is #FAFAFA

### Requirement: Whole amounts in the sidebar

The app SHALL show each balance of an account and each sum of a group in the sidebar on one line and in full, and shorten a long name of the account or the group first. When the balances of an account do not all fit, the row shows the first balance and the number of the others. An amount that does not fit ends with an ellipsis and is never cut off at the edge of the row.

#### Scenario: Long name with large balances

- **GIVEN** a sidebar 340 points wide, the group "Private" with the sums 16.946.892,85 € and 11.111.110,00 US dollars, and in it the account "Reisekasse" with the balances 4.567.890,00 € and 1.234.567,00 US dollars
- **WHEN** the user looks at the sidebar
- **THEN** the group row shows 16.946.892,85 € and 11.111.110,00 US dollars in full
- **AND** the account row shows 4.567.890,00 € and 1.234.567,00 US dollars in full
- **AND** the names "Private" and "Reisekasse" end with an ellipsis

#### Scenario: Sums wider than the narrowest sidebar

- **GIVEN** a sidebar 240 points wide and the group "Private" with the sums 16.946.892,85 € and 99.999.999,00 US dollars
- **WHEN** the user looks at the sidebar
- **THEN** the group row shows an ellipsis in place of the name "Private"
- **AND** it shows 16.946.892,85 € in full
- **AND** the sum in US dollars ends with an ellipsis

#### Scenario: Balances in eight currencies in a narrow row

- **GIVEN** a sidebar 240 points wide and the account "Devisen" with 1.250,00 € and balances in seven other currencies
- **WHEN** the user looks at the sidebar
- **THEN** the row "Devisen" shows 1.250,00 € in full and then "+ 7 more"
- **AND** it shows no part of the other seven balances

#### Scenario: Balances in twenty currencies in a narrow row

- **GIVEN** a sidebar 240 points wide and the account "Devisen" with 1.250,00 € and balances in nineteen other currencies
- **WHEN** the user looks at the sidebar
- **THEN** the row "Devisen" shows 1.250,00 € and then "+19"

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

### Requirement: Sums beyond the range of amounts

The app SHALL keep running when a balance or a sum of stored amounts exceeds the largest amount it can hold. Such a sum shows that largest amount, 92.233.720.368.547.758,07 € for the euro, with its sign.

#### Scenario: Database with absurd amounts

- **GIVEN** a database holds two transactions of 50.000.000.000.000.000,00 € in the CSV account "Giro"
- **WHEN** the user unlocks the database
- **THEN** the main window opens and the account "Giro" shows 92.233.720.368.547.758,07 €
- **AND** the user can delete the two transactions

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

### Requirement: Name a new group in the sidebar

The app SHALL let the user type the name of a new account group or category group in its sidebar row, which is in edit mode when the group appears and which the sidebar scrolls into view. Return stores the typed name without spaces at its ends, and so does a move of the focus away from the row, such as a click on another row. Escape, or a name that is empty or only spaces, keeps the name that the row had when edit mode began. The group stays in every case, and the row leaves edit mode.

#### Scenario: Name confirmed with Return

- **WHEN** the user chooses "Add Account Group", types "  Travel  ", and presses Return
- **THEN** the sidebar shows the selected group "Travel", and the row is no longer in edit mode

#### Scenario: Escape on the new row

- **WHEN** the user chooses "Add Category Group", types "Mobility", and presses Escape
- **THEN** the sidebar shows the category group "New group", and the row is no longer in edit mode

#### Scenario: Empty name

- **WHEN** the user chooses "Add Account Group", replaces the name with "   ", and presses Return
- **THEN** the sidebar shows the group "New group"

#### Scenario: New group at the end of a long sidebar

- **GIVEN** the section "Accounts" holds 43 accounts, and the sidebar shows its top
- **WHEN** the user chooses "Add Account Group"
- **THEN** the sidebar scrolls to the row "New group" below the last account, and the name field has the focus

#### Scenario: Focus leaves the row

- **WHEN** the user chooses "Add Category Group", types "Mobility", and clicks the category "Groceries"
- **THEN** the sidebar shows the category group "Mobility", and the row is no longer in edit mode

### Requirement: Taken name in the row of a new category group

The app SHALL keep the sidebar row of a new category group in edit mode when Return confirms a name that the requirement "Name of a category" refuses because another entry of the same group has it, and SHALL say under the field that the name is taken. Typing clears the note. When the focus leaves the row with such a name, the row keeps the name that it had when edit mode began.

#### Scenario: Taken name and Return

- **GIVEN** the category "Fuel" at the top level, and no category is selected
- **WHEN** the user chooses "Add Category Group", types "fuel", and presses Return
- **THEN** the row stays in edit mode with "fuel" and says "Name taken at the top level."

#### Scenario: Taken name and the focus leaves the row

- **GIVEN** the category "Fuel" at the top level, and no category is selected
- **WHEN** the user chooses "Add Category Group", types "Fuel", and clicks the category "Groceries"
- **THEN** the sidebar shows the category group "New group", and the row is no longer in edit mode

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

The app SHALL show a filter bar above the list with the filters that the current view defines. Each filter is a menu that shows its current value, and "Show All" is the value of a filter that is not set. The capability "transaction-search-and-filters" specifies which filters stay when the view changes and what the pin in the filter bar does.

#### Scenario: Account view

- **WHEN** the user selects an account
- **THEN** the filter bar shows "Period", "Status", "Amount", and "Category", each with "Show All"

#### Scenario: Category view

- **WHEN** the user selects a category
- **THEN** the filter bar shows "Account" in the place of "Category"

### Requirement: Status line

The app SHALL show a status line below the list with the number of rows that the list shows and their sum. The wording follows the kind of row, for example transactions, portfolio items, or scheduled payments. A pending transaction marked for review counts in the number but not in the sum.

#### Scenario: Transactions

- **GIVEN** an account view that shows 3 transactions of -20,00 €, -5,50 €, and 100,00 €
- **WHEN** the user looks at the status line
- **THEN** it reads "3 Transactions" and the sum 74,50 €

#### Scenario: One row

- **GIVEN** a list with one transaction
- **WHEN** the user looks at the status line
- **THEN** it reads "1 Transaction"

#### Scenario: Pending transactions under review

- **GIVEN** a list with two pending transactions of -3,20 € and one booked transaction of -3,20 €, all three marked for review
- **WHEN** the user looks at the status line
- **THEN** it reads "3 Transactions" and the sum -3,20 €

### Requirement: Copy the sum from the status line

The app SHALL let the user copy the sum in the status line to the pasteboard.

#### Scenario: Copy

- **GIVEN** the status line shows the sum 74,50 €
- **WHEN** the user chooses "Copy Sum" in the context menu of the sum and pastes it into a text document
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

### Requirement: Return never confirms an action that cannot be undone

The app SHALL ask before an action that cannot be undone with a question whose action button has no key: Return presses nothing, Escape cancels, and only a click carries the action out. This holds for removing an account, an account group, a category, or a category group, deleting transactions, undoing a split, removing an extension, and removing a saved PIN.

#### Scenario: Return in the question before removing an account

- **GIVEN** the question "Are you sure you want to remove the account Girokonto?" shows
- **WHEN** the user presses Return
- **THEN** the question stays open, and "Girokonto" stays
- **AND** Escape closes the question, and "Girokonto" stays

#### Scenario: Return in the question before deleting transactions

- **GIVEN** the question "Delete 2 selected transactions?" shows
- **WHEN** the user presses Return
- **THEN** the question stays open, and both transactions stay

#### Scenario: Return in the sheet that undoes a split

- **GIVEN** the sheet "Replace the split transactions with the original transaction?" shows for a split of -80,00 € into two parts
- **WHEN** the user presses Return
- **THEN** the sheet stays open, and both parts stay
- **AND** a click on "Undo Split Transaction" brings back one transaction of -80,00 €

#### Scenario: Return in the question before removing an extension

- **GIVEN** the question "Remove Example Bank?" shows in the Extensions window
- **WHEN** the user presses Return
- **THEN** the question stays open, and the extension stays installed

### Requirement: About and help commands

The app SHALL offer "About Moneten" in the application menu, with the version, the license, and a link to the source code. The Help menu offers "Help and FAQ..." (⌘?), which opens the help page of the project in the browser, and "Supported Banks...", which opens the list of supported banks in a window of the app.

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
