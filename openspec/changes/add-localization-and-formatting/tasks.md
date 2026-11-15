# Tasks

One task per requirement of the spec, and the tasks of the design before them. A task is checked only when a test or a check in the running app shows the behavior.

## 1. Catalog and check

- [ ] 1.1 Add `App/Resources/Localizable.xcstrings` to the app target with English as the development language and German, and let the build of the app extract the keys of its literals (`SWIFT_EMIT_LOC_STRINGS`).
- [ ] 1.2 Add `scripts/check-localization.py`. It reads the `.stringsdata` files of a build and the catalog, and it fails for a key without an entry, a key without a German value, and an entry that no code uses. `--update` adds and removes entries. Run it in `scripts/check.sh` after the build for Periphery, and describe in `CONTRIBUTING.md` how a new text gets its German value.
- [ ] 1.3 Turn every text that the app writes itself into a literal that is looked up: `String(localized:)` for a `String` built in code, in an alert, in a notification, and in a message of a library, and `Text(verbatim:)` for a value from the database, a bank, or an extension.
- [ ] 1.4 Write the German value of every entry with the terms of a MoneyMoney user, and give each text with a count the plural variations "one" and "other".

## 2. Requirements

- [ ] 2.1 German and English interface. Verify it with the check of task 1.2 and with screenshots of the main window, the settings, and the "Add Account" assistant in German, light and dark.
- [ ] 2.2 Follow the language of macOS. Verify a German system, an English system, and a French system with German as the second language.
- [ ] 2.3 Language setting. Add the "Language" menu to the "General" tab with the note that the change applies after a restart, and verify a switch from German to English.
- [ ] 2.4 Text from a bank stays as received. Verify that the English interface shows the booking text and the purpose of a German transaction unchanged.
- [ ] 2.5 Dates follow macOS and show four-digit years. Verify the regions Germany and United States.
- [ ] 2.6 Relative day names. "Today" and "Yesterday" exist for the last refresh. Add "Tomorrow" and the numbers of days, and verify them with tests.
- [ ] 2.7 Complete a typed day. Write the tests of the scenarios first, with today as a parameter, then the completion function in `Domain` of the design.
- [ ] 2.8 Complete a typed day and month. Tests first, as in task 2.7.
- [ ] 2.9 Complete a typed day in a field that expects a future date. Tests first. Confirm the list of these fields first, as the design asks.
- [ ] 2.10 Complete a typed day and month in a field that expects a future date. Tests first, as in task 2.9.
- [ ] 2.11 Reject an impossible date. Tests first for the four scenarios, then the date field of the app that marks the field and keeps it in editing.
- [ ] 2.12 Pick a date from a calendar. Add the calendar to the date field of task 2.11.
- [ ] 2.13 Amounts follow the number format of macOS. Verify the region Germany with "1.234,56 €" and "100,00 €".
- [ ] 2.14 Every amount shows its currency. Verify Swiss francs and a group with two currencies.
- [ ] 2.15 Negative amounts are marked. Verify the minus sign and the color in the list.
- [ ] 2.16 Amounts are aligned in lists. Verify a column with "-5,50 €" and "1.250,00 €".
- [ ] 2.17 Amount entry follows macOS. Write the tests for "1.234,5" and "12,3,4" first.
- [ ] 2.18 IBANs in groups of four. Verify the display and that a copied IBAN has no spaces.
- [ ] 2.19 Singular and plural. Verify "1 Transaction" and "3 Transactions" in English and German.
- [ ] 2.20 Light and dark appearance. Verify a switch of macOS while the app runs.
- [ ] 2.21 Booking dates do not move with the time zone. Verify with a test that a `Day` gives the same date in the time zones of Berlin and Auckland.

## 3. Starter categories

- [ ] 3.1 The German starter categories of the change `add-categories` (task 1.20) appear in a database that the app creates with a German interface. Verify it in the debug harness.

## 4. Integration

- [ ] 4.1 Check every scenario of the spec in a release build and record the result in the pull request.

## Workflow follow-up

- Archive the change with `openspec archive add-localization-and-formatting` when every task is checked.
