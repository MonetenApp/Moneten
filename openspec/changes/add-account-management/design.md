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

`Ledger.closing(_:today:now:)` in `Sources/Domain/ClosedAccount.swift` (module `Domain`) returns the closed account and the clearing entry, or no entry when the computed balance at the end of the day is zero or the account is a portfolio. The amount is the opposite of the exact computed balance at the end of that day (`Ledger.exactBalance(of:through:)`, the sum before `Ledger.computedBalance(of:through:)` holds it at the bounds of `Int64`). So it counts the initial balance and every row in the account currency up to that day, pending rows included, and leaves out rows after that day. The bank balance plays no part: a closed account shows its computed balance (`Account.reportedBalance` is nil for it), and only that balance must end at zero. A sum beyond `Money.maxMinorUnits` has no opposite that the app can store, so the close fails and nothing is written. "Calibrate" in the account settings is disabled for a closed account of a bank access, because it needs the reported balance.

The entry is a manual, booked row with the name and purpose in the language of the app, without category and counterparty, and marked as new. Rules do not run on it, so it counts in the default category "Uncategorized" until the user or "Apply Rules" gives it a category; the product owner chose to keep this. Closing also clears the error of the last refresh, because no refresh of a closed account clears it.

A closed account takes no refresh. `AppModel.save(account:)` calls `SyncCoordinator.leaveOut(account:)` (module `Sync`), which removes the account from every refresh that waits and drops a waiting refresh without another account. A refresh that already runs still ends. `reconcile` (module `Domain`) returns an empty result for a refresh delivery into a closed account, and `Store.merge` runs it in its write, so no delivery passes after the close was stored. `Account.record(_:)` ignores the end of a refresh for a closed account, so its time and its error stay.

`Account.clearingEntry` keeps a `ClearingEntryMark`: the ID of the row and the values that the app gave it, in the account currency. The migration `v28` stores the mark as JSON in the column `clearingEntry` of `account`, and the complete export writes it. The import drops a mark that names a row of another account, and keeps a mark whose row is missing, because it names nothing. `Ledger.reopening(_:calendar:)` removes the row only when it belongs to the account, no file or migration matched it, and it still has these values, no comment, no category chosen by hand, and no parts. A checkmark, the mark "new", and a category from a rule leave it unchanged. Reopening always clears the mark, so a kept row becomes an ordinary manual row, and a later close inserts a new entry for the balance that is left.

`AppModel.save(account:)` compares the closed flag with the stored account. It writes the account and the entry, or the open account and the removal of the entry, in one write. While an account is closed, its clearing entry moves no derived initial balance (`Ledger.followingBankBalance`), so the entry brings the computed balance to zero and an edit of it changes that balance. Another manual row moves a derived value as in an open account. When the entry goes at the reopen, the initial balance is the one before the close, and the account meets the bank balance again. A kept entry moves a derived value at the reopen by `Account.moveForManualRows`, as if the user had added it to the open account, so the computed balance meets the bank balance and a later deletion of the entry moves the value back. Like any manual row, the entry moves the value only when the bank balance holds it, so only when the close falls on or before the day of the bank balance. A later close leaves the entry after that day, and the next refresh whose day passes it sets the value by the rule of the first refresh. A file that the user imports into a closed account moves its computed balance, as in an offline account, because only a refresh is left out.

The bar chart of a selected closed account still draws its history. The chart of a group leaves closed accounts out, as the sum of the group does.

### One IBAN type

`IBAN` in `Domain` holds an IBAN whose country code, length, and checksum are valid. It replaces the two checks that the setup entry and the migration had, and it uses the length table of the SWIFT IBAN Registry release 103. `Account.iban` is an `IBAN?`, so no view, rule, or match checks the text again.

The edges make it. `FinTSAccount.account(access:bank:group:)` in `FinTS`, `ListedAccount` in `ExtensionConnector`, `MoneyMoneyMigration.plan` in `Import`, and the import of an export file take the IBAN with `Account.takeIBAN(_:)`. The account of a CAMT or MT940 file is a `FileAccount.iban(IBAN)` only when it is valid, and otherwise a `FileAccount.number`. The setup entry `BankEntry.bankCode(of:)` parses the IBAN and keeps its own error messages.

Text that is not a valid IBAN becomes the account number of an account that has none. A bank or an extension always names an account by a number, so their invalid IBANs are dropped. A migrated account or a file account keeps the number it was known by, and the setup can still find it by account number and Bankleitzahl.

The account of a counterparty stays a `String`. It can be an older account number, and the fingerprint of a transaction reads it, so a refresh must never drop it or fail on it. `IBAN.electronicForm(of:)` stores a valid IBAN without spaces in upper case. The fingerprint compares the account without spaces and case already, so stored rows keep their identity. The details of a transaction show "IBAN" in groups of four only for a valid IBAN, and "Account number" for other text.

`Storage` keeps the text column `iban`. `IBAN` encodes its electronic form and refuses invalid text when it decodes, so the migration `v31` applies `Account.takeIBAN(_:)` once to every stored account.

## Risks / Trade-offs

- An IBAN of a country that the registry adds after release 103 is not taken as an IBAN until the table has it. The account keeps the text as its account number. The table must only grow, because a stored IBAN of a country that leaves it no longer loads.


Tasks marked as built in part may differ from the spec in the way their note says.
