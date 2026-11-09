# Proposal: Collect payments in an outbox and send batch transfers

## Why

Someone who pays ten invoices does not want ten TAN approvals. A small business pays its staff from a file that the payroll software wrote. Both need a place to prepare payments and a way to send many of them as one order with one TAN.

## What Changes

- A view "Outbox" under "Payments" with "Drafts" for prepared payments and "Sent" for transmitted orders.
- "Save in outbox" in the payment window, and a setting that makes this the default.
- Batch transfers from the drafts, from a template group, and from a SEPA XML file. SEPA XML files also open from Finder and from the Dock icon.
- Checks for every position of a batch, with the position number and the reason.
- An offer to split a batch by execution date and by the largest size that the bank accepts.
- A status report when the bank rejects single positions.
- The payee check for batches, with the bank's limit and the opt-out notice.
- Import and export of drafts as SEPA XML.

## Capabilities

### New Capabilities

- `payment-outbox`: prepared payments, the list of sent orders, and batch transfers from drafts, template groups, and SEPA XML files.

### Modified Capabilities

None.

## Impact

- Milestone: later
- Issues: none yet
- Modules: `Domain` owns the batch checks and the split rules. `Import` reads and writes SEPA XML. `FinTSConnector` sends batch orders. `Storage` keeps drafts and sent orders in the encrypted database. `App` owns the view and the batch window.
- Depends on the change `add-sepa-transfers` for the payment window, the single-position checks, the confirmation, the results, and the record of sent orders.
- Depends on the change `add-payment-templates` for batches from a template group.
- Depends on the change `add-scheduled-payments` for scheduled batches in the view "Scheduled".
- The change `add-split-transactions` turns a booked batch into its positions.
- The change `add-direct-debits` adds direct debit batches to the same outbox.
- Decisions: [ADR 0008](../../../docs/decisions/0008-payments-only-through-licensed-channels.md).

## Reference behavior

### Observed in MoneyMoney 2.5.3

- "Outbox" has the views "Drafts" and "Sent" and an "Account" filter. Its toolbar button reads "Batch transfer". Its context menu has "New Batch Transfer...", "Print Outbox...", "Import Outbox...", and "Export Outbox...". See [main window](../../../docs/research/moneymoney-analysis.md#main-window-u) and [context menus](../../../docs/research/moneymoney-analysis.md#context-menus-u).
- The gear menu of the payment window has "Save in outbox". The setting "Save new payments in outbox by default" is on the "Payments" tab. See [settings](../../../docs/research/moneymoney-analysis.md#settings-u).
- Drafts are sent one by one with a double click or together with "New Batch Transfer from Outbox...". All sent transfers appear under "Sent" ([help](https://moneymoney.app/help/)).
- "Sent" shows the submission time, the execution date, and the TAN method, and it lists change and delete orders (version history, 2.2.12, 2.3.5, and 2.4.12).
- The Payment menu has "New Batch Transfer from Outbox...", "from Template Group...", and "from SEPA XML File...". See [menus](../../../docs/research/moneymoney-analysis.md#menus-and-keyboard-shortcuts-u).
- SEPA XML files open from the Dock icon and from Finder (version history, 2.2.13). SEPA container files are read (version history, 2.2.17). The app handles the file type `.pain`. See [URL schemes and file types](../../../docs/research/moneymoney-analysis.md#url-schemes-and-file-types-s).
- A file is converted to the newest SEPA version that the bank supports. One batch is created for each source account. A batch is split by execution date and by the bank's limit of positions (version history, 2.2.9 and 2.3.0).
- Wrong bank details from a file can be corrected in the app (version history, 2.2.11).
- The bank can book a batch as single transactions when the option is set ([help](https://moneymoney.app/help/)). Strings exist for banks that can only book single transactions and for banks that cannot.
- The strings hold one message for each position check in this spec, each with the position number.
- Strings exist for a batch that contains the same IBAN with different names and the same amount to the same account several times.
- A batch can carry its own reference (version history, 2.4.12). The strings call it "Designation" and forbid slashes at the start, at the end, and two in a row.
- Positions that the bank rejects are shown in a status report and stay in the outbox (version history, 2.2.17).
- The payee check for batches, the bank's limit of positions, and the opt-out for business accounts are described on the [payee check page](https://moneymoney.app/vop/) and in the strings.
- Instant batch transfers are supported (version history, 2.4.4).
- Strings exist for an order that was partially transmitted and for an order that was canceled because of a previous server error.
- The outbox can be imported and exported (version history, 2.4.18). The strings limit the format to SEPA XML and forbid mixing transfers with direct debits, positions without an IBAN, and foreign currency.

### Decided for MonetenMoneten

- "Sent" does not show the TAN that was entered. MoneyMoney shows it. See [ADR 0009](../../../docs/decisions/0009-database-password-as-in-moneymoney.md).
- The review of a batch groups the positions by payee check result and lists the positions that do not match. MoneyMoney's screens for the batch payee check were not observed.
- The payee check opt-out is a switch in the batch window that is off by default. Where MoneyMoney places this choice was not observed.
- A batch draws on drafts that the user selected, or on all drafts when none is selected. The help describes the selection with the Command key for mandates only.
- The batches of a split are sent one after the other, and the app stops after the first failure. The strings show the two messages, and the order of events was not observed.
- A SEPA XML file with an error in its structure is rejected as a whole. Only wrong bank details of single positions can be corrected in the app.
