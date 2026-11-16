# Contributing

Thank you for helping. This page explains how to find work, how to propose a change, and what a pull request needs.

## Find something to work on

- The [roadmap](docs/roadmap.md) lists every change and every issue by release.
- Each change in [openspec/changes](openspec/changes/) has a proposal that explains why it exists and specs that say what the app must do.
- Issues labeled `kind: prototype` settle open decisions. They are a good start if you like to explore.
- To add a bank or service, write an extension. The author guide arrives with v0.1.
- To request support for a bank, open an issue with the **Bank or service request** template.

## How a change moves from spec to code

The project uses [OpenSpec](https://github.com/Fission-AI/OpenSpec). Install it with `npm install -g @fission-ai/openspec`. For Claude Code, `openspec init --tools claude` adds the `/opsx` commands to your checkout. Git ignores them.

1. **Pick a change.** `openspec list` shows all changes. `openspec show <change>` prints its proposal and specs.
2. **Plan it.** A change starts with a proposal and specs. Before you write code, add `design.md` and `tasks.md`. `openspec status --change <change>` names the next missing file, and `openspec instructions <file> --change <change>` explains how to write it. With Claude Code, `/opsx:apply <change>` does both steps with you.
3. **Build it.** Work through `tasks.md` and check off each task. Every scenario in the specs becomes a test or a documented manual check.
4. **Archive it.** When the pull request is merged, `openspec archive <change>` moves the requirements into [openspec/specs](openspec/specs/). From then on they describe what is built.

To build the app, you need Xcode and XcodeGen. The [README](README.md#build-and-run) has the commands.

Run `scripts/check.sh` before you open a pull request. It checks the links and paths in the docs, validates the specs, looks for unused code with [Periphery](https://github.com/peripheryapp/periphery), and runs the tests. Install Periphery 3.8.0, the version that CI uses, with `brew install periphery`. Its repository is archived, so 3.8.0 is the last release.

`Tests/DomainTests/PerformanceTests.swift` builds a ledger of 50,000 transactions and measures the build, an import of 2,000 rows, the search, a category view, and the category picker for 50,000 selected rows, each as the fastest of three runs. Its budgets hold for a release build, because a debug build is several times slower: run `scripts/test.sh -c release -Xswiftc -enable-testing --filter PerformanceTests --no-parallel`. `Tests/StorageTests/MergePerformanceTests.swift` measures the merge of one refresh into such a history the same way. CI runs both as their own step, one test after the other, so that no test measures the load of another one.

CI also runs `scripts/perf-check.sh`. It starts the optimized `Perf` build, which contains the debug harness, with a temporary data folder and 50,000 made-up transactions in 10 accounts, and runs the scenarios in [App/Sources/PerfCheck.swift](App/Sources/PerfCheck.swift), such as switching from a scrolled account to its group. It prints the longest main-thread stall and the memory of each scenario. A stall over the half second of the spec is reported as slow. The check fails when a stall exceeds 10 seconds, when the table misses rows of the view, or when the app crashes. Find the cause with `sample` while the scenario runs. Keep modifiers off the rows of a `Table`: a modifier on a row, such as `.draggable`, makes SwiftUI build a view graph for every row on each change of the view, while a modifier in a cell costs only for the visible rows. Add a scenario for every slow path you fix. The app window appears on the screen while the check runs. The check runs a copy of the app under its own bundle ID, so it leaves the settings and window frames of an installed Moneten alone.

## CI checks and runner use

The Ubuntu `changes` job selects checks from every changed path, including deletions and both sides of a rename. The `specs` job runs on every pull request. Main pushes and manual runs always select all checks.

| Event or changed paths | Specs | Units, release, tools, app build | UI performance and debug log | Periphery |
|---|---|---|---|---|
| PR only in docs/, openspec/, Markdown files, or issue templates | Yes | No | No | No |
| Other PR | Yes | Yes | App/, Sources/, scripts/, or workflow and action files | Swift files |
| Push to main or manual run | Yes | Yes | Yes | Yes |

Two unit shards separate Domain, Storage, Import, and Sync from the connectors and extension tools. New test targets join the connector shard unless added to the core filter. FinTS runs after the other connector tests, so their CPU work cannot delay its helper timers. Its second invocation uses only the test bundle built earlier in the same job. Performance suites, the host-start benchmark, and the Lua memory-limit suite run once, serially in release. The memory-limit suite keeps all its cases and iteration counts; optimized Lua avoids the long debug allocator and garbage-collector loops. The full 3,000-seed pairing check stays in every unit run. The FinTS timeout tests use existing inactivity and grace parameters; the default five-second grace still has its own test.

The app job builds Debug, checks the debug log when selected, and runs Periphery against the current build's index. It builds Perf once and uploads its app bundle. Two downstream runners run the UI halves with `scripts/perf-check.sh --skip-build --shard 1/2` and `scripts/perf-check.sh --skip-build --shard 2/2`. The portfolio scenarios stay together because they share setup. Run `scripts/perf-check.sh --build-only` to build without starting an app. The default command still builds and runs every scenario.

Four macOS build jobs can start together. The UI jobs start after the app build and each measure on a separate runner. This uses at most five concurrent macOS runners in one run. The goals are at most ten minutes elapsed and twenty macOS job minutes. Queue time depends on other pull requests in the organization.

Caches use exact keys for the Swift and Xcode versions and Package.resolved, Periphery's version and SHA-256, hbci4java's dependencies.lock, and Homebrew's XcodeGen formula. Downloads keep their checksum checks. The SwiftPM cache contains source checkouts, repositories, and binary dependencies, with no object files, index stores, or test results. Built app artifacts come only from the same run. No compiled build cache can supply a stale pass.

`scripts/ci-run.sh` preserves command failures and rejects compiler warnings whose source location is under App/, Sources/, Tests/, or Tools/. Downloaded dependencies and expected error text from Lua tests do not match that rule. Run `python3 scripts/test-ci.py` for the path and warning-gate checks.

The app writes a trail of the events that can replace the transaction table or change its rows to stderr, one line per event: the view, the filter kinds, changes of the ledger with their row counts, refreshes, sheets, dialogs, the lock, and the unlock. The lines hold kinds and counts only, no names, IBANs, amounts, purposes, or account numbers. When SwiftUI stops the app in a table update, the crash report has no frame of the app, and the last lines of the trail show what changed before. Start the app with stderr in a file to keep them, for example `open --stderr app.log /Applications/Moneten.app`.

## Propose a change

For a bug fix that restores specified behavior, open a pull request. For new or different behavior, change the spec first.

- To change a planned behavior, edit the spec in its change folder and say why in the pull request.
- To add a behavior, create a change with `openspec new change <name>` or with `/opsx:propose` in Claude Code. [openspec/config.yaml](openspec/config.yaml) holds the writing rules.
- A proposal lists what was observed in MoneyMoney and what Moneten decides on its own. [MoneyMoney analysis](docs/research/moneymoney-analysis.md) is the reference.
- MoneyMoney parity covers the content and the behavior, not the window chrome. The sidebar, the toolbar, and the window keep the system materials of macOS, Liquid Glass from macOS 26 on ([ADR 0012](docs/decisions/0012-system-glass-for-window-chrome.md)). `scripts/check-ui.py` enforces it. A pull request that changes the look of the app shows snapshots in light and dark mode.
- A change to a decision in [docs/decisions](docs/decisions/) needs a new decision record.

## What a pull request needs

1. Tests for the behavior you add or change. Tests never contact a real bank. Tests for FinTS and extensions will replay recorded responses.
2. A green CI run.
3. Screenshots in light and dark mode for any change to the interface. Use made-up names, IBANs, and amounts, never your own data.
4. No personal data. Remove names, IBANs, account numbers, and amounts from fixtures and logs before you commit them.

## Licensing

By submitting a contribution, you agree that it is licensed under the GNU General Public License v3.0 or later, the same license as the project. There is no contributor license agreement.

## Be kind

Treat everyone with respect. The maintainers remove comments that attack people.
