# Design

## Context

[ADR 0015](../../../docs/decisions/0015-extension-program.md) lets an installed catalog package run only while the accepted index lists its version (decision 24), and the standing of a package follows from the index (decision 13). The module `ExtensionCatalog` computes the standing in `Standing(of:in:)`, and the update plan in `UpdatePlan`, which plans no update to a version that is not newer.

## Decisions

### An older listed version stops the package

`Standing(of:in:)` compares the versions in the order of the catalog tools (`UpdatePlan.isNewer`). When the installed version is newer than the listed one, the standing is `stopped` with the message of the spec, not `outdated`. So the window shows the badge "Stopped" and no update button, and a running session ends as for a blocked package. A listed version that is newer, or one that the order cannot rank above the installed one, keeps `outdated` and its message.
