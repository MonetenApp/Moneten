# Tasks

One task per requirement of the spec, and two tasks of the FinTS connector without a requirement of their own. Each task moved here from a v0.1 change on 19 November 2026 (owner decision). The text after "Moved from" is the text of the source task at that time. A task is checked only when a test or a check in the running app shows the behavior.

## 1. Requirements

- [ ] 1.1 Country menu. Moved from task 1.5 of `add-account-setup`: "Not built, and not needed for v0.1: the bank directory has only German banks, and the extensions declare no country for their services, so each entry of the menu would show the same banks and services. It comes with a bank directory of another country or with extensions that declare one."
- [ ] 1.2 Choose the access method. Moved from task 1.7 of `add-account-setup`: "Not built until a second method exists (E6)." E6 is issue #88, which added the services of extensions.
- [ ] 1.3 Switch the access method and keep the history. Moved from task 1.19 of `add-account-setup`: "Not built, and not needed for v0.1: it needs a second access method for one bank, which comes with 1.7 "Choose the access method" (E6). Until then FinTS is the only method of a bank, and "Edit Login Data..." applies to FinTS accesses."
- [ ] 1.4 Position details. Moved from task 1.5 of `add-securities-accounts`: "Deferred: needs the market (94B) and the time of the quote from the helper, and a details view."
- [ ] 1.5 Enter and edit the purchase price. Moved from task 1.11 of `add-securities-accounts`: "Deferred: needs a stored manual purchase price beside the one of the bank, the sheet, and the context menu."
- [ ] 1.6 A purchase price from the user survives a refresh. Moved from task 1.12 of `add-securities-accounts`: "Deferred, with 1.11. `Holding.identify` keeps the ID of a position across refreshes, which the manual price will hang on."
- [ ] 1.7 Comment on a position, also the scenario "Quantity changed". Moved from task 1.13 of `add-securities-accounts`: "Deferred. The stable ID of 1.12 prepares it."

## 2. FinTS connector

- [ ] 2.1 Count a holding of Baader Bank in another currency as the account currency (#226). Moved from task 1.53 of `add-fints-banking`: "Not built, and not in the spec yet. The research says that the FinTS server of Baader Bank may send a holding of a US share with its value in euros and the currency USD, and that the app should count that number in the account currency. Without that proof, the rule would show a wrong value for a holding whose value really is in dollars, so a page without a total with a holding whose only value is in USD still fails with "The bank sent no value for this securities account." Check with a real bank (#11): compare the value that Baader Bank sends for a US share with the depot view of the broker on the same day, then add the scenario under "Read the value of a securities account" and build the rule for the host `fints.baaderbank.de` only."
- [ ] 2.2 Map a CAMT entry that has a booking date with a time only. Moved from task 2.4 of `add-fints-banking`: "Deferred: hbci4java reads only the date form of `BookgDt` and `ValDt` and leaves both dates empty. The helper fails such an account with a clear message, verified by FinTSHelper self-test "account without booking date fails alone" and FinTSConnectorTests "A result that does not read fails only its account". Mapping the time form needs the helper to read the raw CAMT document that hbci4java keeps, and to match its entries to the parsed rows. Known gap until then: when only `BookgDt` has the time form and `ValDt` has a date, hbci4java copies the value date into the booking date (`ParseCamt05200108.createLine`), so the helper stores the value date as the booking date and does not fail the account."

## 3. Integration

- [ ] 3.1 Check every scenario of the spec in a release build and record the result in the pull request.

## Workflow follow-up

- Archive the change with `openspec archive defer-v0.1-follow-ups` after `add-account-setup`, `add-securities-accounts`, and `add-fints-banking`, when every task is checked.
