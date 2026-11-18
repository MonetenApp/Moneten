# Moneten

Moneten is an open source banking app for the Mac. It fetches balances and transactions from German banks, sorts them into categories, and shows where your money goes. With FinTS and extensions, your data stays encrypted on your Mac. You need no account, the project runs no server, and the app sends no telemetry. Only the optional subscription passes data through a provider.

> [!NOTE]
> Moneten is at an early stage, and there is no release yet. The current build fetches balances and transactions from German banks over FinTS and from other services through extensions. It refreshes them automatically and tells you about new transactions. It keeps everything in an encrypted database, takes over accounts, categories, and transactions from MoneyMoney, imports CSV, CAMT, and MT940 files, categorizes with rules, and shows the transactions in a list with search and in charts. It cannot send payments yet. The [roadmap](docs/roadmap.md) shows what ships in v0.1, v0.2, and v0.3, and [openspec/changes](openspec/changes/) specifies the complete behavior.

## What you get in v0.3

- Accounts from any German bank that offers FinTS, with pushTAN, photoTAN, and chipTAN.
- Accounts from other services through extensions that anyone can write in Lua. Moneten runs most extensions written for MoneyMoney without changes.
- Categories, split transactions, rules that categorize new transactions, search, and charts.
- Automatic refresh with a notification when new transactions arrive.
- Import from CSV, CAMT, MT940, and MoneyMoney.
- SEPA transfers with the payee check (Verification of Payee).
- Securities accounts.
- An optional paid subscription that connects banks through finAPI. You never need it to use the app.

## How it works

The app is a native macOS app in Swift and SwiftUI. It talks to banks in two ways:

1. FinTS, the standard interface of German banks. This is free and built in. The app runs [hbci4java](https://github.com/hbci4j/hbci4java), the FinTS library that Hibiscus uses, in a helper process inside the app bundle, so you install nothing ([ADR 0014](docs/decisions/0014-fints-through-hbci4java.md)).
2. Extensions. An extension is a Lua script that fetches data from one service, for example a broker, a credit card portal, or a crypto exchange. Each extension runs in a sandboxed process. You install reviewed extensions with one click from the signed catalog in [moneten-extensions](https://github.com/MonetenApp/moneten-extensions). An extension that you install from a file runs after a warning and stays marked "Unverified". Extensions only read data. The extension API has no payment functions, and the app will send payments only through FinTS or finAPI.

Read [architecture](docs/architecture.md) for the modules and the data model, and [decisions](docs/decisions/) for why the project is built this way.

## How your data is protected

- The database is encrypted with SQLCipher. Its key comes from the database password that you set. Until you set one, a random key in the Keychain protects the database.
- Saving the password in the Keychain is optional. With the password saved, the app can unlock at launch, with Touch ID, or with an Apple Watch.
- With a database password, the app locks after 10 minutes without activity. You can change the time or turn the lock off. The app also locks when you close the main window, if you turn that on.
- The app saves a PIN only if you turn that on for a bank access, and only after the bank accepted it. It never stores a TAN.

[ADR 0009](docs/decisions/0009-database-password-as-in-moneymoney.md) and [architecture](docs/architecture.md#the-database-password-protects-everything) have the details.

## Back up your data

The app keeps all your data in one data folder with the subfolders "Database", "Extensions", and "Statements". "Show Database in Finder..." in the Help menu opens it.

- A copy of the whole data folder holds all your data. Time Machine or any other backup of your Mac covers it. To open it on another Mac, set a database password first, because without one the key of the database stays in the Keychain of this Mac (see below).
- "Backup Database..." in the Tools menu saves a copy of the database while the app runs. The copy holds the database only: statements and extensions are not part of it. So the command does not replace a regular backup of your Mac.
- A backup opens with the database password that was valid when you made it, on any Mac. A backup made without a database password opens only on the same Mac and user account, with the key in the Keychain.

## Why this project exists

MoneyMoney and Banking4 are two of the established banking apps for German users on the Mac. Both are closed source. New shareholders took over 90 percent of MoneyMoney's developer, the price doubled, and the developer announced a subscription. [Vision](docs/vision.md) explains what Moneten does differently and how it pays for itself.

## Build and run

You need macOS 15 or newer, Xcode 16.3 or newer, and [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`). `scripts/build-app.sh` and the FinTS probe with hbci4java also need a JDK 17 or later (`brew install openjdk@21`) for the FinTS helper ([ADR 0014](docs/decisions/0014-fints-through-hbci4java.md)). The build takes the FinTS product ID from the login Keychain item "Moneten FinTS product ID". Without it the app builds, and FinTS refuses to connect.

```sh
scripts/test.sh                     # run the tests of the libraries
scripts/generate-project.sh         # write App/Moneten.xcodeproj, then open it in Xcode
scripts/build-app.sh                # build dist/Moneten.app; add "debug" for a debug build
scripts/build-app.sh developer-id   # sign it with the Developer ID certificate, see docs/releasing.md
open dist/Moneten.app
scripts/check.sh                    # run the checks before a pull request; needs OpenSpec and Periphery
```

To sign with your team, create `App/Local.xcconfig` as `App/Signing.xcconfig` describes. A build without a team is signed to run locally. Every new build then has a new signature, and the Keychain does not hand the entries of an older build to a newer one. Set a database password when you rebuild often, or sign with a team. [ADR 0011](docs/decisions/0011-app-target-in-an-xcode-project.md) explains the build.

The app keeps its data in `~/Library/Application Support/Moneten`. To try it with another folder, build a debug build with `scripts/build-app.sh debug`, quit Moneten, and start it with `open -n --env MONETEN_DATA_DIR=/path/to/folder dist/Moneten.app`. Without `-n`, `open` brings an instance that already runs to the front, and that instance keeps its own data folder. A release build ignores the variable. Builds from before the rename used the folder `MonetenMoneten`, and the app moves it on its first start ([ADR 0013](docs/decisions/0013-name-the-app-moneten.md)).

## How the project is planned

The project uses [OpenSpec](https://github.com/Fission-AI/OpenSpec). Every behavior of the app is written down as a requirement with testable scenarios before any code exists.

- [openspec/changes](openspec/changes/) holds one folder for each planned change. A change has a proposal and the specs that it adds.
- [openspec/specs](openspec/specs/) holds the specs of what is built. A change moves there when its code is merged and the change is archived.
- [MoneyMoney analysis](docs/research/moneymoney-analysis.md) records the behavior that the specs start from, and [MoneyMoney features](docs/research/moneymoney-features.md) maps each feature to its change.
- [Extension coverage](docs/research/extension-coverage.md) lists which providers the published MoneyMoney extensions reach in Moneten and what blocks the others.

[CONTRIBUTING.md](CONTRIBUTING.md) explains how to work on a change.

## Contribute

The project needs Swift developers, people who know FinTS or hbci4java, and extension authors for banks and brokers. Start with [CONTRIBUTING.md](CONTRIBUTING.md). To report a security problem, follow [SECURITY.md](SECURITY.md) and do not open a public issue.

## License

Moneten is licensed under the [GNU General Public License v3.0 or later](LICENSE). Extensions in the catalog use a GPL-compatible license such as MIT. [ADR 0020](docs/decisions/0020-keep-gpl-3-after-hbci4java.md) explains why.

Moneten is not affiliated with MoneyMoney, MRH applications GmbH, Banking4, or Subsembly GmbH.
