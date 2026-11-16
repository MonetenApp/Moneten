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

#### Scenario: Whole amount

- **GIVEN** a transaction of -80,00 €
- **WHEN** the user enters 80,00 and confirms
- **THEN** the app does not split and marks the amount field

#### Scenario: A zero transaction has opposite parts

- **GIVEN** a booked transaction of 0,00 €
- **WHEN** the user splits off +5,00
- **THEN** the list shows parts of 5,00 € and -5,00 €

#### Scenario: A part in another currency is unbalanced

- **GIVEN** a transaction of -80,00 €
- **WHEN** a split contains a part of -25,00 USD
- **THEN** the app refuses the split as unbalanced and changes nothing

#### Scenario: Amount text has at most 38 digits

- **GIVEN** a transaction of -80,00 €
- **WHEN** the amount text is "1," followed by 37 zeros
- **THEN** the entered part is -1,00 €
- **AND** adding one more zero makes the text unreadable

### Requirement: Several parts in one pass

The app SHALL split the remainder again when the user clicks "Next Split" in the split window, so that one pass can create any number of parts.

#### Scenario: Three parts

- **GIVEN** a transaction of -80,00 €
- **WHEN** the user enters 25,00, clicks "Next Split", enters 15,00, and confirms
- **THEN** the list shows parts of -25,00 €, -15,00 €, and -40,00 €

#### Scenario: Confirm after keeping an amount

- **GIVEN** a transaction of -89,00 €
- **WHEN** the user enters 25,00, clicks "Next Split", and confirms with the amount field empty
- **THEN** the list shows parts of -25,00 € and -64,00 €

#### Scenario: An empty first amount

- **WHEN** the user opens the split window and leaves the amount field empty
- **THEN** the confirm button is disabled

#### Scenario: An unsigned next amount follows the remainder

- **GIVEN** a transaction of -80,00 €
- **WHEN** the user enters 100,00, clicks "Next Split", enters 5,00, and confirms
- **THEN** the list shows parts of -100,00 €, 5,00 €, and 15,00 €

#### Scenario: An explicit next sign stays

- **GIVEN** a transaction of -80,00 €
- **WHEN** the user enters 100,00, clicks "Next Split", enters -5,00, and confirms
- **THEN** the list shows parts of -100,00 €, -5,00 €, and 25,00 €

#### Scenario: Split a part again

- **GIVEN** the parts -25,00 € and -55,00 € of a transaction of -80,00 €
- **WHEN** the user splits 15,00 off the part of -55,00 €
- **THEN** the list shows parts of -25,00 €, -15,00 €, and -40,00 €
- **AND** "Undo Split Transaction..." brings back one transaction of -80,00 €

### Requirement: Parts with the opposite sign

The app SHALL accept a part whose sign is opposite to the original transaction. The remainder grows by that amount.

#### Scenario: Deposit refund inside a purchase

- **GIVEN** a transaction of -80,00 €
- **WHEN** the user splits off +5,00
- **THEN** the list shows one part of 5,00 € and one part of -85,00 €

### Requirement: Each part has its own category and comment

The app SHALL let the user assign a category and write a comment for each part, in the same way as for a whole transaction. A new part starts in the category of the original transaction. Every part keeps the date, the counterparty, and the purpose of the original. If a refresh removes a part while its edit window is open, confirming closes the window without saving.

#### Scenario: Different categories

- **GIVEN** the parts -25,00 € and -55,00 € of a transaction that was in "Groceries"
- **WHEN** the user assigns the part of -25,00 € to "Household"
- **THEN** "Household" contains -25,00 € and "Groceries" contains -55,00 € of that receipt

#### Scenario: The category picker keeps account restrictions for parts

- **GIVEN** a -80,00 € transaction of account "Private" split into -25,00 € and -55,00 €
- **AND** "Groceries" has no account restriction, "Household" is restricted to "Private", and "Office" is restricted to account "Business"
- **WHEN** the user selects either part or both and opens "Assign Category"
- **THEN** the picker offers "Groceries" and "Household" and does not offer "Office"

#### Scenario: A correction removes the part being edited

- **GIVEN** a booked "TX-1" of -80,00 € split into -25,00 € and -55,00 €, and the edit window is open for the part of -25,00 €
- **WHEN** a refresh delivers a booked "TX-1" of -85,00 € and the user confirms the old edit window
- **THEN** the window closes without saving the edit or adding a transaction
- **AND** the list still shows only the corrected original of -85,00 €

#### Scenario: An unchanged editor runs no rule

- **GIVEN** an uncategorized -30,00 € transaction whose purpose matches the rule of "Groceries"
- **WHEN** the user opens "Edit Transaction..." and confirms without changing a field
- **THEN** the transaction stays uncategorized and no data changes

### Requirement: The checkmark belongs to the whole transaction

The app SHALL show one checkmark for all parts of a split transaction and set it on all of them when the user checks one part.

#### Scenario: Check a part

- **GIVEN** the parts -25,00 € and -55,00 € of a transaction of -80,00 €
- **WHEN** the user checks the part of -25,00 €
- **THEN** the part of -55,00 € shows the checkmark as well

### Requirement: Parts are recognizable

The app SHALL mark each part of a split in the list and show the amount of the original transaction with it.

#### Scenario: Look at a part

- **GIVEN** a transaction of -80,00 € split into -25,00 € and -55,00 €
- **WHEN** the user looks at the part of -25,00 €
- **THEN** the row is marked as a part and names the original amount of -80,00 €

### Requirement: Split off value added tax

The app SHALL offer one entry "Split" with the rate and "VAT" for each rate in the list of VAT rates. The entry divides the transaction into a net part and a tax part. The transaction amount is the gross amount. The net part is the gross amount multiplied by 100 and divided by 100 plus the rate, cut toward zero at the smallest unit of the transaction currency. The tax part is the gross amount minus the net part, so it takes the remainder.

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

#### Scenario: VAT in a currency without decimals

- **GIVEN** a transaction of -1.000 JPY
- **WHEN** the user chooses "Split 7% VAT"
- **THEN** the net part is -934 JPY and the tax part is -66 JPY

#### Scenario: VAT in a currency with three decimals

- **GIVEN** a transaction of -10,000 KWD
- **WHEN** the user chooses "Split 7% VAT"
- **THEN** the net part is -9,345 KWD and the tax part is -0,655 KWD

#### Scenario: Split a VAT part

- **GIVEN** the net part of -100,00 € and the tax part of -19,00 € of a transaction of -119,00 €
- **WHEN** the user splits 50,00 off the net part
- **THEN** the list shows two parts of -50,00 € without the label for net
- **AND** the tax part keeps the label for 19% VAT

### Requirement: The list of VAT rates can be changed

The app SHALL start with the rates 19 and 7 percent and let the user add, change, and remove rates in the settings. The context menu shows one entry for each rate in the list.

#### Scenario: Add a rate

- **WHEN** the user adds the rate 20 to the list
- **THEN** the submenu "Split Transaction" contains "Split 20% VAT"

#### Scenario: Empty list

- **WHEN** the user removes all rates
- **THEN** the submenu contains no tax entries and still contains "Split Amount..."

#### Scenario: Change a rate without changing the order

- **GIVEN** the list contains 19, 7, and 20 percent in that order
- **WHEN** the user changes 7 to 8,1
- **THEN** the settings show 19%, 8.1%, and 20% in that order
- **AND** the submenu shows the same order after the app restarts

#### Scenario: Refuse an unreadable rate

- **GIVEN** the list contains 19 and 7 percent
- **WHEN** the user enters "7,125" and saves the rate
- **THEN** the settings say "Enter a rate above zero with up to two decimal places."
- **AND** the list stays at 19 and 7 percent

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

#### Scenario: Sidebar amounts count the parts

- **GIVEN** a transaction of -100,00 € on 02.11.2026 in "Drinks", split into -60,00 € in "Groceries" and -40,00 € in "Household"
- **AND** these categories show "Total sum" and contain no other transactions
- **WHEN** the user reads the sidebar on 15.11.2026
- **THEN** "Groceries" shows -60,00 € and "Household" shows -40,00 €
- **AND** "Drinks" shows no amount from the original

#### Scenario: Account balance

- **WHEN** a transaction of an account is split
- **THEN** the balance and the daily balance of the account are the same as before

#### Scenario: Search for the original amount

- **GIVEN** a transaction of -80,00 € split into -25,00 € and -55,00 €
- **WHEN** the user searches for "-80,00"
- **THEN** the list shows both parts

#### Scenario: CSV exports the parts

- **GIVEN** a transaction of -80,00 € split into -25,00 € in "Household" with comment "Detergent" and -55,00 € in "Groceries"
- **WHEN** the user exports the account as CSV
- **THEN** the CSV contains the two parts with their amounts, categories, and comments
- **AND** it contains no extra row of -80,00 €

### Requirement: A complete export preserves splits and review reasons

The app SHALL preserve the original transactions, their split parts, and their review reasons through "Export All Data..." and "Import All Data..." in format version 2. Each part keeps its identifier, order, amount, category, comment, and VAT data. Import still accepts version 1, with `needsReview` true read as the review reason for an unclear booking and false read as no review.

#### Scenario: A split survives a complete export and import

- **GIVEN** a booked -119,00 € transaction in "Groceries" with comment "Invoice" and review for an unclear booking
- **AND** its parts are -100,00 € in "Household" with comment "Net goods" and the net label at 19 %, and -19,00 € in "Drinks" with comment "Tax" and the tax label at 19 %
- **AND** a second transaction of -85,00 € has the review reason for an undone split
- **WHEN** the user exports all data and imports the version-2 file into an empty database
- **THEN** the original and both parts keep their identifiers, links, order, literal amounts, categories, comments, and VAT labels
- **AND** both transactions keep their review reasons
- **AND** the account balance stays unchanged and no part becomes a separate stored transaction

#### Scenario: A version-1 review mark still imports

- **GIVEN** a version-1 export with a pending -20,00 € transaction whose `needsReview` is true and a booked -30,00 € transaction whose `needsReview` is false
- **WHEN** the user imports all data into an empty database
- **THEN** the pending -20,00 € transaction has the review reason for an unclear booking
- **AND** the booked -30,00 € transaction has no review mark
- **AND** neither transaction has split parts

#### Scenario: An invalid split import changes nothing

- **GIVEN** a version-2 export whose -119,00 € transaction has parts of -100,00 € and -18,00 €
- **WHEN** the user imports all data into an empty database
- **THEN** the app refuses the file and leaves the database unchanged

### Requirement: A refresh keeps a split while its amount stays

The app SHALL recognize the original transaction of a split when the bank delivers it again, and add no new row for it. When the bank delivers the booked original with the same amount and currency, the app keeps the parts. A pending delivery under its ID keeps the stored original booked and leaves its bank fields and parts unchanged, even with another amount or currency.

#### Scenario: Refresh after a split

- **GIVEN** a split transaction of -80,00 € from last week
- **WHEN** a refresh delivers the transactions of the last 90 days again
- **THEN** the list still shows the two parts and no third row of -80,00 €

#### Scenario: The bank changes the purpose of a split transaction

- **GIVEN** a transaction of -80,00 € with the ID "TX-1", split into -25,00 € and -55,00 €
- **WHEN** a refresh delivers "TX-1" with the amount -80,00 € and the purpose "REWE SAGT DANKE"
- **THEN** the list shows the parts -25,00 € and -55,00 €, each with the purpose "REWE SAGT DANKE"

#### Scenario: A pending delivery leaves a split booked

- **GIVEN** a booked transaction of -80,00 € with the ID "TX-1", split into -25,00 € and -55,00 €
- **WHEN** a refresh delivers a pending "TX-1" with -85,00 € or -80,00 USD
- **THEN** the original stays booked at -80,00 € and the list keeps the parts -25,00 € and -55,00 €
- **AND** the transaction gets no review mark

### Requirement: A corrected amount undoes a split

The app SHALL undo the split when a source that gives IDs delivers the booked original under its ID with another amount or currency. A pending delivery leaves the split unchanged. It updates the whole transaction as the requirement "Update a transaction that the source changed" of `account-refresh` says, and marks it for review with the note "The bank changed the amount; the split was undone."

#### Scenario: The bank corrects the amount of a split transaction

- **GIVEN** a transaction of -80,00 € with the ID "TX-1" in "Groceries" assigned by hand, with the comment "Weekly shop" and a checkmark, split into -25,00 € in "Household" and -55,00 € in "Groceries"
- **WHEN** a refresh delivers "TX-1" with the amount -85,00 €
- **THEN** the list shows one transaction of -85,00 € in "Groceries" and no parts
- **AND** the transaction keeps the comment "Weekly shop" and its checkmark
- **AND** the transaction is marked for review with the note "The bank changed the amount; the split was undone."

#### Scenario: The bank corrects only the currency

- **GIVEN** a booked transaction of -80,00 € with the ID "TX-1" in "Groceries" assigned by hand, split into -25,00 € and -55,00 €
- **WHEN** a refresh delivers a booked "TX-1" with -80,00 USD
- **THEN** the list shows one transaction of -80,00 USD in "Groceries" and no parts
- **AND** the transaction is marked for review with the note "The bank changed the amount; the split was undone."

#### Scenario: Rules assign the corrected original again

- **GIVEN** a booked transaction of -80,00 € with the ID "TX-1" in "Groceries" assigned by a rule, split into -25,00 € and -55,00 €
- **AND** the purpose "REWE SAGT DANKE" matches the first rule of "Drinks"
- **WHEN** a refresh delivers a booked "TX-1" with -85,00 € and the purpose "REWE SAGT DANKE"
- **THEN** the list shows one transaction of -85,00 € in "Drinks" and no parts
- **AND** the transaction is marked for review

#### Scenario: Checking the corrected original clears its review

- **GIVEN** the booked "TX-1" of -85,00 € has a checkmark and the review note for an undone split
- **WHEN** the user marks "TX-1" as checked
- **THEN** the checkmark stays and the review mark and its note disappear

#### Scenario: A correction replaces an earlier review reason

- **GIVEN** a booked -80,00 € transaction with the review reason for an unclear booking and parts of -25,00 € and -55,00 €
- **WHEN** the bank delivers its source ID with the booked amount -85,00 €
- **THEN** the split is undone and the review reason is replaced by the reason for an undone split

### Requirement: Rules leave parts alone

The app SHALL leave split originals and their parts unchanged when a changed rule is applied to existing transactions. The number of matching transactions excludes split originals and parts.

#### Scenario: Apply to all

- **GIVEN** a -80,00 € transaction in "Groceries" split into -25,00 € in "Household" and -55,00 € in "Groceries"
- **AND** its purpose matches the rule of "Drinks"
- **WHEN** the user applies the rule of "Drinks" to all transactions
- **THEN** the original stays in "Groceries" and the parts stay in "Household" and "Groceries"
- **AND** the count of matching transactions excludes the split

#### Scenario: Apply only to uncategorized transactions

- **GIVEN** an uncategorized -80,00 € transaction with two parts whose purpose matches the rule of "Drinks"
- **WHEN** the user applies that rule only to not yet categorized transactions
- **THEN** the original and parts stay unchanged

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
