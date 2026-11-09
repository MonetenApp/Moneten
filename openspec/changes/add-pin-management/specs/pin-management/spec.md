# Spec Delta

## Purpose

The PIN of an online banking access lives on the server of the bank. This capability defines how the user changes that PIN and lifts a block of it from inside the app, and what the app does when a bank demands a new PIN.

## ADDED Requirements

### Requirement: Assistant to change the PIN

The app SHALL offer "Change PIN of PIN/TAN Interface..." in the Tools menu. The command opens an assistant that changes the PIN of one FinTS access on the server of the bank. The first page says that "Edit Login Data..." is the command for a PIN that only the app stores.

#### Scenario: Open the assistant

- **WHEN** the user chooses "Change PIN of PIN/TAN Interface..."
- **THEN** the assistant opens and explains the difference to "Edit Login Data..."

#### Scenario: No FinTS access

- **GIVEN** the app has only offline accounts
- **WHEN** the user opens the Tools menu
- **THEN** "Change PIN of PIN/TAN Interface..." is disabled

### Requirement: Choose the access

The app SHALL list in the assistant every FinTS access with PIN and TAN, with the bank name and the user ID, and preselect the access of the account that is selected in the sidebar.

#### Scenario: Account selected

- **GIVEN** the account "Giro" of the access "erika77" at "Musterbank" is selected
- **WHEN** the assistant opens
- **THEN** "Musterbank, erika77" is selected in the list

#### Scenario: Category selected

- **GIVEN** a category is selected in the sidebar and the app has two FinTS accesses
- **WHEN** the assistant opens
- **THEN** the list shows both accesses and none is selected

### Requirement: Enter the current and the new PIN

The app SHALL ask for the current PIN, the new PIN, and the new PIN a second time, in hidden fields. The labels use the word that the bank uses for the secret. The app fills in no field from its saved PIN.

#### Scenario: Bank calls it a password

- **GIVEN** the bank calls the secret "password"
- **WHEN** the assistant shows the entry page
- **THEN** the labels read "Current password", "New password", and "Repeat new password"

### Requirement: Check the new PIN before sending

The app SHALL refuse to continue when the two entries of the new PIN differ, when the new PIN equals the current one, or when the new PIN breaks the length or digit rule of the bank. It names the rule that is broken.

#### Scenario: Entries differ

- **WHEN** the user enters "24680" and "24681" as the new PIN
- **THEN** the app says that the new PINs differ

#### Scenario: Same as before

- **WHEN** the user enters the current PIN as the new PIN
- **THEN** the app says that the new PIN must not be identical to the old PIN

#### Scenario: Bank requires five digits

- **GIVEN** "Musterbank" requires a PIN of exactly 5 digits
- **WHEN** the user enters "1234567" as the new PIN
- **THEN** the app says that the new PIN must have 5 digits

### Requirement: Confirm the change with a TAN

The app SHALL send the PIN change to the bank and handle the request for a TAN through the dialog for two-factor authentication, which states the PIN change as the purpose. While it waits for the bank, the assistant shows a progress text.

#### Scenario: Change with pushTAN

- **WHEN** the user continues with valid entries and approves the request in the app of the bank
- **THEN** the assistant says that the PIN has been changed

#### Scenario: TAN canceled

- **WHEN** the user cancels the TAN dialog
- **THEN** the assistant says that the PIN was not changed
- **AND** the PIN at the bank is the old one

### Requirement: Use the new PIN after a successful change

The app SHALL replace the PIN that it holds for the access with the new PIN after the bank confirmed the change. A saved PIN stays saved with the new value. A PIN that was only in memory stays only in memory.

#### Scenario: Saved PIN

- **GIVEN** the access has a saved PIN
- **WHEN** the PIN change succeeds
- **THEN** the next refresh logs in with the new PIN and asks for nothing

#### Scenario: PIN not saved

- **GIVEN** the access has no saved PIN
- **WHEN** the PIN change succeeds and the app is restarted
- **THEN** the next refresh asks for the PIN

### Requirement: Failed or unclear PIN change

The app SHALL show the message of the bank when the bank rejects the PIN change, and keep the old PIN. When the connection breaks before the answer arrives, the app says that the result is unknown, forgets the PIN that it holds for the access, and asks for the PIN at the next login.

#### Scenario: Wrong current PIN

- **WHEN** the user enters a wrong current PIN and the bank rejects the change
- **THEN** the assistant shows the message of the bank and the entry page with empty fields

#### Scenario: Connection lost

- **WHEN** the connection breaks after the app sent the change
- **THEN** the assistant says that it is unknown whether the PIN was changed
- **AND** the next refresh of the access asks for the PIN

### Requirement: Bank does not support the PIN change

The app SHALL tell the user to change the PIN on the website of the bank when the FinTS server of the bank does not offer a PIN change, and it SHALL say so before it asks for any PIN.

#### Scenario: Server without PIN change

- **GIVEN** the FinTS server of "Musterbank" does not offer a PIN change
- **WHEN** the user selects the access of "Musterbank" in the assistant
- **THEN** the assistant says that the server does not support changing the PIN and names the website of the bank

### Requirement: PIN change that the server demands

The app SHALL open the PIN change assistant with the access preselected when a bank demands a PIN change during account setup or a refresh, for example at the first login with a start PIN. After a successful change the app continues the setup or the refresh with the new PIN.

#### Scenario: Start PIN at setup

- **GIVEN** the user sets up an access with the start PIN from a letter of the bank
- **WHEN** the bank demands a PIN change at the first login
- **THEN** the PIN change assistant opens for that access
- **AND** after the change the account setup continues with the list of accounts

#### Scenario: Demand during an automatic refresh

- **WHEN** the bank demands a PIN change during an automatic refresh
- **THEN** the account shows that the server requires a PIN change
- **AND** the assistant opens when the user refreshes the account by hand

### Requirement: Assistant to unblock the PIN

The app SHALL offer "Unblock PIN with TAN ..." in the Tools menu. The assistant lists the FinTS accesses like the PIN change assistant, lets the user choose the TAN method under "Unblock using", and sends the request to unblock the PIN with a TAN.

#### Scenario: Unblock succeeds

- **GIVEN** the bank blocked the PIN of "erika77" after three wrong attempts
- **WHEN** the user chooses the access, selects "chipTAN QR", and enters the TAN
- **THEN** the assistant says that the PIN has been unblocked
- **AND** a refresh of the access works again

### Requirement: Unblocking is refused or not offered

The app SHALL tell the user to ask the support of the bank when the bank refuses to unblock the PIN or its FinTS server does not offer unblocking.

#### Scenario: Server without unblocking

- **GIVEN** the FinTS server of "Musterbank" does not offer unblocking
- **WHEN** the user selects the access of "Musterbank" in the unblock assistant
- **THEN** the assistant says that the server does not support unblocking the PIN and that the support of the bank can unblock it

#### Scenario: Bank refuses

- **WHEN** the bank answers the unblock request with a refusal
- **THEN** the assistant shows the message of the bank and the advice to ask its support

### Requirement: Offer the unblock assistant for a blocked PIN

The app SHALL name both ways to lift a block in the error of an account whose PIN the bank blocked, which are the unblock assistant and the support of the bank.

#### Scenario: Blocked PIN after a refresh

- **WHEN** a refresh fails because the bank blocked the PIN
- **THEN** the error of the account says that the PIN can be unblocked with a TAN or by the support of the bank
- **AND** the error offers a button that opens "Unblock PIN with TAN ..." for that access

### Requirement: Cancel changes nothing

The app SHALL change nothing at the bank and nothing in its own data when the user closes an assistant before the bank confirmed the order.

#### Scenario: Close on the entry page

- **WHEN** the user enters a new PIN and closes the assistant without continuing
- **THEN** the PIN at the bank and the PIN that the app holds are unchanged
