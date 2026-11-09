# Vision

This page explains what MonetenMoneten is for, who it serves, and how it stays alive without locking users in.

## The problem

People in Germany who manage several bank accounts, credit cards, and securities accounts on a Mac have few choices. MoneyMoney and Banking4 both work well, and both are closed source. Your financial history lives in a file format only the vendor can read, and the vendor decides the price and the license model.

That risk became real for MoneyMoney users. New shareholders took over 90 percent of the developer, the license price went from 39.99 euros to 79.99 euros, and the developer announced a subscription. The research notes in [competitors](research/competitors.md) link the reports.

## Who it is for

The first user is a person with accounts at several German banks and brokers who wants one place to see balances, transactions, and securities. They are comfortable with a Mac app, they do not want their banking data on someone else's server, and they want to keep using the app if the project changes direction.

The second user is a developer who wants to add a bank or service. They should be able to write an extension in an afternoon, test it without the app, and share it with others.

## What the project promises

- Your data stays on your Mac, in an encrypted database. The app sends nothing to the project.
- The full app is open source under the GPL. Anyone can build it, audit it, or fork it.
- Every core feature works without paying. That includes FinTS banking, extensions, categories, rules, charts, import, and transfers.
- You can export everything in open formats at any time.
- Extensions can read data. They can never send money. Payments go only through FinTS or a licensed provider.

## How the project pays for itself

The app is free. An optional subscription connects banks through finAPI, a licensed German account information service. The subscription is for people whose bank has no FinTS access, or who do not want to deal with FinTS setup. Its price covers finAPI's per-user fee, payment fees, and the small server that holds the finAPI credentials. It never becomes a requirement for core features.

Donations and sponsorships are welcome. They do not buy features.

## What the project does not do

- No Windows, Linux, iPhone, or iPad app before v0.3. The Mac app comes first. An iOS app may follow because SwiftUI makes that cheaper later.
- No cloud service that stores your transactions.
- No business banking features such as EBICS or approvals by two people.
- No budgeting method that forces a workflow on you. Categories and charts come first. Budgets may follow.
- No scraping of bank websites in the core app. Scrapers are extensions, maintained by their authors.
