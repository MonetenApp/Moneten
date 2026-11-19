# Design

## Context

Issue #31 moved into v0.1 after the bank test of issue #11: a Consorsbank depot shows its total value (#112, #126) and no positions. The FinTS helper of [ADR 0014](../../../docs/decisions/0014-fints-through-hbci4java.md) already sends the custody account balance (HKWPD) for a securities account, and hbci4java already reads its MT535 answer into `GVRWPDepotList`. The helper today sums the positions into the value of the account and drops the rest.

What main already has, and this change keeps:

- A portfolio shows `bankBalanceMinor` through `Account.reportedBalance`, so its value counts in the sidebar, in the sum of its group, and in the total of all accounts ("Portfolio value in sums").
- `PortfolioValue` records that value once a day, `Store.merge` and `Store.save` write the record together with the account, and `Store.loadLedger` adds a missing record ("Daily record of the portfolio value", "Record the balance of a saved portfolio", "Record a missing portfolio balance at open"). The balance chart of a group draws a portfolio from its first record on.
- The value of a securities account is the total that the bank sends (HOLP), or else the sum of the values of its positions with their accrued interest, on the day of the statement. An empty securities account is worth 0 (#112). A holding without a value counts with its quantity times its price, and holdings in more than one currency count with their values in the currency of the account when the bank sends them; otherwise the account fails, so no sum leaves out a holding (#241).

So v0.1 adds the positions themselves: the types, their table, the positions in the result of the helper, the merge that replaces them, and the view.

## Scope of v0.1

v0.1 builds what the issue asks for: the types and their storage, the positions from HKWPD, a view with quantity, price, value, and the gain since purchase, and the value of securities in the totals and the balance chart. The requirements that the view needs to be usable come with it: the order, the search, the status line with the sum of the selected positions, the empty state, the total gain of a portfolio group, and a group of portfolios.

The details of a position, entering and editing the purchase price and keeping it across a refresh, and comments moved to the change `defer-v0.1-follow-ups` on 19 November 2026 with their requirements. The warning before removing a portfolio stays open in `tasks.md`.

## Decisions

### Types in `Domain`

`Domain` owns the types and the valuation, and nothing in them does I/O.

- `Security`: `name`, `isin?`, `securityNumber?`. The security number is the WKN that MT535 sends after `/DE/`.
- `Quote`: `amount: Decimal`, `currency: String?`, `day: Day?`. A quote without a currency is a percentage of the nominal amount, as the price of a bond. The purchase price is a `Quote` too, with the purchase day as its day.
- `ExchangeRate`: `base`, `quoted`, `rate: Decimal`. One unit of `base` costs `rate` units of `quoted`, as in field 92B of MT535 and in the unit currency and quoted currency of ISO 20022. `convert(_:from:to:)` works in both directions and returns nil for any other pair of currencies.
- `Holding`: `id`, `accountID`, `security`, `quantity: Decimal`, `isNominal`, `nominalCurrency?`, `quote?`, `marketValue: Money?`, `accruedInterest: Money?`, `purchasePrice: Quote?`, `exchangeRate?`. A quantity with `isNominal` is a nominal amount, and one without is a number of units. The currency of a nominal amount can be unknown.

Prices and quantities are `Decimal` and keep every decimal place that the bank sends. The database stores them as text, because SQLite has no decimal type and a double loses places. The amounts that the bank sends as a value (HOLD) and as accrued interest (ACRU) have the decimals of their currency, so they are `Money` with minor units, as every other amount of the app.

### Valuation

`Holding` computes, in `Domain`:

- `value`: the market value plus the accrued interest, converted with the exchange rate when the interest is in another currency. This is what the position adds to the account, so the values of all positions add up to the total of the bank. MT535 defines HOLP as the sum of the market values and the accrued interest of the positions. When the bank sends no market value, the value is the quantity times the quote, divided by 100 for a percentage, converted with the exchange rate into the currency of the account when the rate links the two currencies, and rounded to the currency once, at the end.
- `purchaseValue`: the quantity times the purchase price, divided by 100 for a percentage, converted the same way into the currency of the value.
- `gain`: the market value without the accrued interest, less the purchase value, and the percentage of the purchase value. The accrued interest is not part of the gain, because the purchase price of a bond is a price without interest. A position without a purchase price, or whose purchase value cannot be converted into the currency of its value, has no gain.

All arithmetic is `Decimal`. Only the final value, purchase value, and gain round to minor units, with `Money(_:currency:)`.

### The helper sends the positions

`FinTSHelper.value` adds `holdings` to the result line of a securities account, one object for each position of every page, from the fields that hbci4java parses: `name`, `isin`, `wkn`, `quantity` and `nominal` (true for FAMT), `currency` (70E), `price` with `amount` and `currency` (`%` for PRCT) and `day`, `value` (HOLD), `accrued` (ACRU), `purchase` (70E line 2, `%` for a percentage) with `day` (the purchase date of 70E), and `rate` (92B) with `base`, `quoted`, and `rate`. Amounts travel as plain decimal text. hbci4java keeps the exchange rate as a `double`, and the helper writes it with `BigDecimal.valueOf`, which gives the shortest decimal text of that double. The balance stays as #112 computes it. The helper writes nothing about a position to stderr.

hbci4java drops some fields of MT535 that the spec names: the time of a quote that has only a date, the market as a name, and the asset class. The market (94B) is kept by hbci4java and is not sent yet, because only the details of a position show it.

### The connector maps the positions

`AccountResult` in `Sources/FinTS/HelperProtocol.swift` decodes `holdings` and maps each one to a `Holding` of the requested account. The name is the name of the bank, or else the ISIN, or else the WKN. The currency of a nominal amount is the currency of the security (70E). Without it the currency stays unknown, and the quantity shows without a currency: the value of the bank may already be converted into the currency of the depot, so it does not tell the currency of a foreign bond, and a guess would show a wrong gain. Such a position shows the value of the bank and no gain. A number that does not read fails the account, as a row of a transaction does. `RefreshResult.holdings` carries them, and nil means that the source sent no positions, as an extension today, so nothing replaces the stored ones.

### The merge replaces the positions

`reconcile` gets the stored positions of the account and returns the delivered ones in `Reconciliation.holdings`. A delivered position takes the `id` of a stored position with the same ISIN. A position that finds none takes the `id` of a stored one with the same WKN, or else the same name, but only when one of the two has no ISIN, because two different ISINs are two securities. Each stored position matches at most once. The view keeps its rows and their selection across a refresh that way, and a later comment or manual purchase price can stay with the position (spec "A refresh replaces the positions"). Every position that the delivery lacks goes. `Store.merge` reads the stored positions only for a refresh that brings positions, deletes them, and inserts the delivered ones in the same transaction as the value, and `Ledger.apply` takes them over. `Ledger.replace(accounts:)` drops the positions of a removed account, as the database does. A failed refresh has no delivery, so the last positions stay, and the header keeps "Balance as of" with the day of the last successful refresh.

### Storage

Migration `v14` in `Sources/Storage/Schema.swift` adds the table `holding`, one row per position, with the columns of `Holding` flattened and `accountID` as a foreign key with `ON DELETE CASCADE`, so the positions go with their account. `HoldingRecord` in `Storage` maps a row to a `Holding`, as `AccessRecord` does for an access. `Store.loadLedger` reads them, and `Ledger.holdings(of:)` lists the positions of an account.

### The view

`App/Sources/Views/HoldingsView.swift` holds the list of positions and its status line. `TransactionsView` shows it in place of the filter bar, the transaction table, and the status line, when the selection is a portfolio or a group whose accounts are all portfolios, and none of them has transactions. A portfolio taken over from MoneyMoney can have rows, which would otherwise disappear. The header band, the chart, and the search field stay. The transaction table keeps its structure, so this change does not touch the code of #151.

The list is a `Table` of its own with the columns "Name", "Quantity", "Purchase price", "Last quote", "Value", and "Profit/Loss". The name shows the ISIN or WKN below it, the last quote its day, and "Profit/Loss" the percentage below the amount. The rows are the `Holding` values with their stable IDs, so a refresh updates rows in place. The table carries `.id` of the selection only and never of the data, so it never starts over in the same update as a change of the ledger (#135, #144, #151). It stays also without rows, with the empty state on top, so a refresh that sells the last position does not remove it. A portfolio without transactions has an empty transaction list, which shows no `Table`, so the swap between the two views never removes a filled table, also not when the user makes an account a portfolio in its settings.

The header shows the total gain of the positions in the upper right corner, below the balance, when the selection holds only portfolios.

## Risks / Trade-offs

- hbci4java parses the exchange rate into a `double`. A rate with more than 15 significant digits loses places. Banks send rates with at most 6 to 8.
- The direction of 92B follows ISO 15022 (one unit of the first currency costs the rate in the second). A bank that sends it the other way would show a wrong gain for a foreign purchase price. The bank test of the operator checks it with a foreign position.
- A position whose purchase price is in another currency than its value, without an exchange rate, shows the purchase price and no gain. The user can correct it with "Edit Purchase Price..." once that task is built.
- The total in the header is the total of the bank. When the bank sends a HOLP that differs from the sum of its positions, the status line and the header differ by that amount.
