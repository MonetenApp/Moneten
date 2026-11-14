# Proposal: Keep offline and cash accounts by hand

## Why

Not all money sits in an account that the app can reach. Cash, a loan between friends, or an account at a bank without any interface still belong in the full picture. An offline account lets the user record these by hand, and it is also the place for imported history.

## What Changes

- The user can create an account without bank access, for example for cash.
- "Add Transaction..." adds a transaction by hand, with suggestions from earlier entries.
- The balance of an offline account is its initial balance plus the sum of its transactions.
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
- Depends on the change `add-charts` for the rule that pending transactions count, and on the change `add-split-transactions` for how the parts of a split count.
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

- The transaction window has one amount field with a sign. A leading minus means money out, and a number without a sign means money in. The user types the amount as the bank statement shows it, and no separate switch can turn a typed -4,80 into +4,80.
- An offsetting entry keeps the name, the purpose, the comment, and the category of the source transaction. The copied category counts as chosen by hand, so a rule does not move it. Its booking date and value date are the booking date of the source, and the IBAN and BIC of the source account become its counterparty account. A cash withdrawal then reads "Geldautomat" in both accounts, so rules and search find both rows, and the counterparty account still shows where the money came from. A category restricted to another account falls back to the default category, so that the restriction holds.
- The balance of an offline account is its initial balance plus its transactions in the account currency. A new offline account starts at an initial balance of 0, and the user can set another one, for example the cash already in the wallet. Pending transactions count, by the one rule of the change `add-charts`, except one marked for review, as the change `add-account-refresh` decides. A transaction in another currency does not change the balance, because the app converts no currencies.
- A manual transaction in an account with bank access survives every refresh and does not change the balance that the bank reports. MoneyMoney's handling was not observed.
- A new offline account uses the euro unless the user picks another currency.
