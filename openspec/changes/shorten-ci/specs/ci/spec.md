## ADDED Requirements

### Requirement: Select CI checks from changed paths
The CI workflow SHALL run specification checks for every pull request and skip macOS only for allowed documentation and issue-template paths with no macOS consumer. Unknown paths select every check.

#### Scenario: Documentation-only pull request
- **WHEN** a pull request changes only CONTRIBUTING.md and docs/architecture.md
- **THEN** specification checks run
- **AND** no macOS job runs

#### Scenario: Full verification
- **WHEN** main receives a push or a developer starts a manual run
- **THEN** all unit, tool, app, and performance checks run

#### Scenario: Documentation consumed on macOS
- **WHEN** a pull request changes docs/export-format.md
- **THEN** all macOS checks run because a storage test reads that file

#### Scenario: Build and analysis inputs
- **WHEN** a pull request changes Package.resolved, App/project.yml, .periphery.yml, Tools/, or .github/workflows/
- **THEN** app privacy, UI performance, and unused-code checks run

### Requirement: Preserve verification in shards
The CI workflow SHALL run every selected test contract and scenario, keep performance measurements isolated, and reject compiler warnings from repository targets.

#### Scenario: Swift implementation changes
- **WHEN** a pull request changes Sources/Domain/Ledger.swift
- **THEN** all unit tests, release performance, app checks, both UI halves, tools, and unused-code checks run
- **AND** a compiler warning in Sources/Domain/Ledger.swift fails the producing step

### Requirement: Bound runner use
The CI workflow SHALL use at most four macOS jobs at once and reuse one run-local Perf app for privacy and both UI halves. Artifacts expire after one day. Every assertion, memory ceiling, performance budget, and host-consent configuration remains checked.

#### Scenario: Full run
- **WHEN** every check is selected
- **THEN** no more than four macOS jobs overlap
- **AND** privacy exercises the CSV handoff in the Perf harness
- **AND** both UI runners download the app built in that run
