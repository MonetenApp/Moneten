# Tasks

One task per requirement of the spec. A task is checked only when a test or a check in the running app shows the behavior.

## 1. Requirements

- [x] 1.1 One rule per category. Verified by the category settings show the rule field, see the debug harness snapshot in the first build.
- [x] 1.2 Terms match text without regard to case and umlauts. Verified by RuleTests "Case is ignored" and "Umlauts are folded".
- [x] 1.3 Unqualified terms search all text fields. Verified by RuleTests "Term found in the comment".
- [x] 1.4 Phrases match words in order. Verified by RuleTests "Phrase in order and in another order".
- [x] 1.5 Wildcards. Verified by RuleTests "Wildcards".
- [x] 1.6 Logical operators. Verified by RuleTests "Logical operators" and "Lower case operator is a term".
- [x] 1.7 Field operators. Verified by RuleTests "Field operators" and "A field operator needs its term without a space".
- [x] 1.8 Amount comparisons. Verified by RuleTests "Amount comparisons".
- [x] 1.9 Regular expressions. Verified by RuleTests "Regular expressions".
- [x] 1.10 Invalid rules are rejected. Verified by RuleTests "Missing parenthesis is reported at the end"; the settings sheet shows the message and disables OK.
- [x] 1.11 Rules run on new transactions. Verified by CategorizerTests "Refresh brings a transaction into its category"; file import and manual entry call the categorizer.
- [x] 1.12 The first matching category wins. Verified by CategorizerTests "The first category in sidebar order wins".
- [x] 1.13 Rules respect the account restriction of a category. Verified by CategorizerTests "Rules respect the account restriction".
- [ ] 1.14 Rules run again when a pending transaction is booked. Build it and verify it with a test or in the app (needs the refresh of add-account-refresh).
- [x] 1.15 Ask how to apply a changed rule. Verified by CategorizerTests "Apply only to uncategorized transactions, or to all"; the dialog in the category settings offers both choices.
- [x] 1.16 Applying a rule to all transactions replaces earlier assignments. Verified by CategorizerTests "A transaction that no longer matches leaves the category".
- [ ] 1.17 Progress while a rule is applied. Built in part: the rule runs in the background and reports the count at the end, but shows no progress line. Finish it and verify it with a test or in the app.
- [x] 1.18 Help for the rule language. Verified by the help button opens a popover with one example per operator.

## 2. Integration

- [ ] 2.1 Check every scenario of the spec in a release build and record the result in the pull request.

## Workflow follow-up

- Archive the change with `openspec archive add-categorization-rules` when every task is checked.
