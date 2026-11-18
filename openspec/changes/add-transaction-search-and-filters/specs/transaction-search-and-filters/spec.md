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

The app SHALL accept every expression of the categorization rule language in the search field, with the same meaning as in a rule. A search word or phrase without a field name, also with a wildcard, searches the fields that the requirement on searched fields names and finds text inside words, so it finds account numbers, IBANs, and the category name.

#### Scenario: Field operator and amount

- **WHEN** the user searches for `name:"Stadtwerke" AND amount<-100`
- **THEN** the list shows the transactions to counterparties with "Stadtwerke" in the name that withdrew more than 100,00 €

#### Scenario: Word without a field name

- **GIVEN** a transaction with the purpose "REWE-Markt 4711" in the category "Groceries" of the account "Girokonto"
- **WHEN** the user searches for `"REWE" AND amount<0`, `Groc*`, `/groceries/`, or `Girok*`
- **THEN** the list shows the transaction

#### Scenario: True and false

- **GIVEN** the account "Giro" with 2 transactions
- **WHEN** the user searches for `true`
- **THEN** the list shows both transactions
- **WHEN** the user searches for `false`
- **THEN** the list shows no transaction

#### Scenario: A quoted word finds text inside words

- **GIVEN** a transaction with the purpose "Lohnsteuer 10/2026"
- **WHEN** the user searches for `"Lohn"`
- **THEN** the list shows the transaction
- **AND** a categorization rule `"Lohn"` does not match it

#### Scenario: Phrase across white space

- **GIVEN** a transaction with the purpose "Abschlag" and "November" on two lines
- **WHEN** the user searches for `"Abschlag November"`
- **THEN** the list shows the transaction

#### Scenario: Text the rule language rejects

- **GIVEN** a transaction to "Stadtwerke Musterstadt"
- **WHEN** the user types `"Stadtw`, `Stadtwerke OR`, `Stadtwerke or`, `Stadtwerke +`, `Name:Stadtwerke OR`, `name:="Stadtw`, or `Stadtwerke amount:=-`
- **THEN** the list shows the transaction, because the app searches the plain words of the text

#### Scenario: A constant in rejected text

- **GIVEN** a transaction to "Stadtwerke Musterstadt"
- **WHEN** the user types `false "Stadtw` or `NOT true "Stadtw`
- **THEN** the list shows no transaction, because the fallback keeps the constants and their negation
- **WHEN** the user types `true "Stadtw` or `NOT false "Stadtw`
- **THEN** the list shows the transaction

#### Scenario: Rejected text with an excluded word

- **GIVEN** a transaction to "Stadtwerke Musterstadt" without the words "Gehalt" and "Lohn"
- **WHEN** the user types `Stadtwerke NOT "Gehalt`, `Stadtwerke -"Gehalt Lohn`, `name!=Gehalt "Stadtw`, `Stadtwerke -(Gehalt Lohn`, `Stadtwerke NOT /Gehalt Lohn`, or `Stadtwerke name:-"Gehalt`
- **THEN** the list shows the transaction, because the app reads an open quotation mark, regular expression, or parenthesis up to the end of the text and leaves out the words that the text excludes

#### Scenario: Unfinished regular expression

- **GIVEN** a transaction to "Stadtwerke Musterstadt"
- **WHEN** the user types `Stadtwerke /\d` or `Stadtwerke /Absch.*`
- **THEN** the list shows the transaction, because the app leaves out a word of a regular expression with a special character

#### Scenario: Either word

- **WHEN** the user searches for `"Lohn" OR "Gehalt"`
- **THEN** the list shows the transactions that contain one of the two words

#### Scenario: An amount outside the stored range

- **GIVEN** a transaction of 92.233.720.368.547.758,07 €
- **WHEN** the user searches for `amount=100000000000000000`
- **THEN** the list shows no transaction, as the same categorization rule does
- **WHEN** the user searches for `amount<99999999999999999999`
- **THEN** the list shows the transaction, as the same categorization rule does

### Requirement: A regular expression without a field name

The app SHALL read a regular expression without a field name in the search field against the fields that a rule term without a field name reads, and against the names of the account and the category. It does not read account numbers or IBANs.

#### Scenario: Category, account name, and IBAN

- **GIVEN** a transaction in the category "Groceries" of the account "Girokonto" with the IBAN DE02 1203 0000 0000 2020 51
- **WHEN** the user searches for `/groceries/` or `/^girok/`
- **THEN** the list shows the transaction
- **WHEN** the user searches for `/DE02 1203/`
- **THEN** the list does not show the transaction

### Requirement: A regular expression that does not end

The app SHALL stop a regular expression in the search that reads one text for about 100 ms of processor time or spends 300 ms of processor time in all regular expression calls of one search, show no results for the whole search, and show "The regular expression stopped because it is too slow" without a sum in the status line.

#### Scenario: Lazy quantifier after an anchor

- **GIVEN** a transaction with the purpose "Tel. +49 170 1234567"
- **WHEN** the user searches for `/^+?49/`
- **THEN** the list shows no transaction within a second

#### Scenario: A slow row and a fast matching row

- **GIVEN** transactions with the purposes "Kundennummer: 4711" and "Abschlag Strom November 2026"
- **WHEN** the user searches for `purpose:/(\w+\s?)*:/` or `NOT purpose:/(\w+\s?)*:/`
- **THEN** the list shows no transaction, in either row order
- **AND** the status line shows "The regular expression stopped because it is too slow" without a sum

#### Scenario: Many slow rows share one processor-time limit

- **GIVEN** 100 transactions whose purpose is "aaaaaaaaaaaaaaaaaaaa!"
- **WHEN** the user searches for `purpose:/^(a+)+$/`
- **THEN** the search stops after about 300 ms of processor time spent on regular expressions on the searching thread
- **AND** the list shows no transaction and the status line shows "The regular expression stopped because it is too slow" without a sum
- **AND** waiting for a processor on a busy Mac uses none of the limit

### Requirement: The search finds exact amounts

The app SHALL find a transaction by its amount when the user enters the amount with its decimals, with a decimal comma or a decimal point, with or without thousands separators, and with or without a sign. A search word that reads as an amount finds only the exact value of an amount. Without a sign it finds either sign, and with a sign only that sign. In the other searched fields the word still finds text inside words.

#### Scenario: Amount with decimals

- **GIVEN** one transaction of -49,99 € and one of -149,99 €
- **WHEN** the user searches for "49,99"
- **THEN** the list shows the transaction of -49,99 € and not the one of -149,99 €

#### Scenario: Amount with a sign

- **GIVEN** one transaction of -49,99 € and one of 49,99 €
- **WHEN** the user searches for "-49,99"
- **THEN** the list shows only the transaction of -49,99 €
- **WHEN** the user searches for "49.99"
- **THEN** the list shows both transactions

#### Scenario: Amount with thousands separators

- **GIVEN** one transaction of -1.249,99 €
- **WHEN** the user searches for "1.249,99" or "1,249.99"
- **THEN** the list shows the transaction
- **WHEN** the user searches for "249,99"
- **THEN** the list shows no transaction

#### Scenario: Amount with three decimals

- **GIVEN** one transaction of 1,230 KWD and one of 1,234 KWD
- **WHEN** the user searches for "1,23" or "1,230"
- **THEN** the list shows only the transaction of 1,230 KWD
- **WHEN** the user searches for "1,2340"
- **THEN** the list shows only the transaction of 1,234 KWD

#### Scenario: Amount without the integer part

- **GIVEN** one transaction of -0,99 € and one of -149,99 €
- **WHEN** the user searches for ",99"
- **THEN** the list shows only the transaction of -0,99 €

#### Scenario: Amount as text in the purpose

- **GIVEN** a transaction of -10,00 € with the purpose "Rechnung 149,99"
- **WHEN** the user searches for "49,99"
- **THEN** the list shows the transaction

### Requirement: Count and sum of the results

The app SHALL show the number of found transactions and their sum in the status line while a search or a filter is active. A pending transaction marked for review counts in the number but not in the sum, as the capability `account-refresh` states. Amounts in different currencies are summed for each currency.

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

#### Scenario: Saved range with the end before the start

- **GIVEN** a saved filter bar or a saved search holds the custom period 31.03.2026 to 01.04.2025
- **WHEN** the app restores it
- **THEN** the period is 01.04.2025 to 31.03.2026

### Requirement: The filter bar applies to every view

The app SHALL keep the period, the status, the amount, and the search text when the user opens another account, account group, or category, whether the pin is on or off. The category filter stays while the user moves between accounts and account groups, and the account filter stays while the user moves between categories.

#### Scenario: Change the view without the pin

- **GIVEN** the pin is off and the user chose "12 Months", the status "Unchecked", and the amount "Withdrawals" in the account "Giro"
- **WHEN** the user selects the category "Groceries"
- **THEN** the "Period" menu shows "12 Months", the "Status" menu shows "Unchecked", and the "Amount" menu shows "Withdrawals"
- **AND** the list of "Groceries" is filtered by all three

### Requirement: A view resets the filter it does not show

The app SHALL set the filter that the filter bar of a view does not show to "Show All" when the user opens that view and when the app opens with that view after a restart. Opening a category or a category group sets the category filter to "Show All", and opening an account or an account group sets the account filter to "Show All".

#### Scenario: From a category to an account

- **GIVEN** the category view "Groceries" with the status "Unchecked" and "Credit card" in the "Account" menu
- **WHEN** the user selects the account "Giro"
- **THEN** the list shows the unchecked transactions of "Giro"
- **AND** the account filter is "Show All"

#### Scenario: From an account to a category

- **GIVEN** the account "Giro" with the status "Unchecked" and "Groceries" in the "Category" menu
- **WHEN** the user selects the category "Rent"
- **THEN** the list shows the unchecked transactions of "Rent"
- **AND** the category filter is "Show All"

### Requirement: Turning the pin on saves the filter bar

The app SHALL show a pin with the tooltip "Save filter bar" in the filter bar. When the user turns the pin on, the app saves the period, the status, the amount, the category filter, and the account filter as the default, and it saves each later change while the pin stays on. After a restart, the pin is still on and the filter bar shows the saved default.

#### Scenario: Restart with the pin on

- **GIVEN** the user chose "90 Days" and the status "Unchecked" in the account "Giro"
- **WHEN** the user turns the pin on, quits the app, and opens it again
- **THEN** the pin is on, the "Period" menu shows "90 Days", and the "Status" menu shows "Unchecked"

#### Scenario: Restart with the pin off

- **GIVEN** the pin is off and the user chose "90 Days" in the account "Giro"
- **WHEN** the user quits the app and opens it again
- **THEN** every menu of the filter bar shows "Show All"

### Requirement: Turning the pin off resets the filters

The app SHALL set the period, the status, the amount, the category filter, and the account filter to "Show All" and clear the search field when the user turns the pin off.

#### Scenario: Unpin

- **GIVEN** the pin is on, the user chose "12 Months" and the status "Unchecked" in the account "Giro", and the search field holds "amazon"
- **WHEN** the user turns the pin off
- **THEN** every menu of the filter bar shows "Show All", the period included
- **AND** the search field is empty and the list shows every transaction of "Giro"

### Requirement: Status filter

The app SHALL filter the list by checkmark with the "Status" menu. Its values are "Show All", "Checked", and "Unchecked".

#### Scenario: Open items

- **GIVEN** 40 transactions of which 35 are checked
- **WHEN** the user chooses "Unchecked"
- **THEN** the list shows the 5 unchecked transactions

### Requirement: Amount filter

The app SHALL filter the list by amount with the "Amount" menu. Its values are "Show All", "Deposits", "Withdrawals", and "Custom...". "Custom..." has the fields "min. amount" and "max. amount" and shows the transactions whose amount with its sign lies in that range. Both ends belong to the range, and an empty field leaves the range open on that side. When "min. amount" is greater than "max. amount", the app does not apply the range and marks "max. amount".

#### Scenario: Deposits only

- **WHEN** the user chooses "Deposits"
- **THEN** the list shows only transactions with an amount above zero

#### Scenario: Range

- **GIVEN** transactions of 150,00 €, -150,00 €, and 500,00 €
- **WHEN** the user chooses "Custom..." and enters 100 in "min. amount" and 500 in "max. amount"
- **THEN** the list shows 150,00 € and 500,00 €
- **AND** the list does not show -150,00 €

#### Scenario: Range of withdrawals

- **GIVEN** transactions of 150,00 € and -150,00 €
- **WHEN** the user chooses "Custom..." and enters -500 in "min. amount" and -100 in "max. amount"
- **THEN** the list shows -150,00 €
- **AND** the list does not show 150,00 €

#### Scenario: Range in an account in yen

- **GIVEN** the account "Yen card" in JPY with transactions of 150 ¥ and 15.000 ¥
- **WHEN** the user chooses "Custom..." and enters 100 in "min. amount" and 500 in "max. amount"
- **THEN** the list shows 150 ¥
- **AND** the list does not show 15.000 ¥

#### Scenario: Only a minimum

- **GIVEN** transactions of 1.000,00 € and -1.500,00 €
- **WHEN** the user enters 1000 in "min. amount" and leaves "max. amount" empty
- **THEN** the list shows 1.000,00 €
- **AND** the list does not show -1.500,00 €

#### Scenario: Minimum above maximum

- **GIVEN** transactions of -150,00 € and -300,00 €
- **WHEN** the user enters -100 in "min. amount" and -500 in "max. amount"
- **THEN** the app does not apply the range and marks "max. amount"
- **AND** the list still shows -150,00 € and -300,00 €

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

The app SHALL filter the list of a category or a category group with the "Account" menu. The menu lists "Show All" and every account and account group in the order of the sidebar, with the entries of a group indented below it. The entry of an account group includes the accounts of its subgroups.

#### Scenario: One account in one category

- **GIVEN** the category view "Groceries"
- **WHEN** the user chooses "Credit card" in the "Account" menu
- **THEN** the list shows the transactions of "Groceries" that belong to "Credit card"

#### Scenario: One account group in one category

- **GIVEN** the group "Private" with the account "Giro" and the subgroup "Cards" with the account "Credit card"
- **AND** the account "Savings" outside "Private"
- **WHEN** the user chooses "Private" in the "Account" menu of the category view "Groceries"
- **THEN** the list shows the transactions of "Groceries" that belong to "Giro" or "Credit card"
- **AND** the menu shows "Private"

### Requirement: Search and filters combine

The app SHALL show a transaction only when it matches the search text and every active filter.

#### Scenario: Search inside a period

- **GIVEN** the period "12 Months" and the status "Unchecked"
- **WHEN** the user searches for "amazon"
- **THEN** the list shows the unchecked transactions of the last 12 months that contain "amazon"

### Requirement: Hint about active filters

The app SHALL show a line below the last row of the list for each active filter, in the order of the filter bar: period, status, amount, category, and account. The line names the kind of filter and says that some entries might be hidden. The search text gets no line, because the search field shows it. A line is text only and does not change a filter. A list without rows shows the lines below the text that says so. The status line shows no hint of its own.

#### Scenario: Date filter

- **GIVEN** the period "30 Days"
- **WHEN** the user scrolls to the end of the list
- **THEN** a line below the last row says "A date filter is active; some entries might be hidden."

#### Scenario: Two filters

- **GIVEN** the period "November 2026" and the category "Groceries" in the account "Giro"
- **WHEN** the user scrolls to the end of the list
- **THEN** the first line below the last row says "A date filter is active; some entries might be hidden."
- **AND** the second line says "A category filter is active; some entries might be hidden."

#### Scenario: Every kind of filter

- **GIVEN** a saved search with "90 Days", "Unchecked", "Withdrawals", "Groceries", and "Giro"
- **WHEN** the user selects it
- **THEN** five lines say that a date filter, a status filter, an amount filter, a category filter, and an account filter are active, in this order

#### Scenario: Search text only

- **GIVEN** every filter shows "Show All"
- **WHEN** the user searches for "amazon"
- **THEN** no line appears below the last row

#### Scenario: No filter

- **WHEN** every filter shows "Show All"
- **THEN** the list ends with its last transaction

### Requirement: Saved searches

The app SHALL let the user save the current search text and filters under a name. A saved search appears in the sidebar section "Searches". Selecting it shows the matching transactions of all accounts with the count and the sum. The user can rename and remove a saved search. The filter bar of a saved search shows "Period", "Status", "Amount", "Category", and "Account", and each menu has the same entries as in an account view and a category view.

#### Scenario: Save and reuse

- **GIVEN** the search text "Finanzamt" and the amount filter "Withdrawals"
- **WHEN** the user saves the search as "Tax payments" and later selects "Tax payments" in the sidebar
- **THEN** the list shows all withdrawals that contain "Finanzamt" from every account

#### Scenario: Filter bar of a saved search

- **GIVEN** the saved search "Tax payments"
- **WHEN** the user selects it and opens the "Category" menu and the "Account" menu
- **THEN** the "Category" menu lists "Show All" and every category including "Uncategorized"
- **AND** the "Account" menu lists "Show All" and every account and account group

#### Scenario: New transactions

- **GIVEN** the saved search "Tax payments"
- **WHEN** a refresh brings a new matching transaction
- **THEN** the saved search shows it the next time the user selects it

#### Scenario: Remove

- **WHEN** the user removes "Tax payments"
- **THEN** the entry leaves the sidebar and no transaction changes

#### Scenario: A removed account group

- **GIVEN** the saved search "Tax payments" with the group "Private" in the "Account" menu
- **WHEN** the user removes the group "Private" and selects "Tax payments"
- **THEN** the "Account" menu shows "Show All"
- **AND** the list shows the matching transactions of every account

### Requirement: The search is fast with a large history

The app SHALL show the results of a search over 50,000 transactions within 100 milliseconds on a Mac with an M1 processor.

#### Scenario: Ten years of history

- **GIVEN** a database with 50,000 transactions
- **WHEN** the user types one more letter in the search field
- **THEN** the list and the sum are up to date within 100 milliseconds
