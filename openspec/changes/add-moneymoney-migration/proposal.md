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

### Decided for Moneten

- The whole capability is specific to Moneten. Its scope comes from issue #24.
- The keys of the property lists are not documented on the website. Before the design starts, record a real export from a test database and fix the field mapping against it.
- Issue #24 expects that rules cannot be migrated. The plan for this change expects that they can. The spec migrates a rule when the category export contains it and lists it in the report when it does not. A real export, checked on 2026-11-10, contains the rules.
- A migrated rule keeps its text. The app reads the operators in any letter case, so `"Lohn" or "Gehalt"` means either word, as its author most likely meant. The help of the source asks for AND, OR, and NOT in capitals, so there a rule with a lower case or searches the word or. The report names each rule with such a word, so that the user can check that the new meaning is the intended one. A rule that the app cannot read stays as text, and the report names its category and the error. The user must know which category no longer fills by itself.
- A term without a field operator does not search account numbers in the app. A migrated rule with an IBAN or an account number as such a term then no longer finds transactions by their account, also when the rule has words besides the number, so the report names it and says that `remote_account:` searches the account of the counterparty. A number counts as an account number only when a migrated account or counterparty has it, so that a customer number in a rule does not fill the report. The app does not rewrite the rule, because only the user knows whether the number meant the own account or the counterparty.
- The report says what happens with budgets and icons. Until the app supports budgets, the report counts the categories with a budget and says that the app did not take them over. It promises no later step, because no change plans a migration of budgets yet. Icons are not taken over as pictures. The app takes their color and draws its own icons, and the report says so.
- A migrated account counts its pending transactions on top of the balance of the source, as every account does, so it shows what is left after them. The report compares the balance without pending transactions with the balance of the source, because the source reports its balance without them. A difference in the report then always means that something did not come over.
- Migrated accounts start as accounts without a bank access, because login data cannot be read. The add account assistant attaches a bank access to a migrated account when the IBAN or account number fits.
- The source shows the balance of an account without its pending transactions. The app counts pending transactions on top, as for a refreshed account and as the change `add-charts` decides. An account with pending transactions therefore shows a different balance than in the source.
- Portfolio accounts are migrated as accounts. Their positions follow when securities accounts are available in v0.2.
- A split transaction arrives as MoneyMoney exports it. If the export lists the parts as separate transactions, the app keeps them as separate transactions and says so in the report.
- The command is in the File menu and in the empty state of a new database.
- The label of the command is "Import from MoneyMoney...". The spec does not quote it, because a requirement does not name the product.
