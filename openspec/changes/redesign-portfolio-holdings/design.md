# Design

## Context

The change `add-securities-accounts` built the list of positions with the columns "Name", "Quantity", "Purchase price", "Last quote", "Value", and "Profit/Loss" (`App/Sources/Views/HoldingsView.swift`). Its design says that hbci4java drops the asset class of MT535. The owner reviewed every column on 26 November 2026 and decided the asset classes, where they come from, and the new look of each column. The change `add-portfolio-analysis` had planned asset classes as a later feature that the user assigns to a security. Its asset class requirements move here, and it keeps the charts that use them.

## Scope

Part 1 builds the data, and part 2 builds the view. They are separate pull requests, because another pull request changes `HoldingsView.swift` at the same time.

- Part 1: `AssetClass`, the two classes of a `Holding` and the class that it shows, the class from FinTS, the storage with its migration, the user's choice in the database and the ledger, and the complete export.
- Part 2: the columns, the tag, the filter "Asset class", the submenu "Asset Class", the day of an old quote, and "–" for a quote of 0.

## Decisions

### Types in `Domain`

`AssetClass` is an enum with the eight cases `stocks`, `funds`, `bonds`, `realEstate`, `commodities`, `etfs`, `cryptocurrencies`, and `others`, in the order of the menu. It is `Codable` and `Sendable`. The raw values are stored in the database and in the complete export, so they never change, and the app never uses a localized name as a key. The app shows its own localized name of each class (part 2).

`Holding` gets two optional fields:

- `sourceAssetClass`: the class that the source sends, nil when it sends none. Each refresh replaces it with the class of the delivery.
- `userAssetClass`: the class that the user chose, nil while the user chose none. Only the user changes it.

`assetClass` derives the class that the position shows: `userAssetClass ?? sourceAssetClass ?? .others`. It is never stored.

Why this structure: the class of the source and the choice of the user are two separate facts. Every pair of the two optionals is a valid state, so the type needs no rule that a constructor or a migration could break. A stored class that the position shows would be a third field that can disagree with the two, so it does not exist. An enum such as `.source(AssetClass?)` or `.chosen(AssetClass)` loses the class of the source while the user's choice holds, so a refresh could not update it, and "Automatic" could show the class of the bank only after the next refresh. Nil for "the source sent none" keeps that apart from a source that sends "Others", although both show "Others".

### The user's choice survives a refresh

`Holding.identify` gives each delivered position the ID of the stored position of the same security. It now also gives it the `userAssetClass` of that stored position, and clears the field of every delivered position first, because no source sends a choice of the user. `reconcile` and `Store.merge` store what `identify` returns, so the merge keeps the choice in the database and in the ledger with no extra step, and the class of the source comes from the delivery. A position that leaves the portfolio takes the choice with it. When the same security comes back later, it starts with the class of the source.

`Store.setUserAssetClass(_:ofHoldings:)` writes the choice of the selected positions in one statement, and `Ledger.setUserAssetClass(_:of:)` takes it over after the write. `AppModel.setAssetClass(_:of:)` calls both, in this order, as `commit` does. Part 2 calls it from the submenu "Asset Class". Until then the debug harness command `assetclass` uses it, so a check can choose a class and read the class of every position.

### The class of a FinTS position

What hbci4java 4.1.17 keeps of a holding of MT535 (`GVRWPDepotList.Entry.Gattung`):

| Field of MT535 | Kept by hbci4java | Used |
|---|---|---|
| 12C with the qualifier CLAS: the CFI code of ISO 10962, six letters | No | Yes, from the raw MT535 text |
| 12A and 12B with the qualifier CLAS: text or a code of a data source scheme | No | No: no public standard defines their values |
| 70E, line 1, the kind of security ("Wertpapierart") | Yes, as `wptype` | No: the app has no code list for it that it could check, and no recorded answer of a bank shows one |
| 35B, the name | Yes | Never: the app does not guess a class from a name |

hbci4java keeps the raw MT535 text of the answer in its result data, under the key content.data535, and the helper already pairs each holding of hbci4java with its holding in that text (`RawHolding.paired`, #241). `RawHolding` now also reads field 12C with the qualifier CLAS and its six letters A to Z, and `position` sends them as `cfi` in each position of the result line. This needs no change of hbci4java. When the raw text does not pair, for example because it has another number of holdings, no position sends a code, because the code of another holding is worse than none.

`AccountResult.Position` in `Sources/FinTS/HelperProtocol.swift` decodes `cfi`, and `CFI.assetClass(of:)` in `Sources/FinTS/CFI.swift` maps it to `sourceAssetClass` with one table of the first two letters, the category and the group of ISO 10962:

| Code | Instruments | Class |
|---|---|---|
| ES, EP, EC, EF, ED | Shares, preferred and convertible shares, depositary receipts on shares | Stocks |
| ER, EV | Preference shares of the edition of 2001 | Stocks |
| EU | Units of investment funds of the edition of 2001 | Funds |
| CE | Exchange traded funds | ETFs |
| CB | Real estate investment trusts | Real estate |
| CI, CH, CS, CF, CP, CM | Investment funds, hedge funds, pension funds, funds of funds, private equity funds, other funds | Funds |
| DB, DC, DW, DT, DY, DA, DG, DN, DD | Bonds, convertible bonds, bonds with warrants, medium-term notes, money market instruments, asset-backed and mortgage-backed securities, municipal bonds, depositary receipts on debt | Bonds |
| Every other code | Limited partnership units (EL), structured instruments (EY, DS, DE), other equities and debt (EM, DM), rights and warrants (R), derivatives, referential instruments such as commodities and currencies (T), others (M) | None |

A code that the table does not list gives no class, so the position shows "Others", and a code of another form gives none either. A class is optional, so a code never fails the position or the account. Commodities and cryptocurrencies have no group of their own in ISO 10962, so only the user gives these classes.

### Extensions and the migration

The securities table of the web banking API ([ADR 0004](../../../docs/decisions/0004-moneymoney-compatible-extension-api.md)) has no field for an asset class, so `ResultMapping` leaves the class of the source nil, and a position of an extension shows "Others" until the user chooses a class. The MoneyMoney migration takes over no positions (`MoneyMoneyMigration` notes each portfolio instead), so it has no class to carry.

### Storage

Migration `v35` in `Sources/Storage/Schema.swift` adds the columns `holding.sourceAssetClass` and `holding.userAssetClass`, text with the raw value of `AssetClass`, empty for every stored position. `HoldingRecord` reads and writes both. Every stored position shows "Others" until the next refresh brings the class of the bank.

### The complete export

`HoldingEntry` in `Sources/Domain/AllData.swift` writes the optional keys `sourceAssetClass` and `userAssetClass` with the raw values, and leaves out a key without a value. [The export format](../../../docs/export-format.md) says that an optional key does not change the format version, so the version stays 4. A file of an earlier version reads with no classes. A name that is not a case of `AssetClass` fails the import as a damaged file. An app before this change ignores the two keys, so it imports such a file without the classes. A new case of `AssetClass` is a new value of a fixed word and raises the format version.

### The view (part 2)

The day below a quote shows when it is older than the newest quote day among the positions of the same portfolio, so a group of two portfolios refreshed on different days compares each position with its own portfolio. The filter "Asset class" lists the classes that the positions of the view have, in the order of `AssetClass.allCases`. A choice in the submenu calls `AppModel.setAssetClass(_:of:)` with the selected positions.

## Risks / Trade-offs

- The spec delta modifies requirements that the change `add-securities-accounts` adds, so `add-securities-accounts` must be archived first. OpenSpec refuses the archive of this change before that.

- No recorded MT535 answer of a bank in the repository shows field 12C. Banks that send no code give every position "Others", which is the owner's rule. The bank test of issue #11 checks whether a bank sends it.
- An earlier app version that reads a new export loses the user's choices without a warning, because it ignores unknown keys. This is the rule for optional keys of the export format.
- The user's choice belongs to the position. A security that leaves the portfolio and comes back later starts with the class of the source again.
