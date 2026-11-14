# Design

## Context

This change is part of the first build of the app. The build is a Swift package with the modules `Domain`, `Storage`, `Import`, and `App`, as [ADR 0010](../../../docs/decisions/0010-swift-package-and-macos-15.md) describes. Everything runs on the Mac, with no server ([ADR 0002](../../../docs/decisions/0002-local-first-no-server.md)).

The app keeps all accounts, categories, and transactions of the open database in one in-memory `Ledger` (module `Domain`). Every change goes to the database through `Store` (module `Storage`) and then to the ledger. Views read the ledger. This keeps filters, sums, and charts fast for some ten thousand transactions without queries per keystroke.

## Decisions

The first build follows the spec where the task list marks a task as checked. Open tasks keep the behavior of the spec as the target.

### Initial balance of a refreshed account: set once, and stored

The initial balance of a refreshed account is set once, as in MoneyMoney. `Account.initialBalanceIsSet` records that it is set. `reconcile` derives the value for an account with `source` `bank` whose flag is false, on a refresh that brings a bank balance in the currency of the account: the bank balance less the booked rows in the account currency up to the day of `bankBalanceDate`. A booked row counts also when it is marked for review. No pending row counts, because the connectors report the booked balance: the FinTS helper reads the booked balance of the bank, and the extension API keeps `balance` and `pendingBalance` apart. The computed balance then adds the pending rows that count on top, so the last day of the chart shows the bank balance plus those pending rows: the money that is still there. It sets the flag in the same step. A refresh whose transactions failed beside the balance ("Fetch the balance separately") does not set it, because the rows that the next refresh brings belong in the value. A bank that offers no transactions at all gets its balance as the initial balance. `Store.merge` writes the account in the same transaction as the rows, and `Ledger.apply` takes it over. Later refreshes, imports, and deletions do not change the value. A difference that appears later, such as from a refresh that brings an older row, is what the calibration proposal resolves.

Other accounts never derive it. A value that the user enters in the account settings sets the flag. An existing account that the setup connects, such as a migrated one, gets the flag, so it keeps the initial balance from MoneyMoney. Offline accounts and portfolios have no bank-derived value: offline accounts do not have `source` `bank`, and the chart of a portfolio comes from its recorded values.

The value is stored and not derived on read. The account settings show and edit "Initial balance", and "Calibrate" and the migration write it. A value derived on read would leave the stored field without meaning, and it could not stay fixed after a later refresh.

The migration `v11` adds the column with true for every account. Then it sets false for an account with `source` `bank`, an initial balance of 0, and no `sourceID`: an account that the setup added before issue #109 and that nobody gave a value. Such an account gets its initial balance at its next refresh. A value that the user typed is not 0, and a migrated account has a `sourceID`, so both keep theirs. A user who typed 0 on purpose cannot be told apart, so that account gets the derived value once, and the user enters 0 again. Entering the value that the field already shows is no change, so it does not set the flag either.

Nothing else changes meaning. The sidebar, the account header, and the group sums show `Account.reportedBalance`, which PR #142 adds: the bank balance of a portfolio or of an account with `source` `bank`. Every other account shows its computed balance.

### Pending transactions count everywhere

A pending row counts like a booked one, from the moment `Store` writes it. A pending row with `needsReview` is the exception and counts in no sum, as the change `add-account-refresh` decides: while a review is open, the booked row stands for the money. A booked row counts with or without `needsReview`. `Domain` owns the rule in one place: `Transaction.isInSum(of:)`, which PR #139 adds. It counts booked rows, and pending rows without `needsReview`, in the given currency. `Account.isInBalance` calls it for `Ledger.computedBalance` and `dailyBalances` in `Sources/Domain/Charts.swift`, and `Ledger.sum(ofCategory:in:)` calls it for the sidebar amount of a category. `periodSums` and `categoryTotals` in the same file sum every currency, so they test `isPending` and `needsReview` alone, by the same rule.

When the merge replaces a pending row by its booked version, the booked row takes its place on its own booking date. When the bank books it on the day of the pending row, no bar moves. When it books it on a later day, the bars between the two days rise by its amount, and the bars from the booking date on stay. When the bank drops a pending row, the merge removes it. Either way the charts follow the ledger, as for every other change.

One rule for every sum keeps the chart, the sidebar, and the status line in step. The bank balance stays as the bank reports it, without pending rows, and it holds for the end of the day of `bankBalanceDate`. So the calibration proposal compares it with `Ledger.computedBalance(of:through:)` at that day, less the pending rows that count up to that day. That is the initial balance plus the booked rows up to that day, the same rows that derive the initial balance. A row booked after that day is not in the bank balance and raises no proposal, and a pending row raises none either.

`Account.deriveInitialBalance` and the migration keep their own filter, booked rows only, once `Transaction.isInSum(of:)` counts pending rows. Task 3.3 changes `Account.deriveInitialBalance` to sum only the rows that are not pending, in the account currency, booked up to the day of `bankBalanceDate`, and no longer call `Account.isInBalance`. A pending row with or without `needsReview` stays out, so the stored value does not depend on a review. The migration subtracts the booked rows of the account from the balance of the source, and pending rows count on top, as for a refreshed account. Databases that were migrated before need no repair, because their stored initial balances already follow this rule.

## Risks / Trade-offs

A source whose balance already contains its pending rows would count them twice, once in the bank balance and once on top. No connector known today reports such a balance. If one does, the proposal stays quiet while the rows are pending, because it leaves them out of the comparison, and offers the fix once the bank books them.

The sidebar of a bank account shows the bank balance, and the last bar shows the bank balance plus the pending rows that count. With a bank balance of 2.500,00 € and a pending row of -30,00 €, the sidebar shows 2.500,00 € and the last bar 2.470,00 €. This is intended: the sidebar shows what the bank reports, and the chart shows the money that is still there.

A migrated pending row stays pending until a bank access refreshes its account or the user deletes it, and it counts until then.

Tasks marked as built in part may differ from the spec in the way their note says.
