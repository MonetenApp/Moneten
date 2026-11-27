# Design

## Context

Each task here comes from a v0.1 change and keeps the design of that change. This file names only what the v0.1 state leaves to build.

- [add-account-setup design](../add-account-setup/design.md), "Deviations from the spec": the country menu, "Access with", and the switch of the access method are not built. In v0.1 the bank directory has only German banks, and FinTS is the only method of a bank. Extensions add services under "Other" (issue #88), so a bank can now have a second method once an extension declares the same bank.
- [add-securities-accounts design](../add-securities-accounts/design.md): `Holding.identify` keeps the ID of a position across refreshes. The manual purchase price hangs on that ID.
- [add-fints-banking design](../add-fints-banking/design.md) and [ADR 0014](../../../docs/decisions/0014-fints-through-hbci4java.md): the helper reads the answers of the bank through hbci4java.

## Decisions

- `App` owns the country menu and "Access with" in the first step of "Add Account", and the method choice in "Edit Login Data...". A switch keeps the account IDs, so the transactions, categories, and comments stay.
- `Domain` adds the manual purchase price to a position, and `Storage` keeps it in a new migration at the end of `Sources/Storage/Schema.swift`. A refresh keeps it for a position whose ID stays. The comment on a position moved to `refine-portfolio-view`.
- `Tools/FinTSHelper` sends the market (94B) and the time of a quote, which the details of a position show.
- `Tools/FinTSHelper` reads the raw CAMT document that hbci4java keeps for an entry whose booking date has a time only, and matches its entries to the parsed rows.
- The Baader Bank rule waits for the bank test of issue #11 and applies to the host `fints.baaderbank.de` only.
