# Proposal: Schedule transfers and manage standing orders

## Why

Rent, insurance, and savings plans run as standing orders, and invoices with a due date are paid as scheduled transfers. Users expect to see and manage these orders next to their accounts and not on the bank website. Business users also authorize payroll files that a service data center (SRZ) sends to the bank.

## What Changes

- The payment window can set an execution date. The bank stores the transfer and executes it on that date.
- A new payment kind, the standing order, with a first payment, an interval, an execution day, and an optional last payment.
- A view "Scheduled" under "Payments" that lists scheduled transfers, standing orders, scheduled batch transfers, and SRZ orders of all accounts.
- "Refresh Scheduled Payments" fetches the lists from the banks.
- Standing orders and scheduled transfers can be changed and deleted where the bank supports it.
- SRZ orders can be authorized and deleted.

## Capabilities

### New Capabilities

- `scheduled-payments`: orders that the bank holds for a later date. That covers scheduled transfers, standing orders, and SRZ orders, the view that lists them, and how they are fetched, changed, and deleted.

### Modified Capabilities

None.

## Impact

- Milestone: later
- Issues: none yet
- Modules: `Domain` owns the schedule rules and the lead time arithmetic. `FinTSConnector` fetches, changes, and deletes the orders. `App` owns the "Scheduled" view and the schedule controls of the payment window.
- Depends on the change `add-sepa-transfers` for the payment window, the field checks, the payee check, the confirmation, and the results.
- Depends on the change `add-main-window` for the "Payments" section of the sidebar.
- Decisions: [ADR 0008](../../../docs/decisions/0008-payments-only-through-licensed-channels.md).

## Reference behavior

### Observed in MoneyMoney 2.5.3

- The payment window has "Schedule" with "Now" and "Set date". "Action" offers "New standing order". See [payment window](../../../docs/research/moneymoney-analysis.md#payment-window-u-s-w).
- The view "Scheduled" has the filter "Kind" with "All", "Scheduled Transfers", "Standing Orders", and "SRZ Orders", the filter "Account", a button "Refresh Scheduled Payments", and a status line with the number and the sum of the orders. The toolbar button reads "Standing order". See [main window](../../../docs/research/moneymoney-analysis.md#main-window-u) and [payments](../../../docs/research/moneymoney-analysis.md#payments-u-s-w).
- The context menu of a standing order has "Change Standing Order...", "New from Selection", "Print Standing Order...", and "Delete Standing Order...". See [context menus](../../../docs/research/moneymoney-analysis.md#context-menus-u).
- The strings name the fields "First payment on", "Last payment on", "Repeat", and "Transaction day", and the check that the first payment lies before the last payment.
- The last day of the month can be chosen as the execution day (version history, 2.2.1).
- The list is compared with the bank only when an execution date is due. The user can fetch it at any time ([help](https://moneymoney.app/help/), version history 2.2.7).
- The strings hold one message for each thing a bank might not support. These are scheduled transfers, standing orders, changing and deleting each kind, and authorizing and deleting SRZ orders. Each message names the alternative.
- The strings hold messages for a minimum and a maximum lead time with the next or the latest possible date.
- Instant scheduled transfers and instant standing orders cannot be changed. Scheduled batch transfers cannot be changed, and their positions cannot be displayed. They can be deleted (version history, 2.2.4).
- A hint says that orders changed on the bank website appear after "Refresh Scheduled Payments".
- A new standing order is shown from a local copy until the bank lists it (version history, 2.4.47, written for one bank).
- SRZ orders are listed in "Scheduled", also when their date has passed, and are authorized in the app (version history, 2.4.12 and 2.4.13). Strings exist for an order that is already authorized, for a bank that needs to activate the function, and for the payee check that a bank cannot run for SRZ orders.
- Placeholders cannot be used in standing orders ([templates page](https://moneymoney.app/templates/)).

### Decided for MonetenMoneten

- The intervals that the app offers for a standing order are those in the bank's parameter data. The list that MoneyMoney shows was not observed.
- The app warns when the purpose of a standing order contains a placeholder. MoneyMoney only documents that placeholders do not work there.
- A new order appears at once from a local copy for every bank, not only for one.
- Scheduled transfers and standing orders run through the same payee check and review as a transfer. The screens of MoneyMoney were not observed.
- Commands that need a selection are disabled without one. MoneyMoney shows a message such as "Please select a standing order."
