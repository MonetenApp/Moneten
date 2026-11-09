# Proposal: Send SEPA transfers with the payee check

## Why

A banking app that can only read still sends its user to the bank website for every invoice. The first transfer is the goal of v0.2. Payments also carry the highest risk in the app, so the spec fixes what the user sees and confirms before any order leaves the Mac.

## What Changes

- A payment window for one SEPA transfer, with a source account, the recipient, IBAN, BIC, amount, and purpose.
- Checks for every field while the user types, and warnings for a likely duplicate, a likely overdraft, and an empty purpose.
- Transfers between the user's own accounts.
- A new transfer from an existing transaction, and recipient suggestions from earlier transactions.
- A review step that shows the result of the Verification of Payee before the user confirms.
- Confirmation with a TAN, transmission, and a clear result. An order with an unknown result is never sent again by the app.
- Instant payments where the bank supports them, with a status check after transmission.
- A record of every transmitted order.

## Capabilities

### New Capabilities

- `sepa-transfers`: the payment window for one SEPA transfer or instant payment, its checks, the payee check, confirmation, transmission, results, and the record of sent orders.

### Modified Capabilities

None.

## Impact

- Milestone: v0.2
- Issues: #27, #28, #29, #30, #32
- Modules: `Domain` owns the payment states and all field checks. `FinTSConnector` sends the orders. `Storage` saves every state. `App` owns the payment window.
- Depends on the change `add-fints-banking` for the bank access and the bank's parameter data.
- Depends on the change `add-tan-handling` for the TAN dialog.
- Depends on the change `add-account-refresh`, which refreshes the account after a payment.
- Depends on the change `add-software-update` for current bank data such as the BIC directory.
- Decisions: [ADR 0008](../../../docs/decisions/0008-payments-only-through-licensed-channels.md), [ADR 0003](../../../docs/decisions/0003-fints-through-hbci4swift.md).

## Reference behavior

### Observed in MoneyMoney 2.5.3

- The payment window has "From", "Action", "Recipient", IBAN, BIC, "Amount", "Purpose", "Schedule", "Confirm using", a gear menu, and "Next", which stays disabled until the entries are valid. See [payment window](../../../docs/research/moneymoney-analysis.md#payment-window-u-s-w).
- "New Bank Transfer..." has the shortcut ⌘N. The toolbar shows "Bank transfer" in account views. See [menus](../../../docs/research/moneymoney-analysis.md#menus-and-keyboard-shortcuts-u).
- The "Action" menu lists one "Transfer to" entry for each own account.
- The interface strings hold one message for each field check in this spec. These are the IBAN checksum, the IBAN length for the country, an unexpected country code, a Bankleitzahl that the Bundesbank directory does not know, an IBAN outside the SEPA area, a BIC that does not fit the IBAN, a BIC that cannot receive SEPA transfers, a zero amount, characters that the bank does not accept, a missing owner name, and identical source and target accounts.
- The strings hold confirmation questions for an empty purpose, a likely overdraft, the same amount to the same account, and the same IBAN with a different name.
- The strings hold messages for a bank without a FinTS server, for a bank that does not allow transfers from giro or savings accounts, and for an access that could be switched to FinTS with "Edit Login Data".
- The BIC is found from the IBAN (version history, 2.2.2). SEPA transfers work without a BIC (version history, 2.1.5).
- "New from Selection" removes system text from the purpose (version history, 2.4.3).
- The payee check is described on the [payee check page](https://moneymoney.app/vop/).
- Result messages exist for transmitted, not accepted by the server, interrupted, and unclear whether the order was transmitted completely, with the advice to check the account statement.
- After an instant payment the app asks the bank for the status for up to 20 seconds (version history, 2.4.29) and shows whether the amount was credited (version history, 2.4.38).
- The app refreshes the account after a payment (version history, 2.4.8).

### Decided for MonetenMoneten

- The review step and the four payee check results with an explicit confirmation follow issues #27 and #29. The exact screens of MoneyMoney for the payee check were not observed.
- Every state of an order is saved, and the app resumes after a crash without sending again. This follows issue #28.
- An order with an unknown result becomes accepted when a later refresh delivers the matching transaction. MoneyMoney only advises the user to check the statement.
- Without a selected account, the payment window preselects the account that the user last paid from. MoneyMoney's choice was not observed.
- Recipient suggestions come from earlier transactions in this change. Suggestions from earlier transfers and templates follow in `add-transfer-conveniences`.
- "New from Selection" fills the amount as well as the bank details and the purpose. The evidence names only the bank details and the purpose.
- The limits of 70 characters for the name and 140 characters for the purpose come from the SEPA rules, not from an observation.
- Accounts that are reached through an extension or the aggregator cannot send payments. MoneyMoney can send through some of its built-in interfaces.
- The record of sent orders appears in a "Sent" list under "Payments". The change `add-payment-outbox` later makes that list one part of the outbox.
- The app never keeps a TAN with a sent order. MoneyMoney shows the TAN that was entered.
