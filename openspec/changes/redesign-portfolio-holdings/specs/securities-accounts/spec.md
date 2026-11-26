# Spec Delta

## ADDED Requirements

### Requirement: Asset classes

The app SHALL give every position exactly one asset class out of "Stocks", "Funds", "Bonds", "Real estate", "Commodities", "ETFs", "Cryptocurrencies", and "Others".

#### Scenario: Classes of a portfolio

- **GIVEN** a portfolio with a share whose bank sends the class "Stocks" and a fund whose bank sends no class
- **WHEN** the user opens the portfolio
- **THEN** the share has the class "Stocks"
- **AND** the fund has the class "Others"

### Requirement: Asset class from the source

The app SHALL take the asset class of a position from its source when the user chose none. When the source sends no class, the position has the class "Others". The app never derives a class from the name of the security.

#### Scenario: Name that sounds like a fund

- **GIVEN** the bank sends the position "Musterwelt ETF" without a class
- **WHEN** the refresh ends
- **THEN** the position has the class "Others"

#### Scenario: Extension result

- **GIVEN** an extension returns the security "Bitcoin" for a portfolio
- **WHEN** the refresh ends
- **THEN** the position has the class "Others"

### Requirement: Asset class of a FinTS position

The app SHALL read the asset class of a FinTS position from the classification code of the security (CFI, ISO 10962) in the custody account balance by its first two letters: ES, EP, EC, EF, ED, ER, and EV give "Stocks", CE "ETFs", CB "Real estate", EU, CI, CH, CS, CF, CP, and CM "Funds", and DB, DC, DW, DT, DY, DA, DG, DN, and DD "Bonds". Every other code gives no class, also DS, DE, and DM.

#### Scenario: Codes of four securities

- **GIVEN** the bank sends the codes "ESVUFR" for "Musterwerke AG", "CEOGLS" for "Musterwelt ETF", "CIOGLS" for "Beispiel Fonds", and "DBFTFB" for "Anleihe Musterland"
- **WHEN** the refresh ends
- **THEN** the positions have the classes "Stocks", "ETFs", "Funds", and "Bonds"

#### Scenario: Code without a class

- **GIVEN** the bank sends the code "RWSNCA" for the warrant "Optionsschein Muster"
- **WHEN** the refresh ends
- **THEN** the position has the class "Others"

#### Scenario: Structured product and other debt

- **GIVEN** the bank sends the code "DSXXXX" for "Garantiezertifikat Muster" and "DMXXXX" for "Schuldschein Muster"
- **WHEN** the refresh ends
- **THEN** both positions have the class "Others"

### Requirement: Choose an asset class

The app SHALL let the user choose the asset class of the selected positions with the submenu "Asset Class" in the context menu of a position. The submenu lists the eight classes and "Automatic", and marks the current choice. "Automatic" removes the choice, so the position takes the class of its source again.

#### Scenario: Choose a class

- **GIVEN** the position "Musterwerke AG" has the class "Others" because the bank sends none
- **WHEN** the user chooses "Stocks" in the submenu "Asset Class" of its context menu
- **THEN** the position has the class "Stocks"
- **AND** the submenu marks "Stocks" the next time it opens

#### Scenario: Several positions

- **GIVEN** the user selects three positions
- **WHEN** the user chooses "ETFs" in the submenu "Asset Class"
- **THEN** all three positions have the class "ETFs"

#### Scenario: Back to the class of the bank

- **GIVEN** the bank sends the class "Funds" for "Beispiel Fonds" and the user chose "ETFs"
- **WHEN** the user chooses "Automatic" in the submenu "Asset Class"
- **THEN** the position has the class "Funds"

### Requirement: The user's asset class survives a refresh

The app SHALL keep the asset class that the user chose for a position when a refresh delivers the position again, also when the bank sends another class. A refresh updates the class of the source and never changes the user's choice. A position that leaves the portfolio takes the choice with it.

#### Scenario: Refresh after a choice

- **GIVEN** the bank sends the class "Funds" for "Beispiel Fonds" and the user chose "ETFs"
- **WHEN** a refresh delivers "Beispiel Fonds" with the class "Funds" and a new quote
- **THEN** the position still has the class "ETFs"

#### Scenario: Bank changes the class

- **GIVEN** the user chose no class for "Beispiel Fonds", and the bank sent no class
- **WHEN** a refresh delivers "Beispiel Fonds" with the class "Funds"
- **THEN** the position has the class "Funds"

#### Scenario: Sold and bought again

- **GIVEN** the bank sends the class "Funds" for "Beispiel Fonds" and the user chose "ETFs"
- **WHEN** a refresh delivers the portfolio without "Beispiel Fonds", and a later refresh delivers "Beispiel Fonds" again with the class "Funds"
- **THEN** the position has the class "Funds"
- **AND** a position without a class from the bank that comes back the same way has the class "Others"

### Requirement: Asset class tag

The app SHALL show the asset class of a position as a small tag in the name column, in the line below the name, next to the ISIN.

#### Scenario: Share with an ISIN

- **GIVEN** the position "Musterwerke AG" with the ISIN DE0001234567 and the class "Stocks"
- **WHEN** the user opens the portfolio
- **THEN** the name column shows "Musterwerke AG" and below it "DE0001234567" with the tag "Stocks"

### Requirement: Filter by asset class

The app SHALL offer the filter "Asset class" in the filter bar above the positions, with "Show All" and one entry for each class that a position of the view has. While a class is selected, the list and the status line show only the positions of that class, and a line below the last row says "An asset class filter is active; some entries might be hidden."

#### Scenario: Show one class

- **GIVEN** a portfolio with 2 positions of the class "Stocks" worth 3.000,00 € and 1 position of the class "Bonds" worth 1.000,00 €
- **WHEN** the user selects "Stocks" in the filter "Asset class"
- **THEN** the list shows the 2 stock positions
- **AND** the status line reads "2 Portfolio Items" with the sum 3.000,00 €

#### Scenario: Hint below the list

- **GIVEN** a portfolio with 3 positions of the class "ETFs" and 2 positions of the class "Stocks"
- **WHEN** the user selects "ETFs" in the filter "Asset class"
- **THEN** the list shows the 3 ETF positions
- **AND** a line below the last row says "An asset class filter is active; some entries might be hidden."

#### Scenario: No hint without a filter

- **GIVEN** the same portfolio with the filter "Asset class" at "Show All"
- **WHEN** the user opens the portfolio
- **THEN** the list shows 5 positions and no line about a filter

#### Scenario: Entries of the filter

- **GIVEN** the same portfolio
- **WHEN** the user opens the filter "Asset class"
- **THEN** it lists "Show All", "Stocks", and "Bonds"

### Requirement: Day of an old quote

The app SHALL show the day of the last quote below the quote only when it is older than the newest quote day among the positions of the same portfolio, and then in the warning color.

#### Scenario: Current and old quotes

- **GIVEN** a portfolio with two positions quoted on 25.11.2026 and one position quoted on 20.11.2026
- **WHEN** the user opens the portfolio
- **THEN** the two positions show their quote without a day
- **AND** the third position shows "20.11.2026" below its quote in the warning color

### Requirement: Quote of zero

The app SHALL show "–" in place of a last quote of 0.

#### Scenario: Position without a price

- **GIVEN** the bank sends the quote 0,00 € for the position "Musterwerke AG"
- **WHEN** the user opens the portfolio
- **THEN** the last quote of "Musterwerke AG" reads "–"

## MODIFIED Requirements

### Requirement: Position row content

The app SHALL show each position in separate columns: the name of the security with its ISIN below it, the quantity, the purchase price, the last quote, the value in the account currency in semibold, and the profit or loss as an amount with the percentage below it.

#### Scenario: Row of a share

- **GIVEN** a position of 40 units of "Musterwerke AG" with the ISIN DE0001234567, the last quote 25,00 €, the value 1.000,00 €, and the purchase price 20,00 €
- **WHEN** the user opens the portfolio
- **THEN** the row shows "Musterwerke AG" with "DE0001234567" below it, the quantity "40", the purchase price 20,00 €, the last quote 25,00 €, the value 1.000,00 € in semibold, and "+200,00 €" with "+25,00 %" below it

### Requirement: Quantities as units or as a nominal amount

The app SHALL show a quantity as a number of units with all decimal places that the source delivers and without a word for the unit, or as a nominal amount with its currency when the source marks the quantity as nominal.

#### Scenario: Fractional units

- **GIVEN** a fund position with the quantity 12.3456
- **WHEN** the user opens the portfolio
- **THEN** the row shows the quantity "12,3456"

#### Scenario: Whole units

- **GIVEN** a position with the quantity 646
- **WHEN** the user opens the portfolio
- **THEN** the row shows the quantity "646"

#### Scenario: Bond with a nominal amount

- **GIVEN** a bond position with the nominal amount 5000 in EUR and the quote 98,50 %
- **WHEN** the user opens the portfolio
- **THEN** the row shows the quantity 5.000,00 € and the last quote 98,50 %

### Requirement: Value of a position

The app SHALL use the value in the account currency that the source delivers for a position, plus the accrued interest that the source delivers. When the source delivers no value, the app computes it from the quantity and the last quote. The profit or loss leaves the accrued interest out.

#### Scenario: Bank delivers the value

- **GIVEN** the bank reports a position with 10 units, the quote 99,99 €, and the value 1.000,00 €
- **WHEN** the user opens the portfolio
- **THEN** the value reads 1.000,00 €

#### Scenario: Source delivers no value

- **GIVEN** an extension returns a position with 10 units and the price 99,99 and no amount
- **WHEN** the user opens the portfolio
- **THEN** the value reads 999,90 €

#### Scenario: Bond with accrued interest

- **GIVEN** the bank reports a bond with the market value 4.925,00 €, the accrued interest 37,50 €, and the purchase rate 97,00 % for the nominal amount 5.000,00 €
- **WHEN** the user opens the portfolio
- **THEN** the value reads 4.962,50 €
- **AND** the profit or loss reads "+75,00 €" with "+1,55 %"

### Requirement: Profit or loss

The app SHALL compute the profit or loss of a position as its value minus its purchase value, and the percentage as the profit or loss divided by the purchase value. A row shows a profit in green with "+" and a loss in red with "−", without a word. A position without a purchase price shows no profit or loss.

#### Scenario: Profit

- **GIVEN** a position with the value 1.000,00 € and the purchase value 800,00 €
- **WHEN** the user opens the portfolio
- **THEN** the row shows "+200,00 €" and "+25,00 %" in green

#### Scenario: Loss

- **GIVEN** a position with the value 800,00 € and the purchase value 1.000,00 €
- **WHEN** the user opens the portfolio
- **THEN** the row shows "−200,00 €" and "−20,00 %" in red
- **AND** the row shows neither "Profit" nor "Loss"

#### Scenario: No purchase price

- **GIVEN** a position for which neither the bank nor the user gave a purchase price
- **WHEN** the user opens the portfolio
- **THEN** the row shows the value and the last quote
- **AND** the fields for the purchase price and the profit or loss are empty

### Requirement: A refresh replaces the positions

The app SHALL replace the positions of a portfolio with the positions that the latest successful refresh delivers. A position that the source no longer reports leaves the list. A position that stays takes the quantity, the quote, and the value of the refresh.

#### Scenario: Position sold

- **GIVEN** the portfolio shows "Musterwerke AG" and "Beispiel Fonds"
- **WHEN** a refresh delivers only "Beispiel Fonds"
- **THEN** the list shows only "Beispiel Fonds"

#### Scenario: Quantity changed

- **GIVEN** the portfolio shows 40 units of "Musterwerke AG"
- **WHEN** a refresh delivers 45 units of the security with the same ISIN
- **THEN** the row shows the quantity "45"
