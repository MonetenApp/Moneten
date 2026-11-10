# Design

## Context

This change is part of the first build of the app. The build is a Swift package with the modules `Domain`, `Storage`, `Import`, and `App`, as [ADR 0010](../../../docs/decisions/0010-swift-package-and-macos-15.md) describes. Everything runs on the Mac, with no server ([ADR 0002](../../../docs/decisions/0002-local-first-no-server.md)).

The app keeps all accounts, categories, and transactions of the open database in one in-memory `Ledger` (module `Domain`). Every change goes to the database through `Store` (module `Storage`) and then to the ledger. Views read the ledger. This keeps filters, sums, and charts fast for some ten thousand transactions without queries per keystroke.

## Goals / Non-Goals

**Goals:** a rule language that accepts every example of the spec, exact error positions, and one place that decides the category of a transaction.

**Non-Goals:** rules that run during a refresh, because there is no refresh yet.

## Decisions

- `Sources/Domain/Rule.swift` holds a tokenizer and a recursive descent parser. Precedence is `NOT`, then `AND`, then `OR`. Two expressions without an operator are joined with `AND`.
- A term matches whole words. The text of a field is folded (lower case, composed Unicode, ä to ae, ß to ss) and split at white space. A phrase matches a run of words. `*` and `?` match inside one word. This is why `"Kundennummer 67890*"` is needed when a slash follows the number, as the MoneyMoney help says.
- Account fields compare without spaces, so `local_account:"DE02 1203 ..."` matches.
- Regular expressions are case-insensitive and run on the unfolded text of each field.
- `Categorizer` walks the categories in sidebar order and returns the first match. `RuleApplier` applies one changed rule to existing transactions in the two modes of the spec.

## Risks / Trade-offs

- MoneyMoney does not document whether it splits words at punctuation. Whole-word matching follows its help text. Rules taken over by hand may need a `*` more often than expected.
