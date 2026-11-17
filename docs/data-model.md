# Data model

This page lists the types in the `Domain` module and the tables that store them. The first sections describe what the code holds today. The last section lists the types that the specs add later. [Architecture](architecture.md) explains how the types are used.

The specs in [openspec/changes](../openspec/changes/) define the behavior. Where this page and a spec differ, the spec wins, and the change that builds the behavior updates this page.

## Money and days

| Type | Fields | Rules |
|---|---|---|
| `Money` | `minorUnits: Int64`, `currency: String` | Exact integer amounts in the smallest unit of the currency, for example cents. `Currency.exponent(of:)` gives the number of decimal places of an ISO 4217 code. No `Double` stores an amount. |
| `MoneySums` | `byCurrency: [String: Int64]` | A sum across accounts or transactions keeps one total per currency and never converts. |
| `Day` | `rawValue: Int` | A calendar day as the number yyyymmdd, without a time and without a time zone. Booking and value dates are days. |

`AmountParser.decimal(from:)` reads amounts that the user types or a file holds, such as `1.250,00`, `-89,00`, or `1250.00`. It refuses a text with two readings, such as `1,234`, unless the caller passes the `DecimalMark` that it knows. The CSV import takes the decimal mark from the other amounts of the file, and MT940 always uses the comma.

## Accounts

| Type | Fields |
|---|---|
| `AccountGroup` | `id`, `name`, `parentID?`, `position`, `showSum`, `isExpanded` |
| `Account` | `id`, `groupID?`, `position`, `name`, `kind`, `source`, `currency`, `iban?`, `bic?`, `accountNumber?`, `bankCode?`, `bankName?`, `owner?`, `bankBalanceMinor?`, `bankBalanceDate?`, `initialBalanceMinor`, `initialBalanceIsSet`, `initialBalanceIsDerived`, `isClosed`, `clearingEntry?`, `comment?`, `sourceID?`, `color?`, `accessID?`, `remoteID?`, `refreshedAt?`, `refreshError?`, `refreshInterval`, `missesOlderTransactions`, `otherBankBalances`, `bonusPoints?` |
| `AccountKind` | `giro`, `savings`, `fixedTermDeposit`, `loan`, `creditCard`, `portfolio`, `cash`, `other` |
| `AccountSource` | `offline` for an account that the user fills by hand or by import, `migrated` for an account taken over from MoneyMoney, `bank` for an account that its bank access refreshes |

Groups and accounts share one `position` order inside their parent group, so the sidebar can mix them as MoneyMoney does.

A portfolio and an account of a bank access (`source` is `bank`) show their `bankBalanceMinor` when they have one (`Account.reportedBalance`). Other accounts show `initialBalanceMinor` plus their transactions in the account currency, pending ones included except those with `review != nil`, so a transaction that the user adds or imports moves the balance. A transaction in another currency stays in the account and its list, but no balance counts it. A migrated account keeps the balance of the source in `bankBalanceMinor` and gets the initial balance that makes its rows from the source end at that value: the balance less the booked rows with a migration ID in the account currency. Pending transactions count on top of the balance of the source. Rows that the user imports or deletes later move the balance from there. A second run moves the initial balance by the change of the balance of the source less the change of those rows, so it keeps what the user changed. A pending row of the source that a file or a bank books keeps its link in the form `moneymoney-booked:<id>`: it counts as imported, and a later run still finds it by the ID and gives back the plain ID once the source books the row too. A deleted row counts as a row of the source while it carries a migration ID that the source still has. A run gives a deleted row the ID of the row of the source that it keeps out, also by its fingerprint, and the store forgets the ID when the source no longer has the row. The migration `v13` sets the stored value of every migrated account except portfolios once by this rule. A row with a migration ID that the user deleted counts as a row of the source there, so its deletion still moves the balance. Connecting a migrated account to a bank access clears `bankBalanceMinor` until the first refresh. An account that the setup adds gets it once, at its first refresh with a bank balance: the bank balance less the booked transactions in the account currency up to the day of that balance. `initialBalanceIsSet` records that, and a value that the user enters sets it as well. `initialBalanceIsDerived` is true only while the value is the one that a refresh derived. A value that the user enters, in the account settings or with "Calibrate", clears it through `Account.enterInitialBalance(_:)`. While it is true (`Account.followsBankBalance`), a manual row booked up to the day of the bank balance that the user adds, changes, or deletes, or that a file matches, moves the value by its own change, and a refresh whose new day passes a manual row sets it to the new bank balance less the booked rows up to that day. A row of the bank or of a file leaves it. The migration `v11` adds the column and leaves it false only for an account of a bank access with an initial balance of 0 and no `sourceID`, which gets its value at its next refresh.

## Bank accesses

| Type | Fields | Rules |
|---|---|---|
| `Access` | `id`, `source`, `bankName`, `loginName` | One login at one source. All its accounts are refreshed in one session. The table `access` stores it with the opaque `AccessState` of its connector, which never holds a PIN. A refresh that returns no state keeps the last one. |
| `AccessSource` | `fints(bankCode, url)`, `extension(id)`, `finAPI(connection)` | Stored as JSON, so a new source needs no migration. |
| `RefreshError` | `message`, `code?`, `date`, `notices`, `waitsForUser`, `suggestsEditLoginData` | The error of the last refresh of an account, until a refresh of the account succeeds. `waitsForUser` marks an error that only the user can resolve, such as a TAN that an automatic refresh could not ask for. `suggestsEditLoginData` marks a failed refresh of the whole access, at the login or after it, after which the bank may want the access set up again with "Edit Login Data...". |

The table `savedPIN` holds the PIN of an access whose user turned on "Save PIN", as a `Secret` by `accessID`. `SessionBroker` writes it through `SavedPINStore` only after a refresh or a setup with it succeeded, and deletes it when the bank rejects it or the user chooses "Remove saved PIN". It goes with its access. No other table, no `AccessState`, no setting, and no Keychain entry holds a PIN.

An account with an `accessID` is refreshed through that access, which knows it by `remoteID`, for example the IBAN. `refreshedAt` is the end of its last successful refresh, and the next refresh asks for the transactions from 14 days before it, or from its oldest pending transaction when that is earlier. A migrated account that the setup finds again by IBAN, or by account number and Bankleitzahl, takes over the access and keeps its history. Any other account that the app has already is never added twice. `refreshInterval` is "Refresh" in the account settings, a `RefreshInterval` from `everyTwoHours` to `never`. `Ledger.dueAccounts(at:)` names the accounts that the automatic refresh fetches: those whose interval passed since their last refresh, or since the failure of the last one, without an error that waits for the user. `missesOlderTransactions` says that older transactions of the account may be missing, because a refresh fetched less than the time since its last successful fetch (`RefreshResult.missesOlder`), such as after a canceled TAN for older transactions. `Store.merge` writes it in the same transaction as the rows, and only a refresh of the full history clears it. While it is set, a refresh derives the initial balance again and leaves `initialBalanceIsSet` false. `otherBankBalances` holds the balances in other currencies that the source reported with `bankBalanceMinor`, and `bonusPoints` the bonus points. Each refresh that stores a balance replaces both, and a portfolio has neither. `Account.reportedBalances` and `Ledger.balances(of:)` give the balances that the sidebar row and the header show, the account currency first, and `Ledger.sum(ofGroup:)` adds each in its currency. An account that computes its balance shows one balance.

A closed account (`isClosed`) shows its computed balance, also when it has a bank balance, and no other balances, so `Account.reportedBalance` is nil for it. Only a closed portfolio keeps its value. `Ledger.closing(_:today:now:)` marks an account as closed and returns the clearing entry: a manual booked row on that day whose amount brings the computed balance at the end of that day to zero, or none when that balance is zero. `clearingEntry` keeps a `ClearingEntryMark` with the ID of that row and the values that the app gave it. `Ledger.reopening(_:calendar:)` clears the mark and names the row for removal while it belongs to the account, no source matched it, and the user has not changed it. While an account is closed, its clearing entry moves no derived initial balance, and a kept entry moves it at the reopen. A closed account takes no refresh: `reconcile` ignores a refresh delivery into it, and `Account.record(_:)` ignores the end of a refresh.

A closed account keeps its transactions, shows no balance in the sidebar, and is left out of the sum of its group.

| Type | Fields | Rules |
|---|---|---|
| `PortfolioValue` | `accountID`, `day`, `minorUnits` | The value of a portfolio at the end of a day. A portfolio gets its value from the bank and not from transactions, so the app records its `bankBalanceMinor` once a day, and the balance chart draws the portfolio from these records. An account has at most one record per day, and a later one replaces it. `Ledger.portfolioValues(of:)` lists them, the oldest first. |

## Securities

A portfolio holds positions. The latest successful refresh of its account replaces them all, and a failed refresh keeps the last ones.

| Type | Fields | Rules |
|---|---|---|
| `Security` | `name`, `isin?`, `securityNumber?` | The security as its source names it. The security number is the national one, such as the WKN. |
| `Quote` | `amount`, `currency?`, `day?` | A price per unit as a `Decimal` with every decimal place of the source, or a percentage of the nominal amount when it has no currency. The purchase price is a `Quote` with the day of the purchase. |
| `ExchangeRate` | `base`, `quoted`, `rate` | One unit of `base` costs `rate` units of `quoted`, as the bank sends it. `convert(_:from:to:)` works in both directions. |
| `Holding` | `id`, `accountID`, `security`, `quantity`, `isNominal`, `nominalCurrency?`, `quote?`, `marketValue?`, `accruedInterest?`, `purchasePrice?`, `exchangeRate?` | One position. `quantity` is a `Decimal`: a number of units, or a nominal amount when `isNominal` is set, in `nominalCurrency` when the source names it. A percentage of a nominal amount without a currency gives no computed value and no gain. `value(in:)` is the market value plus the accrued interest, or else the quantity times the quote. `gain(in:)` is the market value less the purchase value, without the accrued interest. Both round to the currency once, at the end. `Holding.identify` keeps the `id` of a stored position across refreshes: of the same ISIN first, and of the same security number or name only when one of the two has no ISIN. `Ledger.holdings(of:)` lists the positions by name. |

## Categories

| Type | Fields | Rules |
|---|---|---|
| `Category` | `id`, `parentID?`, `position`, `name`, `isGroup`, `isDefault`, `color?`, `currency`, `showInDiagrams`, `sidebarAmount`, `restrictedToID?`, `rule`, `isExpanded`, `sourceID?` | A tree. Exactly one category has `isDefault` set. This default category holds every transaction without a category, and the sidebar shows it last. `color` is `#RRGGBB`. Without a color, a category shows the palette color of its top-level category. `restrictedToID` is an account or an account group. `rule` is text in the rule language of the spec `categorization-rules`, and an empty rule means no rule. |
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
| `returnReason` | `String?` | The ISO 20022 code with which the bank returned the payment, for example "AC04". Read from a CAMT file. |
| `originalAmountMinor`, `originalCurrency` | `Int64?`, `String?` | The amount in another currency that the bank converted, in the minor units of its own currency, with the sign of the booked amount. Read from FinTS, MT940, CAMT, and the card statement. `Transaction.original(_:booked:)` drops an amount in the currency of the booked amount. |
| `deviatingParty` | `String?` | The deviating originator of a credit or the deviating recipient of a debit (ABWA+ and ABWE+ in MT940, UltmtDbtr and UltmtCdtr in CAMT). `name` stays the counterparty. |
| `comment` | `String?` | A comment that the user writes. |
| `isChecked` | `Bool` | The user checked this transaction off. |
| `isPending` | `Bool` | Not booked yet. A pending transaction counts toward the balance and the category sums, except one with `review != nil`. |
| `categoryID` | `UUID?` | `nil` means the default category. |
| `categorizedBy` | `Categorization` | `manual`, `rule`, or `none`. A rule never replaces a manual category. Only "Apply to all transactions." for a changed rule does. |
| `isNew` | `Bool` | Set when a merge adds the transaction, cleared when the user opens its account or checks it. |
| `review` | `ReviewReason?` | `.unclearBooking` when more than one row could be the booked version of a pending row, or `.splitUndone` when a booked correction removes its split parts. Cleared when the user checks a booked row. A checked pending row keeps it. A merge drops a pending row that has it only after the user checked it, and a new review clears that checkmark. |
| `isFetched` | `Bool` | A refresh delivered or matched the row. A file import does not bring back a deleted row that has it. |
| `sourceID` | `String?` | The identifier that the source gave, for example `moneymoney:<id>` or the ID of an extension. A second migration skips known identifiers, and a merge matches a row by it first. A source with IDs of its own replaces a `moneymoney:` identifier when it links the row by its fingerprint. |
| `fileIdentity` | `String?` | Original file fingerprint, set only by file import. Bank takeover, booking, and deletion preserve it. NULL means no file identity. Different file fingerprints can pair for a verified pending-to-booked transition. Conflicting real source IDs or references never pair. |
| `createdAt` | `Date` | |
| `original` | `OriginalValues?` | Nil until the user changes the booking date, the value date, the name, the purpose, or the amount with "Edit Transaction...". Then it holds the values that the source delivered for these five fields. `sourceValues` returns `original`, or the fields of an unedited row. A row that only the user added, `isOnlyManual`, has no source, so an edit replaces its values and records no `original`. |
| `isManual` | `Bool` | The user added the row with "Add Transaction...". A refresh never pairs a delivered row with it, deleting it keeps no `DeletedTransaction` unless a file or a migration matched it. A file that matches it gives it its `fileIdentity`, and a migration its `sourceID`. From then on `Transaction.isOnlyManual` is false, and the row counts as a row of that source. |

Refreshes and file imports go through `reconcile`, which recognizes a stored row by its source ID or by a fingerprint of booking day, amount and currency, counterparty IBAN, end-to-end reference, and purpose. The fingerprint of an edited row takes the day, the amount, and the purpose from `sourceValues`. A merge updates `original` with the delivered values and keeps each field that the user edited. [Architecture](architecture.md#transactions-need-an-identity-the-bank-does-not-give) has the rules.

| Type | Fields | Rules |
|---|---|---|
| `DeletedTransaction` | `accountID`, `sourceID?`, `fileIdentity?`, `bookingDate`, `amountMinor`, `currency`, `isPending`, `purpose`, `counterpartyIBAN?`, `endToEndReference?`, `wasFetched`, `deletedAt` | One record for each transaction that the user deleted, with the raw fields of its fingerprint, taken from `sourceValues` for an edited row. A refresh does not add the transaction again. A file adds it again only when `wasFetched` is false. The records go with their account. |

Lists and sums by category read `Ledger.rows(in:filter:)`, which returns `TransactionSearchResult` with part rows and the search failure flag. `Ledger.sidebarAmounts(today:)` counts the part rows itself within its single pass over the stored transactions. Balances read the stored originals in `Ledger.transactions`.

## Splits

| Type | Fields | Rules |
|---|---|---|
| `SplitPart` | `id`, `transactionID`, `position`, `amountMinor`, `categoryID?`, `comment?`, `vat?` | At least two nonzero parts add up to their original transaction. Each part uses its original's currency. The original keeps its category and comment for undo. |
| `VATShare` | `role`, `rate` | The net or tax label of a VAT part keeps the rate used for the split. |
| `VATRate` | `hundredths` | A percent in hundredths. The standard rates are 1900 and 700. The net amount is cut toward zero at the smallest unit of the currency, and tax takes the remainder. |
| `SplitError` | `pending`, `zeroPart`, `onePart`, `unbalanced` | A refused split leaves the stored parts unchanged. |
| `Split` | Amount parsing and split arithmetic | An unsigned amount takes the sign of the row. An explicit sign stays. Amounts must fit the decimals of the row's currency. |

## Saved searches

| Type | Fields | Rules |
|---|---|---|
| `SavedFilterBar` | `period`, `status`, `amount`, `categoryID?`, `accountID?`, `accountGroupID?` | The filter bar without the search text. The pin keeps one in `UserDefaults`. `period` is a `PeriodChoice`, so "30 Days" counts from the day it is read. The account filter, a `TransactionFilter.AccountFilter`, is an account in `accountID` or an account group in `accountGroupID`, so a filter bar saved before groups reads as before. A category, an account, or an account group that the ledger no longer has comes back as "Show All". |
| `SavedSearch` | `id`, `name`, `position`, `searchText`, `bar` | An entry of the sidebar section "Searches". It holds no rows. Selecting it puts its search text and its `SavedFilterBar` into the search field and the filter bar, and the list shows `LedgerScope.all`, the rows of every account. |

## Tables

`Sources/Storage/Schema.swift` holds the migrations of the encrypted database. Each table stores one type with the same field names:

| Table | Type |
|---|---|
| `accountGroup` | `AccountGroup` |
| `account` | `Account` |
| `category` | `Category` |
| `csvProfile` | A profile name, JSON version, and payload containing `CSVProfile`. Unreadable versions or payloads remain stored when another profile changes. |
| `savedSearch` | `SavedSearch`, with its `bar` as the JSON of `SavedFilterBar` that the pin also writes. A filter bar that cannot be read comes back as "Show All". |
| `bankTransaction` | `Transaction` |
| `splitPart` | `SplitPart`, with `vat` as JSON. Parts go with their transaction and become uncategorized when their category is removed. |
| `portfolioValue` | `PortfolioValue`, with the primary key `accountID` and `day` |
| `holding` | `Holding`, flattened by `HoldingRecord`, with quantities, prices, and rates as decimal text |
| `access` | `Access`, with its `AccessState` in the column `state` |
| `savedPIN` | The saved PIN of an access, with the primary key `accessID` |
| `deletedTransaction` | `DeletedTransaction` |
| `extensionHostDecision` | `HostDecision` of the user for one host of one extension, with the extension and the host as the primary key |
| `extensionCatalog` | One row: the bytes of the catalog index that the app accepted last, its signature, and the version floor of each catalog key as `KeyFloors`. The signature lets the app rebuild the floors when they cannot be read |
| `lockSetting` | One row: `LockSettings`, the lock when the main window closes and the minutes of inactivity before the lock, 0 for never. Without the row the defaults apply |
| `installedExtension` | The origin of an installed extension by its name, `catalog` with its `InstalledPackage` or `file` with the digests the user allowed |

Migration `v1` creates the tables. It also creates the table `setting`, which no code uses, because app settings live in `UserDefaults`. Migration `v2` drops it. Migration `v4` adds `portfolioValue`, whose rows go with their account. Migration `v5` adds `account.color`, the `#RRGGBB` color of the account's icon. Migration `v6` adds `bankTransaction.needsReview` and `bankTransaction.isFetched`, both false for existing rows, and the table `deletedTransaction`. It rewrites no row. Migration `v7` adds the table `access` and the columns `account.accessID`, `account.remoteID`, `account.refreshedAt`, and `account.refreshError`, all empty for existing accounts. Migration `v8` adds `extensionHostDecision`. Migration `v9` adds the table `savedPIN`, whose rows go with their access. Migration `v10` adds `extensionCatalog` and `installedExtension`. Migration `v12` adds `account.refreshInterval`, `everyTwoHours` for existing accounts. Migration `v14` adds `holding`, whose rows go with their account. Migration `v15` adds `deletedTransaction.currency`, the currency of its account for existing rows. Migration `v17` adds the empty table `splitPart` after `v16`. It rewrites no transaction. Migration `v20`, registered after `v19` and `v18`, replaces `bankTransaction.needsReview` with nullable `review`. It maps true to `unclearBooking` and false to nil. `ReviewReason` also has `splitUndone` for an automatic split undo. Migration `v24` adds `bankTransaction.original`, empty for existing rows, because no row could be edited before it. Migration `v21`, registered after `v24`, adds `account.missesOlderTransactions`, false for existing accounts, and moves the marks that a debug build before it kept in the state of a FinTS access into that column once. Migration `v25`, registered after `v21`, adds the table `savedSearch`. Migration `v22`, registered after `v25`, adds the empty table `lockSetting`. Migration `v26`, registered after `v22`, adds `account.otherBankBalances`, an empty JSON list for existing accounts, and `account.bonusPoints`, empty for existing accounts. Migration `v23`, registered after `v24`, `v21`, `v25`, `v22`, and `v26`, adds `bankTransaction.isManual`, false for existing rows, and `account.initialBalanceIsDerived`, false for existing accounts, because the database does not tell a derived initial balance from an entered one. GRDB applies the migrations in the order of registration, so a migration that lands later on main comes before `v23` in the list. Migration `v27`, registered after `v23`, writes the currency codes of `account`, `bankTransaction`, and `deletedTransaction` in upper case, also the currency inside a `fileIdentity`, because the fingerprint compares the currency and an earlier version stored the code of a file or of the FinTS helper as it came. Migration `v28`, registered after `v27`, adds `account.clearingEntry`, empty for existing accounts. Migration `v29`, registered after `v28`, adds `bankTransaction.originalAmountMinor`, `bankTransaction.originalCurrency`, and `bankTransaction.deviatingParty`, empty for existing rows.

## Complete export

`AllData` holds every stored object except saved PINs, the `AccessState` of each access, the lock settings, and the data of extensions. `Store.exportAllData` reads it and `Store.importAllData` writes it into an empty database. Its JSON form is the file of "Export All Data...", which [the export format](export-format.md) describes key by key.

## Types that the specs add later

| Type | Arrives with | Purpose |
|---|---|---|
| `PaymentOrder`, `PaymentState` | v0.2 | SEPA transfers with the payee check. See [architecture](architecture.md#payments-are-a-separate-state-machine). |

Migration `v19` stores CSV profiles. Migration `v18` is registered after `v19`, preserving main's append-only migration order. It adds one nullable TEXT `fileIdentity` column to `bankTransaction` and `deletedTransaction`. Existing rows retain NULL and their prior matching behavior. The original versioned file fingerprint includes booking day, amount, currency, folded purpose, counterparty, source ID, and end-to-end reference. Its length-prefixed encoding excludes pending state and user fields. The operator accepted this migration in the #203 gate.
