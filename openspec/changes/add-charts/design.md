# Design

## Context

This change is part of the first build of the app. The build is a Swift package with the modules `Domain`, `Storage`, `Import`, and `App`, as [ADR 0010](../../../docs/decisions/0010-swift-package-and-macos-15.md) describes. Everything runs on the Mac, with no server ([ADR 0002](../../../docs/decisions/0002-local-first-no-server.md)).

The app keeps all accounts, categories, and transactions of the open database in one in-memory `Ledger` (module `Domain`). Every change goes to the database through `Store` (module `Storage`) and then to the ledger. Views read the ledger. This keeps filters, sums, and charts fast for some ten thousand transactions without queries per keystroke.

## Decisions

The first build follows the spec where the task list marks a task as checked. Open tasks keep the behavior of the spec as the target.

### Initial balance of a refreshed account: derived when the rows change, and stored

For an account with `source` `bank` and a bank balance, `Account.deriveInitialBalance` sets `initialBalanceMinor` to the bank balance less the booked rows up to the day of `bankBalanceDate`. `reconcile` calls it for every merge into such an account: a refresh, a file, or a migration. `Store.merge` writes the account in the same transaction as the rows, and `Ledger.apply` takes it over. `Store.deleteTransactions` derives it again after a deletion and returns the changed accounts, which `AppModel` puts into the ledger. These are the only writes that change the booked rows of a refreshed account, because the transaction editor changes amounts and dates only in offline accounts.

The alternative was to derive the value when the ledger reads it, in `computedBalance` and the charts. The stored value is not a cache of the ledger. The account settings show and edit "Initial balance", and "Calibrate" and the migration write it. A value derived on read would leave the stored field without meaning for refreshed accounts, and the settings would show a number that the chart does not use. Derived on write, `initialBalanceMinor` keeps one meaning for every account: the balance before the oldest transaction. The migration already sets it the same way.

Nothing else changes meaning. The sidebar, the account header, and the group sums show `bankBalanceMinor` where there is one, as before. Only the charts and "Calibrate" read the computed balance.

Portfolios are left out: their chart comes from recorded values. Offline and migrated accounts are left out: their initial balance is what the user entered or what the migration computed, and a deletion or an import does not change it. A migrated account that a bank access connects gets `source` `bank`, so its first refresh derives the value.

## Risks / Trade-offs

Tasks marked as built in part may differ from the spec in the way their note says.
