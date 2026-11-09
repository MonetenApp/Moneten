# Banking API providers

This page compares providers that give access to bank data through one API, as of November 2026. It informs [ADR 0007](../decisions/0007-optional-finapi-subscription.md).

| Provider | Coverage | Securities | Access for this project | Price |
|---|---|---|---|---|
| [finAPI](https://www.finapi.io/en/prices/) | Germany, Austria, Czech Republic, Slovakia, Hungary | Yes, for many brokers | Contract with a company, 30-day test system | Access fee of 60 euros per month for up to 200 private users, 300 euros for up to 1,000, then 0.30 euros per user. Plus a PSD2 license fee for account information of 200 euros per month for up to 200 users, rising to a cap of 1,000 euros. See below. |
| [Enable Banking](https://actualbudget.org/docs/advanced/bank-sync/enable-banking) | PSD2 banks in Europe | No | Free sign-up, used by Actual Budget | Terms for personal use not confirmed |
| GoCardless Bank Account Data | PSD2 banks in Europe | No | [Reportedly closed to new sign-ups](https://dev.to/johnfrandsen/gocardless-bank-account-data-alternatives-what-to-use-when-signups-are-disabled-326d) | Was free |

## finAPI details

- finAPI is registered with BaFin as an account information service and licensed for payment initiation ([about finAPI](https://www.finapi.io/en/about-finapi/about-us/)).
- The price page says "no additional PSD2 licence is required for finAPI Access for own users, as only own accounts are taken into account". That covers a company that reads its own accounts. A subscription for consumers is not own use, so the PSD2 license fees apply on top of the access fees.
- PSD2 license fees per month: account information 200 euros for up to 200 users, then 100 euros per further 100 users, capped at 1,000 euros from 901 users. Payment initiation costs the same. Both together cost 300 euros for up to 200 users, capped at 1,500 euros.
- The smallest setup for consumers therefore costs 260 euros per month before VAT. At 1,000 subscribers, access and account information cost 1,300 euros per month, or 1.30 euros per subscriber.
- Users log in to their bank through finAPI's web form. The client app never sees bank credentials.
- Data endpoints need a user access token per end user ([documentation](https://documentation.finapi.io/access/)).
- According to a [wealthAPI wiki page](https://wealthapi.atlassian.net/wiki/spaces/PD/pages/427753474), securities data is available for Consorsbank, comdirect, ING, flatex, and DAB. Some banks update only when the user approves a TAN.

## Direct PSD2 access

A client that calls banks' PSD2 interfaces directly must be a licensed third party provider with an eIDAS certificate ([Klarna requirements](https://docs.klarna.com/api/xs2a/requirements)). That is out of reach for this project. FinTS and finAPI cover the same banks without it.
