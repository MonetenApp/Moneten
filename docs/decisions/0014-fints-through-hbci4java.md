# 0014. Use hbci4java for FinTS, in a helper process

Status: Accepted

This decision replaces [ADR 0003](0003-fints-through-hbci4swift.md).

## Context

ADR 0003 chose HBCI4Swift. The first bank test on 11 November 2026 ([bank-access.md](../research/bank-access.md)) showed what that means:

- HBCI4Swift has one author and two commits in the last twelve months. Consorsbank rejected its first message with 9010, because it sent the security profile `PIN:2` in HNVSK and `PIN:1` in HNSHK. Hibiscus fixed the same error in 2019. The fix went upstream as [macemmi/HBCI4Swift#1](https://github.com/macemmi/HBCI4Swift/pull/1), and until then the project builds from a fork.
- HBCI4Swift drops a transaction order without an error when the account information has no BIC. It does not fetch depot holdings in the probe, and it does not set the currency on MT940 rows.

Every FinTS client has to absorb the quirks of individual banks. The libraries differ in how many users have already found those quirks. On 11 November 2026 the open source FinTS libraries had this activity on GitHub:

| Library | Language | Commits / authors in 12 months | Used by | License |
|---|---|---|---|---|
| [hbci4java](https://github.com/hbci4j/hbci4java) | Java | 81 / 6 | Hibiscus, since about 2005 | LGPL-2.1-or-later |
| [AqBanking](https://github.com/aqbanking/aqbanking) | C | 100 or more / 5 | GnuCash, KMyMoney | GPL-2.0, "or later" not checked |
| [phpFinTS](https://github.com/nemiah/phpFinTS) | PHP | 100 or more / 13 | server tools | MIT |
| [python-fints](https://github.com/raphaelm/python-fints) | Python | 17 / 7 | pretix and others | LGPL-3.0 |
| [libfintx](https://github.com/libfintx/libfintx) | C# | 44 / 7 | few | LGPL-3.0 |
| [fints-rs](https://github.com/floffel/fints-rs) | Rust | 19 / 5 | young | MIT |
| [HBCI4Swift](https://github.com/macemmi/HBCI4Swift) | Swift | 2 / 1 | Pecunia | GPL-2.0 |

hbci4java has the longest record with German banks. Its code carries notes on the quirks of DKB, Postbank, Commerzbank, Baader Bank, and others, it supports the decoupled app approval and Verification of Payee, and it ships a bank directory with the BIC of every bank code.

The same test ran with hbci4j-core 4.1.17 through `Tools/FinTSProbeJava`. Without changes to the library, the login, the decoupled method, and 24 depot positions with ISIN, WKN, name, price, quantity, and value worked, and every BIC came from the bank directory. Balance and transactions failed with 9075, because Consorsbank marks HKSAL and HKKAZ as "no TAN" in the bank parameters but rejects them without HKTAN. With these two marked "TAN required", balance and transactions arrived. The report is [hbci4j/hbci4java#155](https://github.com/hbci4j/hbci4java/issues/155).

## Decision

- FinTS goes through hbci4java, in a pinned version from Maven Central. `Tools/FinTSProbeJava/dependencies.lock` lists every jar with its SHA-256. The build checks it and needs no Maven.
- hbci4java runs in a helper process inside the app bundle, with a runtime made by `jlink`. On 11 November 2026 the runtime was 40 MB and the jars 6 MB, about 30 MB more in the compressed download. The user installs nothing.
- The app and the helper talk over a pipe with one JSON message per line. The PIN and the TANs go only through this pipe, never through arguments, environment variables, files, or logs. The helper masks PINs, TANs, and message segments in its log, as the probe does.
- The helper keeps no data of its own. The app keeps the passport data of hbci4java (bank parameters, user parameters, system ID) in the encrypted database. For one session the helper writes it to a temporary file with access for the user only, encrypted with a random passphrase, and deletes the file at the end.
- The helper and its runtime are signed with the Developer ID of the app. Only the helper gets the entitlement `com.apple.security.cs.allow-jit`.
- `FinTSConnector` hides the helper behind the interface of issue #6. Another engine can replace it without changes to the rest of the app.
- Fixes for bank quirks go to hbci4java as issues or pull requests. Until a fix is released, the helper applies it itself, and [bank-access.md](../research/bank-access.md) lists each one with its bank and its upstream report.

## Consequences

- The question about "GPL-2.0 or later" to the HBCI4Swift author no longer blocks the project. hbci4java is LGPL-2.1-or-later and can be combined with GPL-3 ([ADR 0006](0006-license-gpl-3.md)).
- Contributors need a JDK 17 or later besides Xcode. CI installs one.
- The repository holds Java code for the helper. The rest of the app stays Swift.
- The helper starts in about two seconds. A sync takes several seconds anyway.
- The runtime contains `java.desktop` and `java.smartcardio`, because hbci4java uses them. A GraalVM native image could make the helper smaller and faster to start. It needs configuration for the classes and syntax files that hbci4java loads by name, so it is a later option, not part of this decision.
- The HBCI4Swift submodule, `scripts/build-hbci4swift.sh`, and `App/FinTSProbe` stay until the connector of issue #13 runs on hbci4java. Then they are removed.

## Alternatives

- **HBCI4Swift with a fork.** Native, but the project would carry the fixes of a library with one maintainer.
- **AqBanking.** Native C and many users, but a long chain of dependencies on macOS, and the license version is not checked.
- **A Swift port of phpFinTS.** Native and allowed by the MIT license, but the project would maintain its own FinTS core.
- **fints-rs through UniFFI.** Native without a runtime, but young, and it has the same open 9010 problem.
- **Only aggregators such as finAPI or Enable Banking.** They test the banks, but the data passes through a provider. They stay an addition for banks that FinTS cannot reach.
