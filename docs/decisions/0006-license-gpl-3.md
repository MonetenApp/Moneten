# 0006. License the app under GPL-3.0-or-later

Status: Accepted

## Context

The project wants every copy of the app, including forks, to stay open source. HBCI4Swift is licensed under GPL-2.0-or-later, which allows combination with GPL-3.0 code. A permissive license such as MIT would allow closed forks and is not compatible with using HBCI4Swift.

The Mac App Store adds usage rules to every app that conflict with the GPL's ban on extra restrictions. Free software projects have had GPL apps removed from Apple's stores for this reason.

## Decision

The app and all packages in this repository are licensed under GPL-3.0-or-later. The project ships outside the Mac App Store, signed with a Developer ID and notarized. Extensions talk to the app only through the extension API. Whether a script that calls a GPL program's API must itself be under the GPL depends on how close that link is, and the [FSF FAQ](https://www.gnu.org/licenses/gpl-faq.html.en#IfInterpreterIsGPL) does not settle it for this case. Until a reviewed additional permission under GPL section 7 says otherwise, extensions in the catalog must use a GPL-compatible license. The project recommends MIT.

## Consequences

- Companies cannot ship a closed version of Moneten.
- Contributions are accepted under the same license, without a contributor license agreement.
- The optional subscription service is a separate project under the AGPL. See [0007](0007-optional-finapi-subscription.md).
