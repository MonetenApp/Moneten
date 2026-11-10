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
| `Account` | `id`, `groupID?`, `position`, `name`, `kind`, `source`, `currency`, `iban?`, `bic?`, `accountNumber?`, `bankCode?`, `bankName?`, `owner?`, `bankBalanceMinor?`, `bankBalanceDate?`, `initialBalanceMinor`, `isClosed`, `comment?`, `sourceID?` |
| `AccountKind` | `giro`, `savings`, `fixedTermDeposit`, `loan`, `creditCard`, `portfolio`, `cash`, `other` |
| `AccountSource` | `offline` for an account that the user fills by hand or by import, `migrated` for an account taken over from MoneyMoney |

Groups and accounts share one `position` order inside their parent group, so the sidebar can mix them as MoneyMoney does.

An account with a `bankBalanceMinor` shows that balance. Other accounts show `initialBalanceMinor` plus their booked transactions. A migrated account gets the initial balance that makes both numbers end at the same value.

A closed account keeps its transactions, shows no balance in the sidebar, and is left out of the sum of its group.

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
| `isNew` | `Bool` | Set on import, cleared when the user has seen the transaction. |
| `sourceID` | `String?` | The identifier in the program the transaction came from, for example `moneymoney:<id>`. A second migration skips known identifiers. |
| `createdAt` | `Date` | |

A file import has no stable identifier per row. `ImportMatching` treats two transactions as the same when the day, the amount, the name, and the purpose match. It counts equal rows, so two identical rows in one file add two transactions.

## Tables

`Sources/Storage/Schema.swift` holds the migrations of the encrypted database. Each table stores one type with the same field names:

| Table | Type |
|---|---|
| `accountGroup` | `AccountGroup` |
| `account` | `Account` |
| `category` | `Category` |
| `bankTransaction` | `Transaction` |

Migration `v1` creates the tables. Migration `v2` drops the table `setting`, which no code used. App settings live in `UserDefaults`.

## Types that the specs add later

| Type | Arrives with | Purpose |
|---|---|---|
| `Connection`, `ConnectionSource` | v0.1, FinTS | A bank access: FinTS user, extension, or finAPI (v0.3). An account without a connection stays an offline account. |
| Saved PIN | v0.1, FinTS | A PIN saved inside the encrypted database, only when the user turns saving on for a connection. |
| Transaction fingerprint | v0.1, FinTS | Identity for bank data without a stable ID, and the match of a pending transaction to its booked version. See [architecture](architecture.md#transactions-need-an-identity-the-bank-does-not-give). |
| `Split` | v0.1 | Parts of a transaction with their own amounts and categories. The parts add up to the transaction amount. |
| `Security`, `Holding` | v0.2 | Securities accounts with quantity, price, market value, and purchase value. |
| `PaymentOrder`, `PaymentState` | v0.2 | SEPA transfers with the payee check. See [architecture](architecture.md#payments-are-a-separate-state-machine). |
