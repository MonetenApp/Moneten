# Proposal: Connect banks through an optional aggregator subscription

## Why

Some banks offer no FinTS access, and some users do not want to set FinTS up. PSD2 interfaces of banks are open only to licensed services, not to an app on a Mac. A licensed aggregator closes that gap. MoneyMoney sells its own PSD2 online service for this purpose. Moneten offers finAPI through an optional subscription that also gives the project an income.

## What Changes

- A settings tab "Subscription" explains the service and shows its state.
- The user signs in to the subscription service from the app. Payment happens on the website of the service.
- Before the first bank is connected, the user gives explicit consent to the data flow.
- The user logs in to a bank in the web form of the aggregator. The app never receives the bank login data.
- Accounts from the aggregator deliver balances, transactions, and securities like every other account.
- The aggregator is read-only in this change.
- The user can stop using the service and delete the customer account. Data on the Mac stays.
- Every other feature works without a subscription.

## Capabilities

### New Capabilities

- `aggregator-subscription`: the optional subscription, consent, bank login through the aggregator, the states of the subscription, and leaving the service.

### Modified Capabilities

None.

## Impact

- Milestone: v0.3
- Issues: #33, #34, #35, #36, #38
- Modules: `FinAPIConnector` owns the bank login in the web form and the data mapping. `App` owns the settings tab and the consent step. The subscription service is a separate repository under the AGPL.
- Depends on the change `add-account-setup` for the assistant and "Edit Login Data...", on `add-account-refresh` for when a refresh runs, on `add-login-credentials` for storing the tokens, and on `add-app-settings` for the settings window.
- Decisions: [ADR 0007](../../../docs/decisions/0007-optional-finapi-subscription.md), which is still in the state Proposed. [ADR 0002](../../../docs/decisions/0002-local-first-no-server.md), [ADR 0008](../../../docs/decisions/0008-payments-only-through-licensed-channels.md).
- The issues #33 and #34 are organizational. They must be closed before this change can start.

## Reference behavior

### Observed in MoneyMoney 2.5.3

- The settings tab "PSD2" explains the PSD2 online service, links to "Privacy Policy", "Terms of Use", and "Supported Banks", and shows "Licensed until" with a date. See [analysis](../../../docs/research/moneymoney-analysis.md#settings-u).
- The service is activated only with explicit consent. The user ticks a box that says which login data goes to which company ([security page](https://moneymoney.app/security/)).
- The service only fetches transactions and cannot send payments ([PSD2 page](https://moneymoney.app/psd2/)).
- The service costs 39.99 euros for one year, can be tried for 30 days, and does not renew by itself.
- The bank login runs in a web browser. A button "Open Web Browser..." starts it, and a URL scheme brings the user back. See [analysis](../../../docs/research/moneymoney-analysis.md#url-schemes-and-file-types-s).
- Some banks ask for a new two-factor approval only every 180 days at the PSD2 interface ([two-factor page](https://moneymoney.app/sca/)).
- The commands "Stop using the service..." and "Delete customer account..." exist. The app says that data stored online is deleted, that data on the Mac stays, and that the operator must keep some data for a legal period.
- "Identifier for customer support..." shows an identifier for support requests.
- An existing account switches to the PSD2 interface with "Edit Login Data...". For a payment the app suggests to switch to FinTS/HBCI.
- After the usage period ends, the app says so and asks for a renewal.

### Decided for Moneten

- The aggregator is finAPI, reached through a subscription service of the project ([ADR 0007](../../../docs/decisions/0007-optional-finapi-subscription.md)). MoneyMoney runs its own registered service.
- The user enters the bank login data in finAPI's web form. The app does not see it. MoneyMoney sends the login data to its own service.
- The subscription is paid on the website of the service and renews until the user cancels. MoneyMoney sells a fixed year without renewal.
- A trial exists only when the service grants one. The app shows the remaining days that the service reports.
- The consent text names two recipients, the operator of the subscription service and finAPI.
- An expired subscription or expired bank consent stops only the refresh through the aggregator. The accounts and all data stay usable.
- The app shows a reminder 14 days before a bank consent ends.
- The app sends no transactions, categories, comments, or other accounts to the subscription service.
- Payments through the aggregator are not part of this change. Issue #36 leaves them open until the contract with finAPI is known.
- The price, the terms, and the operator are not fixed yet. The spec refers to them as values that the service reports.
