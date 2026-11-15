# Tasks

One task per requirement of the spec. A task is checked only when a test or a check in the running app shows the behavior.

## 1. Requirements

- [x] 1.1 Category tree in the sidebar. Verified by sidebar snapshot of the debug harness.
- [x] 1.2 Add a category. Verified by "Add Category" sheet.
- [x] 1.3 Add a category group. Verified by "Add Category Group" sheet.
- [ ] 1.4 Move categories by drag and drop. Build it and verify it with a test or in the app.
- [x] 1.5 Default category. Verified by LedgerTests "Uncategorized holds every transaction without a category".
- [x] 1.6 Category settings. Verified by the debug harness snapshot in the first build.
- [x] 1.7 Category color. Verified by color picker in the settings.
- [x] 1.8 Category currency. Verified by LedgerTests "Mixed currencies: the sidebar sums the category currency, and the rows of the category add up per currency", which also sets the category to USD, and by the "Currency" field in the settings sheet in the debug harness snapshot, which shows "Enter a currency code such as EUR." for a code that is not in ISO 4217.
- [ ] 1.9 Amount in the sidebar. `Ledger.sidebarAmounts(today:)` picks the period of each category and sums all of them in one pass, and the sidebar calls it once for each drawing. The scenarios "Current month", "No amount", and "Group" are verified by LedgerTests "The sidebar shows the sum of the current month, the sum of a group, and no amount when the category says so", and "Pending transaction" by LedgerTests "The sum of a category for the current month counts a pending row and leaves out a pending row marked for review". LedgerTests "Current month, current quarter, and current year in the sidebar end at the last day of the period" verifies the ends of the periods: with today 09.11.2026, a row on 01.12.2026 counts in the quarter and the year, a row on 02.08.2026 only in the year, and a row on 02.01.2027 in none. LedgerTests "Each amount in the sidebar is the sum that the list of its category gives for its period and currency" checks a ledger with a group, a USD category, and pending rows against the sums of the lists. PerformanceTests holds the map of 61 categories over 50,000 rows under 20 ms, and the perf scenario `change-sidebar-amount` draws the sidebar on the rows of the perf check. The debug harness shows it with made-up data: after `rule Fuel|"Tankstelle" OR "Café*"`, `seed`, and `review`, the view of "Fuel" has a pending -42,50 €, a booked -3,20 €, and two pending -3,20 € marked for review, and with "Display in sidebar" set to "Current month" by the harness command `sidebaramount`, the sidebar shows -45,70 €. The scenario "Split transaction" waits for task 3.3.
- [x] 1.10 Restrict a category to an account. Verified by CategorizerTests "Rules respect the account restriction".
- [x] 1.11 Assign a category from the context menu. Verified by "Assign Category" with a checkmark at the current category.
- [ ] 1.12 Add a category while assigning. Built in part: the menu opens the sheet but does not assign the new category. Finish it and verify it with a test or in the app.
- [ ] 1.13 Assign a category by drag and drop. Built in part: rows can be dragged onto a category. Finish it and verify it with a test or in the app.
- [ ] 1.14 Assign a category with the keyboard. Build it and verify it with a test or in the app.
- [x] 1.15 Remove a transaction from its category. Verified by "Remove Transaction from Category".
- [ ] 1.16 Category view. The list and the status line are built, verified by the debug harness snapshot in the first build. The scenario "Pending transaction" is verified by LedgerTests "The sum of a category for the current month counts a pending row and leaves out a pending row marked for review". The category lists 3 rows, and `MoneySums(of:)`, which the status line calls, gives -120,00 €. The debug harness shows it with made-up data: after `rule Fuel|"Tankstelle" OR "Café*"`, `seed`, and `review`, the view of "Fuel" has a pending -42,50 €, a booked -3,20 €, and two pending -3,20 € marked for review, and the status line reads "4 transactions" and -45,70 €, where it read -52,10 € before. The scenario "Split transaction" is open. Task 3.3 builds it.
- [x] 1.17 Category group view. Verified by LedgerTests filter by a category tree.
- [x] 1.18 Remove a category. Verified by confirmation, transactions become uncategorized.
- [x] 1.19 Remove a category group. Verified by subcategories are removed with the group.
- [x] 1.20 Starter categories. Verified by StarterCategoriesTests "The English set keeps its names, with Uncategorized last", "The German set has German names, with the default category last", "Both sets have the same groups, rules, and diagram settings", and "A German localization of the interface gives the German set, any other the English set". The app picks the set by the localization that it shows. The interface is English only today, so the German set appears once the interface is localized (change add-localization-and-formatting).
- [x] 1.21 Category icon. Verified by the debug harness: "symbol" sets SF Symbols on four categories, and the sidebar snapshot and the settings sheet show them in the category color, and a bookmark for a category without an icon; SchemaTests checks that migration v3 keeps existing categories without an icon and stores a chosen one.

## 2. Integration

- [ ] 2.1 Check every scenario of the spec in a release build and record the result in the pull request.

## 3. Pending transactions count

- [x] 3.1 Write the test first in LedgerTests: with today 09.11.2026, a category with a booked -80,00 €, a pending -40,00 €, and a pending -5,00 € with `needsReview` in November 2026 has the sum -120,00 € for "Current month" in `Ledger.sidebarAmounts(today:)`, which replaced `Ledger.sum(ofCategory:in:)`. Verified by LedgerTests "The sum of a category for the current month counts a pending row and leaves out a pending row marked for review". With `isInSum(of:)` set back to `!isPending && currency == currency`, it fails with -80,00 €, and with `currency == currency` alone, it fails with -125,00 €.
- [x] 3.2 Count pending rows without `needsReview` in `Transaction.isInSum(of:)` in `Sources/Domain/Models.swift`, which #139 adds. `Ledger.sidebarAmounts(today:)` calls it for the sidebar. This is the same edit as task 3.2 of the change `add-charts`, done once. The status line of the category view counts pending rows already. The task for `needsReview` in the change `add-account-refresh` leaves the marked ones out of its sum, and its number still counts them. Done by #160, which let `isInSum(of:)` call `countsInSums`. The test of task 3.1 proves it.
- [ ] 3.3 Once the change `add-split-transactions` builds splits, count the parts and not the original in `Ledger.sidebarAmounts(today:)` and in the number and the sum of the status line. Write the tests first with the scenarios "Split transaction" of "Amount in the sidebar" and "Category view".

## Workflow follow-up

- Archive the change with `openspec archive add-categories` when every task is checked.
