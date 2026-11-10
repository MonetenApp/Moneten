# Proposal: Migrate accounts, categories, and transactions from MoneyMoney

## Why

Most early users come from MoneyMoney and have years of categorized transactions there. Banks deliver only a short history, so that work cannot be fetched again. Switching must take minutes. If it means losing the history, nobody switches.

## What Changes

- A command "Import from MoneyMoney..." reads the data of a running, unlocked MoneyMoney through its documented AppleScript export commands.
- The app shows a summary of what it found before it stores anything.
- The app creates the account groups, accounts, categories, and transactions, with each transaction's category, comment, and checkmark.
- A report lists what was migrated and what could not be.
- A second run adds only what is new.
- A migrated account is connected to its bank later without losing its history.
- Nothing in MoneyMoney is changed.

## Capabilities

### New Capabilities

- `moneymoney-migration`: reading accounts, categories, and transactions from a MoneyMoney installation into the app, with a preview, a report, and repeatable runs.

### Modified Capabilities

None.

## Impact

- Milestone: v0.1
- Issues: #24
- Modules: `Import` owns the reader for the property lists and builds an import batch. `App` owns the command, the summary, and the report.
- Depends on the changes `add-categories` and `add-categorization-rules` for the category tree and rules, `add-offline-accounts` for accounts without a bank access, `add-account-refresh` for the rules that decide whether two transactions are the same, and `add-account-setup` for connecting a migrated account to its bank.
- Decisions: [ADR 0004](../../../docs/decisions/0004-moneymoney-compatible-extension-api.md) for the legal basis of using a documented interface.

## Reference behavior

### Observed in MoneyMoney 2.5.3

- MoneyMoney exports accounts, categories, transactions, and portfolio positions as XML property lists through AppleScript. See [analysis](../../../docs/research/moneymoney-analysis.md#applescript-s-w) and the [AppleScript page](https://moneymoney.app/api/applescript/).
- The transaction export takes a start date and an optional account. Each transaction has a numeric ID. Each category has a UUID.
- The scripting dictionary has no command that exports templates, standing orders, statements, or login data.
- The export commands answer only while the database is unlocked.
- PDF statements are plain files in the "Statements" folder of MoneyMoney's data folder ([security page](https://moneymoney.app/security/)).

### Decided for MonetenMoneten

- The whole capability is specific to MonetenMoneten. Its scope comes from issue #24.
- The keys of the property lists are not documented on the website. Before the design starts, record a real export from a test database and fix the field mapping against it.
- Issue #24 expects that rules cannot be migrated. The plan for this change expects that they can. The spec migrates a rule when the category export contains it and lists it in the report when it does not. A real export, checked on 2026-11-10, contains the rules.
- Migrated accounts start as accounts without a bank access, because login data cannot be read. The add account assistant attaches a bank access to a migrated account when the IBAN or account number fits.
- Portfolio accounts are migrated as accounts. Their positions follow when securities accounts are available in v0.2.
- A split transaction arrives as MoneyMoney exports it. If the export lists the parts as separate transactions, the app keeps them as separate transactions and says so in the report.
- The command is in the File menu and in the empty state of a new database.
- The label of the command is "Import from MoneyMoney...". The spec does not quote it, because a requirement does not name the product.
