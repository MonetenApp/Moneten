# Proposal: Download and keep PDF bank statements

## Why

A German bank customer must keep account statements for years, and the tax office asks for them. Banks put them in an online mailbox that the user has to visit bank by bank. The app can fetch them during a refresh and keep them in one place, as ordinary PDF files that stay readable without the app.

## What Changes

- A new sidebar section "Documents" with the view "Statements" shows all PDF statements in a grid.
- The user turns on the download for each account and chooses when it runs. The choices are every month, every two weeks, on a fixed day of the month, or only on request.
- The app stores each statement as a PDF file in the "Statements" folder, sorted by bank and account.
- Statements have a read state. New statements are unread and counted in the sidebar.
- The user can open, show in Finder, delete, import, and reassign statements.

## Capabilities

### New Capabilities

- `bank-statements`: the download schedule, the storage of statement files, and the "Statements" view with its commands.

### Modified Capabilities

None.

## Impact

- Milestone: later
- Issues: none yet
- Modules: `FinTSConnector` fetches statements from the bank. `ExtensionConnector` takes the documents that an extension returns. `Storage` keeps the list of statements and writes the files. `App` owns the view and the settings.
- Depends on the change `add-fints-banking` for the bank dialog, `add-account-refresh` for the refresh in which a due download runs, `add-tan-handling` for a TAN that the bank asks for, `add-web-banking-extensions` for the documents of an extension, `add-data-folder-and-backup` for the "Statements" folder, `add-main-window` for the sidebar section and the filter bar, `add-notifications-and-menu-bar` for the banner about new statements, and `add-printing` for "Print Statement...".
- Decisions: [ADR 0002](../../../docs/decisions/0002-local-first-no-server.md), [ADR 0009](../../../docs/decisions/0009-database-password-as-in-moneymoney.md).

## Reference behavior

### Observed in MoneyMoney 2.5.3

- The "Statements" view shows a grid of PDF statements with the filters "Period", "Status", and "Account" and a button "Settings for Statements". Its sidebar menu has "Settings for Statements...", "Import Statements...", "Show in Finder...", and "Mark All Statements as Read". See [analysis](../../../docs/research/moneymoney-analysis.md#statements-u-s-w) and [context menus](../../../docs/research/moneymoney-analysis.md#context-menus-u).
- Strings show the settings "Automatic download" with "every month", "every two weeks", "on a fixed day" with a day of the month, and "Manual download", and the button "Download now".
- With the monthly setting, the app repeats the download every day until a new statement has arrived. With a fixed day, the download moves to the next possible day when the app is not running on that day. A fixed day keeps the number of two-factor prompts low ([two-factor page](https://moneymoney.app/sca/)).
- The download can be started by hand (version history, 2.3.4). "Every two weeks" is a choice (version history, 2.3.4). A fixed day can be set (version history, 2.3.14).
- Statements are stored as normal files without encryption in the "Statements" folder so that Finder can open them after years ([security page](https://moneymoney.app/security/)).
- Older PDF statements can be imported by drag and drop into the view ([help](https://moneymoney.app/help/)).
- Statements can be assigned to another account through the context menu. Removing an account keeps its PDF statements ([double account page](https://moneymoney.app/help/dual-account/)).
- Strings show the kinds "Account Statement", "Credit Card Statement", and "Portfolio Statement", the states "Read" and "Unread", the commands "Open Statement...", "Delete Statement...", and "Show in Finder", the results for new and for no new PDF statements, and errors for a file that is not a PDF, for a PDF that could not be generated from an MT940 or a text statement, and for a storage folder that cannot be written.
- FinTS messages show that the app acknowledges a fetched statement, that a bank can require an authorization for the download, and that a bank may not provide statements for an account.
- The context menu of a statement includes the macOS Services menu (version history, 2.3.0).
- The [web banking API](https://moneymoney.app/api/webbanking/) lets an extension return documents with an identifier, a name, a file name, a creation date, and an account, also inside a ZIP archive.
- Banks often need an application before they deliver statements through FinTS ([statements page](https://moneymoney.app/statements/)).

### Decided for Moneten

- Statements come only through the access of the account, which is FinTS or an extension. MoneyMoney can also fetch them from a bank website with built-in scripts and offers "Download from" for that. Moneten has no built-in scripts.
- A due download that needs a TAN does not prompt during an automatic refresh. It waits for the next refresh that the user starts. This follows issue #40.
- The grid is sorted by statement date, newest first. The grouping in MoneyMoney was not observed in detail.
- The file name pattern and the folder levels below "Statements" are defined here. MoneyMoney's pattern was not observed.
- The user can mark a statement as unread again. Only the state labels were observed.
- After an account is removed, its statements stay in the view without an account. Only the fact that the files stay was observed.
- An imported PDF takes its date from the user, with the creation date of the file as the default.
