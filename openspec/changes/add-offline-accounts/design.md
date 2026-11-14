# Design

## Context

This change is part of the first build of the app. The build is a Swift package with the modules `Domain`, `Storage`, `Import`, and `App`, as [ADR 0010](../../../docs/decisions/0010-swift-package-and-macos-15.md) describes. Everything runs on the Mac, with no server ([ADR 0002](../../../docs/decisions/0002-local-first-no-server.md)).

The app keeps all accounts, categories, and transactions of the open database in one in-memory `Ledger` (module `Domain`). Every change goes to the database through `Store` (module `Storage`) and then to the ledger. Views read the ledger. This keeps filters, sums, and charts fast for some ten thousand transactions without queries per keystroke.

## Decisions

The first build follows the spec where the task list marks a task as checked. Open tasks keep the behavior of the spec as the target.

### Balance of an offline account

`Domain` owns the balance. `Ledger.computedBalance` adds the initial balance and every row of the account in the account currency, pending rows included except those with `needsReview`, as the changes `add-charts` and `add-account-refresh` decide. `Account.isInBalance`, which PR #139 adds, holds this test. It is the same function that the balance chart starts from, so the sidebar and the last bar agree. Once splits exist, the parts count and the original does not, as the change `add-split-transactions` defines. A new offline account has an initial balance of 0, and the account settings of the change `add-account-management` change it.

### One signed amount

The transaction window in `App` has one amount field. `AmountParser` in `Domain` reads the text with its sign, and the window stores that value as it is. The window has no choice between money in and money out, so no switch can flip a typed sign.

### Offsetting entry

`Domain` builds the offsetting entry from the source transaction, the source account, and the target account, so that a test can check every field. The entry is a manual transaction. It takes the name, the purpose, the comment, and the category of the source, and the booking date of the source as its booking date and value date. The copied category gets `categorizedBy` `.manual`, because `Categorizer.categorize` keeps only a manual category and would otherwise move a copied rule category, or clear it when no rule matches. The IBAN and BIC of the source account become `counterpartyIBAN` and `counterpartyBIC`. `Transaction` has no fields for an account number and a bank code, so a source account without an IBAN gives no counterparty account. A category restricted to an account other than the target is dropped, and then the categorization rules run on the entry, which has `categorizedBy` `.none`. No link joins the two rows, so an edit of one changes only that row.

## Risks / Trade-offs

Tasks marked as built in part may differ from the spec in the way their note says.
