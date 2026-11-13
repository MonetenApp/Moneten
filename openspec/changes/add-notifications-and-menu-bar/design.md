# Design

## Context

Issue #40 builds the automatic refresh of add-account-refresh and this change together. The design of add-account-refresh describes the schedule. This design covers what the app tells the user after a refresh.

## Decisions

### A run, not an access, makes the notification

`SyncCoordinator` calls `runEnded` when the last refresh of a run ended. A run starts with the first refresh while none runs, and every refresh that starts before its end joins it, also a manual one beside an automatic one. `NewTransactionsAnnouncer` in `Sync` collects the rows that each merge stored (`Reconciliation.added`) and turns them into one `NewTransactionsNotice` at the end of the run, so three accesses with new transactions make one notification.

### The notice is a pure value

`NewTransactionsNotice` in `Domain` counts only the rows that are still stored and still new in the ledger at the end of the run. It names the accounts in the order of the sidebar and holds no amount, counterparty, purpose, or balance. While the app is locked it gets no ledger and names no account. Its tone follows the sum of the rows in each currency: positive, negative, or neutral when the sums are zero or have opposite signs.

### Settings live in UserDefaults

`RefreshSettings` reads "Automatically refresh accounts", "Show banner notification on new transactions", and "Play sound on new transactions" from the `UserDefaults` that the app passes, and registers their defaults. The tests pass a suite of their own and delete it afterwards. "Show Moneten icon in menu bar" is read only by the app.

### The app talks to macOS

`Notices` in the app implements `NoticeCenter` with `UNUserNotificationCenter`: it asks for the permission, adds the notification with the sound of its tone, sets the Dock badge to the number of new transactions, removes a notification once its accounts have no new transaction left, and opens the account of a clicked notification. The menu bar item is a `MenuBarExtra` whose presence follows the setting.

## Risks / Trade-offs

- A Focus silences the sound only when the banner is on, see "Decided for Moneten".
- The notification about new statements waits for add-bank-statements, and the dashboard as the target of a click waits for add-dashboard.
