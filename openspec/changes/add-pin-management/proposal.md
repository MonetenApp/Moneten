# Proposal: Change and unblock the PIN of an online banking access

## Why

Banks force a PIN change at the first login with a start PIN and after some security events, and they block a PIN after wrong attempts. A user who works only with the app, and not with the bank website, needs both repairs inside the app. Without them the setup of some accesses cannot finish.

## What Changes

- An assistant "Change PIN of PIN/TAN Interface..." in the Tools menu changes the PIN on the server of the bank and confirms the change with a TAN.
- An assistant "Unblock PIN with TAN ..." lifts a block where the bank allows it.
- When a bank demands a PIN change during setup or a refresh, the app leads into the same assistant and continues afterwards.
- After a successful change the app replaces the PIN that it holds for the access.

## Capabilities

### New Capabilities

- `pin-management`: changing and unblocking the PIN of an access on the server of the bank.

### Modified Capabilities

None.

## Impact

- Milestone: later
- Issues: none yet
- Modules: `FinTSConnector` owns the two orders. `App` owns both assistants. `Storage` updates the saved PIN.
- Depends on the changes `add-fints-banking`, `add-login-credentials`, and `add-tan-handling`.
- Until this change is built, the app tells the user to change or unblock the PIN on the website of the bank, as the change `add-fints-banking` specifies.
- Decisions: [ADR 0009](../../../docs/decisions/0009-database-password-as-in-moneymoney.md).

## Reference behavior

### Observed in MoneyMoney 2.5.3

- The Tools menu has "Change PIN of PIN/TAN Interface..." and "Unblock PIN with TAN ...". See [analysis](../../../docs/research/moneymoney-analysis.md#menus-and-keyboard-shortcuts-u). Both are enabled whatever is selected in the sidebar.
- The assistant explains that it changes the PIN on the server of the bank, and that "Edit Login Data" is the command for a PIN that is only stored in the app (strings).
- Strings show the fields for the current PIN, the new PIN, and its repetition, and the checks that the two new entries are equal, that the new PIN differs from the old one, and that it has the length or the number of digits that the bank requires.
- Strings show that the change is confirmed with a TAN, a progress text, a success text, and the message that a server does not support the change and that the website of the bank must be used.
- Strings show "Unblock using" with a TAN method, a progress text, a success text, and the messages that a bank denied the unblocking or does not support it, both with the advice to ask the support of the bank.
- The start PIN can be changed during setup when the server demands it, and later through the Tools menu (version history 2.2.12). A blocked PIN can be unblocked with a TAN (2.2.14).
- The strings use the word of the bank for the secret, for example PIN or password.

### Decided for Moneten

- Each assistant starts with a list of the FinTS accesses, with the access of the selected account preselected. How MoneyMoney chooses the access was not observed.
- After a successful change the app updates the saved PIN, or the PIN in memory, of the access. This was not observed.
- When a change fails, the app keeps the old PIN. When the result is unclear because the connection broke, the app forgets the PIN of the access and asks at the next login. This was not observed.
- After a PIN change that the server demanded during setup or refresh, the app continues the interrupted step by itself. MoneyMoney's flow was not observed.
