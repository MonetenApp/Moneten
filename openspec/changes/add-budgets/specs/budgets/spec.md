# Spec Delta

## Purpose

A budget is the amount that the user plans for a category in a period. This capability defines how the user sets a budget, how the app computes what is used and what is available, and where the app shows the result.

## ADDED Requirements

### Requirement: Set a budget for a category

The app SHALL let the user set a budget in the settings of a category with an amount and a period. The amount is in the currency of the category and must be above zero. A category has no budget until the user sets one.

#### Scenario: Monthly budget

- **GIVEN** the category "Groceries" with no budget
- **WHEN** the user opens its settings, enters the budget 400,00 with the period "per month", and closes the settings
- **THEN** "Groceries" has a budget of 400,00 € per month

#### Scenario: Amount of zero

- **WHEN** the user enters the budget 0,00 and closes the settings
- **THEN** the app marks the amount field and stores no budget

### Requirement: Budget periods

The app SHALL offer the periods "per month", "per quarter", "per year", and "in total". A month, a quarter, and a year are calendar periods. "in total" covers all transactions of the category with no start and no end.

#### Scenario: Quarter

- **GIVEN** a budget of 300,00 € per quarter and today is 09.11.2026
- **WHEN** the app computes the used budget
- **THEN** it counts the transactions from 01.10.2026 to 31.12.2026

#### Scenario: Whole time

- **GIVEN** the category "Kitchen renovation" with a budget of 8.000,00 € in total
- **WHEN** the app computes the used budget
- **THEN** it counts every transaction of the category

### Requirement: Remove a budget

The app SHALL let the user remove the budget of a category in its settings. The transactions and the category stay as they are.

#### Scenario: Remove

- **GIVEN** "Groceries" with a budget of 400,00 € per month
- **WHEN** the user removes the budget in the settings
- **THEN** the category view shows "(no budget set)"

### Requirement: Used and available budget

The app SHALL compute the used budget as the net sum of the transactions of the category in the current period. A withdrawal uses the budget, and a deposit gives it back. The available budget is the budget minus the used budget.

#### Scenario: Partly used

- **GIVEN** a budget of 400,00 € per month and withdrawals of 250,00 € in the current month
- **WHEN** the app computes the budget
- **THEN** the used budget is 250,00 € and the available budget is 150,00 €

#### Scenario: Refund

- **GIVEN** a budget of 400,00 € per month, withdrawals of 250,00 €, and a refund of 30,00 € in the current month
- **WHEN** the app computes the budget
- **THEN** the used budget is 220,00 € and the available budget is 180,00 €

### Requirement: Budget in the category view

The app SHALL show the budget, the used amount, and the amount under "Available budget" in the view of a category with a budget. A category without a budget shows "(no budget set)".

#### Scenario: Category with a budget

- **GIVEN** "Groceries" with a budget of 400,00 € per month and 250,00 € used
- **WHEN** the user selects "Groceries"
- **THEN** the view shows the budget of 400,00 €, the used 250,00 €, and "Available budget" with 150,00 €

### Requirement: Overspent budget

The app SHALL show "Overspent" with the exceeding amount when the used budget is larger than the budget. The app keeps showing the budget and the used amount.

#### Scenario: Over the limit

- **GIVEN** a budget of 400,00 € per month and 460,00 € used
- **WHEN** the user selects the category
- **THEN** the view shows "Overspent" with 60,00 €

### Requirement: Available budget in the sidebar

The app SHALL add the value "Available budget" to "Display in sidebar" for a category that has a budget. With this value the sidebar shows the available budget of the current period next to the category, and it marks an overspent budget.

#### Scenario: Sidebar value

- **GIVEN** "Groceries" with 150,00 € available and "Display in sidebar" set to "Available budget"
- **WHEN** the user looks at the sidebar
- **THEN** it shows 150,00 € next to "Groceries"

#### Scenario: Budget removed

- **GIVEN** "Display in sidebar" is "Available budget"
- **WHEN** the user removes the budget of the category
- **THEN** "Display in sidebar" returns to "No amount"

### Requirement: Budget for a category group

The app SHALL let the user set a budget for a category group in the same way as for a category. The used budget of a group counts the transactions of every category below it.

#### Scenario: Group budget

- **GIVEN** the group "Leisure" with a budget of 300,00 € per month, 120,00 € used in "Restaurants", and 90,00 € used in "Cinema"
- **WHEN** the user selects "Leisure"
- **THEN** the view shows 210,00 € used and 90,00 € available

#### Scenario: Budget on a group and on one of its categories

- **GIVEN** "Leisure" with 300,00 € per month and "Restaurants" inside it with 100,00 € per month
- **WHEN** 120,00 € is spent in "Restaurants"
- **THEN** "Restaurants" is overspent by 20,00 € and "Leisure" has 180,00 € available

### Requirement: Budget in the bar chart

The app SHALL draw the budget as a line across the bars in the bar chart of a category or category group with a budget. The line shows the budget for one bar of the chosen view. A monthly budget counts three times in the quarterly view and twelve times in the yearly view. A budget whose period is longer than one bar is not drawn.

#### Scenario: Monthly view

- **GIVEN** "Groceries" with a budget of 400,00 € per month
- **WHEN** the user opens the bar chart in the "Monthly view"
- **THEN** a line marks 400,00 € and each month above the line stands out

#### Scenario: Quarterly view

- **WHEN** the user switches to the "Quarterly view"
- **THEN** the line marks 1.200,00 €

#### Scenario: Yearly budget in the monthly view

- **GIVEN** a budget of 2.400,00 € per year
- **WHEN** the user opens the "Monthly view"
- **THEN** the chart shows no budget line

### Requirement: No carry-over between periods

The app SHALL start each new period with the full budget. An unused or an overspent amount of an earlier period does not change the budget of the next one.

#### Scenario: New month

- **GIVEN** a budget of 400,00 € per month with 100,00 € left at the end of October
- **WHEN** November starts
- **THEN** the available budget is 400,00 €

### Requirement: Budget for income

The app SHALL treat the budget of a category whose transactions in the period add up to a deposit as a target. It shows the received amount and how much of the target is still open, and it does not show "Overspent" when the target is exceeded.

#### Scenario: Expected rent income

- **GIVEN** the category "Rent income" with a budget of 1.500,00 € per month and deposits of 900,00 € in the current month
- **WHEN** the user selects the category
- **THEN** the view shows 900,00 € received and 600,00 € still open

### Requirement: Other currencies do not count in a budget

The app SHALL count only transactions in the currency of the category in its budget. A transaction in another currency stays in the category and does not change the used budget.

#### Scenario: Other currency

- **GIVEN** "Travel" with the currency euro, a budget of 500,00 € per month, and a transaction of -50,00 USD
- **WHEN** the app computes the budget of "Travel"
- **THEN** the USD transaction does not change the used budget
