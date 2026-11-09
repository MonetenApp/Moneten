# Spec Delta

## Purpose

A securities account holds positions, not transactions. This capability defines how the app fetches the positions of a portfolio, how it shows and values them, and how the value of a portfolio enters sums and charts.

## ADDED Requirements

### Requirement: Portfolio accounts show positions

The app SHALL show a list of positions for an account of the type "Portfolio" in place of a transaction list. The list has one row for each position that the account holds at the last refresh.

#### Scenario: Open a portfolio

- **GIVEN** the portfolio "Depot" holds 3 positions
- **WHEN** the user selects "Depot" in the sidebar
- **THEN** the content view shows 3 rows, one for each position
- **AND** the view shows no transaction list

#### Scenario: Group of portfolios

- **GIVEN** the account group "Investments" contains two portfolios with 3 and 5 positions
- **WHEN** the user selects "Investments"
- **THEN** the content view shows 8 rows

### Requirement: Fetch positions through FinTS

The app SHALL fetch the positions of a portfolio account through FinTS during a refresh when the bank offers securities holdings for that account. The fetch runs in the same bank session as the other accounts of the login.

#### Scenario: Refresh a portfolio

- **GIVEN** a FinTS login with a current account and a portfolio
- **WHEN** the user refreshes all accounts
- **THEN** the app fetches the transactions of the current account and the positions of the portfolio with one login
- **AND** the portfolio shows the positions that the bank reports

#### Scenario: Bank does not offer holdings

- **GIVEN** the bank lists a portfolio account and does not offer securities holdings through FinTS
- **WHEN** the user refreshes the portfolio
- **THEN** the account shows an error that says the bank does not provide the portfolio through FinTS
- **AND** the other accounts of the login refresh as usual

### Requirement: Take positions from extensions

The app SHALL show the securities that a web banking extension returns for a portfolio account in the same list and with the same fields as positions from FinTS. This includes crypto and other assets.

#### Scenario: Crypto exchange extension

- **GIVEN** an extension returns an account marked as portfolio with the security "Bitcoin", quantity 0.5, price 60000, and amount 30000
- **WHEN** the refresh ends
- **THEN** the portfolio shows the row "Bitcoin" with the quantity 0,5, the last quote 60.000,00 €, and the value 30.000,00 €

### Requirement: Position row content

The app SHALL show for each position the name of the security, the value in the account currency, the quantity, the purchase price, the last quote, and the profit or loss as an amount and as a percentage.

#### Scenario: Row of a share

- **GIVEN** a position of 40 units of "Musterwerke AG" with the last quote 25,00 €, the value 1.000,00 €, and the purchase price 20,00 €
- **WHEN** the user opens the portfolio
- **THEN** the row shows "Musterwerke AG", the value 1.000,00 €, "40 shares", the purchase price 20,00 €, the last quote 25,00 €, and "Profit" with 200,00 € and 25,00 %

### Requirement: Position details

The app SHALL show the details of a position on demand. The details are the ISIN, the security number, the market, the date and time of the last quote under "Trade date", the currency of the quote, the market value, the purchase price, and the purchase date when it is known.

#### Scenario: Open details

- **GIVEN** a position with the ISIN DE0001234567, the security number 123456, the market "Xetra", and a quote from 6 November 2026 at 17:35
- **WHEN** the user opens the details of the position
- **THEN** the details show the ISIN DE0001234567, the security number 123456, "Market" with "Xetra", and "Trade date" with 06.11.2026 17:35

#### Scenario: Missing fields

- **GIVEN** an extension returns a position with a name and a value and no ISIN
- **WHEN** the user opens the details of the position
- **THEN** the details leave the ISIN empty and show no error

### Requirement: Quantities as units or as a nominal amount

The app SHALL show a quantity as a number of units with all decimal places that the source delivers, or as a nominal amount with its currency when the source marks the quantity as nominal.

#### Scenario: Fractional units

- **GIVEN** a fund position with the quantity 12.3456
- **WHEN** the user opens the portfolio
- **THEN** the row shows "12,3456 shares"

#### Scenario: One unit

- **GIVEN** a position with the quantity 1
- **WHEN** the user opens the portfolio
- **THEN** the row shows "1 share"

#### Scenario: Bond with a nominal amount

- **GIVEN** a bond position with the nominal amount 5000 in EUR and the quote 98,50 %
- **WHEN** the user opens the portfolio
- **THEN** the row shows the quantity 5.000,00 € and the last quote 98,50 %

### Requirement: Quotes keep their decimal places

The app SHALL show a quote with all decimal places that the source delivers, and it SHALL round a valuation to the currency only once, at the end of the computation.

#### Scenario: Quote with four decimals

- **GIVEN** a position of 1000 units with the last quote 12,3456 €
- **WHEN** the app values the position without a value from the bank
- **THEN** the last quote reads 12,3456 €
- **AND** the value reads 12.345,60 €

### Requirement: Value of a position

The app SHALL use the value in the account currency that the source delivers for a position. When the source delivers no value, the app computes it from the quantity and the last quote.

#### Scenario: Bank delivers the value

- **GIVEN** the bank reports a position with 10 units, the quote 99,99 €, and the value 1.000,00 €
- **WHEN** the user opens the portfolio
- **THEN** the value reads 1.000,00 €

#### Scenario: Source delivers no value

- **GIVEN** an extension returns a position with 10 units and the price 99,99 and no amount
- **WHEN** the user opens the portfolio
- **THEN** the value reads 999,90 €

### Requirement: Foreign currency positions

The app SHALL convert a quote or a purchase price in a foreign currency to the account currency with the exchange rate that the source delivers. Without an exchange rate and without a value in the account currency, the app shows the value in the foreign currency.

#### Scenario: Quote in US dollars with a rate

- **GIVEN** a position of 10 units with the quote 110,00 USD, the exchange rate 1,10 USD for one euro, and the account currency EUR
- **WHEN** the user opens the portfolio
- **THEN** the last quote reads 110,00 USD
- **AND** the value reads 1.000,00 €

#### Scenario: No rate

- **GIVEN** a position of 10 units with the quote 110,00 USD, no exchange rate, and no value in euro
- **WHEN** the user opens the portfolio
- **THEN** the value reads 1.100,00 USD

### Requirement: Profit or loss

The app SHALL compute the profit or loss of a position as its value minus its purchase value, and the percentage as the profit or loss divided by the purchase value. A gain carries the label "Profit" and a deficit the label "Loss". A position without a purchase price shows no profit or loss.

#### Scenario: Loss

- **GIVEN** a position with the value 800,00 € and the purchase value 1.000,00 €
- **WHEN** the user opens the portfolio
- **THEN** the row shows "Loss" with -200,00 € and -20,00 %

#### Scenario: No purchase price

- **GIVEN** a position for which neither the bank nor the user gave a purchase price
- **WHEN** the user opens the portfolio
- **THEN** the row shows the value and the last quote
- **AND** the fields for the purchase price and the profit or loss are empty

### Requirement: Enter and edit the purchase price

The app SHALL let the user enter the purchase price of a position with "Add Purchase Price..." and change it with "Edit Purchase Price...". The user enters either the price for one unit under "Purchase price" or the total under "Purchase amount", and optionally a "Purchase date". For a nominal quantity the commands read "Add Purchase Rate..." and "Edit Purchase Rate...".

#### Scenario: Enter a price per unit

- **GIVEN** a position of 40 units with the value 1.000,00 € and no purchase price
- **WHEN** the user chooses "Add Purchase Price...", enters 20,00 under "Purchase price", and confirms
- **THEN** the row shows the purchase price 20,00 € and "Profit" with 200,00 € and 25,00 %

#### Scenario: Enter a total amount

- **GIVEN** a position of 40 units with no purchase price
- **WHEN** the user chooses "Add Purchase Price...", enters 800,00 under "Purchase amount", and confirms
- **THEN** the row shows the purchase price 20,00 €

#### Scenario: Correct a converted price

- **GIVEN** the bank reports a purchase price of 100,00 USD that the app converted to 95,00 €
- **WHEN** the user chooses "Edit Purchase Price...", enters 90,00, and confirms
- **THEN** the row shows the purchase price 90,00 €

### Requirement: A purchase price from the user survives a refresh

The app SHALL keep a purchase price that the user entered when a refresh delivers the position again, also when the bank delivers its own purchase price. The purchase price from the bank returns when the user clears the entry.

#### Scenario: Refresh after a manual entry

- **GIVEN** the user entered the purchase price 20,00 € for a position
- **WHEN** a refresh delivers the same position with the purchase price 21,50 €
- **THEN** the row still shows the purchase price 20,00 €

#### Scenario: Clear the entry

- **GIVEN** the user entered 20,00 € and the bank reports 21,50 €
- **WHEN** the user opens "Edit Purchase Price...", clears the field, and confirms
- **THEN** the row shows the purchase price 21,50 €

### Requirement: Comment on a position

The app SHALL let the user add a comment to a position with "Add Comment..." and the shortcut ⇧⌘K, and it SHALL keep the comment as long as the portfolio holds the position.

#### Scenario: Add a comment

- **WHEN** the user selects the position "Musterwerke AG", presses ⇧⌘K, enters "Sparplan", and confirms
- **THEN** the row of "Musterwerke AG" shows that it has a comment
- **AND** the comment is still there after the next refresh

### Requirement: A refresh replaces the positions

The app SHALL replace the positions of a portfolio with the positions that the latest successful refresh delivers. A position that the source no longer reports leaves the list. A position that stays keeps its comment and its manual purchase price.

#### Scenario: Position sold

- **GIVEN** the portfolio shows "Musterwerke AG" and "Beispiel Fonds"
- **WHEN** a refresh delivers only "Beispiel Fonds"
- **THEN** the list shows only "Beispiel Fonds"

#### Scenario: Quantity changed

- **GIVEN** the portfolio shows 40 units of "Musterwerke AG" with the comment "Sparplan"
- **WHEN** a refresh delivers 45 units of the security with the same ISIN
- **THEN** the row shows "45 shares" and still has the comment "Sparplan"

### Requirement: A failed refresh keeps the last positions

The app SHALL keep the positions of the last successful refresh when a refresh of the portfolio fails, and it SHALL show the error on the account together with the time of the last successful refresh.

#### Scenario: Bank not reachable

- **GIVEN** the portfolio shows 3 positions from a refresh at 09:00
- **WHEN** a refresh at 11:00 fails because the bank does not answer
- **THEN** the list still shows the 3 positions
- **AND** the account shows the error and that the positions are from 09:00

### Requirement: Empty portfolio

The app SHALL show a portfolio without positions as an empty list with the text "No portfolio items found." and a balance of zero. An empty portfolio is not an error.

#### Scenario: Bank reports no holdings

- **WHEN** a refresh succeeds and the bank reports no positions for the portfolio
- **THEN** the list shows "No portfolio items found."
- **AND** the sidebar shows the balance 0,00 € for the portfolio

### Requirement: Total value as the account balance

The app SHALL use the sum of the values of all positions as the balance of a portfolio account. The status line shows the number of positions and their sum.

#### Scenario: Three positions

- **GIVEN** a portfolio with positions worth 1.000,00 €, 2.500,00 €, and 500,00 €
- **WHEN** the user opens the portfolio
- **THEN** the sidebar shows the balance 4.000,00 € for the portfolio
- **AND** the status line reads "3 Portfolio Items" with the sum 4.000,00 €

#### Scenario: Positions in two currencies

- **GIVEN** a portfolio with a position worth 1.000,00 € and a position worth 1.100,00 USD that cannot be converted
- **WHEN** the user opens the portfolio
- **THEN** the status line shows the sum 1.000,00 € and the sum 1.100,00 USD

### Requirement: Sum of the selected positions

The app SHALL show the number and the sum of the selected positions in the status line when the user selects one or more positions.

#### Scenario: Select two positions

- **GIVEN** a portfolio with positions worth 1.000,00 €, 2.500,00 €, and 500,00 €
- **WHEN** the user selects the first two rows
- **THEN** the status line shows 2 selected portfolio items with the sum 3.500,00 €

### Requirement: Total gain of a portfolio group

The app SHALL show the total profit or loss of all positions in the upper right corner of the view when the selected account or account group contains only portfolios. Positions without a purchase price do not count.

#### Scenario: Group with two portfolios

- **GIVEN** a group with two portfolios whose positions have a profit of 200,00 € and a loss of 50,00 €
- **WHEN** the user selects the group
- **THEN** the view shows a total profit of 150,00 €

### Requirement: Portfolio value in sums

The app SHALL count the balance of a portfolio account in the sum of its account group and in the total of all accounts, in the same way as the balance of any other account.

#### Scenario: Mixed group

- **GIVEN** the group "Savings" contains a savings account with 5.000,00 € and a portfolio worth 4.000,00 €
- **WHEN** the sidebar shows the sum of the group
- **THEN** the sum reads 9.000,00 €

### Requirement: Daily record of the portfolio value

The app SHALL record the value of each portfolio account once for each day on which a refresh of the portfolio succeeds. A later refresh on the same day replaces the record of that day. The balance chart of an account group includes a portfolio from its first recorded day on.

#### Scenario: Two refreshes on one day

- **GIVEN** a refresh at 09:00 on 6 November 2026 values the portfolio at 4.000,00 €
- **WHEN** a refresh at 17:00 on the same day values it at 4.100,00 €
- **THEN** the record for 6 November 2026 holds 4.100,00 €

#### Scenario: Group chart

- **GIVEN** a group with a current account and a portfolio whose first record is from 1 October 2026
- **WHEN** the user views the balance chart of the group for the year 2026
- **THEN** the bars from 1 October 2026 on include the recorded portfolio value
- **AND** the bars before that date show the current account alone

### Requirement: Order of positions

The app SHALL list positions by the name of the security in alphabetical order, without regard to case. In a group view the order runs across all portfolios of the group.

#### Scenario: Three names

- **GIVEN** the positions "Musterwerke AG", "beispiel Fonds", and "Anleihe Musterland"
- **WHEN** the user opens the portfolio
- **THEN** the rows appear in the order "Anleihe Musterland", "beispiel Fonds", "Musterwerke AG"

### Requirement: Search positions

The app SHALL filter the positions of the current view while the user types in the search field. A position matches when the text occurs in its name, its ISIN, or its security number. Without a match the list shows "No matching portfolio items found."

#### Scenario: Search by ISIN

- **GIVEN** a portfolio with a position that has the ISIN DE0001234567
- **WHEN** the user types "DE000123" in the search field
- **THEN** the list shows only that position

#### Scenario: No match

- **WHEN** the user types "xyz" and no position matches
- **THEN** the list shows "No matching portfolio items found."

### Requirement: Remove a portfolio account

The app SHALL warn before it removes a portfolio account that all its portfolio items and its recorded value history are removed and cannot be restored. It removes them only after the user confirms.

#### Scenario: Confirm removal

- **GIVEN** a portfolio with 3 positions and value records for 200 days
- **WHEN** the user removes the account and confirms the warning
- **THEN** the account, its positions, and its value records are gone

#### Scenario: Cancel removal

- **WHEN** the user removes the account and cancels the warning
- **THEN** the account and all its data stay unchanged
