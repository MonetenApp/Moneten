# Design

## Context

This change is part of the first build of the app. The build is a Swift package with the modules `Domain`, `Storage`, `Import`, and `App`, as [ADR 0010](../../../docs/decisions/0010-swift-package-and-macos-15.md) describes. Everything runs on the Mac, with no server ([ADR 0002](../../../docs/decisions/0002-local-first-no-server.md)).

The app keeps all accounts, categories, and transactions of the open database in one in-memory `Ledger` (module `Domain`). Every change goes to the database through `Store` (module `Storage`) and then to the ledger. Views read the ledger. This keeps filters, sums, and charts fast for some ten thousand transactions without queries per keystroke.

## Decisions

- `Sources/Import/MoneyMoneyMigration.swift` runs `export accounts`, `export categories`, and `export transactions ... as "plist"` through `/usr/bin/osascript`. macOS asks the user once whether MonetenMoneten may control MoneyMoney.
- The exports are flat lists. `indentation` gives the nesting and `group` marks a group. The structure was checked on 2026-11-10 against a real export with 58 accounts and groups, 23 categories, and 30,539 transactions. Only key names, types, and counts were looked at.
- An account has no `iban` or `bic` key. `accountNumber` holds the IBAN and `bankCode` the BIC, so the migration takes a valid IBAN from `accountNumber` and a BIC from `bankCode`.
- `export categories` contains the rule of each category in `rules`. The migration takes it over unchanged. All 12 rules of the real export parse, and replayed over all transactions they pick the category that MoneyMoney shows wherever MoneyMoney applied rules.
- A group carries a balance. MoneyMoney leaves closed accounts out of that sum, but the export has no field that marks an account as closed. A real export showed this for one closed account with a balance other than zero. The migration takes every account over as open and names each group with a different sum in the report, so that the user can mark the closed accounts.
- Booking dates arrive as local midnight and become days in the current calendar.
- The initial balance of each account is the bank balance minus all booked transactions, so the computed balance ends at the bank balance.
- Each transaction keeps `moneymoney:<id>` as its source identifier. A second run skips known identifiers, except that a transaction that was pending and is booked now becomes booked with the date and amount from the source. An account matches by source identifier first, then by IBAN or by bank code and account number. A migrated account takes the newer balance of the source.
- Migrated categories count as assigned by hand.
- When the database has no transactions yet, the plan leaves out the starter categories, and they are removed after the user confirms the import. Categories the user made stay.

## Risks / Trade-offs

- The tests use synthetic exports with the structure of the real export. No real names or amounts are in the repository.
- A transaction can have another currency than its account, for example USD on a EUR account. Sums over such transactions add their amounts without conversion. Foreign currencies get their own change.
