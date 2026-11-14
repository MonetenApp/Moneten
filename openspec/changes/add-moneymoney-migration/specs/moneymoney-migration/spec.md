# Spec Delta

## Purpose

A user who switches brings years of categorized transactions. This capability defines how the app reads accounts, categories, and transactions from an installed copy of MoneyMoney through its documented scripting interface. The requirements call MoneyMoney the source app. The capability also defines how the user checks the result before anything is stored and what the app reports afterwards.

## ADDED Requirements

### Requirement: Migration command

The app SHALL offer a migration command in the File menu and in the empty state of a database without accounts. The label of the command names the source app. The command starts an assistant with the steps check, summary, import, and report.

#### Scenario: New user

- **GIVEN** a new database without accounts
- **WHEN** the user looks at the main window
- **THEN** the empty state offers the migration command next to the way to add the first account

### Requirement: Preconditions are checked first

The app SHALL check, before it reads any data, that the source app is installed, is running, and has an unlocked database, and that macOS allows the app to control it. For each failed check the assistant says what the user must do and offers to check again.

#### Scenario: Source app is locked

- **GIVEN** the source app runs and shows its lock screen
- **WHEN** the user starts the assistant
- **THEN** the assistant asks the user to unlock the source app and offers "Check again"

#### Scenario: Automation not allowed

- **WHEN** the user denied the macOS request to control the source app
- **THEN** the assistant names the place in System Settings where the permission is granted

#### Scenario: Source app not installed

- **WHEN** the source app is not on the Mac
- **THEN** the assistant says so and offers the file import as the other way to bring in transactions

### Requirement: The source is only read

The app SHALL use only the export commands of the source app. It creates, changes, and deletes nothing in the source app and its data folder.

#### Scenario: After a migration

- **WHEN** the migration finishes
- **THEN** the source app shows the same accounts, transactions, categories, checkmarks, and comments as before

### Requirement: Summary before the import

The app SHALL show a summary after it read the source and before it stores anything. The summary states the number of account groups, accounts, categories, rules, and transactions, the date of the oldest and the newest transaction, and what cannot be migrated. The user continues with "Import" or leaves with "Cancel".

#### Scenario: Summary

- **GIVEN** a source with 2 groups, 5 accounts, 30 categories, and 18,400 transactions from 2014 to 2026
- **WHEN** the reading finishes
- **THEN** the summary shows these numbers and the two dates

#### Scenario: Cancel

- **WHEN** the user chooses "Cancel" in the summary
- **THEN** the database is unchanged

### Requirement: Account groups and accounts

The app SHALL create the account groups and accounts of the source with their names, their order and nesting, and for each account the type, the IBAN or account number, the bank code, the currency, the owner, and the last known balance with its date. Accounts start without a bank access.

#### Scenario: Group tree

- **GIVEN** the source has the group "Private" with the accounts "Giro" and "Savings", in this order, and neither has a pending transaction
- **WHEN** the migration finishes
- **THEN** the sidebar shows "Private" with "Giro" above "Savings", each with the balance from the source

#### Scenario: No bank access yet

- **WHEN** the user selects a migrated account
- **THEN** the account shows that it is not connected to a bank and offers to connect it

### Requirement: Categories

The app SHALL create the categories and category groups of the source with their names, order, and nesting. The default category of the source maps to "Uncategorized". A category that already exists at the same place in the tree is used and not created twice.

#### Scenario: Tree and default

- **GIVEN** the source has the group "Household" with the categories "Food" and "Pets", and a default category named "Sonstiges"
- **WHEN** the migration finishes
- **THEN** the sidebar shows "Household" with "Food" and "Pets"
- **AND** transactions of "Sonstiges" are in "Uncategorized"

### Requirement: Rules

The app SHALL take over the categorization rule of each category when the export of the source contains it, without changing its text.

#### Scenario: Rule taken over

- **GIVEN** the category "Salary" has the rule `"Lohn" OR "Gehalt"` in the source and the export contains it
- **WHEN** the migration finishes
- **THEN** the category "Salary" has the same rule

#### Scenario: Lower case operators keep their meaning

- **GIVEN** the category "Salary" has the rule `"Lohn" or "Gehalt"` in the source
- **WHEN** the migration finishes and the user imports a file into "Giro" with a transaction of 2.500,00 € and the purpose "Gehalt Oktober"
- **THEN** the category "Salary" has the rule `"Lohn" or "Gehalt"`
- **AND** the transaction is in "Salary"

#### Scenario: Export without rules

- **WHEN** the export of the source contains no rules
- **THEN** the report says that rules were not migrated and that the user can copy them by hand from the category settings of the source app

### Requirement: Migrated rules that the app cannot read

The app SHALL store a migrated rule that it cannot parse with its text unchanged, mark it as invalid in the category settings, and list it in the report. The report entry names the category, the position and the reason of the error, and says that the category receives no transaction through its rule until the user corrects the rule. Migrated transactions keep their category.

#### Scenario: Missing parenthesis

- **GIVEN** the category "Salary" has the rule `("Lohn" OR "Gehalt"` in the source
- **WHEN** the migration finishes
- **THEN** the report says that the rule of "Salary" cannot be read, because a closing parenthesis is missing at the end of the rule
- **AND** the report says that "Salary" receives no transaction through its rule until the rule is corrected in its settings
- **AND** the settings of "Salary" show the rule `("Lohn" OR "Gehalt"` with the same message

#### Scenario: One part of a rule cannot be read

- **GIVEN** the category "Fees" has the rule `"Gebühr" OR purpose:/GA NR[0-9/` in the source, whose regular expression is not valid, and no other category has a rule
- **WHEN** the migration finishes and the user imports a file into "Giro" with a transaction of -2,50 € and the purpose "Gebühr Oktober"
- **THEN** the report lists the rule of "Fees" with the position of the regular expression and the reason that it is not valid
- **AND** the transaction is in "Uncategorized" and not in "Fees"

### Requirement: Migrated rules that search account numbers

The app SHALL list in the report every migrated rule with a term without a field operator that is an IBAN or an account number, and keep the rule unchanged. A term of digits counts as an account number only when a migrated account or counterparty has that account number. The report entry names the category and says that `remote_account:` before the number searches the account of the counterparty.

#### Scenario: Rule with an IBAN only

- **GIVEN** the category "Rent" has the rule `DE02120300000000202051` in the source
- **WHEN** the migration finishes
- **THEN** the report says that the rule of "Rent" does not search the account fields and that `remote_account:DE02120300000000202051` finds the account of the counterparty
- **AND** the category "Rent" has the rule `DE02120300000000202051`

#### Scenario: Rule with a word and an IBAN

- **GIVEN** the category "Rent" has the rule `"Miete" AND DE02120300000000202051` in the source
- **WHEN** the migration finishes
- **THEN** the report says that the rule of "Rent" does not search the account fields and that `remote_account:DE02120300000000202051` finds the account of the counterparty
- **AND** the category "Rent" has the rule `"Miete" AND DE02120300000000202051`

#### Scenario: Customer number

- **GIVEN** the category "Internet" has the rule `"67890"` in the source, and no migrated account and no counterparty of a migrated transaction has the account number 67890
- **WHEN** the migration finishes
- **THEN** the report does not list the rule of "Internet"

### Requirement: Migrated rules with operators in lower case

The app SHALL list in the report every migrated rule that contains the word and, or, or not without quotation marks and not in capitals. The app reads such a word as an operator, so the rule changes its meaning. The report entry names the category, quotes the word, and says that the word in quotation marks searches the word itself. The rule stays unchanged.

#### Scenario: Rule with a lower case or

- **GIVEN** the category "Salary" has the rule `"Lohn" or "Gehalt"` in the source
- **WHEN** the migration finishes
- **THEN** the report says that the rule of "Salary" reads `or` as an operator and that `"or"` in quotation marks searches the word
- **AND** the category "Salary" has the rule `"Lohn" or "Gehalt"`

#### Scenario: Operators in capitals or in quotation marks

- **GIVEN** the category "Salary" has the rule `"Lohn" OR "Gehalt"` and the category "Books" has the rule `"Krieg" "and" "Frieden"` in the source
- **WHEN** the migration finishes
- **THEN** the report lists neither rule

### Requirement: Transactions

The app SHALL create every transaction of the source with its booking date, value date, amount, currency, counterparty name, counterparty account and bank code, purpose, booking text, SEPA references, and the state booked or pending.

#### Scenario: Counts and balances match

- **GIVEN** the account "Giro" has 6,200 transactions and a balance of 1.234,56 € in the source, and none of them is pending
- **WHEN** the migration finishes
- **THEN** the account "Giro" has 6,200 transactions and shows 1.234,56 €

#### Scenario: Pending transactions count on top

- **GIVEN** the account "Giro" has a balance of 1.000,00 € in the source, booked transactions of -250,00 €, and a pending transaction of -30,00 €
- **WHEN** the migration finishes
- **THEN** the account "Giro" shows 970,00 €

### Requirement: Category, comment, and checkmark of each transaction

The app SHALL keep the category, the comment, and the checkmark of each transaction. A migrated category counts as assigned by hand, so that the rules of the app do not move it.

#### Scenario: Manual category survives

- **GIVEN** a transaction with the purpose "REWE" that the user put into "Gifts" in the source, and a rule of "Food" that matches "REWE"
- **WHEN** the migration finishes and a refresh runs later
- **THEN** the transaction is in "Gifts", with its comment and its checkmark

### Requirement: Migration is all or nothing

The app SHALL store the result of a migration run completely or not at all. When the user cancels during the import, or an error occurs, the database is as it was before the run.

#### Scenario: Source app quits during the import

- **WHEN** the source app quits while the app still reads transactions
- **THEN** the assistant reports that the source app is no longer reachable
- **AND** no account, category, or transaction of this run is stored

### Requirement: Progress

The app SHALL show progress during reading and importing with the current account and the number of transactions done, and offer "Cancel" at every point.

#### Scenario: Large source

- **WHEN** the source has 150,000 transactions
- **THEN** the assistant shows a line such as "Giro, 20,000 of 150,000 transactions" and stays responsive

### Requirement: Repeated runs add only what is new

The app SHALL recognize accounts, categories, and transactions from an earlier run. A later run adds only new objects and creates no duplicate. Changes that the user made in the app since the earlier run stay.

#### Scenario: Second run a week later

- **GIVEN** a first run migrated 18,400 transactions, and the source fetched 35 more since then
- **WHEN** the user runs the migration again
- **THEN** the summary shows 35 new transactions and the import adds exactly these

#### Scenario: Category changed in the app

- **GIVEN** the user moved a migrated transaction from "Food" to "Pets" in the app
- **WHEN** the migration runs again
- **THEN** the transaction stays in "Pets"

#### Scenario: Transaction deleted in the app

- **GIVEN** the user deleted a migrated transaction of 89.00 EUR to "Stadtwerke Musterstadt" in the app
- **WHEN** the migration runs again
- **THEN** the import does not add the transaction again

#### Scenario: Transaction booked in the app

- **GIVEN** a migrated pending transaction of 10.00 EUR to "Kiosk" was booked in the app by a file import, and the source still shows it as pending
- **WHEN** the migration runs again
- **THEN** the transaction stays booked

### Requirement: Migration into a database with accounts

The app SHALL match an account of the source with an existing account of the app by IBAN, or by bank code and account number. Transactions go into the matched account, and transactions that the account already holds are skipped. Accounts without a match are created.

#### Scenario: Account already set up through FinTS

- **GIVEN** the app has a FinTS account with the IBAN DE02120300000000202051 and transactions since August 2026, and the source has the same account with transactions since 2014
- **WHEN** the migration finishes
- **THEN** the account holds the history since 2014 and no transaction twice

### Requirement: Connect a migrated account to its bank

The app SHALL attach a bank access to a migrated account when the add account assistant finds an account with the same IBAN, or the same bank code and account number, and the same currency. The account keeps its transactions, categories, comments, and checkmarks, and the first refresh adds no duplicates. The assistant prefers an open account to a closed one.

#### Scenario: Add the bank after the migration

- **GIVEN** the migrated account "Giro" with the IBAN DE02120300000000202051 and 6,200 transactions
- **WHEN** the user adds the bank with "Add Account..." and the bank reports that IBAN
- **THEN** the assistant marks the account as already present and offers to connect it
- **AND** after the first refresh "Giro" has its 6,200 transactions plus the new ones

#### Scenario: A closed account with the same IBAN

- **GIVEN** the closed migrated account "Giro (alt)" and the open migrated account "Giro", both in EUR with the IBAN DE02120300000000202051
- **WHEN** the bank reports that IBAN in EUR
- **THEN** the assistant offers to connect "Giro" and leaves "Giro (alt)" as it is

#### Scenario: Another currency

- **GIVEN** the migrated account "Giro USD" in USD with the IBAN DE02120300000000202051
- **WHEN** the bank reports that IBAN in EUR
- **THEN** the assistant adds a new account and leaves "Giro USD" without an access

### Requirement: Ask which migrated account to connect

The app SHALL let the user choose the account to connect when more than one open migrated account matches an account of the bank, and when one open migrated account matches more than one account of the bank, such as a migrated account without a subaccount number. Until the user chooses, the assistant adds a new account.

#### Scenario: Several open accounts with the same IBAN

- **GIVEN** the open migrated accounts "Giro" and "Haushalt", both in EUR with the IBAN DE02120300000000202051
- **WHEN** the bank reports that IBAN in EUR
- **THEN** the assistant asks which account to connect, with "New account" selected
- **AND** it connects "Haushalt" only when the user chooses it

#### Scenario: Several subaccounts of one account number

- **GIVEN** the open migrated account "Sparen" with the account number 9 and the Bankleitzahl 12030000, without an IBAN and without a subaccount number
- **WHEN** the bank reports the subaccounts 01 and 02 of the account number 9
- **THEN** the assistant offers "Sparen" in both rows, with "New account" selected
- **AND** it connects "Sparen" only to the row where the user chooses it, and adds the other subaccount as a new account

### Requirement: Portfolio accounts

The app SHALL create portfolio accounts of the source as accounts and, when securities accounts are available in the app, their current positions with name, ISIN, quantity, price, and purchase price. Without that feature the report lists the positions as not migrated.

#### Scenario: Version without securities

- **GIVEN** a version of the app without securities accounts and a source with one portfolio
- **WHEN** the migration finishes
- **THEN** the portfolio exists as an account and the report says that its positions were not migrated

### Requirement: Report

The app SHALL show a report after the import. The report lists for each account the number of migrated transactions and the balance without pending transactions next to the numbers of the source, and it lists what was not migrated with the reason. The user can save the report as a text file.

#### Scenario: Everything matches

- **WHEN** all counts and balances equal those of the source
- **THEN** the report shows a match for every account

#### Scenario: Not migrated

- **WHEN** the migration finishes
- **THEN** the report names login data, templates, standing orders, and statements as not migrated, each with one sentence that says why or what to do

#### Scenario: Budgets in a version without budgets

- **GIVEN** a version of the app without budgets, and a source in which "Food" has a budget of 200,00 € per month and "Leisure" has a budget of 50,00 € per month
- **WHEN** the migration finishes
- **THEN** the report says that 2 categories have a budget in the source and that the app did not take the budgets over
- **AND** the report promises no later step

#### Scenario: Icons

- **WHEN** the migration finishes for a source in which every account and category has an icon
- **THEN** the report says that the app takes the color of each icon and shows its own icons instead of the pictures

### Requirement: The report contains no secrets

The app SHALL write account names, counts, and balances to the report and no login data. The report says that it contains financial data before the user saves it.

#### Scenario: Save the report

- **WHEN** the user chooses "Save Report..."
- **THEN** the app says that the file contains account names and balances and saves it after the user confirms

### Requirement: Category colors

The app SHALL give each category the color it has in the source. The export of the source has no color, but the source draws the icon of a category in its color, so the app takes the color of the icon. A later run gives the color to categories of an earlier run that have no color of their own.

#### Scenario: Category colors

- **GIVEN** "Food" has a blue icon in the source, and an earlier run created "Pets" without a color and the user then colored it green
- **WHEN** the migration runs again
- **THEN** "Food" is blue and "Pets" stays green
