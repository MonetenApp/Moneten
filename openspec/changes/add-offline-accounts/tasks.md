# Tasks

One task per requirement of the spec. A task is checked only when a test or a check in the running app shows the behavior.

## 1. Requirements

- [x] 1.1 Create an offline account. Verified by "Add Account..." sheet; the debug harness creates two.
- [x] 1.2 An offline account has no bank functions. Verified by no refresh in this build.
- [ ] 1.3 Add a transaction by hand. Built for the earlier rule, with a choice between "Withdrawal" and "Deposit" and an amount without a sign. Task 3.2 changes it.
- [ ] 1.4 Manual transactions are validated. Built in part: the amount must be a number. Finish it and verify it with a test or in the app.
- [ ] 1.5 Suggestions while typing. Build it and verify it with a test or in the app.
- [ ] 1.6 A selected transaction is the template. Build it and verify it with a test or in the app.
- [x] 1.7 Edit and delete manual transactions. Verified by transaction sheet and delete command.
- [ ] 1.8 The balance follows the transactions. Built for the earlier rule, which left pending transactions out and added every currency. Task 3.1 checks the new rule.
- [ ] 1.9 Hint for the first transaction. Built in part: the empty list offers "Add Transaction...". Finish it and verify it with a test or in the app.
- [ ] 1.10 Create an offsetting entry. Build it and verify it with a test or in the app.
- [x] 1.11 Manual transactions behave like fetched ones. Verified by rules run on save.
- [x] 1.12 An offline account can be closed. Verified by "The account has been closed" in the settings.
- [ ] 1.13 Manual transactions in an account with bank access. Build it and verify it with a test or in the app.
- [ ] 1.14 An offsetting entry stays in its currency. Tasks 3.3 and 3.4 build it.
- [ ] 1.15 Fields of an offsetting entry. Tasks 3.3 and 3.4 build it.
- [ ] 1.16 Category of an offsetting entry. Tasks 3.3 and 3.4 build it.

## 2. Integration

- [ ] 2.1 Check every scenario of the spec in a release build and record the result in the pull request.

## 3. Balance and signed amount

- [ ] 3.1 Write the test first in LedgerTests: an offline account in euros with an initial balance of 50,00 €, the transactions 100,00 €, -4,80 €, and -12,00 €, a pending transaction of -10,00 €, a pending transaction of -5,00 € with `needsReview`, and a transaction of -10,00 USD has the balance 123,20 €. The code is `Transaction.isInSum(of:)` of PR #139, which `Account.isInBalance` calls, and task 3.2 of the change `add-charts` changes it for pending rows. This change adds no second filter.
- [ ] 3.2 Replace the choice between "Withdrawal" and "Deposit" in `App/Sources/Views/Sheets.swift` with one signed amount field. `save()` stores the value of `AmountParser` with its sign, without `abs` and the factor of `isDeposit`. `load()` shows a stored amount with its sign. `AmountParser` keeps a leading minus already, so verify it in the app: -4,80 stores -4,80 €, 50,00 stores 50,00 €, and editing a row of -12,00 € shows -12,00.
- [ ] 3.3 Write the tests first for the fields of an offsetting entry in `Domain`, with the values of the scenarios of "An offsetting entry stays in its currency", "Fields of an offsetting entry", and "Category of an offsetting entry": name, purpose, comment, category "Cash" with `categorizedBy` `.manual` that `Categorizer.categorize` keeps against the rule for "Fees", booking date and value date 05.11.2026, and counterparty DE02120300000000202051. A source in "Uncategorized" gives `categorizedBy` `.none`, and the rule for "Geldautomat" sorts the entry into "Cash". A category restricted to "Business" ends in "Uncategorized" without a matching rule and in "Household" with one. A source account without an IBAN gives no counterparty account. For a row of -200,00 USD, "Dollar Cash" in US dollars can take the entry and "Wallet" in euros cannot.
- [ ] 3.4 Build the offsetting entry and the choice of offline accounts in `Domain` so that the tests of task 3.3 pass. Task 1.10 uses both for the menu.

## Workflow follow-up

- Archive the change with `openspec archive add-offline-accounts` when every task is checked.
