# 0006. License the app under GPL-3.0-or-later

Status: Accepted

## Context

The project wants every copy of the app, including forks, to stay open source. HBCI4Swift is licensed under GPL-2.0-or-later, which allows combination with GPL-3.0 code. A permissive license such as MIT would allow closed forks and is not compatible with using HBCI4Swift.

The Mac App Store adds usage rules to every app that conflict with the GPL's ban on extra restrictions. Free software projects have had GPL apps removed from Apple's stores for this reason.

## Decision

The app and all packages in this repository are licensed under GPL-3.0-or-later. The project ships outside the Mac App Store, signed with a Developer ID and notarized. Extensions are separate works, and their authors pick their own license. The project recommends MIT for extensions in the catalog.

## Consequences

- Companies cannot ship a closed version of MonetenMoneten.
- Contributions are accepted under the same license, without a contributor license agreement.
- The optional subscription service is a separate project under the AGPL. See [0007](0007-optional-finapi-subscription.md).
