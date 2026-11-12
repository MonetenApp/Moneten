# Architecture

This page explains how Moneten is split into modules, how data flows from a bank into the database, and why each boundary sits where it does. The exact fields of each type are in [data model](data-model.md). The reasons behind the big choices are in [decisions](decisions/).

The first build has six modules: `Domain`, `Storage`, `Import`, `Sync`, `SyncTesting`, and `App`. Bank connectors, extensions, payments, and the log are planned. Each section below says when it describes the plan.

## The modules and what each one owns

The diagram shows the target design.

```
┌───────────────────────── Moneten.app (SwiftUI) ─────────────────────────┐
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
│(hbci4java│ │       │ XPC    │ │   (v0.3)     │ │ MT940,         │
│ helper)  │ │ ┌─────▼──────┐ │ └──────────────┘ │ MoneyMoney     │
└──────────┘ │ │ Lua host   │ │                  └────────────────┘
             │ └────────────┘ │
             └────────────────┘
```

The libraries are one Swift package at the root of the repository. The app target is an Xcode project in `App/`, generated from `App/project.yml` ([ADR 0011](decisions/0011-app-target-in-an-xcode-project.md)). These modules exist:

| Module | Owns | Depends on |
|---|---|---|
| `Domain` | Types, money arithmetic, the in-memory `Ledger`, the rule engine, categorization, import matching, chart data, and the sync model: the connector protocol, the requests to the user, and the refresh states | Nothing |
| `Storage` | The encrypted database, migrations, loading and saving the ledger, Keychain access | `Domain`, GRDB |
| `Import` | The MoneyMoney migration and the CSV, CAMT, and MT940 parsers. `TransactionFileImporter.parse` returns `[Transaction]`, and `MoneyMoneyMigration.plan` returns a `Plan` that the app shows before it stores anything. | `Domain` |
| `Sync` | `SyncCoordinator`, which refreshes up to three accesses at a time with one `SyncState` each, and `SessionBroker`, which shows one dialog at a time and keeps the PINs in memory | `Domain` |
| `SyncTesting` | `ScriptedConnector`, which plays requests, progress, results, and failures in place of a bank, for the tests, the previews, and the debug harness | `Domain` |
| `App` | SwiftUI views, the `AppModel`, window and menu wiring | All of the above |

These modules are planned:

| Module | Owns | Depends on |
|---|---|---|
| `FinTSConnector` | Bank lookup, FinTS dialogs, TAN handling, mapping FinTS data to `Domain` types | `Domain`, the hbci4java helper process ([ADR 0014](decisions/0014-fints-through-hbci4java.md)) |
| `ExtensionConnector` | Starting the XPC host, mapping extension results to `Domain` types | `Domain` |
| `ExtensionHost` | The XPC service that runs one Lua extension with the MoneyMoney-compatible API | Lua 5.4 |
| `FinAPIConnector` | finAPI login through its web form and data mapping (v0.3) | `Domain` |
| `ext` | A command line tool that runs and tests an extension without the app | `ExtensionHost` |

The sync state machine described below is in `Domain`. The payment state machine will be there too.

`Domain` has no dependencies so that every rule about money, categories, and transaction identity can be tested in milliseconds without a database, a network, or a bank.

## Every bank speaks through one protocol

The protocol and the dialogs exist. The connectors are the plan.

FinTS, extensions, and finAPI differ in almost everything. The app hides that behind one protocol in `Domain`:

```swift
protocol BankConnector {
	func refresh(_ request: RefreshRequest, _ session: SyncSession) async throws -> ConnectorReport
}

protocol PaymentConnector: BankConnector {
	func send(_ payment: PaymentOrder, _ session: SyncSession) async throws -> PaymentReceipt
}
```

A refresh covers all requested accounts of one access, that is one login at one source, so FinTS keeps them in one dialog. Listing the accounts of a new access joins the protocol with the FinTS connector. `SyncSession` is how a connector asks the user for something. A connector calls `session.ask(_:)` with a PIN request or a second-factor request and waits for the answer. `Challenge` is one enum for all sources:

```swift
enum Challenge {
	case chooseTANMethod([TANMethod], current: TANMethod.ID?)
	case chooseTANMedium([String])
	case enterTAN(prompt: String, image: ChallengeImage?)
	case flickerCode(prompt: String, code: FlickerCode)
	case approveInApp(prompt: String, app: String?, image: ChallengeImage?, step: Step?)
	case openBrowser(URL)
}
```

The [design of add-account-refresh](../openspec/changes/add-account-refresh/design.md) has the complete types, the dialog queue, and how the callbacks of hbci4java map to these requests.

One enum means one set of dialogs in the app. A pushTAN from FinTS, an app approval in an extension, and the finAPI web form all reach the user through the same screens.

Only `FinTSConnector` and `FinAPIConnector` conform to `PaymentConnector`. `ExtensionConnector` does not, so the app itself never sends a payment through an extension. This does not stop a malicious extension from submitting a form on a bank website it is allowed to reach. The sandbox limits which hosts it reaches, and the catalog review is the protection against that case.

## A sync is a state machine

`SyncState` and its transitions are built. The connectors that drive them are the plan.

A sync of one connection moves through fixed states:

```
idle → connecting → fetching → finished
          ⇅            ⇅
      needsUser    needsUser          any state → failed or cancelled
```

A request for the user can come during the fetch too: Consorsbank waives the second factor at the login and requires it for the balance and the transactions. The state lives in one `SyncState` value per access. The UI reads it to show progress, the TAN dialog, or the error. No view keeps its own copy of "is syncing" flags.

## Transactions need an identity the bank does not give

Today the app gets transactions from the MoneyMoney migration and from files. A migrated transaction keeps its MoneyMoney ID in `sourceID`, so a second migration skips it. A file has no IDs, so `ImportMatching.split(imported:existing:)` treats two transactions as the same when the day, the amount, the name, and the purpose match. It counts equal rows, so two identical rows in one file add two transactions.

FinTS needs more. It returns transactions without a stable ID. A second sync returns the same rows again, and a pending card payment comes back later as a booked one with a different date or text. The plan is two pure functions in `Domain`:

- `fingerprint(_:)` builds an identity from the account, booking date, amount, counterparty IBAN, end-to-end reference, and normalized purpose text. Identical rows on the same day get an occurrence index.
- `reconcile(existing:incoming:)` matches incoming rows to stored ones, one to one. It replaces a pending row with its booked version only when exactly one pending row matches the amount and counterparty within a few days. If two pending rows could match, for example two identical coffees on one day, it keeps all rows and marks them for review instead of guessing. Categories and notes move to the booked row.

If a source gives a stable ID, as some extensions do with `transactionId`, the app uses that ID and skips the fingerprint.

## External data is parsed once, at the edge

Bank responses, extension results, and import files are untrusted input. Each import parser, and later each connector, turns raw data into `Domain` types at its edge and rejects what it cannot parse with an error that names the field. Code inside `Domain`, `Storage`, and `App` trusts those types and does not check them again.

## The database password protects everything

Moneten handles secrets the way MoneyMoney does. [ADR 0009](decisions/0009-database-password-as-in-moneymoney.md) has the details.

- The database is encrypted with SQLCipher. The key comes from the database password that you set at first launch or later. Until you set one, a random key in the Keychain protects the database.
- Saving the password in the Keychain is optional. You need it saved to unlock automatically at launch, with Touch ID, or with an Apple Watch.
- You can make the app lock after a set time without activity or when the main window closes.

The rest of this list is the plan for bank access and the log:

- A PIN is saved only if you turn on saving for that connection, and then only inside the encrypted database. Otherwise the app asks once and keeps it in memory until the app locks or quits.
- TANs are never stored.
- Logs never contain PINs, TANs, passwords, cookies, or tokens. The app removes them from its own output, from the output of the FinTS helper, and from recorded HTTP traffic, and no setting turns that off.
- Logs also redact IBANs, names, and amounts by default. A debug switch shows those for one sync, and the app warns before you share the log.

## Extensions run in a sandbox

This section is the plan for extensions.

Each extension runs in its own XPC process with only the network client entitlement. The host enforces three limits:

1. The extension can only contact hosts listed in its manifest.
2. The extension gets the credentials of its own connection and nothing else.
3. The extension's `LocalStorage` is kept by the app, per connection, inside the encrypted database.

The API follows the [MoneyMoney Web Banking API](https://moneymoney.app/api/webbanking/), so most existing extensions run without changes. [ADR 0004](decisions/0004-moneymoney-compatible-extension-api.md) lists what is compatible and what Moneten adds.

## Payments are a separate state machine

This section is the plan for payments (v0.2).

A transfer moves through these states, and the app saves every step:

```
draft → payeeCheck → confirmed → (needsChallenge) → submitted → accepted
                                                               ↘ rejected
```

`payeeCheck` asks the bank for the Verification of Payee result with `HKVPP`. You confirm the transfer after you see that result, never before. The app then sends the transfer together with `HKVPA`, which binds it to the checked payee. Any change to payee, IBAN, or amount after the check sends the payment back to `draft`. The bank may skip the TAN step, for example for a trusted payee, so `needsChallenge` is optional. A crash or a lost connection leaves the payment in a saved state, and the app shows it as "unknown" until the bank confirms or rejects it. The app never resends a payment on its own.

## The app ships outside the App Store

Releases are signed with the Developer ID of Adanos Software GmbH, notarized by Apple, and updated through Sparkle. `scripts/build-app.sh developer-id` signs with the Developer ID today. Notarization and Sparkle come with issue #25. Other builds sign with the team in `App/Local.xcconfig`, or to run locally without a team. The App Store is not an option because its terms conflict with the GPL. [ADR 0006](decisions/0006-license-gpl-3.md) has the details.

## The subscription service is a separate project

The optional finAPI subscription (v0.3) needs a server that holds the finAPI client secret, manages subscriptions, and creates a finAPI user for each subscriber. That server lives in its own repository under the AGPL. It passes data through to the app and stores no transactions. [ADR 0007](decisions/0007-optional-finapi-subscription.md) explains the design.

## Repository layout

```
Moneten/
├── Package.swift            The Swift package of the libraries
├── Sources/
│   ├── Domain/
│   ├── Storage/
│   ├── Import/
│   ├── Sync/
│   └── SyncTesting/
├── Tests/                   One test target per library
├── App/                     The app target: project.yml, sources, Info.plist, resources
│   └── FinTSProbe/          The FinTS prototype of issue #11
├── Vendor/
│   └── HBCI4Swift/          Git submodule of the Swift probe, until #13 (ADR 0014)
├── scripts/                 Test, build, project, and check scripts
├── openspec/                Specs of every change
└── docs/
```

The planned modules get their own folders under `Sources/`. Recorded bank responses for tests arrive with the FinTS connector.
