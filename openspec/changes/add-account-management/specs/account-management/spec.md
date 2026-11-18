# Spec Delta

## Purpose

Accounts and account groups are the frame for everything else in the app. This capability defines what an account is, how the user changes its settings, how accounts are grouped, closed, and removed.

## ADDED Requirements

### Requirement: Account types

The app SHALL give every account one of the types "Giro account", "Savings account", "Fixed term deposit", "Loan account", "Credit card", "Portfolio", or "Other". The bank or the extension sets the type when the account is added. A later refresh does not change the type, except that a refresh that fetches the value of a securities account makes the account a "Portfolio".

#### Scenario: Type from the bank

- **WHEN** the bank reports a savings account during setup
- **THEN** the new account has the type "Savings account"

#### Scenario: Refresh reports another type

- **GIVEN** the user changed the type of an account to "Fixed term deposit"
- **WHEN** a refresh reports the account as a savings account
- **THEN** the account keeps the type "Fixed term deposit"

#### Scenario: Refresh fetches the value of a securities account

- **GIVEN** the user changed the type of "Depot" to "Savings account"
- **WHEN** a refresh fetches the value of "Depot" as a securities account
- **THEN** "Depot" has the type "Portfolio"

### Requirement: Derive a missing account type

The app SHALL derive the type of a new account from its number and its name when an extension reports no type. The number decides first. Then the name decides, in lowercase, by the tests of the scenarios in their order, and the first test that matches wins. An account that matches no test gets the type "Other". A FinTS account whose bank reports no type gets the type "Other" as well.

#### Scenario: Masked card number

- **WHEN** an extension reports an account with the number "4111 xxxx xxxx 1111" and no type
- **THEN** the new account has the type "Credit card"
- **AND** an "X" or an "*" in the number has the same effect

#### Scenario: The number decides before the name

- **WHEN** an extension reports an account with the number "1234567890123456", the name "Tagesgeld", and no type
- **THEN** the new account has the type "Credit card", because the number has exactly 16 characters

#### Scenario: Card number with spaces

- **WHEN** an extension reports an account with the number "1234 5678 9012 3456", the name "Wallet", and no type
- **THEN** the new account has the type "Other", because spaces count as characters

#### Scenario: First test of the name

- **WHEN** the name contains "giro", "kontokorrent", "sichteinlage", or "gehalt"
- **THEN** the new account has the type "Giro account"

#### Scenario: Second test of the name

- **WHEN** the name contains "karte", "card", or "visa"
- **AND** it contains neither "spar" outside "sparkasse" and "sparda", nor "konto" outside "kartenkonto", nor "zins", nor " mit " with a space on each side
- **THEN** the new account has the type "Credit card"

#### Scenario: Third test of the name

- **WHEN** the name contains "festgeld", "festzins", "termingeld", "termineinlage", "sparbrief", "schatzbrief", or "sparkassenbrief", or ends with "brief"
- **THEN** the new account has the type "Fixed term deposit"

#### Scenario: Fourth test of the name

- **WHEN** the name contains "darlehen", "darlehn", "konsumentenkredit", "privatkredit", "gewerbekredit", or "baufinanzierung", or ends with "kredit"
- **THEN** the new account has the type "Loan account"

#### Scenario: Fifth test of the name

- **WHEN** the name contains "spar" outside "sparkasse" and "sparda", or contains "sparkassenbuch", "geld", "cash", "zins", "anlage", "verrechnung", or "anteil"
- **THEN** the new account has the type "Savings account"

#### Scenario: Sixth test of the name

- **WHEN** the name contains "konto" and one of "geschäfts", "geschaefts", "firmen", "verein", "privat", or "direkt"
- **THEN** the new account has the type "Giro account"

#### Scenario: Type from the name

- **WHEN** an extension reports an account with the number "DE02120300000000202051", the name "Tagesgeld Plus", and no type
- **THEN** the new account has the type "Savings account"

#### Scenario: A card name with "mit"

- **WHEN** an extension reports an account with the number "DE02120300000000202051", the name "Girocard mit Bonus", and no type
- **THEN** the new account has the type "Giro account", because the first test matches

#### Scenario: No hint

- **WHEN** an extension reports an account with the number "K-2231" and the name "Wallet" and no type
- **THEN** the new account has the type "Other"

### Requirement: Change the account type

The app SHALL let the user change the type of an account under "Account type" among "Giro account", "Savings account", "Fixed term deposit", "Loan account", "Credit card", and "Other". The type "Portfolio" cannot be chosen and cannot be changed, because it decides that the account shows securities.

#### Scenario: Correct a wrong type

- **GIVEN** the bank reported a fixed term deposit as "Other"
- **WHEN** the user selects "Fixed term deposit" under "Account type" and clicks "OK"
- **THEN** the account has the type "Fixed term deposit"

#### Scenario: Portfolio

- **WHEN** the user opens the settings of a portfolio
- **THEN** the settings show the type "Portfolio" without a menu

### Requirement: Account settings window

The app SHALL open the settings of the selected account with "Account Settings..." in the Account menu, with "Settings..." in the context menu, and with ⌘I. The window has the title "Settings for" followed by the account name, the tabs for the account and "Account owner", and the buttons "Cancel" and "OK".

#### Scenario: Confirm changes

- **WHEN** the user changes the name to "Household" and clicks "OK"
- **THEN** the sidebar shows "Household"

#### Scenario: Discard changes

- **WHEN** the user changes the name and the account type and clicks "Cancel"
- **THEN** the account keeps its old name and type

### Requirement: Account name

The app SHALL name a new account with the product name that the bank reports, or with the account type when the bank reports none, and it SHALL let the user change the name. Two accounts can have the same name. An empty name is not accepted.

#### Scenario: Name from the bank

- **WHEN** the bank reports the product name "Giro Direkt" for a new account
- **THEN** the account appears as "Giro Direkt"

#### Scenario: Empty name

- **WHEN** the user clears the name field and clicks "OK"
- **THEN** the app keeps the window open and asks for a name

### Requirement: Account color

The app SHALL draw an account in the sidebar and in the header as a small square in its color. The user can choose the color in the account settings. Without a chosen color, all accounts of one bank share a color, and an account without a bank takes a color for its type. A migration takes the color of the account's icon in the other program, not the picture.

#### Scenario: Two accounts of one bank

- **GIVEN** the accounts "Giro" and "Savings" with the same bank code and no chosen color
- **WHEN** the user looks at the sidebar
- **THEN** both squares have the same color

### Requirement: Bank details of an account

The app SHALL show in the account settings the IBAN and the BIC of the account, or the account number and the Bankleitzahl when it has no IBAN, and the "Bank name". The IBAN is shown in groups of four characters. The user can change the bank name and cannot change the other values there.

#### Scenario: Account with an IBAN

- **WHEN** the user opens the settings of the account with the IBAN DE02120300000000202051
- **THEN** the settings show "DE02 1203 0000 0000 2020 51" and the BIC "BYLADEM1001" as fixed text

#### Scenario: Card account without an IBAN

- **WHEN** the user opens the settings of a credit card that the bank reports with a card number only
- **THEN** the settings show the number under "Credit card number" in place of the IBAN

#### Scenario: Portfolio

- **WHEN** the user opens the settings of a portfolio
- **THEN** the settings show the number under "Portfolio number"

### Requirement: IBAN of an account

The app SHALL keep an IBAN for an account only when its country code, its length for that country, and its checksum are valid. Spaces and lower case letters do not matter, and the app keeps the IBAN without spaces in upper case. Text from a bank, an extension, a file, or a migration that is not a valid IBAN becomes the account number when the account has none, and the app drops it otherwise.

#### Scenario: IBAN with spaces from the bank

- **WHEN** the bank reports the account "Giro" with the IBAN "de02 1203 0000 0000 2020 51"
- **THEN** the settings of "Giro" show the IBAN "DE02 1203 0000 0000 2020 51"

#### Scenario: Wrong checksum from an extension

- **WHEN** an extension lists the account "Card" with the IBAN "DE03120300000000202051" and the account number "4711"
- **THEN** "Card" has no IBAN and the settings show the account number "4711"

#### Scenario: Migrated account with a wrong checksum and no account number

- **WHEN** the migration reads the account "Old Giro" with the IBAN "DE03120300000000202051" and no account number
- **THEN** "Old Giro" has no IBAN and the settings show the account number "DE03120300000000202051"

#### Scenario: File names an invalid IBAN

- **GIVEN** a CAMT file whose account is "DE03120300000000202051"
- **WHEN** the user chooses "Create offline account" for the file
- **THEN** the new account is named "Account DE03120300000000202051" and has that text as its account number and no IBAN

### Requirement: Account of a counterparty

The app SHALL keep the account of a counterparty as the bank, the extension, or the file gives it, and it SHALL show it as an IBAN only when it is a valid IBAN. A valid IBAN is kept without spaces in upper case. Other text, such as an older account number or an IBAN with a wrong checksum, never fails a refresh or an import.

#### Scenario: Valid IBAN of a counterparty

- **WHEN** a refresh delivers a transaction whose counterparty has the account "DE02 1203 0000 0000 2020 51"
- **THEN** the details of the transaction show "IBAN" with "DE02 1203 0000 0000 2020 51"

#### Scenario: Wrong checksum of a counterparty

- **WHEN** a refresh delivers the transaction "Miete" of -800.00 EUR whose counterparty has the account "DE03120300000000202051"
- **THEN** the refresh succeeds and stores "Miete"
- **AND** the details of "Miete" show "Account number" with "DE03120300000000202051"

#### Scenario: Older account number of a counterparty

- **WHEN** a file import delivers a transaction whose counterparty has the account "0099887766"
- **THEN** the details of the transaction show "Account number" with "0099887766"

### Requirement: Account currency

The app SHALL store the currency that the source reports for an account and show every amount of that account in that currency. The sidebar shows the currency next to the balance.

#### Scenario: Dollar account

- **GIVEN** a foreign currency account in US dollars with a balance of 1.500,00
- **WHEN** the user looks at the sidebar
- **THEN** the row of the account shows the balance as an amount in US dollars
- **AND** the transactions of the account show amounts in US dollars

### Requirement: Account owner

The app SHALL show the name of the account owner on the tab "Account owner" under "Name of Account Owner". The name comes from the bank at setup, and the user can change it.

#### Scenario: Name from the bank

- **WHEN** the bank reports the owner "Erika Mustermann" at setup
- **THEN** "Name of Account Owner" shows "Erika Mustermann"

#### Scenario: Name corrected by hand

- **WHEN** the user changes the name to "Erika Mustermann-Schmidt" and clicks "OK"
- **THEN** the app stores "Erika Mustermann-Schmidt" as the owner of the account

### Requirement: Balance comes from the bank

The app SHALL show for a portfolio and for each account of a bank access the balance that the source reported last, together with the date of that balance. The app does not compute this balance from the transaction list, so it can differ from the list while transactions are pending. Every other account shows the balance that its transactions give.

#### Scenario: Balance with its date

- **GIVEN** the bank of the account "Giro" reported a balance of 2.340,15 € on 7 November 2026
- **WHEN** the user selects the account
- **THEN** the account view shows 2.340,15 € with the date 07.11.2026

#### Scenario: Deleting a transaction does not change the balance

- **GIVEN** an account of a bank access with a reported balance of 2.340,15 €
- **WHEN** the user deletes a transaction of 40,00 € from the list
- **THEN** the account still shows 2.340,15 €

#### Scenario: Account without a bank access

- **GIVEN** a migrated account "Wallet" without a bank access with a balance of 133,20 €
- **WHEN** the user imports a transaction of -4,80 €
- **THEN** the account shows 128,40 € without the date of a reported balance

### Requirement: Several balances and bonus points

The app SHALL show every balance when a source reports several balances in different currencies for one account, and it SHALL show the number of bonus points under "Bonus points" in the account view when a source reports one. The sidebar row, the account view, and the sum of the group show the balance in the account currency first and then each other balance. Each refresh replaces the balances and the bonus points of the account.

#### Scenario: Wallet with two currencies

- **WHEN** a source reports the balances 120,00 € and 35,00 US dollars for one account
- **THEN** the account view and the sidebar row show both balances
- **AND** the sum of its group holds 120,00 € and 35,00 US dollars

#### Scenario: Card with a bonus program

- **WHEN** a source reports 12400 bonus points for a credit card
- **THEN** the account view shows "Bonus points: 12.400", a whole number with grouping separators
- **AND** the sidebar row shows only the balance

#### Scenario: Account currency missing

- **GIVEN** an account in euros
- **WHEN** a source reports only the balances 35,00 US dollars and 0,00 British pounds
- **THEN** the account shows the balances 0,00 € and 35,00 US dollars

#### Scenario: Two balances in one currency

- **WHEN** a source reports the balances 10,00 € and 2,50 € for an account in euros
- **THEN** the account shows the balance 12,50 €

#### Scenario: A currency disappears

- **GIVEN** an account shows the balances 120,00 € and 35,00 US dollars and 12.400 bonus points
- **WHEN** the next refresh reports only the balance 80,00 €
- **THEN** the account shows only 80,00 € and no bonus points

#### Scenario: Portfolio

- **WHEN** a source reports the value 1.000,00 € and 50 bonus points for a portfolio
- **THEN** the portfolio shows only its value 1.000,00 €

### Requirement: Initial balance

The app SHALL keep an "Initial balance" for each account. The first refresh that brings a balance and does not fail to bring the transactions sets it to that balance, less the booked transactions that the account holds in the account currency up to the day of that balance. Pending transactions never count, because a bank balance does not hold them yet. The user can change the initial balance in the account settings.

#### Scenario: Determined at setup

- **GIVEN** the bank reports a balance of 1.000,00 € and the first refresh brings booked transactions with a sum of 250,00 € and one pending transaction of -30,00 €
- **WHEN** the first refresh ends
- **THEN** "Initial balance" shows 750,00 €

#### Scenario: The transactions of the first refresh failed

- **GIVEN** the first refresh brings a balance of 1.000,00 € and fails to bring the transactions
- **WHEN** the second refresh brings a balance of 1.000,00 € and booked transactions with a sum of 250,00 €
- **THEN** "Initial balance" shows 750,00 €

#### Scenario: Older transactions missing

- **GIVEN** the first refresh brings a balance of 1.000,00 € and booked transactions of the last 90 days with a sum of 250,00 €, because the user canceled the TAN for older transactions
- **WHEN** an enforced refresh brings a balance of 1.000,00 € and older booked transactions with a sum of -100,00 €
- **THEN** "Initial balance" shows 850,00 €

#### Scenario: Changed by hand

- **WHEN** the user enters 800,00 under "Initial balance" and clicks "OK"
- **THEN** the app stores 800,00 € as the initial balance of the account

#### Scenario: Initial balance above the limit

- **WHEN** the user enters 10.000.000.000.000,01 under "Initial balance"
- **THEN** "OK" stays disabled and the initial balance stays as it was

#### Scenario: Derived initial balance beyond the limit

- **GIVEN** the bank reports a balance of 0,00 € and the first refresh brings two booked transactions of 10.000.000.000.000,00 €
- **WHEN** the first refresh ends
- **THEN** the account shows that the fetched transactions could not be saved, because the initial balance of the account is too large
- **AND** the account keeps its initial balance and its transactions as they were

### Requirement: Mark an account as closed

The app SHALL offer the option "The account has been closed" in the account settings. A closed account keeps its transactions, is left out of every refresh, and is left out of the dashboard and of the sum of its group. The sidebar still lists it, without its balance.

#### Scenario: Close an account

- **WHEN** the user turns on "The account has been closed" and clicks "OK"
- **THEN** the account stays in the sidebar with all its transactions and without its balance
- **AND** the sum of its group no longer contains its balance
- **AND** "Refresh All Accounts" does not contact the bank for this account
- **AND** the sidebar shows no error of an earlier refresh for it

#### Scenario: Offline account

- **WHEN** the user turns on the option for an offline account
- **THEN** the offline account is closed in the same way

#### Scenario: Refresh during the close

- **GIVEN** a refresh of the bank of "Giro" runs, and another one of that bank waits for its turn
- **WHEN** the user marks "Giro" as closed and clicks "OK"
- **THEN** the running refresh changes no transaction, no balance, and no refresh time of "Giro"
- **AND** the waiting refresh does not ask the bank for "Giro"

### Requirement: Clearing entry for a closed account

The app SHALL insert one transaction named "Clearing entry" when the user marks an account as closed, clicks "OK", and the computed balance at the end of that day is not zero. That balance is the initial balance plus the transactions up to that day in the account currency, pending ones included. The entry is booked, dated that day, and has the opposite amount in the account currency. A portfolio gets no entry.

#### Scenario: Balance left on the account

- **GIVEN** an offline account with a balance of 12,34 € on 2026-11-17
- **WHEN** the user marks it as closed on that day and clicks "OK"
- **THEN** the list shows a new transaction "Clearing entry" of -12,34 € with the booking date and the value date 2026-11-17
- **AND** its purpose says that the app inserted it because the account was closed
- **AND** it has no category and no counterparty, is marked as new, and is not checked
- **AND** the account shows a balance of 0,00 €

#### Scenario: Balance already zero

- **GIVEN** an account with a balance of 0,00 €
- **WHEN** the user marks it as closed
- **THEN** the app inserts no transaction

#### Scenario: Turned on and off before OK

- **WHEN** the user turns on "The account has been closed", turns it off again, and clicks "OK"
- **THEN** the app inserts no transaction

#### Scenario: Account of a bank access

- **GIVEN** the bank reported 500,00 € for "Giro", and its initial balance and transactions add up to 480,00 € at the end of 2026-11-17
- **WHEN** the user marks "Giro" as closed on 2026-11-17
- **THEN** the clearing entry is -480,00 €

#### Scenario: Transaction after that day

- **GIVEN** an offline account with 250,00 € at the end of 2026-11-17 and a booked transaction of 80,00 € on 2026-11-18
- **WHEN** the user marks it as closed on 2026-11-17
- **THEN** the clearing entry is -250,00 €
- **AND** the transaction of 2026-11-18 stays, and the account shows 80,00 €

#### Scenario: Pending transaction

- **GIVEN** an account with 100,00 € at the end of 2026-11-17, a pending transaction of -20,00 € on 2026-11-16 among them
- **WHEN** the user marks it as closed on 2026-11-17
- **THEN** the clearing entry is -100,00 €
- **AND** the transaction of -20,00 € stays pending

#### Scenario: Balances in several currencies

- **GIVEN** a wallet in EUR whose source reported 120,00 € and 35,00 US$, and whose transactions add up to 120,00 €
- **WHEN** the user marks it as closed
- **THEN** the app inserts one clearing entry of -120,00 € and no entry in US$

#### Scenario: Portfolio

- **WHEN** the user marks a portfolio worth 1.000,00 € as closed
- **THEN** the app inserts no transaction

### Requirement: Balance of a closed account

The app SHALL show the computed balance of a closed account in the header, the initial balance plus its transactions in the account currency, also when a bank reported a balance. It shows no balance in another currency and no bonus points for it. The bar chart of the closed account itself still shows its history. A closed portfolio keeps its value. The sum of a group leaves the closed account out.

#### Scenario: Header after the clearing entry

- **GIVEN** the bank reported 500,00 € and 35,00 US$ for "Giro"
- **WHEN** the user marks "Giro" as closed and the app inserts the clearing entry
- **THEN** the header of "Giro" shows 0,00 € and no amount in US$
- **AND** the header shows no "Balance as of" line and no calibration proposal

#### Scenario: Bar chart of the closed account

- **GIVEN** the closed account "Giro" with a clearing entry on 2026-11-17
- **WHEN** the user selects "Giro" and shows the bar chart
- **THEN** the chart shows the balance of each day before and 0,00 € from 2026-11-17

#### Scenario: File import into a closed account

- **GIVEN** the closed offline account "Wallet" with a balance of 0,00 €
- **WHEN** the user imports a file with a deposit of 7,00 € into "Wallet"
- **THEN** the list of "Wallet" shows the deposit
- **AND** the header of "Wallet" shows 7,00 €

#### Scenario: Group with a closed account

- **GIVEN** the group "Private" with "Giro" at 300,00 € and the closed account "Old Savings", whose edited clearing entry leaves 50,00 €
- **WHEN** the user selects "Private"
- **THEN** the header of the group shows 300,00 €

### Requirement: Reopen a closed account

The app SHALL reopen an account when the user turns off "The account has been closed" and clicks "OK". The app removes the clearing entry of the last close unless the user changed its date, value date, amount, name, purpose, comment, or category, or split it. A checkmark, the mark "new", and a category from a rule do not count as a change. The account is refreshed again and shows the balance of the bank again.

#### Scenario: Unchanged clearing entry

- **GIVEN** a closed account with a clearing entry of -12,34 € that the user did not edit
- **WHEN** the user turns off the option and clicks "OK"
- **THEN** the clearing entry is gone and the balance is 12,34 € again

#### Scenario: Checked clearing entry

- **GIVEN** the user marked the clearing entry of -12,34 € as checked
- **WHEN** the user reopens the account
- **THEN** the clearing entry is gone

#### Scenario: Edited clearing entry

- **GIVEN** the user changed the purpose of the clearing entry
- **WHEN** the user reopens the account
- **THEN** the entry stays in the list as an ordinary manual transaction
- **AND** a later close inserts a new clearing entry only for the balance that is then left

#### Scenario: Edited clearing entry of a bank account

- **GIVEN** the bank reported 500,00 € for "Giro" on 2026-11-17, which matches its transactions
- **AND** the user closed "Giro" on 2026-11-17 and changed the purpose of its clearing entry of -500,00 €
- **WHEN** the user reopens "Giro"
- **THEN** the header shows 500,00 € and no calibration proposal
- **AND** the bar chart ends at 500,00 €

#### Scenario: Account of a bank access

- **GIVEN** the closed account "Giro", for which the bank reported 500,00 € and 35,00 US$, with an unchanged clearing entry of -480,00 €
- **WHEN** the user reopens "Giro"
- **THEN** the clearing entry is gone and the header shows 500,00 € and 35,00 US$ again

### Requirement: Create and rename account groups

The app SHALL create an account group with "Add Account Group". The new group appears in the sidebar with the name "New group" in edit mode. The user can rename a group in the sidebar and in its settings.

#### Scenario: New group

- **WHEN** the user chooses "Add Account Group" and types "Business"
- **THEN** the sidebar shows an empty group "Business"

#### Scenario: Empty group selected

- **WHEN** the user selects a group with no accounts
- **THEN** the content view says that the account group is empty

### Requirement: Move accounts into and out of groups

The app SHALL let the user drag an account or a group onto a group, out of a group, and to another position in the "Accounts" section. An account belongs to at most one group. A group can contain accounts and groups.

#### Scenario: Move into a group

- **WHEN** the user drags the account "Giro" onto the group "Private"
- **THEN** "Giro" is listed under "Private"

#### Scenario: Move out of a group

- **WHEN** the user drags "Giro" from "Private" to the top level of "Accounts"
- **THEN** "Giro" is listed outside every group

#### Scenario: Group into itself

- **WHEN** the user drags the group "Private" onto a group inside "Private"
- **THEN** the app does not accept the drop

### Requirement: Group view

The app SHALL show, when a group is selected, the transactions of all accounts in the group and in its subgroups in one list, and the sum of their balances. A group with accounts in several currencies shows one sum for each currency.

#### Scenario: Two euro accounts

- **GIVEN** the group "Private" with "Giro" at 1.000,00 € and "Savings" at 5.000,00 €
- **WHEN** the user selects "Private"
- **THEN** the list contains the transactions of both accounts
- **AND** the view shows a balance of 6.000,00 €

#### Scenario: Mixed currencies

- **GIVEN** a group with one account at 1.000,00 € and one account at 500,00 US dollars
- **WHEN** the user selects the group
- **THEN** the view shows 1.000,00 € and 500,00 US dollars as two sums

### Requirement: Account group settings

The app SHALL open the settings of the selected group with "Account Group Settings..." and ⌘I. The settings hold the name of the group and the option "Display balance in sidebar", which is on for a new group.

#### Scenario: Hide the sum

- **GIVEN** the group "Private" shows 6.000,00 € in the sidebar
- **WHEN** the user turns off "Display balance in sidebar" for "Private"
- **THEN** the sidebar row of "Private" shows only the name
- **AND** the rows of its accounts still show their balances

### Requirement: Collapsed groups keep their information

The app SHALL show on the row of a collapsed group the sum of the group, when the group displays its balance, and the markers of the accounts inside, which are the count of new transactions and the error indicator.

#### Scenario: Error inside a collapsed group

- **GIVEN** the group "Business" is collapsed and one of its accounts failed to refresh
- **WHEN** the user looks at the sidebar
- **THEN** the row of "Business" shows the error indicator

### Requirement: Remove an account

The app SHALL ask before it removes an account. The question names the account, says that all its transactions are removed as well and cannot be restored, and gives the hint that the account can be marked as closed instead. Statement files of the account stay in the data folder.

#### Scenario: Confirm removal

- **GIVEN** the account "Old Giro" with 800 transactions and 12 statement files
- **WHEN** the user chooses "Remove Account..." and confirms
- **THEN** "Old Giro" and its 800 transactions are gone from the app
- **AND** the 12 statement files are still in the "Statements" folder

#### Scenario: Cancel removal

- **WHEN** the user chooses "Remove Account..." and cancels
- **THEN** nothing changes

#### Scenario: Last account of an access

- **GIVEN** "Old Giro" is the only account of its bank access and the access has a saved PIN
- **WHEN** the user removes "Old Giro"
- **THEN** the app also deletes the saved PIN and the other login data of that access

### Requirement: Remove an account group

The app SHALL ask before it removes an account group and say that the accounts and transactions are kept. After the removal the accounts and subgroups of the group are in the group above it, or at the top level.

#### Scenario: Group with two accounts

- **GIVEN** the top level group "Private" with the accounts "Giro" and "Savings"
- **WHEN** the user chooses "Remove Account Group..." and confirms
- **THEN** "Private" is gone
- **AND** "Giro" and "Savings" are at the top level of "Accounts" with all their transactions
