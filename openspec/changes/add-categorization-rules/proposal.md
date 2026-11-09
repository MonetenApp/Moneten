# Proposal: Categorize transactions with rules

## Why

A user with several accounts gets hundreds of transactions each month. Nobody sorts them by hand for long. Rules sort new transactions into categories without work, and they are the feature that turns a transaction list into a household book.

## What Changes

- Each category gets one rule. The rule is a search expression.
- The expression language has terms, phrases, the wildcards `*` and `?`, the operators `AND`, `OR`, and `NOT`, parentheses, field operators such as `name:` and `purpose:`, amount comparisons, and regular expressions.
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

### Decided for MonetenMoneten

- When rules of several categories match one transaction, the first category in sidebar order wins. MoneyMoney does not document its order.
- The app rejects a rule with a syntax error and shows where the error is. MoneyMoney's behavior was not observed.
- A category that the user assigned by hand survives the next refresh and the booking of a pending transaction. Only "Apply to all transactions." replaces it.
