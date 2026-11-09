# Spec Delta

## Purpose

Search and filters reduce a transaction list to the rows that the user looks for. This capability defines the live search, the filters for period, status, amount, category, and account, how they combine, and how a search can be saved.

## ADDED Requirements

### Requirement: Results while typing

The app SHALL filter the list of the current view after each change of the text in the search field, with no need to press Return.

#### Scenario: Type a name

- **GIVEN** the account "Giro" with 3 transactions to "Stadtwerke Musterstadt" among 500 others
- **WHEN** the user types "stadtw" in the search field
- **THEN** the list shows only the 3 transactions

#### Scenario: Shortcut

- **WHEN** the user chooses "Find in Transactions..." or presses ⌘F
- **THEN** the cursor is in the search field

### Requirement: The search covers all text of a transaction

The app SHALL search the counterparty name, the purpose, the booking text, the end-to-end reference, the mandate reference, the creditor ID, the account numbers of both sides, the category name, and the comment.

#### Scenario: Text in the comment

- **GIVEN** a transaction with the comment "Warranty until 2028" and no other field with that word
- **WHEN** the user searches for "warranty"
- **THEN** the list shows the transaction

#### Scenario: Counterparty IBAN

- **WHEN** the user searches for "DE02120300000000202051"
- **THEN** the list shows all transactions with that counterparty IBAN

### Requirement: The search finds text inside words

The app SHALL treat a search word as found when it occurs at the start, in the middle, or at the end of a word of the transaction.

#### Scenario: Middle of a word

- **GIVEN** a transaction with the purpose "Kundennummer 4711"
- **WHEN** the user searches for "nummer"
- **THEN** the list shows the transaction

### Requirement: The search ignores case, umlauts, and Unicode form

The app SHALL compare search text without regard to upper and lower case. It treats ä, ö, ü, and ß as equal to ae, oe, ue, and ss, and it treats a composed and a decomposed form of the same letter as equal.

#### Scenario: Umlaut written out

- **GIVEN** a transaction to "Bäckerei Gutbrot"
- **WHEN** the user searches for "baeckerei"
- **THEN** the list shows the transaction

#### Scenario: Decomposed umlaut

- **GIVEN** the bank delivered the name "Bäckerei" with a and a separate combining mark
- **WHEN** the user types "Bäckerei" on the keyboard
- **THEN** the list shows the transaction

### Requirement: All search words must occur

The app SHALL show a transaction only when every word of the search text occurs in it, in any order and in any of the searched fields.

#### Scenario: Two words in different fields

- **GIVEN** a transaction to "Stadtwerke Musterstadt" with the purpose "Abschlag November"
- **WHEN** the user searches for "november stadtwerke"
- **THEN** the list shows the transaction

#### Scenario: One word missing

- **WHEN** the user searches for "stadtwerke dezember"
- **THEN** the list does not show that transaction

### Requirement: The search accepts the rule language

The app SHALL accept every expression of the categorization rule language in the search field, with the same meaning as in a rule.

#### Scenario: Field operator and amount

- **WHEN** the user searches for `name:"Stadtwerke" AND amount<-100`
- **THEN** the list shows the transactions to counterparties with "Stadtwerke" in the name that withdrew more than 100,00 €

#### Scenario: Either word

- **WHEN** the user searches for `"Lohn" OR "Gehalt"`
- **THEN** the list shows the transactions that contain one of the two words

### Requirement: The search finds exact amounts

The app SHALL find a transaction by its amount when the user enters the amount with its decimals, with a decimal comma or a decimal point, and with or without a sign.

#### Scenario: Amount with decimals

- **GIVEN** one transaction of -49,99 € and one of -149,99 €
- **WHEN** the user searches for "49,99"
- **THEN** the list shows the transaction of -49,99 € and not the one of -149,99 €

### Requirement: Count and sum of the results

The app SHALL show the number of found transactions and their sum in the status line while a search or a filter is active. Amounts in different currencies are summed for each currency.

#### Scenario: Sum of a search

- **GIVEN** a search that finds 12 transactions of -89,00 € each
- **WHEN** the user looks at the status line
- **THEN** it shows 12 transactions and the sum -1.068,00 €

#### Scenario: Two currencies

- **GIVEN** a search that finds -100,00 € and -20,00 USD
- **WHEN** the user looks at the status line
- **THEN** it shows one sum in euros and one sum in US dollars

### Requirement: Clear the search

The app SHALL restore the unfiltered list when the user clears the search field with its clear button, with the Escape key, or by deleting the text.

#### Scenario: Escape

- **GIVEN** a search for "netflix"
- **WHEN** the user presses the Escape key in the search field
- **THEN** the field is empty and the list shows all transactions that pass the filters

### Requirement: Search for the counterparty of a transaction

The app SHALL offer "Search for" with the counterparty name as the first command in the context menu of a transaction. The command puts the name into the search field as a phrase and searches the current view.

#### Scenario: All invoices of one company

- **GIVEN** a transaction to "Mobilfunk Muster GmbH" in the group "Private"
- **WHEN** the user chooses "Search for" with that name
- **THEN** the search field holds the name and the list shows all transactions of "Private" with that counterparty

### Requirement: Period filter

The app SHALL filter the list by booking date with the "Period" menu. Its values are "Show All", "30 Days", "90 Days", "12 Months", the current month and the two months before it, the current quarter and the two quarters before it, the current year and the two years before it, and "Custom...".

#### Scenario: Last month

- **GIVEN** today is 09.11.2026
- **WHEN** the user chooses the entry for October 2026
- **THEN** the list shows the transactions from 01.10.2026 to 31.10.2026

#### Scenario: Ninety days

- **GIVEN** today is 09.11.2026
- **WHEN** the user chooses "90 Days"
- **THEN** the list shows the transactions from 11.08.2026 on

### Requirement: Custom period

The app SHALL open a date range with a start date and an end date when the user chooses "Custom..." in the "Period" menu. Both dates belong to the period, and the menu button shows the chosen range.

#### Scenario: Tax year in two parts

- **WHEN** the user chooses "Custom..." and enters 01.04.2025 and 31.03.2026
- **THEN** the list shows the transactions from 01.04.2025 to 31.03.2026

#### Scenario: End before start

- **WHEN** the user enters an end date that lies before the start date
- **THEN** the app does not apply the range and marks the end date

### Requirement: The period applies to every view

The app SHALL apply the chosen period to all accounts, account groups, and categories at once.

#### Scenario: Change the view

- **GIVEN** the user chose "12 Months" in the account "Giro"
- **WHEN** the user selects the category "Groceries"
- **THEN** the "Period" menu shows "12 Months" and the list is filtered by it

### Requirement: Status filter

The app SHALL filter the list by checkmark with the "Status" menu. Its values are "Show All", "Checked", and "Unchecked".

#### Scenario: Open items

- **GIVEN** 40 transactions of which 35 are checked
- **WHEN** the user chooses "Unchecked"
- **THEN** the list shows the 5 unchecked transactions

### Requirement: Amount filter

The app SHALL filter the list by amount with the "Amount" menu. Its values are "Show All", "Deposits", "Withdrawals", and "Custom...". "Custom..." takes a "min. amount", a "max. amount", or both.

#### Scenario: Deposits only

- **WHEN** the user chooses "Deposits"
- **THEN** the list shows only transactions with an amount above zero

#### Scenario: Range

- **WHEN** the user chooses "Custom..." and enters the min. amount 100 and the max. amount 500
- **THEN** the list shows the transactions whose amount, without its sign, lies between 100,00 and 500,00

#### Scenario: Only a minimum

- **WHEN** the user enters the min. amount 1000 and leaves the max. amount empty
- **THEN** the list shows the transactions of 1.000,00 or more in either direction

### Requirement: Category filter in account views

The app SHALL filter the list of an account or an account group with the "Category" menu. The menu lists "Show All" and every category including "Uncategorized". The entry of a category group includes the categories below it.

#### Scenario: One category in one account

- **GIVEN** the account "Giro"
- **WHEN** the user chooses "Groceries" in the "Category" menu
- **THEN** the list shows the transactions of "Giro" in "Groceries"

#### Scenario: Uncategorized

- **WHEN** the user chooses "Uncategorized"
- **THEN** the list shows the transactions of the account that have no category

### Requirement: Account filter in category views

The app SHALL filter the list of a category or a category group with the "Account" menu. The menu lists "Show All" and every account and account group.

#### Scenario: One account in one category

- **GIVEN** the category view "Groceries"
- **WHEN** the user chooses "Credit card" in the "Account" menu
- **THEN** the list shows the transactions of "Groceries" that belong to "Credit card"

### Requirement: Search and filters combine

The app SHALL show a transaction only when it matches the search text and every active filter.

#### Scenario: Search inside a period

- **GIVEN** the period "12 Months" and the status "Unchecked"
- **WHEN** the user searches for "amazon"
- **THEN** the list shows the unchecked transactions of the last 12 months that contain "amazon"

### Requirement: Hint about active filters

The app SHALL show a line below the last row of the list for each active filter. The line names the kind of filter and says that some entries might be hidden.

#### Scenario: Date filter

- **GIVEN** the period "30 Days"
- **WHEN** the user scrolls to the end of the list
- **THEN** a line says that a date filter is active and that some entries might be hidden

#### Scenario: No filter

- **WHEN** every filter shows "Show All"
- **THEN** the list ends with its last transaction

### Requirement: Saved searches

The app SHALL let the user save the current search text and filters under a name. A saved search appears in the sidebar section "Searches". Selecting it shows the matching transactions of all accounts with the count and the sum. The user can rename and remove a saved search.

#### Scenario: Save and reuse

- **GIVEN** the search text "Finanzamt" and the amount filter "Withdrawals"
- **WHEN** the user saves the search as "Tax payments" and later selects "Tax payments" in the sidebar
- **THEN** the list shows all withdrawals that contain "Finanzamt" from every account

#### Scenario: New transactions

- **GIVEN** the saved search "Tax payments"
- **WHEN** a refresh brings a new matching transaction
- **THEN** the saved search shows it the next time the user selects it

#### Scenario: Remove

- **WHEN** the user removes "Tax payments"
- **THEN** the entry leaves the sidebar and no transaction changes

### Requirement: The search is fast with a large history

The app SHALL show the results of a search over 50,000 transactions within 100 milliseconds on a Mac with an M1 processor.

#### Scenario: Ten years of history

- **GIVEN** a database with 50,000 transactions
- **WHEN** the user types one more letter in the search field
- **THEN** the list and the sum are up to date within 100 milliseconds
