# Proposal: Set budgets for categories

## Why

Categories show where money went. A budget shows whether that was within plan while there is still time to react. "Are my expenses still within budget?" is one of the questions that MoneyMoney promises to answer at a glance.

## What Changes

- A category or a category group can have a budget with an amount and a period.
- The period is a month, a quarter, a year, or the whole time.
- The category view shows how much of the budget is used and how much is available, and it shows when the budget is overspent.
- The sidebar can show the available budget next to the category.
- The bar chart of a category shows the budget next to the bars.

## Capabilities

### New Capabilities

- `budgets`: budgets for categories and category groups, how the app computes the used and the available amount, and where it shows them.

### Modified Capabilities

None.

## Impact

- Milestone: later
- Issues: none yet
- Modules: `Domain` owns the budget arithmetic. `App` owns the budget fields in the category settings and the display.
- Depends on the change `add-categories` for the category settings and the sidebar amount.
- Depends on the change `add-charts` for the category bar chart.
- Depends on the change `add-split-transactions` for the rule that parts count in their own category.
- Decisions: none apply.

## Reference behavior

### Observed in MoneyMoney 2.5.3

- Budgets can be set for single categories and for category groups ([feature page](https://moneymoney.app/)).
- The category settings hold a budget amount with a currency and a period menu with "per month", "per quarter", "per year", and "in total". See [analysis](../../../docs/research/moneymoney-analysis.md#category-u-w).
- Budgets arrived in version 2.2.10 with a display of the available and the used budget. The budget for the whole time arrived in 2.2.12.
- The sidebar can show the available budget next to the category name (version history, 2.2.10).
- The remaining budget stays visible when the budget is overspent (version history, 2.2.11).
- The interface has the labels "Available budget", "Overspent", and "(no budget set)".

### Decided for Moneten

- Withdrawals use the budget and deposits in the same category give it back. How MoneyMoney nets the two was not observed.
- A period is a calendar month, quarter, or year. Unused budget does not carry over to the next period.
- A budget on a category group counts everything below the group. A budget on a category inside that group counts in both.
- The bar chart scales a budget to the chart view. A monthly budget counts three times in the quarterly view and twelve times in the yearly view. A yearly budget is not drawn in the monthly view.
- A budget on a category with mainly deposits is a target for income. The app then shows how much is still expected.
- The budget amount must be above zero.
- A budget counts only transactions in the currency of the category. The app does not convert currencies.
