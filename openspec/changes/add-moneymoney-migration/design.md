# Design

## Context

This change is part of the first build of the app. The build is a Swift package with the modules `Domain`, `Storage`, `Import`, and `App`, as [ADR 0010](../../../docs/decisions/0010-swift-package-and-macos-15.md) describes. Everything runs on the Mac, with no server ([ADR 0002](../../../docs/decisions/0002-local-first-no-server.md)).

The app keeps all accounts, categories, and transactions of the open database in one in-memory `Ledger` (module `Domain`). Every change goes to the database through `Store` (module `Storage`) and then to the ledger. Views read the ledger. This keeps filters, sums, and charts fast for some ten thousand transactions without queries per keystroke.

## Decisions

- `Import/MoneyMoneyMigration.swift` runs `export accounts`, `export categories`, and `export transactions ... as "plist"` through `/usr/bin/osascript`. macOS asks the user once whether MonetenMoneten may control MoneyMoney.
- The exports are flat lists. `indentation` gives the nesting and `group` marks a group. The field names follow the open source library [rust-moneymoney](https://github.com/gronke/rust-moneymoney), which parses the same exports.
- Booking dates arrive as local midnight and become days in the current calendar.
- The initial balance of each account is the bank balance minus all booked transactions, so the computed balance ends at the bank balance.
- Each transaction keeps `moneymoney:<id>` as its source identifier. A second run skips known identifiers. An account matches by source identifier, IBAN, or bank code and account number.
- Migrated categories count as assigned by hand.
- When the database has no transactions yet, the starter categories are removed before the plan is made.

## Risks / Trade-offs

- The structure of the exports was not checked against MoneyMoney 2.5.3, because MoneyMoney was locked during the build. The tests use synthetic exports with the documented structure.
- MoneyMoney exports no rules. The report says so.
