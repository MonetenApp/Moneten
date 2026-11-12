# Proposal: Add the settings window

## Why

Many features have a switch that the user sets once, such as the language, the lock time, or the automatic refresh. These switches need one place that every Mac user knows how to find, and common rules for when a change takes effect and where it is stored.

## What Changes

- "Settings..." (⌘,) opens one settings window with the tabs "General", "Security", "Payments", and "Subscription". Extensions have their own window, not a settings tab.
- A tab appears when the installed version has at least one setting for it.
- A change takes effect at once. A setting that needs a restart says so.
- Settings survive restarts and updates. They are stored outside the database and hold no personal data.
- This change defines the window and its rules only. Each setting belongs to the capability that owns its behavior.

## Capabilities

### New Capabilities

- `app-settings`: the settings window, its tabs, and the rules that all settings share.

### Modified Capabilities

None.

## Impact

- Milestone: v0.1
- Issues: #5
- Modules: `App` owns the settings window and the storage of settings.
- Depends on the change `add-main-window`.
- Decisions: [ADR 0015](../../../docs/decisions/0015-extension-program.md) moves the extensions from the settings into the "Extensions" window.

These capabilities own the settings on each tab.

| Tab | Setting | Capability |
|---|---|---|
| General | "Show notification about new versions of Moneten", "Participate in beta tests and display pre-release versions" | `software-update` |
| General | "Show Moneten icon in menu bar", "Show banner notification on new transactions", "Play sound on new transactions" | `notifications-and-menu-bar` |
| General | "Automatically refresh accounts" | `account-refresh` |
| General | "Language" | `localization-and-formatting` |
| Security | "Set Database Password..." and "Change Database Password..." | `database-encryption` |
| Security | "Lock when main window is closed", "Lock after ... minutes of inactivity", "Unlock automatically at application start", "Unlock with Touch ID", "Unlock with Apple Watch" | `app-lock` |
| Payments | "Send templates with double click by default" | `payment-templates` |
| Payments | "Save new payments in outbox by default" | `payment-outbox` |
| Payments | "Enable Secoder visualization" | `hbci-keys-and-chipcards` |
| Subscription | The state of the subscription and its links | `aggregator-subscription` |

## Reference behavior

### Observed in MoneyMoney 2.5.3

- "Settings..." in the application menu has the shortcut ⌘, and opens one window with the tabs "General", "Security", "Payments", "PSD2", and "Extensions". See [analysis](../../../docs/research/moneymoney-analysis.md#settings-u).
- The window has no button to save or to cancel.
- Settings with consequences carry a short explanation below the switch, for example the two settings for templates and the outbox on the "Payments" tab.
- The interface strings include a message that the app must be restarted for a change to take effect, and a message that a setting could not be stored.
- Version 0.1 of Moneten needs the tabs "General" and "Security". The other tabs belong to later releases.

### Decided for Moneten

- The tab "Subscription" takes the place of the tab "PSD2". See [not carried over](../../../docs/research/moneymoney-analysis.md#not-carried-over).
- The settings window has no tab "Extensions". The menu item "Extensions" opens the "Extensions" window, which lists, installs, updates, and removes extensions ([ADR 0015](../../../docs/decisions/0015-extension-program.md)). The app has no setting that turns the signature check off, no paid add-ons, and no "Restore Purchases".
- A tab appears only when the installed version has a setting for it.
- Settings are stored outside the encrypted database and hold no personal data. The app needs some of them before the database is open, for example the language and the unlock settings. Where MoneyMoney stores each setting was not checked in detail.
- The settings window opens only while the app is unlocked.
- The window opens on the tab that was open last.
