# Tasks

One task per requirement of the spec. A task is checked only when a test or a check in the running app shows the behavior.

## 1. Requirements

- [x] 1.1 One rule per category. Verified by the category settings show the rule field, see the debug harness snapshot in the first build.
- [x] 1.2 Terms match text without regard to case and umlauts. Verified by RuleTests "Case is ignored" and "Umlauts are folded".
- [x] 1.3 Unqualified terms search all text fields. Verified by RuleTests "Term found in the comment" and "IBAN without a field operator".
- [x] 1.4 Phrases match words in order. Verified by RuleTests "Phrase in order and in another order".
- [x] 1.5 Wildcards. Verified by RuleTests "Wildcards".
- [x] 1.6 Logical operators. Verified by RuleTests "Logical operators", "Lower case operator", "Mixed case operator", and "Operator word in quotation marks".
- [x] 1.7 Field operators. Verified by RuleTests "Field operators", "Field does not match", "Equality forms", "Field name in capitals", "Not equal after a field name", "A word after a field operator is a term, also an operator word or a word that starts with a sign", and "A field operator needs its term without a space".
- [x] 1.8 Amount comparisons. Verified by RuleTests "Amount comparisons", "Amount not equal", and "Amount equal with :=".
- [x] 1.9 Regular expressions. Verified by RuleTests "Regular expressions".
- [x] 1.10 Invalid rules are rejected. Verified by RuleTests "Missing parenthesis is reported at the end" and "Sign after a field operator"; the settings sheet shows the message and disables OK.
- [x] 1.11 Rules run on new transactions. Verified by CategorizerTests "Refresh brings a transaction into its category"; file import and manual entry call the categorizer.
- [x] 1.12 The first matching category wins. Verified by CategorizerTests "The first category in sidebar order wins".
- [x] 1.13 Rules respect the account restriction of a category. Verified by CategorizerTests "Rules respect the account restriction".
- [x] 1.14 Rules run again when a pending transaction is booked. Verified by ReconcileTests "The rules run again on a booked row" and "A category that the user set by hand stays at the booking".
- [x] 1.15 Ask how to apply a changed rule. Verified by CategorizerTests "Apply only to uncategorized transactions, or to all"; the dialog in the category settings offers both choices.
- [x] 1.16 Applying a rule to all transactions replaces earlier assignments. Verified by CategorizerTests "A transaction that no longer matches leaves the category".
- [x] 1.17 Progress while a rule is applied. Verified by CategorizerTests "Applying a rule reports progress every 1,000 transactions and at the end", "A rule run keeps a row that a refresh changed during the run in the category that its current text gives it", and "A cancelled rule run stops and changes nothing", and in the app with 50,175 transactions: the category settings show "Applying rule to transaction 15,000 of 50,175..." with Cancel, OK, and the fields disabled, Escape leaves the sheet open, the harness logs the menu commands disabled during the run and enabled before and after it, after the run the line is gone and the sum of "Groceries" in the sidebar is the sum of the matching rows, and a lock during the run ends it within 58 ms, saves nothing, and shows no count.
- [x] 1.18 Help for the rule language. Verified by the help button opens a popover with one example for each operator, see the light and dark snapshots of the debug harness command `rulehelpsnapshot` in the pull request.
- [x] 1.19 A term matches a whole word. Verified by RuleTests "Word with a hyphen, whole word, and wildcard for part of a word" and "Wildcards".
- [x] 1.20 The rules true and false. Verified by CategorizerTests "Catch-all category" and RuleTests "Rule that matches nothing" and "Quoted true is a word".
- [x] 1.21 Short forms of the operators. Verified by RuleTests "Short forms", "Minus before a term", "Minus before a number", "Plus before a number", "Minus after a word, before a quotation mark or a parenthesis", "Minus after an amount comparison, before a parenthesis", "Plus sign inside a word", "Exclamation mark at the end of a word", and "Not equal after a field name".
- [x] 1.22 A saved rule that cannot be read is marked. Verified by CategorizerTests "A category whose saved rule cannot be read reports the error until the rule is fixed", and in the app: the sidebar row of "Rent" with `amount<-1,000` shows the warning symbol, and with `amount<-1000` it shows none. A group has no rule and shows no mark, even with a saved rule from a migration. Verified by CategorizerTests "A category group has no rule, so it shows no mark, takes no transaction, and leaves the transaction to a category below it", and in the app: the group "Living" with `amount<-1,000` shows no warning symbol.

- [x] 1.23 A group has no rule. Verified by CategorizerTests "A category group has no rule, so it shows no mark, takes no transaction, and leaves the transaction to a category below it". Pending bookings run the same categorizer, verified by ReconcileTests "The rules run again on a booked row".
- [x] 1.24 A regular expression in a rule that does not end. Verified by RuleTests "A regular expression that does not end stops, and the rule matches no further row" and CategorizerTests "A rule that does not end leaves 1,000 rows to the next category": `/^+?49/` over 1,000 rows ends in under a second of processor time, and the category below takes all 1,000. CategorizerTests "A rule stops when all its regex calls of one run add up to its limit" stops 200 texts of 18 "a" against `purpose:/(a+)+$/` after about 1 second, also in a count of matches.
- [x] 1.25 A stopped rule is shown. Verified by CategorizerTests "Applying a rule that does not end changes no row" for both modes, and in a debug build: with `name:"Telekom" OR /^+?49/` on "Internet & Phone", the category settings show "The regular expression at position 19 stopped because it is too slow." in light and dark mode, and the harness command `applyrule` shows the same text as an alert. The snapshots are in the pull request.
- [x] 1.26 A stopped rule matches nothing in its run. Verified by CategorizerTests "A rule that stops matches no row of the refresh, in either order of the rows" and MergeTests "A rule that stops during a merge matches no row of it, in either order of the rows", which go through `Store.merge`.
- [x] 1.27 A stopped rule never moves a transaction that a rule sorted. Verified by CategorizerTests "A stopped rule never moves a row that a rule sorted, also when the bank books it", in both orders of the rows.

## 2. Changes to the first build

- [x] 2.1 Write RuleTests for the scenarios of "Logical operators", "Short forms of the operators", "The rules true and false", "Field operators", and "Amount comparisons": operators in lower and mixed case, `+`, `!`, `-` before a term, `-12,50` as a term, `Disney+` and `Yahoo!` as words, `name!=` as a field operator, a quoted "or" and "true" as terms, `true`, `false`, `name<>`, `currency=`, `currency==`, `currency:=`, and `amount<>` with a row of 0,00 €. Each test checks the row that matches and the row that does not. Replace the test "Lower case operator is a term" with the scenario "Lower case operator".
- [x] 2.2 Change the tokenizer and the parser in `Sources/Domain/Rule.swift` until the tests of 2.1 pass. Keep `amount=-89,00` an amount comparison, `name!="Stadtwerke"` a field operator, `-12,50` one term, and "EC-Karte", "Disney+", and "Yahoo!" one word each.
- [x] 2.3 Add an example for `+`, `!`, `-`, `true`, `false`, `<>`, and `:=` to the help popover in `App/Sources/Views/CategorySettingsSheet.swift`. Replace the line "AND, OR, and NOT must be written in capitals." with one that says the operators work in any letter case and a quoted word stays a search word. Add that a word without a field does not search account numbers or IBANs, and that `local_account:` and `remote_account:` do.
- [x] 2.4 Write the RuleTests test "IBAN without a field operator" from the scenario of "Unqualified terms search all text fields".
- [x] 2.5 Remove `localAccount` and `remoteAccount` from `RuleField.unqualified` in `Sources/Domain/Rule.swift` until the test of 2.4 passes.
- [x] 2.6 Write RuleTests for the scenarios of "A term matches a whole word": `"REWE"` does not match "REWE-Markt", matches "REWE Markt Musterstadt", and `"REWE*"` matches "REWE-Markt".

## 3. Integration

- [ ] 3.1 Check every scenario of the spec in a release build and record the result in the pull request.

## 4. Regular expressions that do not end and IBANs with other spaces (#246, #245)

- [x] 4.1 Write RuleTests for a rule `/^+?49/` over 1,000 rows: the run ends, no row matches, the next category takes every row, `stoppedRegexPosition` is 0, the first character of the rule, NOT before the regular expression matches no row, and "Apply to all transactions." changes nothing. Proof: the tests failed to compile before `stoppedRegexPosition` existed, and pass now in RuleTests and CategorizerTests.
- [x] 4.2 Move `RegexWatch` out of the search into its own file and use it in `Rule.matches`, `Categorizer`, and `RuleApplier` until the tests of 4.1 pass. Keep the search tests of #172 green. Proof: `scripts/test.sh` passes, and the existing regex tests of LedgerTests are unchanged. An empty field takes an answer found once per regular expression, as in the search. A release run over 50,000 rows with four filled fields takes 166 to 169 ms with the watch, against 81 to 84 ms without it.
- [x] 4.3 Show the stop in the category settings in place of the number of matches, and as an alert after "Apply to all transactions." and "Apply only to not yet categorized transactions.", with a German value. Proof: the debug harness snapshots of task 1.25.
- [x] 4.4 Write tests for an IBAN stored with U+00A0 and with U+202F: the search for the plain IBAN and for `local_account:DE02?1203*`, the same rule, and a file row with the IBAN in U+00A0 form that is skipped as stored. Then make `TextFolding.accountKey` remove every Unicode space separator until they pass. Proof: RuleTests "An IBAN written with a no-break or a narrow no-break space matches the plain IBAN", LedgerTests "An IBAN written with a no-break or a narrow no-break space is found by the plain IBAN, as the rule finds it", and FileImportTests "A file row with the IBAN in no-break space form is skipped as stored, also against a row that a file stored before" failed with 20 issues before the change and pass after it. `local_account:DE02?1203*` now matches no form of the IBAN in the search and in a rule alike, because `?` needs one character and the key has none between DE02 and 1203. `local_account:DE0?1203*` matches every form.
- [x] 4.5 Round 2 of the merge gate of #351. Make a stopped rule all-or-nothing within its run with `Categorizer.allOrNothing`, keep a row that a rule sorted, add the limit of 1 second for all calls of one parsed rule, let `RuleApplier.rebase` return no rows for a stopped rule, and count the matches of the category settings in a detached task after a pause of 250 ms. Proof: the five new tests of 1.24, 1.26, 1.27, and CategorizerTests "A rule that a row changed during the run stops saves nothing" each fail when its part of the fix is switched off, with 7 issues in all, and pass with it. Without the limit for the run, 200 texts of 18 "a" took 14 seconds in a debug build.
- [x] 4.6 Add a release budget for a regular expression in a rule. Proof: PerformanceTests "A regular expression in a rule categorizes and counts 50,000 rows within budget, and never reaches its limit" counts 7,865 matches of `/Haendler1/` in 0.57 s and categorizes the 50,000 rows in 0.54 s in two release runs, under the budget of 1 second each. About 390 ms of it builds the `RuleSubject` of each row.

## Workflow follow-up

- Archive the change with `openspec archive add-categorization-rules` when every task is checked.
