# 0005. Store data in SQLite with GRDB and SQLCipher

Status: Accepted

## Context

The database holds years of transactions. It must be encrypted at rest, support migrations, and answer queries for charts in milliseconds. SwiftData has no encryption option. Core Data has none either. GRDB is a mature SQLite library for Swift with migrations and observation of query results. SQLCipher encrypts the SQLite file with AES-256.

The [GRDB 7.10 release notes](https://forums.swift.org/t/grdb-v7-10-0-android-linux-windows-and-sqlcipher-swiftpm/84754) describe SQLCipher through Swift Package Manager. It still needs a fork of GRDB with a modified `Package.swift`, and the thread says Xcode support for package traits is incomplete.

## Decision

Use GRDB with SQLCipher. The key comes from the database password, as described in [ADR 0009](0009-database-password-as-in-moneymoney.md).

Use the GRDB fork [sqlcipher/GRDB.swift](https://github.com/sqlcipher/GRDB.swift) with an exact version.

## Why the GRDB fork

Through Swift Package Manager, GRDB links the SQLite of the system, which cannot encrypt. To link SQLCipher, the `Package.swift` of GRDB itself must change. The [GRDB README](https://github.com/groue/GRDB.swift#encryption) says so: "To use SQLCipher with the Swift Package Manager, you must fork GRDB, and modify `Package.swift`." A package cannot change the manifest of its dependency.

A comparison on 2026-11-10 showed the following:

- The fork is a GitHub fork of [groue/GRDB.swift](https://github.com/groue/GRDB.swift), owned by the SQLCipher organization of Zetetic. A Zetetic developer maintains it. The same developer contributed the SQLCipher changes of GRDB 7.10.
- Against the upstream commit that it merges, the fork changes only `Package.swift`, which turns on the commented "GRDB+SQLCipher" lines, and `README.md`. The Swift code of GRDB is the same.
- The fork tag v7.12.0 is upstream v7.12.0 plus four commits that fix typos in comments, documentation, and one assertion message.
- The fork followed the releases 7.10.0, 7.11.0, 7.11.1, and 7.12.0 within zero to five days.

Alternatives that were checked:

- An upstream package trait "SQLCipher". This is the clean way, but it does not exist yet. [GRDB issue #1816](https://github.com/groue/GRDB.swift/issues/1816) plans it with Zetetic and reserves the name "SQLCipher" for it. Xcode support for traits held it back.
- Our own fork or a copy of GRDB in the repository. It is the same change, with the updates as our work.
- CocoaPods with `GRDB.swift/SQLCipher`. CocoaPods is being retired, and this project is a Swift package without CocoaPods.
- A source build of SQLCipher, as in [GRDB pull request #1708](https://github.com/groue/GRDB.swift/pull/1708). It is not in upstream GRDB and comes from a third party.

The larger trust question is not the fork. `SQLCipher.swift` is a precompiled binary framework from Zetetic, and upstream GRDB would need it too. `Package.resolved` pins both packages to an exact version and commit.

## When to change

When upstream GRDB ships the trait "SQLCipher", switch to it in one line:

```swift
.package(url: "https://github.com/groue/GRDB.swift", exact: "<version>", traits: ["SQLCipher"])
```

The app builds with `swift build`, so missing trait support in Xcode does not block this project.

## Prototype result

The first build settled the open question of this decision. It builds with GRDB fork 7.12.0 and SQLCipher.swift 4.20.0, with the Swift 6.3.3 command line tools and with Xcode 27.2. It creates and opens an encrypted database, changes its password, and runs the migrations. `VaultTests` cover this.

## Consequences

- The migrations are Swift code in `Sources/Storage/Schema.swift` and reviewable.
- The file is unreadable without the key, also in Time Machine backups.
- If the user forgets the database password, the data is lost.
- Each GRDB update waits for the matching tag of the fork, usually a few days.
