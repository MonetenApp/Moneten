# Tasks

One task per requirement of the spec. A task is checked only when a test or a check in the running app shows the behavior.

## 1. Requirements

- [x] 1.1 One rule per category. Verified by the category settings show the rule field, see the debug harness snapshot in the first build.
- [x] 1.2 Terms match text without regard to case and umlauts. Verified by RuleTests "Case is ignored" and "Umlauts are folded".
- [ ] 1.3 Unqualified terms search all text fields. Built the other way: `RuleField.unqualified` also searches both account fields. RuleTests "Term found in the comment" passes. Change it in 2.4 and 2.5.
- [x] 1.4 Phrases match words in order. Verified by RuleTests "Phrase in order and in another order".
- [x] 1.5 Wildcards. Verified by RuleTests "Wildcards".
- [ ] 1.6 Logical operators. Built the other way: the operators count only in upper case, and `+`, `!`, and `-` are not operators. RuleTests "Lower case operator is a term" tests the old behavior. Change it in 2.1 and 2.2.
- [ ] 1.7 Field operators. Built in part: `:` only, verified by RuleTests "Field operators" and "A field operator needs its term without a space". The forms `=`, `==`, `:=`, `!=`, and `<>` come in 2.1 and 2.2.
- [ ] 1.8 Amount comparisons. Built in part: verified by RuleTests "Amount comparisons", without `amount:=` and `amount<>`. They come in 2.1 and 2.2.
- [x] 1.9 Regular expressions. Verified by RuleTests "Regular expressions".
- [x] 1.10 Invalid rules are rejected. Verified by RuleTests "Missing parenthesis is reported at the end"; the settings sheet shows the message and disables OK.
- [x] 1.11 Rules run on new transactions. Verified by CategorizerTests "Refresh brings a transaction into its category"; file import and manual entry call the categorizer.
- [x] 1.12 The first matching category wins. Verified by CategorizerTests "The first category in sidebar order wins".
- [x] 1.13 Rules respect the account restriction of a category. Verified by CategorizerTests "Rules respect the account restriction".
- [ ] 1.14 Rules run again when a pending transaction is booked. Build it and verify it with a test or in the app (needs the refresh of add-account-refresh).
- [x] 1.15 Ask how to apply a changed rule. Verified by CategorizerTests "Apply only to uncategorized transactions, or to all"; the dialog in the category settings offers both choices.
- [x] 1.16 Applying a rule to all transactions replaces earlier assignments. Verified by CategorizerTests "A transaction that no longer matches leaves the category".
- [ ] 1.17 Progress while a rule is applied. Built in part: the rule runs in the background and reports the count at the end, but shows no progress line. Finish it and verify it with a test or in the app.
- [ ] 1.18 Help for the rule language. Built in part: the help button opens a popover with one example per operator of the first build. The new forms come in 2.3.
- [x] 1.19 A term matches a whole word. Verified by RuleTests "Wildcards", where `"Kundennummer 67890"` does not match "Kundennummer 67890/Rechnung 12345".
- [ ] 1.20 The rules true and false. Not built. Build it in 2.1 and 2.2.

## 2. Changes to the first build

- [ ] 2.1 Write RuleTests for the scenarios of "Logical operators", "The rules true and false", "Field operators", and "Amount comparisons": operators in lower and mixed case, `+`, `!`, `-` before a term, `true`, `false`, `name<>`, `currency=`, `currency==`, `currency:=`, and `amount<>`. Replace the test "Lower case operator is a term" with the scenario "Lower case operator".
- [ ] 2.2 Change the tokenizer and the parser in `Sources/Domain/Rule.swift` until the tests of 2.1 pass. Keep `amount=-89,00` an amount comparison and "EC-Karte" one word.
- [ ] 2.3 Add an example for `+`, `!`, `-`, `true`, `false`, `<>`, and `:=` to the help popover of the category settings.
- [ ] 2.4 Write the RuleTests test "IBAN without a field operator" from the scenario of "Unqualified terms search all text fields".
- [ ] 2.5 Remove `localAccount` and `remoteAccount` from `RuleField.unqualified` in `Sources/Domain/Rule.swift` until the test of 2.4 passes.

## 3. Integration

- [ ] 3.1 Check every scenario of the spec in a release build and record the result in the pull request.

## Workflow follow-up

- Archive the change with `openspec archive add-categorization-rules` when every task is checked.
