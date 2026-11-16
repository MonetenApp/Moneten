# Format of the complete export

"Export All Data..." writes one JSON file with all user data of a database, and "Import All Data..." reads it into an empty database. This page describes format version 2 key by key. The reader also accepts version 1. The test `AllDataTests` checks that each key of an export is described here.

## Conventions

- An amount is decimal text with a point and the decimal places of its currency, such as `"-1234.56"`, next to an ISO 4217 currency code. No amount is a JSON number, so no reader rounds it.
- A day is a valid calendar day with exactly four ASCII year digits, two month digits, and two day digits, separated by hyphens, such as `"2026-11-03"`. It has no time zone. The reader checks this bounded form before parsing the date.
- A time is ISO 8601 text in UTC with milliseconds, such as `"2026-11-14T23:46:40.000Z"`.
- An identifier is a UUID as text. Objects refer to each other by these identifiers.
- An optional key without a value is left out, and a reader takes a missing optional key as empty. Every other key is always written, also an empty list or an empty text such as `purpose`.
- A currency code has exactly three uppercase ASCII letters, `[A-Z]{3}`. This also applies to optional currencies of holdings and both currencies of an exchange rate.
- Adding an optional key does not change the format version. A reader treats a missing `csvProfiles` key as an empty list.
- The lists keep the order of the database.
- A category or account group cannot contain itself, directly or through its parents. The reader refuses a loop and names its position.
- The complete export is written atomically with mode 0600, so only its owner can read or write it. An unreadable stored holding fails the export instead of being omitted.

## File

| Key | Content |
|---|---|
| `format` | Always `"moneten-export"` |
| `version` | The format version as a number, `2` for this page. A reader refuses a version below 1 as damaged and a version above 2 as needing a newer app. |
| `exportedAt` | The time of the export |
| `accountGroups` | List of account groups |
| `accounts` | List of accounts |
| `accesses` | List of bank accesses |
| `categories` | List of categories and category groups |
| `transactions` | List of stored originals, once each |
| `splitParts` | Required list of split parts, empty when none |
| `deletedTransactions` | List of deleted transactions, so that a refresh or a migration does not add them again |
| `portfolioValues` | List of daily values of portfolios |
| `holdings` | List of positions of portfolios |
| `csvProfiles` | Optional list of saved CSV profiles, including unreadable versions. Left out when there are none. |

## CSV profile

| Key | Content |
|---|---|
| `name` | Saved profile name |
| `version` | Version of the profile payload, currently `1`, separate from the export format version |
| `payload` | Base64 of the exact stored JSON bytes. The complete export preserves unreadable profiles and unknown fields without interpreting them. |

A version-1 payload contains `name`, `header`, `delimiter`, and `layout`. The header is a list of column titles, and the optional delimiter is the saved field separator. The layout contains `encoding`, `columns`, `dateOrder`, optional `decimalMark`, and `createsCategories`. The columns object maps the field names of `CSVField` in [the CSV reader](../Sources/Import/CSVImport.swift) to zero-based column positions. The other settings use the raw values of `CSVEncoding`, `DateOrder`, and `DecimalMark` from the reader. A profile save updates known fields and preserves unknown fields, including unknown column mappings. A profile with a negative known column position is unreadable and is not applied. Its raw payload remains stored and exported.

## Account group

| Key | Content |
|---|---|
| `id` | Identifier |
| `name` | Name |
| `parentID` | The group that contains this group |
| `position` | Order among the groups and accounts of the same parent, a number |
| `showSum` | Whether the sidebar shows the sum of the group |
| `isExpanded` | Whether the sidebar shows the group open |
| `groupsByAccount` | Whether the list of the group shows its transactions by account |

## Account

| Key | Content |
|---|---|
| `id` | Identifier |
| `groupID` | The account group that contains the account |
| `position` | Order among the groups and accounts of the same parent |
| `name` | Name |
| `kind` | `giro`, `savings`, `fixedTermDeposit`, `loan`, `creditCard`, `portfolio`, `cash`, or `other` |
| `source` | `offline` for an account without a bank access, `migrated` for an account taken over from MoneyMoney, `bank` for an account with a bank access |
| `currency` | Currency of the account |
| `iban`, `bic` | IBAN and BIC |
| `accountNumber`, `bankCode` | Account number and bank code, such as the Bankleitzahl |
| `bankName` | Name of the bank |
| `owner` | Owner of the account |
| `bankBalance` | The last balance that the bank or the source app reported, an amount in the currency of the account |
| `bankBalanceDate` | The time of that balance |
| `initialBalance` | The balance before the first transaction, an amount in the currency of the account |
| `initialBalanceIsSet` | Whether the initial balance is set, by the user or by the first refresh |
| `initialBalanceIsDerived` | Optional `true` while the initial balance is the value that a refresh derived, so manual transactions move it. Missing means a value that the user entered or that came from the source. |
| `isClosed` | Whether the account is closed |
| `comment` | Comment |
| `sourceID` | Identifier of the account in the source it came from, such as `moneymoney:<uuid>` |
| `color` | Color of the icon, such as `"#3478F6"` |
| `accessID` | The bank access that refreshes the account |
| `remoteID` | Identifier of the account at its bank |
| `refreshedAt` | Time of the last successful refresh |
| `refreshError` | The error of the last refresh, with `message`, `code` (the return code of the bank), `date`, `notices` (the notices of the bank), `waitsForUser` (whether only a refresh command of the user can resolve it), and `suggestsEditLoginData` (whether the refresh of the whole access failed, at the login or after it, in a way that can mean that the bank wants it set up again, so the error names "Edit Login Data..."). A reader takes a missing `waitsForUser` or `suggestsEditLoginData` as false. |
| `refreshInterval` | `everyTwoHours`, `fourTimesADay`, `onceADay`, `onceAWeek`, `onlyManually`, or `never` |

## Access

An access is a login at a bank. The file never holds its PIN or the data that its connector keeps between refreshes, so the first refresh after an import asks for the PIN.

| Key | Content |
|---|---|
| `id` | Identifier |
| `connector` | How the app reaches the bank. One of `fints` with `bankCode` and `url` (the FinTS address), `extension` with `id` (the name of the extension), or `finAPI` with `connection` |
| `bankName` | Name of the bank or service |
| `userID` | The user ID of the login |

## Category

| Key | Content |
|---|---|
| `id` | Identifier |
| `parentID` | The category group that contains the category |
| `position` | Order among the categories of the same parent |
| `name` | Name |
| `isGroup` | Whether this is a category group |
| `isDefault` | Whether this is the category of transactions without a category ("Uncategorized") |
| `color` | Color, such as `"#3478F6"` |
| `symbol` | Name of the SF Symbol of its icon |
| `currency` | Currency of the sums of the category |
| `showInDiagrams` | Whether the charts show the category |
| `sidebarAmount` | The amount in the sidebar: `none`, `currentMonth`, `currentQuarter`, `currentYear`, or `totalSum` |
| `restrictedToID` | The account or account group whose transactions alone the rule takes |
| `rule` | The rule for automatic categorization as text, empty for none |
| `isExpanded` | Whether the sidebar shows the group open |
| `sourceID` | Identifier of the category in the source it came from |

## Transaction

| Key | Content |
|---|---|
| `id` | Identifier |
| `accountID` | The account |
| `bookingDate` | Booking day |
| `valueDate` | Value day |
| `amount`, `currency` | Amount and its currency |
| `name` | Name of the counterparty |
| `purpose` | Purpose, with its line breaks |
| `counterpartyIBAN`, `counterpartyBIC` | Account and bank of the counterparty, an IBAN or an account number, and a BIC or a bank code |
| `bookingText` | Booking text of the bank, such as "Lastschrift" |
| `endToEndReference`, `mandateReference`, `creditorID` | SEPA references |
| `returnReason` | ISO 20022 return reason of a returned payment, such as `"AC04"` for a closed account. Missing means no return reason. |
| `comment` | Comment of the user |
| `isChecked` | The checkmark |
| `isPending` | Whether the bank has not booked the transaction yet |
| `categoryID` | The category, missing for "Uncategorized" |
| `categorizedBy` | `none`, `rule` for a category from a rule, or `manual` for a category the user chose |
| `isNew` | Whether the transaction is marked as new |
| `review` | Optional `"unclearBooking"` for an unclear pending match or `"splitUndone"` for a split undone by a bank correction. Missing means no review. |
| `isFetched` | Whether a refresh delivered the transaction |
| `fileIdentity` | Original file fingerprint, if a file import recorded one; absent or null means no file identity |
| `isManual` | Optional `true` for a transaction that the user added with "Add Transaction...". Missing means a transaction that a source delivered. |
| `sourceID` | Identifier of the transaction at its bank or source, such as `moneymoney:<id>` |
| `createdAt` | Time when the app stored the transaction |

## Deleted transaction

What the app keeps of a transaction that the user deleted, so that no refresh, file, or migration adds it again. A manual transaction that no file and no migration matched leaves no record, because no source delivers it.

| Key | Content |
|---|---|
| `accountID` | The account |
| `fileIdentity` | Original file fingerprint, if a file import recorded one; absent or null means no file identity |
| `sourceID` | Identifier of the transaction at its bank or source |
| `bookingDate` | Booking day |
| `amount`, `currency` | Amount and its currency |
| `isPending` | Whether it was pending |
| `purpose` | Purpose |
| `counterpartyIBAN` | Account of the counterparty |
| `endToEndReference` | SEPA end-to-end reference |
| `wasFetched` | Whether a refresh had delivered it |
| `deletedAt` | Time of the deletion |

## Portfolio value

| Key | Content |
|---|---|
| `accountID` | The portfolio |
| `day` | Day of the value |
| `value`, `currency` | Value of the portfolio on that day and the currency of the portfolio. The reader refuses a different currency instead of converting it. |

## Holding

A position of a portfolio, as its bank reported it last.

| Key | Content |
|---|---|
| `id` | Identifier |
| `accountID` | The portfolio |
| `name`, `isin`, `securityNumber` | Name, ISIN, and German security number (WKN) of the security |
| `quantity` | Number of units, or the nominal amount, as decimal text |
| `isNominal` | Whether `quantity` is a nominal amount |
| `nominalCurrency` | Currency of the nominal amount |
| `price` | The price, with `amount` (decimal text), `currency` (missing for a price in percent), and `day` |
| `marketValue`, `accruedInterest` | Market value and accrued interest, each with `amount` and `currency` |
| `purchasePrice` | The purchase price, with `amount`, `currency`, and `day` like `price` |
| `exchangeRate` | The rate between two currencies, with `base`, `quoted`, and `rate` (decimal text, units of `quoted` for one unit of `base`) |

## Split part

Database migrations are v17 for the split table and v20 for review reasons. v18 adds file identity, v19 adds CSV profiles, and v23 adds the manual mark. The file format version is separate from these migration numbers.

Each split part has these keys.

| Key | Content |
|---|---|
| `id` | Identifier of the part |
| `transactionID` | Identifier of its original in `transactions` |
| `position` | Zero-based order within the split, a number |
| `amount` | Decimal amount text in the currency of the original, such as `"-100.00"` |
| `categoryID` | Identifier of its category, missing for "Uncategorized" |
| `comment` | Comment of this part, missing for none |
| `vat` | Optional object with `role` (`"net"` or `"tax"`) and `rate` (a number in hundredths of a percent, such as `1900` for 19 %, always above zero) |

The original stays once in `transactions` with its category and comment for undo. Parts stay in `splitParts`, never as additional transactions. Their IDs, links, positions, amounts, categories, comments, and VAT data survive an export and import. Each split has at least two parts of nonzero amounts that add up to its booked original. The reader refuses an unknown review reason or malformed part. The import refuses missing original or category references, duplicate row IDs or positions, negative positions, pending originals, and parts that break the split rules, without changing the target database.

## Version 1 compatibility

A version-1 file has neither `splitParts` nor `review`. The version-2 reader imports it with no parts and maps `needsReview: true` to `review: "unclearBooking"` and `needsReview: false` to no review. A version-2 file writes `review` and omits `needsReview`. The version-1 app refuses a version-2 file as needing a newer app.
