# Proposal: Run import and export extensions that are compatible with MoneyMoney

## Why

Users move data between the app and many other programs, for example tax tools, budget apps, and accounting software. Each of them wants its own file format. Small Lua scripts let users add a format without waiting for a release, and scripts that exist for MoneyMoney keep working.

## What Changes

- The app runs Lua scripts that register with `Importer{}`. Each adds a file format to "Import Transactions...".
- The app runs Lua scripts that register with `Exporter{}`. Each adds a file format to "Export Transactions...".
- An export extension can name another app. That app then appears under "Send Transactions to".
- Export extensions are available to automation through the format name.
- The scripts read from standard input or write to standard output. They have no network and no other file access.

## Capabilities

### New Capabilities

- `import-export-extensions`: the Lua interfaces `Importer{}` and `Exporter{}`, their entry points and data structures, and where their formats appear in the app.

### Modified Capabilities

None.

## Impact

- Milestone: later
- Issues: none yet
- Modules: `ExtensionHost` runs the scripts. `Import` takes the transactions of an import extension. `App` owns the format menus.
- Depends on the change `add-web-banking-extensions` for the "Extensions" folder, the Lua runtime, the list in the settings, and the warning. Depends on `add-file-import` and `add-data-export` for the import and export commands, and on `add-extension-catalog` for the signature check.
- The menu command "Send Transactions to" is defined in the change `add-more-export-formats`. This change defines only which extensions count as an integration and how the hand-over runs. The AppleScript command that takes a format name is defined in the change `add-applescript-automation`.
- Decisions: [ADR 0004](../../../docs/decisions/0004-moneymoney-compatible-extension-api.md).

## Reference behavior

### Observed in MoneyMoney 2.5.3

- The import interface is documented on the [Import API page](https://moneymoney.app/api/import/), with `Importer{}`, `ReadTransactions`, the account and transaction structures, and the available `MM` functions.
- The export interface is documented on the [Export API page](https://moneymoney.app/api/export/), with `Exporter{}`, `WriteHeader`, `WriteTransactions`, `WriteTail`, the structures, and the `MM` functions.
- Scripts live in the "Extensions" folder. A changed file takes effect without a restart. Errors appear in the log window.
- The format label of a script appears in the format selection of the import or export dialog.
- `bundleIdentifier` lists an installed app under "Send Transactions to". `hidden` removes a format from the dialog. `reverseOrder` hands over the oldest transactions first.
- The AppleScript command `export transactions` accepts the name of an export extension as its format. See [analysis](../../../docs/research/moneymoney-analysis.md#applescript-s-w).
- The community publishes export extensions, for example for HTML, JSON, and Ledger files ([extensions page](https://moneymoney.app/extensions/)).

### Decided for Moneten

- An import or export script has no network access, and `io` is limited to standard input and standard output. The documentation does not state what MoneyMoney allows.
- An imported transaction needs `amount` and `bookingDate`. The Import API page does not name required fields. The rule is taken from the Web Banking API.
- For an export of an account group or a category, the `account` table describes the selection and has no account number, and each transaction table also carries the fields `accountName` and `accountIban` of its own account. The documentation covers only the export of one account.
- When an entry point returns an error message, the app deletes the partly written file.
- `MM.productName` is "Moneten".
- The catalog rules and the warning for unknown scripts apply to these scripts as well.
