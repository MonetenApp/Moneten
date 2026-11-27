# Spec Delta

## ADDED Requirements

### Requirement: Space at the left edge

The app SHALL start the text of the rows, of the column header, and of the filter bar of a portfolio view 20 points from the left edge of the list.

#### Scenario: Rows, header, and filter bar

- **GIVEN** a portfolio with the position "Musterwerke AG"
- **WHEN** the user opens the portfolio
- **THEN** the filter "Asset class", the header "Quote date", and the day of the quote of "Musterwerke AG" each start 20 points from the left edge

### Requirement: Asset class ribbon

The app SHALL show the asset class of a position as a ribbon below the day of the quote, from the left edge of the row, with the name of the class in capitals in white on the color of the class.

#### Scenario: Ribbon of a share

- **GIVEN** the position "Musterwerke AG" with the class "Stocks"
- **WHEN** the user opens the portfolio
- **THEN** the row shows the ribbon "STOCKS" in the color of "Stocks" below the day of the quote

### Requirement: Day of the last quote

The app SHALL show the day of the last quote of a position in the first line of its row. When the day is older than the newest quote day among the positions of the same portfolio, the day and the last quote show in the warning color. A position without a day of the quote leaves the line empty.

#### Scenario: Current and old quotes

- **GIVEN** a portfolio with two positions quoted on 27.11.2026 and the position "Ostsee Rohstoff ADR" quoted on 03.03.2022
- **WHEN** the user opens the portfolio
- **THEN** the two positions show "27.11.2026" in the color of the text
- **AND** "Ostsee Rohstoff ADR" shows "03.03.2022" and its last quote in the warning color

### Requirement: Security numbers below the name

The app SHALL show below the name of a position its ISIN after the label "ISIN" and its WKN after the label "WKN". Each number shows only when the source sends it. The app never derives a WKN from an ISIN.

#### Scenario: ISIN and WKN from the bank

- **GIVEN** the bank sends the position "Musterwerke AG" with the ISIN DE000MUST001 and the WKN MUST00
- **WHEN** the user opens the portfolio
- **THEN** the line below the name reads "ISIN DE000MUST001  WKN MUST00"

#### Scenario: Only an ISIN

- **GIVEN** the bank sends the position "Weltindex UCITS ETF" with the ISIN IE00WELT0003 and no WKN
- **WHEN** the user opens the portfolio
- **THEN** the line below the name reads "ISIN IE00WELT0003" and shows no WKN

#### Scenario: Extension with a security number

- **GIVEN** an extension returns the security "Beispiel Chemie AG" with the ISIN DE000BSPC002 and the security number BSPC00
- **WHEN** the refresh ends
- **THEN** the line below the name reads "ISIN DE000BSPC002  WKN BSPC00"

### Requirement: Column headers with two lines

The app SHALL show above the positions a header that names each column: "Quote date", "Name", "Quantity", "Purchase price" over "Last quote", and "Value" over "Profit/Loss". The second line of a header names the second line of its column.

#### Scenario: Header of a portfolio

- **GIVEN** a portfolio with 5 positions
- **WHEN** the user opens the portfolio
- **THEN** the header reads "Quote date", "Name", "Quantity", "Purchase price" with "Last quote" below, and "Value" with "Profit/Loss" below

### Requirement: Sort positions

The app SHALL sort the positions by the value of a header line when the user clicks it, in ascending order, and in descending order on the next click. The header marks the line and the direction. A position without the value comes last in both directions, and positions with the same value keep the order by name. The order stays while the user moves between portfolio views.

#### Scenario: Sort by value

- **GIVEN** a portfolio with positions worth 50.129,60 €, 130.100,40 €, and 4.955,00 €
- **WHEN** the user clicks "Value" in the header
- **THEN** the rows show 4.955,00 €, 50.129,60 €, and 130.100,40 €
- **AND** the header marks "Value" as ascending

#### Scenario: Second click

- **GIVEN** the list is sorted by "Value" in ascending order
- **WHEN** the user clicks "Value" again
- **THEN** the rows show 130.100,40 €, 50.129,60 €, and 4.955,00 €

#### Scenario: Two values in one column

- **GIVEN** a portfolio with "Musterwerke AG" bought at 156,15 € and quoted at 77,60 €, and "Beispiel Chemie AG" bought at 191,83 € and quoted at 458,10 €
- **WHEN** the user clicks "Last quote" in the header
- **THEN** "Musterwerke AG" comes first
- **AND** the header marks "Last quote" and not "Purchase price"

#### Scenario: Position without a purchase price

- **GIVEN** a portfolio with a position without a purchase price and two positions with purchase prices
- **WHEN** the user clicks "Purchase price" once and then again
- **THEN** the position without a purchase price is the last row both times

### Requirement: Open a position

The app SHALL open a position when the user clicks it. The row of an open position grows and shows the comment of the position below its two lines, over the full width of the row, without a separator line and with a small gap. A second click on the position, or a click on another position, closes it. A position without a comment keeps the height of its row.

#### Scenario: Open and close

- **GIVEN** the position "Musterwerke AG" has the comment "Nachkaufen unter 70 €."
- **WHEN** the user clicks "Musterwerke AG"
- **THEN** its row shows "Nachkaufen unter 70 €." below the two lines, from the start of the name to the right end of the row
- **AND** a second click on "Musterwerke AG" hides the comment again

#### Scenario: Click on another position

- **GIVEN** "Musterwerke AG" is open and "Weltindex UCITS ETF" has the comment "Sparplan 500 € am 1."
- **WHEN** the user clicks "Weltindex UCITS ETF"
- **THEN** the row of "Musterwerke AG" shows no comment
- **AND** the row of "Weltindex UCITS ETF" shows "Sparplan 500 € am 1."

### Requirement: Comment on a position

The app SHALL let the user add, change, and remove the comment of a position with "Add Comment..." or "Edit Comment..." in its context menu and with ⇧⌘K, in the same sheet as the comment of a transaction. An empty comment removes it.

#### Scenario: Add a comment

- **GIVEN** the position "Musterwerke AG" has no comment
- **WHEN** the user chooses "Add Comment..." in its context menu, types "Nachkaufen unter 70 €.", and confirms
- **THEN** the position has the comment "Nachkaufen unter 70 €."
- **AND** its context menu shows "Edit Comment..."

#### Scenario: Remove a comment

- **GIVEN** the position "Musterwerke AG" has the comment "Nachkaufen unter 70 €."
- **WHEN** the user presses ⇧⌘K, deletes the text, and confirms
- **THEN** the position has no comment

### Requirement: Comment mark

The app SHALL show a speech bubble in the color of a note right after the name of a position that has a comment. When the pointer rests on the bubble, the app shows the comment as a tooltip.

#### Scenario: Position with a comment

- **GIVEN** the position "Weltindex UCITS ETF" has the comment "Sparplan 500 € am 1."
- **WHEN** the user rests the pointer on the speech bubble after its name
- **THEN** the tooltip reads "Sparplan 500 € am 1."

### Requirement: A comment survives a refresh

The app SHALL keep the comment of a position when a refresh delivers the position again. A position that leaves the portfolio takes its comment with it, and a security that comes back later has no comment.

#### Scenario: Refresh with a new quote

- **GIVEN** the position "Musterwerke AG" has the comment "Nachkaufen unter 70 €."
- **WHEN** a refresh delivers "Musterwerke AG" with a new quote
- **THEN** the position still has the comment "Nachkaufen unter 70 €."

#### Scenario: Sold and bought again

- **GIVEN** the position "Musterwerke AG" has the comment "Nachkaufen unter 70 €."
- **WHEN** a refresh delivers the portfolio without "Musterwerke AG", and a later refresh delivers it again
- **THEN** the position has no comment

### Requirement: Comments in the complete export

The app SHALL write the comment of each position into the complete export and read it back when it imports the file.

#### Scenario: Export and import

- **GIVEN** the position "Musterwerke AG" has the comment "Nachkaufen unter 70 €."
- **WHEN** the user exports all data and imports the file into an empty database
- **THEN** the position "Musterwerke AG" has the comment "Nachkaufen unter 70 €."

### Requirement: Filter by profit or loss

The app SHALL offer the filter "Profit/Loss" in the filter bar of a portfolio view with "Show All", "Gains", and "Losses". "Gains" shows the positions with a profit above 0, and "Losses" those with a loss. A position with a profit or loss of 0, or without one, shows with neither. While "Gains" or "Losses" is selected, a line below the last row says "A profit/loss filter is active; some entries might be hidden."

#### Scenario: Gains

- **GIVEN** a portfolio with three positions in profit, one with a loss, and one without a purchase price
- **WHEN** the user selects "Gains" in the filter "Profit/Loss"
- **THEN** the list shows the three positions in profit
- **AND** a line below the last row says "A profit/loss filter is active; some entries might be hidden."

#### Scenario: Profit of zero

- **GIVEN** a position with the value 800,00 € and the purchase value 800,00 €
- **WHEN** the user selects "Gains" and then "Losses"
- **THEN** the list shows the position neither time

### Requirement: Filter by quote

The app SHALL offer the filter "Quote" in the filter bar of a portfolio view with "Show All" and "Outdated". "Outdated" shows the positions whose day of the last quote is older than the newest quote day of their portfolio, and the positions with a quote of 0. While "Outdated" is selected, a line below the last row says "A quote filter is active; some entries might be hidden."

#### Scenario: Old quote and quote of zero

- **GIVEN** a portfolio with three positions quoted on 27.11.2026, one quoted on 03.03.2022, and one quoted at 0,00 € on 27.11.2026
- **WHEN** the user selects "Outdated" in the filter "Quote"
- **THEN** the list shows the position quoted on 03.03.2022 and the position quoted at 0,00 €
- **AND** a line below the last row says "A quote filter is active; some entries might be hidden."

### Requirement: Count of a filtered portfolio

The app SHALL show in the status line the number of shown positions of all positions of the view while a filter hides positions, such as "3 of 5 Portfolio Items", with the sum of the shown positions.

#### Scenario: Gains of five positions

- **GIVEN** a portfolio with 5 positions, 3 of them in profit and worth 250.399,40 € together
- **WHEN** the user selects "Gains" in the filter "Profit/Loss"
- **THEN** the status line reads "3 of 5 Portfolio Items" with the sum 250.399,40 €

### Requirement: Portfolio filters across views

The app SHALL keep the filters "Profit/Loss" and "Quote" when the user opens another portfolio or a group of portfolios, and the pin of the filter bar saves both with the other filters.

#### Scenario: Another portfolio

- **GIVEN** the filter "Profit/Loss" is at "Losses" in the portfolio "Depot"
- **WHEN** the user opens the portfolio "Zweitdepot"
- **THEN** the filter "Profit/Loss" reads "Losses"

#### Scenario: Restart with the pin on

- **GIVEN** the pin is on and the filter "Quote" is at "Outdated"
- **WHEN** the user quits the app and opens it again
- **THEN** the filter "Quote" reads "Outdated"

### Requirement: Color of an asset class

The app SHALL give each asset class a default color and let the user change it in the asset class settings, which "Asset Class Settings..." at the end of the submenu "Asset Class" opens. The ribbon of a class shows its color with white text in light and dark mode. "Restore Default Colors" gives every class its default color again.

#### Scenario: Change the color of a class

- **GIVEN** the class "Bonds" has its default color
- **WHEN** the user chooses green for "Bonds" in the asset class settings
- **THEN** every ribbon "BONDS" shows green with white text

#### Scenario: Restore the defaults

- **GIVEN** the user chose green for "Bonds"
- **WHEN** the user chooses "Restore Default Colors" in the asset class settings
- **THEN** the ribbon "BONDS" shows the default color of "Bonds"

### Requirement: Group by asset class

The app SHALL offer the option "Group by asset class" in the filter bar of a portfolio view. When it is on, the list shows a section for each class with positions, in the order of the submenu "Asset Class", under a heading with the name of the class, the number of its positions, their value, and their profit or loss. Each row keeps its ribbon. When it is off, the list shows all positions without sections.

#### Scenario: Two classes

- **GIVEN** a portfolio with 2 positions of the class "Stocks" worth 180.230,00 € with a profit of 24.880,77 €, and 1 position of the class "Bonds" worth 4.955,00 € with a profit of 30,00 €
- **WHEN** the user turns on "Group by asset class"
- **THEN** the list shows the heading "Stocks" with "2 Portfolio Items", 180.230,00 €, and "+24.880,77 €" above the two stock positions
- **AND** the heading "Bonds" with "1 Portfolio Item", 4.955,00 €, and "+30,00 €" above the bond position

#### Scenario: Back to the flat list

- **GIVEN** "Group by asset class" is on
- **WHEN** the user turns it off
- **THEN** the list shows the 3 positions without headings

### Requirement: Assign an asset class with the keyboard

The app SHALL open a picker of the eight asset classes and "Automatic" for the selected positions when the user presses ⌘K in a portfolio view. The choice works as the same entry of the submenu "Asset Class".

#### Scenario: Picker for two positions

- **GIVEN** the user selects two positions in a portfolio view
- **WHEN** the user presses ⌘K and chooses "ETFs"
- **THEN** both positions have the class "ETFs"

### Requirement: Drop positions on a class heading

The app SHALL give the dragged positions the class of a heading of the grouped list when the user drops them on it, as a choice of that class in the submenu "Asset Class".

#### Scenario: Drop a position

- **GIVEN** "Group by asset class" is on and the position "Weltindex UCITS ETF" is in the section "Others"
- **WHEN** the user drags it onto the heading "ETFs"
- **THEN** the position has the class "ETFs" and shows in the section "ETFs"

### Requirement: Allocation by asset class

The app SHALL show the allocation of a portfolio view by asset class in a popover when the user clicks the allocation button above the switch "D" and "M" of the history chart. The popover shows a stacked bar and one line for each class with positions: its color, its name, its share of the value, and its value. The view shows no allocation before the click, and the history chart stays above the list.

#### Scenario: Three classes

- **GIVEN** a portfolio with 180.230,00 € in "Stocks", 115.344,00 € in "ETFs", and 4.955,00 € in "Bonds"
- **WHEN** the user clicks the allocation button
- **THEN** the popover shows "Stocks" with 59,97 % and 180.230,00 €, "ETFs" with 38,38 % and 115.344,00 €, and "Bonds" with 1,65 % and 4.955,00 €

#### Scenario: Empty portfolio

- **GIVEN** an empty portfolio
- **WHEN** the user clicks the allocation button
- **THEN** the popover says "No portfolio items."

### Requirement: The allocation sets the class filter

The app SHALL set the filter "Asset class" to a class and close the popover when the user clicks the line of that class in the allocation.

#### Scenario: Click on a class

- **GIVEN** the allocation popover shows "Stocks", "ETFs", and "Bonds"
- **WHEN** the user clicks "ETFs"
- **THEN** the filter "Asset class" reads "ETFs" and the list shows only the ETF positions

## MODIFIED Requirements

### Requirement: Position row content

The app SHALL show each position in a row of five columns with two lines each: the day of the last quote over the asset class ribbon, the name in bold over the ISIN and the WKN, the quantity over its unit, the purchase price over the last quote, and the value in semibold over the profit or loss as an amount and a percentage. The row does not show the time of the quote.

#### Scenario: Row of a share

- **GIVEN** a position of 646 units of "Musterwerke AG" with the ISIN DE000MUST001, the WKN MUST00, the class "Stocks", the purchase price 156,15 €, the last quote 77,60 € of 27.11.2026, and the value 50.129,60 €
- **WHEN** the user opens the portfolio
- **THEN** the first column shows "27.11.2026" over the ribbon "STOCKS"
- **AND** the second column shows "Musterwerke AG" in bold over "ISIN DE000MUST001  WKN MUST00"
- **AND** the third column shows "646" over "shares"
- **AND** the fourth column shows 156,15 € over 77,60 €
- **AND** the fifth column shows 50.129,60 € in semibold over "−50.741,27 € · −50,30 %" in red

### Requirement: Quantities as units or as a nominal amount

The app SHALL show a quantity as a number of units with all decimal places that the source delivers and the word "shares" below it, or as a nominal amount with its currency and the word "nominal" below it when the source marks the quantity as nominal.

#### Scenario: Fractional units

- **GIVEN** a fund position with the quantity 12.3456
- **WHEN** the user opens the portfolio
- **THEN** the row shows the quantity "12,3456" over "shares"

#### Scenario: Whole units

- **GIVEN** a position with the quantity 646
- **WHEN** the user opens the portfolio
- **THEN** the row shows the quantity "646" over "shares"

#### Scenario: Bond with a nominal amount

- **GIVEN** a bond position with the nominal amount 5000 in EUR and the quote 99,10 %
- **WHEN** the user opens the portfolio
- **THEN** the row shows the quantity 5.000,00 € over "nominal" and the last quote 99,10 %

### Requirement: Profit or loss

The app SHALL compute the profit or loss of a position as its value minus its purchase value, and the percentage as the profit or loss divided by the purchase value. A row shows the amount and the percentage in one line below the value, joined by "·", a profit in green with "+" and a loss in red with "−", without a word. An amount or a percentage that shows as zero has no sign and no color. A position without a purchase price shows no profit or loss.

#### Scenario: Profit

- **GIVEN** a position with the value 1.000,00 € and the purchase value 800,00 €
- **WHEN** the user opens the portfolio
- **THEN** the row shows "+200,00 € · +25,00 %" in green below the value

#### Scenario: Loss

- **GIVEN** a position with the value 800,00 € and the purchase value 1.000,00 €
- **WHEN** the user opens the portfolio
- **THEN** the row shows "−200,00 € · −20,00 %" in red below the value
- **AND** the row shows neither "Profit" nor "Loss"

#### Scenario: Profit that rounds to zero percent

- **GIVEN** a position with the value 800,01 € and the purchase value 800,00 €
- **WHEN** the user opens the portfolio
- **THEN** the row shows "+0,01 €" in green and "0,00 %" without a color

#### Scenario: No purchase price

- **GIVEN** a position for which neither the bank nor the user gave a purchase price
- **WHEN** the user opens the portfolio
- **THEN** the row shows the value and the last quote
- **AND** the fields for the purchase price and the profit or loss are empty

### Requirement: Order of positions

The app SHALL list positions by the name of the security in alphabetical order, without regard to case, until the user sorts by a header line. In a group view the order runs across all portfolios of the group.

#### Scenario: Three names

- **GIVEN** the positions "Musterwerke AG", "beispiel Fonds", and "Anleihe Musterland"
- **WHEN** the user opens the portfolio
- **THEN** the rows appear in the order "Anleihe Musterland", "beispiel Fonds", "Musterwerke AG"

### Requirement: Search positions

The app SHALL filter the positions of the current view while the user types in the search field. A position matches when the text occurs in its name, its ISIN, its security number, or its comment. Without a match the list shows "No matching portfolio items found."

#### Scenario: Search by ISIN

- **GIVEN** a portfolio with a position that has the ISIN DE0001234567
- **WHEN** the user types "DE000123" in the search field
- **THEN** the list shows only that position

#### Scenario: Search by comment

- **GIVEN** a portfolio with a position that has the comment "Sparplan 500 € am 1."
- **WHEN** the user types "sparplan" in the search field
- **THEN** the list shows only that position

#### Scenario: No match

- **WHEN** the user types "xyz" and no position matches
- **THEN** the list shows "No matching portfolio items found."

### Requirement: Filter by asset class

The app SHALL offer the filter "Asset class" in the filter bar above the positions, with "Show All" and one entry for each class that a position of the view has. While a class is selected, the list and the status line show only the positions of that class, and a line below the last row says "An asset class filter is active; some entries might be hidden." When no position of the view has the selected class any more, the filter goes back to "Show All".

#### Scenario: Show one class

- **GIVEN** a portfolio with 2 positions of the class "Stocks" worth 3.000,00 € and 1 position of the class "Bonds" worth 1.000,00 €
- **WHEN** the user selects "Stocks" in the filter "Asset class"
- **THEN** the list shows the 2 stock positions
- **AND** the status line reads "2 of 3 Portfolio Items" with the sum 3.000,00 €

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

- **GIVEN** a portfolio with positions of the classes "Stocks" and "Bonds"
- **WHEN** the user opens the filter "Asset class"
- **THEN** it lists "Show All", "Stocks", and "Bonds"

#### Scenario: The selected class loses its last position

- **GIVEN** a portfolio with 1 position of the class "Bonds" and 2 positions of the class "Stocks", and the filter "Asset class" at "Bonds"
- **WHEN** the user chooses "Stocks" in the submenu "Asset Class" of the bond position
- **THEN** the filter "Asset class" reads "Show All"
- **AND** the list shows 3 positions and no line about a filter

## REMOVED Requirements

### Requirement: Asset class tag

**Reason**: The asset class shows as a ribbon in the first column, in the color of the class, as the category of a transaction does (owner decision of 27 November 2026).

**Migration**: See "Asset class ribbon".

### Requirement: Day of an old quote

**Reason**: Every row shows the day of its last quote in the first column, and an old day shows in the warning color (owner decision of 27 November 2026).

**Migration**: See "Day of the last quote".
