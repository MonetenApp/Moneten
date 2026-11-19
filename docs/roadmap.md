# Roadmap

This page lists what ships in each release. The specs in [openspec/changes](../openspec/changes/) define the behavior. The GitHub issues track the work. Run `python3 scripts/roadmap.py` to regenerate this page from both.

The project has 54 changes with 1266 requirements. A change leaves this page when its code is merged and the change is archived into [openspec/specs](../openspec/specs/).

## v0.1 Read

Fetch, categorize, and understand your money. Read-only.

**Done when.** A user adds a German bank through FinTS with pushTAN, fetches 90 days of transactions, categorizes them with rules, sees charts, imports their MoneyMoney data, and installs three published MoneyMoney extensions from the signed catalog and runs them unchanged, in a notarized build.

### Specs

| Change | Capability | Requirements | Issues |
|---|---|---|---|
| [add-account-management](../openspec/changes/add-account-management/proposal.md) | `account-management` | 27 | [#3](https://github.com/MonetenApp/Moneten/issues/3), [#5](https://github.com/MonetenApp/Moneten/issues/5) |
| [add-account-refresh](../openspec/changes/add-account-refresh/proposal.md) | `account-refresh` | 32 | [#6](https://github.com/MonetenApp/Moneten/issues/6), [#7](https://github.com/MonetenApp/Moneten/issues/7), [#40](https://github.com/MonetenApp/Moneten/issues/40), [#85](https://github.com/MonetenApp/Moneten/issues/85) |
| [add-account-setup](../openspec/changes/add-account-setup/proposal.md) | `account-setup` | 31 | [#5](https://github.com/MonetenApp/Moneten/issues/5), [#13](https://github.com/MonetenApp/Moneten/issues/13), [#85](https://github.com/MonetenApp/Moneten/issues/85), [#230](https://github.com/MonetenApp/Moneten/issues/230) |
| [add-app-lock](../openspec/changes/add-app-lock/proposal.md) | `app-lock` | 27 | [#4](https://github.com/MonetenApp/Moneten/issues/4), [#26](https://github.com/MonetenApp/Moneten/issues/26), [#419](https://github.com/MonetenApp/Moneten/issues/419), [#421](https://github.com/MonetenApp/Moneten/issues/421) |
| [add-app-settings](../openspec/changes/add-app-settings/proposal.md) | `app-settings` | 8 | [#5](https://github.com/MonetenApp/Moneten/issues/5) |
| [add-categories](../openspec/changes/add-categories/proposal.md) | `categories` | 23 | [#18](https://github.com/MonetenApp/Moneten/issues/18) |
| [add-categorization-rules](../openspec/changes/add-categorization-rules/proposal.md) | `categorization-rules` | 34 | [#19](https://github.com/MonetenApp/Moneten/issues/19) |
| [add-charts](../openspec/changes/add-charts/proposal.md) | `charts` | 30 | [#21](https://github.com/MonetenApp/Moneten/issues/21) |
| [add-connection-security](../openspec/changes/add-connection-security/proposal.md) | `connection-security` | 14 | [#13](https://github.com/MonetenApp/Moneten/issues/13), [#26](https://github.com/MonetenApp/Moneten/issues/26) |
| [add-crash-reports](../openspec/changes/add-crash-reports/proposal.md) | `crash-reports` | 6 | [#224](https://github.com/MonetenApp/Moneten/issues/224) |
| [add-data-export](../openspec/changes/add-data-export/proposal.md) | `transaction-export` | 21 | [#8](https://github.com/MonetenApp/Moneten/issues/8) |
| [add-data-folder-and-backup](../openspec/changes/add-data-folder-and-backup/proposal.md) | `data-folder-and-backup` | 15 | [#4](https://github.com/MonetenApp/Moneten/issues/4), [#422](https://github.com/MonetenApp/Moneten/issues/422) |
| [add-encrypted-database](../openspec/changes/add-encrypted-database/proposal.md) | `database-encryption` | 25 | [#2](https://github.com/MonetenApp/Moneten/issues/2), [#4](https://github.com/MonetenApp/Moneten/issues/4), [#26](https://github.com/MonetenApp/Moneten/issues/26), [#335](https://github.com/MonetenApp/Moneten/issues/335) |
| [add-extension-developer-tools](../openspec/changes/add-extension-developer-tools/proposal.md) | `extension-developer-tools` | 19 | [#16](https://github.com/MonetenApp/Moneten/issues/16), [#17](https://github.com/MonetenApp/Moneten/issues/17), [#105](https://github.com/MonetenApp/Moneten/issues/105) |
| [add-file-import](../openspec/changes/add-file-import/proposal.md) | `transaction-import` | 38 | [#22](https://github.com/MonetenApp/Moneten/issues/22), [#23](https://github.com/MonetenApp/Moneten/issues/23) |
| [add-fints-banking](../openspec/changes/add-fints-banking/proposal.md) | `fints-banking` | 51 | [#9](https://github.com/MonetenApp/Moneten/issues/9), [#10](https://github.com/MonetenApp/Moneten/issues/10), [#11](https://github.com/MonetenApp/Moneten/issues/11), [#12](https://github.com/MonetenApp/Moneten/issues/12), [#13](https://github.com/MonetenApp/Moneten/issues/13), [#230](https://github.com/MonetenApp/Moneten/issues/230), [#235](https://github.com/MonetenApp/Moneten/issues/235) |
| [add-localization-and-formatting](../openspec/changes/add-localization-and-formatting/proposal.md) | `localization-and-formatting` | 22 | [#5](https://github.com/MonetenApp/Moneten/issues/5) |
| [add-login-credentials](../openspec/changes/add-login-credentials/proposal.md) | `login-credentials` | 15 | [#4](https://github.com/MonetenApp/Moneten/issues/4), [#13](https://github.com/MonetenApp/Moneten/issues/13), [#26](https://github.com/MonetenApp/Moneten/issues/26) |
| [add-main-window](../openspec/changes/add-main-window/proposal.md) | `main-window` | 31 | [#5](https://github.com/MonetenApp/Moneten/issues/5) |
| [add-moneymoney-migration](../openspec/changes/add-moneymoney-migration/proposal.md) | `moneymoney-migration` | 26 | [#24](https://github.com/MonetenApp/Moneten/issues/24) |
| [add-notifications-and-menu-bar](../openspec/changes/add-notifications-and-menu-bar/proposal.md) | `notifications-and-menu-bar` | 17 | [#40](https://github.com/MonetenApp/Moneten/issues/40) |
| [add-offline-accounts](../openspec/changes/add-offline-accounts/proposal.md) | `offline-accounts` | 21 | [#5](https://github.com/MonetenApp/Moneten/issues/5) |
| [add-securities-accounts](../openspec/changes/add-securities-accounts/proposal.md) | `securities-accounts` | 23 | [#31](https://github.com/MonetenApp/Moneten/issues/31) |
| [add-software-update](../openspec/changes/add-software-update/proposal.md) | `software-update` | 26 | [#25](https://github.com/MonetenApp/Moneten/issues/25), [#13](https://github.com/MonetenApp/Moneten/issues/13), [#411](https://github.com/MonetenApp/Moneten/issues/411) |
| [add-split-transactions](../openspec/changes/add-split-transactions/proposal.md) | `split-transactions` | 20 | [#39](https://github.com/MonetenApp/Moneten/issues/39) |
| [add-tan-handling](../openspec/changes/add-tan-handling/proposal.md) | `tan-handling` | 33 | [#13](https://github.com/MonetenApp/Moneten/issues/13) |
| [add-transaction-list](../openspec/changes/add-transaction-list/proposal.md) | `transaction-list` | 23 | [#5](https://github.com/MonetenApp/Moneten/issues/5) |
| [add-transaction-search-and-filters](../openspec/changes/add-transaction-search-and-filters/proposal.md) | `transaction-search-and-filters` | 26 | [#20](https://github.com/MonetenApp/Moneten/issues/20) |
| [add-web-banking-extensions](../openspec/changes/add-web-banking-extensions/proposal.md) | `web-banking-extensions` | 102 | [#14](https://github.com/MonetenApp/Moneten/issues/14), [#15](https://github.com/MonetenApp/Moneten/issues/15), [#26](https://github.com/MonetenApp/Moneten/issues/26), [#42](https://github.com/MonetenApp/Moneten/issues/42) |

### Issues

| Issue | Labels | Depends on |
|---|---|---|
| [#4 Build the encrypted store, migrations, and Keychain access](https://github.com/MonetenApp/Moneten/issues/4) | area: foundation | #2, #3 |
| [#5 Build the app shell with sidebar, transaction list, and settings](https://github.com/MonetenApp/Moneten/issues/5) | area: core | #4 |
| [#11 Run the first FinTS bank tests](https://github.com/MonetenApp/Moneten/issues/11) | area: fints, kind: prototype | #9 |
| [#18 Add categories with a tree and manual assignment](https://github.com/MonetenApp/Moneten/issues/18) | area: core | #5 |
| [#19 Categorize new transactions with rules](https://github.com/MonetenApp/Moneten/issues/19) | area: core | #18 |
| [#20 Search and filter transactions](https://github.com/MonetenApp/Moneten/issues/20) | area: core | #5 |
| [#21 Show balance history and spending by category](https://github.com/MonetenApp/Moneten/issues/21) | area: core | #18 |
| [#23 Import CAMT.053 and MT940 files](https://github.com/MonetenApp/Moneten/issues/23) | area: import | #7 |
| [#25 Sign, notarize, and update the app with Sparkle](https://github.com/MonetenApp/Moneten/issues/25) | area: release | #1 |
| [#531 Migrated accounts: the Connect button is too hard to see](https://github.com/MonetenApp/Moneten/issues/531) | bug | None |

## v0.2 Pay

Send the first SEPA transfer and see securities accounts.

**Done when.** A user sends a SEPA transfer through FinTS, sees the payee check result before confirming, approves with a TAN, and sees the holdings of a securities account.

### Specs

| Change | Capability | Requirements | Issues |
|---|---|---|---|
| [add-sepa-transfers](../openspec/changes/add-sepa-transfers/proposal.md) | `account-refresh`, `main-window`, `sepa-transfers`, `tan-handling` | 39 | [#27](https://github.com/MonetenApp/Moneten/issues/27), [#28](https://github.com/MonetenApp/Moneten/issues/28), [#29](https://github.com/MonetenApp/Moneten/issues/29), [#30](https://github.com/MonetenApp/Moneten/issues/30), [#32](https://github.com/MonetenApp/Moneten/issues/32) |
| [defer-v0.1-follow-ups](../openspec/changes/defer-v0.1-follow-ups/proposal.md) | `account-setup`, `securities-accounts` | 7 | [#226](https://github.com/MonetenApp/Moneten/issues/226) |

### Issues

| Issue | Labels | Depends on |
|---|---|---|
| [#27 Check the payee with Verification of Payee](https://github.com/MonetenApp/Moneten/issues/27) | area: payments | #13 |
| [#28 Send a SEPA transfer through FinTS](https://github.com/MonetenApp/Moneten/issues/28) | area: payments | #27 |
| [#29 Build the transfer form and review screen](https://github.com/MonetenApp/Moneten/issues/29) | area: payments | #28 |
| [#30 Send instant transfers where the bank supports them](https://github.com/MonetenApp/Moneten/issues/30) | area: payments | #28 |
| [#32 Review payment security before the v0.2 release](https://github.com/MonetenApp/Moneten/issues/32) | area: release | #28, #30 |
| [#478 Account settings: no tab "Account owner", and the owner and the bank name cannot be changed](https://github.com/MonetenApp/Moneten/issues/478) | bug, area: core | None |
| [#519 Perf: group-by-account and the stall after Cancel exceed the budget](https://github.com/MonetenApp/Moneten/issues/519) | performance | None |

## v0.3 Connect

Connect banks without FinTS through an optional subscription.

**Done when.** A subscriber connects a bank through finAPI and fetches transactions. Every v0.1 and v0.2 feature still works without a subscription.

### Specs

| Change | Capability | Requirements | Issues |
|---|---|---|---|
| [add-aggregator-subscription](../openspec/changes/add-aggregator-subscription/proposal.md) | `aggregator-subscription` | 20 | [#33](https://github.com/MonetenApp/Moneten/issues/33), [#34](https://github.com/MonetenApp/Moneten/issues/34), [#35](https://github.com/MonetenApp/Moneten/issues/35), [#36](https://github.com/MonetenApp/Moneten/issues/36), [#38](https://github.com/MonetenApp/Moneten/issues/38) |

### Issues

| Issue | Labels | Depends on |
|---|---|---|
| [#33 Get written license confirmation and prices from finAPI](https://github.com/MonetenApp/Moneten/issues/33) | area: service, kind: organization | None |
| [#34 Set up the company that runs the subscription](https://github.com/MonetenApp/Moneten/issues/34) | area: service, kind: organization | #33 |
| [#35 Build the subscription service in a separate repository](https://github.com/MonetenApp/Moneten/issues/35) | area: service | #34 |
| [#36 Build the finAPI connector](https://github.com/MonetenApp/Moneten/issues/36) | area: service | #35, #6 |
| [#38 Review the subscription service security before launch](https://github.com/MonetenApp/Moneten/issues/38) | area: service, area: release | #36, #37 |
| [#44 Prototype YAXI as a bank access next to FinTS and finAPI](https://github.com/MonetenApp/Moneten/issues/44) | area: service, kind: prototype | #6 |

## Later

These changes have a spec and no release yet.

| Change | Capability | Requirements |
|---|---|---|
| [add-account-extras](../openspec/changes/add-account-extras/proposal.md) | `account-management` | 15 |
| [add-applescript-automation](../openspec/changes/add-applescript-automation/proposal.md) | `applescript-automation` | 22 |
| [add-bank-statements](../openspec/changes/add-bank-statements/proposal.md) | `bank-statements`, `notifications-and-menu-bar` | 29 |
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
| [add-payment-outbox](../openspec/changes/add-payment-outbox/proposal.md) | `payment-outbox`, `split-transactions` | 37 |
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
