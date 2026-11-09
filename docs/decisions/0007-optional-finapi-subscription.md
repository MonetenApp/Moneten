# 0007. Offer finAPI as an optional subscription

Status: Accepted

## Context

Some banks have no FinTS access, and some users do not want to set up FinTS. Commercial providers solve that. [finAPI](https://www.finapi.io/en/prices/) is a German provider registered with BaFin as an account information service and licensed for payment initiation. Its public price list starts at 60 euros per month for up to 200 private users, and 100 euros per month when business accounts are included. It sells only to companies.

GoCardless Bank Account Data, formerly Nordigen, used to be free, but a [developer report](https://dev.to/johnfrandsen/gocardless-bank-account-data-alternatives-what-to-use-when-signups-are-disabled-326d) says it no longer accepts new sign-ups. Enable Banking offers free sign-up, but it covers only PSD2 accounts and no securities.

## Decision

The app gets a `FinAPIConnector` in v0.3. A user who subscribes logs in to their banks through finAPI's web form, so the app never sees those bank credentials. A small server in a separate repository holds the finAPI client secret, manages subscriptions through Stripe, creates one finAPI user per subscriber, and gives the app short-lived access tokens. The server passes data through and stores no transactions. It is licensed under the AGPL.

The subscription is never required for a core feature.

## Open questions

- finAPI confirms in writing that this use falls under its license and that no own BaFin registration is needed.
- Final prices from finAPI, including payment initiation.
- Which company operates the service, with terms, a privacy policy, and a data processing agreement with finAPI.

## Consequences

- Users at banks without FinTS get a supported path.
- The project gets income that does not depend on donations.
- The free FinTS connector competes with the subscription. That is intended.
