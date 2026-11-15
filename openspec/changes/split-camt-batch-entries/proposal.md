# Proposal: Split a CAMT batch entry into its payments

## Why

A CAMT entry that bundles several payments, such as a batch of transfers or direct debits, is one transaction with the amount of the entry. The categorization rules and the search see only the whole batch, not each payment in it. Splitting the entry into separate transactions would count the batch twice: a refresh or an MT940 file brings the same booking as one row with the total, and nothing would match that row against the parts.

## What Changes

- A CAMT entry whose transaction details each have an amount, and whose amounts add up to the entry, stays one transaction and is split into one part per detail.
- Each part takes the amount, the counterparty, and the purpose of its detail. The rules give each part its category, and the search finds each part.
- A refresh or a file that brings the batch as one row with the total matches the transaction as before, so the payment counts once, whichever arrives first.
- A batch that arrived first as one row from a refresh or another file gets its parts when the CAMT file is imported later.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `transaction-import`: a CAMT entry with several payments is split into parts when its details add up to the entry. The requirement "CAMT entry with several payments" of `add-file-import` keeps applying to an entry whose details do not.

## Impact

- Milestone: v0.1
- Issues: #148
- Modules: `Import` reads the amount of each transaction detail and returns the positions of a batch. `Domain` turns the positions into parts and runs the rules on them, and `reconcile` gives the parts to a stored row. `Storage` stores the parts.
- Depends on `add-split-transactions` for the parts of a transaction, on `add-file-import` for the CAMT reader, and on `add-categorization-rules` for the rules.
- Decisions: none apply.

## Reference behavior

### Observed in MoneyMoney 2.5.3

- The context menu of a transaction has "Split Transaction" with "Split from Batch Payment". See [analysis](../../../docs/research/moneymoney-analysis.md#context-menus-u).
- The analysis does not record how a CAMT batch entry is imported.

### Decided for Moneten

- The app splits a batch at the import, without a command, when every detail has an amount and the amounts add up to the entry. A user who imports a statement wants each payment in its category without one more step.
- The batch stays one transaction and its payments are parts of it. A refresh or an MT940 file brings the batch as one row with the total, and the transaction matches it as any other row does. Separate transactions would need their own rule to match a total against a set of parts, in both orders, and across deletions.
- A part of a batch has the name and the purpose of its payment, and the rules categorize it. A part that the user splits by hand keeps the name and the purpose of its transaction, and only the user sets its category, as `add-split-transactions` says.
- A batch whose details do not add up to the entry stays one transaction without parts, as `add-file-import` says. A guess at the missing amount could put money in the wrong category.
