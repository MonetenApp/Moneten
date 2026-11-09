# Competitors and related projects

This page records what other banking apps for German users do, as of November 2026. It informs scope and positioning. Facts come from the linked sources.

## MoneyMoney

MoneyMoney is a closed source Mac app by MRH applications GmbH.

- It connects banks through FinTS and, for banks without FinTS, through PSD2 interfaces ([ifun.de](https://www.ifun.de/moneymoney-unterstuetzt-umsatzabruf-ueber-psd2-155772/)).
- Services without FinTS, for example Trade Republic and American Express, connect through "Web Banking" modules that read the provider's website. These modules break when the website changes. [ifun.de](https://www.ifun.de/mac-banking-moneymoney-verbessert-europa-unterstuetzung-236147/) and [Softpedia's changelog](https://mac.softpedia.com/progChangelog/MoneyMoney-Changelog-108659.html) report several such fixes.
- It has a public [Lua extension API](https://moneymoney.app/api/webbanking/). Community extensions exist for Qonto, Bitpanda, Binance, Monzo, and others ([GitHub topic](https://github.com/topics/moneymoneyapp)).
- Four new shareholders now hold 90 percent of the developer ([ifun.de](https://www.ifun.de/banking-app-moneymoney-neues-logo-und-neue-miteigentuemer-250904/)). The license price doubled from 39.99 to 79.99 euros ([ifun.de](https://www.ifun.de/moneymoney-verdoppelt-preis-support-weiter-unter-druck-287998/)), and the developer announced a subscription ([ifun.de](https://www.ifun.de/moneymoney-wechselt-zum-abo-was-fuer-bestandskunden-gilt-294473/)).

## Banking4

Banking4 is closed source software by Subsembly GmbH in Munich, for Windows, macOS, iOS, and Android ([banking4.de](https://banking4.de/index.html)).

- FinTS is the main connection, with all common TAN methods, key files, and signature cards. EBICS is in the business editions.
- About two dozen providers connect through screen scraping, read-only, among them N26, Trade Republic (cash account only), Scalable Capital, American Express, and Amazon Visa ([screen scraper list](https://banking4.de/screen-scraper.html)). Some need workarounds. American Express works only after the user restarts the Amex app and refreshes in it.
- PayPal connects through PayPal's NVP API.
- There is no extension system.
- Data is stored in a vault encrypted with AES-256 on the device. Backups go to Dropbox, Google Drive, OneDrive, WebDAV, or iCloud ([Banking4 Home](https://banking4.de/banking4home.html)).
- Prices from version 9, released in September 2025. Home for Mac and Windows costs 40 euros once, mobile 9.99 euros once, Professional 80 euros per year, and Business 120 euros per year for one user ([buy page](https://banking4.de/buybanking4home.html), [ifun.de](https://www.ifun.de/banking-app-banking4-mit-neuem-geschaeftsmodell-in-version-9-264685/)).

## Open source projects

| Project | What it is | Relevance |
|---|---|---|
| [Hibiscus](https://github.com/willuhn/hibiscus) | Java desktop banking app with FinTS through hbci4java | Mature FinTS, dated interface |
| [Pecunia](https://github.com/derpue/pecunia-client) | Mac banking app, mostly Objective-C | Its author wrote HBCI4Swift. This repository has had no push since 2016. |
| [Actual Budget](https://actualbudget.org/docs/advanced/bank-sync/enable-banking) | Self-hosted budgeting web app | Bank sync through Enable Banking and GoCardless, no FinTS, no securities |
| Firefly III | Self-hosted bookkeeping web app | FinTS through a [separate importer](https://github.com/bnw/firefly-iii-fints-importer) |
| [kiesel](https://github.com/Bastian-Kuhn/kiesel) | Mac budgeting app in Swift, GPL-3.0, started November 2026 | Plans FinTS. A possible partner. |

## What follows for MonetenMoneten

No other app combines open source code, a native Mac interface, FinTS with securities, and an open extension API. Users accept one-time prices around 40 euros and push back on subscriptions. The optional subscription must therefore be cheap and must add something the free app cannot do.
