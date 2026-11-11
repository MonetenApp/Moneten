# Proposal: Import QIF, OFX, and tab-separated files

## Why

Users who come from other finance programs bring their history in the export format of that program. Quicken-style QIF files and OFX files are the common ones. MoneyMoney reads them, and a user who switches expects the same.

## What Changes

- "Import Transactions..." also reads QIF files, including their categories.
- It also reads OFX and QFX files.
- It also reads tab-separated text files.
- CSV exports of other finance apps are recognized by their header row and need no mapping.
- The message for an unsupported file lists the longer set of formats.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `transaction-import`: adds the formats QIF, OFX, QFX, and tab-separated text, and built-in profiles for the CSV exports of other finance apps. The change `add-file-import` introduces this capability.

## Impact

- Milestone: later
- Issues: none yet
- Modules: `Import` gets three more parsers and the built-in CSV profiles.
- Depends on the change `add-file-import`, and on `add-split-transactions` for split records in QIF files.
- Decisions: none apply.

## Reference behavior

### Observed in MoneyMoney 2.5.3

- The import reads CSV, QIF, OFX, QFX, MT940, and camt.052 and camt.053. The message for an unsupported file lists exactly these. See [analysis](../../../docs/research/moneymoney-analysis.md#file-formats-s-w-c).
- The [help page](https://moneymoney.app/help/) also names tab-separated text files as an import format.
- Categories are taken from QIF files (version history, 2.2.9).
- QIF files that state their date format are read with it (version history, 2.4.62). Without it, the app detects European and American dates by heuristics (version history, 2.4.27).
- OFX import exists since version 2.1.14.
- The app "supports the CSV export formats of current finance apps" and detects other CSV files by itself (interface strings).

### Decided for Moneten

- A QIF file can hold sections of several kinds. The app imports the bank, cash, and credit card sections and reports investment sections as skipped. MoneyMoney's behavior was not observed.
- An OFX file with several accounts is matched to the accounts of the app by account number. MoneyMoney's behavior was not observed.
- The OFX transaction ID is used to detect a transaction that was imported before.
- Which finance apps get a built-in CSV profile is decided when the work starts. The spec names the rule, not the list.
- Tab-separated text goes through the same preview as CSV.
- A cleared QIF record gets a checkmark, and a QIF record with split lines becomes a split transaction. Neither was observed in MoneyMoney.
- The app ships a profile for its own CSV export, so that an export can be imported again without setup.
