# 0003. Use HBCI4Swift for FinTS

Status: Proposed

## Context

FinTS is the standard interface of German banks and the only free way to read securities accounts. A complete FinTS client needs the message syntax, dialog handling, all common TAN methods, parsers for MT940, CAMT, and MT535, and years of fixes for individual banks.

[HBCI4Swift](https://github.com/macemmi/HBCI4Swift) is a FinTS library in Swift by Frank Emminghaus, the author of the Mac banking app Pecunia. It started in 2015 and is still maintained. In 2026 it added Verification of Payee. It supports PIN/TAN, pushTAN, chipTAN flicker codes, chip cards, MT940, CAMT, MT535, and SEPA transfers. It is licensed under GPL-2.0-or-later. It ships as an Xcode framework project, not as a Swift package, and has few tests.

The alternatives are to write a FinTS client from scratch, using [python-fints](https://github.com/raphaelm/python-fints) and [hbci4java](https://github.com/hbci4j/hbci4java) as references, or to run python-fints as a helper process. Writing from scratch costs one to two months before the first bank works. A Python helper makes the app harder to ship and to sign.

## Decision

Use HBCI4Swift behind `FinTSConnector`. First, contact the author and offer to work together on a Swift package version. If the author does not want that, fork it, convert it to a Swift package, and add tests from recorded bank responses.

## What settles this decision

- A prototype that fetches balances and transactions from three German banks, including one with pushTAN, through HBCI4Swift. Tracked in the v0.1 milestone.
- The author's answer about working together.

## Consequences

- The app must be licensed under the GPL. See [0006](0006-license-gpl-3.md).
- `FinTSConnector` hides HBCI4Swift types. If the library has to be replaced later, only that module changes.
