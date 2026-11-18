# Design

## Context

The app keeps every account, category, and transaction of the open database in one in-memory `Ledger`, and `Store` is the only write path ([docs/architecture.md](../../../docs/architecture.md)). Everything runs on the Mac ([ADR 0002](../../../docs/decisions/0002-local-first-no-server.md)). The database is encrypted with SQLCipher ([ADR 0005](../../../docs/decisions/0005-grdb-and-sqlcipher.md)). A complete export leaves that protection on purpose, so the app warns first.

## Decisions

### Complete export

- `Domain` owns the file format in `Sources/Domain/AllData.swift`. `AllData` holds the stored objects as `Domain` types. Its `Codable` form is the documented format: amounts are decimal text next to a currency code, days are `yyyy-MM-dd`, times are ISO 8601 in UTC, and objects refer to each other by their UUIDs. The file starts with `format`, `version`, and `exportedAt`.
- The format started at version 1. A reader refuses a file with a higher version and names the version of the app it needs. A later change that stores more data adds an optional key. A key that a reader of an earlier version cannot read raises the version: a new required key, a required key that is removed or renamed, and a new value of a fixed word such as `reason` or `review`. Version 2 added `splitParts` and `review` (`add-split-transactions`). Version 3 stores the error of a refresh as `failure` in place of the required `message` (#310, `add-localization-and-formatting`). The reader of version 3 still reads versions 1 and 2.
- The file holds account groups, accounts, bank accesses, categories with their rules, transactions, deleted transactions, the daily values of portfolios, and the positions of portfolios. Splits follow with the change `add-split-transactions`, which adds a task for it.
- The file leaves out saved PINs, the state of each bank access (the connector data of FinTS and the storage of extensions), the decisions about hosts of extensions, the catalog of extensions, and statement files. An access keeps its bank, its user ID, and its connector, so the first refresh after an import asks for the PIN.
- `Storage` reads and writes it. `Store.exportAllData()` reads every table in one read transaction. `Store.importAllData(_:)` writes every object in one write transaction and refuses a database with an account or a transaction. The app passes the starter categories that it may replace, as it does for a migration, so a new database counts as empty.
- The round trip is exact. Every field of every stored object is in the file, also the source identifiers, so a refresh or a migration after an import recognizes the same rows.
- [docs/export-format.md](../../../docs/export-format.md) documents each key. A test exports a database with every kind of object and checks that each key of the file is in that document.

### CSV export

- `Domain` writes the CSV text with a new type `TransactionCSV` from rows, the ledger, and a locale. `TransactionCSV.rows(visible:selection:)` chooses the visible selected rows, or all visible rows when the selection is hidden or empty. The account context menu reads the whole account without filters.
- The file is written to a temporary file next to the target and moved into place, so a failed or canceled export leaves no file.

## Risks / Trade-offs

- The file holds all financial data in readable form. The warning names that, and the app never writes the file without the save panel.
- An export of 200,000 transactions is one JSON file of some 100 MB. The app builds it in memory, which is acceptable for a file that is written once.
