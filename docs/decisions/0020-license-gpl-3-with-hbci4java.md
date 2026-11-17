# 0020. License the app under GPL-3.0-or-later, with hbci4java

Status: Accepted

This decision replaces [ADR 0006](0006-license-gpl-3.md). The license stays the same. The context of ADR 0006 named HBCI4Swift as a reason for the GPL, and [ADR 0014](0014-fints-through-hbci4java.md) replaced HBCI4Swift with hbci4java.

## Context

The project wants every copy of the app, including forks, to stay open source. A permissive license such as MIT would allow closed forks.

The code that ships in a release has these licenses. Each of them can be combined with GPL-3.0:

| Part | License |
|---|---|
| [hbci4java](https://github.com/hbci4j/hbci4java) and the JAXB jars of `Tools/FinTSProbeJava/dependencies.lock`, in the FinTS helper | LGPL-2.1-or-later, Eclipse Distribution License 1.0 |
| The Java runtime of the FinTS helper, from the Temurin JDK | GPL-2.0 with the Classpath Exception |
| [GRDB](https://github.com/sqlcipher/GRDB.swift) with SQLCipher | MIT, BSD-style |
| Lua 5.4 in `Sources/CLua` | MIT |
| [Sparkle](https://github.com/sparkle-project/Sparkle), for updates | MIT |
| The Public Suffix List in `Sources/ExtensionHost/PublicSuffix` | MPL-2.0 |

The FinTS helper is a separate process that talks JSON lines over a pipe, so the Java runtime and the jars are not linked into the app.

The Mac App Store adds usage rules to every app that conflict with the GPL's ban on extra restrictions. Free software projects have had GPL apps removed from Apple's stores for this reason.

## Decision

The app and all packages in this repository are licensed under GPL-3.0-or-later. The project ships outside the Mac App Store, signed with a Developer ID and notarized. Extensions talk to the app only through the extension API. Whether a script that calls a GPL program's API must itself be under the GPL depends on how close that link is, and the [FSF FAQ](https://www.gnu.org/licenses/gpl-faq.html.en#IfInterpreterIsGPL) does not settle it for this case. Until a reviewed additional permission under GPL section 7 says otherwise, extensions in the catalog must use a GPL-compatible license. The project recommends MIT.

## Consequences

- Companies cannot ship a closed version of Moneten.
- Contributions are accepted under the same license, without a contributor license agreement.
- A new dependency must have a license that can be combined with GPL-3.0. A pull request that adds one names its license.
- The optional subscription service is a separate project under the AGPL. See [0007](0007-optional-finapi-subscription.md).
