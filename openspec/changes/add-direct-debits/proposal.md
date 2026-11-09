# Proposal: Collect payments with SEPA direct debits

## Why

Clubs, landlords, and small businesses collect fees, rent, and invoices by direct debit. They keep a mandate for each payer and draw the same amounts every month. MoneyMoney sells this as a paid add-on. Without it, these users cannot switch.

## What Changes

- A creditor ID in the account settings.
- A list "Direct Debit Mandates" under "Payments" with mandates for core and B2B direct debits. Mandates live in template groups.
- Single direct debits from a mandate, with a due date that follows the lead time and the cut-off time of the bank.
- Direct debit batches from a template group, from the outbox, and from a SEPA XML file.
- An offer to split a batch by kind, sequence, due date, and size.
- Submitted direct debits in the view "Scheduled", with change and delete where the bank supports it.
- Import and export of mandates as CSV and SEPA XML.

## Capabilities

### New Capabilities

- `direct-debits`: the creditor ID, mandates, single direct debits, direct debit batches, and the direct debits that wait at the bank.

### Modified Capabilities

None.

## Impact

- Milestone: later
- Issues: none yet
- Modules: `Domain` owns the mandate type, the due date arithmetic, and the checks. `Import` reads and writes CSV and SEPA XML. `FinTSConnector` sends the orders. `App` owns the mandate list and the direct debit window.
- Depends on the change `add-sepa-transfers` for the payment window, the field checks, the confirmation, and the results.
- Depends on the change `add-payment-templates` for template groups, placeholders, and the address fields.
- Depends on the change `add-payment-outbox` for drafts, the batch window, the position checks, the status report, and the list of sent orders.
- Depends on the change `add-scheduled-payments` for the view "Scheduled".
- Decisions: [ADR 0008](../../../docs/decisions/0008-payments-only-through-licensed-channels.md), [ADR 0006](../../../docs/decisions/0006-license-gpl-3.md).

## Reference behavior

### Observed in MoneyMoney 2.5.3

- The Payment menu has "New Direct Debit Mandate...", "Import Direct Debit Mandates...", "Export Direct Debit Mandates...", "New Direct Debit...", and "New Batch Direct Debit" from the outbox, from a template group, and from a SEPA XML file. See [menus](../../../docs/research/moneymoney-analysis.md#menus-and-keyboard-shortcuts-u).
- The [help](https://moneymoney.app/help/) describes core and B2B direct debits as single orders and as batches, mandates in template groups with drag and drop, the placeholder for the month, "Use Direct Debit Mandate...", the selection of some mandates with the Command key, batches from SEPA XML files, saving direct debits in the outbox, and submitted direct debits under "Scheduled".
- The strings name the commands "Use Direct Debit Mandates...", "Use as direct debit", and "Use as batch direct debit" for several selected mandates.
- The strings name the sequences first/recurring, final, and one-off, the mandate fields "Mandate reference" and "Mandate date", the date "last used on", and the debtor.
- The strings hold messages for a missing or invalid creditor ID, for an account that the bank has not set up for direct debits, for the collection agreement with the bank, and for accounts in another currency than the euro.
- The strings hold the mandate checks in this spec. These are a missing mandate reference, slashes at the start, at the end, or two in a row, spaces that a bank does not support, a mandate date in the future, a debtor address for countries outside the European Economic Area, and a BIC that cannot be used for direct debits or for B2B direct debits.
- The strings hold lead time messages with business days and a cut-off time, and a maximum lead time.
- A batch must have one kind, one sequence, and one due date. The app offers to split it, also by the bank's limit of positions (version history, 2.2.9). Banks with SEPA 3.1 accept several sequences in one batch (version history, 2.3.3).
- Invalid BICs are ignored in direct debit batches inside the European Union (version history, 2.4.30).
- Mandates store the date of their last use (version history, 2.2.11). Mandates can hold a postal address (version history, 2.3.4).
- The creditor ID in a SEPA XML file must equal the creditor ID of the account (strings).
- The express direct debit was replaced by the core direct debit (strings).
- Strings exist for SRZ authorization for direct debits.

### Decided for MonetenMoneten

- Direct debits are part of the app for everyone. MoneyMoney sells them as an add-on for 49,99 €.
- The entry "Direct Debit Mandates" is always in the sidebar under "Payments" once this change ships.
- The app sets the due date of a new direct debit to the next possible date. MoneyMoney's default was not observed.
- The app checks the creditor ID by its length, its country code, and its check digits. The strings show only that an invalid creditor ID is rejected.
- The limit of 35 characters for the mandate reference comes from the SEPA rules.
- The app warns when a mandate is used again after a final or a one-off direct debit. MoneyMoney's behavior was not observed.
- The payee check does not apply to direct debits, and the review says so.
