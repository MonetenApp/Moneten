# Tasks

One task per requirement of the spec. A task is checked only when a test or a check in the running app shows the behavior.

## 1. Requirements

- [x] 1.1 Category tree in the sidebar. Verified by sidebar snapshot of the debug harness.
- [x] 1.2 Add a category. Verified by "Add Category" sheet.
- [x] 1.3 Add a category group. Verified by "Add Category Group" sheet.
- [ ] 1.4 Move categories by drag and drop. Built; the drag gesture is not yet observed. CategoryMoveTests check `Ledger.move(category:into:at:)`: Fuel moves into Mobility with its 20 transactions, Groceries moves above Leisure, a group does not move into its own tree, "Uncategorized" does not move and stays last, and positions stay without gaps. In the debug harness on made-up data, "movecategory" sends a `DraggedCategory` through an item provider and calls the model function of the drop: Fuel moved into the open view of Mobility, which showed its 20 rows in a new table, Groceries moved above Leisure, and both stayed after a restart. The empty category "Empty" moved into the open view of Mobility without a new table. ShownRowsTests check the same two moves in `Ledger.changesShownRows`. "dropcategory" checks a drop on a group row as the row checks it: Leisure went to the end of Mobility, and the row refused Mobility on itself, Mobility on Leisure inside it, Leisure on Mobility where it was already last, and Transfers on Groceries, which is not a group. The harness cannot drag, so the drag gesture and the highlight in the sidebar are not seen.
- [x] 1.5 Default category. Verified by LedgerTests "Uncategorized holds every transaction without a category".
- [x] 1.6 Category settings. Verified by the debug harness snapshot in the first build.
- [x] 1.7 Category color. Verified by color picker in the settings.
- [x] 1.8 Category currency. Verified by LedgerTests "Mixed currencies: the sidebar sums the category currency, and the rows of the category add up per currency", which also sets the category to USD, and by the "Currency" field in the settings sheet in the debug harness snapshot, which shows "Enter a currency code such as EUR." for a code that is not in ISO 4217.
- [ ] 1.9 Amount in the sidebar. Built for the earlier rule, which left pending transactions out. Tasks 3.1 and 3.2 change it.
- [x] 1.10 Restrict a category to an account. Verified by CategorizerTests "Rules respect the account restriction".
- [x] 1.11 Assign a category from the context menu. Verified by "Assign Category" with a checkmark at the current category.
- [x] 1.12 Add a category while assigning. Verified by the debug harness on 40 made-up rows: with 2 rows selected, "sheet newCategory" opened the real "Add Category" sheet as a click on "Add category" in "Assign Category" does, and "Pets" typed into its name field and Return on OK made the top-level category "Pets" with the 2 rows. The trail logged "sheet newCategory", "sheet none", and "ledger commit rows=2".
- [ ] 1.13 Assign a category by drag and drop. Built; the drag gesture is not yet observed. CategoryAssignmentTests check `Ledger.canAssign(_:to:)` with the restriction. In the debug harness on made-up data, "droprows" sends a `DraggedTransactions` through an item provider and calls the model function of the drop: 3 selected rows went into "Groceries", and the group "Mobility" refused 20 rows while the pointer check and the drop both said no. After each drop the rows of that drag no longer lit up a category. 2 rows dropped out of the open view of "Groceries" on "Transfers" came with a new table, and a drop in an account view did not. ShownRowsTests check `Ledger.changesShownRows`, which decides this for a drop and for a move. The harness cannot drag and has no command to restrict a category, so the highlight in the sidebar and the scenario "Restricted target" are not seen in the app.
- [ ] 1.14 Assign a category with the keyboard. Built; the ⌘K menu path is not yet observed. CategoryAssignmentTests check the search and the restriction. In the debug harness, the picker that the stand-in of the menu command opens assigns with Return, closes with Escape, and moves and scrolls the highlight with the arrow keys. The screen was locked during each run, and SwiftUI disables menu commands without a key window, so ⌘K reached "Assign Category..." disabled.
- [x] 1.15 Remove a transaction from its category. Verified by "Remove Transaction from Category".
- [ ] 1.16 Category view. The list and the status line are built, verified by the debug harness snapshot in the first build. The scenarios "Pending transaction" and "Split transaction" are open. Tasks 3.1 to 3.3 build them.
- [x] 1.17 Category group view. Verified by LedgerTests filter by a category tree.
- [x] 1.18 Remove a category. Verified by confirmation, transactions become uncategorized.
- [x] 1.19 Remove a category group. Verified by subcategories are removed with the group.
- [x] 1.20 Starter categories. Verified by StarterCategoriesTests "The English set keeps its names, with Uncategorized last", "The German set has German names, with the default category last", "Both sets have the same groups, rules, and diagram settings", and "A German localization of the interface gives the German set, any other the English set". The app picks the set by the localization that it shows. The interface is English only today, so the German set appears once the interface is localized (change add-localization-and-formatting).
- [x] 1.21 Category icon. Verified by the debug harness: "symbol" sets SF Symbols on four categories, and the sidebar snapshot and the settings sheet show them in the category color, and a bookmark for a category without an icon; SchemaTests checks that migration v3 keeps existing categories without an icon and stores a chosen one.

## 2. Integration

- [ ] 2.1 Check every scenario of the spec in a release build and record the result in the pull request.

## 3. Pending transactions count

- [ ] 3.1 Write the test first in LedgerTests: with today 09.11.2026, a category with a booked -80,00 €, a pending -40,00 €, and a pending -5,00 € with `needsReview` in November 2026 has the sum -120,00 € for "Current month" in `Ledger.sum(ofCategory:in:)`.
- [ ] 3.2 Count pending rows without `needsReview` in `Transaction.isInSum(of:)` in `Sources/Domain/Models.swift`, which #139 adds. `Ledger.sum(ofCategory:in:)` calls it, and `AppModel.sidebarAmount(of:)` uses that sum. This is the same edit as task 3.2 of the change `add-charts`, done once. The status line of the category view counts pending rows already. The task for `needsReview` in the change `add-account-refresh` leaves the marked ones out of its sum, and its number still counts them.
- [ ] 3.3 Once the change `add-split-transactions` builds splits, count the parts and not the original in `Ledger.sum(ofCategory:in:)` and in the number and the sum of the status line. Write the tests first with the scenarios "Split transaction" of "Amount in the sidebar" and "Category view".

## Workflow follow-up

- Archive the change with `openspec archive add-categories` when every task is checked.
