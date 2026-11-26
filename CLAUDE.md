# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

Moneten is an open source banking app for the Mac: Swift 6, SwiftUI, macOS 15 or newer, GPL-3.0-or-later. It is local-first. It has no server, no account, and no telemetry, and all data stays in an encrypted database on the Mac. The local part of v0.1 is built: the encrypted database, the MoneyMoney migration, the CSV, CAMT, and MT940 import, the transaction list, categories, rules, charts, and the sync model. The FinTS connector adds bank accesses and refreshes them, and saves a PIN in the database on request. Lua extensions add accounts of other services, installed from the signed catalog or from a file.

The behavior target is MoneyMoney 2.5.3. [docs/research/moneymoney-analysis.md](docs/research/moneymoney-analysis.md) records what was observed. A user who switches must find the same behavior, unless a proposal names a difference under "Decided for Moneten".

## Commands

Tools: Xcode, XcodeGen (`brew install xcodegen`), the OpenSpec CLI (`npm install -g @fission-ai/openspec`), Periphery 3.8.0 (`brew install periphery`), and a JDK 17 or later for the FinTS helper and the FinTS probe.

```sh
scripts/test.sh                                    # all library tests
scripts/test.sh --filter LedgerTests               # one suite
scripts/test.sh --filter 'LedgerTests/accountTree' # one test
scripts/test.sh -c release -Xswiftc -enable-testing --filter PerformanceTests   # budgets hold only in release
LIBDISPATCH_COOPERATIVE_POOL_STRICT=1 scripts/test.sh --filter 'CatalogStore|MigrationStore|Extension'   # local diagnosis: one thread of Swift concurrency, so a test that blocks a shared thread hangs; not on CI, where it hangs before any output
scripts/check.sh                                   # docs, chrome rule, specs, Periphery, tests: run before a PR

scripts/generate-project.sh                        # writes App/Moneten.xcodeproj
scripts/build-app.sh                               # dist/Moneten.app, Release; "debug" for a Debug build
scripts/build-app.sh compile                       # compiles and links the app in Release, unsigned, as CI does after the debug build
scripts/release.sh dry-run                         # the release pipeline without secrets: disk image and signed test feed
python3 scripts/release-notes.py check             # the format of CHANGELOG.md
swift run --disable-keychain ext test Extensions/Example Fixtures/example/fixture.json Fixtures/example/expected.json
scripts/perf-check.sh                              # UI performance scenarios in the Perf build; shows a window
scripts/fints-probe-java.sh --build-only           # compiles the hbci4java probe, as CI does
scripts/update-test-feed.sh DIR 0.1.2:204 0.1.3:205   # a test feed signed with the test update key, for a Debug build with MONETEN_FEED_URL

python3 scripts/check-docs.py                      # links, paths, data-model names, ADR index
python3 scripts/check-ui.py                        # window chrome rule (ADR 0012)
python3 scripts/check-time-limits.py               # every time limit in Tests/ goes through budget(_:)
python3 scripts/check-localization.py .build/xcode # German value for every text, after scripts/build-app.sh debug; --update adds and removes keys
openspec validate --all --strict --no-interactive
python3 scripts/roadmap.py                         # regenerates docs/roadmap.md, needs gh
python3 scripts/make-sounds.py                     # writes the three notification sounds into App/Resources/Sounds
```

Use `scripts/test.sh` instead of plain `swift test`. It adds `--disable-keychain`, without which the package manager waits for a Keychain prompt, and the Swift Testing paths for a Mac with only the Command Line Tools.

Start a debug build with a throwaway data folder: `scripts/build-app.sh debug`, quit every running Moneten, then `open -n --env MONETEN_DATA_DIR=/path/to/folder dist/Moneten.app`. Without `-n`, `open` brings an instance that already runs to the front, and that instance keeps its own data folder. Without the variable, the app opens the real database in `~/Library/Application Support/Moneten`. Only Debug and Perf builds read `MONETEN_DATA_DIR`. A Release build ignores it and always opens the real database. A run with `MONETEN_DATA_DIR` keeps its settings in `Settings.plist` in that folder, never in the defaults of the bundle ID, so it leaves the settings of a real Moneten alone (issue #220, `AppSettings` in `App/Sources/AppSettings.swift`). Set a setting before the launch with `defaults write /path/to/folder/Settings <key> <value>`. Sparkle and AppKit still write their own keys, such as the times of the update checks and the frames of the windows, into the defaults of the bundle ID. Such a run never changes "Show notification about new versions of Moneten", whose value `SUEnableAutomaticChecks` Sparkle keeps there: the switch logs "update check setting kept: harness" instead.

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
| `FinTS` | `FinTSConnector`, which runs the helper of `Tools/FinTSHelper`, the bank directory and `BankLookup` for "Add Account", the rules of each bank group, and `BankDataUpdater` for the signed bank data files |
| `ExtensionHost` | Runs a Lua extension session with the host limit of ADR 0015, one sandboxed `MonetenExtensionHost` process per session, and offers the MoneyMoney-compatible API in `Sources/ExtensionHost/API`. `Sources/CLua` is Lua 5.4 from lua.org (`scripts/vendor-lua.sh`). |
| `ExtensionConnector` | `ExtensionConnector`, which calls the entry points of an extension in order, turns its challenge tables into requests to the user, and maps its result tables to `Domain` types. `scripts/check-published.sh` checks the published MoneyMoney extensions against the host. |
| `ExtensionCatalog` | The signed index of the catalog (`IndexVerifier`), the `Installer` of catalog packages, the `UpdatePlan` of a newer version, and `FileInstall` for an extension from a file |
| `ext` | The command line tool for extension authors in `Tools/ext`: `ext run`, `ext record`, and `ext test`. It starts its own binary as the host process and calls `ExtensionConnector` as the app does. The design of `add-extension-developer-tools` has the fixture format. |
| App | SwiftUI views and the `@Observable` `AppModel` |

How the parts work together:

- **Ledger and store.** After unlocking, `AppModel` loads everything once with `Store.loadLedger()` into a `Ledger` value. Views read only the ledger. A change must write through `Store` first and change the ledger only after the write succeeds, as `commit` in `App/Sources/AppModel.swift` does. Keep both in step, and never query the database from a view.
- **Money and days.** An amount is an `Int64` in minor units (`amountMinor`, `Money.minorUnits`) with an ISO 4217 currency. No `Double` stores an amount. A sum across currencies is a `MoneySums` and never converts. A booking date is a `Day` (yyyymmdd as `Int`) without a time zone.
- **Localized text.** The libraries, `Domain` included, may call `String(localized:)`, but only to build a text that the user reads. A localized text is never data, never a key, and never compared to decide behavior. The app holds the one catalog, `App/Resources/Localizable.xcstrings`; the tests run without it and read English.
- **Parse at the edge.** Each parser and each connector turns raw data into `Domain` types. Code inside `Domain`, `Storage`, and the app trusts those types and does not check them again. An entry that cannot be read fails the whole file with its line, so nothing from the file is imported. Only the CSV parser skips a row without a date.
- **Schema changes.** Add a new `registerMigration("vN")` at the end of `Sources/Storage/Schema.swift`. Never change a migration that has shipped. `Transaction` is stored in the table `bankTransaction`. The models are Codable GRDB records.
- **Sync.** FinTS and extensions implement `BankConnector.refresh(_:_:)`, as finAPI will, and ask the user only through `SyncSession.ask(_:)`. `SyncState` is a pure state machine. Views read it and keep no flags of their own. The `deliver` closure of `SyncCoordinator` merges fetched data, `storeState` stores the new `AccessState` before the next work of the access starts, and `ended` stores the status of each account. The [design of add-account-refresh](openspec/changes/add-account-refresh/design.md) has the complete types and the dialog queue.
- **FinTS.** [ADR 0014](docs/decisions/0014-fints-through-hbci4java.md) replaces HBCI4Swift with hbci4java in a helper process that talks JSON lines over a pipe. `FinTSConnector` runs the helper of `Tools/FinTSHelper`. `Tools/FinTSProbeJava` is the probe for bank tests (issue #11), and its `dependencies.lock` pins the jars of both and the JDK whose runtime ships in a release. The HBCI4Swift submodule and the Swift probe were removed in issue #107. A text that still names HBCI4Swift as the FinTS engine is out of date.

### Debug harness

Debug and Perf builds (`#if DEBUG || PERF_HARNESS`) can be driven without a screen when the environment variable `MONETEN_DEBUG_DIR` names a folder. Build one with `scripts/build-app.sh debug`. Every harness run needs `MONETEN_DATA_DIR`, because commands such as `create`, `seed`, and `setpassword` change the database that is open, and `MONETEN_KEYCHAIN_PATH`, the absolute path of a throwaway keychain file, which takes the place of the login keychain for every Keychain entry of the app. Without either, a harness run exits with status 2 at launch, so that no check changes the real database or reads or writes the login keychain. Create the file with `security create-keychain -p <password> <path>`, as `scripts/check-debug-log.sh` does, and remove it as a plain file, never with `security delete-keychain`, which edits the search list of the user. A debug build started without the harness keeps the real data folder and the login keychain. One started with `MONETEN_KEYCHAIN_PATH` needs `MONETEN_DATA_DIR` too, or it exits with status 2, and a Release build reads none of these variables. Commands arrive as distributed notifications named `io.github.moneten.debug`, with the debug folder as the object and the `userInfo` keys `command` and `argument`. Examples are `create`, `unlock`, `seed`, `syncdemo`, `appearance dark`, `snapshot`, and `perf`. The app writes `debug.log` and PNG snapshots into the folder. `scripts/perf-check.sh` shows how to post the notifications, and `App/Sources/DebugHarness.swift` lists every command. A harness run never asks to become the active app, not even for a bank dialog, an alert, or the offer of a crash report: it drops the requests of AppKit as well. Its windows can still open above the app you work in, and a click on one activates it. Start the binary inside the app bundle directly, as `scripts/perf-check.sh` does, or with `open -g`, because a plain `open` brings the app to the front. Only `mainkey table` and `securefield` ask for the focus, and macOS grants it only when the app in front gives it up. Use the harness to check a UI change and to make the light and dark screenshots that a UI pull request needs. With `MONETEN_FINTS_HELPER` set to `scripts/fake-fints-helper.sh`, a debug build runs the commands `setup`, `answer`, `refresh`, and `status` against a made-up bank and never contacts a real one. `MONETEN_DEBUG_NO_IDLE_LOCK=1` keeps the inactivity lock off, which the lock settings in the database would otherwise turn on. `MONETEN_DEBUG_CLOCK_OFFSET` moves the clock of the automatic refresh ahead by that many seconds, so with 7155 an account with the interval "every two hours" is due 45 seconds after its last refresh. `notices` and `menubarsnapshot` show the notifications and the menu bar popover, `noticeclick` acts as a click on a notification, `menubar click` and `menubar press <n>` click the menu bar icon and a control of its popover, `setting <key> on` writes the default of one of the switches of these checks directly, without the question for the permission that its toggle asks, `closemain` and `openmain` close and open the main window, `network off` lets the app act as if the Mac were offline, and `present on` lets the automatic refresh run while the display sleeps. The login "neu" of the made-up bank brings one more transaction with each refresh. macOS knows the notifications of a copy of the app only when the copy lies outside the temporary folder, for example in `.build`, and a copy under a new bundle ID asks for the permission, which only a person can grant. `MONETEN_DEBUG_REAL_BANK=1`, read only by a Debug build for the bank tests of `docs/research/bank-access.md`, lets a refresh that a person starts in the window, and the automatic refresh, reach a real bank through FinTS, and the harness then takes only `create`, `sheet`, and `status`; an agent never sets it. `update` drives the update window and the updater (`App/Sources/Update/UpdateHarness.swift`); a debug build looks for updates only in the feed that `MONETEN_FEED_URL` names.

## Rules

- **Specs come first.** The project uses OpenSpec. Each planned change is a folder in `openspec/changes/` with a proposal and specs, and gets `design.md` and `tasks.md` before its code. New or different behavior changes the spec first. A bug fix that restores specified behavior goes straight to a pull request. The `/opsx:*` commands explore, propose, apply, update, sync, and archive changes. They are not in git: `openspec init --tools claude` writes them into the checkout. `openspec/specs/` gets the requirements of a change when the change is archived. The `.openspec.yaml` of a change holds `x-milestone` and `x-issues`.
- **Writing.** [openspec/config.yaml](openspec/config.yaml) has the rules for specs: English, short sentences, active voice, present tense, one term for one thing, and no em or en dashes. A requirement starts with "The app SHALL", states one behavior, has scenarios with concrete values, and never names MoneyMoney. The docs, code comments, and commit messages use the same plain style.
- **Decisions.** A change to a decision in `docs/decisions/` needs a new decision record. The status in each record must match the index in `docs/decisions/README.md`.
- **Docs are checked against the code.** In every tracked Markdown file, each relative link and each repository path in code font must exist or be ignored by git. Each name in code font in `docs/data-model.md`, above its section on later types, must be declared in `Sources/`. Update the docs when you rename or remove something. `docs/roadmap.md` is generated, so do not edit it by hand.
- **Window chrome.** The sidebar, the toolbar, and the window keep the system materials of macOS, Liquid Glass from macOS 26 on ([ADR 0012](docs/decisions/0012-system-glass-for-window-chrome.md)). MoneyMoney parity covers content and behavior, not chrome. `scripts/check-ui.py` fails on `.toolbarBackground` or `.containerBackground` in any Swift file in `App/Sources` except the debug harness, and on a colored `.background` in a file with the sidebar or the split view, unless the line has `// chrome-ok: <reason>`.
- **No unused code.** Periphery runs in strict mode in CI, so a declaration without a use fails the build. `.periphery.yml` keeps the sync model until the connectors use it.
- **Performance.** The ledger must stay fast with 50,000 transactions (`Tests/DomainTests/PerformanceTests.swift`). In a SwiftUI `Table`, put modifiers in the cells, never on the rows: a row modifier such as `.draggable` rebuilds the view graph of every row. Add a scenario to `App/Sources/PerfCheck.swift` for every slow path you fix.
- **Tests.** Use Swift Testing (`@Suite`, `@Test`, `#expect`), not XCTest. Tests never contact a real bank. FinTS tests run scripts in place of the helper, and extension tests replay recorded responses. Write the test for a rule about money, categories, or transaction identity before the code. Every upper time limit in a test goes through `budget(_:)` in `Tests/TestSupport/Budget.swift`, which gives it 1.5 times as long on a runner that GitHub hosts. `scripts/check-time-limits.py` fails on a raw limit in either direction, unless the line has `// time-ok: <reason>`. A wait on a deadline and a lower bound need no budget.
- **No personal data.** Fixtures, examples, logs, and screenshots use made-up names and amounts and the test IBAN DE02120300000000202051. Logs never contain PINs, TANs, passwords, cookies, or tokens.
- **Code style.** Tabs for indentation. Swift 6 language mode with strict concurrency: `Domain` types are `Sendable`, and `AppModel` and `SyncCoordinator` are `@MainActor`. Doc comments say why, in the plain English of the docs.
