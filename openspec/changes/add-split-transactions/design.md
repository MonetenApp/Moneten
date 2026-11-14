# Design

## Context

The proposal says why users split a transaction. This design decides how the parts are stored and how every list and sum reads them. The build is a Swift package with the modules of [ADR 0010](../../../docs/decisions/0010-swift-package-and-macos-15.md), and all data stays in the encrypted database on the Mac ([ADR 0002](../../../docs/decisions/0002-local-first-no-server.md), [ADR 0005](../../../docs/decisions/0005-grdb-and-sqlcipher.md)). No decision record changes.

What main has today, and what a split must not break:

- `Transaction` is stored in the table `bankTransaction`. `Ledger.transactions` holds every stored row, newest first. `Ledger.computedBalance` and `dailyBalances` add these rows to the initial balance, and `Account.deriveInitialBalance` subtracts them from the bank balance.
- `reconcile` recognizes a delivered row by its source ID, then by a fingerprint of booking day, amount, purpose, counterparty IBAN, and end-to-end reference. It builds the fingerprint from the stored columns at every merge. `Store.merge` reads the stored rows of the account inside its write transaction.
- `Ledger.transactions(in:filter:)` gives the rows of the list, the category view, the status line, the charts of categories, the search, and the filters. `Ledger.sum(ofCategory:in:)` reads it for the amount in the sidebar.
- `RuleApplier.apply` walks `Ledger.transactions`. `reconcile` runs `Categorizer.categorize` on a row whose bank fields changed.
- `AppModel.commit` writes changed rows with `Store.save` and then calls `Ledger.update`. The views find a selected row with `Ledger.transaction(_:)`.
- App settings live in `UserDefaults` through the keys of `Preference`.
- Periphery runs in strict mode on the app schemes, not on the tests. A declaration that only a test calls fails `scripts/check.sh`.

## Goals / Non-Goals

**Goals:**

- One data shape in which a split cannot change a balance or the identity of a transaction, and an undo needs no stored copy of the original.
- One function that decides which rows a list or a sum by category counts, so that no place counts the original and its parts both.
- Pull requests that each end in a check: the arithmetic, the table, the rows and sums, the refresh and the rules, the commands, and the settings.

**Non-Goals:**

- The positions of a batch payment. The change `add-payment-outbox` knows them. It adds the name and the purpose of a part and enables "Split from Batch Payment". Until then the command is disabled.
- A changed amount of a part after the split. The user undoes the split and splits again.
- Split records of QIF files (`add-more-import-formats`) and the export, budgets, reports, and printouts of split transactions. Those changes read the rows that this design defines.

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
- `VATRate`: `hundredths`, the rate in hundredths of a percent, so 19 % is 1900 and 8,1 % is 810. `VATRate.standard` is 19 % and 7 %. Hundredths keep the rates of Switzerland and Austria exact, and the arithmetic stays in integers.
- `SplitError`: `pending` for a row that the bank has not booked, and `zeroPart` for a split that would make a part of 0.

The parts of one transaction are at least two, none is 0, and they add up to its amount. Only the functions of `Split.swift` build parts, so the rule lives in one file.

### The arithmetic

- `Split.amount(from:sign:)` reads the text of the amount field with `AmountParser`. A number without a sign takes the sign of the row, so "25,00" on -80,00 € is -25,00 €. A number with a sign keeps it, so "+5,00" on -80,00 € is 5,00 €. Text that is not a number gives nil.
- `Split.amounts(of:off:)` returns the entered amounts and then the remainder, the amount of the row less their sum. It throws `zeroPart` for an entered amount of 0 and for a remainder of 0. Entering the whole amount leaves nothing to split, so the app treats it like 0 and marks the field. Task 1.1 adds this scenario to the spec.
- `VATRate.split(_:)` computes the net part as the gross amount times 10.000 divided by 10.000 plus the rate in hundredths. Swift divides integers toward zero, which is the cut toward zero at the cent of the spec, also for a refund. The tax part is the gross amount less the net part. -10,00 € at 7 % gives -9,34 € and -0,66 €. -0,01 € gives a net part of 0, so the app refuses it like an amount of 0.
- `Ledger.splitting(row:off:)` and `Ledger.splittingVAT(row:rate:)` return the complete new list of parts of the transaction behind a row. The row can be a transaction without a split or a part. A part is replaced in place by its new parts, so splitting the part of -55,00 € of the receipt gives -25,00 €, -15,00 €, and -40,00 €, and one undo brings back -80,00 €. Each new part copies the category and the comment of the row, and the positions count from 0 again. A pending row throws `pending`.

### The ledger offers rows, and the original stays the stored truth

`Ledger.transactions` keeps every stored transaction and never a part. Everything that counts the money of an account reads it, as today.

`Ledger.transactions(in:filter:)` becomes `Ledger.rows(in:filter:)`, so each call site says what it counts. A row is a transaction without a split, or a part row in place of a split transaction. A part row is a `Transaction` value with the ID, the amount, the category, and the comment of the part. Its `categorizedBy` is `manual`, or `none` without a category. Every other field comes from the original: the date, the counterparty, the purpose, the account, the checkmark, and the marks for new and for review. The parts of one transaction follow each other in the order of `position`.

`Ledger.replaceParts(of:with:)` sets the parts of one transaction, and an empty list removes them. The ledger keeps the part rows of each split transaction and builds them again when its parts or its original change. `rows(in:filter:)` puts them in place of the original while it filters. The ledger keeps no second copy of all 50,000 rows, and a ledger without splits filters as before. `Ledger.row(_:)` finds a row by its ID. `Ledger.transaction(_:)` still finds only stored transactions.

The search text of a part row holds the fields of the original, the comment of the part, the amount of the part, and the amount of the original. A search for -80,00 then finds both parts of the receipt, whose sum the status line shows as -80,00 €.

Removing an account, a transaction, or a category changes the parts in the ledger as the database does. The parts of a removed transaction go, and a part of a removed category becomes uncategorized. `AppModel.remove(category:)` changes the transactions of the ledger itself today. A ledger function takes that over for the transactions and the parts.

### Where each count reads

No place counts a split twice, because `rows(in:filter:)` never holds a split original and `Ledger.transactions` never holds a part.

| Place | Reads | Task |
|---|---|---|
| Amount of a category in the sidebar, `Ledger.sum(ofCategory:in:)` | rows | 3.1, 3.2, and task 3.3 of `add-categories` |
| List, category view, and status line, `AppModel.visibleTransactions` | rows | 3.1, 3.2 |
| Category bars and pie charts, `periodSums` and `categoryTotals` of `AppModel.chartTransactions` | rows | 3.1, 3.2 |
| Search and filters | rows | 3.1, 3.2 |
| Balance, daily balance, and initial balance | transactions | 3.1 checks that they stay |
| Merge, migration, and new marks | transactions | 4.1, 4.2 |
| Budgets, reports, printouts, and export | rows, and the parts for "Export All Data..." | the changes `add-budgets`, `add-reports`, `add-printing`, and `add-data-export` |

### Writing a change of a row

`Ledger.changes(from:)` turns changed rows into what the store writes: transactions and parts. A part row gives its category and its comment to its part. Its checkmark and its marks for new and for review go to the original, and several rows of one original give one original. `AppModel.commit` calls it and writes both with `Store.save` in one transaction, then updates the ledger. The views look up a selected row with `Ledger.row(_:)`: the context menu, the category ribbon, the category choices, and the comment sheet. "Edit Transaction..." on a part shows the bank fields read-only, as for a fetched row, and saves the category and the comment of the part.

The checkmark belongs to the whole transaction, because the user checks a transaction against the one line of the bank statement. Checking one part checks all parts of its transaction. Task 1.1 adds this scenario to the spec.

### A refresh recognizes the original and changes nothing

`reconcile` takes the IDs of the split transactions of the account. `Store.merge` reads them inside its write transaction, as it reads the stored rows. A delivered row whose partner is a split original never adds a row. The original may take the link of the delivered row, its source ID and `isFetched`, because the link changes no amount and no category. It never takes the bank fields, and the rules never run on it. The parts keep their sum, and an undo still gives back the category from before the split.

A split original is always booked. So it never pairs with a pending row, and a merge never drops it.

### Rules leave splits alone

`RuleApplier.apply` skips split transactions. The parts are not in `Ledger.transactions`, so no rule reaches them. The number of matching transactions in the category settings skips split transactions too, so it equals what applying the rule changes.

### Storage

Migration `v16` in `Sources/Storage/Schema.swift` adds the table `splitPart`. Issue #150 adds `v15` in another lane, so `v16` comes after it.

- `id` (primary key), `transactionID` (references `bankTransaction` with `ON DELETE CASCADE`, indexed), `position`, `amountMinor`, `categoryID` (references `category` with `ON DELETE SET NULL`), `comment`, `vat`.
- `vat` is JSON, as `account.refreshError` is.
- The parts go with their transaction, and so with their account.

`SplitPart` is a GRDB record like `Transaction`. `Store.loadLedger` reads the parts. `Store.replaceParts(of:with:)` deletes the parts of a transaction and writes the new ones in one transaction. An empty list is the undo. `Store.save` for transactions also takes parts, for `AppModel.commit`.

### The commands in `App`

The context menu of a row gets the submenu "Split Transaction" with "Split Amount...", one entry "Split 19% VAT" for each rate, "Split from Batch Payment", and "Undo Split Transaction...". The entries are enabled for one selected row. On a pending row, "Split Amount..." and the VAT entries say that only booked transactions can be split and change nothing. "Split from Batch Payment" is always disabled. "Undo Split Transaction..." is enabled only on a part.

The split window `SplitSheet` shows the row, the field for the amount, and the remainder. "Next Split" keeps the entered amount and empties the field. The window marks the field for an amount of 0, for an amount that leaves a remainder of 0, and for text that is not a number. A split and an undo remove a shown row and add others. So both go through `AppModel.replacingTable`, as a refresh that removes shown rows does (issues #135 and #151). After a split the new parts are selected, and after an undo the original.

A part row shows a mark and "Part of -80,00 €" with the amount of the original, and the label of a VAT part. The pull request settles the look with snapshots.

"Undo Split Transaction..." asks "Replace the split transactions with the original transaction?" and says "The split transactions cannot be restored." "Delete Transaction..." on a selection with a part says that a part of a split cannot be deleted alone, and names "Undo Split Transaction...". `AppModel.delete` refuses such a selection too, so no other path deletes a part.

### The list of VAT rates is a setting

`Preference.vatRates` stores the rates in `UserDefaults` as an array of hundredths. `Preference.registerDefaults` registers `VATRate.standard`, 1900 and 700. The tab "General" of the settings gets a list of the rates with add, change, and remove. `VATRate(text:)` reads a rate with up to two decimals above 0, so "8,1" is 810. The submenu shows the rates in the order of the list. An empty list shows no VAT entry. Rates are numbers, so the setting holds no personal data, as the change `add-app-settings` requires.

### Order of the work

Each group of `tasks.md` is one pull request. Groups 1 to 3 add code that only group 5 calls: the arithmetic, `Ledger.replaceParts(of:with:)`, and `Store.replaceParts(of:with:)`. They put it into `Split.swift` in `Sources/Domain` and `Store+Split.swift` in `Sources/Storage` and list both files in `retain_files` of `.periphery.yml`, as the sync model was listed until the connectors used it. Group 5 removes both lines.

## Risks / Trade-offs

- A bank can deliver a split transaction again with the same source ID and another amount. The original keeps its old amount, and the balance of the account differs from the bank by the difference. Banks change booked amounts rarely. The user undoes the split, and the next refresh takes the new amount.
- A part row is a `Transaction` value whose ID is not in `bankTransaction`. Writing it with `Store.save` as a transaction would add a row that changes the balance. Only `AppModel.commit` writes rows, and it always goes through `Ledger.changes(from:)`. Test 3.1 checks that a changed part row gives a part and no transaction.
- Checking one part checks all parts of the transaction. A user who wants to check parts one by one cannot. The bank statement has one line for the transaction, so one checkmark fits it.
- A search for the amount of the original lists all its parts. This finds the transaction by the amount on the bank statement.
- The list of VAT rates belongs to the user account of the Mac, not to the database. A second database shows the same rates. Each part keeps its rate, so changing the list changes no part.
- `rows(in:filter:)` looks up each row in the part rows when the ledger has splits. Task 3.3 holds it to the budget of `PerformanceTests` with 50,000 transactions and 1,000 splits.

## Migration Plan

`v16` creates an empty table and rewrites no row. Undoing every split empties the table again. No release has shipped, so no database has a `v16` from another build.
