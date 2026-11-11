# Proposal: Sort transactions into a tree of categories

## Why

A list of transactions shows what happened. Categories show where the money goes. They are the base for rules, budgets, charts, and reports, so they come first.

## What Changes

- The sidebar gets a section "Categories" with categories and category groups in a tree.
- The default category "Uncategorized" holds every transaction without a category.
- The user assigns categories from the context menu, by drag and drop, and with the keyboard, for one or for many transactions.
- Each category has settings for its name, currency, color, the amount in the sidebar, and a restriction to one account.
- A category view lists the transactions of the category across all accounts.
- A first launch creates a starter set of categories.

## Capabilities

### New Capabilities

- `categories`: the category tree, the default category, the category settings, manual assignment, and the category view.

### Modified Capabilities

None.

## Impact

- Milestone: v0.1
- Issues: #18
- Modules: `Domain` owns the category tree and the assignment rules. `Storage` owns the sums. `App` owns the sidebar section, the settings popover, and the assignment commands.
- Depends on the change `add-main-window` for the sidebar and on the change `add-transaction-list` for the list.
- The changes `add-categorization-rules`, `add-budgets`, and `add-charts` add the rule field, the budget fields, and the effect of "Show in diagrams" to the same settings popover.
- [Data model](../../../docs/data-model.md) says that the transactions of a deleted category move to the parent. This change moves them to "Uncategorized". The data model page needs that correction.
- Decisions: none apply.

## Reference behavior

### Observed in MoneyMoney 2.5.3

- The sidebar section "Categories" holds categories and category groups, and "Uncategorized" is the last entry. See [analysis](../../../docs/research/moneymoney-analysis.md#main-window-u).
- The add menu and the Account menu offer "Add Category" and "Add Category Group". See [analysis](../../../docs/research/moneymoney-analysis.md#menus-and-keyboard-shortcuts-u).
- The settings popover of a category has "Name", "Currency", a color control, "Show in diagrams", "Display in sidebar" with five values, and "Restrict to". See [analysis](../../../docs/research/moneymoney-analysis.md#category-u-w).
- "Assign Category" in the context menu lists all categories, marks the current one, and ends with "Add category". See [analysis](../../../docs/research/moneymoney-analysis.md#context-menus-u).
- A category that is restricted to another account is greyed out in that menu (version history, 2.2.9).
- Transactions can be dragged onto a category (version history, 2.1.13).
- In a category view the context menu has "Remove Transaction from Category". Assigning "Uncategorized" has the same effect ([categorization page](https://moneymoney.app/categorization/)).
- The default category was renamed to "Uncategorized", and its name can be changed in its settings (version history, 2.4.30). Its remove command is disabled.
- Removing a category keeps its transactions. Removing a category group also removes its subcategories and says so (interface strings).
- The sidebar can show an amount next to a category, for example the sum of the current month or the total (version history, 2.2.10).
- The status line of a category view shows one sum for each currency.

### Decided for MonetenMoneten

- Category icons are SF Symbols. MoneyMoney offers its own pictures, which belong to its maker; the migration takes only their color.
- The transactions of a removed category go to "Uncategorized". MoneyMoney says only that they are kept.
- Assignment with the keyboard through a picker with the shortcut ⌘K comes from issue #18. MoneyMoney has no such picker.
- The starter set of categories comes from issue #18. Whether MoneyMoney ships one was not observed.
- The currency of a category is the currency of its sidebar amount and of its budget. Transactions in other currencies stay in the category and are summed separately. The exact meaning of the "Currency" field in MoneyMoney was not observed.
- The app refuses two categories with the same name under the same parent, so that a category path stays unique.
- Issue #18 also asks for hiding a category. MoneyMoney has no hidden categories, and this change does not specify them.
