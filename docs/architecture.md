# Architecture

This page explains how MonetenMoneten is split into modules, how data flows from a bank into the database, and why each boundary sits where it does. The exact fields of each type are in [data model](data-model.md). The reasons behind the big choices are in [decisions](decisions/).

## The modules and what each one owns

```
┌───────────────────────── MonetenMoneten.app (SwiftUI) ─────────────────────────┐
│  Sidebar · Transactions · Categories · Rules · Charts · Transfers · Settings   │
└───────────────┬──────────────────────────────┬─────────────────────────────────┘
                │                              │
        ┌───────▼────────┐             ┌───────▼────────┐
        │     Domain     │◄────────────│    Storage     │  GRDB + SQLCipher, Keychain
        │  pure Swift,   │             └────────────────┘
        │  no I/O        │
        └───────▲────────┘
                │ SyncEvent, Challenge, PaymentState
     ┌──────────┼──────────────────┬──────────────────────┐
┌────┴─────┐ ┌──┴─────────────┐ ┌──┴───────────┐ ┌────────┴───────┐
│  FinTS   │ │   Extension    │ │    finAPI    │ │     Import     │
│connector │ │   connector    │ │  connector   │ │ CSV, CAMT,     │
│(HBCI4-   │ │       │ XPC    │ │   (v0.3)     │ │ MT940,         │
│ Swift)   │ │ ┌─────▼──────┐ │ └──────────────┘ │ MoneyMoney     │
└──────────┘ │ │ Lua host   │ │                  └────────────────┘
             │ └────────────┘ │
             └────────────────┘
```

The repository is one Swift package workspace with an Xcode app target:

| Module | Owns | Depends on |
|---|---|---|
| `Domain` | Types, money arithmetic, the rule engine, de-duplication, the sync and payment state machines | Nothing |
| `Storage` | The encrypted database, migrations, queries, Keychain access | `Domain`, GRDB |
| `FinTSConnector` | Bank lookup, FinTS dialogs, TAN handling, mapping FinTS data to `Domain` types | `Domain`, HBCI4Swift |
| `ExtensionConnector` | Starting the XPC host, mapping extension results to `Domain` types | `Domain` |
| `ExtensionHost` | The XPC service that runs one Lua extension with the MoneyMoney-compatible API | Lua 5.4 |
| `FinAPIConnector` | finAPI login through its web form and data mapping (v0.3) | `Domain` |
| `Import` | File parsers that return an `ImportBatch` | `Domain` |
| `ext` | A command line tool that runs and tests an extension without the app | `ExtensionHost` |
| `App` | SwiftUI views, view models, window and menu wiring | All of the above |

`Domain` has no dependencies so that every rule about money, categories, and transaction identity can be tested in milliseconds without a database, a network, or a bank.

## Every bank speaks through one protocol

FinTS, extensions, and finAPI differ in almost everything. The app hides that behind one protocol in `Domain`:

```swift
protocol BankConnector {
	func listAccounts(_ session: SyncSession) async throws -> [RemoteAccount]
	func refresh(_ account: RemoteAccount, since: Date?, _ session: SyncSession) async throws -> RefreshResult
}

protocol PaymentConnector: BankConnector {
	func send(_ payment: PaymentOrder, _ session: SyncSession) async throws -> PaymentReceipt
}
```

`SyncSession` is how a connector asks the user for something. A connector calls `session.ask(_ challenge: Challenge)` and waits for the answer. `Challenge` is one enum for all sources:

```swift
enum Challenge {
	case chooseTANMethod([TANMethod])
	case enterTAN(prompt: String, image: Data?)
	case flickerCode(String)
	case approveInApp(prompt: String)
	case openBrowser(URL)
}
```

One enum means one set of dialogs in the app. A pushTAN from FinTS, an app approval in an extension, and the finAPI web form all reach the user through the same screens.

Only `FinTSConnector` and `FinAPIConnector` conform to `PaymentConnector`. `ExtensionConnector` does not, so the app itself never sends a payment through an extension. This does not stop a malicious extension from submitting a form on a bank website it is allowed to reach. The sandbox limits which hosts it reaches, and the catalog review is the protection against that case.

## A sync is a state machine

A sync of one connection moves through fixed states:

```
idle → connecting → (needsChallenge ⇄ connecting) → fetching → finished
                                                              ↘ failed
```

The state lives in one `SyncState` value per connection. The UI reads it to show progress, the TAN dialog, or the error. No view keeps its own copy of "is syncing" flags.

## Transactions need an identity the bank does not give

FinTS returns transactions without a stable ID. A second sync returns the same rows again, and a pending card payment comes back later as a booked one with a different date or text. `Domain` handles this with two pure functions:

- `fingerprint(_:)` builds an identity from the account, booking date, amount, counterparty IBAN, end-to-end reference, and normalized purpose text. Identical rows on the same day get an occurrence index.
- `reconcile(existing:incoming:)` matches incoming rows to stored ones, one to one. It replaces a pending row with its booked version only when exactly one pending row matches the amount and counterparty within a few days. If two pending rows could match, for example two identical coffees on one day, it keeps all rows and marks them for review instead of guessing. Categories and notes move to the booked row.

If a source gives a stable ID, as some extensions do with `transactionId`, the app uses that ID and skips the fingerprint.

## External data is parsed once, at the edge

Bank responses, extension results, and import files are untrusted input. Each connector and each import parser turns raw data into `Domain` types at its edge and rejects what it cannot parse with an error that names the field. Code inside `Domain`, `Storage`, and `App` trusts those types and does not check them again.

## Secrets stay in the Keychain

- The database is encrypted with SQLCipher. Its key is a random 256-bit value in the macOS Keychain, readable only by MonetenMoneten, and unlocked with Touch ID or the login password.
- Bank PINs live in the Keychain, one item per connection. They never enter the database or a log.
- TANs are never stored.
- Logs never contain PINs, TANs, passwords, cookies, or tokens. The app removes them from its own output, from HBCI4Swift output, and from recorded HTTP traffic, and no setting turns that off.
- Logs also redact IBANs, names, and amounts by default. A debug switch shows those for one sync, and the app warns before you share the log.

## Extensions run in a sandbox

Each extension runs in its own XPC process with only the network client entitlement. The host enforces three limits:

1. The extension can only contact hosts listed in its manifest.
2. The extension gets the credentials of its own connection and nothing else.
3. The extension's `LocalStorage` is kept by the app, per connection, inside the encrypted database.

The API follows the [MoneyMoney Web Banking API](https://moneymoney.app/api/webbanking/), so most existing extensions run without changes. [ADR 0004](decisions/0004-moneymoney-compatible-extension-api.md) lists what is compatible and what MonetenMoneten adds.

## Payments are a separate state machine

A transfer moves through these states, and the app saves every step:

```
draft → payeeCheck → confirmed → (needsChallenge) → submitted → accepted
                                                               ↘ rejected
```

`payeeCheck` asks the bank for the Verification of Payee result with `HKVPP`. You confirm the transfer after you see that result, never before. The app then sends the transfer together with `HKVPA`, which binds it to the checked payee. Any change to payee, IBAN, or amount after the check sends the payment back to `draft`. The bank may skip the TAN step, for example for a trusted payee, so `needsChallenge` is optional. A crash or a lost connection leaves the payment in a saved state, and the app shows it as "unknown" until the bank confirms or rejects it. The app never resends a payment on its own.

## The app ships outside the App Store

MonetenMoneten is signed with a Developer ID, notarized by Apple, and updated through Sparkle. The App Store is not an option because its terms conflict with the GPL. [ADR 0006](decisions/0006-license-gpl-3.md) has the details.

## The subscription service is a separate project

The optional finAPI subscription (v0.3) needs a server that holds the finAPI client secret, manages subscriptions, and creates a finAPI user for each subscriber. That server lives in its own repository under the AGPL. It passes data through to the app and stores no transactions. [ADR 0007](decisions/0007-optional-finapi-subscription.md) explains the design.

## Repository layout

```
monetenmoneten/
├── App/                     Xcode app target
├── Packages/
│   ├── Domain/
│   ├── Storage/
│   ├── FinTSConnector/
│   ├── ExtensionConnector/
│   ├── ExtensionHost/
│   ├── FinAPIConnector/     (v0.3)
│   └── Import/
├── Tools/ext/               Extension command line tool
├── Extensions/              Example extensions
├── Fixtures/                Recorded bank responses for tests, anonymized
└── docs/
```
