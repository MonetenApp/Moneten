# Proposal: Add icons, notes, transfer rules, and repair tools to accounts

## Why

Users who switch from MoneyMoney expect the smaller comforts of its account settings. They tell accounts apart by icon, keep contract data in notes, and stop a fixed term deposit from showing up as a transfer target. Two repair tools save a long history when a bank changes its IBANs or when an account must be set up again.

## What Changes

- An account gets an icon from a built-in set, with an optional colored background.
- A "Notes" tab holds free text and a table of user-defined fields.
- The "Account owner" tab holds the postal address of the owner.
- The owner name follows the bank when the bank reports a new name.
- A credit card account has a setting for how its number is shown.
- A fixed term deposit is not offered as a transfer target. A savings account can name a reference account as its only transfer target.
- "Transfer Transactions..." moves the transactions of one account to another account.
- A bank merger assistant updates IBANs after a bank changes them and keeps the history.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `account-management`: adds requirements for icons, notes, the owner address, the card number display, transfer targets, the transfer of transactions, and bank mergers. The change `add-account-management` introduces this capability.

## Impact

- Milestone: later
- Issues: none yet
- Modules: `Domain` owns the transfer of transactions and the IBAN update. `App` owns the settings tabs and both assistants. `FinTSConnector` reports merged banks from the bank directory.
- Depends on the change `add-account-management`. The transfer target rules take effect in the change `add-sepa-transfers`. The owner address is used by the change `add-foreign-currency-transfers`.
- Decisions: none apply.

## Reference behavior

### Observed in MoneyMoney 2.5.3

- The account settings show an icon next to the name. The website describes an icon choice for each account (https://moneymoney.app/), and strings show "Colored background" (version history 2.2.0).
- The "Notes" tab and "User-defined fields" with "Attribute" and "Value" are in the strings. Notes can be kept as a table (version history 2.3.0).
- "Address of Account Owner" is in the strings. International transfers need the address of the sender.
- The owner name is taken from the bank when it changes (version history 2.2.13).
- "Display credit card number as" is in the strings.
- An account marked as a fixed term deposit is not listed as a target of own-account transfers, and a savings account can have a reference account that is then the only target (version history 2.2.16).
- "Transfer Transactions..." is in the Tools menu and is enabled for a single account. Its dialog says that identical transactions are skipped, that the operation cannot be undone, and that a backup is advised. Result texts report how many transactions were transferred (version history 2.5.0).
- A "Bank Merger" sheet asks whether to update the account data, shows "Old IBAN" and "New IBAN", and checks the new IBAN. The assistant covers German and Austrian banks (version history).
- Portfolios cannot be merged this way (https://moneymoney.app/help/dual-account/).

### Decided for MonetenMoneten

- The icon set is drawn for MonetenMoneten. MoneyMoney's icons are not copied.
- A new account gets a default icon for its account type. MoneyMoney's default was not observed.
- "Display credit card number as" has the values "Last four digits" and "Full number", and starts with "Last four digits". MoneyMoney's values were not observed.
- "Transfer Transactions..." moves transactions. They leave the source account. Skipped identical transactions stay in the source account. Whether MoneyMoney moves or copies was not observed.
- A transaction counts as identical when booking date, amount, counterparty, and purpose are equal. MoneyMoney's rule was not observed.
- The app offers the bank merger assistant at launch and after a refresh, once for each affected access, and again from the account error. The trigger in MoneyMoney was not observed.
