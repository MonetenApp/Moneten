# Roadmap

This page lists what ships in each release up to v0.3. Each row links to the GitHub issue that holds the scope and the definition of done. The issues are the source of truth. Run `python3 scripts/roadmap.py` to regenerate this page from them.

## v0.1 Read

Fetch, categorize, and understand your money. Read-only.

**Done when.** A user adds a German bank through FinTS with pushTAN, fetches 90 days of transactions, categorizes them with rules, sees charts, imports their MoneyMoney data, and runs three published MoneyMoney extensions unchanged, in a notarized build.

| Issue | Labels | Depends on |
|---|---|---|
| [#1 Set up the Xcode project, packages, and CI](https://github.com/alexander-schneider/monetenmoneten/issues/1) | area: foundation | None |
| [#2 Prototype GRDB with SQLCipher through Swift Package Manager](https://github.com/alexander-schneider/monetenmoneten/issues/2) | area: foundation, kind: prototype | None |
| [#3 Define the core domain types](https://github.com/alexander-schneider/monetenmoneten/issues/3) | area: foundation | #1 |
| [#4 Build the encrypted store, migrations, and Keychain access](https://github.com/alexander-schneider/monetenmoneten/issues/4) | area: foundation | #2, #3 |
| [#5 Build the app shell with sidebar, transaction list, and settings](https://github.com/alexander-schneider/monetenmoneten/issues/5) | area: core | #4 |
| [#6 Define BankConnector, SyncSession, Challenge, and the sync state machine](https://github.com/alexander-schneider/monetenmoneten/issues/6) | area: foundation | #3 |
| [#7 De-duplicate transactions and reconcile pending rows with booked rows](https://github.com/alexander-schneider/monetenmoneten/issues/7) | area: core | #3 |
| [#8 Export and re-import all data as JSON, and export CSV](https://github.com/alexander-schneider/monetenmoneten/issues/8) | area: core | #4 |
| [#9 Apply for FinTS product registration](https://github.com/alexander-schneider/monetenmoneten/issues/9) | area: fints, kind: organization | None |
| [#10 Ask the HBCI4Swift author about a joint Swift package](https://github.com/alexander-schneider/monetenmoneten/issues/10) | area: fints, kind: organization | None |
| [#11 Prototype HBCI4Swift against three banks](https://github.com/alexander-schneider/monetenmoneten/issues/11) | area: fints, kind: prototype | None |
| [#12 Turn HBCI4Swift into a tested Swift package](https://github.com/alexander-schneider/monetenmoneten/issues/12) | area: fints | #11, #10 |
| [#13 Build the FinTS connector for accounts, balances, and transactions](https://github.com/alexander-schneider/monetenmoneten/issues/13) | area: fints | #12, #6, #7, #9 |
| [#14 Run Lua 5.4 extensions in a sandboxed XPC process](https://github.com/alexander-schneider/monetenmoneten/issues/14) | area: extensions | #6 |
| [#15 Implement the MoneyMoney-compatible extension API](https://github.com/alexander-schneider/monetenmoneten/issues/15) | area: extensions | #14 |
| [#16 Build the ext command line tool with record and replay](https://github.com/alexander-schneider/monetenmoneten/issues/16) | area: extensions | #15 |
| [#17 Write the extension author guide](https://github.com/alexander-schneider/monetenmoneten/issues/17) | area: extensions | #16 |
| [#18 Add categories with a tree and manual assignment](https://github.com/alexander-schneider/monetenmoneten/issues/18) | area: core | #5 |
| [#19 Categorize new transactions with rules](https://github.com/alexander-schneider/monetenmoneten/issues/19) | area: core | #18 |
| [#20 Search and filter transactions](https://github.com/alexander-schneider/monetenmoneten/issues/20) | area: core | #5 |
| [#21 Show balance history and spending by category](https://github.com/alexander-schneider/monetenmoneten/issues/21) | area: core | #18 |
| [#22 Import CSV files with saved column profiles](https://github.com/alexander-schneider/monetenmoneten/issues/22) | area: import | #7, #5 |
| [#23 Import CAMT.053 and MT940 files](https://github.com/alexander-schneider/monetenmoneten/issues/23) | area: import | #7 |
| [#24 Migrate accounts, transactions, and categories from MoneyMoney](https://github.com/alexander-schneider/monetenmoneten/issues/24) | area: import | #18, #23 |
| [#25 Sign, notarize, and update the app with Sparkle](https://github.com/alexander-schneider/monetenmoneten/issues/25) | area: release | #1 |
| [#26 Review security before the first public release](https://github.com/alexander-schneider/monetenmoneten/issues/26) | area: release | #13, #15, #25 |

## v0.2 Pay

Send the first SEPA transfer and see securities accounts.

**Done when.** A user sends a SEPA transfer through FinTS, sees the payee check result before confirming, approves with a TAN, and sees the holdings of a securities account.

| Issue | Labels | Depends on |
|---|---|---|
| [#27 Check the payee with Verification of Payee](https://github.com/alexander-schneider/monetenmoneten/issues/27) | area: payments | #13 |
| [#28 Send a SEPA transfer through FinTS](https://github.com/alexander-schneider/monetenmoneten/issues/28) | area: payments | #27 |
| [#29 Build the transfer form and review screen](https://github.com/alexander-schneider/monetenmoneten/issues/29) | area: payments | #28 |
| [#30 Send instant transfers where the bank supports them](https://github.com/alexander-schneider/monetenmoneten/issues/30) | area: payments | #28 |
| [#31 Read securities accounts through FinTS](https://github.com/alexander-schneider/monetenmoneten/issues/31) | area: fints | #13 |
| [#32 Review payment security before the v0.2 release](https://github.com/alexander-schneider/monetenmoneten/issues/32) | area: release | #28, #30 |

## v0.3 Connect

Connect banks without FinTS through an optional subscription, and install extensions from a catalog.

**Done when.** A subscriber connects a bank through finAPI and fetches transactions, and a user installs and updates extensions from a signed catalog. Every v0.1 and v0.2 feature still works without a subscription.

| Issue | Labels | Depends on |
|---|---|---|
| [#33 Get written license confirmation and prices from finAPI](https://github.com/alexander-schneider/monetenmoneten/issues/33) | area: service, kind: organization | None |
| [#34 Set up the company that runs the subscription](https://github.com/alexander-schneider/monetenmoneten/issues/34) | area: service, kind: organization | #33 |
| [#35 Build the subscription service in a separate repository](https://github.com/alexander-schneider/monetenmoneten/issues/35) | area: service | #34 |
| [#36 Build the finAPI connector](https://github.com/alexander-schneider/monetenmoneten/issues/36) | area: service | #35, #6 |
| [#37 Install and update extensions from a signed catalog](https://github.com/alexander-schneider/monetenmoneten/issues/37) | area: extensions | #15 |
| [#38 Review the subscription service security before launch](https://github.com/alexander-schneider/monetenmoneten/issues/38) | area: service, area: release | #36, #37 |

## After v0.3

- Sync between your Macs through iCloud.
- An app for iPhone and iPad that reuses the `Domain`, `Storage`, and connector packages.
- Budgets.
