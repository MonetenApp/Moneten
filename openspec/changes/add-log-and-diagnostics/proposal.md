# Proposal: Show a log that helps with problems and never leaks secrets

## Why

When a bank rejects a login or a refresh fails, the user and the people who help them need to see what happened. This project gets its help through public issues, so a log that someone shares must not expose a PIN, a name, or a balance.

## What Changes

- "Log Window" (⌘L) shows what the app did, with a time for each entry.
- The log never contains PINs, TANs, passwords, cookies, or tokens.
- The log replaces IBANs, names, amounts, and purpose texts with placeholders, unless the user turns on full detail for one refresh.
- The user can clear, copy, and save the log. The app warns before a log with personal data leaves the app.
- Error messages show when the error happened and lead to the matching log entry.
- "Report an Issue..." opens the issue page of the project with the versions filled in. The app sends nothing by itself.
- The log has a size limit.

## Capabilities

### New Capabilities

- `log-and-diagnostics`: what the app records about its own work, what the log must never contain, how the user reads and shares it, and how the app reports errors.

### Modified Capabilities

None.

## Impact

- Milestone: later
- Issues: none yet
- Modules: `App` owns the log window and the commands. Every connector writes to the log through one interface that removes secrets.
- Depends on the change `add-main-window`.
- The app writes a log file from the first release on, and the rules about secrets in [architecture](../../../docs/architecture.md) and [SECURITY.md](../../../SECURITY.md) apply from then. This change adds the window, the commands, and the full rule set as a spec.
- Decisions: [ADR 0002](../../../docs/decisions/0002-local-first-no-server.md).

## Reference behavior

### Observed in MoneyMoney 2.5.3

- The Window menu has "Log Window" with the shortcut ⌘L. See [analysis](../../../docs/research/moneymoney-analysis.md#menus-and-keyboard-shortcuts-u).
- The log can be cleared, copied, and saved (version history, 2.5.0).
- The log shows which database file was loaded. An interface string sends the user to the log to check this.
- Error messages show the time at which the error happened (version history, 2.1.1).
- The interface strings include "View Log...", which leads from a message to the log.
- A message for an internal error shows the technical error text and asks the user to send it to support.
- The Help menu has "Report an Issue...", which starts a message to the vendor's support (version history, 2.4.50).
- The Help menu has "Encrypt File for Sending...". It encrypts the log or another file so that only the vendor's staff can open it (version history, 2.5.0).
- Names in the program file point to switches for more detail in the log for single areas, such as the network and Bluetooth, and to a limit for the size of the log.

### Decided for MonetenMoneten

- The rules about secrets and about placeholders for personal data come from [architecture](../../../docs/architecture.md). What MoneyMoney writes into its log was not read, because the log of the analyzed installation holds real data.
- Full detail applies to the next refresh of one access, stays in memory only, and ends by itself. The log file on disk always has placeholders.
- A redacted log for public bug reports takes the place of "Encrypt File for Sending...". See [not carried over](../../../docs/research/moneymoney-analysis.md#not-carried-over).
- "Report an Issue..." opens the issue page of the project in the browser. The app attaches nothing.
- The app never sends logs, crash reports, or usage data on its own.
- The log keeps 10 MB or 30 days, whichever is less. MoneyMoney's limit was not observed.
- The log window has a search field. MoneyMoney's log window was not opened.
- "Clear" asks for no confirmation.
