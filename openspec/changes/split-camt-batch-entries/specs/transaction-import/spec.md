# Spec Delta

## ADDED Requirements

### Requirement: Parts of a CAMT batch entry

The app SHALL import a CAMT entry with two or more transaction details, each with an amount, whose amounts add up to the amount of the entry, as one transaction with one part per detail. Each part has the amount, the counterparty name, and the purpose of its detail, in the order of the file.

#### Scenario: Rent and electricity in one batch

- **GIVEN** a camt.053 entry of -150,00 € on 3 November 2026 with two transaction details, -100,00 € to "Vermieter A" with the purpose "Miete November" and -50,00 € to "Vermieter B" with the purpose "Miete Garage"
- **WHEN** the user imports the file
- **THEN** the account has one transaction of -150,00 € on 3 November 2026 with two parts, -100,00 € to "Vermieter A" with the purpose "Miete November" and -50,00 € to "Vermieter B" with the purpose "Miete Garage"
- **AND** the balance of the account drops by 150,00 €

#### Scenario: Details that do not add up

- **GIVEN** a camt.053 entry of -150,00 € with two transaction details of -100,00 € and -40,00 €
- **WHEN** the user imports the file
- **THEN** the account has one transaction of -150,00 € without parts

#### Scenario: Details without amounts

- **GIVEN** a camt.053 entry of -150,00 € with two transaction details without an amount
- **WHEN** the user imports the file
- **THEN** the account has one transaction of -150,00 € without parts

### Requirement: Rules and search for the parts of a batch

The app SHALL run the categorization rules on each part of a CAMT batch entry when the parts are created, with the counterparty name and the purpose of the part, and SHALL find a part by its counterparty name and purpose in the search.

#### Scenario: A rule for one landlord

- **GIVEN** the rule `name:"Vermieter A"` for the category "Miete" and the batch of the scenario "Rent and electricity in one batch"
- **WHEN** the user imports the file
- **THEN** the part of -100,00 € is in "Miete" and the part of -50,00 € has no category

#### Scenario: Search for a payment in a batch

- **GIVEN** the imported batch of the scenario "Rent and electricity in one batch"
- **WHEN** the user types "Garage" in the search field
- **THEN** the list shows the part of -50,00 € to "Vermieter B"

### Requirement: A batch counts once

The app SHALL count a CAMT batch entry with parts once when a refresh or another file delivers the same booking as one transaction with the amount of the entry, in either order. When the transaction with the total is stored first and has no parts, the import of the CAMT file gives it the parts and changes none of its other fields.

#### Scenario: Parts first, total later

- **GIVEN** the account holds the batch of -150,00 € on 3 November 2026 with its two parts from a camt.053 file
- **WHEN** a refresh delivers one booked transaction of -150,00 € on 3 November 2026 with the same purpose
- **THEN** the account still has one transaction of -150,00 € with two parts, and the balance dropped by 150,00 € once

#### Scenario: Total first, parts later

- **GIVEN** a refresh stored one booked transaction of -150,00 € on 3 November 2026 with the purpose "Miete November Miete Garage" and the comment "November"
- **WHEN** the user imports the camt.053 file with the batch of the scenario "Rent and electricity in one batch"
- **THEN** the account has one transaction of -150,00 € with the comment "November" and two parts of -100,00 € and -50,00 €
- **AND** the result message says "Imported no new transactions." and "Split one transaction into its payments."

#### Scenario: Total already split by the user

- **GIVEN** the stored transaction of -150,00 € that the user split by hand into -120,00 € and -30,00 €
- **WHEN** the user imports the camt.053 file with the batch
- **THEN** the transaction keeps the parts of the user and the import skips the entry
