# Spec Delta

## Purpose

Categories group transactions by what the money was for. This capability defines the category tree in the sidebar, the default category, the settings of a category, how the user assigns categories by hand, and what a category view shows.

## ADDED Requirements

### Requirement: Category tree in the sidebar

The app SHALL show a section "Categories" in the sidebar with all categories and category groups as a tree. A category group can contain categories and other category groups to any depth.

#### Scenario: Nested groups

- **GIVEN** the group "Living" with the group "Home" inside it, and the category "Rent" inside "Home"
- **WHEN** the user expands "Living" and "Home"
- **THEN** the sidebar shows "Rent" indented below "Home", and "Home" indented below "Living"

### Requirement: Add a category

The app SHALL create a category with "Add Category". The new category appears in the selected category group, or at the top level when no group is selected, and its name is ready for typing.

#### Scenario: Add inside a group

- **GIVEN** the category group "Living" is selected
- **WHEN** the user chooses "Add Category" and types "Electricity"
- **THEN** the sidebar shows the category "Electricity" inside "Living"

#### Scenario: Same name twice

- **GIVEN** the group "Living" contains the category "Electricity"
- **WHEN** the user names a second category in "Living" "Electricity"
- **THEN** the app keeps the name field open and says that the name is taken in this group

### Requirement: Add a category group

The app SHALL create a category group with "Add Category Group". A group holds no transactions of its own.

#### Scenario: New group

- **WHEN** the user chooses "Add Category Group" and types "Mobility"
- **THEN** the sidebar shows the empty group "Mobility"

### Requirement: Move categories by drag and drop

The app SHALL let the user drag a category or a category group to another position, into a group, or out of a group. The transactions stay with their category.

#### Scenario: Move into a group

- **GIVEN** the category "Fuel" at the top level with 20 transactions
- **WHEN** the user drags "Fuel" onto the group "Mobility"
- **THEN** "Fuel" stands inside "Mobility" and still has its 20 transactions

#### Scenario: Reorder

- **WHEN** the user drags "Groceries" above "Leisure"
- **THEN** the sidebar and every category menu list "Groceries" before "Leisure"

### Requirement: Default category

The app SHALL keep one default category named "Uncategorized" as the last entry of the section. It holds every transaction that has no other category. The user can rename it in its settings and cannot remove or move it.

#### Scenario: New transaction without a match

- **WHEN** a new transaction arrives and no rule matches it
- **THEN** the transaction is in "Uncategorized"

#### Scenario: Remove is disabled

- **WHEN** the user opens the context menu of "Uncategorized"
- **THEN** "Remove..." is disabled

#### Scenario: Rename

- **WHEN** the user changes the name of the default category to "To sort"
- **THEN** the sidebar and all category menus show "To sort" in its place

### Requirement: Category settings

The app SHALL open the settings of the selected category with "Category Settings..." or ⌘I. The settings hold "Name", "Currency", a color, an icon, "Show in diagrams", "Display in sidebar", and "Restrict to". A change takes effect when the user closes the settings.

#### Scenario: Open with the keyboard

- **GIVEN** the category "Groceries" is selected in the sidebar
- **WHEN** the user presses ⌘I
- **THEN** the app shows the settings of "Groceries"

#### Scenario: Rename

- **WHEN** the user changes "Name" from "Groceries" to "Food" and closes the settings
- **THEN** the sidebar, the transaction rows, and the category menus show "Food"

### Requirement: Category color

The app SHALL let the user choose a color for each category in its settings. The app uses this color for the category wherever a chart draws it.

#### Scenario: Change the color

- **WHEN** the user sets the color of "Groceries" to green
- **THEN** the slice of "Groceries" in the pie chart is green

### Requirement: Category icon

The app SHALL let the user choose an icon for each category in its settings, from a set of SF Symbols, or no icon. The sidebar, the title of the category view, and the category menu of the ribbon show the icon in the color of the category. A category without an icon shows a bookmark, and a category group a folder. A migration takes only the color of an icon from the other program, not the picture.

#### Scenario: Choose an icon

- **WHEN** the user chooses the shopping cart as the icon of "Groceries" and closes the settings
- **THEN** the sidebar shows a shopping cart in the color of "Groceries" in place of its bookmark

#### Scenario: Remove the icon

- **GIVEN** "Groceries" shows a shopping cart
- **WHEN** the user chooses the bookmark as its icon and closes the settings
- **THEN** the sidebar shows a bookmark for "Groceries"

### Requirement: Category currency

The app SHALL give each category one currency, which is the euro unless the user changes it. The amount in the sidebar counts the transactions in that currency. Transactions in another currency stay in the category, and the status line of the category view sums them for each currency.

#### Scenario: Mixed currencies

- **GIVEN** the category "Travel" with the currency euro, transactions of -300,00 € in total, and one transaction of -50,00 USD
- **WHEN** the user opens "Travel"
- **THEN** the sidebar amount is -300,00 €
- **AND** the status line shows the sums -300,00 € and -50,00 USD

### Requirement: Amount in the sidebar

The app SHALL show an amount next to a category according to "Display in sidebar". The values are "No amount", "Current month", "Current quarter", "Current year", and "Total sum". The amount is the sum of the transactions of the category in that time. Pending transactions count, except one marked for review, as the capabilities `charts` and `account-refresh` state. A split counts with its parts and never with its original. A category group shows the sum of everything below it.

#### Scenario: Current month

- **GIVEN** today is 09.11.2026, and "Groceries" has transactions of -120,00 € in November 2026 and -480,00 € in October 2026
- **WHEN** "Display in sidebar" of "Groceries" is "Current month"
- **THEN** the sidebar shows -120,00 € next to "Groceries"

#### Scenario: Pending transaction

- **GIVEN** today is 09.11.2026, and "Groceries" has a booked transaction of -80,00 € and a pending transaction of -40,00 € in November 2026
- **WHEN** "Display in sidebar" of "Groceries" is "Current month"
- **THEN** the sidebar shows -120,00 € next to "Groceries"

#### Scenario: Split transaction

- **GIVEN** a card payment of -100,00 € on 02.11.2026 is split into a part of -60,00 € in "Groceries" and a part of -40,00 € in "Household"
- **WHEN** "Display in sidebar" of both categories is "Total sum"
- **THEN** the sidebar shows -60,00 € next to "Groceries" and -40,00 € next to "Household", and neither counts -100,00 €

#### Scenario: No amount

- **WHEN** "Display in sidebar" is "No amount"
- **THEN** the sidebar shows only the name of the category

#### Scenario: Group

- **GIVEN** the group "Living" set to "Total sum", with "Rent" at -9.600,00 € and "Electricity" at -840,00 € in total
- **WHEN** the user looks at the sidebar
- **THEN** "Living" shows -10.440,00 €

### Requirement: Restrict a category to an account

The app SHALL let the user restrict a category to one account or one account group with "Restrict to". Only transactions of that account or group can be assigned to the category.

#### Scenario: Assignment menu

- **GIVEN** the category "Office" is restricted to the account "Business"
- **WHEN** the user opens "Assign Category" on a transaction of the account "Private"
- **THEN** "Office" is disabled in the menu

#### Scenario: Matching account

- **WHEN** the user opens "Assign Category" on a transaction of the account "Business"
- **THEN** "Office" can be chosen

### Requirement: Assign a category from the context menu

The app SHALL offer "Assign Category" in the context menu of a transaction. The submenu lists all categories in sidebar order with their nesting, and it marks the current category with a checkmark. A choice assigns the category to every selected transaction.

#### Scenario: One transaction

- **GIVEN** a transaction in "Uncategorized"
- **WHEN** the user chooses "Assign Category" and then "Groceries"
- **THEN** the transaction is in "Groceries" and its row shows "Groceries"

#### Scenario: Many transactions

- **GIVEN** 15 selected transactions
- **WHEN** the user chooses "Assign Category" and then "Leisure"
- **THEN** all 15 transactions are in "Leisure"

#### Scenario: Current category

- **GIVEN** a transaction in "Groceries"
- **WHEN** the user opens "Assign Category"
- **THEN** "Groceries" has a checkmark

### Requirement: Add a category while assigning

The app SHALL offer "Add category" at the end of the "Assign Category" submenu. It creates a category, asks for its name, and assigns the selected transactions to it.

#### Scenario: New category for a selection

- **GIVEN** 2 selected transactions
- **WHEN** the user chooses "Assign Category", then "Add category", and enters "Pets"
- **THEN** the sidebar shows the category "Pets" with the 2 transactions

### Requirement: Assign a category by drag and drop

The app SHALL assign the dragged transactions to a category when the user drops them on that category in the sidebar. A drop on a category that is restricted to another account is refused.

#### Scenario: Drag three rows

- **GIVEN** 3 selected transactions
- **WHEN** the user drags them onto "Groceries" in the sidebar
- **THEN** the 3 transactions are in "Groceries"

#### Scenario: Restricted target

- **GIVEN** "Office" is restricted to the account "Business"
- **WHEN** the user drags a transaction of the account "Private" over "Office"
- **THEN** the sidebar does not accept the drop

### Requirement: Assign a category with the keyboard

The app SHALL open a category picker for the selected transactions with the shortcut ⌘K. The picker narrows the list of categories while the user types. Return assigns the highlighted category, and Escape closes the picker without a change.

#### Scenario: Type to find

- **GIVEN** a selected transaction
- **WHEN** the user presses ⌘K, types "groc", and presses Return
- **THEN** the transaction is in "Groceries"

#### Scenario: Whole month without the mouse

- **GIVEN** a list of 40 uncategorized transactions
- **WHEN** the user moves through the list with the arrow keys and assigns each row with ⌘K
- **THEN** all 40 transactions have a category and the user never needed the mouse

### Requirement: Remove a transaction from its category

The app SHALL move the selected transactions back to "Uncategorized" with "Remove Transaction from Category" in a category view, or when the user assigns "Uncategorized".

#### Scenario: Remove in the category view

- **GIVEN** the category view "Groceries" with a selected transaction
- **WHEN** the user chooses "Remove Transaction from Category"
- **THEN** the transaction leaves the list of "Groceries" and is in "Uncategorized"

#### Scenario: Several transactions

- **GIVEN** 4 selected transactions in the category view "Groceries"
- **WHEN** the user opens the context menu
- **THEN** the command reads "Remove Transactions from Category"

### Requirement: Category view

The app SHALL list the transactions of the selected category from all accounts in one list. The status line shows their number and their sum, with one sum for each currency. The number also counts a pending transaction marked for review. The sum includes pending transactions, except a pending transaction marked for review, as the capability `account-refresh` states. Both count the parts of a split and not its original.

#### Scenario: Two accounts

- **GIVEN** "Groceries" contains 30 transactions of the account "Giro" and 12 of the account "Credit card"
- **WHEN** the user selects "Groceries"
- **THEN** the list shows 42 transactions and the status line shows their sum

#### Scenario: Pending transaction

- **GIVEN** "Groceries" contains a booked transaction of -80,00 € and a pending transaction of -40,00 €
- **WHEN** the user selects "Groceries"
- **THEN** the status line shows 2 transactions and -120,00 €

#### Scenario: Split transaction

- **GIVEN** a transaction of -100,00 € is split into two parts of -30,00 € and -70,00 €, both in "Groceries"
- **WHEN** the user selects "Groceries"
- **THEN** the status line shows 2 transactions and -100,00 €, not -200,00 €

### Requirement: Category group view

The app SHALL list the transactions of all categories below the selected category group in one list.

#### Scenario: Group with two categories

- **GIVEN** the group "Living" with "Rent" holding 12 transactions and "Electricity" holding 12 transactions
- **WHEN** the user selects "Living"
- **THEN** the list shows 24 transactions

### Requirement: Remove a category

The app SHALL remove a category with "Remove Category..." after the user confirms. The confirmation names the category and says that its transactions are kept. The transactions move to "Uncategorized".

#### Scenario: Confirm

- **GIVEN** the category "Pets" with 7 transactions
- **WHEN** the user chooses "Remove Category..." and confirms
- **THEN** "Pets" is gone from the sidebar and the 7 transactions are in "Uncategorized"

#### Scenario: Cancel

- **WHEN** the user cancels the confirmation
- **THEN** the category and its transactions are unchanged

### Requirement: Remove a category group

The app SHALL remove a category group with "Remove Category Group..." after the user confirms. The confirmation says that the transactions are kept and that all subcategories are removed as well. All transactions below the group move to "Uncategorized".

#### Scenario: Group with subcategories

- **GIVEN** the group "Mobility" with the categories "Fuel" and "Train" and 60 transactions in total
- **WHEN** the user chooses "Remove Category Group..." and confirms
- **THEN** "Mobility", "Fuel", and "Train" are gone and the 60 transactions are in "Uncategorized"

### Requirement: Starter categories

The app SHALL create a starter set of categories and category groups when it creates a new database. The names are in the language of the interface at that moment. The user can rename, move, and remove each of them.

#### Scenario: First launch in English

- **GIVEN** the interface language is English
- **WHEN** the app creates a new database
- **THEN** the section "Categories" contains the starter set with English names and "Uncategorized" as the last entry

#### Scenario: First launch in German

- **GIVEN** the interface language is German
- **WHEN** the app creates a new database
- **THEN** the starter set has German names
