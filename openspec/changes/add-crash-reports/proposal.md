## Why

A user currently has to find a system crash report to report an unexpected quit. That report can hold identifying data. Issue #224 brings an optional, limited crash report into v0.1.

## What Changes

- Offer the newest crash report after the system delivers it.
- Keep it encrypted until a decision. Opening GitHub with a cut report keeps the full report available.
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
- General logging stays in add-log-and-diagnostics for a later release. This change adds no log file, helper crash report, or server. The fallback reads only system crash file names and modification dates.
- Release dSYM retention remains an open task of add-software-update and #25.

## Reference behavior

### Observed in MoneyMoney 2.5.3

The [analysis](../../../docs/research/moneymoney-analysis.md) found "Report an Issue..." but no crash reporter.

### Decided for Moneten

The user reviews a report before sharing it on GitHub. Nothing is uploaded automatically. When MetricKit delivers no diagnostic, a Moneten crash file newer than the previous launch provides a short report. Force quits and power loss without a crash file do not prompt. The encrypted state records the launch time and versions across updates. Delayed details replace an undecided short report. A declined crash is not offered again.
