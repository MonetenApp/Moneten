## Why

A user currently has to find a system crash report to report an unexpected quit. That report can hold identifying data. Issue #224 brings an optional, limited crash report into v0.1.

## What Changes

- Offer the newest crash report after the system delivers it.
- Keep it encrypted until the user opens GitHub, copies it, or declines.
- Include versions, exception and signal numbers, and binary UUIDs and offsets of the crashed thread.
- Prefill the bug report form from the sheet and the Help menu.
- Give maintainers a local symbolication script.

## Capabilities

### New Capabilities

- `crash-reports`: private crash reports that the user reads and shares on request.

### Modified Capabilities

None.

## Impact

- Milestone: v0.1. Issue: #224.
- Modules: Domain builds reports and URLs. Storage keeps one encrypted report. App subscribes to the system and shows the sheet.
- [ADR 0002](../../../docs/decisions/0002-local-first-no-server.md) and [SECURITY.md](../../../SECURITY.md) apply.
- General logging stays in add-log-and-diagnostics for a later release. This change adds no log file, helper crash report, server, or marker fallback.
- Release dSYM retention remains an open task of add-software-update and #25.

## Reference behavior

### Observed in MoneyMoney 2.5.3

The [analysis](../../../docs/research/moneymoney-analysis.md) found "Report an Issue..." but no crash reporter.

### Decided for Moneten

The user reviews a report before sharing it on GitHub. Nothing is uploaded automatically. System diagnostic delivery must be measured in a debug build and any missing delivery stays an open point.
