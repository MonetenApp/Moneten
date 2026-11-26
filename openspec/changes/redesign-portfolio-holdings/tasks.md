# Tasks

A task is checked only when a test or a check in the running app shows the behavior. "FinTSHelper self-test" is `scripts/build-fints-helper.sh`, which CI runs.

## 1. Part 1: data

- [x] 1.1 Test first: the class that a position shows is the user's choice, or else the class of the source, or else "Others", whatever the name. AssetClassTests "The user's class wins over the class of the source, and a position without either is Others, whatever its name" and "The eight classes keep their stored names and their order".
- [x] 1.2 `Domain`: `AssetClass`, `Holding.sourceAssetClass`, `Holding.userAssetClass`, and `Holding.assetClass`.
- [x] 1.3 Test first, then `Holding.identify`: a refresh takes the class of the source from the delivery and keeps the user's choice of the stored position. AssetClassTests "A refresh takes the class of the source from the delivery and keeps the user's choice of the stored position".
- [x] 1.4 `Ledger.setUserAssetClass(_:of:)`. AssetClassTests "A choice of the user changes the chosen positions only, and nil goes back to the class of the source".
- [x] 1.5 Test first, then `CFI.assetClass(of:)`: the table of ISO 10962. CFITests "Shares, ETFs, REITs, other funds, and debt give their class" and "Codes whose class the standard does not tell give none".
- [x] 1.6 `Tools/FinTSHelper`: `RawHolding` reads field 12C with the qualifier CLAS of the raw MT535 text, and each position sends it as `cfi`. FinTSHelper self-test "each holding sends the CFI code of its raw holding", "a page with a total sends the CFI code too", "a CFI code in lower case, of another length, or with a digit is not sent", and "a raw answer that does not pair sends no CFI code".
- [x] 1.7 `FinTS`: `AccountResult.Position` decodes `cfi` into the class of the source. FinTSConnectorTests "Reads the lines that the helper writes for … securities accounts …" with the depot 7654332.
- [x] 1.8 `Storage`: migration `v35`, `HoldingRecord`, and `Store.setUserAssetClass(_:ofHoldings:)`. HoldingStoreTests "A refresh stores the class of the source, and the user's choice survives the next refresh, in the database and in the ledger" and "v35 leaves every stored position without a class, so it shows Others".
- [x] 1.9 The complete export carries both classes as optional keys, and `docs/export-format.md` describes them. AllDataTests "A complete export imports into an empty database …" and "The asset classes of a holding travel with their stored names, a file without them reads with none, and an unknown name is refused".
- [x] 1.10 Extensions and the migration: checked that the web banking API and the MoneyMoney migration carry no asset class, so both leave the class of the source nil (design).
- [x] 1.11 `App`: `AppModel.setAssetClass(_:of:)` and the debug harness command `assetclass`. `scripts/fake-fints-helper.sh` sends CFI codes for three positions of the login "depot".

## 2. Part 2: view

- [ ] 2.1 Asset classes: the localized names of the eight classes, with German values.
- [ ] 2.2 Asset class tag: the tag next to the ISIN below the name.
- [ ] 2.3 Filter by asset class: "Asset class" in the filter bar with "Show All" and the classes of the view; the list and the status line follow it.
- [ ] 2.4 Choose an asset class: the submenu "Asset Class" with the eight classes and "Automatic", with a mark at the current choice, for the selected positions.
- [ ] 2.5 Position row content: the value in semibold, and the ISIN below the name.
- [ ] 2.6 Quantities as units or as a nominal amount: "646" without "shares", and "5.000,00 €" for a nominal amount.
- [ ] 2.7 Profit or loss: green with "+" and red with "−", the percentage below the amount, no word in the row. The header keeps "Profit" and "Loss".
- [ ] 2.8 Day of an old quote: the day only when it is older than the newest quote day of the portfolio, in the warning color.
- [ ] 2.9 Quote of zero: "–".
- [ ] 2.10 Light and dark screenshots of the debug harness for the pull request, with the login "depot" of `scripts/fake-fints-helper.sh`.
