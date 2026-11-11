# Proposal: Export transactions in banking and spreadsheet formats

## Why

Tax advisers and accounting programs ask for bank formats such as MT940 and CAMT. Other users want a spreadsheet file that opens without an import step. MoneyMoney offers all of these, and a user who switches expects them.

## What Changes

- "Export Transactions..." also writes OFX, MT940, camt.053, Excel, and Numbers files.
- MT940 has two options, the account identification and interim balances.
- MT940 and OFX can hold all accounts of a group in one file.
- Bank formats carry an opening and a closing balance that fit the exported rows.
- A property list format serves automation.
- "Send Transactions to" hands transactions to another installed app.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `transaction-export`: adds the formats OFX, MT940, camt.053, Excel, Numbers, and property list, the options of MT940, group exports, and the command "Send Transactions to". The change `add-data-export` introduces this capability.

## Impact

- Milestone: later
- Issues: none yet
- Modules: `Domain` owns the export model. A new export package holds the writers. `App` owns the format menu and its options.
- Depends on the change `add-data-export`. "Send Transactions to" lists the apps that export extensions from the change `add-import-export-extensions` name. The property list format is used by the change `add-applescript-automation`.
- Decisions: none apply.

## Reference behavior

### Observed in MoneyMoney 2.5.3

- The export formats are CSV, OFX 1.6, MT940, camt.053.001.08, Excel `.xlsx`, Numbers, and property list. See [analysis](../../../docs/research/moneymoney-analysis.md#file-formats-s-w-c).
- OFX uses version 1.6 (version history, 2.3.9) and states the account type (version history, 2.0.0).
- MT940 offers a choice between IBAN and Bankleitzahl (version history, 2.3.25) and an option for interim balances (version history, 2.4.18). It writes exactly two decimals (version history, 2.4.2), is compact (version history, 2.4.16), fits DATEV software (version history, 2.1.14), and uses the extension `.sta` (version history, 2.0.13).
- CAMT export is camt.053.001.08 (version history, 2.4.33). The opening balance of an export of selected rows fits the selection (version history, 2.4.3).
- MT940 and OFX can export a whole account group (version history, 2.2.3).
- Excel export writes `.xlsx` (version history, 2.5.0) and includes comments (version history, 2.1.6).
- An account without an IBAN, such as a PayPal account, can get an account number for the MT940 export and an IBAN for the CAMT export in its settings (version history, 2.4.16).
- The context menu offers "Send Transaction to" for installed integration apps. See [analysis](../../../docs/research/moneymoney-analysis.md#context-menus-u).
- The format `plist` is available to AppleScript. See [analysis](../../../docs/research/moneymoney-analysis.md#applescript-s-w).

### Decided for Moneten

- Spreadsheet files have the same columns as the CSV export, with real date and number cells.
- A group export in a bank format writes one statement for each account, in sidebar order. The exact layout in MoneyMoney was not observed.
- Formats that cannot describe several accounts or several currencies in one file refuse such an export with a message. MoneyMoney's behavior was not observed.
- The balances of a bank format come from the balance history of the account. When the history has a gap, the app says so before it writes the file.
- The property list format does not appear in the save panel. It exists for automation only.
- Pending transactions are left out of MT940 and camt.053 files, because these formats describe booked statements.
