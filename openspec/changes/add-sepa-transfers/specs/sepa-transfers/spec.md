# Spec Delta

## Purpose

A user sends one SEPA transfer or one instant payment from an account that the app reaches through FinTS. This capability defines the payment window, the checks before sending, the Verification of Payee, the confirmation, the result, and the record of sent orders.

## ADDED Requirements

### Requirement: Open the payment window

The app SHALL open a payment window for a new transfer through the menu command "New Bank Transfer..." with the shortcut ⌘N and through the toolbar button "Bank transfer". The window preselects the account that is selected in the sidebar as the source account under "From".

#### Scenario: Shortcut in an account view

- **GIVEN** the account "Giro" is selected in the sidebar and can send transfers
- **WHEN** the user presses ⌘N
- **THEN** the payment window opens with "Giro" under "From" and the action "New bank transfer"

#### Scenario: No account selected

- **GIVEN** the dashboard is selected
- **WHEN** the user chooses "New Bank Transfer..."
- **THEN** the payment window opens with the account that the user last paid from

### Requirement: Only accounts that can pay are offered as the source

The app SHALL list under "From" only accounts whose bank access can send transfers. Each entry shows the account name and the IBAN.

#### Scenario: Mixed accounts

- **GIVEN** a giro account with FinTS access, a credit card account, and an offline account
- **WHEN** the user opens the "From" menu
- **THEN** the menu lists the giro account only

#### Scenario: No account can pay

- **GIVEN** no account has an access that can send transfers
- **WHEN** the user chooses "New Bank Transfer..."
- **THEN** the app explains that none of the accounts is set up for transfers and opens no payment window

### Requirement: Payments go only through FinTS

The app SHALL send a transfer only through the FinTS access of the source account. For an account that is reached through an extension or the aggregator, the app says that this access is read-only, and it names "Edit Login Data..." as the way to switch to FinTS when the bank offers a FinTS server.

#### Scenario: Account from an extension

- **GIVEN** the account "Broker" is reached through an extension
- **WHEN** the user selects "Broker" and chooses "New Bank Transfer..."
- **THEN** the app explains that transfers are not possible for this account because its access is read-only

#### Scenario: Bank also offers FinTS

- **GIVEN** the account "Giro" is reached through the aggregator and its bank has a FinTS server
- **WHEN** the user tries to start a transfer from "Giro"
- **THEN** the message says that the transfer is possible after the access is changed to FinTS with "Edit Login Data..."

### Requirement: Respect what the bank allows for the account

The app SHALL read from the bank's parameter data whether the source account can send SEPA transfers. When the bank does not allow transfers for the account, the app says so before the user fills the form and names the bank.

#### Scenario: Savings account without transfers

- **GIVEN** the bank reports that the savings account "Tagesgeld" cannot send transfers
- **WHEN** the user selects "Tagesgeld" under "From"
- **THEN** the app explains that the FinTS server of the bank does not allow transfers from this account
- **AND** "Next" stays disabled

### Requirement: SEPA transfers need a euro account

The app SHALL refuse a SEPA transfer from an account whose currency is not the euro and name the currency of the account in the message.

#### Scenario: Dollar account

- **GIVEN** the account "USD-Konto" has the currency USD
- **WHEN** the user selects it as the source of a SEPA transfer
- **THEN** the app explains that SEPA transfers only work with euro accounts and that this account has the currency USD

### Requirement: Recipient name

The app SHALL require a recipient name of 1 to 70 characters and accept only characters that the bank accepts in a SEPA order. A message names the characters that are not accepted.

#### Scenario: Name missing

- **WHEN** the user leaves "Recipient" empty and fills all other fields
- **THEN** "Next" stays disabled

#### Scenario: Character the bank does not accept

- **GIVEN** the bank does not accept the character "€" in names
- **WHEN** the user enters the recipient "Café 5€ GmbH"
- **THEN** the app shows that the recipient contains the invalid character "€"

### Requirement: Check the IBAN while the user types

The app SHALL check the IBAN as soon as it is complete and show the reason when it is invalid. The reasons are a wrong checksum, a length that does not fit the country code, an unknown country code, and a Bankleitzahl inside a German IBAN that the Bundesbank directory does not contain.

#### Scenario: Typing error

- **WHEN** the user enters the IBAN DE02120300000000202052
- **THEN** the app shows that the checksum of the IBAN is invalid and asks the user to check for typing errors

#### Scenario: Too short

- **WHEN** the user enters the IBAN DE0212030000000020205
- **THEN** the app shows that an IBAN with the country code DE has 22 characters

#### Scenario: Valid IBAN with spaces

- **WHEN** the user pastes "DE02 1203 0000 0000 2020 51"
- **THEN** the app accepts the IBAN

### Requirement: Only SEPA countries

The app SHALL accept as the target of a SEPA transfer only an IBAN from a country that takes part in SEPA. For another country the app says that the IBAN does not come from a SEPA country.

#### Scenario: IBAN outside SEPA

- **WHEN** the user enters a valid IBAN with the country code TR
- **THEN** the app shows that the IBAN does not originate from a SEPA country
- **AND** "Next" stays disabled

### Requirement: Find and check the BIC

The app SHALL fill the BIC from the IBAN when its bank directory knows the bank. The BIC is optional for a recipient inside the European Economic Area. It is required outside it and when the bank of the source account asks for one. The app rejects a BIC with a wrong format, a BIC whose country differs from the IBAN, a BIC that the directory replaces by another one for this IBAN, and a BIC that cannot receive SEPA transfers.

#### Scenario: BIC is filled

- **WHEN** the user enters the IBAN DE02120300000000202051
- **THEN** the BIC field shows BYLADEM1001

#### Scenario: Recipient in Switzerland without BIC

- **WHEN** the user enters the IBAN CH9300762011623852957 and leaves the BIC empty
- **THEN** the app shows that a BIC is required for countries outside the European Economic Area

#### Scenario: BIC from another country

- **WHEN** the user enters the IBAN DE02120300000000202051 and the BIC BKAUATWWXXX
- **THEN** the app shows that the BIC is invalid for this IBAN because the country codes do not match

#### Scenario: Bank of the source account requires a BIC

- **GIVEN** the bank of the source account requires a BIC for recipients in other countries
- **WHEN** the user enters the IBAN AT611904300234573201 and the app finds no BIC for it
- **THEN** the app shows that the BIC is missing and that the bank requires it for other countries

### Requirement: Amount

The app SHALL require an amount greater than zero with at most two decimals. The amount field accepts a decimal comma and a decimal point.

#### Scenario: Zero

- **WHEN** the user enters the amount 0,00
- **THEN** the app shows that the amount must not be zero and "Next" stays disabled

#### Scenario: Small amount

- **WHEN** the user enters the amount 1,59
- **THEN** the app accepts the amount as 1,59 €

### Requirement: Purpose

The app SHALL accept a purpose of at most 140 characters and only characters that the bank accepts in a SEPA order. Line breaks that the user types are sent as spaces.

#### Scenario: Too long

- **WHEN** the user enters a purpose with 150 characters
- **THEN** the app shows that the purpose is too long and that at most 140 characters are allowed

#### Scenario: Line break

- **WHEN** the user enters "Rechnung 4711" and "Kundennummer 0815" on two lines
- **THEN** the review step shows the purpose "Rechnung 4711 Kundennummer 0815"

### Requirement: The name of the account owner is required

The app SHALL send the name of the account owner with every transfer. When the source account has no owner name, the app asks the user to enter the name in the account settings before the transfer can continue.

#### Scenario: Owner name missing

- **GIVEN** the account "Giro" has no owner name
- **WHEN** the user clicks "Next" in a complete transfer form
- **THEN** the app explains that the user's own name must be submitted and points to the account settings

### Requirement: Source and target must differ

The app SHALL reject a transfer whose recipient IBAN equals the IBAN of the source account.

#### Scenario: Same account

- **GIVEN** the source account has the IBAN DE02120300000000202051
- **WHEN** the user enters DE02120300000000202051 as the recipient IBAN
- **THEN** the app shows that the source account and the target account are identical

### Requirement: "Next" is available only for a valid form

The app SHALL keep the button "Next" disabled while a required field is empty or a field check fails, and it SHALL show the reason next to the field that fails.

#### Scenario: Complete form

- **WHEN** the user enters the recipient "Stadtwerke Musterstadt", the IBAN DE02120300000000202051, the amount 89,00, and the purpose "Abschlag November"
- **THEN** "Next" becomes enabled

### Requirement: Transfer between own accounts

The app SHALL offer under "Action" one entry "Transfer to" for each other account of the user that can receive a transfer. Choosing an entry fills the recipient with the owner name and the IBAN of that account.

#### Scenario: Move money to the savings account

- **GIVEN** the accounts "Giro" and "Tagesgeld", both owned by Erika Mustermann
- **WHEN** the user opens the payment window from "Giro" and chooses "Transfer to Tagesgeld"
- **THEN** the recipient is "Erika Mustermann" with the IBAN of "Tagesgeld"

#### Scenario: Target account has no owner name

- **GIVEN** the account "Tagesgeld" has no owner name in its settings
- **WHEN** the user chooses "Transfer to Tagesgeld"
- **THEN** the app asks the user to enter the name of the account owner in the settings of "Tagesgeld"

### Requirement: New transfer from a transaction

The app SHALL offer "New from Selection" with "New Bank Transfer..." in the context menu of a transaction. The payment window opens with the counterparty name, IBAN, BIC, the amount without its sign, and the purpose of that transaction. Text that the bank added to the purpose, such as references and dates, is removed.

#### Scenario: Pay the same recipient again

- **GIVEN** a transaction of -89,00 € to "Stadtwerke Musterstadt" with the IBAN DE02120300000000202051 and the purpose "Abschlag Oktober EREF+4711 MREF+M-01"
- **WHEN** the user chooses "New from Selection" and "New Bank Transfer..."
- **THEN** the payment window shows the recipient "Stadtwerke Musterstadt", the IBAN DE02120300000000202051, the amount 89,00 €, and the purpose "Abschlag Oktober"

#### Scenario: Transaction without bank details

- **GIVEN** a card payment without a counterparty IBAN
- **WHEN** the user chooses "New Bank Transfer..." from the selection
- **THEN** the payment window opens with the name and the purpose, and the IBAN field is empty

### Requirement: Recipient suggestions from earlier transactions

The app SHALL suggest recipients while the user types in "Recipient". The suggestions come from the counterparties of existing transactions. Choosing a suggestion fills the name, the IBAN, and the BIC.

#### Scenario: Known recipient

- **GIVEN** earlier transactions with the counterparty "Stadtwerke Musterstadt" and the IBAN DE02120300000000202051
- **WHEN** the user types "Stadt" in "Recipient"
- **THEN** the app suggests "Stadtwerke Musterstadt" with its IBAN
- **AND** choosing the suggestion fills name, IBAN, and BIC

### Requirement: Warn about a likely duplicate

The app SHALL ask for confirmation when the user transferred the same amount to the same IBAN recently. The question names the amount and the account.

#### Scenario: Same transfer twice

- **GIVEN** the user sent 89,00 € to DE02120300000000202051 yesterday
- **WHEN** the user clicks "Next" for another transfer of 89,00 € to the same IBAN
- **THEN** the app asks whether this is a duplicate bank transfer
- **AND** the transfer continues only when the user confirms

### Requirement: Warn about a different name for a known IBAN

The app SHALL ask for confirmation when the user recently used the same IBAN with a different recipient name. The question shows both names.

#### Scenario: Changed name

- **GIVEN** the user recently sent a transfer to DE02120300000000202051 with the name "Max Mustermann"
- **WHEN** the user enters the same IBAN with the name "Erika Mustermann" and clicks "Next"
- **THEN** the app shows both names and asks whether to continue

### Requirement: Warn about an overdraft

The app SHALL ask for confirmation when the amount is higher than the money that is available in the source account. The question states by how much the account will probably be overdrawn.

#### Scenario: Balance too low

- **GIVEN** the account "Giro" has a balance of 50,00 € and no credit line
- **WHEN** the user clicks "Next" for a transfer of 89,00 €
- **THEN** the app says that the account will probably be overdrawn by 39,00 € and asks whether to continue

### Requirement: Warn about an empty purpose

The app SHALL ask for confirmation when the user sends a transfer without a purpose.

#### Scenario: No purpose

- **WHEN** the user leaves "Purpose" empty and clicks "Next"
- **THEN** the app asks whether the user wants to continue without a purpose text

### Requirement: Review step

The app SHALL show a review of the transfer after "Next" and before any confirmation. The review shows the source account, the recipient name, the IBAN, the BIC, the name of the recipient bank, the amount, the purpose, the kind of payment, and the result of the payee check.

#### Scenario: Review a transfer

- **WHEN** the user clicks "Next" for a transfer of 89,00 € to "Stadtwerke Musterstadt"
- **THEN** the app shows all entered details and the payee check result on one screen
- **AND** nothing has been sent to execute the transfer

### Requirement: Check the payee before confirmation

The app SHALL ask the bank for the Verification of Payee of every SEPA transfer and instant payment, and it SHALL show the result before the user can confirm. The app never asks for the confirmation first.

#### Scenario: Name matches

- **GIVEN** the bank reports that the name matches the account holder
- **WHEN** the review step appears
- **THEN** the review shows that the recipient name matches
- **AND** the user can confirm the transfer

### Requirement: Payee check with a close match

The app SHALL show the name that the bank suggests when the payee check reports a close match. The user can adopt the suggested name or keep the entered name. Keeping the entered name needs an explicit confirmation.

#### Scenario: Adopt the suggestion

- **GIVEN** the user entered "Stadtwerk Musterstadt" and the bank suggests "Stadtwerke Musterstadt GmbH"
- **WHEN** the user adopts the suggested name
- **THEN** the transfer uses the name "Stadtwerke Musterstadt GmbH"
- **AND** the app runs the payee check again before the confirmation

#### Scenario: Keep the entered name

- **GIVEN** the bank reports a close match
- **WHEN** the user chooses to keep the entered name
- **THEN** the app asks the user to confirm that the transfer goes to an account whose holder name differs

### Requirement: Payee check with no match or no result

The app SHALL show a warning when the payee check reports no match or when the check is not possible. The warning says that the bank is not liable when the money reaches an account holder other than the intended recipient. The transfer continues only after an explicit confirmation.

#### Scenario: No match

- **GIVEN** the bank reports that the name does not match the account holder
- **WHEN** the review step appears
- **THEN** the app shows the warning with the liability notice
- **AND** the default action is to go back to the form

#### Scenario: Check not possible

- **GIVEN** the recipient bank cannot check the name
- **WHEN** the review step appears
- **THEN** the app says that the name could not be checked and asks for an explicit confirmation

### Requirement: A change after the payee check starts over

The app SHALL discard the payee check result when the user changes the recipient name, the IBAN, or the amount after the check. The transfer returns to the form, and a new check runs before the confirmation.

#### Scenario: Amount changed after the check

- **GIVEN** a transfer of 89,00 € with the result "match" in the review step
- **WHEN** the user goes back and changes the amount to 98,00 €
- **THEN** the earlier result is discarded
- **AND** the next review step shows a new payee check result

### Requirement: Confirm with a TAN

The app SHALL let the user choose the TAN method under "Confirm using" from the methods that the bank offers for this user, and it SHALL ask for the TAN after the user confirmed the review. When the bank exempts the order from a TAN, the app sends the order without a TAN dialog.

#### Scenario: App approval

- **GIVEN** the method "pushTAN" is selected under "Confirm using"
- **WHEN** the user confirms the review
- **THEN** the TAN dialog states that the approval is for a transfer of 89,00 € to "Stadtwerke Musterstadt" at the FinTS server of the bank

#### Scenario: No TAN needed

- **GIVEN** the bank needs no TAN for a transfer between the user's own accounts
- **WHEN** the user confirms the review of such a transfer
- **THEN** the app sends the order without asking for a TAN

### Requirement: Nothing is sent without the user's confirmation in the window

The app SHALL transmit a payment order only after the user confirmed its review in the payment window. No other part of the app, no automation command, and no extension can transmit an order.

#### Scenario: Window opened by another program

- **GIVEN** another program asked the app to create a bank transfer
- **WHEN** the payment window opens with the given data
- **THEN** the order is not transmitted until the user goes through the review and the confirmation

#### Scenario: User cancels the TAN dialog

- **WHEN** the user cancels the TAN dialog
- **THEN** the order is not transmitted and the payment window returns to the review

### Requirement: Show the transmission and its result

The app SHALL show progress while it transmits the order, and it SHALL show one clear result. An accepted order shows that the transfer has been transmitted to the bank. A notice that the bank adds to its answer is shown with the result.

#### Scenario: Accepted

- **WHEN** the bank accepts the order
- **THEN** the payment window shows that the transfer has been successfully transmitted to the bank
- **AND** the order appears in the list of sent payments

#### Scenario: Bank adds a notice

- **GIVEN** the bank accepts the order and adds the notice "Ausführung am nächsten Bankarbeitstag"
- **WHEN** the result appears
- **THEN** the result shows the notice of the bank below the success message

### Requirement: Rejected orders

The app SHALL show the message of the bank when the bank rejects an order, keep the entered data in the payment window, and let the user correct and send the order as a new order.

#### Scenario: Limit exceeded

- **GIVEN** the bank answers that the daily limit is exceeded
- **WHEN** the result appears
- **THEN** the app shows that the transfer was not accepted and shows the text of the bank
- **AND** the form still holds the entered data

### Requirement: Never send an order again without the user

The app SHALL treat an order as unknown when the connection breaks after the order was sent and before the answer arrived. The app says that it is not clear whether the order was transmitted and advises the user to check the account. The app never transmits the same order again by itself.

#### Scenario: Connection lost during transmission

- **WHEN** the connection breaks while the app waits for the answer of the bank
- **THEN** the app shows that it is unclear whether the transfer was transmitted completely
- **AND** the order is listed with the state "unknown"
- **AND** the app starts no second transmission

#### Scenario: Matching transaction arrives

- **GIVEN** an order of 89,00 € to DE02120300000000202051 with the state "unknown"
- **WHEN** a later refresh delivers a withdrawal of 89,00 € to that IBAN with the same purpose
- **THEN** the order changes to the state "accepted"

### Requirement: Every state of an order is saved

The app SHALL save each state change of an order before it takes the next step. After a crash or a restart the app shows the order in its last saved state and continues only when the user asks for it.

#### Scenario: Crash while waiting for the TAN

- **GIVEN** the app quits unexpectedly while the TAN dialog of a transfer is open
- **WHEN** the user starts the app again
- **THEN** the order is not transmitted
- **AND** the user finds the transfer with its entered data and can start the confirmation again

#### Scenario: Crash after transmission

- **GIVEN** the app quits unexpectedly after it sent the order and before it stored the answer
- **WHEN** the user starts the app again
- **THEN** the order is listed with the state "unknown" and the advice to check the account

### Requirement: Record of sent payments

The app SHALL keep a record of every order that it transmitted and list the records in the view "Sent" under "Payments". A record holds the time of transmission, the source account, the recipient, the IBAN, the amount, the purpose, the kind of payment, the payee check result, the TAN method, and the state. A record never holds the TAN.

#### Scenario: Look up a sent transfer

- **GIVEN** the user sent 89,00 € to "Stadtwerke Musterstadt" on 3 November 2026 at 10:15
- **WHEN** the user opens "Sent"
- **THEN** the list shows the transfer with its time, amount, recipient, TAN method, and the state "accepted"

### Requirement: Send an instant payment

The app SHALL offer "New Instant Payment..." in the Payment menu and "New instant payment" under "Action". An instant payment uses the same form, checks, payee check, and confirmation as a transfer.

#### Scenario: Choose the instant payment in the window

- **GIVEN** an open payment window with a complete transfer
- **WHEN** the user changes "Action" to "New instant payment"
- **THEN** the entered data stays and the review step names the payment an instant payment

### Requirement: Instant payments only where the bank supports them

The app SHALL read from the bank's parameter data whether the source account supports instant payments. When it does not, the app says so, names the bank, and suggests an ordinary bank transfer.

#### Scenario: Bank without instant payments

- **GIVEN** the bank does not support instant payments for the account "Giro"
- **WHEN** the user chooses "New instant payment" for "Giro"
- **THEN** the app explains that the bank does not support instant payments for this account and suggests an ordinary bank transfer

### Requirement: Check the status of an instant payment

The app SHALL ask the bank for the status of an instant payment right after the transmission and for up to 20 seconds. It shows progress during that time and then one of three results. The amount was credited to the recipient, the payment was rejected, or the status could not be determined.

#### Scenario: Credited

- **WHEN** the bank reports within 5 seconds that the recipient bank processed the payment
- **THEN** the app shows that the amount has been credited to the recipient

#### Scenario: Status stays open

- **WHEN** the bank reports no final status within 20 seconds
- **THEN** the app shows that the instant payment was transmitted, that it could not determine whether the recipient bank processed it, and that the user should check the account
