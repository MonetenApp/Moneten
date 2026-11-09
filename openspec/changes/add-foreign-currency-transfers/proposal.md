# Proposal: Send transfers in foreign currencies and to countries outside SEPA

## Why

SEPA covers the euro area and a few neighbors. A user who pays a supplier in the United States, a landlord in Australia, or family in Mexico needs an international transfer. German banks offer this through FinTS, and MoneyMoney users have it today.

## What Changes

- A new payment kind, the foreign currency transfer, with a currency, the country of the recipient, the address of the recipient, the bank of the recipient, a charges scheme, and instructions for the bank.
- Country rules for account numbers, addresses, and the purpose.
- Notices before sending. These are the hint that a SEPA transfer is cheaper, the reporting duty to the Deutsche Bundesbank, and a final confirmation.
- Templates for foreign currency transfers, with import and export.

## Capabilities

### New Capabilities

- `foreign-currency-transfers`: transfers in a currency other than the euro or to a country outside the SEPA area, their extra fields, country rules, and notices.

### Modified Capabilities

None.

## Impact

- Milestone: later
- Issues: none yet
- Modules: `Domain` owns the country rules and the checks. `FinTSConnector` sends the order. `App` extends the payment window.
- Depends on the change `add-sepa-transfers` for the payment window, the review, the confirmation, and the results.
- Depends on the change `add-payment-templates` for templates.
- Depends on the change `add-scheduled-payments` for the scheduled date.
- Depends on the change `add-account-extras` for the address of the account owner.
- Decisions: [ADR 0008](../../../docs/decisions/0008-payments-only-through-licensed-channels.md).

## Reference behavior

### Observed in MoneyMoney 2.5.3

- The Payment menu has "New Foreign Currency Transfer..." and "New Foreign Currency Transfer Template...". "Action" in the payment window has "New foreign currency transfer". See [menus](../../../docs/research/moneymoney-analysis.md#menus-and-keyboard-shortcuts-u) and [payment window](../../../docs/research/moneymoney-analysis.md#payment-window-u-s-w).
- Foreign transfers arrived in version 2.2.16. The recipient and the bank of the recipient can be in different countries since version 2.3.0.
- The strings ask the user to choose a currency, a country for the recipient, and a charging scheme. They name the fields "IBAN or account number", "Bank name", "Street of bank", "Place of bank", "Country of bank", and "Instructions for bank", and the gear commands "Set address", "Set country of bank", and "Set instructions for bank".
- Strings exist for a missing BIC or bank address, for an IBAN or a BIC that does not come from the country of the recipient, for countries that need the complete recipient address or a purpose text, and for account numbers that must be a BSB number with an account number or a CLABE number.
- Strings exist for the missing address of the account owner, for the cheaper SEPA transfer, for the reporting duty to the Deutsche Bundesbank with a threshold, a hotline, and a reporting portal, for the final question before an international transfer, for a bank or an account that does not support foreign currency transfers, and for the maximum lead time.
- A string says that the field for instructions for the bank can no longer be used and that its value belongs in another field.
- Foreign currency templates are exported and imported as XML in an international variant of `pain.001.001.09` (version history, 2.4.33).
- Batch transfers with foreign currency are not supported (strings).

### Decided for MonetenMoneten

- The three charges schemes are named "Shared", "Sender pays all charges", and "Recipient pays all charges". MoneyMoney's labels were not observed.
- The review says that the bank sets the exchange rate and the charges and that the payee check does not apply. MoneyMoney's review for this payment kind was not observed.
- The country rules ship as data with the app and name Australia for the BSB format and Mexico for the CLABE number. The strings show the two formats and leave the country to a variable.
- Which countries need the complete address or a purpose text is part of the same data. Canada and China in the scenarios are examples, not observations.
- The reporting threshold is data that ships with the app. The example value of 50.000 € is the threshold of the Außenwirtschaftsverordnung since 2025.
- The amount is entered in the chosen currency. A euro amount that the bank converts was not observed and is not offered.
