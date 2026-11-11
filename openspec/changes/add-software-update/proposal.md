# Proposal: Ship a signed app that updates itself

## Why

Banks change their servers often, so a banking app that is a few months old stops working for some of them. Users need new versions without effort, and they need to know that an update really comes from the project. A download that macOS opens without warnings is also the first sign of trust.

## What Changes

- The app is signed and notarized, so macOS opens it without a security warning.
- "Check for Updates..." looks for a new version. With the setting "Show notification about new versions of Moneten", the app also looks on its own once a day.
- An update window shows the new version and its release notes, with "Install" and "Remind Me Later".
- The app downloads the update, checks its signature, installs it, and restarts.
- Each failure has its own message and leaves the running version intact.
- "Participate in beta tests and display pre-release versions" also offers pre-release versions.
- The bank list and the BIC directory update between releases, with the same signature check.
- No request for an update sends personal data.

## Capabilities

### New Capabilities

- `software-update`: how the app proves where it comes from, how it finds, checks, and installs new versions, and how its bank data files stay current.

### Modified Capabilities

None.

## Impact

- Milestone: v0.1
- Issues: #25
- Modules: `App` owns the update commands, the update window, and the settings. The release pipeline in CI signs and notarizes the app and publishes the update feed.
- Depends on the change `add-app-settings` for the two settings on the "General" tab.
- Depends on the change `add-encrypted-database`, which upgrades the database after an update.
- Decisions: [ADR 0002](../../../docs/decisions/0002-local-first-no-server.md), [ADR 0006](../../../docs/decisions/0006-license-gpl-3.md).

## Reference behavior

### Observed in MoneyMoney 2.5.3

- The app is digitally signed, and the automatic update checks that a new version really comes from the developer ([security page](https://moneymoney.app/security/)).
- The application menu has "Check for Updates...". See [analysis](../../../docs/research/moneymoney-analysis.md#menus-and-keyboard-shortcuts-u).
- The "General" settings have "Show notification about new versions of MoneyMoney" and "Participate in beta tests and display pre-release versions". See [analysis](../../../docs/research/moneymoney-analysis.md#settings-u).
- With the notification setting on, a new version is shown at the launch of the app, at most one day after its release ([update page](https://moneymoney.app/help/install-update/)).
- With the beta setting on, the app offers the current beta version ([beta page](https://moneymoney.app/beta/)).
- The interface strings include "A new version of MoneyMoney is available!", "Release Notes:", "Install", "Remind Me Later", "Downloading update...", "Ready to Install", "You're up-to-date!", a sentence that names the newest version, "Could not check for updates:", "Could not display release notes.", and "Could not install update.".
- The interface strings include messages for these cases. macOS runs the app from a temporary location and the app must first be moved to the Applications folder. Several copies of the app are installed. The application file is damaged and must be installed again, and the accounts stay because the database is stored elsewhere. The newest version needs a newer macOS. The running version has not been checked with this version of macOS.
- Failure messages point to the download page for a manual update.
- The app regularly asks the developer's service for updates and for current bank server settings and sends no personal information ([analysis](../../../docs/research/moneymoney-analysis.md#network-s-w)).
- The BIC directory inside the app is updated online (version history, 2.2.11).

### Decided for Moneten

- Updates and data files come from the public releases of the project on GitHub. There is no vendor service.
- The update request sends the version of the app, the version of macOS, and the processor type. It sends no identifier of the user or of the installation.
- With the notification setting off, the app makes no automatic request for a new version. The manual command still works. Whether MoneyMoney still contacts its service with the setting off was not observed.
- The app does not install an update while a bank dialog or a payment is in progress.
- On a macOS version that is newer than the installed app, the app looks for an update even when the automatic check is off. MoneyMoney shows the notice. Whether it also checks was not observed.
- The beta setting is off by default. A user who turns it off stays on the installed pre-release version until a newer stable version exists.
- A renamed application file is no obstacle for an update. MoneyMoney requires its original file name.
- Bank data files are signed with the same key as the app updates, and the app keeps its current files when a download fails the check.
- There is no App Store edition, so the App Store messages have no counterpart.
