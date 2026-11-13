# 0003. Use HBCI4Swift for FinTS

Status: Superseded by [ADR 0014](0014-fints-through-hbci4java.md)

## Context

FinTS is the standard interface of German banks and the only free way to read securities accounts. A complete FinTS client needs the message syntax, dialog handling, all common TAN methods, parsers for MT940, CAMT, and MT535, and years of fixes for individual banks.

[HBCI4Swift](https://github.com/macemmi/HBCI4Swift) is a FinTS library in Swift by Frank Emminghaus, the author of the Mac banking app Pecunia. It started in 2015 and is still maintained. In 2026 it added Verification of Payee. It supports PIN/TAN, pushTAN, chipTAN flicker codes, chip cards, MT940, CAMT, MT535, and SEPA transfers. Its repository holds the text of GPL version 2, and its source files carry no license notice, so it is not clear whether "or later" applies. It ships as an Xcode framework project, not as a Swift package, and has few tests.

The alternatives are to write a FinTS client from scratch, using [python-fints](https://github.com/raphaelm/python-fints) and [hbci4java](https://github.com/hbci4j/hbci4java) as references, or to run python-fints as a helper process. Writing from scratch costs one to two months before the first bank works. A Python helper makes the app harder to ship and to sign.

## Decision

Use HBCI4Swift behind `FinTSConnector`, unchanged, as a Git submodule in `Vendor/HBCI4Swift`. [ADR 0011](0011-app-target-in-an-xcode-project.md) describes how the Xcode project builds it. Send fixes and tests from recorded bank responses to the author as pull requests instead of keeping a fork. While a pull request waits, the submodule points to its commit in the fork [alexander-schneider/HBCI4Swift](https://github.com/alexander-schneider/HBCI4Swift), and the fork holds nothing but the open pull requests. After the merge, the submodule points to the upstream commit again. The first one is [macemmi/HBCI4Swift#1](https://github.com/macemmi/HBCI4Swift/pull/1): the security profile version for security function 999, which Consorsbank checks.

## What settles this decision

- A prototype that fetches balances and transactions from three German banks, including one with pushTAN, through HBCI4Swift. Tracked in the v0.1 milestone.
- The author's answer about the license version and about working together.

## Prototype status

The prototype, the submodule, and the build script were removed on 13 November 2026 (issue #107). The links point to their last version.

[App/FinTSProbe/main.swift](https://github.com/MonetenApp/Moneten/blob/b6ea16c/App/FinTSProbe/main.swift) is the prototype of issue #11. It fetches the TAN methods, the accounts, the balances, and the transactions of one bank access and prints which fields arrived. It builds against the fork commit of [macemmi/HBCI4Swift#1](https://github.com/macemmi/HBCI4Swift/pull/1), one commit on top of upstream `d7aaede`, loads the syntax files from the app bundle, and composes the first message. The bank tests wait for the product ID of the FinTS registration.

Two findings so far:

- The Xcode project of HBCI4Swift sets macOS 10.10 and 10.13, which Xcode 27 does not build. [scripts/build-hbci4swift.sh](https://github.com/MonetenApp/Moneten/blob/b6ea16c/scripts/build-hbci4swift.sh) overrides the deployment target.
- When a message fails, HBCI4Swift logs the unencrypted message at info level. With PIN/TAN, its signature segment holds the PIN. The probe drops such lines, and `FinTSConnector` must do the same.

## Consequences

- The app must be licensed under the GPL. See [0006](0006-license-gpl-3.md). If HBCI4Swift is GPL-2.0-only, a new ADR replaces 0006 with GPL-2.0-or-later.
- `FinTSConnector` hides HBCI4Swift types. If the library has to be replaced later, only that module changes.
