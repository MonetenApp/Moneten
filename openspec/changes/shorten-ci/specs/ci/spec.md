## ADDED Requirements

### Requirement: Select CI checks from changed paths
The CI workflow SHALL run specification checks for every pull request and skip macOS jobs when every changed path is documentation, a Markdown file, or an issue template.

#### Scenario: Documentation-only pull request
- **WHEN** a pull request changes only CONTRIBUTING.md and docs/architecture.md
- **THEN** specification checks run
- **AND** no macOS job runs

#### Scenario: Full verification
- **WHEN** main receives a push or a developer starts a manual run
- **THEN** all unit, tool, app, and performance checks run

### Requirement: Preserve verification in shards
The CI workflow SHALL run every selected test and scenario once, keep performance measurements isolated, and reject compiler warnings from repository targets.

#### Scenario: Swift implementation changes
- **WHEN** a pull request changes Sources/Domain/Ledger.swift
- **THEN** both unit shards, release performance, app checks, both UI halves, tools, and unused-code checks run
- **AND** a compiler warning in Sources/Domain/Ledger.swift fails the producing step
