# Tasks

One task per requirement of the spec. A task is checked only when a test or a check in the running app shows the behavior.

## 1. Requirements

- [x] 1.1 Create an offline account. Verified by "Add Account..." sheet; the debug harness creates two.
- [x] 1.2 An offline account has no bank functions. Verified by no refresh in this build.
- [ ] 1.3 Add a transaction by hand. Built for the earlier rule, with a choice between "Withdrawal" and "Deposit" and an amount without a sign. Tasks 3.3 and 3.4 change it.
- [ ] 1.4 Manual transactions are validated. Built in part: the amount must be a number. Finish it and verify it with a test or in the app.
- [ ] 1.5 Suggestions while typing. Build it and verify it with a test or in the app.
- [ ] 1.6 A selected transaction is the template. Build it and verify it with a test or in the app.
- [x] 1.7 Edit and delete manual transactions. Verified by transaction sheet and delete command.
- [ ] 1.8 The balance follows the transactions. Built for the earlier rule, which left pending transactions out and added every currency. Tasks 3.1 and 3.2 change it.
- [ ] 1.9 Hint for the first transaction. Built in part: the empty list offers "Add Transaction...". Finish it and verify it with a test or in the app.
- [ ] 1.10 Create an offsetting entry. Build it and verify it with a test or in the app.
- [x] 1.11 Manual transactions behave like fetched ones. Verified by rules run on save.
- [x] 1.12 An offline account can be closed. Verified by "The account has been closed" in the settings.
- [ ] 1.13 Manual transactions in an account with bank access. Build it and verify it with a test or in the app.

## 2. Integration

- [ ] 2.1 Check every scenario of the spec in a release build and record the result in the pull request.

## 3. Balance and signed amount

- [ ] 3.1 Write the test first in LedgerTests: an offline account in euros with an initial balance of 50,00 €, the transactions 100,00 €, -4,80 €, and -12,00 €, a pending transaction of -10,00 €, and a transaction of -10,00 USD has the balance 123,20 €.
- [ ] 3.2 Count pending rows and only rows in the account currency in `Ledger.computedBalance`. Task 3.2 of the change `add-charts` removes the same pending filter.
- [ ] 3.3 Write the test first: `AmountParser` reads "-4,80" as -4,80 and "50,00" as 50,00.
- [ ] 3.4 Replace the choice between "Withdrawal" and "Deposit" in `App/Sources/Views/Sheets.swift` with one signed amount field. Store the parsed value with its sign, not its absolute value, and show a stored amount with its sign when the window opens.

## Workflow follow-up

- Archive the change with `openspec archive add-offline-accounts` when every task is checked.
