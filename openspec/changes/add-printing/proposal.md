# Proposal: Print lists and single entries

## Why

Paper and PDF are still how money matters reach a tax adviser, a landlord, or a folder on the shelf. A user must be able to print what a view shows, with the same filters, and decide how much detail goes on the page.

## What Changes

- Every list view has a print command with the shortcut ⌘P that prints what the view shows.
- A selection prints only the selected rows.
- The print dialog has options for transaction lists, for example categories, comments, the order, balances, and sums.
- Single transactions, portfolio items, statements, and the payment views can be printed.
- "Page Setup…" sets the paper for all printouts.

## Capabilities

### New Capabilities

- `printing`: the print commands of all views, the print options for transaction lists, and the page layout.

### Modified Capabilities

None.

## Impact

- Milestone: later
- Issues: none yet
- Modules: `App` owns the print layouts and the print panel options.
- Depends on the change `add-transaction-list` and the change `add-transaction-search-and-filters` for what a view shows.
- The print commands for portfolio items, statements, the outbox, scheduled payments, templates, and direct debit mandates work once the changes `add-securities-accounts`, `add-bank-statements`, `add-payment-outbox`, `add-scheduled-payments`, `add-payment-templates`, and `add-direct-debits` are done.
- Reports belong to the change `add-reports`. The INI letter belongs to the change `add-hbci-keys-and-chipcards`.
- Decisions: none apply.

## Reference behavior

### Observed in MoneyMoney 2.5.3

- The File menu has "Page Setup…" with ⇧⌘P. The Account menu and the context menus have one print command with ⌘P that takes the name of the view, for example "Print Transactions...", "Print Portfolio Items...", "Print Outbox...", "Print Scheduled Payments...", "Print Templates...", and "Print Statements...". See [analysis](../../../docs/research/moneymoney-analysis.md#menus-and-keyboard-shortcuts-u) and [context menus](../../../docs/research/moneymoney-analysis.md#context-menus-u).
- The interface strings hold a print command in the singular and the plural for transactions, transfers, payments, transfer templates, scheduled transfers, standing orders, SRZ orders, direct debits, direct debit mandates, portfolio items, and statements.
- The options for a transaction list are "Print category names", "Print comments", "Print first purpose line only", "Print newest transactions first" or "Print oldest transactions first", "Print current balance", "Print daily balance", and "Print sum of deposits/withdrawals" (interface strings).
- More information on printed transaction lists, configured in the print preview, arrived in version 2.2.3. The reverse order arrived in 2.1.9, printed comments in 2.1.5, and the first purpose line option in 2.3.12.
- A selection in the list is respected when printing (version history, 2.2.1).
- Batch transfers print as a list (version history, 2.2.3).
- Printouts carry a period line and page numbers in the form "Page 1 of 3" (interface strings).
- A fix in version 2.4.65 concerns a transaction that was lost before a page break. Another fix concerns a purpose that printed in one line only (2.2.1).

### Decided for MonetenMoneten

- The print dialog is the standard dialog of macOS with its preview and its PDF functions.
- Printouts use dark text on a white page in every appearance.
- The app remembers the print options for transaction lists.
- The header of a transaction list names the account, group, or category, the period, and the search text. The exact header of MoneyMoney was not observed.
- A single transaction prints on one page with all its details.
- A row is never divided between two pages.
- "Print Outbox..." prints the drafts and "Print Payments..." prints the sent payments. Both commands are interface strings of MoneyMoney, but which view each belongs to was not observed.
- With a kind filter in the "Scheduled" view, the command takes the name of the kind, for example "Print Standing Orders...". The plural commands are interface strings, and when MoneyMoney shows them was not observed.
