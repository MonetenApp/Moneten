# Design

## Context

The proposal says why users split a transaction. This design decides how the parts are stored and how every list and sum reads them. The build is a Swift package with the modules of [ADR 0010](../../../docs/decisions/0010-swift-package-and-macos-15.md), and all data stays in the encrypted database on the Mac ([ADR 0002](../../../docs/decisions/0002-local-first-no-server.md), [ADR 0005](../../../docs/decisions/0005-grdb-and-sqlcipher.md)). No decision record changes.

What main has today, and what a split must not break:

- `Transaction` is stored in the table `bankTransaction`. `Ledger.transactions` holds every stored row, newest first. `Ledger.computedBalance` and `dailyBalances` add these rows to the initial balance, and `Account.deriveInitialBalance` subtracts them from the bank balance.
- `reconcile` recognizes a delivered row by its source ID, then by a fingerprint of booking day, amount, purpose, counterparty IBAN, and end-to-end reference. It builds the fingerprint from the stored columns at every merge. `Store.merge` reads the stored rows of the account inside its write transaction. A refresh that delivers a known source ID gives the stored row the delivered bank fields, and the rules run again on a changed row, as the requirement "Update a transaction that the source changed" of `add-account-refresh` says. On the first refresh with a balance, `reconcile` derives the initial balance of a bank account once, from the stored rows with the changes of that merge.
- `Transaction.review` names either an unclear pending match or an automatic split undo. The list and edit sheet show the reason's note.
- `Ledger.rows(in:filter:)` gives the rows of the list, the category view, the status line, the charts of categories, the search, and the filters. `Ledger.sidebarAmounts(today:)` reads the stored transactions directly in one pass for all amounts in the sidebar, with a 20 ms release budget in `PerformanceTests`.
- `RuleApplier.apply` walks `Ledger.transactions`. `reconcile` runs `Categorizer.categorize` on a row whose bank fields changed.
- `AppModel.commit` writes changed rows with `Store.save` and then calls `Ledger.update`. `AppModel.assign`, `setChecked`, `toggleChecked`, `markAllChecked`, and `setComment` find their rows with `Ledger.transaction(_:)`, and so do the views. `AppModel.save(transaction:)` runs the `Categorizer` on a row without a category whose category was not set by hand.
- `Ledger.rebuildIndexes()` builds the search text of every row of `transactions`. `init` calls it, and so does `replace` with accounts or transactions, which the removal of an account and of an account group call. `Ledger.upsert(_:)` of a renamed account builds the search text of its transactions again, because the search text holds the account name.
- App settings live in `UserDefaults` through the keys of `Preference`.
- Periphery runs in strict mode on the app schemes, not on the tests. A declaration that only a test calls fails `scripts/check.sh`.

## Goals / Non-Goals

**Goals:**

- One data shape in which a split cannot change a balance or the identity of a transaction, and an undo needs no stored copy of the original.
- One function that decides which rows a list or a sum by category counts, so that no place counts the original and its parts both.
- Pull requests that each end in a check: the arithmetic, the table, the rows and sums, the change path of a part row, the refresh and the rules, the commands, the settings, and the MoneyMoney migration.

**Non-Goals:**

- The positions of a batch payment. The change `add-payment-outbox` knows them. It adds the name and the purpose of a part and enables "Split from Batch Payment". Until then the command is disabled.
- A changed amount of a part after the split. The user undoes the split and splits again.
- Split records of QIF files (`add-more-import-formats`) and the later export formats, budgets, reports, and printouts of split transactions. The complete data export and import are part of this change. Those later changes read the rows that this design defines.

## Decisions

### The original stays, and the parts live in their own table

A split leaves the original row in `bankTransaction` exactly as it is. The parts go into a new table `splitPart`. This gives three things without extra code:

- A refresh still finds the original by its source ID or its fingerprint, because no stored column changed.
- The balance, the daily balance, and the initial balance still add the original, so they stay the same. The parts add up to its amount, so the account view shows the same total.
- An undo deletes the parts. The original comes back with the category and the comment that it had before the split, because nothing changed them.

Alternatives considered:

- The parts as rows of `bankTransaction` with a link to a hidden original, as MoneyMoney shows them. Every reader of `Ledger.transactions` would then have to skip either the parts or the original: the balance, the daily balance, the initial balance, the merge, the migration, and the new marks. `reconcile` would also see parts that carry the fingerprint fields of the original with other amounts.
- A flag `isSplit` on `Transaction`. It is a second fact that must stay in step with the parts. The ledger and the store know a split from its parts instead.

### Types in `Domain`

`Split.swift` in `Sources/Domain` holds the types and the arithmetic. Nothing in them does I/O.

- `SplitPart`: `id`, `transactionID`, `position`, `amountMinor`, `categoryID?`, `comment?`, `vat?`. The `id` is the ID of the row of the part in the list. A part has the currency of its transaction. `categoryID` nil means "Uncategorized", as for a transaction.
- `VATShare`: `role` (`net` or `tax`) and `rate`. Only the parts of a VAT split have one. The list shows "(net)" or "(19% VAT)" from it. The rate stays on the part when the user later changes the list of rates.
- `VATRate`: `hundredths`, the rate in hundredths of a percent, so 19 % is 1900 and 8,1 % is 810. `VATRate.standard` is 19 % and 7 %. Hundredths keep the rates of Switzerland and Austria exact, and the arithmetic stays in integers. `VATRate.text` names the rate as the menu and the label show it, so 1900 is "19%" and 810 is "8.1%". The menu of group 6 reads it, so it lives in `Split.swift` from group 1. `VATRate(text:)` reads a rate with up to two decimals above 0, so "8,1" is 810. Only the setting of group 7 reads it, so group 7 adds it to `Split.swift`.
- `SplitError`: `pending` for a row that the bank has not booked, `zeroPart` for a split that would make a part of 0, `onePart` for a list with a single part, and `unbalanced` for parts that do not add up to the amount of their transaction or use another currency.
- `Split`: the namespace of `Split.amount(from:on:decimalMark:)` and `Split.amounts(of:off:)`.

The parts of one transaction are at least two, none is 0, and they add up to its amount. A zero original can have opposite nonzero parts, such as 5,00 € and -5,00 €. Only the arithmetic of `Split.swift` computes the amounts of parts, so the rule lives in one file. `Store.replaceParts(of:with:)` checks the rule again against the stored transaction, because the store is the last place before the database. `Store.replaceParts(of:with:)` and `Ledger.replaceParts(of:with:)` set the `transactionID` of every part to the transaction of `of:`, so no part can name another transaction.

### The arithmetic

- `Split.amount(from:on:decimalMark:)` reads the text of the amount field with `AmountParser.decimal(from:decimalMark:)`. `on:` is the amount of the row as `Money`, and the result is a `Money` in its currency. `SplitSheet` passes the decimal mark of `Locale.current.decimalSeparator`, because the list shows amounts in the format of that locale. Without the mark, `AmountParser` gives nil for text that reads two ways, so "1.250" on -3.000,00 € would be refused. With the comma of a German locale it is -1.250,00 €.
- `AmountParser` drops a leading "+" and gives a plain number. So `Split.amount` reads the sign from the first character of the trimmed text itself: "+", "-", or the minus sign "−" that the list shows. A number without a sign takes the sign of the row, so "25,00" on -80,00 € is -25,00 €. A number with a sign keeps it, so "+5,00" on -80,00 € is 5,00 €. Text that is not a number gives nil.
- The amount has the decimals of the currency of the row, as `Currency.exponent(of:)` gives them: 2 for EUR and USD, 0 for JPY, and 3 for KWD. A number with more decimals than the currency has gives nil, because `Money(_:currency:)` would round it to a part that the user did not enter. So "25,5" on -1.000 JPY is nil, "1,250" on -10,000 KWD is -1,250 KWD, and "1,2345" on -10,000 KWD is nil. Every part has the currency of its transaction, so the parts of a USD row in a EUR account are in USD.
- `Split.amounts(of:off:)` returns the entered amounts and then the remainder, the amount of the row less their sum. It throws `zeroPart` for an entered amount of 0 and for a remainder of 0. Entering the whole amount leaves nothing to split, so the app treats it like 0 and marks the field. Task 1.1 adds this scenario to the spec.
- `VATRate.split(_:)` computes the net part as the gross amount times 10.000 divided by 10.000 plus the rate in hundredths. Swift divides integers toward zero, which is the cut toward zero at the smallest unit of the transaction currency in the spec, also for a refund. The tax part is the gross amount less the net part. -10,00 € at 7 % gives -9,34 € and -0,66 €. -0,01 € gives a net part of 0, so the app refuses it like an amount of 0. The arithmetic works on minor units, so it cuts at the smallest unit of any currency. -1.000 JPY at 7 % gives -934 JPY and -66 JPY, and -10,000 KWD at 7 % gives -9,345 KWD and -0,655 KWD.
- `Ledger.splitting(row:off:)` and `Ledger.splittingVAT(row:rate:)` return the complete new list of parts of the transaction behind a row. The row can be a transaction without a split or a part. A part is replaced in place by its new parts, so splitting the part of -55,00 € of the receipt gives -25,00 €, -15,00 €, and -40,00 €, and one undo brings back -80,00 €. Each new part copies the category and the comment of the row, and the positions count from 0 again. A pending row throws `pending`.
- The new parts of a split part never copy its VAT label. "(net)" on half of a net amount would be wrong. Splitting the net part of -100,00 € by 50,00 gives two parts of -50,00 € without a label, and the tax part of -19,00 € keeps "(19% VAT)". `Ledger.splittingVAT(row:rate:)` on a part gives its new parts the labels of the new rate.

### The ledger offers rows, and the original stays the stored truth

`Ledger.transactions` keeps every stored transaction and never a part. Everything that counts the money of an account reads it, as today.

`Ledger.rows(in:filter:)` keeps `TransactionSearchResult` with `.rows` and `.gaveUp`, so a stopped search still reports failure. A row is a transaction without a split, or a part row in place of a split transaction. A part row is a `Transaction` value with the ID, the amount, the category, and the comment of the part. Its `categorizedBy` is always `manual`, also without a category, because the user sets the category of a part and no rule does. So `Categorizer.categorize` leaves a part row as it is. Every other field comes from the original: the date, the counterparty, the purpose, the account, the checkmark, and the marks for new and for review. The parts of one transaction follow each other in the order of `position`.

`Ledger.replaceParts(of:with:)` sets the parts of one transaction, and an empty list removes them. The ledger keeps the part rows of each split transaction. `rows(in:filter:)` puts them in place of the original while it filters. The ledger keeps no second copy of all 50,000 rows, and a ledger without splits filters as before. A private index from the ID of a part to its transaction, beside `transactionIndex`, serves two lookups. `Ledger.row(_:)` finds a row by its ID. `Ledger.part(_ rowID:) -> SplitPart?` beside it gives the part behind a part row, and nil for any other ID. The mark of a part row, the undo, the refusal to delete a part, and the menu read `Ledger.part(_:)`. `Ledger.transaction(_:)` still finds only stored transactions. `Ledger.row(_:)` gives nil for the ID of a split original, because no row shows it.

One private function in `Ledger.swift` builds the search text of a transaction and, for a split transaction, its part rows with their search texts. `rebuildIndexes()` calls it for every transaction, and first drops the parts whose transaction is no longer in `transactions`. So `init` and every `replace` keep the part rows and their search texts, also the removal of an account group, which calls `replace(groups:accounts:)` and builds every search text again. The removal of an account goes through the same rebuild. `AppModel.remove(account:)` calls `replace(accounts:transactions:)` without the transactions of the account, and the rebuild drops their parts. `update(_:)`, `replaceParts(of:with:)`, and `upsert(_:)` of a renamed account call the function for the transactions that they change. `remove(transactionIDs:)`, which `AppModel.delete` calls, drops the parts and the part rows of the removed transactions. `apply(_:)` of a merge goes through `update(_:)`, so a split original that takes a source ID or a new purpose gets its part rows built again. A merge that undoes a split drops its parts before `update(_:)`.

`Ledger.init` takes the parts with the parameter `parts:`, and `Store.loadLedger` passes them. The dictionary of parts by transaction, `Ledger.parts(of:)`, and every other function of the ledger that this design adds live in `Ledger.swift`, because they read the private state of the ledger, such as `searchText` and `transactionIndex`.

The search text of a part row holds the fields of the original, the comment of the part, the amount of the part, and the amount of the original. A search for -80,00 then finds both parts of the receipt, whose sum the status line shows as -80,00 €.

Removing an account, a transaction, or a category changes the parts in the ledger as the database does. The parts of a removed transaction go, and a part of a removed category becomes uncategorized. `AppModel.remove(category:)` changes the transactions of the ledger itself today. A ledger function takes that over for the transactions and the parts.

### Where each count reads

No place counts a split twice, because `rows(in:filter:)` never holds a split original and `Ledger.transactions` never holds a part.

| Place | Reads | Task |
|---|---|---|
| Amounts of categories in the sidebar, `Ledger.sidebarAmounts(today:)` | parts in place of each split original, within its single pass and 20 ms release budget | 3.1, 3.2, and task 3.3 of `add-categories` |
| List, category view, and status line, `AppModel.visibleTransactions` | rows | 3.1, 3.2 |
| Category bars and pie charts, `periodSums` and `categoryTotals` of `AppModel.chartTransactions` | rows | 3.1, 3.2 |
| Search and filters | rows | 3.1, 3.2 |
| Balance, daily balance, and initial balance | transactions | 3.1 checks that they stay |
| Merge, migration, and new marks | transactions | 5.1, 5.2, 8.2, 8.3 |
| CSV transaction export | rows, including the part categories and comments | 3.1, 3.2 |
| Budgets, reports, printouts, and later transaction export formats | rows | the changes `add-budgets`, `add-reports`, `add-printing`, and `add-more-export-formats` |
| "Export All Data..." and "Import All Data..." | stored originals, parts, and review reasons | 5.1a, 5.2a, before group 6 |

`Ledger.sidebarAmounts(today:)` keeps its single pass over the stored transactions. For each split original it accumulates the part rows instead of the original. Each part contributes to its own category and its ancestor groups, using the existing period, currency, and pending-review checks. It does not call the category filter for each category. Task 3.1 checks the literal amounts through this function, and task 3.3 includes split rows in its 20 ms release budget.

### Complete export and import use format v2 before splits are enabled

`Domain` owns `AllData` in `Sources/Domain/AllData.swift`, its `json()` encoder, and its `init(json:)` reader. Its private `File` maps the format-v2 lists and `TransactionEntry` maps `review`. `Storage` owns `Store.exportAllData(at:)` and `Store.importAllData` in `Sources/Storage/Store+AllData.swift`. Tasks 5.1a and 5.2a extend these existing paths before group 6 enables split commands for users.

`AllData.formatVersion` is 2. `AllData` and `File` gain `splitParts`, a list of every stored `SplitPart`. Each entry holds `id`, `transactionID`, `position`, `amount` as decimal text, `categoryID`, `comment`, and optional `vat` with `role` and `rate` in hundredths of a percent. The amount uses `AmountText` and the currency of the referenced original. The export keeps the original once in `transactions`, with its original category and comment for undo, and never exports a part row as a transaction. `TransactionEntry` writes `review` as `unclearBooking` or `splitUndone`, omitted for nil. The format preserves part IDs, positions, categories, comments, and VAT labels, even after the user changes the list of VAT rates.

`AllData(json:)` accepts v1 and v2. A v1 file has no `splitParts`; it yields an empty list and maps `needsReview` true to `.unclearBooking` and false to nil. A v2 file requires `splitParts`, including an empty list, and reads `review`. Unknown review reasons, malformed parts, and unsupported newer versions are refused, rather than silently losing data. The same split invariants apply to an import as to `Store.replaceParts(of:with:)`. The store validates them for both decoded and programmatically constructed `AllData`. Missing original or category references, duplicate IDs or positions, pending originals, fewer than two parts, zero amounts, and an unequal sum fail the import without a write.

`Store.exportAllData(at:)` reads originals and parts in its existing database read. `Store.importAllData` inserts the parts after the originals in its existing write transaction and keeps its empty-database check and rollback. Loading the imported ledger restores the split and review reasons without categorizing the parts again. Tasks 5.1a and 5.2a cover the literal split round trip and the fixed v1 fixture, and update [the export format](../../../docs/export-format.md). That page describes active v2 and v1 compatibility.

### Writing a change of a row

`Ledger.changes(from:)` turns changed rows into what the store writes: transactions and parts. A part row gives its category and its comment to its part. Its checkmark and its marks for new and for review go to the original, and several rows of one original give one original. The row of a transaction without a split gives that transaction. A row whose ID the ledger does not hold gives no change. Only "Add Transaction...", whose `TransactionSheet.transactionID` is nil, passes a new transaction directly to `AppModel.commit`. An edit sheet with a non-nil ID never falls back to adding a transaction when its row disappears. A row with the ID of a split original gives nothing, because `Ledger.row(_:)` never gives such a row.

`Ledger.changes(from:)` returns only what differs from the ledger. A part row whose category and comment equal those of its part gives no part. An original whose checkmark and marks equal the stored ones gives no transaction. A row of a transaction without a split that equals the stored transaction gives nothing. So "Edit Transaction..." that changes nothing writes nothing and runs no rule. When rows of one original carry different values, each of the three fields takes the value that differs from the original: the checkmark, the mark for new, and the mark for review. The checkmark and the new mark are `Bool` values. The review is a `ReviewReason?`; row edits can only keep it or clear it to nil. Only one changed value is possible for each field, so the order of the rows does not matter. A part row with a checkmark beside an unchanged part row of the same original checks the original.

Each path below calls `Ledger.changes(from:)` and passes the transactions and the parts of the result to `AppModel.commit`. `AppModel.commit` writes both with `Store.save` in one transaction, then gives both to `Ledger.update`. `Store.save` for transactions takes the parts as well. It writes each part with `update` of the columns `categoryID` and `comment` only, so a save never changes the amount of a part, and it refuses a part that the database does not hold. Only `Store.replaceParts(of:with:)` adds parts.

Every path that changes a row finds it with `Ledger.row(_:)`, because `Ledger.transaction(_:)` never finds the ID of a part:

- `AppModel.assign`, which the drop of rows on a category in `SidebarView`, the menu "Assign Category", the category ribbon, "Remove Transaction from Category", and `AppModel.addCategory(assigning:)` call.
- `AppModel.setChecked`, `toggleChecked`, and `markAllChecked`. `markAllChecked` counts the transactions that `Ledger.changes(from:)` gives for its rows, so a split counts once in its question.
- `AppModel.setComment`.
- `AppModel.save(transaction:)`. It calls `Ledger.changes(from:)`, then `Categorizer(ledger: ledger).categorize(&t)` on each transaction of the result that has no category and whose category was not set by hand, and commits. `Categorizer(ledger:)` reads only the accounts and the categories of the ledger, so the function needs no copy of the ledger with the new row. A part is a `SplitPart` in the result, which the `Categorizer` never sees. So "Edit Transaction..." on a part without a category saves it without a category, also when the sheet sets `categorizedBy` to `none` because the user cleared the category.
- `Ledger.accountIDs(ofTransactions:)`, which `AppModel.openCategoryPicker()` uses to determine the allowed categories. It resolves selected IDs through `Ledger.row(_:)` so a part contributes its original account. `Ledger.categories(matching:assignableTo:)` then keeps the existing account restrictions, including a mixed selection of parts and unsplit rows. Task 4.1 pins the account IDs and the allowed category names.
- The views that read a selected row: `TransactionMenu`, the category ribbon, and the category choices in `TransactionsView.swift`, and the comment sheet and `TransactionSheet` in `Sheets.swift`.

"Edit Transaction..." on a part shows the bank fields read-only, as for a fetched row, and saves the category and the comment of the part. In `TransactionSheet.save`, a non-nil `transactionID` that no longer resolves through `Ledger.row(_:)` closes the sheet without calling `AppModel.save(transaction:)`. This check runs before any fallback to the selected account or creation of a `Transaction`. A refresh can undo the split while its part editor is open; confirming that stale editor writes nothing. A nil `transactionID` still opens a real new-transaction sheet.

The checkmark belongs to the whole transaction, because the user checks a transaction against the one line of the bank statement. Checking one part checks all parts of its transaction. Task 1.1 adds this rule to the spec as its own requirement.

### A refresh keeps a split while its amount stays, and undoes it when the bank changes the amount

`reconcile` takes the IDs of the split transactions of the account in a new parameter `split:` with the default `[]`. `Store.merge` reads them from `splitPart` inside its write transaction, as it reads the stored rows. `MoneyMoneyMigration.plan` stays as it is and passes none. The partner selection stays the one from #203, including its five priorities, its scoped booked-only legacy path, and `fileIdentity`. Split handling runs after that selection and adds no matching path. In a migration, the branch of the source ID already only links a booked row, and a split original is always booked.

A delivered row whose partner is a split original never adds a row. What it changes depends on how it found the original:

- By its source ID, as a booked row with the same amount in the same currency. The original takes the bank fields, as every row does under "Update a transaction that the source changed". The parts stay, and they still add up. The rules do not run on the original, because the parts carry the categories while the split lasts, and an undo gives back the category from before the split. A new purpose shows on every part row, because a part row takes the purpose of its original.
- By its source ID, as a booked row with another amount or currency. The merge undoes the split. The original takes the bank fields and gets `review` `.splitUndone`, and the rules run on it as on every row whose bank fields changed. `Reconciliation.unsplit` holds its ID, and the original is in `updated` as well. `Store.merge` deletes its parts in the same write transaction. `Ledger.apply(_:)` drops its parts and part rows before `update(_:)`. The original keeps its comment, its checkmark, and a category assigned by hand before the split. A category assigned by a rule can change when the rules run again. The categories and comments of the parts are gone.
- By its source ID, as a pending row. The existing #203 guard `delivered.isPending && !live.isPending` leaves it unchanged. There is no new condition in the migration-only link branch. A pending row never undoes a split, also with another amount or currency. It leaves the stored bank fields unchanged.
- By its fingerprint, or as the booked version in the steps `.bookedVersion` of `Identity.steps`. The fingerprint holds the amount, so the amount is the same, and the original takes only a missing source ID and `isFetched`, as today.

A split original is booked, and a merge drops only pending rows, so a merge never drops it. An undo does remove the shown part rows. `AppModel.mergeRefresh` must therefore use `replacingTable` for this path. In `removesShownRows`, keep the holdings branch and extend the transaction predicate to `$0.accountID == accountID && ($0.isPending || ledger.part($0.id) != nil)`. Any shown part of the refreshed account makes it true, even if no pending row is shown. The predicate need not predict whether this delivery undoes the split. Removing shown parts in place reaches the table update that stopped in AttributeGraph in #135. Tasks 5.5 and 5.6 check a refresh with the parts on screen and no pending row.

`Reconciliation.unsplit` overlaps `updated`: the corrected original belongs to both. Task 5.2 updates the doc comment of `Reconciliation` in `Sources/Domain/Reconcile.swift`, which currently says that the lists are disjoint.

The proposal records the undo under "Decided for Moneten". Each alternative fails a rule of this design:

- Scaling the parts to the new amount guesses. A tax part of -19,00 € is the tax of an invoice, and the correction of the bank does not say which part changed.
- A notice alone keeps parts that add up to -80,00 € beside an original of -85,00 €. That breaks the rule that the parts add up to their transaction, which `Store.replaceParts(of:with:)` checks.
- Keeping the old amount without a notice leaves the balance of the account 5,00 € away from the bank. On a bank account whose initial balance is not set yet, the merge derives it from the stored -80,00 € and the bank balance, so the initial balance and every daily balance before the row are 5,00 € off instead.

The undo keeps the balance, the derived initial balance, and every daily balance equal to the bank, because the original holds the amount of the bank, as every other row does. A bank account that derives its initial balance from the bank balance 915,00 € and the corrected -85,00 € gets 1.000,00 €. With the stored -80,00 € it would get 995,00 €.

### The review mark names its reason

`Transaction.needsReview: Bool` becomes `Transaction.review: ReviewReason?`, an enum with `unclearBooking` for the rows of an unclear pending match and `splitUndone` for a split that a refresh undid. One field holds the mark and its reason, so a row cannot have a reason without the mark. The list shows the mark with the help text of its reason: today's text for `unclearBooking`, and "The bank changed the amount; the split was undone." for `splitUndone`. `TransactionSheet` shows the same note above the fields, so the note is visible without a help tag. `markChecked()` clears it, as today. `reconcile`, `MoneyMoneyMigration.plan`, `AppModel.changesWhenChecked`, `TransactionCell`, and the harness log of the rows of a refresh read `review` in place of `needsReview`. The pending-review rules of `add-account-refresh` still apply when that change lands. Task 5.7 assigns the rename to whichever change lands second. It covers the open tasks and designs of `add-account-refresh`, `add-categories`, `add-charts`, `add-file-import`, and `add-offline-accounts`, plus `docs/architecture.md` and `docs/data-model.md`. A marked pending row is represented by `.unclearBooking`; its sum, check, booking, and removal rules stay those of `add-account-refresh`. A booked `.splitUndone` row clears its review when checked, even when its checkmark was already set. An automatic undo replaces an earlier `.unclearBooking` with `.splitUndone`.

Alternatives considered:

- `needsReview` alone. Its help text says that several transactions could belong together, which is wrong for an undone split.
- A column with the note beside `needsReview`. It is a second fact that must stay in step with the first, as a flag `isSplit` would be.

### Rules leave splits alone

`RuleApplier.apply` skips split transactions. The parts are not in `Ledger.transactions`, so no rule reaches them. The number of matching transactions in the category settings skips split transactions too and uses the same account restriction. Rebasing a finished rule run excludes originals split during the run and rechecks originals whose split was undone during the run.

### Storage

Migration `v17` in `Sources/Storage/Schema.swift` adds the table `splitPart`. It is the next migration after `v16`, which #198 adds for the CAMT return reason.

- `id` (primary key), `transactionID` (references `bankTransaction` with `ON DELETE CASCADE`, indexed), `position`, `amountMinor`, `categoryID` (references `category` with `ON DELETE SET NULL`), `comment`, `vat`.
- `vat` is JSON, as `account.refreshError` is.
- The parts go with their transaction, and so with their account.

`SplitPart` is a GRDB record like `Transaction`. `Store.loadLedger` reads the parts. The section "Writing a change of a row" says how `Store.save` writes a changed part.

`Store.replaceParts(of:with:)` deletes the parts of a transaction and writes the new ones in one write transaction. An empty list is the undo. Inside the same write transaction, before it changes a row, it reads the stored transaction and throws when the new parts break the rule of a split:

- `SplitError.pending` when the stored transaction is pending.
- `SplitError.onePart` for a list with one part.
- `SplitError.zeroPart` when a part is 0.
- `SplitError.unbalanced` when the parts do not add up to the stored amount.

The foreign key refuses parts of a transaction that the database no longer holds. A refused call leaves the parts as they were.

Migration `v20` of group 5 adds the column `review` to `bankTransaction`, sets it to "unclearBooking" on every row whose `needsReview` is true, and drops `needsReview`. PR #203 uses v18 for file identity and PR #219 uses v19.

### The commands in `App`

The context menu of a row gets the submenu "Split Transaction" with "Split Amount...", one entry "Split 19% VAT" for each rate, "Split from Batch Payment", and "Undo Split Transaction...". The entries are enabled for one selected row. On a pending row, "Split Amount..." and the VAT entries say that only booked transactions can be split and change nothing. "Split from Batch Payment" is always disabled. "Undo Split Transaction..." is enabled only on a part.

The split window `SplitSheet` shows the row, the field for the amount, and the remainder. "Next Split" keeps the entered amount and empties the field. Confirming with an empty field adds no part once "Next Split" kept at least one amount, so 25,00, "Next Split", and confirm on -80,00 € give -25,00 € and -55,00 €. Without a kept amount, the confirm button stays disabled while the field is empty. The window marks text in the field when `Split.amount(from:on:decimalMark:)` gives nil for it, and it marks an amount of 0 and an amount that leaves a remainder of 0. It does not use `marksUnreadableAmount` of `App/Sources/Views/Format.swift`, which reads the text without the decimal mark and so marks "1.250". An empty field is not marked. A split and an undo remove a shown row and add others. So both go through `AppModel.replaceParts(of:with:)`, which writes with `Store.replaceParts(of:with:)` and `Ledger.replaceParts(of:with:)` inside `AppModel.replacingTable`, as a refresh that removes shown rows does (issues #135 and #151). After a split the new parts are selected, and after an undo the original. Task 4.3 adds `AppModel.replaceParts(of:with:)` with the debug harness command `split`, so that the app can check the change path of group 4 before the commands exist.

A part row shows a mark and "Part of -80,00 €" with the amount of the original, and the label of a VAT part. The pull request settles the look with snapshots.

"Undo Split Transaction..." asks "Replace the split transactions with the original transaction?" and says "The split transactions cannot be restored." "Delete Transaction..." on a selection with a part says that a part of a split cannot be deleted alone, and names "Undo Split Transaction...". `AppModel.delete` refuses such a selection too, so no other path deletes a part.

### The list of VAT rates is a setting

`Preference.vatRates` stores the rates in `UserDefaults` as an array of hundredths. `Preference.registerDefaults` registers `VATRate.standard`, 1900 and 700. The tab "General" of the settings gets a list of the rates with add, change, and remove. The list reads a typed rate with `VATRate(text:)` of `Split.swift`. The submenu shows the rates in the order of the list. An empty list shows no VAT entry. Rates are numbers, so the setting holds no personal data, as the change `add-app-settings` requires.

### Order of the work

Each group of `tasks.md` is one pull request. Groups 1 to 3 add code that at first only tests call: the arithmetic, `Ledger.parts(of:)`, `Ledger.part(_:)`, `Ledger.replaceParts(of:with:)`, and `Store.replaceParts(of:with:)`. Group 4 calls the last two from the debug harness, and group 6 from the commands.

- The types and the pure arithmetic go into `Split.swift` in `Sources/Domain`, and `Store.replaceParts(of:with:)` into `Store+Split.swift` in `Sources/Storage`. Both files go into `retain_files` of `.periphery.yml`, as the sync model is listed until the connectors use it.
- `Ledger.parts(of:)`, `Ledger.part(_:)`, and `Ledger.replaceParts(of:with:)` stay in `Ledger.swift`, because they read its private state. Each gets the comment `// periphery:ignore - task 6.8`, in the form of `App/Sources/Views/SyncDemo.swift`.

Task 6.8 removes both lines of `retain_files` and every `// periphery:ignore - task 6.8`. `periphery scan` then shows that each declaration has a caller in the app. `VATRate(text:)` comes with its only caller, the setting of group 7, so it needs no ignore.

Group 3 makes the list read the rows, and group 4 makes the changes write parts. Between those groups, a part row cannot be changed in the app. No path of the app makes a split before the harness command of group 4, so no user meets that state. The harness of group 4 uses throwaway data only. Group 5 completes format v2 in tasks 5.1a and 5.2a before group 6 enables split commands for users.

## Risks / Trade-offs

- A refresh that undoes a split loses the categories and the comments of its parts. The user splits again, and the mark with its note says why. Banks change booked amounts rarely, so the user rarely meets this. Keeping the parts would keep a wrong sum or a wrong balance instead.
- A part row is a `Transaction` value whose ID is not in `bankTransaction`. Writing it with `Store.save` as a transaction would add a row that changes the balance. Only `AppModel.commit` writes rows, and it takes only the result of `Ledger.changes(from:)`. The tests of 4.1 check that a changed part row gives a part and no transaction.
- How the `export transactions` of MoneyMoney carries a split booking is not recorded. `docs/research/moneymoney-analysis.md` names only the window and the menu entries. `MoneyMoneyMigration.plan` makes one transaction of each row of the export, so parts that the export lists as rows arrive today as separate transactions. If the export lists the original as a row as well, the balance counts the amount twice. The proposal of `add-moneymoney-migration` says that the app keeps such parts as separate transactions and names them in the report. The code writes no such note yet. Group 8 of `tasks.md` records the export with a made-up MoneyMoney database, tests the migration with a synthetic export in that shape, and builds the note.
- Checking one part checks all parts of the transaction. A user who wants to check parts one by one cannot. The bank statement has one line for the transaction, so one checkmark fits it.
- A search for the amount of the original lists all its parts. This finds the transaction by the amount on the bank statement.
- The list of VAT rates belongs to the user account of the Mac, not to the database. A second database shows the same rates. Each part keeps its rate, so changing the list changes no part.
- `rows(in:filter:)` looks up each row in the part rows when the ledger has splits, and the build and `update(_:)` build part rows. Task 3.3 builds the ledger of `PerformanceTests` with 1,000 splits among its 50,000 transactions and keeps all existing budgets, including the sidebar under 20 ms and the amount-range filter under 100 ms, as well as the build, search, category view, and update budgets.

## Migration Plan

`v17` creates an empty table and rewrites no row. Undoing every split empties the table again. `v20` turns `needsReview` into `review` and keeps the mark of every row that has it. No release has shipped, so no database has a `v17` or a `v20` from another build.

PR #203 uses v18 for file identity and PR #219 uses v19 for CSV profiles. v20 is the next free number after v18 and v19, so split review reasons use v20.
