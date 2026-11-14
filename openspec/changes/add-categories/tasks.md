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
- [ ] 1.8 Category currency. Build it and verify it with a test or in the app.
- [ ] 1.9 Amount in the sidebar. Built for the earlier rule, which left pending transactions out. Tasks 3.1 and 3.2 change it.
- [x] 1.10 Restrict a category to an account. Verified by CategorizerTests "Rules respect the account restriction".
- [x] 1.11 Assign a category from the context menu. Verified by "Assign Category" with a checkmark at the current category.
- [ ] 1.12 Add a category while assigning. Built in part: the menu opens the sheet but does not assign the new category. Finish it and verify it with a test or in the app.
- [ ] 1.13 Assign a category by drag and drop. Built in part: rows can be dragged onto a category. Finish it and verify it with a test or in the app.
- [ ] 1.14 Assign a category with the keyboard. Build it and verify it with a test or in the app.
- [x] 1.15 Remove a transaction from its category. Verified by "Remove Transaction from Category".
- [ ] 1.16 Category view. The list and the status line are built, verified by the debug harness snapshot in the first build. The scenarios "Pending transaction" and "Split transaction" are open. Tasks 3.1 to 3.3 build them.
- [x] 1.17 Category group view. Verified by LedgerTests filter by a category tree.
- [x] 1.18 Remove a category. Verified by confirmation, transactions become uncategorized.
- [x] 1.19 Remove a category group. Verified by subcategories are removed with the group.
- [ ] 1.20 Starter categories. Built in part: English names only. Finish it and verify it with a test or in the app.
- [x] 1.21 Category icon. Verified by the debug harness: "symbol" sets SF Symbols on four categories, and the sidebar snapshot and the settings sheet show them in the category color, and a bookmark for a category without an icon; SchemaTests checks that migration v3 keeps existing categories without an icon and stores a chosen one.

## 2. Integration

- [ ] 2.1 Check every scenario of the spec in a release build and record the result in the pull request.

## 3. Pending transactions count

- [ ] 3.1 Write the test first in LedgerTests: with today 09.11.2026, a category with a booked -80,00 €, a pending -40,00 €, and a pending -5,00 € with `needsReview` in November 2026 has the sum -120,00 € for "Current month" in `Ledger.sum(ofCategory:in:)`.
- [ ] 3.2 Count pending rows without `needsReview` in `Transaction.isInSum(of:)` in `Sources/Domain/Models.swift`, which PR #139 adds. `Ledger.sum(ofCategory:in:)` calls it, and `AppModel.sidebarAmount(of:)` uses that sum. This is the same edit as task 3.2 of the change `add-charts`, done once. The status line of the category view counts pending rows already. The task for `needsReview` in the change `add-account-refresh` leaves the marked ones out of its sum, and its number still counts them.
- [ ] 3.3 Once the change `add-split-transactions` builds splits, count the parts and not the original in `Ledger.sum(ofCategory:in:)` and in the number and the sum of the status line. Write the tests first with the scenarios "Split transaction" of "Amount in the sidebar" and "Category view".

## Workflow follow-up

- Archive the change with `openspec archive add-categories` when every task is checked.
