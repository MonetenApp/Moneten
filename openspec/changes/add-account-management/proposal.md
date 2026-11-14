# Proposal: Manage accounts and account groups

## Why

A user with several banks needs order. Accounts need names that mean something, groups such as "Private" and "Business", and a way to retire an account without losing its history. The settings of an account are also the place where the user corrects what the bank reported.

## What Changes

- Every account has a type, a name, a currency, bank details, an owner, and an initial balance.
- An account settings window shows and changes these values.
- An account can be marked as closed. The app then inserts a clearing entry, stops refreshing the account, and keeps its history.
- Accounts can be put into account groups. A group shows the transactions and the sum of its accounts.
- Removing an account removes its transactions after a warning. Removing a group keeps its accounts.

## Capabilities

### New Capabilities

- `account-management`: account types, the account settings, closed accounts, account groups, and the removal of accounts and groups.

### Modified Capabilities

None.

## Impact

- Milestone: v0.1
- Issues: #3, #5
- Modules: `Domain` owns the account and group types and the clearing entry. `Storage` keeps them. `App` owns the settings window and the sidebar actions.
- Depends on the change `add-main-window` for the sidebar and on `add-account-setup` for new accounts.
- The refresh interval and "Remove saved PIN" appear in the same window. The changes `add-account-refresh` and `add-login-credentials` specify them.
- The change `add-account-extras` adds icons, notes, the owner address, and more.
- Decisions: none apply.

## Reference behavior

### Observed in MoneyMoney 2.5.3

- The account settings window has the tabs for the account, "Account owner", and "Notes", with the fields listed in the [analysis](../../../docs/research/moneymoney-analysis.md#account-settings-u-s). It closes with "Cancel" or "OK".
- The account types in the settings are "Giro account", "Savings account", "Fixed term deposit", "Loan account", "Credit card", and "Other". Portfolios have their own view.
- "The account has been closed" inserts a clearing entry that brings the balance to zero. The user can edit that entry (strings, version history 2.2.17). Closed accounts do not appear on the dashboard (version history 2.1.14). Offline accounts can be closed too (2.2.16).
- The balance at the upper right comes from the bank and is not computed from the transactions (https://moneymoney.app/help/).
- The app determines the initial balance at setup (https://moneymoney.app/help/).
- The name of the account owner comes from the bank and can be changed in the settings (version history 2.2.13).
- Accounts can be grouped (version history 2.1.1). A group setting shows or hides the sum in the sidebar (2.2.16). A collapsed group shows its balance and markers (2.1.2).
- The remove dialogs say that all transactions of an account are removed, that the user could mark the account as closed instead, and that removing a group keeps accounts and transactions.
- PDF statements stay when an account is removed (https://moneymoney.app/help/dual-account/).
- The sidebar shows the currency of an account (version history 2.2.10).
- An extension can report several balances in different currencies and a number of bonus points for an account. When an extension reports no account type, the type is derived from the account number and name, where 16 characters or masked digits mean a credit card. The type is set only when the account is created (https://moneymoney.app/api/webbanking/). Strings show "Bonus points", "Portfolio number", and "Credit card number".

### Decided for Moneten

- An account is a colored square, as in MoneyMoney. MoneyMoney's own icon pictures are not copied; the migration takes only their color.
- The account type "Portfolio" is set by the bank or the extension and cannot be chosen by hand. This was not observed.
- An account without a type and without a hint in its number or name gets the type "Other". MoneyMoney's fallback is not documented.
- A group can contain other groups. Nesting of groups was not observed.
- A group with accounts in several currencies shows one sum for each currency. MoneyMoney's rule was not observed.
- When the user removes the closed mark, the app removes the clearing entry that it inserted, unless the user changed that entry. This was not observed.
- A closed account is left out of every refresh. MoneyMoney's help implies this and does not state it.
- Removing the last account of an access also removes the saved login data of that access. This was not observed.
- A removed group passes its accounts to the group above it. The target was not observed.
