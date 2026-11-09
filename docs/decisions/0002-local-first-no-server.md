# 0002. Keep all data on the Mac, run no server for core features

Status: Accepted

## Context

A service that fetches account data on behalf of other people is an account information service under the German Payment Services Supervision Act (ZAG). It needs a BaFin registration or a licensed partner. A server that stores transactions is also a target for attackers and a privacy burden under the GDPR.

When the app runs on the user's Mac and the user logs in to their own bank, none of that applies. MoneyMoney and Banking4 work the same way.

## Decision

All core features run on the Mac. The app talks to banks directly through FinTS or through extensions. The project runs no server for these features and collects no telemetry.

## Consequences

- No BaFin registration is needed for the free app.
- The project has no server cost for core features.
- Sync between devices needs a channel the user controls, such as iCloud. That work starts after v0.3.
- Crash reports are opt-in and sent only when the user chooses to.
