# MonetenMoneten

MonetenMoneten is an open source banking app for the Mac. It fetches balances and transactions from German banks, sorts them into categories, and shows where your money goes. Your data stays encrypted on your Mac. There is no account, no server, and no telemetry.

> [!NOTE]
> MonetenMoneten is in the planning phase. There is no app to download yet. The [roadmap](docs/roadmap.md) shows what ships in v0.1, v0.2, and v0.3.

## What you get in v0.3

- Accounts from any German bank that offers FinTS, with pushTAN, photoTAN, and chipTAN.
- Accounts from other services through extensions that anyone can write in Lua. MonetenMoneten runs most extensions written for MoneyMoney without changes.
- Categories, rules that categorize new transactions, search, and charts.
- Import from CSV, CAMT, MT940, and MoneyMoney.
- SEPA transfers with the payee check (Verification of Payee).
- Securities accounts.
- An optional paid subscription that connects banks through finAPI. You never need it to use the app.

## How it works

The app is a native macOS app in Swift and SwiftUI. It talks to banks in two ways:

1. FinTS, the standard interface of German banks. This is free and built in.
2. Extensions. An extension is a Lua script that fetches data from one service, for example a broker, a credit card portal, or a crypto exchange. Extensions run in a sandboxed process and can only fetch data. They can never send money.

Read [architecture](docs/architecture.md) for the modules and the data model, and [decisions](docs/decisions/) for why the project is built this way.

## Why this project exists

MoneyMoney and Banking4 are two of the established banking apps for German users on the Mac. Both are closed source. New shareholders took over 90 percent of MoneyMoney's developer, the price doubled, and the developer announced a subscription. [Vision](docs/vision.md) explains what MonetenMoneten does differently and how it pays for itself.

## Contribute

The project needs Swift developers, people who know FinTS, and extension authors for banks and brokers. Start with [CONTRIBUTING.md](CONTRIBUTING.md). To report a security problem, follow [SECURITY.md](SECURITY.md) and do not open a public issue.

## License

MonetenMoneten is licensed under the [GNU General Public License v3.0 or later](LICENSE). Extensions are separate works, and each extension author picks its license.

MonetenMoneten is not affiliated with MoneyMoney, MRH applications GmbH, Banking4, or Subsembly GmbH.
