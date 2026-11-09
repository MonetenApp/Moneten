# 0007. Offer finAPI as an optional subscription

Status: Proposed

## Context

Some banks have no FinTS access, and some users do not want to set up FinTS. Commercial providers solve that. [finAPI](https://www.finapi.io/en/prices/) is a German provider registered with BaFin as an account information service and licensed for payment initiation. It sells only to companies. For a consumer subscription, its public price list adds a PSD2 license fee to the access fee. The smallest setup costs 260 euros per month before VAT, and about 1.30 euros per subscriber at 1,000 subscribers. [Banking API providers](../research/banking-apis.md) has the details.

MoneyMoney runs its own PSD2 online service as a paid add-on for 39.99 euros per year ([MoneyMoney features](../research/moneymoney-features.md#prices)). That is the price users will compare against.

GoCardless Bank Account Data, formerly Nordigen, used to be free, but a [developer report](https://dev.to/johnfrandsen/gocardless-bank-account-data-alternatives-what-to-use-when-signups-are-disabled-326d) says it no longer accepts new sign-ups. Enable Banking offers free sign-up, but it covers only PSD2 accounts and no securities.

## Decision

The app gets a `FinAPIConnector` in v0.3. A user who subscribes logs in to their banks through finAPI's web form, so the app never sees those bank credentials. A small server in a separate repository holds the finAPI client secret, manages subscriptions through Stripe, creates one finAPI user per subscriber, and gives the app short-lived access tokens. The server passes data through and stores no transactions. It is licensed under the AGPL.

The subscription is never required for a core feature.

## What settles this decision

- finAPI confirms in writing that this use falls under its license and that no own BaFin registration is needed.
- Final prices from finAPI, including payment initiation.
- The privacy policy explains what finAPI stores, for how long, and how a subscriber deletes it.
- Which company operates the service, with terms, a privacy policy, and a data processing agreement with finAPI.

## Consequences

- Users at banks without FinTS get a supported path.
- The project gets income that does not depend on donations.
- The free FinTS connector competes with the subscription. That is intended.
