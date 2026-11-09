# Spec Delta

## ADDED Requirements

### Requirement: Suggestions from transfers and templates

The app SHALL also take recipient suggestions from earlier transfers and from transfer templates. When two entries have the same name with different IBANs, or the same IBAN with different spellings of the name, the app suggests only the newest entry.

#### Scenario: Recipient changed the bank

- **GIVEN** a transfer to "Max Mustermann" with the IBAN DE89370400440532013000 from 2024 and one with the IBAN DE02120300000000202051 from 2026
- **WHEN** the user types "Max" in "Recipient"
- **THEN** the app suggests "Max Mustermann" once, with the IBAN DE02120300000000202051

#### Scenario: Suggestion from a template

- **GIVEN** a transfer template "Miete" for "Erika Mustermann"
- **WHEN** the user types "Erika" in "Recipient"
- **THEN** the app suggests "Erika Mustermann" with the IBAN of the template

### Requirement: Recently used recipients

The app SHALL list the ten recipients of the most recent transfers under "Recently used" in the "Action" menu. Choosing an entry fills the name, the IBAN, and the BIC.

#### Scenario: Pick a recent recipient

- **GIVEN** the user sent a transfer to "Stadtwerke Musterstadt" last week
- **WHEN** the user opens "Action" and chooses "Stadtwerke Musterstadt" under "Recently used"
- **THEN** the form shows the name, IBAN, and BIC of that recipient
- **AND** the amount and the purpose stay empty

### Requirement: Insert bank details from the pasteboard

The app SHALL offer "Insert from Pasteboard" in the "Action" menu. The app searches the copied text for a recipient name, an IBAN, a BIC, an amount, and a purpose, and it fills every field that it finds. The user checks the fields before sending, and the normal field checks apply.

#### Scenario: Invoice footer

- **GIVEN** the pasteboard holds "Stadtwerke Musterstadt, IBAN: DE02 1203 0000 0000 2020 51, BIC: BYLADEM1001, Betrag: 89,00 EUR, Verwendungszweck: Rechnung 4711"
- **WHEN** the user chooses "Insert from Pasteboard"
- **THEN** the form shows the recipient "Stadtwerke Musterstadt", the IBAN DE02120300000000202051, the BIC BYLADEM1001, the amount 89,00 €, and the purpose "Rechnung 4711"

#### Scenario: Only an IBAN

- **GIVEN** the pasteboard holds "DE02120300000000202051"
- **WHEN** the user chooses "Insert from Pasteboard"
- **THEN** the form shows the IBAN and the BIC that belongs to it
- **AND** the other fields keep their content

### Requirement: Read a GiroCode from the pasteboard

The app SHALL read the text of a GiroCode from the pasteboard. This is the text of the QR code on an invoice, and it starts with the line "BCD". The app fills the recipient, the IBAN, the BIC when present, the amount when it is in euro, and the purpose.

#### Scenario: Code scanned with an iPhone

- **GIVEN** the user copied a GiroCode on an iPhone and the text reached the Mac through the shared clipboard
- **WHEN** the user chooses "Insert from Pasteboard" in a new transfer
- **THEN** the form shows the recipient, the IBAN, the amount, and the purpose from the code

#### Scenario: Code without an amount

- **GIVEN** the GiroCode holds no amount
- **WHEN** the user inserts it
- **THEN** the amount field stays empty and the other fields are filled

### Requirement: Explain a failed insert

The app SHALL show a message when the pasteboard holds no IBAN, and a different message when macOS denied the app access to the pasteboard. The second message names the place in the system settings where the user can allow the access.

#### Scenario: Nothing usable copied

- **GIVEN** the pasteboard holds the text "Vielen Dank für Ihre Bestellung"
- **WHEN** the user chooses "Insert from Pasteboard"
- **THEN** the app says that it could not find an IBAN in the pasteboard and asks the user to copy the payment information first

#### Scenario: Access denied

- **GIVEN** the user denied the app access to the pasteboard
- **WHEN** the user chooses "Insert from Pasteboard"
- **THEN** the app explains that access was denied and that the privacy settings of macOS can change this

### Requirement: Open a payment window from a link

The app SHALL handle links with the URL schemes `bank` and `payto`. A link opens the payment window filled with the recipient name, IBAN, BIC, amount, and purpose from the link. The app unlocks first when it is locked. A link never sends a payment.

#### Scenario: payto link

- **WHEN** the user opens the link `payto://iban/DE02120300000000202051?amount=EUR:89.00&receiver-name=Stadtwerke%20Musterstadt&message=Rechnung%204711`
- **THEN** the payment window opens with the recipient "Stadtwerke Musterstadt", the IBAN DE02120300000000202051, the amount 89,00 €, and the purpose "Rechnung 4711"
- **AND** the transfer waits for the user to click "Next"

#### Scenario: BezahlCode link

- **WHEN** the user opens the link `bank://singlepaymentsepa?name=Stadtwerke%20Musterstadt&iban=DE02120300000000202051&bic=BYLADEM1001&amount=89,00&reason=Rechnung%204711`
- **THEN** the payment window opens with these values

#### Scenario: Link with an invalid IBAN

- **WHEN** the user opens a `payto` link with the IBAN DE02120300000000202052
- **THEN** the payment window opens and the IBAN field shows the checksum error

### Requirement: Deduce a cash discount

The app SHALL offer "Deduce cash discount" in the gear menu of the payment window. The user enters a percentage or a discount amount, and the app shows the resulting amount and the resulting discount before it changes the amount field. The calculator needs a full amount in the payment window first. The user can restore the previous amount.

#### Scenario: Two percent

- **GIVEN** the amount field holds 1.000,00 €
- **WHEN** the user chooses "Deduce cash discount" and enters 2 percent
- **THEN** the calculator shows a resulting amount of 980,00 € and a resulting discount of 20,00 €
- **AND** the amount field shows 980,00 € after the user confirms

#### Scenario: No amount yet

- **GIVEN** the amount field is empty
- **WHEN** the user chooses "Deduce cash discount"
- **THEN** the app asks the user to enter the full amount in the payment window first

#### Scenario: Restore

- **GIVEN** the user deduced 2 percent from 1.000,00 €
- **WHEN** the user restores the previous amount
- **THEN** the amount field shows 1.000,00 € again

### Requirement: End-to-end reference

The app SHALL add a field for the end-to-end reference when the user chooses "Set end-to-end reference" in the gear menu. The reference has at most 35 characters. It must not start with a slash, end with a slash, or contain two slashes in a row.

#### Scenario: Valid reference

- **WHEN** the user sets the end-to-end reference "RE-2026-4711"
- **THEN** the review step shows the reference and the bank receives it with the order

#### Scenario: Slash at the start

- **WHEN** the user enters the end-to-end reference "/4711"
- **THEN** the app shows that the end-to-end reference must not start with a slash

### Requirement: Purpose code

The app SHALL add a field for the SEPA purpose code when the user chooses "Set purpose code" in the gear menu. The field suggests SALA for salaries, CBFF for capital building benefits, and CHAR for donations, and it accepts any code of four letters.

#### Scenario: Salary payment

- **WHEN** the user sets the purpose code SALA for a transfer to an employee
- **THEN** the review step shows the purpose code SALA

#### Scenario: Invalid code

- **WHEN** the user enters the purpose code "SAL1"
- **THEN** the app shows that the purpose code is invalid
