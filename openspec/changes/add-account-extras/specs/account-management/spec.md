# Spec Delta

## ADDED Requirements

### Requirement: Account icon

The app SHALL let the user choose an icon for each account from a built-in set in the account settings. The sidebar and the dashboard show the icon. A new account starts with the default icon of its account type.

#### Scenario: Choose an icon

- **WHEN** the user opens the settings of "Giro", selects the piggy bank icon, and clicks "OK"
- **THEN** the sidebar row of "Giro" shows the piggy bank icon

#### Scenario: Default icon

- **WHEN** the setup adds a credit card account
- **THEN** the account shows the default icon for the type "Credit card"

### Requirement: Colored icon background

The app SHALL offer the option "Colored background" in the icon choice. With the option on, the icon is drawn on a background in a color that the user picks from the offered colors.

#### Scenario: Turn on the background

- **WHEN** the user turns on "Colored background" and picks blue for "Giro"
- **THEN** the icon of "Giro" has a blue background in the sidebar

### Requirement: Account notes

The app SHALL offer a tab "Notes" in the account settings with a text field for notes of any length. The notes are stored with the account in the encrypted database.

#### Scenario: Keep a contract number

- **WHEN** the user enters "Contract 4711, notice period 3 months" on the tab "Notes" and clicks "OK"
- **THEN** the same text is on the tab when the user opens the settings again

### Requirement: User-defined fields

The app SHALL offer a table "User-defined fields" on the tab "Notes" with the columns "Attribute" and "Value". The user adds, edits, and removes rows.

#### Scenario: Add a field

- **WHEN** the user adds a row with the attribute "Interest rate" and the value "2,1 %" and clicks "OK"
- **THEN** the table shows that row when the settings open again

#### Scenario: Remove a field

- **WHEN** the user removes the row "Interest rate" and clicks "OK"
- **THEN** the table no longer contains the row

### Requirement: Address of the account owner

The app SHALL let the user enter the postal address of the account owner on the tab "Account owner" under "Address of Account Owner", with street, postal code, place, and country.

#### Scenario: Enter an address

- **WHEN** the user enters "Musterstraße 1, 12345 Musterstadt, Germany" and clicks "OK"
- **THEN** the app stores the address with the account

### Requirement: Owner name follows the bank

The app SHALL replace the stored owner name of an account when a refresh reports another name, unless the user changed the name by hand.

#### Scenario: Name changed at the bank

- **GIVEN** the owner name "Erika Mustermann" came from the bank
- **WHEN** a refresh reports the owner "Erika Musterfrau"
- **THEN** "Name of Account Owner" shows "Erika Musterfrau"

#### Scenario: Name entered by hand

- **GIVEN** the user changed the owner name to "E. Mustermann"
- **WHEN** a refresh reports the owner "Erika Mustermann"
- **THEN** "Name of Account Owner" still shows "E. Mustermann"

### Requirement: Display of the credit card number

The app SHALL offer the setting "Display credit card number as" for accounts of the type "Credit card", with the values "Last four digits" and "Full number". The setting applies wherever the app shows the number of the account. A new account starts with "Last four digits".

#### Scenario: Masked number

- **GIVEN** a credit card with the number 4111 1111 1111 1111 and the setting "Last four digits"
- **WHEN** the user opens the account settings
- **THEN** the number is shown as "•••• •••• •••• 1111"

#### Scenario: Full number

- **WHEN** the user selects "Full number" and clicks "OK"
- **THEN** the account settings show "4111 1111 1111 1111"

### Requirement: Fixed term deposits are not transfer targets

The app SHALL leave an account of the type "Fixed term deposit" out of every list that offers the user's own accounts as the target of a transfer.

#### Scenario: Target list

- **GIVEN** the accounts "Giro", "Savings", and "Festgeld 2027" with the type "Fixed term deposit"
- **WHEN** the user opens the list of own accounts in the payment window of "Giro"
- **THEN** the list offers "Savings" and does not offer "Festgeld 2027"

### Requirement: Reference account of a savings account

The app SHALL let the user set a "reference account" in the settings of an account of the type "Savings account". When a reference account is set, the payment window of the savings account offers only that account as a target among the user's own accounts.

#### Scenario: Reference account set

- **GIVEN** the accounts "Giro", "Second Giro", and "Savings" with the reference account "Giro"
- **WHEN** the user opens the list of own accounts in the payment window of "Savings"
- **THEN** the list offers only "Giro"

#### Scenario: No reference account

- **GIVEN** "Savings" has no reference account
- **WHEN** the user opens the same list
- **THEN** the list offers "Giro" and "Second Giro"

### Requirement: Transfer transactions to another account

The app SHALL offer "Transfer Transactions..." in the Tools menu when exactly one account that is not a portfolio is selected. The dialog names the source account and the number of its transactions, and the user selects a target account that is not a portfolio. The transferred transactions leave the source account and keep their category, comment, and checkmark.

#### Scenario: Account was set up again

- **GIVEN** "Giro old" with 3,000 transactions and the newly added "Giro" with 90 transactions of the same bank account
- **WHEN** the user chooses "Transfer Transactions..." on "Giro old", selects "Giro", and confirms
- **THEN** every transaction of "Giro old" that "Giro" does not have yet is in "Giro" with its category and comment

#### Scenario: Group selected

- **WHEN** an account group is selected
- **THEN** "Transfer Transactions..." is disabled

### Requirement: Identical transactions are skipped during a transfer

The app SHALL skip a transaction during "Transfer Transactions..." when the target account already has a transaction with the same booking date, amount, counterparty, and purpose. Skipped transactions stay in the source account. At the end the app reports how many transactions it transferred.

#### Scenario: Overlap of 90 transactions

- **GIVEN** 90 of the 3,000 transactions of "Giro old" also exist in "Giro"
- **WHEN** the transfer ends
- **THEN** the app reports that 2,910 new transactions were transferred
- **AND** "Giro old" still contains the 90 skipped transactions

#### Scenario: Nothing new

- **GIVEN** every transaction of the source account exists in the target account
- **WHEN** the transfer ends
- **THEN** the app reports that no new transactions were transferred

### Requirement: Warn before a transfer of transactions

The app SHALL state in the dialog of "Transfer Transactions..." that the operation cannot be undone and that the user should back up the database first, and it SHALL change nothing until the user confirms.

#### Scenario: Cancel

- **WHEN** the user opens the dialog, selects a target account, and clicks "Cancel"
- **THEN** both accounts are unchanged

### Requirement: Bank merger assistant

The app SHALL offer to update the account data when the bank directory reports that the bank of an account merged into another bank and changed its Bankleitzahl. The sheet "Bank Merger" lists each affected account with its "Old IBAN" and a field "New IBAN", and tells the user to look up the new IBANs at the bank first.

#### Scenario: Merger found after a directory update

- **GIVEN** the bank directory marks the Bankleitzahl of "Giro" as merged into another bank
- **WHEN** the app starts
- **THEN** the app asks whether the user wants to update the account data now
- **AND** when the user agrees, the sheet lists "Giro" with its old IBAN

#### Scenario: Later

- **WHEN** the user declines the question
- **THEN** the accounts stay unchanged
- **AND** the account error of the next failed refresh offers the assistant again

### Requirement: Update IBANs and keep the history

The app SHALL check each new IBAN that the user enters in the bank merger assistant, name the account whose new IBAN is invalid, and apply the change only when all entries are valid. After the change each account has its new IBAN, BIC, and bank name, and keeps all its transactions and settings.

#### Scenario: Valid new IBAN

- **GIVEN** "Giro" with 2,000 transactions
- **WHEN** the user enters a valid new IBAN for "Giro" and confirms
- **THEN** the settings of "Giro" show the new IBAN and the name of the new bank
- **AND** "Giro" still has its 2,000 transactions

#### Scenario: Invalid new IBAN

- **WHEN** the user enters an IBAN with a wrong checksum for "Giro"
- **THEN** the app says that the new IBAN of the account "Giro" is invalid
- **AND** no account is changed

### Requirement: Login data after a bank merger

The app SHALL ask the user, after the IBANs are updated, whether the login data changed as well, and open "Edit Login Data..." for the access when the user agrees.

#### Scenario: New user ID from the new bank

- **GIVEN** the merger assistant updated the IBAN of "Giro"
- **WHEN** the app asks whether to update the login data and the user agrees
- **THEN** the login data step opens for the access of "Giro"
