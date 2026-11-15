# Design

## Context

`add-file-import` imports a CAMT batch entry as one transaction with the amount of the entry and without a single counterparty (`CAMTParser` in `Sources/Import/TransactionFileImporter.swift`). `add-split-transactions` adds parts to a transaction: a `SplitPart` with an amount, a category, and a comment, which add up to the amount of the transaction. Its design leaves the positions of a batch to `add-payment-outbox`. This change gives a CAMT batch those positions, so it needs the parts of `add-split-transactions` first. No decision record applies.

## Decisions

- **One transaction with parts, not one transaction per payment.** The transaction keeps the amount, the date, and the fingerprint of the entry, so `reconcile` (module `Domain`) matches a total from a refresh or an MT940 file as it matches any row. Nothing new decides whether a total and a set of parts are the same payment, and a deleted part cannot let a total in again.
- **The reader returns positions.** `CAMTParser` reads `TxDtls/Amt` and `TxDtls/AmtDtls/TxAmt/Amt` of each detail, signed by the `CdtDbtInd` of the detail or else of the entry. `TransactionFileImporter.Parsed` gets the positions of each transaction: amount, name, IBAN, and purpose. The reader returns positions only when there are two or more, each has an amount in the currency of the entry, and they add up to the entry. The fields of the transaction stay as `add-file-import` says.
- **A part of a batch has a name and a purpose.** `SplitPart` gets `name` and `purpose`, nil for a part that the user splits by hand. A part row takes them in place of the fields of its transaction, so the search text and the rules see the payment. This is the field that the design of `add-split-transactions` plans for `add-payment-outbox`.
- **The rules run once, when the parts are created.** `Categorizer.categorize` runs on each part row of a batch at the import, and the category counts as set by a rule. Later changes to a rule follow `add-categorization-rules` and `add-split-transactions` for parts.
- **`reconcile` gives parts to a stored total.** `Delivery.file` carries the positions. For a delivered row that has positions and matches a stored row (`partners`), and the stored row has no parts, the result lists new parts for that row. `Reconciliation` gets `split: [UUID: [SplitPart]]`, and `Store.merge` writes it in the same transaction. A stored row with parts keeps them. The result message counts the split rows.

## Risks / Trade-offs

- A bank that delivers a pending total and books it later: the parts attach only to a booked row. A pending row from a refresh that the CAMT file books gets its parts at the booking, through `takingBankFields(of:)` and the same `split` list.
- A total from a refresh with another purpose than the CAMT entry does not match by fingerprint. It matches through the rules of `add-account-refresh` for a row without IBAN and references, as today, or it does not match and both rows stay, as today.
- Rejected: one transaction per payment, as issue #148 first asked. It needs a batch key on each row and on each deleted row, a migration, and a rule in `reconcile` that matches a delivered total against stored parts and stored parts against a delivered total. A part that the user deletes changes the sum, and a later refresh then adds the total again.
