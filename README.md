# MonetenMoneten

MonetenMoneten is an open source banking app for the Mac. It fetches balances and transactions from German banks, sorts them into categories, and shows where your money goes. With FinTS and extensions, your data stays encrypted on your Mac. You need no account, the project runs no server, and the app sends no telemetry. Only the optional subscription passes data through a provider.

> [!NOTE]
> MonetenMoneten is at an early stage. The first build opens an encrypted database, takes over accounts, categories, and transactions from MoneyMoney, imports CSV, CAMT, and MT940 files, and categorizes with rules. It cannot talk to a bank yet. The complete behavior of the app is specified in [openspec/changes](openspec/changes/). The [roadmap](docs/roadmap.md) shows what ships in v0.1, v0.2, and v0.3.

## What you get in v0.3

- Accounts from any German bank that offers FinTS, with pushTAN, photoTAN, and chipTAN.
- Accounts from other services through extensions that anyone can write in Lua. MonetenMoneten runs most extensions written for MoneyMoney without changes.
- Categories, split transactions, rules that categorize new transactions, search, and charts.
- Automatic refresh with a notification when new transactions arrive.
- Import from CSV, CAMT, MT940, and MoneyMoney.
- SEPA transfers with the payee check (Verification of Payee).
- Securities accounts.
- An optional paid subscription that connects banks through finAPI. You never need it to use the app.

## How it works

The app is a native macOS app in Swift and SwiftUI. It talks to banks in two ways:

1. FinTS, the standard interface of German banks. This is free and built in.
2. Extensions. An extension is a Lua script that fetches data from one service, for example a broker, a credit card portal, or a crypto exchange. Each extension runs in a sandboxed process. The extension API has no payment functions, and the app sends payments only through FinTS or finAPI.

Read [architecture](docs/architecture.md) for the modules and the data model, and [decisions](docs/decisions/) for why the project is built this way.

## Build and run

You need macOS 15 or newer, Xcode 16.3 or newer, and [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).

```sh
scripts/test.sh                 # run the tests of the libraries
scripts/generate-project.sh     # write App/MonetenMoneten.xcodeproj, then open it in Xcode
scripts/build-app.sh            # build dist/MonetenMoneten.app
scripts/build-app.sh developer-id   # sign it with the Developer ID of the team, for other Macs
open dist/MonetenMoneten.app
```

To sign with your team, create `App/Local.xcconfig` as `App/Signing.xcconfig` describes.

The app keeps its data in `~/Library/Application Support/MonetenMoneten`. To try it with another folder, start it with `open --env MONETENMONETEN_DATA_DIR=/path/to/folder dist/MonetenMoneten.app`.

A build without a team is signed to run locally. Every new build then has a new signature, and the Keychain does not hand the entries of an older build to a newer one. Set a database password when you rebuild often, or sign with a team. [ADR 0011](docs/decisions/0011-app-target-in-an-xcode-project.md) explains the build.

## How the project is planned

The project uses [OpenSpec](https://github.com/Fission-AI/OpenSpec). Every behavior of the app is written down as a requirement with testable scenarios before any code exists.

- [openspec/changes](openspec/changes/) holds one folder for each planned change. A change has a proposal and the specs that it adds.
- [openspec/specs](openspec/specs/) holds the specs of what is built. It is empty until the first change is merged.
- [MoneyMoney analysis](docs/research/moneymoney-analysis.md) records the behavior that the specs start from, and [MoneyMoney features](docs/research/moneymoney-features.md) maps each feature to its change.

[CONTRIBUTING.md](CONTRIBUTING.md) explains how to work on a change.

## Why this project exists

MoneyMoney and Banking4 are two of the established banking apps for German users on the Mac. Both are closed source. New shareholders took over 90 percent of MoneyMoney's developer, the price doubled, and the developer announced a subscription. [Vision](docs/vision.md) explains what MonetenMoneten does differently and how it pays for itself.

## Contribute

The project needs Swift developers, people who know FinTS, and extension authors for banks and brokers. Start with [CONTRIBUTING.md](CONTRIBUTING.md). To report a security problem, follow [SECURITY.md](SECURITY.md) and do not open a public issue.

## License

MonetenMoneten is licensed under the [GNU General Public License v3.0 or later](LICENSE). Extensions in the catalog use a GPL-compatible license such as MIT. [ADR 0006](docs/decisions/0006-license-gpl-3.md) explains why.

MonetenMoneten is not affiliated with MoneyMoney, MRH applications GmbH, Banking4, or Subsembly GmbH.
