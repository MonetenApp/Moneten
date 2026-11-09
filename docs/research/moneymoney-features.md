# MoneyMoney features

This page lists the features of MoneyMoney 2.5.3 and where each one lands in MonetenMoneten. It is the checklist for what MoneyMoney users will look for after they switch.

## Sources

- The menus and the settings window of MoneyMoney 2.5.3, read on 9 November 2026.
- The AppleScript dictionary in the app bundle, `MoneyMoney.app/Contents/Resources/MoneyMoney.sdef`.
- The MoneyMoney website: [features](https://moneymoney.app/#features), [help and FAQ](https://moneymoney.app/help/), [security](https://moneymoney.app/security/), [PSD2](https://moneymoney.app/psd2/), and the API docs for [web banking](https://moneymoney.app/api/webbanking/), [import](https://moneymoney.app/api/import/), and [export](https://moneymoney.app/api/export/) extensions.
- The [price list](https://www.cleverbridge.com/1041/purl-moneymoney-all) of the online shop.

A row with "Not in the sources" means the feature may exist, but none of the sources above shows it.

## How to read the status column

- **v0.1**, **v0.2**, or **v0.3** with an issue number. The feature is planned in that release.
- **After v0.3.** The feature is on the [roadmap](../roadmap.md#after-v03) for later.
- **Not planned.** There is no plan yet. Open an issue if you need it.

## Banks and accounts

| Feature | MonetenMoneten |
|---|---|
| FinTS with PIN/TAN | v0.1 [#13](https://github.com/alexander-schneider/MonetenMoneten/issues/13) |
| pushTAN, appTAN, photoTAN, chipTAN with QR code or flicker code | v0.1 [#13](https://github.com/alexander-schneider/MonetenMoneten/issues/13) |
| Many bank-specific TAN methods, such as BestSign, SecureGo, Sm@rtTAN, and TAN2go | v0.1 [#13](https://github.com/alexander-schneider/MonetenMoneten/issues/13) where they follow the FinTS standard. Others as banks need them. |
| USB and Bluetooth TAN generators | Not planned |
| HBCI chip cards and key files | After v0.3 |
| Secoder card readers | Not planned |
| Change the PIN of an online banking access, unblock a PIN with a TAN, chip card PIN and PUK tools | Not planned |
| PSD2 online service for banks without FinTS. A paid add-on for 39.99 euros per year, read-only, run by MoneyMoney's developer as a BaFin-registered account information service. | v0.3 [#36](https://github.com/alexander-schneider/MonetenMoneten/issues/36) through finAPI |
| Web banking extensions in Lua | v0.1 [#14](https://github.com/alexander-schneider/MonetenMoneten/issues/14), [#15](https://github.com/alexander-schneider/MonetenMoneten/issues/15) |
| Signature check for extensions. Unsigned extensions run only after you turn the check off. | v0.3 [#37](https://github.com/alexander-schneider/MonetenMoneten/issues/37) signs the catalog. From v0.1, the app warns before it installs an extension from outside the catalog. |
| More than 6,500 European banks by bank code | German FinTS banks in v0.1. Other banks through extensions and, in v0.3, finAPI. |
| Account types for current, savings, fixed-term, credit card, securities, building society, loan, foreign currency, PayPal, cash, and offline accounts | v0.1 [#3](https://github.com/alexander-schneider/MonetenMoneten/issues/3). PayPal through an extension. A building society contract is an account of kind `other`. |
| Account groups | v0.1 [#5](https://github.com/alexander-schneider/MonetenMoneten/issues/5) |
| Icons per account | Not planned |
| Refresh all accounts, cancel a refresh | v0.1 [#13](https://github.com/alexander-schneider/MonetenMoneten/issues/13) |
| Refresh automatically, notify and play a sound on new transactions, menu bar icon | v0.1 [#40](https://github.com/alexander-schneider/MonetenMoneten/issues/40) |
| Log window | Not planned as a window. The app writes logs from v0.1. |

## Transactions

| Feature | MonetenMoneten |
|---|---|
| Transaction list, pending rows shown differently | v0.1 [#5](https://github.com/alexander-schneider/MonetenMoneten/issues/5) |
| Full history kept on the Mac, beyond the 30 to 450 days a bank returns | v0.1 [#4](https://github.com/alexander-schneider/MonetenMoneten/issues/4), [#13](https://github.com/alexander-schneider/MonetenMoneten/issues/13) |
| Daily balance view | v0.1 [#21](https://github.com/alexander-schneider/MonetenMoneten/issues/21) |
| Live search with the sum of the results | v0.1 [#20](https://github.com/alexander-schneider/MonetenMoneten/issues/20) |
| Search for all transactions with the same counterparty | v0.1 [#20](https://github.com/alexander-schneider/MonetenMoneten/issues/20) |
| Check off one or all transactions | v0.1 [#5](https://github.com/alexander-schneider/MonetenMoneten/issues/5) |
| Comments on transactions | v0.1 [#5](https://github.com/alexander-schneider/MonetenMoneten/issues/5) |
| Manual transactions in offline and cash accounts | v0.1 [#5](https://github.com/alexander-schneider/MonetenMoneten/issues/5) |
| Move transactions to another account | Not planned |
| New transfer from a selected transaction | v0.2 [#29](https://github.com/alexander-schneider/MonetenMoneten/issues/29) |
| Print transactions | After v0.3 |

## Categories and rules

| Feature | MonetenMoneten |
|---|---|
| Categories and category groups | v0.1 [#18](https://github.com/alexander-schneider/MonetenMoneten/issues/18) |
| Rules that categorize new transactions | v0.1 [#19](https://github.com/alexander-schneider/MonetenMoneten/issues/19) |
| Split a transaction across categories | v0.1 [#39](https://github.com/alexander-schneider/MonetenMoneten/issues/39) |
| Exclude categories from charts, for example transfers between own accounts | v0.1 [#21](https://github.com/alexander-schneider/MonetenMoneten/issues/21) |
| Take categories over from CSV and QIF files | CSV in v0.1 [#22](https://github.com/alexander-schneider/MonetenMoneten/issues/22). QIF not planned. |

## Charts, reports, and budgets

| Feature | MonetenMoneten |
|---|---|
| Bar chart of income and spending by month, quarter, or year | v0.1 [#21](https://github.com/alexander-schneider/MonetenMoneten/issues/21) |
| Pie chart of categories | Not planned |
| Account balance report and category report | After v0.3 |
| Dashboard | After v0.3 |
| Budgets for categories and category groups | After v0.3 |

## Securities

| Feature | MonetenMoneten |
|---|---|
| Securities accounts with holdings | v0.2 [#31](https://github.com/alexander-schneider/MonetenMoneten/issues/31) |
| Asset classes | Not planned |
| Crypto and other assets through extensions, shown as securities | v0.2 [#31](https://github.com/alexander-schneider/MonetenMoneten/issues/31) adds the holdings that these extensions return |

## Payments

| Feature | MonetenMoneten |
|---|---|
| SEPA transfer | v0.2 [#28](https://github.com/alexander-schneider/MonetenMoneten/issues/28) |
| Instant transfer | v0.2 [#30](https://github.com/alexander-schneider/MonetenMoneten/issues/30) |
| Verification of Payee | Not in the sources. Required by EU law since October 2025. MonetenMoneten has it in v0.2 [#27](https://github.com/alexander-schneider/MonetenMoneten/issues/27). |
| Scheduled transfers | After v0.3 |
| Standing orders, including change, delete, and refresh from the bank | After v0.3 |
| Foreign currency transfers | After v0.3 |
| Templates, template groups, and placeholders in the purpose line | After v0.3 |
| Import and export of templates | After v0.3 |
| Fill a transfer from bank details on the clipboard | After v0.3 |
| Outbox, and batch transfers from the outbox, a template group, or a SEPA XML file | After v0.3 |
| SEPA direct debits, core and B2B, with mandates and batches. A paid add-on for 49.99 euros. | After v0.3 |
| Release of orders from a computing center (SRZ) | Not planned |

## Documents

| Feature | MonetenMoneten |
|---|---|
| PDF account statements from the bank, a documents section, and dragging in older PDFs | After v0.3 |

## Import, export, and automation

| Feature | MonetenMoneten |
|---|---|
| Import CSV | v0.1 [#22](https://github.com/alexander-schneider/MonetenMoneten/issues/22) |
| Import CAMT and MT940 | v0.1 [#23](https://github.com/alexander-schneider/MonetenMoneten/issues/23) |
| Import QIF, OFX, and tab-separated text | Not planned |
| Export CSV | v0.1 [#8](https://github.com/alexander-schneider/MonetenMoneten/issues/8), together with a full JSON export |
| Export OFX, MT940, CAMT.053, Excel, and Numbers | Not planned |
| Lua import and export extensions, and sending transactions to other apps | After v0.3 |
| AppleScript to export accounts, categories, transactions, and securities | After v0.3 |
| AppleScript to create transfers and direct debits, add transactions to offline accounts, and set checkmarks, categories, and comments | After v0.3 |
| E-invoices (ZUGFeRD) through a separate app | Not planned |

## Security and data

| Feature | MonetenMoneten |
|---|---|
| Encrypted database with 256-bit AES | v0.1 [#4](https://github.com/alexander-schneider/MonetenMoneten/issues/4) with SQLCipher |
| The database password is the key. Storing it in the Keychain is optional. | Different design. MonetenMoneten keeps a random key in the Keychain and unlocks it with Touch ID. See [ADR 0005](../decisions/0005-grdb-and-sqlcipher.md). |
| PINs saved only if you choose | Different design. v0.1 [#4](https://github.com/alexander-schneider/MonetenMoneten/issues/4) saves PINs in the Keychain, which automatic refresh needs. |
| Lock when the main window closes, lock after inactivity, unlock with Touch ID or Apple Watch | v0.1 [#4](https://github.com/alexander-schneider/MonetenMoneten/issues/4) |
| Certificate pinning for bank servers, with a fingerprint check for unknown certificates | After v0.3 |
| Signed app and signed updates | v0.1 [#25](https://github.com/alexander-schneider/MonetenMoneten/issues/25) |
| Database backup | v0.1 [#4](https://github.com/alexander-schneider/MonetenMoneten/issues/4) |
| Encrypt a file before sending it to support | Not planned |

## App

| Feature | MonetenMoneten |
|---|---|
| German and English interface | v0.1 [#5](https://github.com/alexander-schneider/MonetenMoneten/issues/5) |
| Dark mode | v0.1 [#5](https://github.com/alexander-schneider/MonetenMoneten/issues/5) |
| Beta versions on request | Not planned |
| Version in the Mac App Store | Not planned. See [ADR 0006](../decisions/0006-license-gpl-3.md). |
| Sync between devices and an iPhone app | Not in the sources. MonetenMoneten lists both after v0.3. |

## Prices

MoneyMoney costs 79.99 euros. Direct debits cost 49.99 euros once. The PSD2 online service costs 39.99 euros for 12 months and does not renew on its own. All prices include VAT.

## What follows for MonetenMoneten

MoneyMoney is furthest ahead in payments, with templates, the outbox, batch transfers, standing orders, and direct debits. It also supports many TAN devices and chip cards. MonetenMoneten covers reading and categorizing in v0.1, which is what most private users do every day, and adds single transfers in v0.2.

MoneyMoney's PSD2 online service is the closest match to the optional finAPI subscription in [ADR 0007](../decisions/0007-optional-finapi-subscription.md). At 39.99 euros per year it sets the price users will compare against.
