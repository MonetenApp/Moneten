# Design

## Context

This change is part of the first build of the app. The build is a Swift package with the modules `Domain`, `Storage`, `Import`, and `App`, as [ADR 0010](../../../docs/decisions/0010-swift-package-and-macos-15.md) describes. Everything runs on the Mac, with no server ([ADR 0002](../../../docs/decisions/0002-local-first-no-server.md)).

The app keeps all accounts, categories, and transactions of the open database in one in-memory `Ledger` (module `Domain`). Every change goes to the database through `Store` (module `Storage`) and then to the ledger. Views read the ledger. This keeps filters, sums, and charts fast for some ten thousand transactions without queries per keystroke.

## Decisions

The first build follows the spec where the task list marks a task as checked. Open tasks keep the behavior of the spec as the target.

### A missing account type

`ListedAccount.derivedKind(number:name:)` in `Sources/ExtensionConnector/ResultMapping.swift` holds the rule of the requirement "Derive a missing account type". It runs once, when the app reads the table of `ListAccounts`, and the setup stores the result in the new account. A refresh keeps the stored type, because `SetupService` matches a listed account to a stored one by `remoteID` and never copies the type. The remote ID names only whether the account is a portfolio, so a different derived type never makes a stored account a new one. The length test counts every character as the script sent it, spaces included. The name tests compare the name in lowercase. A FinTS account whose bank reports no type keeps the type "Other" of `FinTSAccount.kind(of:)`. A file import and an offline account get their type from the user, so no derivation runs for them.

### Several balances and bonus points

`Account.bankBalanceMinor` stays the balance in the account currency. Every other rule reads it, the initial balance among them, so a second currency never reaches it. Two new fields hold the rest:

- `Account.otherBankBalances` lists the balances in other currencies, in the order of the source, without a zero. The migration `v26` stores it as JSON in the column `otherBankBalances` of `account`, with an empty list for every existing account.
- `Account.bonusPoints` is the whole number of points, or nil. The migration stores it in the column `bonusPoints`.

`RefreshResult` carries `otherBalances` and `bonusPoints`. The extension connector reads them from `balances` and `bonusPoints`. `reconcile` sets both fields whenever it stores the balance in the account currency, so each refresh replaces them, and a portfolio gets neither. `Account.reportedBalances` returns the reported balance and the other balances, and `Ledger.balances(of:)` returns what the sidebar row and the header show. `Ledger.sum(ofGroup:)` adds every balance, each in its currency. An account that shows a computed balance has no other balances, so a migrated or offline account shows one balance.

An empty `balances` array counts as a missing one, so `balance` is read then. This keeps a result with an empty array from failing with "The balance could not be fetched." A `balances` that is not an array fails the account, so a broken script never clears the stored balances. A currency of a pair must be three letters A to Z after trimming and uppercasing, because the import of the complete export refuses any other code.

`RefreshResult` combines what a connector hands it: a repeated currency adds up into one entry, a part in the currency of the balance goes to the balance, and a zero is left out. So every connector stores one entry per currency. The import of the complete export refuses other balances in the account currency or with a repeated currency, because the sum of a group would count them twice.

## Risks / Trade-offs

Tasks marked as built in part may differ from the spec in the way their note says.
