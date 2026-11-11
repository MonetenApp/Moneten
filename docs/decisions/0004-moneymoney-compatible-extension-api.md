# 0004. Make the extension API compatible with MoneyMoney

Status: Accepted

## Context

Many services have no FinTS access, for example brokers such as Trade Republic, credit card portals, PayPal, and crypto exchanges. The core team cannot maintain connections to all of them. Community extensions can.

MoneyMoney already has a public Lua extension API, the [Web Banking API](https://moneymoney.app/api/webbanking/), and people have published extensions for it on GitHub, for example for Qonto, Bitpanda, and Binance. Banking4 has no extension system.

An API is a description of an interface. Re-implementing an interface for compatibility is allowed under EU law (CJEU, SAS Institute v World Programming, C-406/10, 2012). Copying MoneyMoney's code, name, or design is not, and the project does neither.

## Decision

Moneten runs Lua 5.4 extensions with an API that is compatible with the MoneyMoney Web Banking API:

- The entry points `WebBanking{}`, `SupportsBank`, `InitializeSession`, `InitializeSession2`, `ListAccounts`, `RefreshAccount`, `FetchStatements`, and `EndSession`.
- The helpers `Connection`, `HTML`, `JSON`, `PDF`, `LocalStorage`, and the `MM` functions.
- The two-factor challenge tables, mapped to the app's `Challenge` enum.

Moneten adds three things:

1. A manifest next to the script that lists the hosts the extension contacts and the labels of its credential fields.
2. An embedded browser window for logins that need a captcha or a redirect.
3. An API version number, so that later changes do not break old extensions.

## Consequences

- MoneyMoney users can bring their extensions along.
- Extension authors can write once for both apps.
- The project must track changes to the MoneyMoney API. Differences are listed in the extension docs.
- Payment functions of the MoneyMoney API are not supported. See [0008](0008-payments-only-through-licensed-channels.md).
