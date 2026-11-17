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

### Closing and reopening an account

`Ledger.closing(_:today:)` in `Sources/Domain/ClosedAccount.swift` (module `Domain`) returns the closed account and the clearing entry, or no entry when the computed balance at the end of the day is zero or the account is a portfolio. The amount is the opposite of `Ledger.computedBalance(of:through:)`, so it counts the initial balance and every row in the account currency up to that day, pending rows included, and leaves out rows after that day. The bank balance plays no part: a closed account shows its computed balance (`Account.reportedBalance` is nil for it), and only that balance must end at zero. A sum beyond `Money.maxMinorUnits` has no opposite that the app can store, so the close fails and nothing is written.

The entry is a manual, booked row with the name and purpose in the language of the app, without category and counterparty, and marked as new. Rules do not run on it, so it stays in the default category until the user or "Apply Rules" moves it. Closing also clears the error of the last refresh, because no refresh of a closed account clears it.

`Account.clearingEntry` keeps a `ClearingEntryMark`: the ID of the row and the values that the app gave it. The migration `v28` stores the mark as JSON in the column `clearingEntry` of `account`, and the complete export writes it. `Ledger.reopening(_:)` removes the row when it still has these values, no comment, no category chosen by hand, and no parts. A checkmark, the mark "new", and a category from a rule leave it unchanged. Reopening always clears the mark, so a kept row becomes an ordinary manual row, and a later close inserts a new entry for the balance that is left.

`AppModel.save(account:)` compares the closed flag with the stored account. It writes the account and the entry, or the account and the removal of the entry, in one write. While an account is closed, `Account.followsBankBalance` is false, so neither the clearing entry nor an edit of a row in a closed account moves a derived initial balance. Reopening deletes the entry with the account still marked as closed in the same write, so the initial balance stays as it was before the close, and the account meets the bank balance again.

The bar chart of a selected closed account still draws its history. The chart of a group leaves closed accounts out, as the sum of the group does.

## Risks / Trade-offs

Tasks marked as built in part may differ from the spec in the way their note says.
