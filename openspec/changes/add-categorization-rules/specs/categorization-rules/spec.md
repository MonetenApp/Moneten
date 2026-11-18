# Spec Delta

## Purpose

Rules sort transactions into categories without manual work. This capability defines the rule language, when the app runs the rules, and how a changed rule affects transactions that already exist.

## ADDED Requirements

### Requirement: One rule per category

The app SHALL let the user enter one rule for each category in the category settings, in the field "Rules for automatic categorization". A category with an empty rule receives transactions only by manual assignment.

#### Scenario: Enter a rule

- **GIVEN** a category "Groceries" with an empty rule
- **WHEN** the user opens the settings of "Groceries", enters `"REWE" OR "EDEKA"`, and closes the settings
- **THEN** the app stores the rule with the category

#### Scenario: Empty rule

- **GIVEN** a category "Gifts" with an empty rule
- **WHEN** the app fetches new transactions
- **THEN** no transaction enters "Gifts" automatically

### Requirement: A group has no rule

The app SHALL treat a category group as having no rule, even if an earlier migration stored rule text for it. A group shows no rule warning symbol. New transactions and pending transactions assigned by a rule go to the next matching category or to "Uncategorized" when the rules run.

#### Scenario: A migrated group leaves the transaction to its child

- **GIVEN** the group "Living" with the migrated rule `amount<-1000` and its category "Rent" with the rule `"Miete"`
- **WHEN** a new transaction has the purpose "Miete November" and the amount -1.200,00 €
- **THEN** the transaction is in "Rent"
- **AND** "Living" shows no warning symbol

#### Scenario: Booking a transaction previously assigned by a group rule

- **GIVEN** a pending transaction of -1.200,00 € with the purpose "Miete November" that a rule assigned to "Living" in an existing database
- **AND** "Living" has the saved rule `amount<-1000` and its category "Rent" has the rule `"Miete"`
- **WHEN** the bank books the transaction
- **THEN** the transaction moves to "Rent"
- **AND** if no category rule matches, the transaction moves to "Uncategorized"

### Requirement: Terms match text without regard to case and umlauts

The app SHALL compare a term with the text of a transaction without regard to upper and lower case, and it SHALL treat the umlauts ä, ö, ü and the letter ß as equal to ae, oe, ue, and ss.

#### Scenario: Case is ignored

- **GIVEN** the rule `"gehalt"`
- **WHEN** a transaction has the purpose "GEHALT 10/2026"
- **THEN** the rule matches

#### Scenario: Umlauts are folded

- **GIVEN** the rule `"Baeckerei"`
- **WHEN** a transaction has the counterparty "Bäckerei Gutbrot"
- **THEN** the rule matches

### Requirement: A term matches a whole word

The app SHALL match a term only against a whole word of the text. Words are separated by spaces. A hyphen, a slash, and other punctuation stay inside the word. Only the wildcards `*` and `?` match part of a word.

#### Scenario: Word with a hyphen

- **GIVEN** the rule `"REWE"`
- **WHEN** a transaction has the purpose "REWE-Markt" and the amount -12,50 €
- **THEN** the rule does not match

#### Scenario: Whole word

- **GIVEN** the rule `"REWE"`
- **WHEN** a transaction has the purpose "REWE Markt Musterstadt"
- **THEN** the rule matches

#### Scenario: Wildcard for part of a word

- **GIVEN** the rule `"REWE*"`
- **WHEN** a transaction has the purpose "REWE-Markt"
- **THEN** the rule matches

### Requirement: Unqualified terms search all text fields

The app SHALL search an unqualified term in the counterparty name, the purpose, the booking text, the end-to-end reference, the mandate reference, the creditor ID, and the comment. An unqualified term does not search an account number or an IBAN of either side. Only `local_account:` and `remote_account:` search them.

#### Scenario: Term found in the comment

- **GIVEN** the rule `"Steuer"`
- **WHEN** a transaction has the comment "für die Steuer" and no other field contains the word
- **THEN** the rule matches

#### Scenario: IBAN without a field operator

- **GIVEN** the rule `"DE02120300000000202051"`
- **WHEN** a transaction has the counterparty "Stadtwerke", the purpose "Abschlag", the amount -89,00 €, and the counterparty IBAN DE02120300000000202051
- **THEN** the rule does not match

### Requirement: Phrases match words in order

The app SHALL treat several words inside one pair of quotation marks as a phrase. A phrase matches only when the words occur next to each other in the given order.

#### Scenario: Phrase in order

- **GIVEN** the rule `"Bahn AG"`
- **WHEN** a transaction has the counterparty "Deutsche Bahn AG"
- **THEN** the rule matches

#### Scenario: Words in another order

- **GIVEN** the rule `"Bahn AG"`
- **WHEN** a transaction has the purpose "AG Fahrkarte Bahn"
- **THEN** the rule does not match

### Requirement: Wildcards

The app SHALL support the wildcard `*` for any number of characters and the wildcard `?` for exactly one character inside a term.

#### Scenario: Word beginning

- **GIVEN** the rule `"Blumen*"`
- **WHEN** one transaction has the purpose "Blumenerde" and another has the purpose "Blumentopf"
- **THEN** the rule matches both

#### Scenario: Word followed by punctuation

- **GIVEN** the rule `"Kundennummer 67890*"`
- **WHEN** a transaction has the purpose "Kundennummer 67890/Rechnung 12345"
- **THEN** the rule matches

### Requirement: Logical operators

The app SHALL combine expressions with the operators `AND`, `OR`, and `NOT` in any letter case, and it SHALL group expressions with parentheses. `AND` binds more strongly than `OR`. A word in quotation marks is always a term. Two expressions with no operator between them are combined with `AND`.

#### Scenario: Either word

- **GIVEN** the rule `"Lohn" OR "Gehalt"`
- **WHEN** a transaction has the purpose "Gehalt Oktober"
- **THEN** the rule matches

#### Scenario: Negation

- **GIVEN** the rule `"EC-Karte" AND (NOT "Barauszahlung")`
- **WHEN** a transaction has the purpose "EC-Karte Barauszahlung"
- **THEN** the rule does not match

#### Scenario: Grouping

- **GIVEN** the rule `"Bücher" OR "eBooks" OR ("Waren" AND "Versand")`
- **WHEN** a transaction has the purpose "Waren und Versand"
- **THEN** the rule matches

#### Scenario: Lower case operator

- **GIVEN** the rule `"Lohn" or "Gehalt"`
- **WHEN** a transaction has the purpose "Gehalt Oktober" and the amount 2.500,00 €
- **THEN** the rule matches

#### Scenario: Mixed case operator

- **GIVEN** the rule `"EC-Karte" And Not "Barauszahlung"`
- **WHEN** one transaction has the purpose "EC-Karte Supermarkt" and another has the purpose "EC-Karte Barauszahlung"
- **THEN** the rule matches the first and not the second

#### Scenario: Operator word in quotation marks

- **GIVEN** the rule `"Lohn" "or" "Gehalt"`
- **WHEN** one transaction has the purpose "Lohn or Gehalt" and another has the purpose "Gehalt Oktober"
- **THEN** the rule matches the first and not the second, because a quoted "or" is a term

### Requirement: Short forms of the operators

The app SHALL read a plus sign between two expressions as `AND`, and an exclamation mark or a minus sign before an expression as `NOT`. A plus sign or a minus sign before a digit belongs to the number. A plus sign or an exclamation mark directly after a letter or a digit is part of the word, as in Disney+. The field operator `!=` after a field name is the exception, as in `name!="Stadtwerke"` and `amount!=0`.

#### Scenario: Short forms

- **GIVEN** the rule `"Netflix" + !"Gutschrift"`
- **WHEN** one transaction has the purpose "Netflix Abo" and another has the purpose "Netflix Gutschrift"
- **THEN** the rule matches the first and not the second

#### Scenario: Minus before a term

- **GIVEN** the rule `"Amazon" -"Erstattung"`
- **WHEN** one transaction has the purpose "Amazon Bestellung" and the amount -19,99 €, and another has the purpose "Amazon Erstattung" and the amount 19,99 €
- **THEN** the rule matches the first and not the second

#### Scenario: Minus at the end of a word

- **GIVEN** the rule `Amazon-"Erstattung"`
- **WHEN** one transaction has the purpose "Amazon Bestellung" and the amount -19,99 €, and another has the purpose "Amazon Erstattung" and the amount 19,99 €
- **THEN** the rule matches the first and not the second, because a minus before a quotation mark is `NOT` and not part of the word Amazon

#### Scenario: Minus before a number

- **GIVEN** the rule `-12,50`
- **WHEN** one transaction has the purpose "Rückbuchung -12,50" and another has the purpose "Miete November"
- **THEN** the rule matches the first and not the second, because `-12,50` is a term and not `NOT` before 12,50

#### Scenario: Plus before a number

- **GIVEN** the rule `"Tel" +4917012345`
- **WHEN** one transaction has the purpose "Tel +4917012345" and another has the purpose "Tel 4917012345"
- **THEN** the rule matches the first and not the second, because `+4917012345` is a term and not `AND` before 4917012345

#### Scenario: Plus sign inside a word

- **GIVEN** the rule `Disney+`
- **WHEN** one transaction has the purpose "Disney+ Abo" and the amount -9,99 €, and another has the purpose "Disney Store" and the amount -24,00 €
- **THEN** the rule matches the first and not the second, because `Disney+` is one word and not `Disney` followed by `AND`

#### Scenario: Exclamation mark at the end of a word

- **GIVEN** the rule `Yahoo! OR "Spotify"`
- **WHEN** one transaction has the purpose "Yahoo! Mail Pro" and another has the purpose "Yahoo Finanzen"
- **THEN** the rule matches the first and not the second, because `Yahoo!` is one word

#### Scenario: Not equal after a field name

- **GIVEN** the rule `"Abschlag" AND name!="Stadtwerke"`
- **WHEN** one transaction from "Gasversorger Muster" and one from "Stadtwerke" both have the purpose "Abschlag"
- **THEN** the rule matches the transaction from "Gasversorger Muster" and not the one from "Stadtwerke", because `name!=` is the field operator and not the word `name!`

### Requirement: The rules true and false

The app SHALL read the words `true` and `false` in any letter case and without quotation marks as rules of their own. `true` matches every transaction, and `false` matches none. A quoted `"true"` or `"false"` is a term.

#### Scenario: Catch-all category

- **GIVEN** the category "Business", restricted to the account "Business", with the rule `true`
- **WHEN** a new transaction of -42,00 € arrives in the account "Business" and no category above "Business" matches
- **THEN** the transaction is in "Business"

#### Scenario: Rule that matches nothing

- **GIVEN** the rule `FALSE`
- **WHEN** a transaction has the purpose "False Angabe korrigiert"
- **THEN** the rule does not match

#### Scenario: Quoted true is a word

- **GIVEN** the rule `"true"`
- **WHEN** one transaction has the purpose "true fruits Smoothie" and another has the purpose "Miete November"
- **THEN** the rule matches the first and not the second

### Requirement: Field operators

The app SHALL restrict a term or a regular expression to one field when it follows a field operator with no space between them. The fields are `name`, `purpose`, `local_account`, `remote_account`, `currency`, `reference`, `mandate`, `creditor_id`, `comment`, and `booking_text`. After the field, `:`, `=`, `==`, and `:=` test that the field matches, and `!=` and `<>` test that it does not. A field name counts in any letter case. A word right after a field operator is always a term.

#### Scenario: Name only

- **GIVEN** the rule `name:"Bahn AG"`
- **WHEN** a transaction has the counterparty "Stadtwerke" and the purpose "Bahn AG Ticket"
- **THEN** the rule does not match

#### Scenario: Combined fields

- **GIVEN** the rule `name:"Bahn AG" AND remote_account:"DE02120300000000202051" AND NOT purpose:"Abrechnung"`
- **WHEN** a transaction has the counterparty "Deutsche Bahn AG", the counterparty IBAN DE02120300000000202051, and the purpose "Fahrkarte"
- **THEN** the rule matches

#### Scenario: Own account

- **GIVEN** the rule `local_account:"DE02120300000000202051"`
- **WHEN** a transaction belongs to the account with that IBAN
- **THEN** the rule matches

#### Scenario: Field does not match

- **GIVEN** the rule `"Abschlag" AND name<>"Stadtwerke"`
- **WHEN** one transaction from "Stadtwerke" and one from "Gasversorger Muster" both have the purpose "Abschlag"
- **THEN** the rule matches the transaction from "Gasversorger Muster" and not the one from "Stadtwerke"

#### Scenario: Equality forms

- **GIVEN** the rules `currency:EUR`, `currency=EUR`, `currency==EUR`, and `currency:=EUR`
- **WHEN** a transaction has the amount -1,50 €
- **THEN** each of the four rules matches

#### Scenario: Field name in capitals

- **GIVEN** the rule `Name:"Bahn AG"`
- **WHEN** one transaction has the counterparty "Deutsche Bahn AG", and another has the counterparty "Stadtwerke" and the purpose "Bahn AG Ticket"
- **THEN** the rule matches the first and not the second, because `Name:` is the field operator `name:`

#### Scenario: Operator word after a field operator

- **GIVEN** the rule `name:and`
- **WHEN** one transaction has the counterparty "Muster and Partner" and another has the counterparty "Muster Partner"
- **THEN** the rule matches the first and not the second, because `and` after `name:` is a term and not the operator `AND`

### Requirement: Amount comparisons

The app SHALL compare the amount of a transaction with a value through `amount=`, `amount==`, `amount:=`, `amount!=`, `amount<>`, `amount<`, `amount>`, `amount<=`, and `amount>=`. The value uses a decimal comma or a decimal point. A withdrawal has a negative amount.

#### Scenario: All deposits

- **GIVEN** the rule `amount>0,00`
- **WHEN** a transaction has the amount 1.250,00 €
- **THEN** the rule matches

#### Scenario: Exact amount with a name

- **GIVEN** the rule `name:"Stadtwerke" AND amount=-89,00`
- **WHEN** a transaction from "Stadtwerke Musterstadt" has the amount -89,00 €
- **THEN** the rule matches

#### Scenario: Not equal

- **GIVEN** the rule `amount<>0`
- **WHEN** one transaction has the amount -1,50 € and another has the amount 0,00 €
- **THEN** the rule matches the first and not the second

### Requirement: Regular expressions

The app SHALL treat text between two slashes as a regular expression and match it against the text of the transaction.

#### Scenario: Pattern with digits

- **GIVEN** the rule `/GA NR[0-9]{8}/`
- **WHEN** a transaction has the purpose "GA NR00012345 BLZ12030000"
- **THEN** the rule matches

### Requirement: A regular expression in a rule that does not end

The app SHALL stop a rule when one of its regular expressions takes about 100 ms of processor time on one text, when its calls that took 1 ms or more each add up to 50 ms, or when its regular expressions take 1 second of processor time in all within one run. A run is the categorization of one account's refresh or one account's import, of one entry, or of one migration, one application of a rule to existing transactions, or one count of matches in the category settings.

#### Scenario: Refresh with a rule that does not end

- **GIVEN** the category "Phone" above "Other" in the sidebar, "Phone" with the rule `/^+?49/`, and "Other" with the rule `"Telefon"`
- **WHEN** a refresh brings 1,000 transactions with the purpose "Telefon +49 170 1234567"
- **THEN** the refresh ends within a few seconds
- **AND** no transaction is in "Phone", and all 1,000 are in "Other"

#### Scenario: Many texts that are each just under the limit

- **GIVEN** the category "Phone" with the rule `purpose:/(a+)+$/`
- **WHEN** the rule tests 200 transactions whose purpose is 18 times "a" and then "!"
- **THEN** the rule stops after about 50 ms of processor time and matches none of them

### Requirement: A slow call of a regular expression counts only when it is slow again

The app SHALL run a regular expression of a rule once more on the same text when a call takes 1 ms or more or stops at the limit of one call, unless the call reached the limit of the run, and SHALL stop the second call at 1 ms. When the second call takes less than 1 ms, only the second call counts toward the limits of the rule. Otherwise both calls count. The host of a virtual machine can pause the Mac during a fast call, and the Mac counts the pause as processor time of that call.

#### Scenario: A pause of the host during a fast call

- **GIVEN** the category "Traders" with the rule `/Haendler1x/`
- **WHEN** a migration tests the name "Haendler1 Musterstadt", the host of the virtual machine pauses the Mac for 60 ms during that call, and the second call on the name takes 5 µs
- **THEN** only the second call counts, and the rule does not stop

#### Scenario: A pattern that backtracks

- **GIVEN** the category "Phone" with the rule `purpose:/(a+)+$/`
- **WHEN** a call on a purpose of 18 times "a" and then "!" takes 3 ms, and the second call stops after 1.1 ms
- **THEN** both calls count, 4.1 ms in all

### Requirement: The rules of one run stop together after 3 seconds

The app SHALL stop every rule with a regular expression when the slow calls of the regular expressions of all rules of one categorization run take 3 seconds of processor time together. A slow call is one that takes 0.1 ms or more on one text. A rule that does not stop runs its regular expressions on each text of the run once, apart from the second call of a slow call, also when the run repeats after another rule stopped.

#### Scenario: Many slow rules above a normal one

- **GIVEN** twelve categories whose rules stop, above "Traders" with the rule `/Haendler1/`
- **WHEN** a migration categorizes 50,000 transactions, of which 7,865 have a name that starts with "Haendler1"
- **THEN** the 7,865 transactions are in "Traders", and the categorization ends within a few seconds

#### Scenario: Many fast rules over a long history

- **GIVEN** 30 categories with the rules `/Haendler0x/` to `/Haendler29x/`
- **WHEN** a migration categorizes 50,000 transactions with a name, a purpose, a booking text, and a reference each
- **THEN** no rule stops, also when the regular expressions of the 30 rules take more than 3 seconds together

### Requirement: A stopped rule matches nothing in its run

The app SHALL treat a stopped rule as matching no transaction of its run, also none that it tested before the stop, and SHALL still run the rules of the other categories.

#### Scenario: The order of the rows does not matter

- **GIVEN** the category "Phone" above "Other", "Phone" with the rule `purpose:/ok|(a+)+$/`, and "Other" with the rule `true`
- **WHEN** a refresh brings one transaction with the purpose "ok" and one whose purpose is 32 times "a" and then "!", in either order
- **THEN** both transactions are in "Other"

### Requirement: A stopped rule never moves a transaction that a rule sorted

The app SHALL keep the category of a transaction that a rule assigned when a stopped rule stands above every rule that matches it, because the stopped rule could have matched it first.

#### Scenario: A pending transaction is booked during the stop

- **GIVEN** the category "Phone" above "Other", "Phone" with the rule `purpose:/ok|(a+)+$/`, "Other" with the rule `true`, and a pending transaction with the purpose "ok" that the rule put into "Phone"
- **WHEN** a refresh books it and brings a transaction whose purpose is 32 times "a" and then "!"
- **THEN** the booked transaction stays in "Phone"
- **AND** the new transaction is in "Other"

### Requirement: A stopped rule is shown

The app SHALL show "The regular expression at position N stopped because it is too slow." for a rule whose regular expression stopped, with N as the position of the regular expression in the rule, counted from 1. The category settings show it in place of the number of matches. An application of the stopped rule to existing transactions changes no transaction and shows it as well.

#### Scenario: Category settings

- **WHEN** the user enters the rule `name:"Telekom" OR /^+?49/` in the settings of "Phone"
- **THEN** the settings show "The regular expression at position 19 stopped because it is too slow." in place of the number of matches

#### Scenario: Apply to all transactions

- **GIVEN** the category "Phone" contains 2 transactions
- **WHEN** the user sets the rule of "Phone" to `/^+?49/` and chooses "Apply to all transactions."
- **THEN** both transactions stay in "Phone"
- **AND** the app shows "The regular expression at position 1 stopped because it is too slow."

### Requirement: Invalid rules are rejected

The app SHALL refuse to store a rule that it cannot parse. It shows a message that names the position of the error and keeps the settings open with the text that the user entered.

#### Scenario: Missing parenthesis

- **WHEN** the user enters `("Lohn" OR "Gehalt"` and closes the settings
- **THEN** the app shows that a closing parenthesis is missing at the end of the rule
- **AND** the app does not change the stored rule

#### Scenario: Sign after a field operator

- **WHEN** the user enters `name:-"Stadtwerke"` or the regular expression `name:-/Stadtwerke/` and closes the settings
- **THEN** the app shows at position 6 that a sign cannot follow `name:`, and that `name!="…"` excludes a value
- **AND** the app does not change the stored rule

### Requirement: A saved rule that cannot be read is marked

The app SHALL mark a category in the sidebar when it cannot parse the saved rule of the category, because such a category gets no new transactions. The mark is a warning symbol with a tooltip that names the error. The mark goes away when the user saves a rule that the app can parse.

#### Scenario: Ambiguous amount in a saved rule

- **GIVEN** the category "Rent" with the saved rule `amount<-1,000`
- **WHEN** the sidebar shows "Rent"
- **THEN** the row of "Rent" shows a warning symbol
- **AND** its tooltip says that the amount -1,000 is not a number

#### Scenario: Fixed rule

- **GIVEN** the category "Rent" with the mark
- **WHEN** the user saves the rule `amount<-1000`
- **THEN** the row of "Rent" shows no warning symbol

### Requirement: Rules run on new transactions

The app SHALL apply the rules to every transaction that enters the database without a category. That includes transactions from a refresh, from a file import, from manual entry, and from automation.

#### Scenario: Refresh

- **GIVEN** the category "Salary" with the rule `"Gehalt"`
- **WHEN** a refresh brings a new transaction with the purpose "Gehalt 10/2026"
- **THEN** the transaction is in "Salary" when it first appears in the list

#### Scenario: No rule matches

- **WHEN** a refresh brings a new transaction that no rule matches
- **THEN** the transaction is in "Uncategorized"

### Requirement: The first matching category wins

The app SHALL assign a transaction to the first category whose rule matches, in the order of the categories in the sidebar from top to bottom.

#### Scenario: Two rules match

- **GIVEN** "Insurance" stands above "Car" in the sidebar, "Insurance" has the rule `"Versicherung"`, and "Car" has the rule `"KFZ"`
- **WHEN** a new transaction has the purpose "KFZ Versicherung 2026"
- **THEN** the transaction is in "Insurance"

### Requirement: Rules respect the account restriction of a category

The app SHALL apply the rule of a category only to transactions of the account or account group that the category is restricted to under "Restrict to".

#### Scenario: Transaction of another account

- **GIVEN** the category "Office" with the rule `"Miete"`, restricted to the account "Business"
- **WHEN** a new transaction with the purpose "Miete" arrives in the account "Private"
- **THEN** the transaction does not enter "Office"

### Requirement: Rules run again when a pending transaction is booked

The app SHALL apply the rules again when the bank books a transaction that was pending, unless the user assigned its category by hand.

#### Scenario: Purpose completed at booking

- **GIVEN** a pending transaction with the purpose "KARTENZAHLUNG" in "Uncategorized", and the category "Groceries" with the rule `"REWE"`
- **WHEN** the bank books the transaction with the purpose "KARTENZAHLUNG REWE SAGT DANKE"
- **THEN** the transaction moves to "Groceries"

#### Scenario: Manual assignment is kept

- **GIVEN** a pending transaction that the user assigned to "Gifts"
- **WHEN** the bank books the transaction and a rule of "Groceries" matches it
- **THEN** the transaction stays in "Gifts"

### Requirement: Ask how to apply a changed rule

The app SHALL ask "Should this categorization rule be applied to the existing transactions now?" when the user changes a rule. The user chooses between "Apply only to not yet categorized transactions." and "Apply to all transactions.", or declines.

#### Scenario: Only uncategorized transactions

- **GIVEN** 3 transactions with "Netflix" in the purpose, 2 in "Uncategorized" and 1 in "Leisure"
- **WHEN** the user sets the rule of "Streaming" to `"Netflix"` and chooses "Apply only to not yet categorized transactions."
- **THEN** "Streaming" contains the 2 transactions from "Uncategorized"
- **AND** the third transaction stays in "Leisure"

#### Scenario: Decline

- **WHEN** the user changes a rule and declines to apply it
- **THEN** no existing transaction changes its category
- **AND** the rule applies to new transactions from then on

### Requirement: Applying a rule to all transactions replaces earlier assignments

The app SHALL, for "Apply to all transactions.", move every matching transaction into the category, including transactions that the user assigned by hand, and move every transaction of the category that no longer matches to "Uncategorized". The dialog states both effects before the user confirms.

#### Scenario: Manual assignment is replaced

- **GIVEN** a transaction with "Netflix" in the purpose that the user assigned to "Leisure"
- **WHEN** the user sets the rule of "Streaming" to `"Netflix"` and chooses "Apply to all transactions."
- **THEN** the transaction is in "Streaming"

#### Scenario: Transaction no longer matches

- **GIVEN** the category "Streaming" contains a transaction with the purpose "Spotify"
- **WHEN** the user changes the rule of "Streaming" from `"Netflix" OR "Spotify"` to `"Netflix"` and chooses "Apply to all transactions."
- **THEN** the "Spotify" transaction is in "Uncategorized"

### Requirement: Progress while a rule is applied

The app SHALL show progress while it applies a rule to existing transactions, with the number of the current transaction and the total, and it SHALL keep the list usable after the run with all changes visible.

#### Scenario: Large database

- **GIVEN** a database with 20,000 transactions
- **WHEN** the user applies a changed rule to all transactions
- **THEN** the app shows a line such as "Applying rule to transaction 5,000 of 20,000..."
- **AND** the category list and the sums in the sidebar are correct when the run ends

### Requirement: Help for the rule language

The app SHALL offer a help button next to the rule field that opens a description of the rule language with one example for each operator.

#### Scenario: Open help

- **WHEN** the user clicks the help button in the category settings
- **THEN** the app shows the description of the rule language

### Requirement: Create a rule from a transaction

The app SHALL offer "Create Rule" in the context menu of one selected transaction that has a counterparty name with a character other than `*`, `?`, and quotation marks, or a counterparty IBAN.

#### Scenario: One transaction with a counterparty

- **GIVEN** a transaction from the counterparty "Stadtwerke Musterstadt"
- **WHEN** the user opens its context menu
- **THEN** the menu has "Create Rule"

#### Scenario: No counterparty

- **GIVEN** a transaction without a counterparty name and without a counterparty IBAN
- **WHEN** the user opens its context menu
- **THEN** the menu has no "Create Rule"

#### Scenario: Several transactions

- **GIVEN** two selected transactions from the counterparty "Stadtwerke Musterstadt"
- **WHEN** the user opens the context menu of the selection
- **THEN** the menu has no "Create Rule"

### Requirement: The categories of a created rule

The app SHALL list in "Create Rule" every category that can have a rule, and SHALL disable a category that cannot take the transaction.

#### Scenario: Groups and Uncategorized

- **GIVEN** the group "Living" with the category "Energy"
- **WHEN** the user opens "Create Rule" for a transaction
- **THEN** the list has "Energy"
- **AND** it has neither the group "Living" nor "Uncategorized"

#### Scenario: Restricted category

- **GIVEN** the category "Car" restricted to the account "Savings"
- **WHEN** the user opens "Create Rule" for a transaction of the account "Giro"
- **THEN** the list has "Car", and "Car" is disabled

### Requirement: The settings of a created rule

The app SHALL open the settings of the chosen category with the condition for the counterparty added to its rule, and the settings SHALL show how many transactions the new rule matches.

#### Scenario: Category without a rule

- **GIVEN** the category "Energy" without a rule, and 3 transactions from the counterparty "Stadtwerke Musterstadt"
- **WHEN** the user chooses "Create Rule" and then "Energy" in the context menu of one of these transactions
- **THEN** the settings of "Energy" open with the rule `name:"Stadtwerke Musterstadt"`
- **AND** they show "The rule matches 3 transactions."

### Requirement: Confirm a created rule

The app SHALL change no rule and no transaction until the user confirms the settings of a created rule.

#### Scenario: OK

- **GIVEN** the settings of "Energy" with the created rule `"Abschlag" OR name:"Stadtwerke Musterstadt"`
- **WHEN** the user clicks OK
- **THEN** "Energy" has the new rule
- **AND** the app asks how to apply it to the existing transactions
- **AND** no transaction changes its category until the user chooses how to apply the rule

#### Scenario: Cancel

- **GIVEN** the settings of "Energy" with the created rule `"Abschlag" OR name:"Stadtwerke Musterstadt"`
- **WHEN** the user clicks Cancel
- **THEN** "Energy" keeps the rule `"Abschlag"`
- **AND** no transaction changes its category

### Requirement: The condition of a created rule

The app SHALL build the condition of "Create Rule" as `name:` with the counterparty name in quotation marks, or as `remote_account:` with the IBAN without spaces when the transaction has no name or a name made only of the wildcards `*` and `?` after each quotation mark became `?`. A quotation mark in the name becomes the wildcard `?`. The condition joins an existing rule with `OR`.

#### Scenario: Category with a rule

- **GIVEN** the category "Energy" with the rule `"Abschlag"`
- **WHEN** the user creates a rule for "Energy" from a transaction of "Stadtwerke Musterstadt"
- **THEN** the settings show the rule `"Abschlag" OR name:"Stadtwerke Musterstadt"`

#### Scenario: Transaction without a name

- **GIVEN** a transaction without a counterparty name and with the counterparty IBAN "DE02 1203 0000 0000 2020 51"
- **WHEN** the user creates a rule for "Energy" from it
- **THEN** the settings show the rule `remote_account:"DE02120300000000202051"`

#### Scenario: Quotation marks in the name

- **GIVEN** a transaction from the counterparty `Café "Zur Linde"`
- **WHEN** the user creates a rule for "Restaurants" from it
- **THEN** the settings show the rule `name:"Café ?Zur Linde?"`
- **AND** the rule matches the transaction

#### Scenario: Operator words in the name

- **GIVEN** a transaction from the counterparty "Müller OR Söhne"
- **WHEN** the user creates a rule for "Craftsmen" from it
- **THEN** the rule `name:"Müller OR Söhne"` matches the transaction and not a transaction from "Müller"

#### Scenario: Wildcard characters in the name

- **GIVEN** a card payment from the counterparty "AMAZON* MKTP DE"
- **WHEN** the user creates a rule for "Shopping" from it
- **THEN** the settings show the rule `name:"AMAZON* MKTP DE"`
- **AND** the rule matches the transaction

#### Scenario: Name made only of wildcards

- **GIVEN** a transaction from the counterparty "* ?" with the counterparty IBAN "DE02 1203 0000 0000 2020 51"
- **WHEN** the user creates a rule for "Energy" from it
- **THEN** the settings show the rule `remote_account:"DE02120300000000202051"`

#### Scenario: Name made only of wildcards and no IBAN

- **GIVEN** a transaction from the counterparty "*" without a counterparty IBAN
- **WHEN** the user opens its context menu
- **THEN** the menu has no "Create Rule"

#### Scenario: Rule syntax in the name

- **GIVEN** a transaction from the counterparty `Acme" OR name:"*`
- **WHEN** the user creates a rule for "Shopping" from it
- **THEN** the settings show the rule `name:"Acme? OR name:?*"`
- **AND** the rule matches the transaction and not a transaction from "Stadtwerke Musterstadt"

#### Scenario: Rule with parentheses and NOT

- **GIVEN** the category "Streaming" with the rule `("Netflix" OR "Spotify") AND NOT purpose:"Erstattung"`
- **WHEN** the user creates a rule for "Streaming" from a transaction of "Stadtwerke Musterstadt" with the purpose "Erstattung"
- **THEN** the settings show the rule `("Netflix" OR "Spotify") AND NOT purpose:"Erstattung" OR name:"Stadtwerke Musterstadt"`
- **AND** the rule matches that transaction and a transaction with the purpose "Spotify Abo", and not one with the purpose "Spotify Erstattung"

#### Scenario: Saved rule that does not read

- **GIVEN** the category "Energy" with the saved rule `name:`, which does not read
- **WHEN** the user creates a rule for "Energy" from a transaction of "Stadtwerke Musterstadt"
- **THEN** the settings show the rule `name: OR name:"Stadtwerke Musterstadt"` with its error
- **AND** OK is disabled
