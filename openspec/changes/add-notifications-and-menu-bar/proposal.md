# Proposal: Notify about new transactions and offer a menu bar icon

## Why

Users should see that money arrived or left without opening the app and pressing refresh. A notification tells them when it happens, and a menu bar icon keeps the balances one click away while the main window is closed.

## What Changes

- After a refresh with new transactions the app shows one macOS notification with the number of new transactions.
- An optional sound plays with it.
- The Dock icon shows the number of new transactions as a badge.
- An optional menu bar icon opens a popover with the accounts, their balances, and their new transactions, and it can refresh and open the main window.
- The same notification channel announces new PDF statements once the app downloads statements.
- Three settings on the "General" tab control this. They are "Show banner notification on new transactions", "Play sound on new transactions", and "Show Moneten icon in menu bar".

## Capabilities

### New Capabilities

- `notifications-and-menu-bar`: notifications, the sound, the Dock badge, and the menu bar icon with its popover.

### Modified Capabilities

None.

## Impact

- Milestone: v0.1
- Issues: #40
- Modules: `App` owns notifications, the Dock badge, and the menu bar item. `Domain` provides the result of a refresh run with the new transactions for each account.
- Depends on the change `add-account-refresh` for the refresh run, its result, and the new state of a transaction, `add-app-lock` for the locked state, `add-app-settings` for the "General" tab, `add-main-window` for the main window that the menu bar item opens, and later `add-bank-statements` for new statements and `add-dashboard` as the target of a notification for several accounts.
- Decisions: [ADR 0002](../../../docs/decisions/0002-local-first-no-server.md). Notifications are local. The app uses no push service.

## Reference behavior

### Observed in MoneyMoney 2.5.3

- The "General" tab of the settings has "Show MoneyMoney icon in menu bar", "Show banner notification on new transactions", and "Play sound on new transactions". See [analysis](../../../docs/research/moneymoney-analysis.md#settings-u).
- Strings show the texts "1 new transaction" and one for several new transactions, "1 new bank statement" and one for several, and a text that a number of new PDF statements have been downloaded.
- The bundle contains a popover for the menu bar item and a list of items in it. The bundle contains four sounds with the names positive, negative, neutral, and sent. See [analysis](../../../docs/research/moneymoney-analysis.md#windows-sheets-and-popovers-s).
- Notifications appear in the Notification Center of macOS (version history, 2.0.24).
- A notification must not appear for a transaction that was not stored (version history, 2.1.4).
- While the main window is locked, no accounts are fetched in the background (version history, 2.4.49).

### Decided for Moneten

- One notification for each refresh run, not one for each account. Issue #40 asks for exactly one notification for each refresh. The notification lists the accounts in its text.
- A notification never contains an amount, a counterparty, or a purpose. While the app is locked it also leaves out account names. MoneyMoney's notification text beyond the count was not observed.
- A click on a notification opens the account, or the dashboard when several accounts have new transactions. Not observed.
- The sound has three variants for a net deposit, a net withdrawal, and a balanced result. This is inferred from the names of the sound files. Moneten ships its own sounds.
- The Dock badge has no setting in the app. The macOS notification settings turn it off. In MoneyMoney the badge is controlled by a hidden preference.
- The content and the actions of the menu bar popover are defined here. Only its existence was observed.
- The banner is on by default. The sound and the menu bar icon are off by default. The default settings file of MoneyMoney turns the current menu bar key off and lists no default for the banner and the sound.
- When macOS denies notifications, the settings say where to allow them. Not observed.
- A notification about new transactions is removed when the user has seen the transactions. It goes once none of the accounts it names has a new transaction left.
- The notification separates the account names with commas. While the app is locked its text has only the count.
- The banner also appears while Moneten is the active app. Not observed.
- The app asks macOS for the permission when the user turns on the banner or the sound, or when the first notification is due. It never asks at the launch.
- With the banner off and the sound on, the app plays the sound without a notification, and a Focus does not silence it, because macOS tells an app about a Focus only with an entitlement for communication apps. With the banner on, the sound is part of the notification, and a Focus silences both.
- The Dock badge uses the notification permission of macOS. Without the permission no badge appears. The lock removes the badge until the next unlock.
- The menu bar icon shows one state at a time: a running refresh first, then an account that needs attention, then new transactions. Locked, it shows the plain icon.
- In the popover an account that waits for the user carries an orange mark, and one whose refresh failed for another reason a red one. The text of the error shows as help.
- When a refresh from the popover needs the PIN or a TAN while the main window is closed, the main window opens with the dialog, because the dialogs belong to it. Not observed.
- The three sounds are short bell tones that `scripts/make-sounds.py` writes: two rising notes, two falling notes, and one note.
