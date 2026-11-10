# Roadmap

This page lists what ships in each release. The specs in [openspec/changes](../openspec/changes/) define the behavior. The GitHub issues track the work. Run `python3 scripts/roadmap.py` to regenerate this page from both.

The project has 53 changes with 1086 requirements. A change leaves this page when its code is merged and the change is archived into [openspec/specs](../openspec/specs/).

## v0.1 Read

Fetch, categorize, and understand your money. Read-only.

**Done when.** A user adds a German bank through FinTS with pushTAN, fetches 90 days of transactions, categorizes them with rules, sees charts, imports their MoneyMoney data, and runs three published MoneyMoney extensions unchanged, in a notarized build.

### Specs

| Change | Capability | Requirements | Issues |
|---|---|---|---|
| [add-account-management](../openspec/changes/add-account-management/proposal.md) | `account-management` | 21 | [#3](https://github.com/alexander-schneider/MonetenMoneten/issues/3), [#5](https://github.com/alexander-schneider/MonetenMoneten/issues/5) |
| [add-account-refresh](../openspec/changes/add-account-refresh/proposal.md) | `account-refresh` | 29 | [#6](https://github.com/alexander-schneider/MonetenMoneten/issues/6), [#7](https://github.com/alexander-schneider/MonetenMoneten/issues/7), [#40](https://github.com/alexander-schneider/MonetenMoneten/issues/40) |
| [add-account-setup](../openspec/changes/add-account-setup/proposal.md) | `account-setup` | 21 | [#5](https://github.com/alexander-schneider/MonetenMoneten/issues/5), [#13](https://github.com/alexander-schneider/MonetenMoneten/issues/13) |
| [add-app-lock](../openspec/changes/add-app-lock/proposal.md) | `app-lock` | 21 | [#4](https://github.com/alexander-schneider/MonetenMoneten/issues/4), [#26](https://github.com/alexander-schneider/MonetenMoneten/issues/26) |
| [add-app-settings](../openspec/changes/add-app-settings/proposal.md) | `app-settings` | 8 | [#5](https://github.com/alexander-schneider/MonetenMoneten/issues/5) |
| [add-categories](../openspec/changes/add-categories/proposal.md) | `categories` | 20 | [#18](https://github.com/alexander-schneider/MonetenMoneten/issues/18) |
| [add-categorization-rules](../openspec/changes/add-categorization-rules/proposal.md) | `categorization-rules` | 18 | [#19](https://github.com/alexander-schneider/MonetenMoneten/issues/19) |
| [add-charts](../openspec/changes/add-charts/proposal.md) | `charts` | 20 | [#21](https://github.com/alexander-schneider/MonetenMoneten/issues/21) |
| [add-connection-security](../openspec/changes/add-connection-security/proposal.md) | `connection-security` | 14 | [#13](https://github.com/alexander-schneider/MonetenMoneten/issues/13), [#26](https://github.com/alexander-schneider/MonetenMoneten/issues/26) |
| [add-data-export](../openspec/changes/add-data-export/proposal.md) | `transaction-export` | 17 | [#8](https://github.com/alexander-schneider/MonetenMoneten/issues/8) |
| [add-data-folder-and-backup](../openspec/changes/add-data-folder-and-backup/proposal.md) | `data-folder-and-backup` | 13 | [#4](https://github.com/alexander-schneider/MonetenMoneten/issues/4) |
| [add-encrypted-database](../openspec/changes/add-encrypted-database/proposal.md) | `database-encryption` | 20 | [#2](https://github.com/alexander-schneider/MonetenMoneten/issues/2), [#4](https://github.com/alexander-schneider/MonetenMoneten/issues/4), [#26](https://github.com/alexander-schneider/MonetenMoneten/issues/26) |
| [add-extension-developer-tools](../openspec/changes/add-extension-developer-tools/proposal.md) | `extension-developer-tools` | 17 | [#16](https://github.com/alexander-schneider/MonetenMoneten/issues/16), [#17](https://github.com/alexander-schneider/MonetenMoneten/issues/17) |
| [add-file-import](../openspec/changes/add-file-import/proposal.md) | `transaction-import` | 24 | [#22](https://github.com/alexander-schneider/MonetenMoneten/issues/22), [#23](https://github.com/alexander-schneider/MonetenMoneten/issues/23) |
| [add-fints-banking](../openspec/changes/add-fints-banking/proposal.md) | `fints-banking` | 25 | [#9](https://github.com/alexander-schneider/MonetenMoneten/issues/9), [#10](https://github.com/alexander-schneider/MonetenMoneten/issues/10), [#11](https://github.com/alexander-schneider/MonetenMoneten/issues/11), [#12](https://github.com/alexander-schneider/MonetenMoneten/issues/12), [#13](https://github.com/alexander-schneider/MonetenMoneten/issues/13) |
| [add-localization-and-formatting](../openspec/changes/add-localization-and-formatting/proposal.md) | `localization-and-formatting` | 18 | [#5](https://github.com/alexander-schneider/MonetenMoneten/issues/5) |
| [add-login-credentials](../openspec/changes/add-login-credentials/proposal.md) | `login-credentials` | 15 | [#4](https://github.com/alexander-schneider/MonetenMoneten/issues/4), [#13](https://github.com/alexander-schneider/MonetenMoneten/issues/13), [#26](https://github.com/alexander-schneider/MonetenMoneten/issues/26) |
| [add-main-window](../openspec/changes/add-main-window/proposal.md) | `main-window` | 28 | [#5](https://github.com/alexander-schneider/MonetenMoneten/issues/5) |
| [add-moneymoney-migration](../openspec/changes/add-moneymoney-migration/proposal.md) | `moneymoney-migration` | 17 | [#24](https://github.com/alexander-schneider/MonetenMoneten/issues/24) |
| [add-notifications-and-menu-bar](../openspec/changes/add-notifications-and-menu-bar/proposal.md) | `notifications-and-menu-bar` | 16 | [#40](https://github.com/alexander-schneider/MonetenMoneten/issues/40) |
| [add-offline-accounts](../openspec/changes/add-offline-accounts/proposal.md) | `offline-accounts` | 13 | [#5](https://github.com/alexander-schneider/MonetenMoneten/issues/5) |
| [add-software-update](../openspec/changes/add-software-update/proposal.md) | `software-update` | 19 | [#25](https://github.com/alexander-schneider/MonetenMoneten/issues/25) |
| [add-split-transactions](../openspec/changes/add-split-transactions/proposal.md) | `split-transactions` | 15 | [#39](https://github.com/alexander-schneider/MonetenMoneten/issues/39) |
| [add-tan-handling](../openspec/changes/add-tan-handling/proposal.md) | `tan-handling` | 28 | [#13](https://github.com/alexander-schneider/MonetenMoneten/issues/13) |
| [add-transaction-list](../openspec/changes/add-transaction-list/proposal.md) | `transaction-list` | 20 | [#5](https://github.com/alexander-schneider/MonetenMoneten/issues/5) |
| [add-transaction-search-and-filters](../openspec/changes/add-transaction-search-and-filters/proposal.md) | `transaction-search-and-filters` | 21 | [#20](https://github.com/alexander-schneider/MonetenMoneten/issues/20) |
| [add-web-banking-extensions](../openspec/changes/add-web-banking-extensions/proposal.md) | `web-banking-extensions` | 79 | [#14](https://github.com/alexander-schneider/MonetenMoneten/issues/14), [#15](https://github.com/alexander-schneider/MonetenMoneten/issues/15), [#26](https://github.com/alexander-schneider/MonetenMoneten/issues/26) |

### Issues

| Issue | Labels | Depends on |
|---|---|---|
| [#1 Set up the Swift package and CI](https://github.com/alexander-schneider/MonetenMoneten/issues/1) | area: foundation | None |
| [#2 Prototype GRDB with SQLCipher through Swift Package Manager](https://github.com/alexander-schneider/MonetenMoneten/issues/2) | area: foundation, kind: prototype | None |
| [#3 Define the core domain types](https://github.com/alexander-schneider/MonetenMoneten/issues/3) | area: foundation | #1 |
| [#4 Build the encrypted store, migrations, and Keychain access](https://github.com/alexander-schneider/MonetenMoneten/issues/4) | area: foundation | #2, #3 |
| [#5 Build the app shell with sidebar, transaction list, and settings](https://github.com/alexander-schneider/MonetenMoneten/issues/5) | area: core | #4 |
| [#6 Define BankConnector, SyncSession, Challenge, and the sync state machine](https://github.com/alexander-schneider/MonetenMoneten/issues/6) | area: foundation | #3 |
| [#7 De-duplicate transactions and reconcile pending rows with booked rows](https://github.com/alexander-schneider/MonetenMoneten/issues/7) | area: core | #3 |
| [#8 Export and re-import all data as JSON, and export CSV](https://github.com/alexander-schneider/MonetenMoneten/issues/8) | area: core | #4 |
| [#9 Apply for FinTS product registration](https://github.com/alexander-schneider/MonetenMoneten/issues/9) | area: fints, kind: organization | None |
| [#10 Ask the HBCI4Swift author about a joint Swift package](https://github.com/alexander-schneider/MonetenMoneten/issues/10) | area: fints, kind: organization | None |
| [#11 Prototype HBCI4Swift against three banks](https://github.com/alexander-schneider/MonetenMoneten/issues/11) | area: fints, kind: prototype | None |
| [#12 Turn HBCI4Swift into a tested Swift package](https://github.com/alexander-schneider/MonetenMoneten/issues/12) | area: fints | #11, #10 |
| [#13 Build the FinTS connector for accounts, balances, and transactions](https://github.com/alexander-schneider/MonetenMoneten/issues/13) | area: fints | #12, #6, #7, #9 |
| [#14 Run Lua 5.4 extensions in a sandboxed XPC process](https://github.com/alexander-schneider/MonetenMoneten/issues/14) | area: extensions | #6 |
| [#15 Implement the MoneyMoney-compatible extension API](https://github.com/alexander-schneider/MonetenMoneten/issues/15) | area: extensions | #14 |
| [#16 Build the ext command line tool with record and replay](https://github.com/alexander-schneider/MonetenMoneten/issues/16) | area: extensions | #15 |
| [#17 Write the extension author guide](https://github.com/alexander-schneider/MonetenMoneten/issues/17) | area: extensions | #16 |
| [#18 Add categories with a tree and manual assignment](https://github.com/alexander-schneider/MonetenMoneten/issues/18) | area: core | #5 |
| [#19 Categorize new transactions with rules](https://github.com/alexander-schneider/MonetenMoneten/issues/19) | area: core | #18 |
| [#20 Search and filter transactions](https://github.com/alexander-schneider/MonetenMoneten/issues/20) | area: core | #5 |
| [#21 Show balance history and spending by category](https://github.com/alexander-schneider/MonetenMoneten/issues/21) | area: core | #18 |
| [#22 Import CSV files with saved column profiles](https://github.com/alexander-schneider/MonetenMoneten/issues/22) | area: import | #7, #5 |
| [#23 Import CAMT.053 and MT940 files](https://github.com/alexander-schneider/MonetenMoneten/issues/23) | area: import | #7 |
| [#24 Migrate accounts, transactions, and categories from MoneyMoney](https://github.com/alexander-schneider/MonetenMoneten/issues/24) | area: import | #18, #23 |
| [#25 Sign, notarize, and update the app with Sparkle](https://github.com/alexander-schneider/MonetenMoneten/issues/25) | area: release | #1 |
| [#26 Review security before the first public release](https://github.com/alexander-schneider/MonetenMoneten/issues/26) | area: release | #13, #15, #25 |
| [#39 Split a transaction across several categories](https://github.com/alexander-schneider/MonetenMoneten/issues/39) | area: core | #18 |
| [#40 Refresh accounts automatically and notify about new transactions](https://github.com/alexander-schneider/MonetenMoneten/issues/40) | area: core | #13, #5 |
| [#42 Run the YAXI extension for MoneyMoney unchanged as a compatibility test](https://github.com/alexander-schneider/MonetenMoneten/issues/42) | area: extensions | #14, #15, #16, #43 |
| [#43 Check whether MoneyMoney sends payments through extensions](https://github.com/alexander-schneider/MonetenMoneten/issues/43) | area: extensions, area: payments, kind: prototype | None |

## v0.2 Pay

Send the first SEPA transfer and see securities accounts.

**Done when.** A user sends a SEPA transfer through FinTS, sees the payee check result before confirming, approves with a TAN, and sees the holdings of a securities account.

### Specs

| Change | Capability | Requirements | Issues |
|---|---|---|---|
| [add-securities-accounts](../openspec/changes/add-securities-accounts/proposal.md) | `securities-accounts` | 24 | [#31](https://github.com/alexander-schneider/MonetenMoneten/issues/31) |
| [add-sepa-transfers](../openspec/changes/add-sepa-transfers/proposal.md) | `sepa-transfers` | 36 | [#27](https://github.com/alexander-schneider/MonetenMoneten/issues/27), [#28](https://github.com/alexander-schneider/MonetenMoneten/issues/28), [#29](https://github.com/alexander-schneider/MonetenMoneten/issues/29), [#30](https://github.com/alexander-schneider/MonetenMoneten/issues/30), [#32](https://github.com/alexander-schneider/MonetenMoneten/issues/32) |

### Issues

| Issue | Labels | Depends on |
|---|---|---|
| [#27 Check the payee with Verification of Payee](https://github.com/alexander-schneider/MonetenMoneten/issues/27) | area: payments | #13 |
| [#28 Send a SEPA transfer through FinTS](https://github.com/alexander-schneider/MonetenMoneten/issues/28) | area: payments | #27 |
| [#29 Build the transfer form and review screen](https://github.com/alexander-schneider/MonetenMoneten/issues/29) | area: payments | #28 |
| [#30 Send instant transfers where the bank supports them](https://github.com/alexander-schneider/MonetenMoneten/issues/30) | area: payments | #28 |
| [#31 Read securities accounts through FinTS](https://github.com/alexander-schneider/MonetenMoneten/issues/31) | area: fints | #13 |
| [#32 Review payment security before the v0.2 release](https://github.com/alexander-schneider/MonetenMoneten/issues/32) | area: release | #28, #30 |

## v0.3 Connect

Connect banks without FinTS through an optional subscription, and install extensions from a catalog.

**Done when.** A subscriber connects a bank through finAPI and fetches transactions, and a user installs and updates extensions from a signed catalog. Every v0.1 and v0.2 feature still works without a subscription.

### Specs

| Change | Capability | Requirements | Issues |
|---|---|---|---|
| [add-aggregator-subscription](../openspec/changes/add-aggregator-subscription/proposal.md) | `aggregator-subscription` | 20 | [#33](https://github.com/alexander-schneider/MonetenMoneten/issues/33), [#34](https://github.com/alexander-schneider/MonetenMoneten/issues/34), [#35](https://github.com/alexander-schneider/MonetenMoneten/issues/35), [#36](https://github.com/alexander-schneider/MonetenMoneten/issues/36), [#38](https://github.com/alexander-schneider/MonetenMoneten/issues/38) |
| [add-extension-catalog](../openspec/changes/add-extension-catalog/proposal.md) | `extension-catalog` | 17 | [#37](https://github.com/alexander-schneider/MonetenMoneten/issues/37) |

### Issues

| Issue | Labels | Depends on |
|---|---|---|
| [#33 Get written license confirmation and prices from finAPI](https://github.com/alexander-schneider/MonetenMoneten/issues/33) | area: service, kind: organization | None |
| [#34 Set up the company that runs the subscription](https://github.com/alexander-schneider/MonetenMoneten/issues/34) | area: service, kind: organization | #33 |
| [#35 Build the subscription service in a separate repository](https://github.com/alexander-schneider/MonetenMoneten/issues/35) | area: service | #34 |
| [#36 Build the finAPI connector](https://github.com/alexander-schneider/MonetenMoneten/issues/36) | area: service | #35, #6 |
| [#37 Install and update extensions from a signed catalog](https://github.com/alexander-schneider/MonetenMoneten/issues/37) | area: extensions | #15 |
| [#38 Review the subscription service security before launch](https://github.com/alexander-schneider/MonetenMoneten/issues/38) | area: service, area: release | #36, #37 |
| [#44 Prototype YAXI as a bank access next to FinTS and finAPI](https://github.com/alexander-schneider/MonetenMoneten/issues/44) | area: service, kind: prototype | #6 |

## Later

These changes have a spec and no release yet.

| Change | Capability | Requirements |
|---|---|---|
| [add-account-extras](../openspec/changes/add-account-extras/proposal.md) | `account-management` | 15 |
| [add-applescript-automation](../openspec/changes/add-applescript-automation/proposal.md) | `applescript-automation` | 22 |
| [add-bank-statements](../openspec/changes/add-bank-statements/proposal.md) | `bank-statements` | 28 |
| [add-budgets](../openspec/changes/add-budgets/proposal.md) | `budgets` | 12 |
| [add-certificate-pinning](../openspec/changes/add-certificate-pinning/proposal.md) | `connection-security` | 11 |
| [add-dashboard](../openspec/changes/add-dashboard/proposal.md) | `dashboard` | 14 |
| [add-direct-debits](../openspec/changes/add-direct-debits/proposal.md) | `direct-debits` | 36 |
| [add-foreign-currency-transfers](../openspec/changes/add-foreign-currency-transfers/proposal.md) | `foreign-currency-transfers` | 22 |
| [add-hbci-keys-and-chipcards](../openspec/changes/add-hbci-keys-and-chipcards/proposal.md) | `hbci-keys-and-chipcards` | 21 |
| [add-import-export-extensions](../openspec/changes/add-import-export-extensions/proposal.md) | `import-export-extensions` | 19 |
| [add-log-and-diagnostics](../openspec/changes/add-log-and-diagnostics/proposal.md) | `log-and-diagnostics` | 17 |
| [add-more-export-formats](../openspec/changes/add-more-export-formats/proposal.md) | `transaction-export` | 13 |
| [add-more-import-formats](../openspec/changes/add-more-import-formats/proposal.md) | `transaction-import` | 9 |
| [add-payment-outbox](../openspec/changes/add-payment-outbox/proposal.md) | `payment-outbox` | 36 |
| [add-payment-templates](../openspec/changes/add-payment-templates/proposal.md) | `payment-templates` | 22 |
| [add-pin-management](../openspec/changes/add-pin-management/proposal.md) | `pin-management` | 13 |
| [add-portfolio-analysis](../openspec/changes/add-portfolio-analysis/proposal.md) | `securities-accounts` | 13 |
| [add-printing](../openspec/changes/add-printing/proposal.md) | `printing` | 23 |
| [add-reports](../openspec/changes/add-reports/proposal.md) | `reports` | 19 |
| [add-scheduled-payments](../openspec/changes/add-scheduled-payments/proposal.md) | `scheduled-payments` | 29 |
| [add-tan-generator-devices](../openspec/changes/add-tan-generator-devices/proposal.md) | `tan-handling` | 9 |
| [add-transfer-conveniences](../openspec/changes/add-transfer-conveniences/proposal.md) | `sepa-transfers` | 9 |

## Ideas without a spec

- Sync between your Macs through iCloud.
- An app for iPhone and iPad that reuses the `Domain`, `Storage`, and connector packages.
