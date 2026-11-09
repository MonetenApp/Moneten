# Proposal: Add bank accounts with a three-step assistant

## Why

A banking app is empty until the first account is in it. The setup must work for a person who knows only the IBAN and the online banking login. It must also say in plain words why a bank cannot be added, because that is the first thing a new user will hit.

## What Changes

- "Add Account..." opens an assistant with three steps. The steps are the bank, the login data, and the accounts.
- The first step accepts an IBAN or a Bankleitzahl, or a service from "Other". "Other" lists the services of installed extensions and "Offline account / Cash".
- The app checks the IBAN and the Bankleitzahl before it contacts a bank.
- When a bank offers several access methods, the user chooses one under "Access with". A method that is not possible shows its reason.
- The third step lists the accounts that the bank reports. The user selects which ones to add.
- "Look for New Accounts..." finds accounts that the bank added after the setup.
- "Edit Login Data..." changes the login data or the access method of an existing access and keeps all transactions.

## Capabilities

### New Capabilities

- `account-setup`: the assistant that adds accounts, the search for new accounts, and the change of login data.

### Modified Capabilities

None.

## Impact

- Milestone: v0.1
- Issues: #5, #13
- Modules: `App` owns the assistant. `FinTSConnector` owns the bank directory and the first dialog with the bank. `ExtensionConnector` supplies the services under "Other". `Domain` owns the IBAN check.
- Depends on the change `add-fints-banking` for the bank dialog, on `add-login-credentials` for the PIN prompt and the choice to save a PIN, on `add-tan-handling` for a TAN during setup, on `add-web-banking-extensions` for the services under "Other", and on `add-offline-accounts` for "Offline account / Cash".
- The changes `add-hbci-keys-and-chipcards` and `add-aggregator-subscription` add their own setup steps later.
- Decisions: [ADR 0003](../../../docs/decisions/0003-fints-through-hbci4swift.md), [ADR 0009](../../../docs/decisions/0009-database-password-as-in-moneymoney.md).

## Reference behavior

### Observed in MoneyMoney 2.5.3

- The assistant is a sheet on the main window with the field "IBAN or Bankleitzahl", the choice "Other", a country menu at the lower left, a help button, "Cancel", and "Next". See [analysis](../../../docs/research/moneymoney-analysis.md#add-account-u-w).
- The website names the three steps as IBAN or service, login data, and account selection (https://moneymoney.app/).
- The country menu has three entries. The version history says that the European Union can be selected (2.4.37), and the banks page tells users to select Germany or Austria first for one card issuer (https://moneymoney.app/banken/).
- Strings show the checks for an invalid IBAN, an IBAN that is too short or too long for its country, an unexpected country code, an invalid Bankleitzahl, and an outdated Bankleitzahl.
- Strings show the access methods "FinTS/HBCI with TAN method", "HBCI keyfile", "HBCI chipcard", "PSD2 Access", "Web Scraping", and "API Access", and reasons such as "This bank does not provide a FinTS/HBCI server."
- Strings show "Duplicate IBAN" and "Duplicate account number" for accounts that already exist.
- Strings show format checks for login fields, for example a required number of digits, a maximum length, invalid characters, an invalid email address, a date of birth in the format DD.MM.YYYY, and a phone number with or without a country code.
- "Look for New Accounts..." and "Edit Login Data..." are commands of an account in the Account menu and the context menu. See [analysis](../../../docs/research/moneymoney-analysis.md#context-menus-u).
- "Edit Login Data" switches the access method of an existing access (https://moneymoney.app/sca/, version history 2.4.x).
- Bank messages tell the user to apply for FinTS access first, to set up a TAN method on the bank website first, or to use the user ID in place of an alias.
- The Help menu has "Supported Banks (Germany)..." and "Supported Banks (Europe)...".
- A credit card is added with the bank code of the issuing bank, or with "Look for New Accounts" on the giro account.

### Decided for MonetenMoneten

- "Other" lists only the services of installed extensions and "Offline account / Cash". MoneyMoney also lists built-in credit card services that its vendor maintains.
- The bank directory is the institute list that comes with the FinTS product registration. MoneyMoney's source was not observed.
- The supported banks list is a window in the app that reads the bank directory and the installed extensions. MoneyMoney opens a web page.
- All accounts in the third step are selected at first. The initial selection was not observed.
- "Cancel" at any step leaves no access, no account, and no saved PIN. This was not observed.
- "Edit Login Data" checks the new login data with the bank before it replaces the old data. This was not observed.
- When the access method changes, the app matches accounts by IBAN, or by account number and Bankleitzahl. The matching rule was not observed.
- The subscription appears as an access method only when the change `add-aggregator-subscription` is built.
