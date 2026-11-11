# Contributing

Thank you for helping. This page explains how to find work, how to propose a change, and what a pull request needs.

## Find something to work on

- The [roadmap](docs/roadmap.md) lists every change and every issue by release.
- Each change in [openspec/changes](openspec/changes/) has a proposal that explains why it exists and specs that say what the app must do.
- Issues labeled `kind: prototype` settle open decisions. They are a good start if you like to explore.
- To add a bank or service, write an extension. The author guide arrives with v0.1.
- To request support for a bank, open an issue with the **Bank or service request** template.

## How a change moves from spec to code

The project uses [OpenSpec](https://github.com/Fission-AI/OpenSpec). Install it with `npm install -g @fission-ai/openspec`.

1. **Pick a change.** `openspec list` shows all changes. `openspec show <change>` prints its proposal and specs.
2. **Plan it.** A change starts with a proposal and specs. Before you write code, add `design.md` and `tasks.md`. `openspec status --change <change>` names the next missing file, and `openspec instructions <file> --change <change>` explains how to write it. With Claude Code, `/opsx:apply <change>` does both steps with you.
3. **Build it.** Work through `tasks.md` and check off each task. Every scenario in the specs becomes a test or a documented manual check.
4. **Archive it.** When the pull request is merged, `openspec archive <change>` moves the requirements into [openspec/specs](openspec/specs/). From then on they describe what is built.

To build the app, you need Xcode and XcodeGen. The [README](README.md#build-and-run) has the commands.

Run `scripts/check.sh` before you open a pull request. It checks the links and paths in the docs, validates the specs, looks for unused code with [Periphery](https://github.com/peripheryapp/periphery), and runs the tests. Install Periphery 3.8.0, the version that CI uses, with `brew install periphery`. Its repository is archived, so 3.8.0 is the last release.

`Tests/DomainTests/PerformanceTests.swift` builds a ledger of 50,000 transactions and measures the build, an import of 2,000 rows, the search, and a category view, each as the fastest of three runs. Its budgets hold for a release build, because a debug build is several times slower: run `scripts/test.sh -c release -Xswiftc -enable-testing --filter PerformanceTests`. CI runs it as its own step.

CI also runs `scripts/perf-check.sh`. It starts the optimized `Perf` build, which contains the debug harness, with a temporary data folder and 50,000 made-up transactions in 10 accounts, and runs the scenarios in [App/Sources/PerfCheck.swift](App/Sources/PerfCheck.swift), such as switching from a scrolled account to its group. It prints the longest main-thread stall and the memory of each scenario. A stall over the half second of the spec is reported as slow. The check fails when a stall exceeds 5 seconds, when the table misses rows of the view, or when the app crashes. Find the cause with `sample` while the scenario runs. Keep modifiers off the rows of a `Table`: a modifier on a row, such as `.draggable`, makes SwiftUI build a view graph for every row on each change of the view, while a modifier in a cell costs only for the visible rows. Add a scenario for every slow path you fix. The app window appears on the screen while the check runs.

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
