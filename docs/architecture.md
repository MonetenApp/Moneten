# Architecture

This page explains how Moneten is split into modules, how data flows from a bank into the database, and why each boundary sits where it does. The exact fields of each type are in [data model](data-model.md). The reasons behind the big choices are in [decisions](decisions/).

The first build has nine modules: `Domain`, `Storage`, `Import`, `Sync`, `SyncTesting`, `FinTS`, `ExtensionHost`, `ExtensionConnector`, and `App`. The other bank connectors, payments, and the log are planned. Each section below says when it describes the plan.

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
│    │pipe │ │       │ pipe   │ │   (v0.3)     │ │ MT940,         │
│┌───▼────┐│ │ ┌─────▼──────┐ │ └──────────────┘ │ MoneyMoney     │
││  Java  ││ │ │ Lua host   │ │                  └────────────────┘
││ helper ││ │ └────────────┘ │
│└────────┘│ └────────────────┘
└──────────┘
```

The libraries are one Swift package at the root of the repository. The app target is an Xcode project in `App/`, generated from `App/project.yml` ([ADR 0011](decisions/0011-app-target-in-an-xcode-project.md)). These modules exist:

| Module | Owns | Depends on |
|---|---|---|
| `Domain` | Types, money arithmetic, the in-memory `Ledger`, the rule engine, categorization, import matching, chart data, and the sync model: the connector protocol, the requests to the user, and the refresh states | Nothing |
| `Storage` | The encrypted database, migrations, loading and saving the ledger, Keychain access | `Domain`, GRDB |
| `Import` | The MoneyMoney migration and the CSV, CAMT, and MT940 parsers. `TransactionFileImporter.parse` returns `[Transaction]`, and `MoneyMoneyMigration.plan` returns a `Plan` that the app shows before it stores anything. | `Domain` |
| `Sync` | `SyncCoordinator`, which refreshes up to three accesses at a time with one `SyncState` each, and `SessionBroker`, which shows one dialog at a time, keeps the PINs in memory, and saves a PIN through `SavedPINStore` on request | `Domain` |
| `SyncTesting` | `ScriptedConnector`, which plays requests, progress, results, and failures in place of a bank, for the tests, the previews, and the debug harness | `Domain` |
| `FinTS` | `FinTSConnector`, which starts the hbci4java helper of `Tools/FinTSHelper` for each refresh, lists the accounts of a login, looks up a bank by its code, and maps the requests and results of the helper to `Domain` types. macOS decides whether to trust the server of the bank, and a helper that stays silent for 30 seconds fails the refresh. The app uses it for the "Add Account" assistant and for every refresh of a FinTS access. A debug build can replace the helper with `scripts/fake-fints-helper.sh`. | `Domain`, the helper process ([ADR 0014](decisions/0014-fints-through-hbci4java.md)) |
| `ExtensionHost` | `HostSession`, which runs one extension package in its own Lua 5.4 state with the environment of ADR 0015, `HostPolicy`, which decides every request and redirect target, and `ExtensionHostClient`, which starts one sandboxed `MonetenExtensionHost` process per session and talks to it in JSON lines over a pipe. `Sources/ExtensionHost/API` offers the MoneyMoney-compatible API: the entry points, `Connection`, `HTML`, `JSON`, `PDF`, `LocalStorage`, and `MM`. `Sources/CLua` holds the Lua sources of lua.org. `Sources/ExtensionHost/PublicSuffix` holds the Public Suffix List under the Mozilla Public License 2.0 (`scripts/vendor-public-suffix.sh`), so that the cookie jar refuses a cookie for a domain such as `github.io`. | `Domain`, Lua 5.4 |
| `ExtensionConnector` | `ExtensionConnector`, which logs in, calls the entry points in the order of the API, turns each challenge table into a request to the user, and maps the account and result tables to `Domain` types. It keeps `LocalStorage` and the account tables in the `AccessState` of the access, and lists the accounts again when a refresh asks for one without a table. The app stores extension accesses in the table `access` like FinTS accesses. | `Domain`, `ExtensionHost` |
| `App` | SwiftUI views, the `AppModel`, window and menu wiring | All of the above |

These modules are planned:

| Module | Owns | Depends on |
|---|---|---|
| `FinAPIConnector` | finAPI login through its web form and data mapping (v0.3) | `Domain` |
| `ext` | A command line tool that runs and tests an extension without the app | `ExtensionHost` |
| `ExtensionCatalog` | Verifying the signed catalog index, installing packages, and planning updates | `Domain`, `ExtensionHost`, `Storage` |

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

A refresh, a file import, a MoneyMoney migration, and later an extension deliver rows that the history may already hold. FinTS gives no stable ID: a second refresh returns the same rows again, and a pending card payment comes back booked with another date or text. All of them go through one pure function in `Domain`, `reconcile`, and one write, `Store.merge`:

```swift
public enum Delivery: Sendable {
	case refresh(RefreshResult)   // balance, balance date, rows, and the first day the answer covers
	case file([Transaction])      // never drops a pending row, carries no balance
	case migration([Transaction]) // MoneyMoney: like a file, but honors every deleted row
}

public func reconcile(_ delivery: Delivery, into account: Account, stored: [Transaction],
	deleted: [DeletedTransaction], rules: Categorizer, now: Date) -> Reconciliation
```

`reconcile` gives each delivered row its partner by ordered evidence, strongest first. Each step takes rows out of the pool, so a weaker rule never takes a row that a stronger one claimed.

1. The source ID, when the source gives one. A delivered row with an ID never takes a stored row that has another ID.
2. The fingerprint of the requirement "Do not store a transaction twice": booking day, amount, and the purpose folded and without white space, with the counterparty IBAN and the end-to-end reference equal.
3. The same fingerprint where the IBAN or the reference is missing on one side, because a file often lacks them where a refresh has them.

The fingerprint is computed from the columns at every merge and never stored, so a change of the rule needs no migration. There is no occurrence index: rows with the same fingerprint count as a multiset, so two coffees on one day stay two rows, and the next refresh adds none.

A booked row without a partner can replace a stored pending row. Two rows can pair when they have the same amount, booking days at most 7 days apart, and the same counterparty: the IBAN when both rows have one, otherwise the folded name, where the words of one name must lead the other ("REWE" matches "REWE SAGT DANKE 1234", "SPAR" does not match "SPARKASSE"). Rows that can pair form connected groups. A group of one pending and one booked row books: the stored row takes the bank fields and keeps its comment, checkmark, and hand-set category. In any larger group nothing moves, and every row gets `needsReview`. A pending row without a partner is dropped when the answer covers its day and it is not marked for review. Once the user checks a marked row, the mark is gone, and a later refresh may drop it. The user has seen the mark and chosen.

A delete leaves a `DeletedTransaction` with the raw fields of the fingerprint and `wasFetched`. Deleted rows count like stored ones, so deleting one of two coffees leaves one. A refresh and a MoneyMoney migration honor every deleted row. A file honors only those that a refresh had delivered, so a file brings back a row that only a file added, and never a fetched row that the user deleted. A deleted pending row does not block its booked version.

`Store.merge` reads the account's live rows, deleted rows, and rules inside its write transaction, calls `reconcile`, and writes the result. `Ledger.apply` then takes over exactly what was written. `SyncCoordinator.deliver` calls the merge once per fetched account. A thrown error fails only that account with `SyncFailure.notSaved`, and the next refresh delivers the same rows again.

The bank fields of a fetched row can't be edited yet. When the transaction list allows that, the original fields move to columns of their own, so that the fingerprint keeps the bank's version.

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

This section is the plan for extensions. [ADR 0015](decisions/0015-extension-program.md) records the decisions behind it.

An extension is a single `.lua` file or a package. A single file may have a manifest with the same base name next to it, such as `Demo.json` next to `Demo.lua`. A package is a folder with `manifest.json`, one or more Lua files in the load order that the manifest lists, and a README. The app installs, updates, and removes a package as one unit.

Each extension session runs in its own process, `MonetenExtensionHost`, with the app sandbox and only the network client entitlement. An XPC service would share one process between sessions without private API, so the app starts the helper itself, as it does the FinTS helper. The host enforces these limits:

1. An extension with a manifest can only contact the hosts that the manifest lists, by exact name. The host checks the target of every HTTP redirect too. An extension without a manifest asks the user before it contacts each new host, also before a redirect to one, and the app remembers the answer. An automatic refresh sends nothing to a new host and waits for the user. In both cases only an exact host name on the HTTPS port passes. An IP address, `localhost`, a name without a dot, a trailing dot, and a user name in the URL fail without a question. A redirect to another host keeps only `Accept`, `Accept-Language`, and `User-Agent` of the headers that the extension set, and drops the body.
2. `io` is a table without `open` and without any other function that touches a file. `os` keeps only `time`, `date`, `clock`, and `difftime`. `debug`, `package`, `load`, `loadstring`, `dofile`, `loadfile`, `require`, and `string.dump` are absent. A call of a name that the host does not offer stops the script with an error that names the function.
3. The extension gets the credentials of its own connection and nothing else.
4. The extension's `LocalStorage` is kept by the app, per connection, inside the encrypted database.
5. A session has 256 MB of memory for Lua and 60 seconds of processor time. A request fails after 60 seconds without data, after 2 minutes in all, or with a body larger than 32 MB. The app stops a host that sends nothing for 3 minutes while no question waits for the user, a host whose answer is larger than 64 MB, and a host that sends more than the app reads. It keeps 4 MB of `print` output per session and drops the rest before it is queued. A session runs one call at a time.

The host checks hosts in the same process that runs the script. A flaw in Lua or in a parser of the host could reach any host with the login data of that one access. [ADR 0015](decisions/0015-extension-program.md) accepts this risk and names when the network calls move into a separate process.

The manifest is required for a package in the catalog and optional for an extension installed from a file. The catalog is the public repository [MonetenApp/moneten-extensions](https://github.com/MonetenApp/moneten-extensions). Its checks and a maintainer review every package and every update. A signing workflow publishes a signed index with the SHA-256 digest of every file at `extensions.monetenapp.com`, the only host that the app contacts for the catalog. A file that the user installs by hand runs after a warning that lists the hosts of its manifest, and stays "Unverified". The app warns again when any of its files changes. The app records whether each extension came from the catalog, so a changed catalog package stays blocked and never runs as a file install.

The module `ExtensionCatalog` verifies the index against the two public keys in the app and the version floor of each key, downloads and checks the files, and decides whether an update installs by itself or waits for the user because it adds a host or a login field.

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
│   ├── SyncTesting/
│   └── FinTS/
├── Tests/                   One test target per library
├── App/                     The app target: project.yml, sources, Info.plist, resources
├── Tools/
│   ├── FinTSHelper/         The hbci4java helper that FinTSConnector runs (ADR 0014)
│   └── FinTSProbeJava/      The hbci4java probe of issue #11, and dependencies.lock
├── scripts/                 Test, build, project, and check scripts
├── openspec/                Specs of every change
└── docs/
```

The planned modules get their own folders under `Sources/`.
