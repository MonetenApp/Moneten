# Extension coverage

This page records, as of 2026-11-15, which providers v0.1 reaches beyond FinTS through the published MoneyMoney Web Banking extensions, and what still blocks the others. It tells users which providers an extension can reach in Moneten, as far as made-up responses can show it, and tells the project which gaps in the extension host to close next.

## Method

- `scripts/check-published.sh` downloads every file of the [MoneyMoney extensions page](https://moneymoney.app/extensions/). The page lists 109 entries. 105 files are hosted, 101 of them are Web Banking extensions, and 100 of those are signed. The other 4 are export extensions, which `add-import-export-extensions` covers.
- The census of the script found no gap: all 101 load in the host, and the host offers every `MM` function and every method of a connection, an HTML document, an element list, and a JSON object that they use. A second census of the Lua standard library found only names that the runtime removes on purpose, such as `io.open` and `os.remove`. Each script tests for them before it calls them.
- Loading says little about running, so each extension then ran through `ext test` against a fixture with made-up responses that follow the shape its script parses. The fixtures use made-up names and amounts and the test IBAN DE02120300000000202051. No run contacted a provider. A failure counted as a gap of the host only when a copy of the script with that one cause removed ran to the end.
- "Runs" means the extension went through `SupportsBank`, the login with its challenges, `ListAccounts`, `RefreshAccount`, and `EndSession` in the host, and `ExtensionConnector` accepted every result. It does not prove that the provider still answers as the script expects. Only a real login can show that.
- The fixtures and the third-party scripts are not in the repository. Only the three extensions of the compatibility tests are, under `Fixtures/extensions`.

## Summary

| Status | Extensions |
|---|---|
| Runs on main | 45 |
| Runs with [#277](https://github.com/MonetenApp/Moneten/pull/277) | 41 |
| Runs with another open PR, some also with #277 | 8 |
| Partial: login and accounts work, orders need a second run | 2 |
| Blocked | 5 |

With the open PRs, 94 of the 101 extensions run in the host and 2 more run in part. 4 of the 94 run, but their recording cannot replay in `ext test`, see the smaller findings.

## Gaps by reach

| Gap | Extensions | State |
|---|---|---|
| G1. A security without `amount` failed the whole account ("Security 1 has no amount"). Most crypto, price, and peer-to-peer extensions give the quantity and the price and leave the value to the app. One script also keeps its securities under their names in the same table. | 45 | [#277](https://github.com/MonetenApp/Moneten/pull/277) |
| G2. The `account` table of `RefreshAccount` had no `balance` (Alpaca) and no `attributes` (Paddle, which reads a user-defined field). | 2 | [#286](https://github.com/MonetenApp/Moneten/pull/286). Paddle then needs the user-defined fields of `add-account-extras`. |
| G3. An account with `portfolio=false` and `type=AccountTypePortfolio` counted as a portfolio, so the app asked for `securities` where the script returns a balance and transactions. | 2 (both Whitebox) | [#288](https://github.com/MonetenApp/Moneten/pull/288) |
| G4. `ProtocolWebBanking` held "ProtocolWebBanking". Two scripts compare `protocol` with the text "Web Banking", so `SupportsBank` said no. | 2 | [#285](https://github.com/MonetenApp/Moneten/pull/285) |
| G5. A browser login (OAuth) opened only on a host that the user allowed, and a file install without a manifest had no host question for the login page, because the script returns the page before it sends a request there. A catalog package lists its hosts in the manifest and is not affected. | 2 (Monzo, Bondora) | [#280](https://github.com/MonetenApp/Moneten/pull/280) |
| G6. Plain HTTP. The spec refuses it on purpose (scenario "Plain HTTP"). | 2 (Appfigures, BitcoinHD) | Decided, see below |
| G7. A port other than 443. The host limit refuses it on purpose. | 1 (Ripple) | Decided, see below |
| G8. reCAPTCHA v3: the script returns the script URL with `render=<key>` and no `sitekey`, and expects the score token. The captcha window builds only the v2 widget. | 1 (DeutschlandCard) | Open |
| G9. A header name that is not a token, such as `:path:` copied from the developer tools of a browser, stopped the script. | 1 (Morgan Stanley StockPlan) | [#284](https://github.com/MonetenApp/Moneten/pull/284) |

Smaller findings:

- `MM.hexToBin` returned nil for a text of odd length. The Addiko script reads an RSA exponent from the login page, and such pages often write 65537 as "10001". [#290](https://github.com/MonetenApp/Moneten/pull/290) reads it with a leading 0.
- `click()` on an empty element list stopped the script, while the Amazon orders script tests the result for nil. [#290](https://github.com/MonetenApp/Moneten/pull/290) returns nothing.
- `MM.productVersion` is the version of Moneten. Kraken compares it with "2.3.4" field by field and stops when the number of fields differs. The app passes `MARKETING_VERSION`, which is "0.0.1" today, so a release as "0.1" would stop Kraken. [#282](https://github.com/MonetenApp/Moneten/pull/282) always gives three numbers.
- `ext test` fixes the clock and the random values of `MM`, but not `math.random`. EquatePlus and Pluxee put `math.random` into URLs, so their recordings cannot replay. The CoinGecko script builds a URL from `pairs`, whose order changes per run. Their catalog packages need a fixed seed in the replay, or a change in the script.

## Decisions for the owner

- **Plain HTTP and other ports (G6, G7).** Recommendation: keep both rules. Plain HTTP would send login data without encryption. The host limit and the host question name a host without a port, so a request to another port would reach a service that neither the manifest nor the user named. The two rules block only three small extensions. Their authors can switch to HTTPS on port 443 where the service offers it, and the catalog can take the fixed versions.
- **reCAPTCHA v3 (G8).** Supporting it needs a spec change and a page in the captcha window that runs the score variant. A score token comes from the page that the captcha window loads, so whether the service accepts it can only be checked with a real login. Recommendation: plan it after v0.1, unless DeutschlandCard is wanted for v0.1.

## Providers without a published extension

PayPal, American Express, Trade Republic, and Scalable Capital are not on the extensions page. MoneyMoney reads PayPal and Trade Republic with built-in code. [bank-access.md](bank-access.md) records the options: PayPal fits the extension API through its classic API and is a candidate for a first catalog extension of the project. Trade Republic needs a WebSocket, which the extension API does not offer, and so a decision record of its own. Until then these providers come in through the file import.

## Catalog proposals

The catalog `MonetenApp/moneten-extensions` can take the extensions whose authors chose a license from the allowlist of ADR 0015. Proposed first packages, by the users they likely reach: the crypto exchanges Kraken, Bitvavo, Bitstamp, Coinbase, Binance, Bitpanda, and bitcoin.de; the brokers Trading 212, Interactive Brokers, and CapTrader; Parqet; the peer-to-peer platforms Bondora, Estateguru, Twino, and Swaper; Amazon orders; Splitwise; and the business accounts Stripe, Mollie, and GoCardless. Each package needs a manifest with its hosts and login fields and a recording for `ext test`. The recordings of this research use made-up responses and are no substitute for a recording of a real login.

## Coverage

"Kind" is what the extensions page says the extension fetches: balance, transactions, portfolio, quotes, or statements.

| Provider | Extension | Kind | Status | Blocking gap or PR |
|---|---|---|---|---|
| Addiko Bank | AddikoAustria | balance, transactions | Runs | #290 if the login page writes the exponent with an odd length |
| Alpaca | Alpaca | portfolio | Runs with #286 | G2 |
| Amazon orders | amazon-bestellungen | transactions, balance | Partial | Partial: login and accounts; orders need a second run with stored data |
| Amazon orders | amazon-orders | transactions, balance | Partial | Partial: login and accounts; orders need a second run with stored data; `click()` on an empty list fixed by #290 |
| Appfigures | Appfigures | balance, transactions | Blocked | G6: plain HTTP (decided) |
| auxmoney | auxmoney | portfolio | Runs |  |
| Bank of America | Bank of America | transactions, balance, statements | Runs |  |
| Beel (formerly Tokenize.it) | Beel | balance, portfolio | Runs with #277 | G1 |
| Binance | binance | portfolio | Runs with #277 | G1 |
| Bitcoin HD | bitcoinHD | portfolio | Blocked | G6: plain HTTP (decided); G1 fixed by #277 |
| Bitcoin | Bitcoin | portfolio | Runs with #277 | G1 |
| Bitcoin.de | bitcoin.de | portfolio | Runs with #277 | G1 |
| Bitget | Bitget | portfolio | Runs |  |
| Bitpanda | bitpanda | portfolio | Runs |  |
| Bitstamp | bitstamp | portfolio | Runs with #277 | G1 |
| Bittrex | Bittrex | portfolio | Runs |  |
| Bitvavo | Bitvavo | portfolio, balance, transactions, quotes | Runs with #277 | G1 |
| Bondora | Bondora-OAuth2 | balance | Runs with #277 and #280 | G1, G5 |
| bonVito | bonVito | balance, transactions | Runs |  |
| Bosch Vorsorgeplan | BoschVorsorgeplan | balance | Runs |  |
| BUX Zero | Bux | portfolio | Runs |  |
| CapTrader | CapTrader | portfolio | Runs |  |
| Cardano | Cardano | portfolio | Runs with #277 | G1 |
| Chia | chia | portfolio | Runs with #277 | G1 |
| Coinbase Pro | Coinbase Pro | portfolio | Runs with #277 | G1 |
| Coinbase | Coinbase | portfolio | Runs |  |
| CoinTracking | Cointracking | portfolio | Runs |  |
| CoinTracking | CoinTrackingAPI | portfolio | Runs |  |
| Cosmos | Cosmos | portfolio | Runs with #277 | G1 |
| Crypto wallet quotes | coingecko | quotes | Runs | the order of `pairs` changes a URL of the replay |
| Crypto | CoinGeckoPortfolio | quotes | Runs with #277 | G1 |
| Crypto | Cryptocurrencies | quotes | Runs with #277 | G1 |
| Cryptopia | Cryptopia | portfolio | Runs with #277 | G1 |
| DeutschlandCard | Deutschlandcard-Punkte | balance, transactions | Blocked | G8: reCAPTCHA v3 |
| EBS.ie | EBS | balance, transactions | Runs |  |
| EOS | Eosio | portfolio | Runs with #277 | G1 |
| EquatePlus | EquatePlus | portfolio | Runs with #277 | G1; the replay needs a fixed `math.random` |
| EquatePlus | EquatePlus | portfolio, statements | Runs with #277 | G1; the replay needs a fixed `math.random` |
| EstateGuru | estateguru | portfolio | Runs with #277 | G1 |
| Ethereum (ERC20-Tokens) | ERC20 | portfolio | Runs with #277 | G1 |
| Ethereum (ERC20-Tokens) | Ether-Erc20-Tokens | portfolio | Runs with #277 | G1 |
| Ethereum | Ether | portfolio | Runs with #277 | G1 |
| Fidelity | Fidelity | portfolio, balance | Runs |  |
| finpension | finpension | portfolio | Runs |  |
| GEG-Gastro | GEG-Gastro | balance, transactions | Runs |  |
| Givve Prepaid | Givve Prepaid | transactions, balance | Runs |  |
| GoAndGrow | GoAndGrow | balance, transactions | Runs |  |
| GoCardless | GoCardless | balance, transactions | Runs |  |
| GranValora | GranValora | portfolio | Runs |  |
| HDI insurance | HDI | portfolio | Runs |  |
| HitBTC | hitbtc | portfolio | Runs with #277 | G1 |
| Interactive Brokers | ibkr | portfolio | Runs |  |
| IOTA | IOTA | portfolio | Runs with #277 | G1 |
| Kraken | Kraken | portfolio | Runs with #277 | G1; needs #282 for a version with two numbers |
| KuCoin | kucoin | portfolio | Runs with #277 | G1 |
| Litecoin | Litecoin | portfolio | Runs with #277 | G1 |
| Lloyds Bank UK | Lloyds Bank UK | balance, transactions | Runs with #285 | G4 |
| MLP insurance | MLP insurance | portfolio, balance | Runs |  |
| Mollie | Mollie | balance, transactions | Runs |  |
| Monzo | Monzo | balance, transactions | Runs with #280 | G5, file install only |
| Morgan Stanley StockPlan | StockPlanConnect | portfolio | Runs with #284 | G9 |
| Moventum | moventum | portfolio | Runs |  |
| Nano | Nano | portfolio | Runs with #277 | G1 |
| NEO | NEO | portfolio | Runs with #277 | G1 |
| Nimiq | Nimiq | portfolio | Runs with #277 | G1 |
| Oikocredit | oikokredit | portfolio | Runs |  |
| Paddle | Paddle | balance, transactions | Blocked | G2 fixed by #286; needs the user-defined field GroupTransactions of `add-account-extras` |
| Parqet | Parqet | portfolio | Runs with #277 | G1 |
| Paxum | Paxum | balance, transactions | Runs |  |
| PayLife MasterCard RED | MasterCard RED | balance, transactions | Runs with #285 | G4 |
| Permanent TSB Business | Permanent TSB Business | balance, transactions | Runs |  |
| Planetshares | Planetshares BNP Paribas | portfolio | Runs |  |
| Pluxee Benefits | Pluxee Benefits | transactions, balance | Runs | the replay needs a fixed `math.random` |
| Polkadot | dot | portfolio | Runs with #277 | G1 |
| Precious metals | MetalPortfolio | quotes | Runs with #277 | G1 |
| Presidential Bank | Presidential Bank | transactions, balance | Runs |  |
| Provinzial | Provinzial | balance, transactions | Runs |  |
| Real Estate Tracker | RealEstateTracker | portfolio | Runs |  |
| Ripple | Ripple | portfolio | Blocked | G7: port 51234 (decided); G1 fixed by #277 |
| Shares and derivatives (EUR) | StockPortfolio_EUR | quotes | Runs with #277 | G1 |
| Shares and derivatives (USD) | StockPortfolio_USD | quotes | Runs with #277 | G1 |
| Shares and derivatives | EODDataPortfolio | quotes | Runs |  |
| Shareview | Shareview | portfolio, balance | Runs |  |
| Shoop | Shoop | balance, transactions | Runs |  |
| Solana | Solana | portfolio | Runs with #277 | G1 |
| Splitwise | Splitwise | portfolio | Runs |  |
| Storj | Storj | portfolio | Runs with #277 | G1 |
| Stripe | Stripe | balance, transactions | Runs |  |
| Swaper | swaper | portfolio | Runs with #277 | G1 |
| Tchibo | tchiboMyAccount | balance, transactions | Runs |  |
| Tezos | Tezos | portfolio | Runs with #277 | G1 |
| Trading 212 | Trading212 | portfolio | Runs with #277 | G1 |
| TRON | TRON | portfolio | Runs with #277 | G1 |
| Twino | twino | portfolio | Runs with #277 | G1 |
| Umweltbank Depots | UmweltbankDepot | balance, portfolio | Runs |  |
| United Nations Federal Credit Union | unfcu | transactions, balance, statements | Runs |  |
| VIAC | VIAC | portfolio | Runs |  |
| Whitebox | Whitebox | portfolio | Runs with #277 and #288 | G1, G3 |
| Whitebox | Whitebox | transactions, balance, portfolio | Runs with #288 | G3 |
| Zcash | Zcash | portfolio | Runs with #277 | G1 |
| Zürcher Kantonalbank | ZKB | balance, transactions | Runs |  |
