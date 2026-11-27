# Proposal: Finish the parts of v0.1 that were deferred

## Why

By the owner's decision of 19 November 2026, v0.1 is complete when the bank tests of issue #11, the walk-through of a Release build, and the publish of v0.1.0 (issue #25) are done. Some tasks of the v0.1 changes said that they were deferred or not needed for v0.1, and no later change owned them. This change holds them, so that the v0.1 changes can be archived and the work is not lost.

## What Changes

- The country menu of "Add Account", the choice of the access method under "Access with", and the switch of the access method in "Edit Login Data...", from `add-account-setup`.
- The details of a position, and the purchase price that the user enters and that survives a refresh, from `add-securities-accounts`. The comment on a position moved on to the change `refine-portfolio-view` on 27 November 2026.
- The value of a Baader Bank holding in another currency, and CAMT entries whose booking date has a time only, from `add-fints-banking`.

The requirements move unchanged. The requirement "Comment on a position", with the scenario "Quantity changed" of "A refresh replaces the positions", was here until 27 November 2026 and moved to the change `refine-portfolio-view`, which builds comments for v0.1 and holds the scenario in "A comment survives a refresh". The other deferred tasks of v0.1 moved into the later changes that own their feature: `add-sepa-transfers`, `add-payment-outbox`, and `add-bank-statements`.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `account-setup`: adds the country menu, the choice of the access method, and the switch of the access method. The change `add-account-setup` introduces the capability.
- `securities-accounts`: adds the details of a position and the purchase price from the user. The change `add-securities-accounts` introduces the capability.

## Impact

- Milestone: v0.2
- Issues: #226 for the Baader Bank holding. The other tasks have no issue yet.
- Modules: `App` owns the country menu, "Access with", the details view, and the sheets. `Domain` owns the manual purchase price of a `Holding`, and `Storage` keeps it. `FinTS` and `Tools/FinTSHelper` own the market and the time of a quote, the Baader Bank rule, and the CAMT dates.
- Depends on the changes `add-account-setup`, `add-securities-accounts`, and `add-fints-banking`, whose designs describe the v0.1 state that this change builds on, and on `add-web-banking-extensions` for a second access method of one bank.
- Decisions: [ADR 0014](../../../docs/decisions/0014-fints-through-hbci4java.md).

## Reference behavior

### Observed in MoneyMoney 2.5.3

- The proposals of `add-account-setup` and `add-securities-accounts` list what was observed for each requirement that moves here: the country menu, "Access with", the detail fields of a position and "Edit Purchase Price...".

### Decided for Moneten

- The decisions of the source proposals apply unchanged.
- A Baader Bank holding counts its value in the account currency only after a bank test shows that Baader Bank sends a value in euros with the currency USD, and only for the host `fints.baaderbank.de`.
