# Design

## Context

This change is part of the first build of the app. The build is a Swift package with the modules `Domain`, `Storage`, `Import`, and `App`, as [ADR 0010](../../../docs/decisions/0010-swift-package-and-macos-15.md) describes. Everything runs on the Mac, with no server ([ADR 0002](../../../docs/decisions/0002-local-first-no-server.md)).

The app keeps all accounts, categories, and transactions of the open database in one in-memory `Ledger` (module `Domain`). Every change goes to the database through `Store` (module `Storage`) and then to the ledger. Views read the ledger. This keeps filters, sums, and charts fast for some ten thousand transactions without queries per keystroke.

## Decisions

The first build follows the spec where the task list marks a task as checked. Open tasks keep the behavior of the spec as the target.

### Initial balance of a refreshed account: set once, and stored

The initial balance of a refreshed account is set once, as in MoneyMoney. `Account.initialBalanceIsSet` records that it is set. `reconcile` derives the value for an account with `source` `bank` whose flag is false, on a refresh that brings a bank balance in the currency of the account: the bank balance less every row of the account after the merge, pending rows included and with no date limit. Rows that the merge drops are gone and do not count. Pending rows that stay count, except pending rows marked for review: while a review is open, the booked row stands for the money, so a marked pending row counts in no balance. So the last day of the chart equals the bank balance. It sets the flag in the same step. A refresh whose transactions failed beside the balance ("Fetch the balance separately") does not set it, because the rows that the next refresh brings belong in the value. A bank that offers no transactions at all gets its balance as the initial balance. `Store.merge` writes the account in the same transaction as the rows, and `Ledger.apply` takes it over. Later refreshes, imports, and deletions do not change the value. A difference that appears later, such as from a refresh that brings an older row, is what the calibration proposal resolves.

Other accounts never derive it. A value that the user enters in the account settings sets the flag. An existing account that the setup connects, such as a migrated one, gets the flag, so it keeps the initial balance from MoneyMoney. Offline accounts and portfolios have no bank-derived value: offline accounts do not have `source` `bank`, and the chart of a portfolio comes from its recorded values.

The value is stored and not derived on read. The account settings show and edit "Initial balance", and "Calibrate" and the migration write it. A value derived on read would leave the stored field without meaning, and it could not stay fixed after a later refresh.

The migration `v11` adds the column with true for every account. Then it sets false for an account with `source` `bank`, an initial balance of 0, and no `sourceID`: an account that the setup added before issue #109 and that nobody gave a value. Such an account gets its initial balance at its next refresh. A value that the user typed is not 0, and a migrated account has a `sourceID`, so both keep theirs. A user who typed 0 on purpose cannot be told apart, so that account gets the derived value once, and the user enters 0 again. Entering the value that the field already shows is no change, so it does not set the flag either.

Nothing else changes meaning. The sidebar, the account header, and the group sums show `bankBalanceMinor` where there is one, as before.

### Pending transactions count everywhere

A pending row counts like a booked one, from the moment `Store` writes it. `Domain` owns the rule: `Ledger.computedBalance` and the balance, category, and pie data in `Sources/Domain/Charts.swift` add every row of the account or category and do not test the pending flag. The sidebar amount of a category in `App` reads the same rows. When the merge replaces a pending row by its booked version, the booked row takes its place. When the bank drops it, the merge removes it. Either way the charts follow the ledger, as for every other change.

One rule for every sum keeps the chart, the sidebar, and the status line in step. The bank balance stays as the bank reports it. Some banks report it without pending rows, so the calibration proposal ignores a difference of exactly the pending sum.

The migration sets the initial balance by the same rule: the bank balance less every migrated row of the account, pending rows included.

## Risks / Trade-offs

Some banks report a balance without pending rows. At such a bank, the first refresh sets an initial balance that makes the chart end at that balance although the chart contains the pending rows. When the bank books them, its balance drops and the chart stays, so the chart is too high by that pending sum. The calibration proposal then offers the fix. Pending rows of later refreshes make the chart lower than the bank balance by their sum until the bank books them, and the proposal stays quiet for that difference.

Tasks marked as built in part may differ from the spec in the way their note says.
