# MoneyMoney features

This page lists the features of MoneyMoney 2.5.3 and the change that specifies each one for Moneten. It is the checklist for what MoneyMoney users will look for after they switch.

[MoneyMoney analysis](moneymoney-analysis.md) records how the features were found and what the app looks like in detail. The [roadmap](../roadmap.md) lists every change by release.

## How to read the second column

Each entry links to the proposal of a change in [openspec/changes](../../openspec/changes/). The specs of that change define the behavior. The release follows in parentheses.

- **v0.1**, **v0.2**, or **v0.3**. The change is planned for that release.
- **later**. The change has a complete spec and no release yet.
- **No spec.** Moneten does not copy this part. [Not carried over](moneymoney-analysis.md#not-carried-over) explains why.

## Banks and accounts

| Feature | Moneten |
|---|---|
| FinTS with PIN/TAN | [add-fints-banking](../../openspec/changes/add-fints-banking/proposal.md) (v0.1), [add-login-credentials](../../openspec/changes/add-login-credentials/proposal.md) (v0.1) |
| Add an account in three steps, look for new accounts, edit login data | [add-account-setup](../../openspec/changes/add-account-setup/proposal.md) (v0.1) |
| pushTAN, appTAN, photoTAN, chipTAN with QR code or flicker code, smsTAN, and bank-specific methods that follow the FinTS standard | [add-tan-handling](../../openspec/changes/add-tan-handling/proposal.md) (v0.1) |
| USB and Bluetooth TAN generators, TAN generator synchronization, pushTAN activation | [add-tan-generator-devices](../../openspec/changes/add-tan-generator-devices/proposal.md) (later) |
| HBCI chip cards and key files, INI letter, Secoder card readers, chip card PIN and PUK tools | [add-hbci-keys-and-chipcards](../../openspec/changes/add-hbci-keys-and-chipcards/proposal.md) (later) |
| Change the PIN of an online banking access, unblock a PIN with a TAN | [add-pin-management](../../openspec/changes/add-pin-management/proposal.md) (later) |
| PSD2 online service for banks without FinTS. A paid add-on for 39.99 euros per year, read-only, run by MoneyMoney's developer as a BaFin-registered account information service. | [add-aggregator-subscription](../../openspec/changes/add-aggregator-subscription/proposal.md) (v0.3). Moneten uses finAPI instead. |
| Web banking extensions in Lua | [add-web-banking-extensions](../../openspec/changes/add-web-banking-extensions/proposal.md) (v0.1), [add-extension-developer-tools](../../openspec/changes/add-extension-developer-tools/proposal.md) (v0.1) |
| Signature check for extensions. Unsigned extensions run only after you turn the check off. | [add-extension-catalog](../../openspec/changes/add-extension-catalog/proposal.md) (v0.1). Moneten has no signature check setting. The "Extensions" window installs from a reviewed, signed catalog, and an extension from outside the catalog runs after a warning and stays marked "Unverified". |
| More than 6,500 European banks by bank code | German FinTS banks in v0.1. Other banks through extensions and, in v0.3, finAPI. |
| Account types for current, savings, fixed-term, credit card, securities, building society, loan, foreign currency, PayPal, cash, and offline accounts | [add-account-management](../../openspec/changes/add-account-management/proposal.md) (v0.1), [add-offline-accounts](../../openspec/changes/add-offline-accounts/proposal.md) (v0.1). PayPal comes through an extension. |
| Account groups, account settings, closed accounts | [add-account-management](../../openspec/changes/add-account-management/proposal.md) (v0.1) |
| Icons per account, notes, reference accounts, moving transactions to another account, new IBANs after a bank merger | [add-account-extras](../../openspec/changes/add-account-extras/proposal.md) (later) |
| Refresh all accounts or one account, cancel a refresh, refresh automatically at an interval per account | [add-account-refresh](../../openspec/changes/add-account-refresh/proposal.md) (v0.1) |
| Notify and play a sound on new transactions, Dock badge, menu bar icon | [add-notifications-and-menu-bar](../../openspec/changes/add-notifications-and-menu-bar/proposal.md) (v0.1) |
| Log window | [add-log-and-diagnostics](../../openspec/changes/add-log-and-diagnostics/proposal.md) (later) |

## Transactions

| Feature | Moneten |
|---|---|
| Transaction list with details, pending rows shown differently | [add-transaction-list](../../openspec/changes/add-transaction-list/proposal.md) (v0.1) |
| Full history kept on the Mac, beyond the 30 to 450 days a bank returns | [add-account-refresh](../../openspec/changes/add-account-refresh/proposal.md) (v0.1), [add-fints-banking](../../openspec/changes/add-fints-banking/proposal.md) (v0.1) |
| Daily balance in the list | [add-transaction-list](../../openspec/changes/add-transaction-list/proposal.md) (v0.1) |
| Live search with the sum of the results, search for all transactions with the same counterparty, filters for period, status, amount, category, and account | [add-transaction-search-and-filters](../../openspec/changes/add-transaction-search-and-filters/proposal.md) (v0.1) |
| Check off one or all transactions, comments on transactions, edit and delete transactions | [add-transaction-list](../../openspec/changes/add-transaction-list/proposal.md) (v0.1) |
| Manual transactions in offline and cash accounts, offsetting entries | [add-offline-accounts](../../openspec/changes/add-offline-accounts/proposal.md) (v0.1) |
| New transfer from a selected transaction | [add-sepa-transfers](../../openspec/changes/add-sepa-transfers/proposal.md) (v0.2) |
| Print transactions | [add-printing](../../openspec/changes/add-printing/proposal.md) (later) |

## Categories and rules

| Feature | Moneten |
|---|---|
| Categories and category groups | [add-categories](../../openspec/changes/add-categories/proposal.md) (v0.1) |
| Rules that categorize new transactions | [add-categorization-rules](../../openspec/changes/add-categorization-rules/proposal.md) (v0.1) |
| Split a transaction across categories, VAT splits | [add-split-transactions](../../openspec/changes/add-split-transactions/proposal.md) (v0.1) |
| Exclude categories from charts, for example transfers between own accounts | [add-categories](../../openspec/changes/add-categories/proposal.md) (v0.1), [add-charts](../../openspec/changes/add-charts/proposal.md) (v0.1) |
| Take categories over from CSV and QIF files | [add-file-import](../../openspec/changes/add-file-import/proposal.md) (v0.1) for CSV, [add-more-import-formats](../../openspec/changes/add-more-import-formats/proposal.md) (later) for QIF |

## Charts, reports, and budgets

| Feature | Moneten |
|---|---|
| Bar chart of the balance, bar chart of income and spending by month, quarter, or year, pie chart of categories, calibration | [add-charts](../../openspec/changes/add-charts/proposal.md) (v0.1) |
| Account balance report and category report | [add-reports](../../openspec/changes/add-reports/proposal.md) (later) |
| Dashboard | [add-dashboard](../../openspec/changes/add-dashboard/proposal.md) (later) |
| Budgets for categories and category groups | [add-budgets](../../openspec/changes/add-budgets/proposal.md) (later) |

## Securities

| Feature | Moneten |
|---|---|
| Securities accounts with holdings, purchase prices, profit and loss | [add-securities-accounts](../../openspec/changes/add-securities-accounts/proposal.md) (v0.2) |
| Asset classes, portfolio history, export of positions | [add-portfolio-analysis](../../openspec/changes/add-portfolio-analysis/proposal.md) (later) |
| Crypto and other assets through extensions, shown as securities | [add-securities-accounts](../../openspec/changes/add-securities-accounts/proposal.md) (v0.2), [add-web-banking-extensions](../../openspec/changes/add-web-banking-extensions/proposal.md) (v0.1) |

## Payments

| Feature | Moneten |
|---|---|
| SEPA transfer, transfer between own accounts, instant transfer | [add-sepa-transfers](../../openspec/changes/add-sepa-transfers/proposal.md) (v0.2) |
| Verification of Payee. Required by EU law since October 2025. | [add-sepa-transfers](../../openspec/changes/add-sepa-transfers/proposal.md) (v0.2) |
| Recipient suggestions, fill a transfer from bank details on the clipboard or from a GiroCode, cash discount, purpose codes | [add-transfer-conveniences](../../openspec/changes/add-transfer-conveniences/proposal.md) (later) |
| Scheduled transfers, standing orders including change, delete, and refresh from the bank, release of orders from a computing center (SRZ) | [add-scheduled-payments](../../openspec/changes/add-scheduled-payments/proposal.md) (later) |
| Templates, template groups, placeholders in the purpose line, import and export of templates | [add-payment-templates](../../openspec/changes/add-payment-templates/proposal.md) (later) |
| Outbox, and batch transfers from the outbox, a template group, or a SEPA XML file | [add-payment-outbox](../../openspec/changes/add-payment-outbox/proposal.md) (later) |
| Foreign currency transfers | [add-foreign-currency-transfers](../../openspec/changes/add-foreign-currency-transfers/proposal.md) (later) |
| SEPA direct debits, core and B2B, with mandates and batches. A paid add-on for 49.99 euros in MoneyMoney. | [add-direct-debits](../../openspec/changes/add-direct-debits/proposal.md) (later). Included for everyone. |

## Documents

| Feature | Moneten |
|---|---|
| PDF account statements from the bank, a documents section, and dragging in older PDFs | [add-bank-statements](../../openspec/changes/add-bank-statements/proposal.md) (later) |

## Import, export, and automation

| Feature | Moneten |
|---|---|
| Import CSV, CAMT, and MT940 | [add-file-import](../../openspec/changes/add-file-import/proposal.md) (v0.1) |
| Import QIF, OFX, and tab-separated text | [add-more-import-formats](../../openspec/changes/add-more-import-formats/proposal.md) (later) |
| Export CSV | [add-data-export](../../openspec/changes/add-data-export/proposal.md) (v0.1), together with a full JSON export |
| Export OFX, MT940, CAMT.053, Excel, and Numbers, and sending transactions to other apps | [add-more-export-formats](../../openspec/changes/add-more-export-formats/proposal.md) (later) |
| Lua import and export extensions | [add-import-export-extensions](../../openspec/changes/add-import-export-extensions/proposal.md) (later) |
| AppleScript to export accounts, categories, transactions, and securities, to create transfers and direct debits, to add transactions to offline accounts, and to set checkmarks, categories, and comments | [add-applescript-automation](../../openspec/changes/add-applescript-automation/proposal.md) (later) |
| E-invoices (ZUGFeRD) through a separate app | No spec. The other app can use [add-applescript-automation](../../openspec/changes/add-applescript-automation/proposal.md) (later). |

## Security and data

| Feature | Moneten |
|---|---|
| Encrypted database with 256-bit AES. The database password is the key. | [add-encrypted-database](../../openspec/changes/add-encrypted-database/proposal.md) (v0.1). See [ADR 0009](../decisions/0009-database-password-as-in-moneymoney.md). |
| PINs saved only if you choose | [add-login-credentials](../../openspec/changes/add-login-credentials/proposal.md) (v0.1) |
| Lock when the main window closes, lock after inactivity, unlock automatically at launch, unlock with Touch ID or Apple Watch | [add-app-lock](../../openspec/changes/add-app-lock/proposal.md) (v0.1) |
| Direct, encrypted connections to the bank | [add-connection-security](../../openspec/changes/add-connection-security/proposal.md) (v0.1) |
| Certificate pinning for bank servers, with a fingerprint check for unknown certificates | [add-certificate-pinning](../../openspec/changes/add-certificate-pinning/proposal.md) (later) |
| Signed app and signed updates, beta versions on request | [add-software-update](../../openspec/changes/add-software-update/proposal.md) (v0.1) |
| Database backup, data folder, moving to another Mac | [add-data-folder-and-backup](../../openspec/changes/add-data-folder-and-backup/proposal.md) (v0.1) |
| Encrypt a file before sending it to support | [add-log-and-diagnostics](../../openspec/changes/add-log-and-diagnostics/proposal.md) (later) defines a redacted log export instead. |

## App

| Feature | Moneten |
|---|---|
| Main window with sidebar, toolbar, filter bar, and navigation | [add-main-window](../../openspec/changes/add-main-window/proposal.md) (v0.1) |
| Settings window | [add-app-settings](../../openspec/changes/add-app-settings/proposal.md) (v0.1) |
| German and English interface, dark mode | [add-localization-and-formatting](../../openspec/changes/add-localization-and-formatting/proposal.md) (v0.1) |
| License keys, trial period, in-app purchases, version in the Mac App Store | No spec. Moneten is free software. See [ADR 0006](../decisions/0006-license-gpl-3.md). |
| Sync between devices and an iPhone app | Not in MoneyMoney. Both are ideas on the [roadmap](../roadmap.md#ideas-without-a-spec) and have no spec. |

## Changes without a counterpart in MoneyMoney

| Change | What it adds |
|---|---|
| [add-moneymoney-migration](../../openspec/changes/add-moneymoney-migration/proposal.md) (v0.1) | Brings accounts, categories, and transactions over from MoneyMoney |
| [add-extension-developer-tools](../../openspec/changes/add-extension-developer-tools/proposal.md) (v0.1) | A command line tool and a guide for extension authors |
| [add-extension-catalog](../../openspec/changes/add-extension-catalog/proposal.md) (v0.1) | A signed catalog that installs and updates open extensions in the "Extensions" window |

## Prices

MoneyMoney costs 79.99 euros. Direct debits cost 49.99 euros once. The PSD2 online service costs 39.99 euros for 12 months and does not renew on its own. All prices include VAT.

MoneyMoney's PSD2 online service is the closest match to the optional finAPI subscription in [ADR 0007](../decisions/0007-optional-finapi-subscription.md). At 39.99 euros per year it sets the price users will compare against.
