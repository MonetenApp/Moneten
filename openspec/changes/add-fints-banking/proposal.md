# Proposal: Read accounts, balances, and transactions through FinTS

## Why

FinTS is the interface that almost every German bank offers to banking software. It is free, it needs no intermediary, and it is the only free way to read securities accounts. Without it the app would depend on extensions or on the paid subscription for the most common banks. This change defines what the user gets from a FinTS access with PIN and TAN.

## What Changes

- The app finds the FinTS address of a bank from its Bankleitzahl.
- The app lists the accounts of a login and reads what each account allows.
- The app fetches the balance and the transactions of each account, in CAMT where the bank offers it and in MT940 otherwise.
- A normal refresh asks for at most the last 90 days, so that most banks ask for no TAN. The first refresh and an enforced refresh ask for the full history.
- The app splits the structured purpose into its fields, such as the end-to-end reference and the mandate reference.
- The app shows notices and error messages of the bank in the bank's own words.
- The app handles a required PIN change and a blocked access without a second login attempt.

## Capabilities

### New Capabilities

- `fints-banking`: what the app reads through FinTS 3.0 with PIN and TAN, and how it reports what the bank answers.

### Modified Capabilities

None.

## Impact

- Milestone: v0.1
- Issues: #9, #10, #11, #12, #13
- Modules: `FinTSConnector` owns the bank directory, the dialogs, and the mapping to `Domain` types. `Domain` owns the parsed transaction fields.
- Depends on the change `add-login-credentials` for the PIN, on `add-tan-handling` for every TAN, on `add-account-refresh` for when a refresh runs and for the removal of duplicates, and on `add-connection-security` for the encrypted connection.
- Payments, securities, statements, key files, chip cards, and the PIN change assistant come with their own changes.
- Decisions: [ADR 0014](../../../docs/decisions/0014-fints-through-hbci4java.md). Banks accept only registered products, so issue #9 must be closed before a public release.

## Reference behavior

### Observed in MoneyMoney 2.5.3

- MoneyMoney fetches the balance separately from the transactions and shows the balance of the bank, not a computed one (https://moneymoney.app/help/).
- MoneyMoney normally fetches only the last 90 days, because older transactions need two-factor authentication under EU regulation 2018/389. Banks keep between 30 and 450 days. "Refresh Account (enforced)" in the context menu with the Option key fetches everything the bank provides (https://moneymoney.app/help/).
- Transactions are fetched as CAMT (camt.052) or MT940 (version history 2.2.0 and later entries).
- Pending transactions are delivered and shown hatched (https://moneymoney.app/help/).
- More details from the structured purpose are shown, namely the booking text, the end-to-end reference, the mandate reference, and the creditor ID (version history 2.2.11). A deviating originator or recipient is shown (2.2.9). Foreign currency amounts of card transactions from CAMT are shown.
- When the bank sends only an end-to-end reference and no purpose, the reference becomes the purpose (version history 2.4.32).
- Line breaks in the purpose are detected (version history 2.0.18).
- Announcements of the bank that arrive through FinTS, for example about maintenance, appear in a notice window (version history 2.4.18).
- Strings show bank errors quoted in the bank's words, and messages for a PIN change that the server requires, for a blocked PIN, for an empty account list, for a timeout, and for "No older transactions are provided by your bank."
- Strings show that the app says which operation the FinTS server of a bank does not support for an account.
- Accounts of one bank are handled in one session to keep the number of logins low (https://moneymoney.app/sca/).
- A credit card that the bank offers through FinTS is added with the Bankleitzahl of the bank (strings).

### Decided for Moneten

- The app supports FinTS 3.0. It does not support the older HBCI 2.2. MoneyMoney supports both.
- The user cannot enter a FinTS address by hand. The address comes from the bank directory. MoneyMoney's current behavior was not observed.
- The first refresh after setup asks for the full history. When the bank wants a separate TAN for transactions older than 90 days and the user cancels that TAN, the app fetches the last 90 days. The plan in issue #13 names 90 days. MoneyMoney's behavior at setup was not observed.
- A normal refresh asks for the time since the last successful fetch plus an overlap of 14 days, and never for more than 90 days. MoneyMoney states only the limit of 90 days.
- A notice of the bank is shown once. Whether MoneyMoney repeats a notice was not observed.
- A canceled or interrupted fetch stores nothing for the account that was in progress. This was not observed.
- The app shows the return code of the bank next to the bank's text. MoneyMoney shows the text.
