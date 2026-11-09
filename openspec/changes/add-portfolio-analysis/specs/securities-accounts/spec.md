# Spec Delta

## ADDED Requirements

### Requirement: Predefined asset classes

The app SHALL offer the asset classes "Stocks", "Funds", "Bonds", "Real estate", "Commodities", "ETFs", "Cryptocurrencies", and "Others". A security without a class counts as "Unassigned".

#### Scenario: New position

- **WHEN** a refresh delivers a security that the app has not seen before
- **THEN** the position has no asset class and counts as "Unassigned"

### Requirement: Assign an asset class

The app SHALL let the user assign an asset class to one or more selected positions through "Assign Asset Class" in the context menu. The menu marks the current class and offers a way to remove the assignment.

#### Scenario: Assign one position

- **GIVEN** the position "Musterwerke AG" is "Unassigned"
- **WHEN** the user opens its context menu and chooses "Assign Asset Class" and then "Stocks"
- **THEN** the position has the class "Stocks"
- **AND** the menu shows a checkmark at "Stocks" the next time it opens

#### Scenario: Assign several positions

- **GIVEN** three selected fund positions
- **WHEN** the user chooses "Assign Asset Class" and then "ETFs"
- **THEN** all three positions have the class "ETFs"

### Requirement: The asset class belongs to the security

The app SHALL keep the asset class with the security and not with the single position. The class survives every refresh and applies to the same security in every portfolio.

#### Scenario: Refresh

- **GIVEN** the security with the ISIN DE0001234567 has the class "Stocks"
- **WHEN** a refresh delivers the position again with a new quote
- **THEN** the position still has the class "Stocks"

#### Scenario: Same security in a second portfolio

- **GIVEN** the security with the ISIN DE0001234567 has the class "Stocks"
- **WHEN** a second portfolio reports a position in the same security
- **THEN** that position has the class "Stocks"

### Requirement: Filter by asset class

The app SHALL offer the filter "Asset class" in portfolio views with "Show All", one entry for each class that occurs, and "Unassigned". While a class is selected, the list, the status line, and the charts use only the matching positions, and a hint says that an asset class filter is active and that entries might be hidden.

#### Scenario: Show one class

- **GIVEN** a portfolio with 2 positions of the class "Stocks" worth 3.000,00 € and 1 position of the class "Bonds" worth 1.000,00 €
- **WHEN** the user selects "Stocks" in the filter "Asset class"
- **THEN** the list shows the 2 stock positions
- **AND** the status line reads "2 Portfolio Items" with the sum 3.000,00 €
- **AND** the view shows the hint that an asset class filter is active

#### Scenario: Reset

- **WHEN** the user selects "Show All"
- **THEN** the list shows all positions and the hint disappears

### Requirement: Pie chart by asset class

The app SHALL show a pie chart of the portfolio value by asset class when the user selects "Pie Chart" in a portfolio view. Each class has one slice with its name, its value, and its share. "Unassigned" positions form their own slice.

#### Scenario: Two classes

- **GIVEN** a portfolio with 3.000,00 € in "Stocks" and 1.000,00 € in "Bonds"
- **WHEN** the user selects "Pie Chart"
- **THEN** the chart shows the slice "Stocks" with 3.000,00 € and 75 %, and the slice "Bonds" with 1.000,00 € and 25 %

#### Scenario: No positions

- **GIVEN** an empty portfolio
- **WHEN** the user selects "Pie Chart"
- **THEN** the chart area shows "No portfolio items; no pie chart."

### Requirement: Bar chart of the portfolio history

The app SHALL show a bar chart of the recorded portfolio value over time when the user selects "Bar Chart" in a portfolio view. The switch "Daily balance" shows one value for each day, and "Monthly average balance" shows the average of each month.

#### Scenario: Daily values

- **GIVEN** value records of 4.000,00 € on 5 November 2026 and 4.100,00 € on 6 November 2026
- **WHEN** the user selects "Bar Chart" with "Daily balance"
- **THEN** the chart shows a bar of 4.000,00 € for 5 November and a bar of 4.100,00 € for 6 November

#### Scenario: Day without a refresh

- **GIVEN** records for 5 and 7 November 2026 and no refresh on 6 November
- **WHEN** the user views the daily chart
- **THEN** the bar for 6 November shows the value of 5 November

#### Scenario: No positions

- **GIVEN** an empty portfolio without records
- **WHEN** the user selects "Bar Chart"
- **THEN** the chart area shows "No portfolio items; no bar chart."

### Requirement: The history starts with the first record

The app SHALL mark the day of the first record in the history chart and state that there have been no recordings before that date. The chart shows no bars before that day.

#### Scenario: Chart reaches back before the first record

- **GIVEN** the first value record of a portfolio is from 1 October 2026
- **WHEN** the user views the history for the year 2026
- **THEN** the chart shows no bars before 1 October 2026
- **AND** the chart states that there have been no recordings before 01.10.2026

### Requirement: Scaled value axis

The app SHALL scale the value axis of the history chart to the range of the shown values, so that a small change of a large portfolio is visible. The axis shows its lowest and highest value.

#### Scenario: Small change

- **GIVEN** records between 100.000,00 € and 101.000,00 € in the shown period
- **WHEN** the user views the history chart
- **THEN** the bars differ visibly in height
- **AND** the axis labels show that the axis does not start at zero

### Requirement: Choose the value of the history chart

The app SHALL offer a menu in the chart area of a portfolio view that selects what the history chart shows. The entries are "Account balance" for the recorded value, "Absolute change" for the change against the first shown day as an amount, and "Relative change" for that change as a percentage.

#### Scenario: Relative change

- **GIVEN** records of 4.000,00 € on the first shown day and 4.200,00 € on the last shown day
- **WHEN** the user selects "Relative change"
- **THEN** the bar of the last day shows 5,00 %

### Requirement: Explain the daily record

The app SHALL state in the portfolio view that it records a snapshot of the portfolio values once a day, so that the user knows where the history comes from.

#### Scenario: First visit

- **GIVEN** a portfolio with one value record
- **WHEN** the user selects "Bar Chart" for the first time
- **THEN** the chart area contains the note about the daily snapshot

### Requirement: Export positions as CSV

The app SHALL export the positions of the selected portfolio or portfolio group with "Export Portfolio Positions..." and the selected rows with "Export Portfolio Position..." to a CSV file. Each row holds the account, name, ISIN, security number, asset class, quantity, quote with currency and date, value, purchase price, profit or loss, and comment.

#### Scenario: Export a portfolio

- **GIVEN** a portfolio with 3 positions
- **WHEN** the user chooses "Export Portfolio Positions..." and picks a file name
- **THEN** the app writes a CSV file with one header row and 3 data rows

#### Scenario: Export one position

- **GIVEN** the user selected the position "Musterwerke AG"
- **WHEN** the user chooses "Export Portfolio Position..."
- **THEN** the file holds the header row and the row of "Musterwerke AG"

#### Scenario: File cannot be written

- **WHEN** the user picks a folder without write access
- **THEN** the app shows that it could not export to the file and writes nothing

### Requirement: Manual positions in an offline portfolio

The app SHALL let the user add, edit, and remove positions by hand in an offline account of the type "Portfolio" with "New portfolio item". A manual position has a name, an optional ISIN, a quantity, a price, a purchase price, and an asset class. The app does not refresh it.

#### Scenario: Add a position

- **GIVEN** an offline portfolio "Gold im Tresor"
- **WHEN** the user chooses "New portfolio item" and enters the name "Goldbarren 100 g", the quantity 2, and the price 9.000,00 €
- **THEN** the list shows "Goldbarren 100 g" with the value 18.000,00 €

#### Scenario: Not offered for a bank portfolio

- **GIVEN** a portfolio that comes from a bank access
- **WHEN** the user opens the context menu of the list
- **THEN** the menu does not offer "New portfolio item"

### Requirement: Import positions into an offline portfolio

The app SHALL import positions into an offline portfolio with "Import Portfolio Positions..." from a CSV file in the format of its own position export. A row whose ISIN already exists in the portfolio updates that position.

#### Scenario: Import an exported file

- **GIVEN** a CSV file that the app exported with 3 positions, and an empty offline portfolio
- **WHEN** the user chooses "Import Portfolio Positions..." and selects the file
- **THEN** the offline portfolio shows the 3 positions with the same names, quantities, and values

#### Scenario: Unreadable file

- **WHEN** the user selects a file that has no column for the name or the quantity
- **THEN** the app shows that it could not import from the file and changes nothing
