# 0005. Store data in SQLite with GRDB and SQLCipher

Status: Proposed

## Context

The database holds years of transactions. It must be encrypted at rest, support migrations, and answer queries for charts in milliseconds. SwiftData has no encryption option. Core Data has none either. GRDB is a mature SQLite library for Swift with migrations and observation of query results. SQLCipher encrypts the SQLite file with AES-256.

The [GRDB 7.10 release notes](https://forums.swift.org/t/grdb-v7-10-0-android-linux-windows-and-sqlcipher-swiftpm/84754) describe SQLCipher through Swift Package Manager. It still needs a fork of GRDB with a modified `Package.swift`, and the thread says Xcode support for package traits is incomplete.

## Decision

Use GRDB with SQLCipher. The database key is a random 256-bit value stored in the Keychain.

## What settles this decision

A prototype that builds the app with GRDB and SQLCipher through Swift Package Manager in Xcode, opens an encrypted database, and runs a migration. It records the exact Xcode version, GRDB fork, and SQLCipher version. Tracked in the v0.1 milestone.

## Consequences

- SQL migrations are plain files in the repository and reviewable.
- The file is unreadable without the key, also in Time Machine backups.
- If the Keychain item is lost, the data is lost. The app offers an encrypted export as a backup with its own password.
