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

The app SHALL read a plus sign between two expressions as `AND`, and an exclamation mark or a minus sign before an expression as `NOT`. A minus sign before a digit belongs to the number. A plus sign or an exclamation mark directly after a letter or a digit is part of the word, as in Disney+. The field operator `!=` after a field name is the exception, as in `name!="Stadtwerke"` and `amount!=0`.

#### Scenario: Short forms

- **GIVEN** the rule `"Netflix" + !"Gutschrift"`
- **WHEN** one transaction has the purpose "Netflix Abo" and another has the purpose "Netflix Gutschrift"
- **THEN** the rule matches the first and not the second

#### Scenario: Minus before a term

- **GIVEN** the rule `"Amazon" -"Erstattung"`
- **WHEN** one transaction has the purpose "Amazon Bestellung" and the amount -19,99 €, and another has the purpose "Amazon Erstattung" and the amount 19,99 €
- **THEN** the rule matches the first and not the second

#### Scenario: Minus before a number

- **GIVEN** the rule `-12,50`
- **WHEN** one transaction has the purpose "Rückbuchung -12,50" and another has the purpose "Miete November"
- **THEN** the rule matches the first and not the second, because `-12,50` is a term and not `NOT` before 12,50

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

The app SHALL restrict a term or a regular expression to one field when it follows a field operator with no space between them. The fields are `name`, `purpose`, `local_account`, `remote_account`, `currency`, `reference`, `mandate`, `creditor_id`, `comment`, and `booking_text`. After the field, `:`, `=`, `==`, and `:=` test that the field matches, and `!=` and `<>` test that it does not.

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

### Requirement: Invalid rules are rejected

The app SHALL refuse to store a rule that it cannot parse. It shows a message that names the position of the error and keeps the settings open with the text that the user entered.

#### Scenario: Missing parenthesis

- **WHEN** the user enters `("Lohn" OR "Gehalt"` and closes the settings
- **THEN** the app shows that a closing parenthesis is missing at the end of the rule
- **AND** the app does not change the stored rule

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
