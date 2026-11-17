# 0020. Keep GPL-3.0-or-later after the move to hbci4java

Status: Accepted

This decision replaces [ADR 0006](0006-license-gpl-3.md). The license stays the same. The context of ADR 0006 named HBCI4Swift as a reason for the GPL, and [ADR 0014](0014-fints-through-hbci4java.md) replaced HBCI4Swift with hbci4java.

## Context

The project wants every copy of the app, including forks, to stay open source. A permissive license such as MIT would allow closed forks.

These parts ship with Moneten under their own licenses, and each of those licenses allows that. The table is a summary:

| Part | License |
|---|---|
| [hbci4java](https://github.com/hbci4j/hbci4java), in the FinTS helper | LGPL-2.1-or-later |
| The JAXB jars of `Tools/FinTSProbeJava/dependencies.lock`, in the FinTS helper | Eclipse Distribution License 1.0 |
| The Java runtime of the FinTS helper, from the Temurin JDK | GPL-2.0-only with the Classpath Exception (and the OpenJDK Assembly Exception) |
| [GRDB](https://github.com/sqlcipher/GRDB.swift) with SQLCipher | MIT, BSD-style |
| Lua 5.4 in `Sources/CLua` | MIT |
| [Sparkle](https://github.com/sparkle-project/Sparkle), for updates | MIT, with parts under BSD-2-Clause (bsdiff) and the zlib license (ed25519) |
| The Public Suffix List in `Sources/ExtensionHost/PublicSuffix` | MPL-2.0 |

The Java runtime keeps its own license. GPL-2.0-only code cannot become part of a GPL-3.0 work, so the runtime runs only in the FinTS helper, a separate process that talks JSON lines over a pipe. The helper links the jars, which LGPL-2.1 allows. The runtime that jlink builds carries the notices of its own third-party parts, such as zlib, FreeType, HarfBuzz, libpng, Little CMS, and the Unicode data, in its `legal` folder.

The Mac App Store adds usage rules to every app that conflict with the GPL's ban on extra restrictions. Free software projects have had GPL apps removed from Apple's stores for this reason.

## Decision

The app and all packages in this repository are licensed under GPL-3.0-or-later. The project ships outside the Mac App Store, signed with a Developer ID and notarized. Extensions talk to the app only through the extension API. Whether a script that calls a GPL program's API must itself be under the GPL depends on how close that link is, and the [FSF FAQ](https://www.gnu.org/licenses/gpl-faq.html.en#IfInterpreterIsGPL) does not settle it for this case. Until a reviewed additional permission under GPL section 7 says otherwise, extensions in the catalog must use a GPL-compatible license. The project recommends MIT.

## Consequences

- Companies cannot ship a closed version of Moneten.
- Contributions are accepted under the same license, without a contributor license agreement.
- A new dependency must have a license that allows it to ship with Moneten. A pull request that adds one names its license.
- A release carries the license texts and copyright notices of these parts and says where their source is.
- The optional subscription service is a separate project under the AGPL. See [0007](0007-optional-finapi-subscription.md).
