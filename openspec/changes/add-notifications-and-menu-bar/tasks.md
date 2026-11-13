# Tasks

One task per requirement of the spec. A task is checked only when a test or a check in the running app shows the behavior. The issue in brackets builds it.

## 1. Requirements

- [x] 1.1 One notification for a refresh with new transactions. Verified by NewTransactionsNoticeTests "New transactions in two accounts make one notice...", AutoRefreshTests "The run ends once, after the last of several accesses...", "New transactions of a run make one notification...", and "An automatic refresh of three accesses makes one notification...", and the debug app check of issue #40, which delivered one notification for each run (#40).
- [x] 1.2 Notify only about stored transactions. Verified by NewTransactionsNoticeTests "Only rows that are still stored and still new count" and AutoRefreshTests "An automatic refresh of three accesses...", whose second run delivers the same rows and makes no notification (#40).
- [x] 1.3 Notifications reveal no transaction details. Verified by NewTransactionsNoticeTests "One new transaction names its account and nothing of the transaction" and "While the app is locked the notice has the count and no account name" (#40).
- [ ] 1.4 Open the account from a notification. Built: a click brings the main window to the front with the first of the accounts in the order of the sidebar, after the unlock when the app is locked. Open: not clicked in the app, and the dashboard comes with add-dashboard (#40).
- [ ] 1.5 Remove notifications that are out of date. Built. Open: not checked in the app (#40).
- [ ] 1.6 Sound on new transactions. Built, and AutoRefreshTests "New transactions of a run make one notification, with the sound only when the setting is on" and NewTransactionsNoticeTests "The sound follows the sum..." verify the choice. Open: the sound was not heard in the app (#40).
- [ ] 1.7 Respect Focus. Built for the banner, whose sound is part of the notification. Open: the sound without a banner ignores a Focus, see "Decided for Moneten" (#40).
- [ ] 1.8 Dock badge with the number of new transactions. Built. Open: the debug app check had no permission, so no badge showed (#40).
- [ ] 1.9 Ask for permission and explain a refusal. Built: the app asks when the user turns on the banner or the sound or when the first notification is due. The debug app check showed the note and the button to the System Settings while macOS denied the permission. Open: the note was not seen to go after a later permission (#40).
- [ ] 1.10 Notification about new statements. Comes with add-bank-statements.
- [ ] 1.11 Menu bar icon. Built: the debug app check found the item in the menu bar with the setting on. Open: turning the setting on and off was not checked (#40).
- [x] 1.12 Menu bar popover. Verified by the debug app check of issue #40: the popover lists the open accounts in the order of the sidebar with balance and count of new transactions, and marks the two accounts whose access waits for a TAN (#40).
- [ ] 1.13 Actions in the popover. Built. Open: not clicked in the app (#40).
- [ ] 1.14 Menu bar icon shows the state. Built. Open: not checked in the app (#40).
- [ ] 1.15 The popover respects the lock. Built. Open: not checked in the app (#40).
- [ ] 1.16 Keep working with the main window closed. Built: the app does not quit with its last window, and the automatic refresh does not depend on a window. Open: not checked with the window closed (#40).
