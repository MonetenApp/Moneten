# Spec Delta

## Purpose

A split divides one transaction into parts so that each part can have its own category. This capability defines how the user splits a transaction, how the parts stay equal to the original amount, how parts count in other functions, and how a split is undone.

## ADDED Requirements

### Requirement: Split off an amount

The app SHALL open a split window with "Split Transaction" and then "Split Amount..." for one selected transaction. The user enters the amount to split off. The app replaces the row by two parts, one with the entered amount and one with the remainder.

#### Scenario: Household goods on a grocery receipt

- **GIVEN** a booked transaction of -80,00 € to "REWE Markt GmbH" in "Groceries"
- **WHEN** the user chooses "Split Amount...", enters 25,00, and confirms
- **THEN** the list shows one part of -25,00 € and one part of -55,00 € in place of the original row

#### Scenario: Cancel

- **WHEN** the user cancels the split window
- **THEN** the transaction is unchanged

### Requirement: The parts add up to the original amount

The app SHALL compute the remainder so that all parts of a split add up to the amount of the original transaction. The split window shows the resulting remainder before the user confirms. The app refuses an amount of zero and text that is not a number.

#### Scenario: Remainder is shown

- **GIVEN** a transaction of -80,00 €
- **WHEN** the user enters 25,00 in the split window
- **THEN** the window shows that the remainder is -55,00 €

#### Scenario: Amount of zero

- **WHEN** the user enters 0,00 and confirms
- **THEN** the app does not split and marks the amount field

### Requirement: Several parts in one pass

The app SHALL split the remainder again when the user clicks "Next Split" in the split window, so that one pass can create any number of parts.

#### Scenario: Three parts

- **GIVEN** a transaction of -80,00 €
- **WHEN** the user enters 25,00, clicks "Next Split", enters 15,00, and confirms
- **THEN** the list shows parts of -25,00 €, -15,00 €, and -40,00 €

### Requirement: Parts with the opposite sign

The app SHALL accept a part whose sign is opposite to the original transaction. The remainder grows by that amount.

#### Scenario: Deposit refund inside a purchase

- **GIVEN** a transaction of -80,00 €
- **WHEN** the user splits off +5,00
- **THEN** the list shows one part of 5,00 € and one part of -85,00 €

### Requirement: Each part has its own category and comment

The app SHALL let the user assign a category and write a comment for each part, in the same way as for a whole transaction. A new part starts in the category of the original transaction. Every part keeps the date, the counterparty, and the purpose of the original.

#### Scenario: Different categories

- **GIVEN** the parts -25,00 € and -55,00 € of a transaction that was in "Groceries"
- **WHEN** the user assigns the part of -25,00 € to "Household"
- **THEN** "Household" contains -25,00 € and "Groceries" contains -55,00 € of that receipt

### Requirement: Parts are recognizable

The app SHALL mark each part of a split in the list and show the amount of the original transaction with it.

#### Scenario: Look at a part

- **GIVEN** a transaction of -80,00 € split into -25,00 € and -55,00 €
- **WHEN** the user looks at the part of -25,00 €
- **THEN** the row is marked as a part and names the original amount of -80,00 €

### Requirement: Split off value added tax

The app SHALL offer one entry "Split" with the rate and "VAT" for each rate in the list of VAT rates. The entry divides the transaction into a net part and a tax part. The transaction amount is the gross amount. The net part is the gross amount multiplied by 100 and divided by 100 plus the rate, cut toward zero at the cent. The tax part is the gross amount minus the net part, so it takes the fraction of a cent that the net part leaves.

#### Scenario: Nineteen percent

- **GIVEN** a transaction of -119,00 €
- **WHEN** the user chooses "Split 19% VAT"
- **THEN** the list shows a net part of -100,00 € and a tax part of -19,00 €
- **AND** the parts carry the labels for net and for 19% VAT

#### Scenario: The net part is cut toward zero

- **GIVEN** a transaction of -10,00 €
- **WHEN** the user chooses "Split 7% VAT"
- **THEN** the net part is -9,34 € and the tax part is -0,66 €

#### Scenario: A refund is cut toward zero as well

- **GIVEN** a transaction of 10,00 €
- **WHEN** the user chooses "Split 7% VAT"
- **THEN** the net part is 9,34 € and the tax part is 0,66 €

### Requirement: The list of VAT rates can be changed

The app SHALL start with the rates 19 and 7 percent and let the user add, change, and remove rates in the settings. The context menu shows one entry for each rate in the list.

#### Scenario: Add a rate

- **WHEN** the user adds the rate 20 to the list
- **THEN** the submenu "Split Transaction" contains "Split 20% VAT"

#### Scenario: Empty list

- **WHEN** the user removes all rates
- **THEN** the submenu contains no tax entries and still contains "Split Amount..."

### Requirement: Only booked transactions can be split

The app SHALL refuse to split a pending transaction. It tells the user to wait until the bank has booked the transaction.

#### Scenario: Pending card payment

- **GIVEN** a pending transaction
- **WHEN** the user chooses "Split Amount..."
- **THEN** the app says that only booked transactions can be split and changes nothing

### Requirement: Parts count in their own category

The app SHALL count each part with its own amount and category in search results, sums, category views, charts, budgets, reports, printouts, and exports. The original amount is never counted in addition to its parts.

#### Scenario: Category sums

- **GIVEN** a transaction of -80,00 € split into -25,00 € in "Household" and -55,00 € in "Groceries"
- **WHEN** the user opens the pie chart for the month
- **THEN** "Household" grows by 25,00 € and "Groceries" by 55,00 €, and no category counts 80,00 €

#### Scenario: Account balance

- **WHEN** a transaction of an account is split
- **THEN** the balance and the daily balance of the account are the same as before

### Requirement: A refresh does not undo or duplicate a split

The app SHALL recognize the original transaction of a split when the bank delivers it again. The app adds no new row for it and leaves the parts as they are.

#### Scenario: Refresh after a split

- **GIVEN** a split transaction of -80,00 € from last week
- **WHEN** a refresh delivers the transactions of the last 90 days again
- **THEN** the list still shows the two parts and no third row of -80,00 €

### Requirement: Rules leave parts alone

The app SHALL keep the category of each part when categorization rules run or when a changed rule is applied to all transactions.

#### Scenario: Apply to all

- **GIVEN** a part in "Household" whose purpose matches the rule of "Groceries"
- **WHEN** the user applies the rule of "Groceries" to all transactions
- **THEN** the part stays in "Household"

### Requirement: Undo a split

The app SHALL replace all parts of a split by the original transaction with "Undo Split Transaction..." after the user confirms. The confirmation says that the parts cannot be restored. The original returns with the category and the comment that it had before the split.

#### Scenario: Confirm

- **GIVEN** the parts -25,00 € and -55,00 € of a transaction that was in "Groceries"
- **WHEN** the user chooses "Undo Split Transaction..." on one part and confirms
- **THEN** the list shows one transaction of -80,00 € in "Groceries"

#### Scenario: Not a split

- **WHEN** the user opens "Split Transaction" on a transaction that is not a part
- **THEN** "Undo Split Transaction..." is disabled

### Requirement: A part cannot be deleted alone

The app SHALL refuse to delete a single part of a split. It tells the user to undo the split first.

#### Scenario: Delete a part

- **GIVEN** a part of a split is selected in the view of a single account
- **WHEN** the user chooses "Delete Transaction..."
- **THEN** the app does not delete the part and names "Undo Split Transaction..." as the way to go

### Requirement: Split a batch payment into its positions

The app SHALL replace the row of a batch payment by one part for each position with "Split from Batch Payment", when the app knows the positions of that batch. Each part takes the recipient or debtor, the amount, and the purpose of its position. The command is disabled when the positions are not known.

#### Scenario: Batch transfer sent with the app

- **GIVEN** a booked transaction of -1.500,00 € for a batch transfer with 3 positions of -500,00 € that the app sent
- **WHEN** the user chooses "Split from Batch Payment"
- **THEN** the list shows 3 parts of -500,00 €, each with the recipient and the purpose of its position

#### Scenario: Unknown batch

- **WHEN** the user opens "Split Transaction" on a transaction whose positions the app does not know
- **THEN** "Split from Batch Payment" is disabled
