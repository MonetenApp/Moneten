# Design

## Context

This change is part of the first build of the app. The build is a Swift package with the modules `Domain`, `Storage`, `Import`, and `App`, as [ADR 0010](../../../docs/decisions/0010-swift-package-and-macos-15.md) describes. Everything runs on the Mac, with no server ([ADR 0002](../../../docs/decisions/0002-local-first-no-server.md)).

The app keeps all accounts, categories, and transactions of the open database in one in-memory `Ledger` (module `Domain`). Every change goes to the database through `Store` (module `Storage`) and then to the ledger. Views read the ledger. This keeps filters, sums, and charts fast for some ten thousand transactions without queries per keystroke.

## Goals / Non-Goals

**Goals:** a rule language that accepts every example of the spec, exact error positions, and one place that decides the category of a transaction.

**Non-Goals:** rules that run during a refresh, because there is no refresh yet.

## Decisions

- `Sources/Domain/Rule.swift` holds a tokenizer and a recursive descent parser. Precedence is `NOT`, then `AND`, then `OR`. Two expressions without an operator are joined with `AND`.
- The tokenizer reads `and`, `or`, `not`, `true`, and `false` in any letter case as operators. `+` between two expressions is `AND`. `!`, and `-` before an expression that is not an amount, are `NOT`. A hyphen inside a word, as in "EC-Karte", stays part of the word.
- A field test takes `:`, `=`, `==`, or `:=` for a match and `!=` or `<>` for no match. An amount comparison takes `:=` as equal and `<>` as not equal.
- A term matches whole words. The text of a field is folded (lower case, composed Unicode, ä to ae, ß to ss) and split at white space. A phrase matches a run of words. `*` and `?` match inside one word. This is why `"Kundennummer 67890*"` is needed when a slash follows the number, as the MoneyMoney help says.
- A term without a field operator searches the name, the purpose, the booking text, the references, the creditor ID, and the comment. The account fields are searched only through `local_account:` and `remote_account:`.
- Account fields compare without spaces, so `local_account:"DE02 1203 ..."` matches.
- Regular expressions are case-insensitive and run on the unfolded text of each field.
- `Categorizer` walks the categories in sidebar order and returns the first match. `RuleApplier` applies one changed rule to existing transactions in the two modes of the spec.

## Risks / Trade-offs

- A hyphen or a slash does not split a word, so `"REWE"` does not match "REWE-Markt". A user who writes a new rule may need a `*` more often than expected. The help shows this case.
- The words and, or, not, true, and false are operators in every letter case. A rule stored by the first build that used one of them in lower case as a search word changes its meaning.
