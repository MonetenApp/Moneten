# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

Moneten is an open source banking app for the Mac: Swift 6, SwiftUI, macOS 15 or newer, GPL-3.0-or-later. It is local-first. It has no server, no account, and no telemetry, and all data stays in an encrypted database on the Mac. The local part of v0.1 is built: the encrypted database, the MoneyMoney migration, the CSV, CAMT, and MT940 import, the transaction list, categories, rules, charts, and the sync model. The FinTS connector adds bank accesses and refreshes them, and saves a PIN in the database on request; extensions are not built yet.

The behavior target is MoneyMoney 2.5.3. [docs/research/moneymoney-analysis.md](docs/research/moneymoney-analysis.md) records what was observed. A user who switches must find the same behavior, unless a proposal names a difference under "Decided for Moneten".

## Commands

Tools: Xcode, XcodeGen (`brew install xcodegen`), the OpenSpec CLI (`npm install -g @fission-ai/openspec`), Periphery 3.8.0 (`brew install periphery`), and a JDK 17 or later for the FinTS probe.

```sh
scripts/test.sh                                    # all library tests
scripts/test.sh --filter LedgerTests               # one suite
scripts/test.sh --filter 'LedgerTests/accountTree' # one test
scripts/test.sh -c release -Xswiftc -enable-testing --filter PerformanceTests   # budgets hold only in release
scripts/check.sh                                   # docs, chrome rule, specs, Periphery, tests: run before a PR

scripts/generate-project.sh                        # builds HBCI4Swift if needed, writes App/Moneten.xcodeproj
scripts/build-app.sh                               # dist/Moneten.app, Release; "debug" for a Debug build
scripts/perf-check.sh                              # UI performance scenarios in the Perf build; shows a window
scripts/fints-probe-java.sh --build-only           # compiles the hbci4java probe, as CI does

python3 scripts/check-docs.py                      # links, paths, data-model names, ADR index
python3 scripts/check-ui.py                        # window chrome rule (ADR 0012)
openspec validate --all --strict --no-interactive
python3 scripts/roadmap.py                         # regenerates docs/roadmap.md, needs gh
```

Use `scripts/test.sh` instead of plain `swift test`. It adds `--disable-keychain`, without which the package manager waits for a Keychain prompt, and the Swift Testing paths for a Mac with only the Command Line Tools.

Start the app with a throwaway data folder: `open --env MONETEN_DATA_DIR=/path/to/folder dist/Moneten.app`. Without it, the app opens the real database in `~/Library/Application Support/Moneten`.

A build without a team in `App/Local.xcconfig` is signed to run locally and gets a new signature each time. The Keychain then refuses the random database key of an older build (`Vault.Failure.keyNotInKeychain`). Set a database password in a test database, or sign with a team as `App/Signing.xcconfig` describes.

## Architecture

The repository has two builds ([ADR 0011](docs/decisions/0011-app-target-in-an-xcode-project.md)):

- The Swift package at the root holds the libraries and all unit tests. `scripts/test.sh` builds and tests them without Xcode.
- The app target in `App/` builds only with Xcode. XcodeGen writes `App/Moneten.xcodeproj` from `App/project.yml`, which uses the root package as `MonetenKit`. The generated project is not in git, so edit `App/project.yml` and run `scripts/generate-project.sh` again. The app has no unit tests. Logic that needs tests belongs in a library.

[docs/architecture.md](docs/architecture.md) describes the modules and the plan. [docs/data-model.md](docs/data-model.md) lists the types and tables.

| Module | Owns |
|---|---|
| `Domain` | Pure Swift with no dependencies and no I/O: types, money arithmetic, the in-memory `Ledger`, rules and `Categorizer`, import matching, chart data, and the sync model (`BankConnector`, `SyncState`, the requests to the user, `Challenge`) |
| `Storage` | `Vault` opens, creates, and re-keys the SQLCipher database. `Store` is the only write path. `Schema` holds the GRDB migrations. Also `Keychain` and `DataFolder`. GRDB comes from the fork that links SQLCipher. |
| `Import` | `TransactionFileImporter.parse` for CSV, CAMT, and MT940, and `MoneyMoneyMigration.plan`, which returns a plan that the app shows before it stores anything |
| `Sync` | `SyncCoordinator` refreshes up to three accesses at a time, each with one `SyncState`. `SessionBroker` shows one dialog at a time, keeps PINs in memory, and saves a PIN in the database only on request and after the bank accepted it. |
| `SyncTesting` | `ScriptedConnector`, a fake bank for the tests, the previews, and the debug harness |
| `ExtensionHost` | Runs a Lua extension session with the host limit of ADR 0015, one sandboxed `MonetenExtensionHost` process per session. `Sources/CLua` is Lua 5.4 from lua.org (`scripts/vendor-lua.sh`). |
| App | SwiftUI views and the `@Observable` `AppModel` |

How the parts work together:

- **Ledger and store.** After unlocking, `AppModel` loads everything once with `Store.loadLedger()` into a `Ledger` value. Views read only the ledger. A change must write through `Store` first and change the ledger only after the write succeeds, as `commit` in `App/Sources/AppModel.swift` does. Keep both in step, and never query the database from a view.
- **Money and days.** An amount is an `Int64` in minor units (`amountMinor`, `Money.minorUnits`) with an ISO 4217 currency. No `Double` stores an amount. A sum across currencies is a `MoneySums` and never converts. A booking date is a `Day` (yyyymmdd as `Int`) without a time zone.
- **Parse at the edge.** Each parser, and later each connector, turns raw data into `Domain` types. Code inside `Domain`, `Storage`, and the app trusts those types and does not check them again. An entry that cannot be read fails the whole file with its line, so nothing from the file is imported. Only the CSV parser skips a row without a date.
- **Schema changes.** Add a new `registerMigration("vN")` at the end of `Sources/Storage/Schema.swift`. Never change a migration that has shipped. `Transaction` is stored in the table `bankTransaction`. The models are Codable GRDB records.
- **Sync.** FinTS, extensions, and finAPI will each implement `BankConnector.refresh(_:_:)` and ask the user only through `SyncSession.ask(_:)`. `SyncState` is a pure state machine. Views read it and keep no flags of their own. The `deliver` closure of `SyncCoordinator` merges fetched data, and `ended` stores the new `AccessState` and the status of each account. The [design of add-account-refresh](openspec/changes/add-account-refresh/design.md) has the complete types and the dialog queue.
- **FinTS.** [ADR 0014](docs/decisions/0014-fints-through-hbci4java.md) replaces HBCI4Swift with hbci4java in a helper process that talks JSON lines over a pipe. `Tools/FinTSProbeJava` is the current prototype. The `Vendor/HBCI4Swift` submodule, `scripts/build-hbci4swift.sh`, and `App/FinTSProbe` stay only until the FinTS connector of issue #13 runs on hbci4java. A text that still names HBCI4Swift as the FinTS engine is out of date.

### Debug harness

Debug and Perf builds (`#if DEBUG || PERF_HARNESS`) can be driven without a screen when the environment variable `MONETEN_DEBUG_DIR` names a folder. Build one with `scripts/build-app.sh debug`. Always set `MONETEN_DATA_DIR` as well, because commands such as `create`, `seed`, and `setpassword` change the database that is open. Commands arrive as distributed notifications named `io.github.moneten.debug`, with the debug folder as the object and the `userInfo` keys `command` and `argument`. Examples are `create`, `unlock`, `seed`, `syncdemo`, `appearance dark`, `snapshot`, and `perf`. The app writes `debug.log` and PNG snapshots into the folder. `scripts/perf-check.sh` shows how to post the notifications, and `App/Sources/DebugHarness.swift` lists every command. Use the harness to check a UI change and to make the light and dark screenshots that a UI pull request needs. With `MONETEN_FINTS_HELPER` set to `scripts/fake-fints-helper.sh`, a debug build runs the commands `setup`, `answer`, `refresh`, and `status` against a made-up bank and never contacts a real one.

## Rules

- **Specs come first.** The project uses OpenSpec. Each planned change is a folder in `openspec/changes/` with a proposal and specs, and gets `design.md` and `tasks.md` before its code. New or different behavior changes the spec first. A bug fix that restores specified behavior goes straight to a pull request. The `/opsx:*` commands explore, propose, apply, update, sync, and archive changes. They are not in git: `openspec init --tools claude` writes them into the checkout. `openspec/specs/` stays empty until a change is archived. The `.openspec.yaml` of a change holds `x-milestone` and `x-issues`.
- **Writing.** [openspec/config.yaml](openspec/config.yaml) has the rules for specs: English, short sentences, active voice, present tense, one term for one thing, and no em or en dashes. A requirement starts with "The app SHALL", states one behavior, has scenarios with concrete values, and never names MoneyMoney. The docs, code comments, and commit messages use the same plain style.
- **Decisions.** A change to a decision in `docs/decisions/` needs a new decision record. The status in each record must match the index in `docs/decisions/README.md`.
- **Docs are checked against the code.** In every tracked Markdown file, each relative link and each repository path in code font must exist or be ignored by git. Each name in code font in `docs/data-model.md`, above its section on later types, must be declared in `Sources/`. Update the docs when you rename or remove something. `docs/roadmap.md` is generated, so do not edit it by hand.
- **Window chrome.** The sidebar, the toolbar, and the window keep the system materials of macOS, Liquid Glass from macOS 26 on ([ADR 0012](docs/decisions/0012-system-glass-for-window-chrome.md)). MoneyMoney parity covers content and behavior, not chrome. `scripts/check-ui.py` fails on `.toolbarBackground` or `.containerBackground` in any Swift file in `App/Sources` except the debug harness, and on a colored `.background` in a file with the sidebar or the split view, unless the line has `// chrome-ok: <reason>`.
- **No unused code.** Periphery runs in strict mode in CI, so a declaration without a use fails the build. `.periphery.yml` keeps the sync model until the connectors use it.
- **Performance.** The ledger must stay fast with 50,000 transactions (`Tests/DomainTests/PerformanceTests.swift`). In a SwiftUI `Table`, put modifiers in the cells, never on the rows: a row modifier such as `.draggable` rebuilds the view graph of every row. Add a scenario to `App/Sources/PerfCheck.swift` for every slow path you fix.
- **Tests.** Use Swift Testing (`@Suite`, `@Test`, `#expect`), not XCTest. Tests never contact a real bank. FinTS and extension tests will replay recorded responses. Write the test for a rule about money, categories, or transaction identity before the code.
- **No personal data.** Fixtures, examples, logs, and screenshots use made-up names and amounts and the test IBAN DE02120300000000202051. Logs never contain PINs, TANs, passwords, cookies, or tokens.
- **Code style.** Tabs for indentation. Swift 6 language mode with strict concurrency: `Domain` types are `Sendable`, and `AppModel` and `SyncCoordinator` are `@MainActor`. Doc comments say why, in the plain English of the docs.
