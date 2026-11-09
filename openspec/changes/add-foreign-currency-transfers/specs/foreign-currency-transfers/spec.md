# Spec Delta

## Purpose

A foreign currency transfer pays in a currency other than the euro or to a country outside the SEPA area. This capability defines the extra fields of such a transfer, the rules for single countries, and the notices that the user sees before sending.

## ADDED Requirements

### Requirement: Open a foreign currency transfer

The app SHALL open the payment window for a foreign currency transfer through "New Foreign Currency Transfer..." in the Payment menu and through "New foreign currency transfer" under "Action". The window shows the fields of a transfer and also a currency, the country of the recipient, the bank of the recipient, the charges, and optional fields for the address of the recipient and for instructions for the bank.

#### Scenario: Switch from a SEPA form

- **GIVEN** an open payment window with the recipient "Max Mustermann" and the amount 500,00
- **WHEN** the user changes "Action" to "New foreign currency transfer"
- **THEN** the recipient and the amount stay
- **AND** the window shows the fields for currency, country, bank, and charges

### Requirement: Foreign currency transfers only where the bank supports them

The app SHALL read from the bank's parameter data whether the source account supports foreign currency transfers. When it does not, the app says so and names the account by its IBAN or its account number.

#### Scenario: Bank without foreign transfers

- **GIVEN** the bank does not support foreign currency transfers for the account "Giro"
- **WHEN** the user chooses "New foreign currency transfer" for "Giro"
- **THEN** the app explains that the bank does not support foreign currency transfers for the account with this IBAN

### Requirement: Currency and amount

The app SHALL require the user to choose the currency of the transfer from a list of currencies. The amount is entered in that currency and shown with its currency code.

#### Scenario: No currency chosen

- **WHEN** the user fills the form and leaves the currency menu on its placeholder
- **THEN** the app asks the user to choose a currency

#### Scenario: Dollar amount

- **WHEN** the user chooses USD and enters the amount 1.200,00
- **THEN** the review step shows "1.200,00 USD"

### Requirement: Country of the recipient

The app SHALL require the user to choose the country of the recipient. The app applies the rules of that country to the other fields.

#### Scenario: No country chosen

- **WHEN** the user leaves the country menu on its placeholder and clicks "Next"
- **THEN** the app asks the user to choose a country for the recipient

### Requirement: IBAN or account number

The app SHALL accept an IBAN or an account number for the account of the recipient. An IBAN passes the checksum and length checks of a transfer. An account number is accepted as entered unless the country of the recipient has its own format.

#### Scenario: Recipient in the United States

- **GIVEN** the country of the recipient is the United States
- **WHEN** the user enters the account number 123456789
- **THEN** the app accepts the account number

#### Scenario: Invalid IBAN

- **WHEN** the user enters the IBAN GB82WEST12345698765433
- **THEN** the app shows that the IBAN has an invalid checksum

### Requirement: Account number formats of single countries

The app SHALL require the account number in the format of the country where a country needs one. For Australia the format is the BSB number, the text "ACC", and the account number. For Mexico it is the CLABE number with 18 digits. The message names the country and the format.

#### Scenario: Australia

- **GIVEN** the country of the recipient is Australia
- **WHEN** the user enters the account number 12345678
- **THEN** the app says that for transfers to Australia the account number must be given as BSB number, "ACC", and account number
- **AND** the entry "062000 ACC 12345678" is accepted

#### Scenario: Mexico

- **GIVEN** the country of the recipient is Mexico
- **WHEN** the user enters the account number 032180000118359719
- **THEN** the app accepts the CLABE number

### Requirement: The bank of the recipient

The app SHALL require a BIC or the name and the address of the bank of the recipient. The address has the fields "Bank name", "Street of bank", "Place of bank", and "Country of bank".

#### Scenario: Neither BIC nor address

- **WHEN** the user leaves the BIC and the bank address empty and clicks "Next"
- **THEN** the app asks the user to specify a BIC or a bank address

#### Scenario: Bank without a BIC

- **WHEN** the user enters the bank name "First Example Bank", the street "100 Main Street", and the place "Springfield"
- **THEN** the app accepts the bank without a BIC

### Requirement: Bank in another country than the recipient

The app SHALL check that the country code of the IBAN and of the BIC equals the country of the recipient. When they differ, the app says so and points to "Set country of bank" in the gear menu. After the user set the country of the bank, the app checks the IBAN and the BIC against that country.

#### Scenario: Recipient in Switzerland with a German account

- **GIVEN** the country of the recipient is Switzerland
- **WHEN** the user enters the IBAN DE02120300000000202051
- **THEN** the app says that the IBAN does not originate from Switzerland and that the country of the bank can be set in the gear menu

#### Scenario: Country of the bank set

- **GIVEN** the user chose "Set country of bank" and selected Germany
- **WHEN** the user enters the IBAN DE02120300000000202051 for a recipient in Switzerland
- **THEN** the app accepts the IBAN

### Requirement: Address of the recipient

The app SHALL let the user enter the postal address of the recipient through "Set address" in the gear menu. For countries that need it, the app requires the complete address with street, place, and country before the transfer can continue.

#### Scenario: Country that needs the address

- **GIVEN** the rules for Canada require the complete address of the recipient
- **WHEN** the user clicks "Next" for a transfer to Canada without an address
- **THEN** the app says that for transfers to Canada the complete recipient address must be specified

### Requirement: Purpose for countries that need one

The app SHALL require a purpose text for countries whose rules need one.

#### Scenario: Purpose missing

- **GIVEN** the rules for China require a purpose text
- **WHEN** the user clicks "Next" for a transfer to China with an empty purpose
- **THEN** the app says that for transfers to China a purpose text must be specified

### Requirement: Charges

The app SHALL require the user to choose who pays the charges of the transfer. The choices are "Shared", "Sender pays all charges", and "Recipient pays all charges". No choice is preselected.

#### Scenario: No charges scheme

- **WHEN** the user clicks "Next" and the charges menu is on its placeholder
- **THEN** the app asks the user to choose a charging scheme

#### Scenario: Shared charges

- **WHEN** the user chooses "Shared"
- **THEN** the review step shows that sender and recipient each pay the charges of their own bank

### Requirement: Instructions for the bank

The app SHALL let the user add instructions for the bank through "Set instructions for bank" in the gear menu. When the format that the bank expects has no such field, the app says that the field can no longer be used and asks the user to move its text to another field.

#### Scenario: Add an instruction

- **GIVEN** the bank accepts instructions
- **WHEN** the user sets the instruction "Avis an Empfänger per Telefon"
- **THEN** the review step shows the instruction

#### Scenario: Bank without the field

- **GIVEN** the bank no longer accepts instructions
- **WHEN** the user opens a template that holds the instruction "REF 4711"
- **THEN** the app says that the field can no longer be used and that "REF 4711" must go into another field

### Requirement: Name and address of the account owner

The app SHALL send the name and the postal address of the account owner with a foreign currency transfer. When the settings of the source account hold no address, the app asks the user to enter it there before the transfer can continue.

#### Scenario: Address missing

- **GIVEN** the account "Giro" has an owner name and no owner address
- **WHEN** the user clicks "Next" for a foreign currency transfer from "Giro"
- **THEN** the app explains that the user's own address must be submitted and points to the account settings

### Requirement: Hint about the cheaper SEPA transfer

The app SHALL show a hint when the country of the recipient takes part in SEPA. The hint says that SEPA transfers to that country are generally cheaper and that "New bank transfer" under "Action" switches to a SEPA transfer. The user can continue with the foreign currency transfer.

#### Scenario: Recipient in Austria

- **WHEN** the user chooses Austria as the country of the recipient
- **THEN** the app shows the hint that SEPA transfers to Austria are generally cheaper

### Requirement: Point from the SEPA form to the foreign currency transfer

The app SHALL add to the message for an IBAN outside the SEPA area in a SEPA transfer the advice to choose "New foreign currency transfer" under "Action".

#### Scenario: Turkish IBAN in a SEPA form

- **WHEN** the user enters a valid IBAN with the country code TR in a new bank transfer
- **THEN** the message says that the IBAN does not originate from a SEPA country and names "New foreign currency transfer" as the way to pay this recipient

### Requirement: Notice about the reporting duty

The app SHALL show a notice when the amount of a foreign transfer is above the reporting threshold of the Deutsche Bundesbank. The notice states the threshold, says that the user must report the payment unless an exception applies, and gives the hotline and the reporting portal of the Bundesbank. The threshold is 50.000 € at the time of writing and ships as data with the app.

#### Scenario: Amount above the threshold

- **WHEN** the user clicks "Next" for a transfer of 60.000,00 € to the United States
- **THEN** the app shows the notice about the reporting obligation with the threshold of 50.000 €

#### Scenario: Amount below the threshold

- **WHEN** the user clicks "Next" for a transfer of 1.200,00 USD
- **THEN** no notice about the reporting obligation appears

### Requirement: Final question before sending

The app SHALL ask the user whether to continue with the international money transfer before the TAN step. The question follows the review.

#### Scenario: Confirm

- **WHEN** the user confirms the review of a foreign currency transfer
- **THEN** the app asks whether the user is sure to continue with this international money transfer
- **AND** the TAN dialog opens only after the user agrees

### Requirement: Review of a foreign currency transfer

The app SHALL show in the review of a foreign currency transfer all entered fields, the currency, the charges scheme, and two notes. The first note says that the bank sets the exchange rate and its charges. The second note says that the payee check does not apply to this kind of transfer.

#### Scenario: Review

- **WHEN** the user clicks "Next" for a transfer of 1.200,00 USD to "Max Mustermann" in the United States with shared charges
- **THEN** the review shows the amount in USD, the bank of the recipient, the charges scheme, and both notes

### Requirement: Scheduled foreign currency transfers

The app SHALL accept a scheduled date for a foreign currency transfer where the bank supports it, and check the date against the maximum lead time that the bank reports for this kind of transfer.

#### Scenario: Date beyond the lead time

- **GIVEN** the bank allows a lead time of at most 14 days for foreign currency transfers and today is 3 November 2026
- **WHEN** the user picks 30 November 2026
- **THEN** the app says that the latest possible scheduled date is 17 November 2026

### Requirement: Send and record like a transfer

The app SHALL confirm a foreign currency transfer with a TAN, transmit it, show the result, and record it under "Sent" in the same way as a SEPA transfer. An order with an unknown result is never sent again by the app.

#### Scenario: Accepted

- **WHEN** the bank accepts a foreign currency transfer of 1.200,00 USD
- **THEN** the app shows that the foreign currency transfer has been transmitted to the bank
- **AND** "Sent" lists it with the amount 1.200,00 USD

### Requirement: Templates for foreign currency transfers

The app SHALL let the user create a template for a foreign currency transfer through "New Foreign Currency Transfer Template..." and "Add Foreign Currency Transfer Template...". The template holds all fields of a foreign currency transfer. Using the template opens the payment window as a foreign currency transfer.

#### Scenario: Monthly payment abroad

- **GIVEN** a foreign currency template for "Max Mustermann" with 1.200,00 USD
- **WHEN** the user uses the template
- **THEN** the payment window opens with the action "New foreign currency transfer", the currency USD, and the data of the template

### Requirement: Import and export foreign currency templates

The app SHALL export foreign currency templates as an XML file in the international variant of the format `pain.001.001.09`, and import such files as templates.

#### Scenario: Round trip

- **WHEN** the user exports 2 foreign currency templates and imports the file into an empty group
- **THEN** the group holds 2 foreign currency templates with the same currency, recipient, bank, and charges scheme
