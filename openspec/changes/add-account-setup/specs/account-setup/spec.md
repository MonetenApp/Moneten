# Spec Delta

## Purpose

The account setup brings bank accounts into the app. This capability defines the assistant that adds accounts, the search for accounts that a bank adds later, and the change of the login data of an existing access.

## ADDED Requirements

### Requirement: Assistant with three steps

The app SHALL add accounts through an assistant that opens as a sheet on the main window. The assistant has three steps in a fixed order. The steps are the bank, the login data, and the accounts. Each step has "Cancel" and "Next", and the second and third step have "Back".

#### Scenario: Open the assistant from the menu

- **WHEN** the user chooses "Add Account..." in the Account menu
- **THEN** the assistant opens with the title "Add Account" and the field "IBAN or Bankleitzahl"

#### Scenario: Open the assistant from the sidebar

- **WHEN** the user chooses "Add account" in the menu under the sidebar, or "Add Account..." in the context menu of an account
- **THEN** the same assistant opens

#### Scenario: Go back one step

- **GIVEN** the assistant shows the login data step for "Musterbank"
- **WHEN** the user clicks "Back"
- **THEN** the assistant shows the bank step with the IBAN that the user entered before

### Requirement: Find the bank by IBAN or Bankleitzahl

The app SHALL find the bank from an IBAN or a Bankleitzahl that the user enters in the first step, and it SHALL show the name of the bank before the user continues. The entry can contain spaces and lower case letters.

#### Scenario: IBAN entered

- **WHEN** the user enters "de02 1203 0000 0000 2020 51"
- **THEN** the app shows the name of the bank with the Bankleitzahl 12030000
- **AND** "Next" is enabled

#### Scenario: Bankleitzahl entered

- **WHEN** the user enters "12030000"
- **THEN** the app shows the name of the same bank

#### Scenario: Empty field

- **WHEN** the user clicks "Next" with an empty field and "Other" not selected
- **THEN** the app asks for an IBAN or a Bankleitzahl and stays on the first step

### Requirement: Check the IBAN before any connection

The app SHALL check an IBAN for its country code, its length for that country, and its checksum, and it SHALL name the failed check. The app contacts no bank while the IBAN is invalid.

#### Scenario: Wrong checksum

- **WHEN** the user enters "DE03120300000000202051"
- **THEN** the app says that the checksum of the IBAN is invalid and asks the user to look for typing errors

#### Scenario: Too short

- **WHEN** the user enters "DE0212030000000020205"
- **THEN** the app says that an IBAN with the country code DE has 22 characters

#### Scenario: Unknown country code

- **WHEN** the user enters an IBAN that starts with "XX"
- **THEN** the app says that the IBAN starts with an unexpected country code

### Requirement: Check the Bankleitzahl

The app SHALL reject a Bankleitzahl that is not in the bank directory, and it SHALL tell the user when a Bankleitzahl is outdated, also when it is part of an IBAN.

#### Scenario: Unknown Bankleitzahl

- **WHEN** the user enters "00000000"
- **THEN** the app says that the Bankleitzahl is invalid

#### Scenario: Outdated Bankleitzahl after a bank merger

- **GIVEN** the bank directory marks the Bankleitzahl 10010010 as replaced
- **WHEN** the user enters an IBAN that contains 10010010
- **THEN** the app says that the IBAN contains an outdated Bankleitzahl and asks for the current IBAN

### Requirement: Country menu

The app SHALL offer a country menu in the first step with the entries for Germany, Austria, and the European Union. The selected country decides which banks the app finds and which services "Other" lists. The menu starts with Germany.

#### Scenario: Service of another country

- **GIVEN** an installed extension declares a service for Austria only
- **WHEN** the user selects Austria in the country menu
- **THEN** "Other" lists that service
- **AND** "Other" does not list it while Germany is selected

### Requirement: Other services

The app SHALL offer the choice "Other" in the first step as an alternative to the IBAN field. "Other" lists every service that an installed web banking extension declares, in alphabetical order, and "Offline account / Cash" as the last entry.

#### Scenario: Extension service

- **GIVEN** an installed extension declares the service "Musterbroker"
- **WHEN** the user selects "Other" and opens its menu
- **THEN** the menu contains "Musterbroker" and "Offline account / Cash"

#### Scenario: Offline account

- **WHEN** the user selects "Offline account / Cash" and clicks "Next"
- **THEN** the assistant asks for the name and the currency of the account and contacts no bank

### Requirement: Choose the access method

The app SHALL show the access methods that are possible for the bank under "Access with" when there is more than one, and it SHALL let the user choose one. A method that the app knows and that the bank does not offer is listed as disabled with its reason.

#### Scenario: Bank with FinTS and an extension

- **GIVEN** "Musterbank" offers FinTS with a TAN method, and an installed extension also supports "Musterbank"
- **WHEN** the user enters the Bankleitzahl of "Musterbank"
- **THEN** "Access with" lists "FinTS/HBCI with TAN method" and the extension
- **AND** "FinTS/HBCI with TAN method" is selected

#### Scenario: Only one method

- **GIVEN** "Musterbank" offers only FinTS with a TAN method and no extension supports it
- **WHEN** the user enters its Bankleitzahl
- **THEN** the app shows no choice and continues with FinTS

### Requirement: Explain why a bank cannot be added

The app SHALL tell the user why no access is possible when it finds the bank and knows no way to reach it. The message names the bank and the ways that would work, which are an extension for that bank or the optional subscription.

#### Scenario: Bank without a FinTS server

- **GIVEN** the bank directory lists "Neobank Muster" without a FinTS address, and no installed extension supports it
- **WHEN** the user enters an IBAN of "Neobank Muster" and clicks "Next"
- **THEN** the app says that this bank does not provide a FinTS/HBCI server
- **AND** the app says that an extension can add support for the bank
- **AND** the assistant stays on the first step

### Requirement: Ask for the login data in the words of the bank

The app SHALL ask for the login data in the second step with the field names that the bank or the extension uses, and it SHALL mark which fields are optional. "Next" stays disabled until every required field has a value.

#### Scenario: Bank with its own field name

- **GIVEN** "Musterbank" calls its login name "VR-NetKey or alias"
- **WHEN** the assistant shows the second step
- **THEN** the first field has the label "VR-NetKey or alias" and the second field has the label "PIN"

#### Scenario: Optional customer ID

- **GIVEN** "Musterbank" accepts a customer ID in addition to the user ID
- **WHEN** the user fills in "User ID" and "PIN" and leaves the customer ID empty
- **THEN** "Next" is enabled

### Requirement: Check the format of login fields

The app SHALL check each login field against the format that the bank directory or the extension declares for it, before it contacts the bank, and name the field and the broken rule. Formats cover digits only, a minimum and a maximum length, an exact length, characters that are not allowed, an email address, a date, and a phone number with or without a country code.

#### Scenario: User ID with a fixed length

- **GIVEN** "Musterbank" declares a user ID of exactly 10 digits
- **WHEN** the user enters "12345" and clicks "Next"
- **THEN** the app says that the user ID must be 10 digits long and stays on the second step

#### Scenario: Date of birth

- **GIVEN** an extension declares a field "Date of birth" as a date
- **WHEN** the user enters "1.2.80"
- **THEN** the app says that the date of birth must be in the format DD.MM.YYYY

### Requirement: Show what the bank requires before the first login

The app SHALL show a hint in the second step when the bank directory or the extension holds a note for the bank, for example that the user must apply for the FinTS access first or must set up a TAN method on the bank website first.

#### Scenario: Access must be requested

- **GIVEN** the note for "Musterbank" says that the FinTS access must be requested from the bank
- **WHEN** the assistant shows the second step
- **THEN** the app shows that note above the fields

#### Scenario: Credit card

- **WHEN** the user opens the help of the first step
- **THEN** the help says that a credit card is added with the Bankleitzahl of the bank that issued the card, or with "Look for New Accounts..." on the giro account of that bank

### Requirement: Report a failed login without leaving the assistant

The app SHALL show the message of the bank when the login fails, keep the user on the second step with the entries intact except for the PIN, and store nothing.

#### Scenario: Wrong PIN

- **WHEN** the user enters a wrong PIN and clicks "Next"
- **THEN** the app shows that the bank did not accept the PIN, with the text that the bank sent
- **AND** the PIN field is empty and the user ID is still filled in
- **AND** the app does not try the login again by itself

#### Scenario: Login name is an alias that the bank rejects

- **WHEN** the bank rejects the alias "erika.m"
- **THEN** the app asks for the user ID in place of the alias

### Requirement: Progress and cancel during setup

The app SHALL show the progress text "Setting up Accounts" with the current step of the bank dialog while it talks to the bank, and it SHALL let the user cancel at any time. A canceled setup leaves no access, no account, and no saved PIN.

#### Scenario: Cancel while the bank asks for a TAN

- **GIVEN** the bank asks for a TAN during the first login
- **WHEN** the user cancels the TAN dialog and then clicks "Cancel" in the assistant
- **THEN** the sidebar shows no new account
- **AND** a new start of the assistant begins with empty fields

### Requirement: Select the accounts to add

The app SHALL list in the third step every account that the bank reports for the login, with the name, the account type, the IBAN or account number, and the currency. All accounts are selected at first. The user selects which ones to add and needs at least one.

#### Scenario: Three accounts found

- **GIVEN** the bank reports a giro account, a savings account, and a portfolio for the login
- **WHEN** the assistant shows the third step
- **THEN** the list has three rows and all three are selected

#### Scenario: Nothing selected

- **WHEN** the user deselects all accounts
- **THEN** the button that finishes the assistant is disabled

#### Scenario: Bank reports no account

- **WHEN** the login succeeds and the bank reports no account
- **THEN** the app says that the bank reported no accounts for this login, and suggests the user ID in place of an alias or a request for FinTS access at the bank

### Requirement: Do not add an account twice

The app SHALL mark an account in the third step as already present when the app has the same account with a bank access or as an offline account, also a closed one, and it SHALL not add that account again. A closed account without a bank access is left as it is, and the account of the bank is added as a new account.

#### Scenario: Existing giro account

- **GIVEN** the app already has the account with the IBAN DE02120300000000202051
- **WHEN** the bank reports that IBAN again together with a new savings account
- **THEN** the row of the giro account is marked as already present and cannot be selected
- **AND** only the savings account is added

### Requirement: Tell the accounts of a bank apart

The app SHALL treat two accounts as the same account only when they have the same currency and the same IBAN. When one of them has no IBAN, they are the same when they have the same currency, account number, and Bankleitzahl, and, when the account in the app has a bank access, the same ID at the bank. The ID at the bank is the IBAN when the bank reports one, and else the account number with the subaccount number.

#### Scenario: Same IBAN in another currency

- **GIVEN** the app has the offline account "Giro USD" in USD with the IBAN DE02120300000000202051
- **WHEN** the bank reports that IBAN in EUR
- **THEN** the row is not marked as present
- **AND** the setup adds a new account in EUR and leaves "Giro USD" as it is

#### Scenario: Closed account without a bank access

- **GIVEN** the app has the closed migrated account "Giro (alt)" in EUR with the IBAN DE02120300000000202051, and no other account with that IBAN
- **WHEN** the bank reports that IBAN in EUR
- **THEN** the row is not marked as present
- **AND** the setup adds a new account and leaves "Giro (alt)" closed and without a bank access

#### Scenario: Another subaccount of the same account number

- **GIVEN** the app has the account "Sparkonto" with a bank access, the account number 9, and the subaccount number 01 at the Bankleitzahl 12030000
- **WHEN** the bank reports the subaccounts 01 and 02 of the account number 9
- **THEN** the row of subaccount 01 is marked as already present
- **AND** the row of subaccount 02 can be selected and is added as a new account

### Requirement: Finish the setup

The app SHALL, when the user finishes the assistant, add the selected accounts to the sidebar under one access, select the first new account, and start the first refresh of the new accounts.

#### Scenario: Two accounts added

- **WHEN** the user finishes the assistant with a giro account and a savings account selected
- **THEN** both accounts appear in the sidebar with the names that the bank reported
- **AND** the app starts a refresh that fetches their balances and transactions

#### Scenario: Assistant opened on a group

- **GIVEN** the user opened the assistant from the context menu of the account group "Private"
- **WHEN** the user finishes the assistant
- **THEN** the new accounts are in the group "Private"

### Requirement: Look for new accounts

The app SHALL offer "Look for New Accounts..." for an account with a bank access. The command asks the bank for the accounts of that login and opens the account selection with only the accounts that the app does not have yet.

#### Scenario: New credit card

- **GIVEN** the bank added a credit card to the login of the giro account "Giro"
- **WHEN** the user chooses "Look for New Accounts..." on "Giro"
- **THEN** the app shows the progress text "Looking for new Accounts"
- **AND** the selection lists the credit card and not "Giro"

#### Scenario: No new account

- **WHEN** the bank reports only accounts that the app already has
- **THEN** the app says that there are no new accounts

### Requirement: Edit the login data of an access

The app SHALL offer "Edit Login Data..." for an account with a bank access. The command opens the login data step with the stored values except secrets, lets the user change every field, and applies the change to all accounts of that access.

#### Scenario: New user ID

- **GIVEN** the bank gave the user a new user ID
- **WHEN** the user chooses "Edit Login Data...", enters the new user ID and the PIN, and confirms
- **THEN** the next refresh of all accounts of that access uses the new user ID

#### Scenario: Login data is checked first

- **WHEN** the user confirms changed login data that the bank rejects
- **THEN** the app shows the message of the bank
- **AND** the app keeps the old login data

### Requirement: Switch the access method and keep the history

The app SHALL let the user choose another access method for an existing access in "Edit Login Data...". After the switch every account keeps its transactions, categories, comments, and settings.

#### Scenario: From an extension to FinTS

- **GIVEN** the account "Giro" with 1,200 transactions uses an extension, and the bank now offers FinTS
- **WHEN** the user chooses "Edit Login Data...", selects "FinTS/HBCI with TAN method", enters the login data, and confirms
- **THEN** "Giro" still has its 1,200 transactions
- **AND** the next refresh of "Giro" runs through FinTS

#### Scenario: Account not available with the new method

- **GIVEN** an access with a giro account and a credit card
- **WHEN** the user switches to a method through which the bank reports only the giro account
- **THEN** the app says that the credit card is not available with the new method and asks whether to continue
- **AND** when the user continues, the credit card stays in the app with its transactions and is no longer refreshed

### Requirement: Reinitialize an access after an aborted authentication

The app SHALL tell the user to use "Edit Login Data..." when a bank reports that the access must be set up again, for example after an aborted two-factor authentication or a new TAN method, and running the command with unchanged values SHALL perform that setup.

#### Scenario: TAN method changed at the bank

- **GIVEN** the user moved from chipTAN to pushTAN on the bank website
- **WHEN** the next refresh fails with a message of the bank about the TAN method
- **THEN** the account error names "Edit Login Data..." as the next step
- **AND** after the user runs the command and confirms, the app offers the new TAN methods of the bank

### Requirement: List of supported banks

The app SHALL show a list of the banks and services it can reach, with a search field, the access methods for each entry, and the note that belongs to the entry. The Help menu opens the list.

#### Scenario: Search for a bank

- **WHEN** the user opens the list and types "Muster"
- **THEN** the list shows "Musterbank" with "FinTS/HBCI with TAN method"

#### Scenario: Service from an extension

- **GIVEN** an installed extension declares the service "Musterbroker"
- **WHEN** the user opens the list
- **THEN** the list contains "Musterbroker" with the name of the extension as its access method
