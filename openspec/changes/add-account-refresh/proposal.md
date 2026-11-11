# Proposal: Refresh accounts by hand and automatically without duplicates

## Why

The value of the app is a transaction list that is current and correct. The user wants new transactions to arrive without work, and must be able to trust that a transaction is in the list once, that nothing disappears, and that a problem at one bank does not block the others. Banks give no stable identity for a transaction, so the app has to decide which rows are the same.

## What Changes

- "Refresh All Accounts", a refresh of one account or one group, and "Cancel Refresh".
- An automatic refresh with the setting "Automatically refresh accounts" and an interval for each account.
- No automatic refresh while the app is locked or the Mac is in Power Nap. An automatic refresh never asks the user for anything.
- The accounts of one login are refreshed in one session.
- Each account shows the time of its last refresh or an error with the message of the bank.
- Fetched transactions are kept for good. A transaction that arrives again is not stored twice. A pending transaction is replaced by its booked version and keeps what the user added.
- New transactions are marked until the user has seen them.

## Capabilities

### New Capabilities

- `account-refresh`: when and how the app fetches new data, how it reports the result for each account, and how it merges fetched transactions into the stored history.

### Modified Capabilities

None.

## Impact

- Milestone: v0.1
- Issues: #6, #7, #40
- Modules: `Domain` owns the sync states, the identity of a transaction, and the merge of pending and booked rows. `Storage` keeps the history. `App` owns the commands, the schedule, the sidebar states, and the error popover. Every connector reports through the same states.
- Depends on the changes `add-fints-banking`, `add-web-banking-extensions`, `add-login-credentials`, `add-tan-handling`, and `add-app-lock`.
- The changes `add-notifications-and-menu-bar` and `add-categorization-rules` act on the result of a refresh.
- Decisions: none apply. [Architecture](../../../docs/architecture.md) describes the state machine and the identity of a transaction.

## Reference behavior

### Observed in MoneyMoney 2.5.3

- The File menu has "Refresh All Accounts" (⌘R) and "Cancel Refresh". The Account menu and the context menus have "Refresh Account" and "Refresh Accounts" (⇧⌘R). A button under the sidebar refreshes all accounts, and a single account shows a refresh button next to the date of its last refresh. See [analysis](../../../docs/research/moneymoney-analysis.md#main-window-u).
- The settings have "Automatically refresh accounts". The account settings have "Refresh" with "every two hours", "four times a day", "once a day", "once a week", "only manually", and "never". See [analysis](../../../docs/research/moneymoney-analysis.md#account-settings-u-s).
- "never" also excludes an account from the manual refresh (version history 2.3.21).
- No account is refreshed in the background while the app is locked (version history 2.4.49) or during a Power Nap (2.3.25), so that no two-factor authentication starts unattended.
- An account that needs an authorization shows an error that tells the user to run "Refresh Account" to perform it. An account with a failed refresh shows its error text in the sidebar in place of the balance (running app, strings).
- An error popover shows "The last refresh was aborted with the following error", the message, the date and time of the event, and a notice of the bank when there is one (strings, version history 2.1.1).
- Strings show "Canceled because of previous FinTS/HBCI server error." for accounts that follow a failed one in the same session.
- Accounts of the same bank are combined into one session to keep the number of logins and TAN entries low (https://moneymoney.app/sca/).
- All fetched transactions are stored for good on the Mac (https://moneymoney.app/help/).
- The app detects duplicates when it fetches transactions (version history 2.0.21 and later entries). Two identical transactions on the same day are both loaded (beta notes 2.5.4).
- After a payment the app starts a refresh of the account (version history 2.4.8).
- Notifications count new transactions, for example "3 new transactions" (strings).

### Decided for Moneten

- "Automatically refresh accounts" is on for a new installation, and a new account starts with "every two hours". The defaults of MoneyMoney were inferred from one installation.
- The app also runs the automatic refresh after launch and after the Mac wakes, for accounts that are due. This was not observed.
- A transaction is identified by the ID of the source when there is one. Otherwise it is identified by account, booking date, amount, counterparty account, end-to-end reference, and the purpose without regard to case and spacing. MoneyMoney's rule is not public.
- A pending transaction is replaced by a booked one only when exactly one pending transaction fits. When several fit, the app keeps all rows and marks them for review. This follows issue #7.
- A pending transaction that the bank no longer reports and that has no booked version is removed. This was not observed.
- A transaction that the user deleted does not come back at a later refresh. This was not observed.
- A transaction counts as seen when the user opens the view of its account, or marks all transactions as checked. MoneyMoney's rule was not observed.
- Without an Internet connection the automatic refresh does nothing and shows no error. This was not observed.
