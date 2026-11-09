# Proposal: Import transactions from CSV, CAMT, and MT940 files

## Why

A bank gives only 30 to 450 days of history through FinTS. Older transactions exist only as files from the bank's website or from another finance program. Many brokers and some banks offer nothing but a CSV download. Without a file import a new user starts with a short history, and some accounts cannot be filled at all.

## What Changes

- "Import Transactions..." imports one or more files into the selected account.
- The app reads CSV files and detects delimiter, encoding, date format, decimal format, and columns by itself.
- A preview shows how the app reads a CSV file. The user corrects the mapping and saves it as a profile.
- The app reads camt.052 and camt.053 files and MT940 files.
- Transactions that already exist are skipped and counted.
- Categories can be taken from a CSV column.
- A result message states what was imported.

## Capabilities

### New Capabilities

- `transaction-import`: importing transactions from files into an account, with format detection, the CSV preview and profiles, duplicate handling, and result and error messages.

### Modified Capabilities

None.

## Impact

- Milestone: v0.1
- Issues: #22, #23
- Modules: `Import` owns the parsers and returns an import batch. `Domain` owns the detection of duplicates. `App` owns the file dialog, the preview, and the messages.
- Depends on the change `add-account-refresh` for the rules that decide whether two transactions are the same, on `add-categorization-rules` for the rules that run on imported transactions, on `add-categories` for the category tree, and on `add-offline-accounts` for accounts without a bank access.
- Decisions: none apply.

## Reference behavior

### Observed in MoneyMoney 2.5.3

- "Import Transactions..." is in the Account menu and in the context menu of an account. It is disabled for an account group. See [analysis](../../../docs/research/moneymoney-analysis.md#menus-and-keyboard-shortcuts-u) and [analysis](../../../docs/research/moneymoney-analysis.md#context-menus-u).
- The supported formats are CSV, QIF, OFX, QFX, MT940, and camt.052 and camt.053. See [analysis](../../../docs/research/moneymoney-analysis.md#file-formats-s-w-c). This change covers CSV, CAMT, and MT940. The other formats are in the change `add-more-import-formats`.
- The app detects the format of a CSV file by itself and works best when the columns carry common keywords as headers (interface strings).
- An option "Auto-create categories" exists, with the result message "Created 2 new categories." Categories can be taken from CSV files (version history, 2.2.9).
- Existing transactions are kept and not overwritten (version history, 2.0.23). The result names the number of imported and of skipped transactions.
- The app detects European and American date formats by heuristics (version history, 2.4.27).
- Several MT940 files can be imported at once, and they use the extension `.sta` (version history, 2.0.13).
- The chart is recomputed after an import (version history, 2.0.13).
- Error messages exist for an unsupported format with the list of supported ones, for an empty file, and for a file larger than 100 MB. Messages titled "Error in file" and "Warnings for file" name the file.
- Older transactions can be imported into an online account ([help page](https://moneymoney.app/help/)).

### Decided for MonetenMoneten

- The preview with a column mapping and saved profiles comes from issue #22. MoneyMoney imports a CSV file without a preview.
- A file is imported completely or not at all. One row that cannot be read stops the import of that file with the line number. MoneyMoney's behavior for a partly readable file was not observed.
- The app detects the format from the content of the file, not from its name.
- For a CAMT or MT940 file whose IBAN belongs to another account, the app asks before it imports. For an IBAN that no account has, the app offers to create an offline account (issue #23).
- A category from a file counts as assigned by hand.
- The list of header keywords in the spec is a starting set. MoneyMoney's full list was not extracted.
