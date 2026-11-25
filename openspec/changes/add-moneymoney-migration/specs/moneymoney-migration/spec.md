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
- **THEN** the assistant says so and offers "Import File..." as the other way to bring in transactions
- **AND** "Import File..." first asks the user to choose an account, then opens the file chooser for that account

#### Scenario: A group, category, or nothing is selected

- **GIVEN** the database has the accounts "Giro" and "Savings", the source app is not installed, and a group, a category, or nothing is selected
- **WHEN** the assistant reports that the source app is not installed
- **THEN** it offers "Import File..."
- **AND** choosing "Savings" imports the file into "Savings", regardless of the sidebar selection

#### Scenario: File import without an account

- **GIVEN** the source app is not installed and the database has no accounts
- **WHEN** the user chooses "Import File..."
- **THEN** the assistant asks the user to add an account before importing transactions
- **AND** it offers "Add Account..."

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

- **GIVEN** the open migrated account "Giro" without a bank access
- **WHEN** the user selects "Giro"
- **THEN** the header shows the notice "This account has no bank access yet, so it cannot be refreshed."
- **AND** the notice has "Connect..." as a button filled with the blue of the system and a white label, at the normal size of a button, also in a window that is not active

### Requirement: Categories

The app SHALL create the categories and category groups of the source with their names, order, and nesting. The default category of the source maps to "Uncategorized". A category that already exists at the same place in the tree is used and not created twice.

#### Scenario: Tree and default

- **GIVEN** the source has the group "Household" with the categories "Food" and "Pets", and a default category named "Sonstiges"
- **WHEN** the migration finishes
- **THEN** the sidebar shows "Household" with "Food" and "Pets"
- **AND** transactions of "Sonstiges" are in "Uncategorized"

### Requirement: Rules

The app SHALL take over the categorization rule of each category that is neither a group nor the default category when the export of the source contains it, without changing its text.

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

### Requirement: A group rule in the export is reported

The app SHALL leave out a group rule and name the group in a note in the report. The note says that a group holds no transactions and asks the user to move the rule to a category below the group. The note about an export without rules counts group rules but ignores rules of the default category.

#### Scenario: A group and its category both have a rule

- **GIVEN** the export contains the group "Wohnen" with `amount<-1000` and its category "Miete" with `"Miete"`
- **WHEN** the migration finishes
- **THEN** one categorization rule is taken over
- **AND** a note says 'The rule of the group "Wohnen" was not taken over, because a group holds no transactions. Move it to a category below the group.'
- **AND** no note says that the export contains no categorization rules

#### Scenario: Only a group has a rule

- **GIVEN** the export contains the group "Wohnen" with `amount<-1000` and no other rule
- **WHEN** the migration finishes
- **THEN** no categorization rule is taken over
- **AND** a note says 'The rule of the group "Wohnen" was not taken over, because a group holds no transactions. Move it to a category below the group.'
- **AND** no note says that the export contains no categorization rules

#### Scenario: An unchanged repeat run still shows its notes

- **GIVEN** an earlier migration stored the group "Wohnen" with `amount<-1000`, and the source export is unchanged
- **WHEN** the user runs the migration again and there is nothing new to import
- **THEN** the sheet shows the report with the note that the rule of "Wohnen" was not taken over
- **AND** the sheet offers "Save Report..." and "Done" without importing anything

#### Scenario: Only the default category has a rule

- **GIVEN** the export contains a rule only for its default category "Sonstiges"
- **WHEN** the migration finishes
- **THEN** no categorization rule is taken over
- **AND** a note says that the export contains no categorization rules

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

The app SHALL report unqualified IBAN or account-number terms and keep rules unchanged. Digit terms count only for a migrated account or counterparty. An IBAN needs a SWIFT registry country, its exact registry length, and mod-97. A quoted term counts only if it is an IBAN, also with spaces between groups of four. Creditor IDs and RF references are no IBANs. Notes name the category and position and suggest `remote_account:`.

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

#### Scenario: Account number of a counterparty

- **GIVEN** the category "Rent" has the rule `"Miete" OR 202051` in the source, and a migrated transaction has a counterparty with the account number 202051 and the bank code 12030000
- **WHEN** the migration finishes
- **THEN** the report says that the rule of "Rent" does not search the account fields and that `remote_account:202051` finds the account of the counterparty

#### Scenario: Calendar week

- **GIVEN** the category "Payroll" has the rule `"Lohn" AND KW45` in the source
- **WHEN** the migration finishes
- **THEN** the report does not list the rule of "Payroll", because `KW45` is too short for an IBAN

#### Scenario: Other identifiers and quoted phrases

- **GIVEN** categories with the rules `DE98ZZZ09999999999`, `RF18539007547034`, `"Ab 01 Januar Miete"`, `"EG 12 Hausverwaltung"`, `"EG 16 Hausverwaltung"`, `"AB 50 Januar Miete"`, `"Ab 30 November Miete"`, and `DE9800009999999999`
- **WHEN** the migration finishes
- **THEN** none of these rules gets an account-term note

#### Scenario: All two-digit phrase numbers

- **GIVEN** rules `"EG NN Hausverwaltung"` and `"AB NN Januar Miete"` for every two-digit value NN from 00 to 99
- **WHEN** the migration finishes
- **THEN** none gets an account-term note, even if its letters and digits pass mod-97

#### Scenario: Registry lengths and spacing

- **GIVEN** valid IBAN terms from Germany with 22 characters, Austria with 20, and the Netherlands with 18
- **WHEN** the migration finishes
- **THEN** each gets an account-term note, also in quotation marks with single spaces between groups of four
- **AND** an otherwise valid German term with one character added or removed gets no note, even with a recalculated mod-97 checksum
- **AND** other spacing gets no IBAN note

### Requirement: Migrated rules with operators in lower case

The app SHALL list in the report every migrated rule that contains and, or, or not as an operator not in capitals. The app reads such a word as an operator, so the rule changes its meaning. The report entry names the category and position, quotes the word, and says that the word in quotation marks searches the word itself. The rule stays unchanged.

#### Scenario: Rule with a lower case or

- **GIVEN** the category "Salary" has the rule `"Lohn" or "Gehalt"` in the source
- **WHEN** the migration finishes
- **THEN** the report says that the rule of "Salary" reads `or` as an operator and that `"or"` in quotation marks searches the word
- **AND** the category "Salary" has the rule `"Lohn" or "Gehalt"`

#### Scenario: Operators in capitals or in quotation marks

- **GIVEN** the category "Salary" has the rule `"Lohn" OR "Gehalt"` and the category "Books" has the rule `"Krieg" "and" "Frieden"` in the source
- **WHEN** the migration finishes
- **THEN** the report lists neither rule

### Requirement: Migrated rules with the words true and false

The app SHALL list in the report every migrated rule that contains true or false as a constant, in any letter case. The app reads `true` as a rule that matches every transaction and `false` as one that matches none, so the rule changes its meaning. The report entry names the category and position, quotes the word, and says that the word in quotation marks searches the word itself. The rule stays unchanged.

#### Scenario: Rule with the word true

- **GIVEN** the category "Drinks" has the rule `true OR "Smoothie"` in the source, meant for the brand "true fruits"
- **WHEN** the migration finishes
- **THEN** the report says that the rule of "Drinks" reads `true` as a rule that matches every transaction and that `"true"` in quotation marks searches the word
- **AND** the category "Drinks" has the rule `true OR "Smoothie"`

#### Scenario: Quoted true

- **GIVEN** the category "Drinks" has the rule `"true" "fruits"` in the source
- **WHEN** the migration finishes
- **THEN** the report does not list the rule of "Drinks"

#### Scenario: False in capitals

- **GIVEN** the category "Drinks" has the rule `FALSE` in the source
- **WHEN** the migration finishes
- **THEN** the report names "Drinks", position 1, and `FALSE`, and says that `"FALSE"` searches the word
- **AND** the category "Drinks" keeps the rule `FALSE`

#### Scenario: Words after a field operator

- **GIVEN** the category "Drinks" has the rule `name:true OR purpose:false OR comment:and` in the source
- **WHEN** the migration finishes
- **THEN** the report does not list the rule, because each word searches its field

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

#### Scenario: Balance follows an imported transaction

- **GIVEN** the migrated account "Giro" shows 1.234,56 €, the balance of the source
- **WHEN** the user imports a file with a transaction of -4,80 € to "Bäckerei Gutbrot"
- **THEN** the account shows 1.229,76 €

### Requirement: Amount limit of the source

The app SHALL refuse a migration when a transaction, an account balance, or a group balance of the source has an amount that is not a finite number or is more than 1,000,000,000,000,000 in the smallest unit of its currency, which is 10.000.000.000.000,00 € for the euro. The app also refuses it when the initial balance of an account would be more. The app names the transaction, the account, or the group and stores nothing.

#### Scenario: Absurd amount in the source

- **WHEN** the transaction 4711 of the source has an amount of 50.000.000.000.000.000,00 €
- **THEN** the assistant says that the amount of transaction 4711 is too large
- **AND** no account, category, or transaction of this run is stored

#### Scenario: Amount that is not a number

- **WHEN** the balance of the account "Savings" in the source is infinite
- **THEN** the assistant says that the balance of the account "Savings" cannot be read
- **AND** no account, category, or transaction of this run is stored

#### Scenario: Initial balance beyond the limit

- **GIVEN** the account "Giro" has a balance of 0,00 € in the source and two transactions of 10.000.000.000.000,00 €
- **WHEN** the migration runs
- **THEN** the assistant says that the initial balance of the account "Giro" is too large
- **AND** no account, category, or transaction of this run is stored

### Requirement: Currency codes of the source

The app SHALL read the currency of each account, each first balance of an account, each transaction, and each category of the source as a code of 3 to 10 letters A to Z and digits that starts with a letter, after trimming and capitals. A missing or empty currency takes the currency of the account in the source for a transaction, and EUR for an account or a category. The app stores no currency text that is not such a code.

#### Scenario: Code in lower case

- **WHEN** the account "Krypto" of the source has the currency "usdc" and a transaction of 20,00 with the currency " usdc"
- **THEN** the account "Krypto" and its transaction are in USDC
- **AND** the complete export of the database imports again with this account and this transaction

#### Scenario: Empty code

- **WHEN** a transaction of the account "Giro" in USD has the currency ""
- **THEN** the transaction is in USD

### Requirement: Source items with a currency that is no code

The app SHALL leave out an account of the source whose currency or first balance currency is not a code, together with its transactions, and a transaction whose currency is not a code. The report names each of them. The app migrates every other account and transaction, and the complete export of the result imports again.

#### Scenario: Account currency that is no code

- **GIVEN** the source has the accounts "Kasse" with the currency "€" and "Giro" with the currency "EUR"
- **WHEN** the migration finishes
- **THEN** the app has the account "Giro" with its transactions and no account "Kasse"
- **AND** the report says 'The account "Kasse" was not migrated, because its currency "€" is not a currency code.'

#### Scenario: Transaction currency that is no code

- **GIVEN** the account "Giro" of the source has a transaction of -20,00 on 2 November 2026 with the currency "US$" and 3 other transactions in EUR
- **WHEN** the migration finishes
- **THEN** the account "Giro" has the 3 other transactions
- **AND** the report says 'The transaction of 02.11.26 over -20,00 in "Giro" was not migrated, because its currency "US$" is not a currency code.'

#### Scenario: Many transactions with a currency that is no code

- **GIVEN** 12 transactions of the source have the currency "€"
- **WHEN** the migration finishes
- **THEN** the report names the first 10 of them one by one
- **AND** the report says "2 more transactions were not migrated, because their currency is not a currency code."

### Requirement: Category currency that is no code

The app SHALL migrate a category of the source whose currency is not a code with the currency EUR, as a category without a currency, and name it in the report.

#### Scenario: Category in a currency sign

- **WHEN** the category "Urlaub" of the source has the currency "€"
- **THEN** the app has the category "Urlaub" in EUR
- **AND** the report says 'The category "Urlaub" was migrated in EUR, because its currency "€" is not a currency code.'

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

The app SHALL show the current step, the current account when known, and completed and total transaction counts during reading and importing. Counts never decrease within a step and update at least once per second while rows are processed. Until an export returns its total, the assistant shows a waiting message without an invented count. "Cancel" stays available until the database transaction commits.

#### Scenario: Large source

- **GIVEN** the source has 150,000 transactions
- **WHEN** the assistant processes transaction 20,000 of "Giro"
- **THEN** it shows "Transactions: 20,000 of 150,000" and "Giro"
- **AND** the assistant stays responsive

#### Scenario: Progress decision

- **GIVEN** the assistant last showed 1,200 of 5,000 transactions at second 10
- **WHEN** 1,234 transactions have been processed at second 11
- **THEN** it shows "Transactions: 1,234 of 5,000"
- **AND** a later update with 1,200 does not replace that count
- **AND** completion shows 5,000 of 5,000 even before the next second

#### Scenario: Comparing one large account

- **GIVEN** one account has 150,000 transactions
- **WHEN** the assistant compares its history
- **THEN** it publishes the current count at least once per second, including a count of zero while it builds the matching index
- **AND** Cancel stops at a comparison checkpoint without returning a partial plan

#### Scenario: Preview becomes outdated

- **GIVEN** the preview includes one new transaction of 1.00 EUR
- **AND** a bank refresh stores that transaction with another identifier before the import starts
- **WHEN** the user imports the preview
- **THEN** the assistant compares the cached export with the current database in its write transaction and stores no duplicate
- **AND** a transaction deleted since the preview stays deleted
- **AND** a bank booking corrected to 2.00 EUR keeps its corrected value and the user's comment

#### Scenario: Bank refreshes during storage

- **GIVEN** a bank refresh is already running and another refresh becomes due
- **WHEN** the user imports the migration plan
- **THEN** storage waits for the running refresh and its final state and account writes
- **AND** no new refresh starts during migration storage
- **AND** progress and Cancel remain responsive
- **AND** refreshes already queued resume after storage and ledger loading finish

#### Scenario: Other database commands during storage

- **GIVEN** the assistant is storing 150,000 transactions
- **WHEN** the user opens the menus or the Extensions window
- **THEN** commands that read or change the database are disabled
- **AND** Cancel, Cancel Refresh, and Lock remain available

#### Scenario: A catalog download finishes during storage

- **GIVEN** an extension catalog download started before migration storage
- **WHEN** the download finishes while the migration holds the database writer
- **THEN** saving the catalog waits without blocking progress, Cancel, or Lock
- **AND** an extension installation already in progress finishes before migration storage starts
- **AND** no new extension installation starts during storage

#### Scenario: Cancel a bank refresh while migration waits

- **GIVEN** migration waits for a bank refresh to finish
- **WHEN** the user chooses "Cancel Refresh"
- **THEN** no deferred command starts another bank refresh after migration ends
- **AND** new manual refresh commands stay disabled during migration storage

#### Scenario: Waiting for the source

- **WHEN** the assistant waits for the transaction export
- **THEN** it shows "Waiting for transactions..."
- **AND** it shows no total until the export returns
- **AND** "Cancel" closes the assistant without storing anything

#### Scenario: Cancel during import

- **GIVEN** the assistant has written 1,234 of 5,000 transactions in its database transaction
- **WHEN** the user chooses "Cancel" before the transaction commits
- **THEN** the transaction rolls back, including new accounts, categories, and replaced starter categories
- **AND** no background result reopens the assistant
- **AND** the database stays open, and the app does not report that the database file changed on disk

#### Scenario: Cancel after the last write check

- **GIVEN** the assistant has written all 5,000 transactions and passed its last cancellation check
- **WHEN** the user chooses "Cancel" before the progress shows "Finishing..."
- **THEN** the transaction commits
- **AND** the assistant stays open, shows "Finishing...", and then shows the report of the stored migration

### Requirement: Repeated runs add only what is new

The app SHALL recognize accounts, categories, and transactions from an earlier run. A later run adds only new objects and creates no duplicate. Changes that the user made in the app since the earlier run stay. The report keeps notes for earlier migrated rules whose text is unchanged in both apps.

#### Scenario: Second run a week later

- **GIVEN** a first run migrated 18,400 transactions, and the source fetched 35 more since then
- **WHEN** the user runs the migration again
- **THEN** the summary shows 35 new transactions and the import adds exactly these

#### Scenario: Corrected balance of the source

- **GIVEN** the migrated account "Giro" shows 1.229,76 € after a first run with 1.234,56 € and an imported transaction of -4,80 €
- **AND** the source corrected its balance to 1.254,56 € without a new transaction
- **WHEN** the migration runs again
- **THEN** the account shows 1.249,76 €

#### Scenario: Transaction that only a refresh stored

- **GIVEN** a first run migrated the account "GiroA" with a balance of 100,00 € and one transaction of -5,00 €
- **AND** a refresh then stored a transaction of 1,00 € from "Laden A" with its own identifier, which the source does not have
- **WHEN** the migration runs again with the source still at 100,00 €
- **THEN** "GiroA" shows 101,00 €, because the transaction counts on top of the balance of the source

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

#### Scenario: Unchanged migrated rules keep their notes

- **GIVEN** an earlier run migrated "Drinks" with `true OR "Smoothie"`, "Salary" with `"Lohn" or "Gehalt"`, and "Rent" with `DE02120300000000202051`
- **AND** the source export and the stored rules are unchanged
- **WHEN** the user runs the migration again with nothing new to import
- **THEN** the sheet shows the report with the constant, operator, and account-term notes for these rules
- **AND** "Save Report..." includes all three notes in the saved text
- **AND** the app keeps the stored rules and imports nothing

### Requirement: Migration into a database with accounts

The app SHALL match an account of the source with an existing account of the app by IBAN, or by bank code and account number. Transactions go into the matched account, and transactions that the account already holds are skipped. Accounts without a match are created.

#### Scenario: Account already set up through FinTS

- **GIVEN** the app has a FinTS account with the IBAN DE02120300000000202051 and transactions since August 2026, and the source has the same account with transactions since 2014
- **WHEN** the migration finishes
- **THEN** the account holds the history since 2014 and no transaction twice

### Requirement: Connect a migrated account to its bank

The app SHALL attach a bank access to a migrated account when the add account assistant finds an account with the same IBAN, or the same bank code and account number, and the same currency. A portfolio and an account of another type never match, unless the account has a bank access already. The account keeps its transactions, categories, comments, and checkmarks, and the first refresh adds no duplicates. The assistant prefers an open account to a closed one.

#### Scenario: Add the bank after the migration

- **GIVEN** the migrated account "Giro" with the IBAN DE02120300000000202051 and 6,200 transactions
- **WHEN** the user adds the bank with "Add Account..." and the bank reports that IBAN
- **THEN** the assistant marks the account as already present and offers to connect it
- **AND** after the first refresh "Giro" has its 6,200 transactions plus the new ones

#### Scenario: A closed account with the same IBAN

- **GIVEN** the closed migrated account "Giro (alt)" and the open migrated account "Giro", both in EUR with the IBAN DE02120300000000202051
- **WHEN** the bank reports that IBAN in EUR
- **THEN** the assistant offers to connect "Giro" and leaves "Giro (alt)" as it is

#### Scenario: A portfolio with the number of a giro account

- **GIVEN** the migrated portfolio "Depot" with the Bankleitzahl 12030000 and the account number 202051, in EUR
- **WHEN** the bank reports the giro account 202051 in EUR and no portfolio
- **THEN** the assistant adds the giro account as a new account and leaves "Depot" without an access
- **AND** "Connect..." in "Depot" chooses nothing, and the row of the giro account does not offer "Depot"

#### Scenario: A connected account that a refresh made a portfolio

- **GIVEN** the account "Girokonto" with the IBAN DE02120300000000202051 has a bank access, and a refresh made it a portfolio
- **WHEN** the user chooses "Look for New Accounts..." and the bank still lists that IBAN as a giro account
- **THEN** the assistant counts "Girokonto" as present and adds no second account

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

### Requirement: Connect from a migrated account

The app SHALL offer "Connect..." in a notice in the header of an open migrated account without a bank access. It opens the add account assistant with the IBAN of the account, else its Bankleitzahl, as the bank entry. When the account matches exactly one account of the bank, counting accounts that the app has connected already, and that row is a choice, the row has the account chosen. In every other case the rows stay as the assistant sets them.

#### Scenario: Connect from the account

- **GIVEN** the migrated account "Giro" with the IBAN DE02120300000000202051 and no bank access
- **WHEN** the user selects "Giro" and clicks "Connect..."
- **THEN** the add account assistant opens with DE02120300000000202051 as the bank entry
- **AND** a migrated account without an IBAN starts with its Bankleitzahl 12030000, and one with neither starts with an empty entry

#### Scenario: A closed migrated account

- **WHEN** the user selects the closed migrated account "Giro (alt)"
- **THEN** the header says that the account came from the source app and is not connected to a bank
- **AND** it shows no notice and no "Connect...", because the assistant leaves a closed account as it is

### Requirement: Mark of an account without a bank access in the sidebar

The app SHALL show the symbol of a network with a slash on the left of the sidebar row of an open migrated account without a bank access, in the secondary color, with the help tag "Not connected to a bank". The color mark of the account stays.

#### Scenario: Only the account that needs connecting

- **GIVEN** the open migrated account "Girokonto" without a bank access, the offline account "Bargeld", the closed migrated account "Giro (alt)", and the account "Tagesgeld" of a bank access
- **WHEN** the sidebar shows them
- **THEN** only the row of "Girokonto" shows the mark, on the left of its color mark, and the help tag of the mark says "Not connected to a bank"
- **AND** the rows of "Bargeld", "Giro (alt)", and "Tagesgeld" show no mark

#### Scenario: A long name

- **GIVEN** the open migrated account "Gemeinschaftskonto Haushalt und Urlaub Familie Mustermann" without a bank access, with a balance of 1.234,56 €
- **WHEN** the sidebar is 240 points wide
- **THEN** the row shows the mark, the color mark, the start of the name with an ellipsis, and 1.234,56 €

#### Scenario: Connected

- **WHEN** the user connects "Girokonto" to its bank
- **THEN** its row shows no mark

### Requirement: Refresh commands and accounts without a bank access

The app SHALL say that an account has no bank access yet and offer "Connect..." for it when a refresh command finds no account to refresh but an open migrated account without a bank access. Every refresh command of the main window does this, also ⌘R, the refresh button under the sidebar, and the context menu of the account. "Connect..." opens the add account assistant for the selected account when the command covers it, else for the first such account in the order of the sidebar.

#### Scenario: Only migrated accounts

- **GIVEN** the open migrated accounts "Giro" and "Sparen" without a bank access, and no other account
- **WHEN** the user presses ⌘R
- **THEN** the app contacts no bank
- **AND** it says "The accounts are not connected to a bank yet." with the buttons "Connect..." and "Cancel"
- **AND** "Connect..." opens the add account assistant for "Giro"

#### Scenario: One migrated account

- **GIVEN** the open migrated account "Sparen" without a bank access
- **WHEN** the user selects "Sparen" and chooses "Refresh Account"
- **THEN** the app says "“Sparen” is not connected to a bank yet." with the buttons "Connect..." and "Cancel"
- **AND** "Connect..." opens the add account assistant for "Sparen"

#### Scenario: Connected accounts besides migrated ones

- **GIVEN** the account "Girokonto" of a bank access and the open migrated account "Sparen" without a bank access
- **WHEN** the user presses ⌘R
- **THEN** the app refreshes "Girokonto" and says nothing about "Sparen"

#### Scenario: Context menu of a migrated account

- **GIVEN** the open migrated account "Sparen" without a bank access
- **WHEN** the user opens the context menu of "Sparen" in the sidebar
- **THEN** "Refresh Account" is enabled, and choosing it says "“Sparen” is not connected to a bank yet." with "Connect..."
- **AND** the menu has no "Edit Login Data..." and no "Look for New Accounts..."

#### Scenario: Menu bar popover

- **GIVEN** the open migrated account "Giro" without a bank access, and no other account
- **WHEN** the user opens the popover of the menu bar icon
- **THEN** "Refresh All Accounts" in the popover is disabled, because the popover shows no alert and the main window can be closed

#### Scenario: Lock right after Connect

- **GIVEN** the alert for "Giro" is open
- **WHEN** the user clicks "Connect..." and the app locks before the alert has slid out
- **THEN** the add account assistant does not open, also not after the unlock

#### Scenario: Nothing to connect

- **GIVEN** the offline account "Cash" and the closed migrated account "Giro (alt)", and no other account
- **WHEN** the user looks at "Refresh All Accounts"
- **THEN** the command is disabled

#### Scenario: Connect one of several accounts with the same IBAN

- **GIVEN** the open migrated accounts "Giro" and "Haushalt", both in EUR with the IBAN DE02120300000000202051
- **WHEN** the user clicks "Connect..." in "Haushalt" and the bank reports that IBAN in EUR
- **THEN** the assistant asks which account to connect, with "Haushalt" selected

#### Scenario: Connect an account without a subaccount number

- **GIVEN** the open migrated account "Sparen" with the account number 9 and the Bankleitzahl 12030000, without a subaccount number
- **WHEN** the user clicks "Connect..." in "Sparen" and the bank reports the subaccounts 01 and 02 of the account number 9
- **THEN** both rows have "New account" selected

#### Scenario: One subaccount connected already

- **GIVEN** the subaccount 01 of the account number 9 is connected as "Sparkonto 01", and the open migrated account "Sparen" has the account number 9 without a subaccount number
- **WHEN** the user clicks "Connect..." in "Sparen" and the bank reports the subaccounts 01 and 02
- **THEN** the assistant offers "Sparen" in the row of 02, with "New account" selected

### Requirement: Portfolio accounts

The app SHALL create portfolio accounts of the source as accounts and, when securities accounts are available in the app, their current positions with name, ISIN, quantity, price, and purchase price. Without that feature the report lists the positions as not migrated.

#### Scenario: Positions in a verified export

- **GIVEN** a verified securities export describes 12.5 units of "Example Fund", ISIN "DE000A0SYN01", a quote of 80.25 EUR, and a purchase price of 70.10 EUR
- **WHEN** the export keys and their types are documented and supported
- **THEN** the portfolio shows those values without rounding the quantity or the prices
- **AND** a repeated run creates no duplicate position

#### Scenario: Position keys are not verified

- **GIVEN** the source exports "Depot" with a balance of 10,000.00 EUR and no verified position fields
- **WHEN** the migration finishes
- **THEN** "Depot" exists with a balance of 10,000.00 EUR and its first portfolio history record
- **AND** the report names "Depot" and says its positions were not migrated because the portfolio export format is not verified
- **AND** the report says to connect the portfolio to its bank to fetch positions
- **AND** a repeated run keeps this note and any positions already fetched from the bank

#### Scenario: Position keys are not verified for a connected portfolio

- **GIVEN** "Depot" came over in an earlier run and is now connected to its bank, which fetched 12.5 units of "Example Fund"
- **WHEN** the migration runs again
- **THEN** the report names "Depot" and says its positions were not migrated because the portfolio export format is not verified
- **AND** the report says that its bank access fetches them with each refresh, and does not ask to connect "Depot"
- **AND** the 12.5 units of "Example Fund" stay

### Requirement: Report

The app SHALL show a report after the import. The report lists for each account the number of migrated transactions and the balance without pending transactions next to the numbers of the source, and it lists what was not migrated with the reason. The user can save the report as a text file.

#### Scenario: Pending transactions are no mismatch

- **GIVEN** the account "Giro" has a balance of 1.000,00 € and one pending transaction of -30,00 € in the source
- **WHEN** the migration finishes
- **THEN** the report shows 1.000,00 € for "Giro" next to the balance of the source, 1.000,00 €, as a match

#### Scenario: Two source accounts share an existing target

- **GIVEN** the source accounts "Giro" with 3 transactions and 1.234,56 EUR and "Savings" with 1 transaction and 500,00 EUR both have the IBAN DE02120300000000202051
- **AND** the existing account "Mein Giro" has that IBAN
- **WHEN** the migration finishes
- **THEN** the report lists "Giro" with 3 of 3 transactions and its source balance of 1.234,56 EUR, and "Savings" with 1 of 1 transaction and its source balance of 500,00 EUR
- **AND** one note says '2 source accounts, "Giro", "Savings", were merged into "Mein Giro". Each line shows the source balance; only transactions are compared.'
- **AND** a missing transaction makes only its source account differ

#### Scenario: Identical rows of sources that share a target

- **GIVEN** "Giro" and "Savings" each export one booked transaction of -5,00 EUR with the same date and purpose into one existing account
- **WHEN** only the transaction of "Savings" is stored
- **THEN** the report shows "Giro" with 0 of 1 transactions as a difference and "Savings" with 1 of 1 as a match

#### Scenario: A shared target keeps a row no longer in the source

- **GIVEN** a shared target still holds one migrated transaction that neither source exports any more
- **WHEN** the migration finishes
- **THEN** the shared target note also says "The target also holds 1 migrated transaction no longer in the source export."
- **AND** the report does not assign that transaction to an unknown source account

#### Scenario: Everything matches

- **WHEN** all counts and balances equal those of the source
- **THEN** the report shows a match for every account

#### Scenario: Not migrated

- **WHEN** the migration finishes
- **THEN** the report names login data, templates, standing orders, and statements as not migrated, each with one sentence that says why or what to do
- **AND** the templates note says to use "Export Transfer Templates..." in the source app to keep them
- **AND** the statements note says to use "Show in Finder..." on "Statements" in the source app to find the statement files and copy them to keep them

#### Scenario: Budgets in a version without budgets

- **GIVEN** a version of the app without budgets, and a source in which "Food" has a budget of 200,00 € per month and "Leisure" has a budget of 50,00 € per month
- **WHEN** the migration finishes
- **THEN** the report says that 2 categories have a budget in the source and that the app did not take the budgets over
- **AND** the report promises no later step

#### Scenario: Icons

- **WHEN** the migration finishes for a source in which every account and category has an icon
- **THEN** the report says that the app takes the color of each icon and shows its own icons instead of the pictures

### Requirement: The report contains no secrets

The app SHALL write account names, counts, balances, and rule notes to the report and no login data. Before saving, the report warns that it contains account names, balances, and account numbers and IBANs from rules.

#### Scenario: Save the report

- **WHEN** the user chooses "Save Report..."
- **THEN** the app says "The report contains account names, balances, and account numbers and IBANs from rules."
- **AND** the message says "Anyone who can open the file can read them."
- **AND** the app saves it only after the user confirms

### Requirement: Category colors

The app SHALL give each category the color it has in the source. The export of the source has no color, but the source draws the icon of a category in its color, so the app takes the color of the icon. A later run gives the color to categories of an earlier run that have no color of their own.

#### Scenario: Category colors

- **GIVEN** "Food" has a blue icon in the source, and an earlier run created "Pets" without a color and the user then colored it green
- **WHEN** the migration runs again
- **THEN** "Food" is blue and "Pets" stays green
