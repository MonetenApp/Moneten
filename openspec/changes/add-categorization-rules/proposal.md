# Proposal: Categorize transactions with rules

## Why

A user with several accounts gets hundreds of transactions each month. Nobody sorts them by hand for long. Rules sort new transactions into categories without work, and they are the feature that turns a transaction list into a household book.

## What Changes

- Each category gets one rule. The rule is a search expression.
- The expression language has terms that match whole words, phrases, the wildcards `*` and `?`, the operators `AND`, `OR`, and `NOT` in any letter case with the short forms `+`, `!`, and `-`, the rules `true` and `false`, parentheses, field operators such as `name:` and `purpose:`, amount comparisons, and regular expressions.
- The app applies the rules to every new transaction, and again when a pending transaction is booked.
- When the user changes a rule, the app asks how to apply it to existing transactions.
- A category can be restricted to one account or account group.

## Capabilities

### New Capabilities

- `categorization-rules`: the rule language, when rules run, and how a changed rule is applied to existing transactions.

### Modified Capabilities

None.

## Impact

- Milestone: v0.1
- Issues: #19
- Modules: `Domain` owns the rule parser and the rule engine. `App` owns the rule field in the category settings and the apply dialog.
- Depends on the change `add-categories`.
- Decisions: none apply.

## Reference behavior

### Observed in MoneyMoney 2.5.3

- The rule language, with all operators and examples, is documented on the [categorization page](https://moneymoney.app/categorization/).
- The category settings hold the rule in one text field under "Rules for automatic categorization", next to "Restrict to" and a help button. See [analysis](../../../docs/research/moneymoney-analysis.md#category-u-w).
- After a rule change the app asks "Should this categorization rule be applied to the existing transactions now?" with the options "Apply only to not yet categorized transactions." and "Apply to all transactions."
- "Apply to all" overwrites manual assignments and removes transactions that no longer match from the category.
- Rules run again when a pending transaction is booked, because a pending transaction often has an incomplete purpose (version history, 2.2.12).
- Rules can search comments (version history, 2.3.10).
- Adjacent terms are joined with "and" by default (version history, 2.1.1).

### Decided for Moneten

- When rules of several categories match one transaction, the first category in sidebar order wins. MoneyMoney does not document its order.
- The operators `and`, `or`, and `not` work in any letter case, with `+` for `AND` and `!` or `-` for `NOT`. `true` and `false` are rules of their own, and `:=` and `<>` are further forms of equal and not equal. Users write rules in lower case and expect `or` to mean either word. MoneyMoney's help asks for the operators in capitals, so there a rule such as `"Lohn" or "Gehalt"` needs all three words and finds almost nothing. A migrated rule of that kind then works as its author meant it, and the migration report names it. A word in quotation marks stays a search word, so `"or"` still finds the word or.
- A term matches a whole word, and only `*` and `?` match part of a word. A short term such as "REWE" then does not pull in a longer word such as "REWE-Markt" by accident. A user who wants that writes `"REWE*"`.
- A term without a field operator does not search account numbers or IBANs. A number in a rule then does not pull in transactions because of the account they belong to. `local_account:` and `remote_account:` search the accounts on purpose. The migration report names every migrated rule with an IBAN or an account number as such a term.
- The app rejects a rule with a syntax error and shows where the error is. MoneyMoney's behavior was not observed.
- A category that the user assigned by hand survives the next refresh and the booking of a pending transaction. Only "Apply to all transactions." replaces it.
