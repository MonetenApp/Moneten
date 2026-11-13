# Data model

This page lists the types in the `Domain` module and the tables that store them. The first sections describe what the code holds today. The last section lists the types that the specs add later. [Architecture](architecture.md) explains how the types are used.

The specs in [openspec/changes](../openspec/changes/) define the behavior. Where this page and a spec differ, the spec wins, and the change that builds the behavior updates this page.

## Money and days

| Type | Fields | Rules |
|---|---|---|
| `Money` | `minorUnits: Int64`, `currency: String` | Exact integer amounts in the smallest unit of the currency, for example cents. `Currency.exponent(of:)` gives the number of decimal places of an ISO 4217 code. No `Double` stores an amount. |
| `MoneySums` | `byCurrency: [String: Int64]` | A sum across accounts or transactions keeps one total per currency and never converts. |
| `Day` | `rawValue: Int` | A calendar day as the number yyyymmdd, without a time and without a time zone. Booking and value dates are days. |

`AmountParser.decimal(from:)` reads amounts that the user types, such as `1.250,00`, `-89,00`, or `1250.00`.

## Accounts

| Type | Fields |
|---|---|
| `AccountGroup` | `id`, `name`, `parentID?`, `position`, `showSum`, `isExpanded` |
| `Account` | `id`, `groupID?`, `position`, `name`, `kind`, `source`, `currency`, `iban?`, `bic?`, `accountNumber?`, `bankCode?`, `bankName?`, `owner?`, `bankBalanceMinor?`, `bankBalanceDate?`, `initialBalanceMinor`, `isClosed`, `comment?`, `sourceID?`, `color?`, `accessID?`, `remoteID?`, `refreshedAt?`, `refreshError?` |
| `AccountKind` | `giro`, `savings`, `fixedTermDeposit`, `loan`, `creditCard`, `portfolio`, `cash`, `other` |
| `AccountSource` | `offline` for an account that the user fills by hand or by import, `migrated` for an account taken over from MoneyMoney, `bank` for an account that its bank access refreshes |

Groups and accounts share one `position` order inside their parent group, so the sidebar can mix them as MoneyMoney does.

An account with a `bankBalanceMinor` shows that balance. Other accounts show `initialBalanceMinor` plus their booked transactions. A migrated account gets the initial balance that makes both numbers end at the same value.

## Bank accesses

| Type | Fields | Rules |
|---|---|---|
| `Access` | `id`, `source`, `bankName`, `loginName` | One login at one source. All its accounts are refreshed in one session. The table `access` stores it with the opaque `AccessState` of its connector, which never holds a PIN. A refresh that returns no state keeps the last one. |
| `AccessSource` | `fints(bankCode, url)`, `extension(id)`, `finAPI(connection)` | Stored as JSON, so a new source needs no migration. |
| `RefreshError` | `message`, `code?`, `date`, `notices` | The error of the last refresh of an account, until a refresh of the account succeeds. |

The table `savedPIN` holds the PIN of an access whose user turned on "Save PIN", as a `Secret` by `accessID`. `SessionBroker` writes it through `SavedPINStore` only after a refresh or a setup with it succeeded, and deletes it when the bank rejects it or the user chooses "Remove saved PIN". It goes with its access. No other table, no `AccessState`, no setting, and no Keychain entry holds a PIN.

An account with an `accessID` is refreshed through that access, which knows it by `remoteID`, for example the IBAN. `refreshedAt` is the end of its last successful refresh, and the next refresh asks for the transactions from 14 days before it. A migrated account that the setup finds again by IBAN, or by account number and Bankleitzahl, takes over the access and keeps its history. Any other account that the app has already is never added twice.

A closed account keeps its transactions, shows no balance in the sidebar, and is left out of the sum of its group.

| Type | Fields | Rules |
|---|---|---|
| `PortfolioValue` | `accountID`, `day`, `minorUnits` | The value of a portfolio at the end of a day. A portfolio gets its value from the bank and not from transactions, so the app records its `bankBalanceMinor` once a day, and the balance chart draws the portfolio from these records. An account has at most one record per day, and a later one replaces it. `Ledger.portfolioValues(of:)` lists them, the oldest first. |

## Categories

| Type | Fields | Rules |
|---|---|---|
| `Category` | `id`, `parentID?`, `position`, `name`, `isGroup`, `isDefault`, `color?`, `currency`, `showInDiagrams`, `sidebarAmount`, `restrictedToID?`, `rule`, `isExpanded`, `sourceID?` | A tree. Exactly one category has `isDefault` set. It is "Uncategorized" and holds every transaction without a category. `color` is `#RRGGBB`. Without a color, a category shows the palette color of its top-level category. `restrictedToID` is an account or an account group. `rule` is text in the rule language of the spec `categorization-rules`, and an empty rule means no rule. |
| `SidebarAmount` | `none`, `currentMonth`, `currentQuarter`, `currentYear`, `totalSum` | The sum that the sidebar shows next to the category. |

When the rules of several categories match a transaction, the first category in sidebar order wins.

## Transactions

| Field | Type | Notes |
|---|---|---|
| `id` | `UUID` | Local identity. |
| `accountID` | `UUID` | |
| `bookingDate` | `Day` | |
| `valueDate` | `Day?` | |
| `amountMinor`, `currency` | `Int64`, `String` | Negative for withdrawals. `amount` returns both as `Money`. |
| `name` | `String` | The counterparty: payee of a withdrawal, payer of a deposit. |
| `purpose` | `String` | Remittance text. |
| `counterpartyIBAN`, `counterpartyBIC` | `String?` | |
| `bookingText` | `String?` | The kind of booking as the bank names it, for example "SEPA-BASISLASTSCHRIFT". |
| `endToEndReference`, `mandateReference`, `creditorID` | `String?` | SEPA references. |
| `comment` | `String?` | A comment that the user writes. |
| `isChecked` | `Bool` | The user checked this transaction off. |
| `isPending` | `Bool` | Not booked yet. Pending transactions count toward neither the balance nor the category sums in the sidebar. |
| `categoryID` | `UUID?` | `nil` means "Uncategorized". |
| `categorizedBy` | `Categorization` | `manual`, `rule`, or `none`. A rule never replaces a manual category. Only "Apply to all transactions." for a changed rule does. |
| `isNew` | `Bool` | Set when a merge adds the transaction, cleared when the user opens its account or checks it. |
| `needsReview` | `Bool` | Set by a merge when more than one row could be the booked version of a pending row. Cleared when the user checks the row. A merge never drops a pending row that has it. |
| `isFetched` | `Bool` | A refresh delivered or matched the row. A file import does not bring back a deleted row that has it. |
| `sourceID` | `String?` | The identifier that the source gave, for example `moneymoney:<id>` or the ID of an extension. A second migration skips known identifiers, and a merge matches a row by it first. A source with IDs of its own replaces a `moneymoney:` identifier when it links the row by its fingerprint. |
| `createdAt` | `Date` | |

Refreshes and file imports go through `reconcile`, which recognizes a stored row by its source ID or by a fingerprint of booking day, amount, counterparty IBAN, end-to-end reference, and purpose. [Architecture](architecture.md#transactions-need-an-identity-the-bank-does-not-give) has the rules.

| Type | Fields | Rules |
|---|---|---|
| `DeletedTransaction` | `accountID`, `sourceID?`, `bookingDate`, `amountMinor`, `isPending`, `purpose`, `counterpartyIBAN?`, `endToEndReference?`, `wasFetched`, `deletedAt` | One record for each transaction that the user deleted, with the raw fields of its fingerprint. A refresh does not add the transaction again. A file adds it again only when `wasFetched` is false. The records go with their account. |

## Tables

`Sources/Storage/Schema.swift` holds the migrations of the encrypted database. Each table stores one type with the same field names:

| Table | Type |
|---|---|
| `accountGroup` | `AccountGroup` |
| `account` | `Account` |
| `category` | `Category` |
| `bankTransaction` | `Transaction` |
| `portfolioValue` | `PortfolioValue`, with the primary key `accountID` and `day` |
| `access` | `Access`, with its `AccessState` in the column `state` |
| `savedPIN` | The saved PIN of an access, with the primary key `accessID` |
| `deletedTransaction` | `DeletedTransaction` |
| `extensionHostDecision` | `HostDecision` of the user for one host of one extension, with the extension and the host as the primary key |
| `extensionCatalog` | One row: the bytes of the catalog index that the app accepted last, its signature, and the version floor of each catalog key as `KeyFloors`. The signature lets the app rebuild the floors when they cannot be read |
| `installedExtension` | The origin of an installed extension by its name, `catalog` with its `InstalledPackage` or `file` with the digests the user allowed |

Migration `v1` creates the tables. It also creates the table `setting`, which no code uses, because app settings live in `UserDefaults`. Migration `v2` drops it. Migration `v4` adds `portfolioValue`, whose rows go with their account. Migration `v5` adds `account.color`, the `#RRGGBB` color of the account's icon. Migration `v6` adds `bankTransaction.needsReview` and `bankTransaction.isFetched`, both false for existing rows, and the table `deletedTransaction`. It rewrites no row. Migration `v7` adds the table `access` and the columns `account.accessID`, `account.remoteID`, `account.refreshedAt`, and `account.refreshError`, all empty for existing accounts. Migration `v8` adds `extensionHostDecision`. Migration `v9` adds the table `savedPIN`, whose rows go with their access. Migration `v10` adds `extensionCatalog` and `installedExtension`.

## Types that the specs add later

| Type | Arrives with | Purpose |
|---|---|---|
| `Split` | v0.1 | Parts of a transaction with their own amounts and categories. The parts add up to the transaction amount. |
| `Security`, `Holding` | v0.2 | Securities accounts with quantity, price, market value, and purchase value. |
| `PaymentOrder`, `PaymentState` | v0.2 | SEPA transfers with the payee check. See [architecture](architecture.md#payments-are-a-separate-state-machine). |
