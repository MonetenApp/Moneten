## ADDED Requirements

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

#### Scenario: Quantity changed

- **GIVEN** the portfolio shows 40 units of "Musterwerke AG" with the comment "Sparplan"
- **WHEN** a refresh delivers 45 units of the security with the same ISIN
- **THEN** the row shows the quantity "45" and still has the comment "Sparplan"
