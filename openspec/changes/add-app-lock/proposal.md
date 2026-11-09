# Proposal: Lock the app and unlock it with the password, Touch ID, or an Apple Watch

## Why

A Mac is often unlocked while its owner is away from the desk. The finances must not be open to everyone who sits down at it. At the same time, typing a long password many times a day makes people choose a short one. Locking with a comfortable way to unlock solves both.

## What Changes

- The app asks for the database password at launch and shows a lock screen until the user has unlocked it.
- The user can lock the app with a menu command, a shortcut, and a toolbar button.
- The app can lock itself when the main window closes and after a time without activity.
- Three optional settings make unlocking comfortable: automatically at launch, with Touch ID, and with an Apple Watch. Each one keeps the password in the Keychain. When all three are off, the app deletes it there.
- The password always works as a fallback.
- A locked app shows no data and does no work that needs the data.
- Changing a security setting needs the database password.

## Capabilities

### New Capabilities

- `app-lock`: when the app locks, what a locked app shows and does, and the ways to unlock it.

### Modified Capabilities

None.

## Impact

- Milestone: v0.1
- Issues: #4
- Modules: `Storage` owns the Keychain entry and closes the database when the app locks. `App` owns the lock screen, the commands, and the "Security" settings.
- Depends on the change `add-encrypted-database`.
- The changes `add-account-refresh`, `add-notifications-and-menu-bar`, `add-applescript-automation`, and `add-login-credentials` rely on the lock state that this change defines.
- Decisions: [ADR 0009](../../../docs/decisions/0009-database-password-as-in-moneymoney.md).

## Reference behavior

### Observed in MoneyMoney 2.5.3

- The application menu has "Lock MoneyMoney" with the shortcut ⌃⌘L, and the toolbar has a lock button. See [analysis](../../../docs/research/moneymoney-analysis.md#menus-and-keyboard-shortcuts-u).
- The "Security" settings have "Lock when main window is closed", "Lock after" a number of "minutes of inactivity", "Unlock automatically at application start", "Unlock with Touch ID", and "Unlock with Apple Watch". See [analysis](../../../docs/research/moneymoney-analysis.md#settings-u).
- Saving the database password in the Keychain is optional and exists so that the user need not type it at every launch ([security page](https://moneymoney.app/security/)).
- Touch ID and Apple Watch have separate settings (version history, 2.3.25).
- The interface strings include "Open with password", "Open with Touch ID.", "Open with Apple Watch.", "Open with Touch ID or Apple Watch.", "Incorrect password!", and "Forgot your password?".
- The interface strings include messages for these cases. The Mac has no Touch ID sensor. Touch ID is not set up in macOS. Touch ID is locked after too many failed attempts. The MacBook lid is closed. No Apple Watch is nearby. Unlocking with Apple Watch is not set up in macOS. The Keychain could not store the password or the configuration.
- Touch ID does not start while a MacBook runs with a closed lid on an external display (version history, 2.2.17).
- A typed database password is removed from the field after five minutes of inactivity (version history, 2.4.3).
- While the main window is locked, no account is refreshed in the background, so that no two-factor request is triggered (version history, 2.4.49).
- The interface strings include "This setting is password-protected." and "Please enter your database password first.".
- The interface strings include "Locked database".

### Decided for MonetenMoneten

- The three unlock settings keep the password in the Keychain, and the app deletes it when all three are off. This follows [ADR 0009](../../../docs/decisions/0009-database-password-as-in-moneymoney.md). MoneyMoney documents only that the Keychain copy is optional.
- The Keychain entry stays on this Mac and does not sync through iCloud.
- "Unlock automatically at application start" applies to the launch only. After a lock during the session, the app asks for Touch ID, the Apple Watch, or the password.
- The inactivity lock is off by default and suggests 5 minutes. Time that the Mac sleeps counts as inactivity.
- Locking hides every window that shows data. An open payment window keeps its entries and comes back after unlocking.
- While no database password is set, the lock command and the lock settings are disabled and point to "Set Database Password...".
- A locked app also stops automation and statement downloads, not only the refresh. MoneyMoney documents the refresh only.
- A change of the database password updates the Keychain entry.
