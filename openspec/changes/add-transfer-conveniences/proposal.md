# Proposal: Make transfers faster to enter

## Why

Most transfers pay an invoice. The data is already on the screen, in an email, a PDF, or a QR code, and typing it again causes errors. MoneyMoney users are used to pasting a block of bank details and to picking a recipient from a list.

## What Changes

- Recipient suggestions also come from earlier transfers and from templates, and they prefer the newest spelling.
- The "Action" menu lists the recently used recipients.
- "Insert from Pasteboard" fills the payment window from copied text, including the text of a GiroCode.
- Links with the URL schemes `bank` and `payto` open a filled payment window.
- A cash discount calculator changes the amount by a percentage.
- Optional fields for the end-to-end reference and the purpose code.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `sepa-transfers`: adds input aids to the payment window. The change `add-sepa-transfers` introduces this capability.

## Impact

- Milestone: later
- Issues: none yet
- Modules: `Domain` owns the text recognition, the GiroCode reader, and the discount arithmetic. `App` owns the menu entries and the URL handling.
- Depends on the change `add-sepa-transfers`.
- Depends on the change `add-payment-templates` for suggestions from templates.
- Decisions: [ADR 0008](../../../docs/decisions/0008-payments-only-through-licensed-channels.md). A link or a pasted text never sends a payment.

## Reference behavior

### Observed in MoneyMoney 2.5.3

- The "Action" menu ends with "Insert from Pasteboard" and a list "Recently used". See [payment window](../../../docs/research/moneymoney-analysis.md#payment-window-u-s-w).
- The gear menu offers "Deduce cash discount", "Set end-to-end reference", and "Set purpose code".
- Suggestions come from earlier transfers, templates, and transactions (version history, 2.2.13). An older entry is not suggested when a newer entry has the same name with another IBAN, or the same IBAN with another spelling (version history, 2.4.24).
- Pasting finds all usable information in the copied text ([feature page](https://moneymoney.app/)). A GiroCode can be scanned with an iPhone and pasted through the shared clipboard. The app takes the recipient, IBAN, BIC, amount, and purpose, and it leaves the amount empty for another currency ([QR code help](https://moneymoney.app/help/ueberweisung-aus-qr-code/)).
- Messages exist for "no IBAN found in the pasteboard" and for denied pasteboard access.
- The app registers the URL schemes `bank` and `payto`, and it has supported the SEPA BezahlCode since version 2.0.1. See [URL schemes](../../../docs/research/moneymoney-analysis.md#url-schemes-and-file-types-s).
- The cash discount calculator arrived in version 2.4.24. Its strings show the resulting amount and the resulting discount, an error for an invalid value, the need to enter the full amount first, and a way to restore the previous amount.
- The end-to-end reference must not start or end with a slash and must not contain two slashes in a row. An invalid purpose code is rejected.
- The default settings list the purpose codes SALA, CBFF, and CHAR.

### Decided for MonetenMoneten

- The parameters that the app reads from `bank` and `payto` links follow the public BezahlCode description and RFC 8905. MoneyMoney's parsing was not observed.
- The "Recently used" list holds ten recipients. The length of MoneyMoney's list was not observed.
- The limit of 35 characters for the end-to-end reference comes from the SEPA rules.
- The purpose code field accepts any code of four letters and suggests the three default codes. How MoneyMoney presents the list was not observed.
- A percentage or a discount amount can be entered in the calculator. MoneyMoney's input format was not observed.
