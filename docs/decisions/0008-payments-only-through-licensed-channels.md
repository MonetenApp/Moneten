# 0008. Send payments only through FinTS or finAPI

Status: Accepted

## Context

A payment sent by an extension that drives a bank's website could go wrong in ways nobody notices, for example through a changed form, a wrong field, or a double submit. A malicious extension could change the payee. Banking4 also limits its screen scrapers to reading data.

## Decision

Only `FinTSConnector` and `FinAPIConnector` can send payments. The extension API offers no payment functions. In code, only those two types conform to `PaymentConnector`.

This rule covers what the app does. It cannot stop a malicious extension from submitting a payment form on a bank website it is allowed to reach. Catalog review, the host list in the manifest, and a warning before installing an extension from outside the catalog limit that risk. Where a service offers read-only credentials, such as API keys without trading rights, extensions should ask for those.

Every payment shows the bank's Verification of Payee result before the user confirms it. The app never resends a payment on its own.

## Consequences

- Services that only extensions reach, such as some brokers, are read-only in MonetenMoneten.
- Existing MoneyMoney extensions with payment functions still work for reading.
