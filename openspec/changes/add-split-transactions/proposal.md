# Proposal: Split a transaction across several categories

## Why

One supermarket receipt often covers food and household goods. One invoice holds a net amount and value added tax. A single category for the whole amount makes charts and budgets wrong. Users who come from MoneyMoney rely on split bookings.

## What Changes

- "Split Transaction" in the context menu splits a booked transaction into parts.
- Each part has its own amount, category, and comment. The parts always add up to the original amount.
- Presets split off the value added tax at a given rate.
- "Undo Split Transaction..." brings the original transaction back.
- "Split from Batch Payment" turns the row of a batch payment into its positions.

## Capabilities

### New Capabilities

- `split-transactions`: splitting a transaction into parts, the tax presets, how parts count elsewhere, and undoing a split.

### Modified Capabilities

None.

## Impact

- Milestone: v0.1
- Issues: #39
- Modules: `Domain` owns the split arithmetic and the rule that parts add up. `App` owns the split window and the menu.
- Depends on the change `add-transaction-list` for the list and on the change `add-categories` for the categories.
- Depends on the change `add-account-refresh` for the rule that a refresh does not store a known transaction twice.
- "Split from Batch Payment" needs the positions of a batch payment. The app knows them only for batches that it sent itself, which arrives with the change `add-payment-outbox`. Until then the command is always disabled.
- Decisions: none apply.

## Reference behavior

### Observed in MoneyMoney 2.5.3

- The context menu of a transaction has "Split Transaction" with "Split Amount...", one entry for each VAT rate, "Split from Batch Payment", and "Undo Split Transaction...". See [analysis](../../../docs/research/moneymoney-analysis.md#context-menus-u).
- The split window asks for the amount to split off and has a button "Next Split" (interface strings).
- Split bookings arrived in version 2.1.14. Parts with the opposite sign are allowed (version history, 2.2.1).
- Only booked transactions can be split. For a pending transaction the app asks the user to wait (interface string).
- Undoing asks whether to replace the split transactions by the original, and warns that the replaced transactions cannot be restored (interface strings).
- A batch transfer can be resolved into its positions through "Split Transaction" ([help](https://moneymoney.app/help/), version history 2.1.14).
- The labels "(net)", "(19% VAT)", and the gross amount mark the parts of a tax split (interface strings).
- The list of VAT rates is a setting with no visible control. The context menu showed two rates.

### Decided for MonetenMoneten

- The VAT rates are 19 and 7 percent at first, and the user can change the list in the settings. MoneyMoney stores the list in a hidden setting.
- Each part counts in its own category in search results, charts, budgets, reports, and exports. This comes from issue #39.
- Categorization rules do not move the parts of a split. MoneyMoney's behavior was not observed.
- After an undo, the original has the category and the comment that it had before the split.
- A part of a split cannot be deleted alone.
