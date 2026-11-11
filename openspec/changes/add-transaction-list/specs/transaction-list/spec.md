# Spec Delta

## Purpose

The transaction list shows what happened in an account, an account group, or a category. This capability defines the content and the order of the list, how the user selects rows and text, and how checkmarks, comments, edits, and deletions work.

## ADDED Requirements

### Requirement: One row per transaction

The app SHALL show one row for each transaction of the selected account, account group, or category. A row shows the booking date, the counterparty name, the purpose, the category, and the amount with its sign and currency.

#### Scenario: Card payment

- **GIVEN** the account "Giro" has a booked transaction of -42,50 € on 03.11.2026 to "REWE Markt GmbH" with the purpose "Kartenzahlung 02.11." in the category "Groceries"
- **WHEN** the user selects "Giro" in the sidebar
- **THEN** the list has a row with 03.11.2026, "REWE Markt GmbH", "Kartenzahlung 02.11.", "Groceries", and -42,50 €

#### Scenario: Purpose with several lines

- **WHEN** a transaction has a purpose with three lines
- **THEN** the row shows them in one line, joined with spaces, as MoneyMoney does
- **AND** the help tag of the purpose and the transaction sheet show all three lines

### Requirement: Newest transactions first

The app SHALL order the list by booking date with the newest transaction at the top. Transactions of the same day keep the order in which the bank delivered them, with the last delivered one at the top.

#### Scenario: Two days

- **GIVEN** one transaction booked on 02.11.2026 and one booked on 03.11.2026
- **WHEN** the user opens the account
- **THEN** the transaction of 03.11.2026 stands above the transaction of 02.11.2026

### Requirement: Details from the bank

The app SHALL show each detail that the bank delivered for a transaction with its label in the row. The details are the booking text, the value date, the receipt date of a card payment, the IBAN and BIC of the counterparty, the end-to-end reference, the mandate reference, the creditor ID, the original amount in a foreign currency, the return reason, and a deviating originator or recipient. A detail without a value does not appear.

#### Scenario: Direct debit with references

- **GIVEN** a direct debit with the mandate reference "M-2026-0042", the creditor ID "DE98ZZZ09999999999", and the value date 04.11.2026
- **WHEN** the user looks at its row
- **THEN** the row shows "Mandate reference" with M-2026-0042, "Creditor ID" with DE98ZZZ09999999999, and "Value date" with 04.11.2026

#### Scenario: Card payment abroad

- **GIVEN** a credit card transaction of -18,40 € that was paid as 20,00 USD
- **WHEN** the user looks at its row
- **THEN** the row shows the original amount 20,00 USD next to -18,40 €

#### Scenario: No details

- **WHEN** a transaction has no end-to-end reference
- **THEN** its row shows no line for the end-to-end reference

### Requirement: Account name in group and category views

The app SHALL show the account of a selected transaction in a view that lists transactions of more than one account, in small text at the end of the line with the payee, so that the row keeps its height. MoneyMoney writes it in a third line below the purpose. The list has no account column. For an account group, the option "Group transactions by account" in the group settings puts the transactions of each account under a heading with the account name.

#### Scenario: Mixed list

- **GIVEN** the group "Private" with the accounts "Giro" and "Savings"
- **WHEN** the user selects "Private"
- **THEN** both accounts share one list ordered by date
- **AND** a selected row names its account at the end of the line with the payee

#### Scenario: Grouped by account

- **GIVEN** the option "Group transactions by account" is on for "Private"
- **WHEN** the user selects "Private"
- **THEN** the list shows the heading "Giro" with its transactions, then the heading "Savings" with its transactions

### Requirement: Pending transactions look different

The app SHALL draw a transaction that the bank has not yet booked with a hatched background, and it SHALL show the sum of all pending amounts of the view with the label "Pending".

#### Scenario: Pre-authorized card payment

- **GIVEN** the account "Credit card" has two pending transactions of -30,00 € and -12,00 €
- **WHEN** the user opens "Credit card"
- **THEN** both rows are hatched
- **AND** the view shows "Pending" with -42,00 €

#### Scenario: No pending transactions

- **WHEN** an account has only booked transactions
- **THEN** the view shows no pending sum

### Requirement: New transactions are marked

The app SHALL show a mark on the row of each transaction that the user has not seen before. The mark stays while the view is open in which the user first sees the transaction, and it is gone when the user leaves that view.

#### Scenario: After a refresh

- **GIVEN** a refresh delivered 3 transactions for "Giro" while the user looked at another account
- **WHEN** the user opens "Giro"
- **THEN** the 3 rows carry the mark for new transactions
- **AND** the mark is gone when the user returns to "Giro" later

### Requirement: Text can be selected and copied

The app SHALL let the user select text inside a row and copy it. A double click selects a word. A triple click selects the whole text field.

#### Scenario: Copy an invoice number

- **GIVEN** a row with the purpose "Rechnung 2026-1187 Kundennummer 4711"
- **WHEN** the user double-clicks "2026-1187" and presses ⌘C
- **THEN** the pasteboard holds the selected word

#### Scenario: Triple click

- **WHEN** the user triple-clicks the purpose of a row
- **THEN** the whole purpose is selected

### Requirement: Several rows can be selected

The app SHALL let the user select a range of rows with the Shift key, single rows with the Command key, and all rows with "Select All". The status line shows the number of selected rows and their sum.

#### Scenario: Range

- **WHEN** the user clicks the first row and then clicks the fifth row with the Shift key held
- **THEN** rows one to five are selected

#### Scenario: Sum of the selection

- **GIVEN** three selected rows with -10,00 €, -20,00 €, and 5,00 €
- **WHEN** the user looks at the status line
- **THEN** it shows 3 transactions and the sum -25,00 €

#### Scenario: Deselect one row

- **GIVEN** rows one to five are selected
- **WHEN** the user clicks row three with the Command key held
- **THEN** rows one, two, four, and five stay selected

### Requirement: The context menu acts on the selection

The app SHALL apply a command of the context menu to all selected rows when the user opens the menu on a selected row. When the user opens the menu on a row outside the selection, the app selects that row first and applies the command only to it.

#### Scenario: Menu on a selected row

- **GIVEN** 4 selected rows
- **WHEN** the user opens the context menu on one of them and chooses a category under "Assign Category"
- **THEN** all 4 transactions get the category

#### Scenario: Menu on another row

- **GIVEN** 4 selected rows
- **WHEN** the user opens the context menu on a fifth row
- **THEN** only the fifth row is selected, and commands apply to it alone

### Requirement: Checkmarks

The app SHALL show a checkmark control on each row. A click sets or clears the checkmark, and the app stores the state with the transaction.

#### Scenario: Check off a paid invoice

- **GIVEN** an unchecked transaction
- **WHEN** the user clicks its checkmark control
- **THEN** the transaction is checked, also after a restart of the app

#### Scenario: Clear a checkmark

- **WHEN** the user clicks the checkmark control of a checked transaction
- **THEN** the transaction is unchecked

### Requirement: Mark all transactions as checked

The app SHALL offer "Mark All Transactions as Checked". Before it changes anything, the app states how many transactions in how many accounts it will mark, and it waits for the user to confirm.

#### Scenario: Confirm

- **GIVEN** 12 unchecked transactions in 3 accounts
- **WHEN** the user chooses "Mark All Transactions as Checked"
- **THEN** the app states that a total of 12 transactions in 3 accounts will be marked as checked
- **AND** all 12 are checked after the user confirms

#### Scenario: Cancel

- **WHEN** the user cancels the confirmation
- **THEN** no checkmark changes

### Requirement: Checkmarks can be hidden

The app SHALL hide and show the checkmark controls with "Checkmarks" in the View menu. The app keeps the stored checkmarks while they are hidden, and it remembers the choice after a restart.

#### Scenario: Hide

- **GIVEN** "Checkmarks" has a checkmark in the View menu
- **WHEN** the user chooses "Checkmarks"
- **THEN** no row shows a checkmark control

#### Scenario: Show again

- **GIVEN** 5 checked transactions and hidden checkmarks
- **WHEN** the user chooses "Checkmarks" again
- **THEN** the 5 transactions show their checkmarks

### Requirement: Comments

The app SHALL let the user write a comment for a transaction with "Add Comment..." or the shortcut ⇧⌘K. A transaction with a comment shows a yellow icon and the comment text in its row. For a transaction that has a comment, the command reads "Edit Comment...".

#### Scenario: Add a comment

- **GIVEN** a selected transaction without a comment
- **WHEN** the user presses ⇧⌘K, enters "Warranty until 2028", and confirms
- **THEN** the row shows a yellow icon and the text "Warranty until 2028"

#### Scenario: Remove a comment

- **WHEN** the user opens "Edit Comment...", deletes the whole text, and confirms
- **THEN** the row shows no icon and no comment

#### Scenario: No selection

- **WHEN** no transaction is selected
- **THEN** "Add Comment..." is disabled

### Requirement: Daily balance in the list

The app SHALL show the balance at the end of each day between the rows of a single account when the user turns on "Daily balance" in the filter bar or chooses "Daily Balance" in the View menu. The switch and the command are available only in the view of a single account.

#### Scenario: Turn on

- **GIVEN** the account "Giro" with a computed balance of 1.200,00 € at the end of 02.11.2026 and two transactions of -50,00 € and -25,00 € on 03.11.2026
- **WHEN** the user turns on "Daily balance"
- **THEN** the list shows 1.125,00 € as the balance of 03.11.2026

#### Scenario: Group view

- **WHEN** the user selects an account group
- **THEN** "Daily Balance" in the View menu is disabled and the filter bar has no "Daily balance" switch

### Requirement: Go to the account or the category

The app SHALL offer "Go to" in the context menu of a transaction. The submenu lists the account and the category of the transaction, without the one that the current view already shows. A choice opens that view with the transaction selected and visible.

#### Scenario: From a category to the account

- **GIVEN** the category view "Groceries" with a transaction of the account "Giro"
- **WHEN** the user chooses "Go to" and then "Giro"
- **THEN** the app shows the account "Giro" with that transaction selected

#### Scenario: From a group view

- **WHEN** the user opens "Go to" on a transaction in an account group view
- **THEN** the submenu lists the account and the category of the transaction

### Requirement: Edit a transaction

The app SHALL let the user change the booking date, the value date, the counterparty name, the purpose, and the amount of a transaction with "Edit Transaction...". A later refresh keeps the changed values and does not add the original again.

#### Scenario: Correct a purpose

- **GIVEN** a fetched transaction with the purpose "LASTSCHRIFT 8837271"
- **WHEN** the user chooses "Edit Transaction...", changes the purpose to "Gym membership October", and confirms
- **THEN** the row shows the new purpose
- **AND** the next refresh leaves the row unchanged and adds no second row for it

#### Scenario: Cancel

- **WHEN** the user cancels the edit window
- **THEN** the transaction is unchanged

### Requirement: Delete transactions

The app SHALL offer "Delete Transaction..." in the view of a single account, for one or for several selected transactions. The app asks for confirmation, names the number of transactions, and warns that deleted transactions cannot be restored.

#### Scenario: Delete a duplicate

- **GIVEN** one selected transaction in the account "Giro"
- **WHEN** the user chooses "Delete Transaction..." and confirms
- **THEN** the transaction is gone from the account, from its category, and from all sums

#### Scenario: Delete several

- **GIVEN** 3 selected transactions
- **WHEN** the user opens the context menu
- **THEN** the command reads "Delete Transactions..." and the confirmation asks about 3 selected transactions

#### Scenario: Cancel

- **WHEN** the user cancels the confirmation
- **THEN** no transaction is deleted

#### Scenario: Group or category view

- **WHEN** the user opens the context menu of a transaction in an account group view or a category view
- **THEN** the menu has no delete command

### Requirement: Services for selected text

The app SHALL include the macOS Services that accept text in the context menu while text in a row is selected.

#### Scenario: Look up selected text

- **GIVEN** the user selected the counterparty name in a row
- **WHEN** the user opens the context menu
- **THEN** the menu contains the Services submenu of macOS for the selected text

### Requirement: Empty states

The app SHALL show a short message in place of the list when there is nothing to list. The message tells an account without transactions apart from a list that the search or a filter emptied.

#### Scenario: New account

- **GIVEN** an account for which the bank has delivered no transactions
- **WHEN** the user opens the account
- **THEN** the view shows that the bank provided no transactions yet

#### Scenario: Filter hides everything

- **GIVEN** an account with 200 transactions and a search text that matches none
- **WHEN** the user looks at the list
- **THEN** the view shows "No matching transactions found."

### Requirement: The list stays fluid with a large history

The app SHALL scroll, select, and update the list without visible delay for a view with 50,000 transactions.

#### Scenario: Scroll through ten years

- **GIVEN** an account group with 50,000 transactions
- **WHEN** the user scrolls from the top to the bottom of the list
- **THEN** rows appear without blank areas and without stutter

### Requirement: Row layout

The app SHALL lay out a row as MoneyMoney does. The category is a ribbon in the color of the category below the booking date, not a column of its own. The amount omits the currency when it is the currency of the view, and it shows a minus sign. The checkmark is at the end of the row. The list has no column headers, a line separates the rows, and every row has the same height.

#### Scenario: Categorized card payment

- **GIVEN** the account "Giro" in EUR has a booked transaction of -42,50 € in the category "Groceries"
- **WHEN** the user selects "Giro" in the sidebar
- **THEN** the row shows the ribbon "GROCERIES" below the date and the amount "−42,50" without "€"
- **AND** the checkmark is right of the amount
