# Data model

This page lists the core types in the `Domain` module. It is the target for v0.3. Fields marked (v0.2) or (v0.3) arrive in that release. [Architecture](architecture.md) explains how the types are used.

## Money and quantities

| Type | Fields | Rules |
|---|---|---|
| `Currency` | `code: String` | ISO 4217 code, three uppercase letters. |
| `Money` | `minorUnits: Int64`, `currency: Currency` | Exact integer arithmetic for settled amounts. Adding two amounts with different currencies throws an error. The type never converts currencies. No `Double` anywhere. |
| `Quote` | `value: Decimal`, `currency: Currency` | A price with more decimal places than the currency, for example a share price of 12.3456 euros. Valuations round to `Money` once, at the end. |
| `Totals` | `[Currency: Money]` | A sum across accounts keeps one total per currency. Exchange rates are out of scope until after v0.3. |
| `Quantity` | `value: Decimal` | Number of shares or units in a securities account. |
| `IBAN` | `value: String` | Validated with the ISO 13616 checksum when parsed. |

## Connections and accounts

| Type | Fields |
|---|---|
| `Connection` | `id`, `name`, `source: ConnectionSource`, `lastSync: Date?` |
| `ConnectionSource` | `.fints(bankCode, userID, customerID?, tanMethod?)`, `.extension(extensionID, service)`, `.finAPI(bankConnectionID)` (v0.3) |
| `AccountGroup` | `id`, `name`, `order`, `parentID?` |
| `Account` | `id`, `connectionID?`, `groupID?`, `kind: AccountKind`, `name`, `owner?`, `iban: IBAN?`, `accountNumber?`, `bankCode?`, `currency`, `isHidden` |
| `AccountKind` | `giro`, `savings`, `fixedTermDeposit`, `loan`, `creditCard`, `portfolio`, `cash`, `other` |
| `BalanceSnapshot` | `accountID`, `date`, `booked: Money`, `pending: Money?` |

An account without a `connectionID` is a manual account. You fill it by hand or by import.

Secrets are not part of the model. The Keychain stores the PIN for a connection under the connection's `id`.

## Transactions

| Field | Type | Notes |
|---|---|---|
| `id` | `UUID` | Local identity. |
| `accountID` | `UUID` | |
| `status` | `pending` or `booked` | |
| `bookingDate` | `Date` | Day precision. |
| `valueDate` | `Date?` | |
| `amount` | `Money` | Negative for debits. |
| `counterparty` | `Counterparty?` | `name`, `iban`, `bic`. |
| `purpose` | `String` | Remittance text, newlines kept. |
| `references` | `References` | `endToEnd`, `mandate`, `creditorID`, `bankReference`. |
| `transactionCode` | `String?` | The bank's business transaction code (Geschäftsvorfallcode, GVC). |
| `sourceID` | `String?` | Stable ID from the source, if it has one. |
| `fingerprint` | `String` | Identity for sources without `sourceID`. See [architecture](architecture.md#transactions-need-an-identity-the-bank-does-not-give). |
| `categoryID` | `UUID?` | |
| `categorizedBy` | `.manual`, `.rule(UUID)`, or `.none` | Manual choices are never overwritten by rules. |
| `note` | `String?` | |
| `importBatchID` | `UUID?` | Set when the row came from a file import. |

## Categories and rules

| Type | Fields | Rules |
|---|---|---|
| `Category` | `id`, `parentID?`, `name`, `order`, `isHidden` | A tree. Deleting a category moves its transactions to the parent. |
| `Rule` | `id`, `order`, `match: .all` or `.any`, `conditions: [Condition]`, `categoryID` | Rules run in `order`. The first match wins. |
| `Condition` | `field`, `op`, `value` | `field` is one of counterparty name, counterparty IBAN, purpose, amount, account, transaction code. `op` is one of contains, equals, starts with, matches regex, less than, greater than. |

## Securities (v0.2)

| Type | Fields |
|---|---|
| `Security` | `isin?`, `wkn?`, `name` |
| `Holding` | `accountID`, `date`, `security`, `quantity: Quantity`, `price: Quote?`, `marketValue: Money`, `purchaseValue: Money?` |

## Payments (v0.2)

| Type | Fields |
|---|---|
| `PaymentOrder` | `id`, `accountID`, `kind: .sepa` or `.instant`, `payee: Counterparty`, `amount`, `purpose`, `endToEnd?`, `executionDate?`, `payeeCheckID?` |
| `PaymentState` | `draft`, `payeeCheck(PayeeCheckResult)`, `confirmed`, `needsChallenge(Challenge)`, `submitted`, `accepted`, `rejected(reason)`, `unknown`. A change to payee, IBAN, or amount returns the order to `draft`. |
| `PayeeCheckResult` | `match`, `closeMatch(suggestedName)`, `noMatch`, `notPossible` |

## Import

| Type | Fields |
|---|---|
| `ImportBatch` | `id`, `source: .csv`, `.camt`, `.mt940`, or `.moneyMoney`, `fileName`, `importedAt`, `accounts`, `transactions`, `categories` |
| `CSVProfile` | Column mapping, date format, decimal separator, encoding. Saved per bank so the second import of the same format needs no setup. |
