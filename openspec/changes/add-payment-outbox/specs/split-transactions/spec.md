## ADDED Requirements

### Requirement: Split a batch payment into its positions

The app SHALL replace the row of a batch payment by one part for each position with "Split from Batch Payment", when the app knows the positions of that batch. Each part takes the recipient or debtor, the amount, and the purpose of its position.

#### Scenario: Batch transfer sent with the app

- **GIVEN** a booked transaction of -1.500,00 € for a batch transfer with 3 positions of -500,00 € that the app sent
- **WHEN** the user chooses "Split from Batch Payment"
- **THEN** the list shows 3 parts of -500,00 €, each with the recipient and the purpose of its position
