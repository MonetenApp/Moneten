# Spec Delta

## Purpose

The dashboard shows all accounts on one page. This capability defines what an account item shows, which accounts appear, what the status line sums up, and how the user gets from the dashboard to an account.

## ADDED Requirements

### Requirement: Dashboard in the sidebar

The app SHALL show "Dashboard" as the first row of the sidebar. Selecting it shows the dashboard in the content view. At launch the app shows the dashboard when it has no remembered view.

#### Scenario: Select the dashboard

- **GIVEN** the user views an account
- **WHEN** the user selects "Dashboard" in the sidebar
- **THEN** the content view shows the dashboard

#### Scenario: First launch with accounts

- **GIVEN** a database with accounts and no remembered view
- **WHEN** the app starts and the user unlocks it
- **THEN** the content view shows the dashboard

### Requirement: One item for each open account

The app SHALL show one item on the dashboard for each account that is not marked as closed. The items follow the order of the sidebar, and the items of an account group stand together under the name of the group.

#### Scenario: Two groups

- **GIVEN** the group "Private" with the accounts "Girokonto" and "Tagesgeld", and the group "Business" with the account "Geschäftskonto"
- **WHEN** the user opens the dashboard
- **THEN** the dashboard shows the heading "Private" with the items "Girokonto" and "Tagesgeld", then the heading "Business" with the item "Geschäftskonto"

#### Scenario: Closed account

- **GIVEN** the account "Altes Sparbuch" is marked as closed
- **WHEN** the user opens the dashboard
- **THEN** the dashboard shows no item for "Altes Sparbuch"

### Requirement: Item content

The app SHALL show on each item the icon of the account, its name, and its balance with the currency. A negative balance is marked in the same way as a negative amount in a list.

#### Scenario: Current account

- **GIVEN** the account "Girokonto" with the balance 2.450,10 €
- **WHEN** the user opens the dashboard
- **THEN** the item shows the icon of the account, "Girokonto", and 2.450,10 €

#### Scenario: Overdrawn account

- **GIVEN** the account "Girokonto" with the balance -120,00 €
- **WHEN** the user opens the dashboard
- **THEN** the item shows -120,00 € marked as negative

### Requirement: Newest transactions on an item

The app SHALL list on each item up to five of the newest transactions of the account, newest first, each with its date, its counterparty, and its amount. A transaction that the user has not yet seen carries the marker for new transactions.

#### Scenario: Seven transactions

- **GIVEN** the account "Girokonto" has 7 transactions and none is new
- **WHEN** the user opens the dashboard
- **THEN** the item lists the 5 newest transactions

#### Scenario: Two new transactions

- **GIVEN** a refresh brought 2 new transactions for "Girokonto"
- **WHEN** the user opens the dashboard
- **THEN** the two transactions stand at the top of the item with the marker for new transactions

### Requirement: More new transactions

The app SHALL add a line to an item when the account has more new transactions than the item lists. The line states how many more there are, for example "3 more new transactions...", and for one it reads "1 more new transaction...". A click on the line opens the account.

#### Scenario: Eight new transactions

- **GIVEN** a refresh brought 8 new transactions for "Girokonto"
- **WHEN** the user opens the dashboard
- **THEN** the item lists 5 of them and the line "3 more new transactions..."

#### Scenario: Follow the line

- **WHEN** the user clicks "3 more new transactions..."
- **THEN** the content view shows the account "Girokonto"

### Requirement: Pending transactions are marked

The app SHALL mark a pending transaction on a dashboard item in the same way as in the transaction list.

#### Scenario: Card payment not yet booked

- **GIVEN** the newest transaction of "Kreditkarte" is pending
- **WHEN** the user opens the dashboard
- **THEN** the item shows that transaction with the marking for pending transactions

### Requirement: Portfolio items

The app SHALL show the total value of a portfolio account as the balance of its item and list no transactions on it.

#### Scenario: Portfolio

- **GIVEN** the portfolio "Depot" worth 12.300,00 €
- **WHEN** the user opens the dashboard
- **THEN** the item "Depot" shows 12.300,00 € and no transaction rows

### Requirement: Refresh state on an item

The app SHALL show on an item that its account is being refreshed, and it SHALL show the error state of an account whose last refresh failed. The balance and the transactions of the last successful refresh stay visible.

#### Scenario: Refresh in progress

- **WHEN** the app refreshes "Girokonto" while the dashboard is visible
- **THEN** the item "Girokonto" shows a progress indicator until the refresh ends
- **AND** new transactions appear on the item without a new selection of the dashboard

#### Scenario: Failed refresh

- **GIVEN** the last refresh of "Tagesgeld" failed
- **WHEN** the user opens the dashboard
- **THEN** the item "Tagesgeld" shows the error indicator and the last known balance

### Requirement: Open an account from the dashboard

The app SHALL show the account view when the user clicks an item, and "Back" returns to the dashboard. A click on a transaction of an item opens the account with that transaction selected.

#### Scenario: Click an item

- **WHEN** the user clicks the item "Girokonto"
- **THEN** the content view shows "Girokonto" and the sidebar selects it

#### Scenario: Back

- **GIVEN** the user opened "Girokonto" from the dashboard
- **WHEN** the user chooses "Back"
- **THEN** the content view shows the dashboard again

### Requirement: The dashboard does not mark transactions as seen

The app SHALL keep the new state of a transaction while the user only looks at the dashboard. The state ends when the user opens the account, as the capability for refresh defines.

#### Scenario: Look and leave

- **GIVEN** 2 new transactions on the item "Girokonto"
- **WHEN** the user opens the dashboard, then quits the app and starts it again
- **THEN** the item still shows both transactions as new

### Requirement: Total and last refresh in the status line

The app SHALL show in the status line of the dashboard the sum of the balances of all open accounts after "Sum:", and the time of the last refresh with a relative day such as "Today" or "Yesterday". Balances in different currencies are not added together. The status line shows one sum for each currency.

#### Scenario: Euro accounts

- **GIVEN** open accounts with 2.450,10 €, 10.000,00 €, and a portfolio worth 12.300,00 €, and the last refresh ran today at 09:41
- **WHEN** the user opens the dashboard
- **THEN** the status line shows "Sum:" with 24.750,10 € and "Today, 09:41"

#### Scenario: Two currencies

- **GIVEN** open accounts with 1.000,00 € and 500,00 USD
- **WHEN** the user opens the dashboard
- **THEN** the status line shows the sums 1.000,00 € and 500,00 USD

### Requirement: Toolbar on the dashboard

The app SHALL keep the button "Bank transfer" available on the dashboard once the app supports transfers, and it SHALL disable the view switch between list, bar chart, and pie chart, because the dashboard has only one presentation.

#### Scenario: Start a transfer

- **GIVEN** an app version with transfers and an account that can pay
- **WHEN** the user clicks "Bank transfer" on the dashboard
- **THEN** the payment window opens

#### Scenario: View switch

- **WHEN** the dashboard is visible
- **THEN** "List", "Bar Chart", and "Pie Chart" are disabled in the toolbar and in the View menu

### Requirement: Dashboard commands

The app SHALL offer in the context menu of "Dashboard" the commands to add an account, an account group, a category, a category group, and a template group, "Print Accounts...", and "Mark All Transactions as Checked".

#### Scenario: Open the context menu

- **WHEN** the user opens the context menu of "Dashboard" in the sidebar
- **THEN** the menu contains "Add Account...", "Add Account Group", "Add Category", "Add Category Group", "Print Accounts...", and "Mark All Transactions as Checked"

### Requirement: Dashboard without open accounts

The app SHALL show the text "No accounts present." on the dashboard when no open account exists, together with a way to add an account.

#### Scenario: All accounts are closed

- **GIVEN** every account is marked as closed
- **WHEN** the user opens the dashboard
- **THEN** the dashboard shows "No accounts present." and a button that starts "Add Account..."
