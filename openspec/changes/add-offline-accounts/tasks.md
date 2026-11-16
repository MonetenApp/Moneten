# Tasks

One task per requirement of the spec. A task is checked only when a test or a check in the running app shows the behavior.

## 1. Requirements

- [x] 1.1 Create an offline account. Verified by "Add Account..." sheet; the debug harness creates two.
- [x] 1.2 An offline account has no bank functions. Verified by no refresh in this build.
- [x] 1.3 Add a transaction by hand. Verified by TransactionDraftTests "The amount keeps its sign" and the debug app: -4,80 and 50,00 in "Wallet" give 45,20 € (#272).
- [x] 1.4 Manual transactions are validated. Verified by TransactionDraftTests "An amount of zero, text that is not a number, and an empty field are refused" and the debug app: 0,00 shows "The amount should not be zero." and the window stays open. The date picker always holds a date (#272).
- [x] 1.5 Suggestions while typing. Verified by TransactionDraftTests "Suggestions complete the typed start of a name..." and "A chosen suggestion fills the name, and the purpose and the category while they are empty", PerformanceTests "Suggestions for a typed name...", and the debug app: "Bäck" suggests "Bäckerei Gutbrot", which fills the purpose and "Groceries" (#272).
- [x] 1.6 A selected transaction is the template. Verified by TransactionDraftTests "A selected transaction fills the name, the amount with its sign, the purpose, and the category" and the debug app: a selected row of -12,00 € "Kiosk am Markt" fills "-12,00" and today's date (#272).
- [x] 1.7 Edit and delete manual transactions. Verified by transaction sheet and delete command.
- [x] 1.8 The balance follows the transactions. Verified by LedgerTests "An offline account adds its initial balance and its rows in its currency..." (task 3.1) (#272).
- [x] 1.9 Hint for the first transaction. Verified in the debug app: an empty loan account asks for "the initial payout", an empty cash account for "the initial deposit" (#272).
- [ ] 1.10 Create an offsetting entry. Build it and verify it with a test or in the app.
- [x] 1.11 Manual transactions behave like fetched ones. Verified by rules run on save.
- [x] 1.12 An offline account can be closed. Verified by "The account has been closed" in the settings.
- [x] 1.13 Manual transactions in an account with bank access. Verified by LedgerTests "A manual row in an account with bank access counts in the daily balance and leaves the bank balance unchanged", ReconcileTests "A refresh keeps a row that the user added by hand in an account with bank access", and the debug app with the made-up FinTS helper: a manual row in "Kreditkarte" stays through a refresh, and the bank balance stays -120,00 € (#272).
- [ ] 1.14 An offsetting entry stays in its currency. Tasks 3.3 and 3.4 build it.
- [ ] 1.15 Fields of an offsetting entry. Tasks 3.3 and 3.4 build it.
- [ ] 1.16 Category of an offsetting entry. Tasks 3.3 and 3.4 build it.
- [x] 1.17 Reading a typed amount. Verified by TransactionDraftTests "A reading with more decimal places than the currency has does not count, and the decimal mark of the region decides a tie" and "An amount with more decimal places than its currency has is refused and never rounds" (#272).
- [x] 1.18 A refresh never takes a manual transaction. Verified by ReconcileTests "A refresh adds a delivered row with the day and the amount of a manual row and leaves the manual row alone", ManualMarkTests "A refresh stores the delivered row next to a manual row with the same day and amount" and "Deleting a manual row keeps no record, so a refresh still adds the delivered row", and the export round trip of `isManual` (#272).
- [x] 1.19 A manual transaction is part of the bank balance. Verified by LedgerTests "After a real first refresh, a manual deposit moves the initial balance..." and "Only a manual row booked by the day of the bank balance...", and ReconcileTests "The first refresh derives the initial balance with the manual rows..." (#272).
- [x] 1.20 What a transaction in an account with bank access can change. Verified by TransactionDraftTests "What the window can change..." (#272).

## 2. Integration

- [ ] 2.1 Check every scenario of the spec in a release build and record the result in the pull request.

## 3. Balance and signed amount

- [x] 3.1 Write the test first in LedgerTests: an offline account in euros with an initial balance of 50,00 €, the transactions 100,00 €, -4,80 €, and -12,00 €, a pending transaction of -10,00 €, a pending transaction of -5,00 € with `review != nil`, and a transaction of -10,00 USD has the balance 123,20 €. The code is `Transaction.isInSum(of:)`, which #139 adds and which `Account.isInBalance` calls, and task 3.2 of the change `add-charts` changes it for pending rows. This change adds no second filter. Done in #272 with LedgerTests "An offline account adds its initial balance and its rows in its currency, pending rows included, except one marked for review".
- [x] 3.2 Replace the choice between "Withdrawal" and "Deposit" in `App/Sources/Views/Sheets.swift` with one signed amount field. `save()` stores the value of `AmountParser` with its sign, without `abs` and the factor of `isDeposit`. `load()` shows a stored amount with its sign. `AmountParser` keeps a leading minus already, so verify it in the app: -4,80 stores -4,80 €, 50,00 stores 50,00 €, and editing a row of -12,00 € shows -12,00. Done in #272, verified in the debug app.
- [ ] 3.3 Write the tests first for the fields of an offsetting entry in `Domain`, with the values of the scenarios of "An offsetting entry stays in its currency", "Fields of an offsetting entry", and "Category of an offsetting entry": name, purpose, comment, category "Cash" with `categorizedBy` `.manual` that `Categorizer.categorize` keeps against the rule for "Fees", booking date and value date 05.11.2026, and counterparty DE02120300000000202051. A source in "Uncategorized" gives `categorizedBy` `.none`, and the rule for "Geldautomat" sorts the entry into "Cash". A category restricted to "Business" ends in "Uncategorized" without a matching rule and in "Household" with one. A source account without an IBAN gives no counterparty account. For a row of -200,00 USD, "Dollar Cash" in US dollars can take the entry and "Wallet" in euros cannot. A row of -50,00 € and a row of -200,00 USD selected together leave neither "Wallet" nor "Dollar Cash".
- [ ] 3.4 Build the offsetting entry and the choice of offline accounts in `Domain` so that the tests of task 3.3 pass. Task 1.10 uses both for the menu.

## Workflow follow-up

- Archive the change with `openspec archive add-offline-accounts` when every task is checked.
