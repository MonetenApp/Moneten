# Proposal: Keep offline and cash accounts by hand

## Why

Not all money sits in an account that the app can reach. Cash, a loan between friends, or an account at a bank without any interface still belong in the full picture. An offline account lets the user record these by hand, and it is also the place for imported history.

## What Changes

- The user can create an account without bank access, for example for cash.
- "Add Transaction..." adds a transaction by hand, with suggestions from earlier entries.
- The balance of an offline account is the sum of its transactions.
- "Create Offsetting Entry" copies a transaction of another account into an offline account with the opposite sign, for example a cash withdrawal.
- "Add Transaction..." also works in an account with bank access when the bank delivers no transactions for it.

## Capabilities

### New Capabilities

- `offline-accounts`: accounts without bank access, manual transactions, the computed balance, and offsetting entries.

### Modified Capabilities

None.

## Impact

- Milestone: v0.1
- Issues: #5
- Modules: `Domain` owns the balance arithmetic and the offsetting entry. `App` owns the transaction window.
- Depends on the change `add-account-setup` for the entry "Offline account / Cash" in the assistant.
- Depends on the change `add-account-management` for the account settings and the closed state.
- Depends on the change `add-transaction-list` for the list, and for editing and deleting.
- Decisions: none apply.

## Reference behavior

### Observed in MoneyMoney 2.5.3

- "Offline account / Cash" is the last entry under "Other" in the add account assistant. See [analysis](../../../docs/research/moneymoney-analysis.md#add-account-u-w).
- Offline accounts arrived in version 2.1.3. The shortcut ⌘+ adds a transaction (version history, 2.2.1).
- The entry window suggests completions from earlier data (2.2.13). A selected transaction serves as the template for the new one (2.2.9).
- An empty offline account asks the user to add at least the initial deposit or the initial payout with "Add Transaction" (interface strings).
- The balance of an offline account is computed from its transactions (2.4.47).
- "Create Offsetting Entry" lists the offline accounts in the context menu of a transaction (2.1.12). See [analysis](../../../docs/research/moneymoney-analysis.md#context-menus-u). Without a target the menu says "No offline accounts available" or "No other offline account available".
- An offline account can be marked as closed (2.2.16).
- Statements cannot be downloaded for an offline account (interface string).
- "Add Transaction..." is also in the context menu of an account with bank access. The version history names it as the way to get a bar chart when the bank provides no transactions (2.4.38).
- The transaction window rejects an amount of zero (interface string "Amount should not be zero.").

### Decided for Moneten

- The transaction window has a choice between "Debit" and "Credit" and takes the amount without a sign. Both labels are interface strings of MoneyMoney, but the window was not opened.
- An offsetting entry copies the date, the purpose, and the comment, and it uses the name of the source account as the counterparty. Which fields MoneyMoney copies was not observed.
- A manual transaction in an account with bank access survives every refresh and does not change the balance that the bank reports. MoneyMoney's handling was not observed.
- A new offline account uses the euro unless the user picks another currency.
