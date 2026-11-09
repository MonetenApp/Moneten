# MoneyMoney analysis

This page records how MoneyMoney 2.5.3 behaves and how that was found out. It is the evidence behind the specs in [openspec/changes](../../openspec/changes/). [MoneyMoney features](moneymoney-features.md) maps each feature to the change that specifies it.

The analysis ran on 9 November 2026 against MoneyMoney 2.5.3 (build 518) on macOS.

## Method

Four sources were used. Each statement on this page names its source with a letter.

| Letter | Source | What it shows |
|---|---|---|
| S | The text resources in the app bundle. These are 1,895 interface strings in English and German, 1,169 FinTS message strings, the default settings, the `Info.plist`, and the AppleScript dictionary. | Every label, message, and option that the app can show |
| U | The running app, read through the macOS Accessibility interface. Menus, context menus, views, and dialogs were opened and read. | The structure of the interface and which commands appear where |
| W | The MoneyMoney website. These are the feature page, help and FAQ, security, PSD2, the pages for categorization, templates, statements, the payee check, and two-factor authentication, and the API pages for web banking, import, export, and AppleScript. | The intended behavior in the developer's own words |
| C | The [version history](https://moneymoney.app/changelog/) from version 2.0.0 to 2.5.3. | When a behavior arrived and why |

The names of interface files in the bundle (source S) show which windows, sheets, and popovers exist. Names that the `strings` tool prints from the program file were used as hints only, for example for the list of account types.

### Limits

- macOS blocked screenshots, so colors, spacing, and the drawn content of charts were not observed.
- The dashboard draws its content without Accessibility elements. Its description rests on sources S and C.
- No bank was contacted. No refresh, payment, or TAN dialog was started. Behavior during a bank dialog rests on sources S, W, and C.
- Nothing was decrypted or decompiled. The built-in bank scripts of MoneyMoney are encrypted and were not read.
- Every dialog was closed with "Cancel". No setting and no data was changed.

### Privacy

The analysis ran against a database with real accounts. A filter replaced every value that is not a known interface string with placeholder characters before the value was stored or read. This page and the specs contain no account names, balances, counterparties, or file names from that database.

## Parts of the app

### Windows, sheets, and popovers (S)

| Kind | Elements |
|---|---|
| Windows | Main window, payment window, account settings, settings, log, account report and category report, categorization, export transactions, import transactions, split transaction, statement download settings, bar chart calibration, PIN change assistant, license, about, news, notification, OAuth browser, and one panel whose purpose was not found |
| Sheets | Add account assistant, unlock, set or change password, PIN entry, one-time password, SSL certificate check, bank merger |
| Popovers | Account properties, account error, category settings, default category settings, template group settings, securities properties, transaction properties, transaction comment, amount range, date range, menu bar popover |
| Views in the main window | Account, category, dashboard, outbox, scheduled payments, template group, portfolio, statements, lock screen |

### Main window (U)

The main window has a sidebar on the left and one content view on the right.

**Sidebar.** The rows from top to bottom are "Dashboard", the section "Accounts" with account groups and accounts, the section "Payments" with "Outbox", "Scheduled", and "Templates", the section "Documents" with "Statements", and the section "Categories" with category groups and categories. The last category is "Uncategorized". Sections can be collapsed. An account row shows the name and the balance. An account with a failed refresh shows the error text instead of the balance. A category row can show an amount. With the direct debit add-on, "Direct Debit Mandates" appears under "Payments" (S).

**Below the sidebar.** A menu button adds an account, an account group, a category, a category group, or a template group. A second button refreshes all accounts.

**Toolbar.** From left to right there is a lock button, a view switch with "Show list only", "Show bar chart", and "Show pie chart", a print menu, one action button that depends on the view, "Previous view" and "Next view", and the search field. The action button reads "Bank transfer" in account views, "Batch transfer" in the outbox, "Standing order" in the scheduled view, and "Add template" in the templates view.

**Filter bar.** The filter bar sits above the list. A pin button with the tooltip "Save filter bar" keeps the filters when the user changes the view. The filters depend on the view.

| View | Filters |
|---|---|
| Account or account group | Period, Status, Amount, Category. A single account adds a "Daily balance" switch. |
| Category | Period, Status, Amount, Account |
| Portfolio | Asset class |
| Outbox | View with "Drafts" and "Sent", Account |
| Scheduled | Kind with "All", "Scheduled Transfers", "Standing Orders", and "SRZ Orders", Account |
| Templates | Kind with "Transfer Templates", and with the add-on also direct debit mandates |
| Statements | Period, Status, Account |

The values of each filter are these.

| Filter | Values |
|---|---|
| Period | "Show All", "30 Days", "90 Days", "12 Months", the current month and the two months before it, the current quarter and the two quarters before it, the current year and the two years before it, "Custom..." |
| Status | "Show All", "Checked", "Unchecked". For statements "Read" and "Unread" (S). |
| Amount | "Show All", "Deposits", "Withdrawals", "Custom..." with a minimum and a maximum amount |
| Category, Account, Asset class | "Show All" and one entry for each category, account, or asset class |

**Status line.** The line under the list shows the number of rows and their sum, for example the number of transactions, of portfolio items with their total value, or of scheduled payments with their total. On the dashboard it shows the sum of all accounts and the time of the last refresh.

### Menus and keyboard shortcuts (U)

| Menu | Commands |
|---|---|
| MoneyMoney | About, "Check for Updates...", "Settings..." (⌘,), "License Key...", "Privacy Policy...", "License Agreement...", "Imprint...", "Lock MoneyMoney" (⌃⌘L), Quit (⌘Q) |
| File | "Refresh All Accounts" (⌘R), "Refresh Scheduled Payments", "Cancel Refresh", "Mark All Transactions as Checked", "Mark All Statements as Read", "Page Setup…" (⇧⌘P) |
| Edit | Undo, Redo, Cut, Copy, Paste, Delete, Select All, "Find in Transactions..." (⌘F) |
| View | "Back" (⌘[), "Forward" (⌘]), "List" (⌘1), "Bar Chart" (⌘2), "Pie Chart" (⌘3), "Daily Balance", "Checkmarks", "Enter Full Screen" |
| Payment | "New Bank Transfer..." (⌘N), "New Instant Payment...", "New Foreign Currency Transfer...", "New Standing Order...", "New Transfer Template...", "New Foreign Currency Transfer Template...", "Import Transfer Templates...", "Export Transfer Templates...", "New Batch Transfer from Outbox...", "New Batch Transfer from Template Group...", "New Batch Transfer from SEPA XML File...", "New Direct Debit Mandate...", "Import Direct Debit Mandates...", "Export Direct Debit Mandates...", "New Direct Debit...", "New Batch Direct Debit from Outbox...", "New Batch Direct Debit from Template Group...", "New Batch Direct Debit from SEPA XML File...", "Import Outbox...", "Export Outbox...", "Add Template Group", "Change Standing Order...", "Delete Standing Order..." |
| Account | "Add Account...", "Add Account Group", "Add Category", "Add Category Group", "Add Comment..." (⇧⌘K), a print command (⌘P), "Import Transactions...", "Export Transactions...", a remove command, a refresh command (⇧⌘R), "Edit Login Data...", "Look for New Accounts...", a settings command (⌘I) |
| Reporting | "Account Balance Report...", "Category Report..." |
| Tools | "Change PIN of Chipcard...", "Unblock Chipcard with PUK...", "Change Password of Keyfile...", "Change PIN of PIN/TAN Interface...", "Unblock PIN with TAN ...", "Transfer Transactions...", "Backup Database..." |
| Window | "Main Window" (⌘0), "Log Window" (⌘L), and the standard window commands |
| Help | "Show Database in Finder...", "Supported Banks (Germany)...", "Supported Banks (Europe)...", "Help and FAQ..." (⌘?), "Report an Issue...", "Encrypt File for Sending..." |

The Account menu follows the selection. Its print, remove, refresh, and settings commands take the name of the selected thing, for example "Print Portfolio Items...", "Remove Category...", "Refresh Account", or "Settings for Statements...". With the Option key, the refresh command becomes "Refresh Account (enforced)" (S, W). Two more shortcuts come from the version history (C). ⌘+ adds a transaction to an offline account, and ⌘N in the templates view sends the selected template.

### Context menus (U)

| Object | Commands |
|---|---|
| Account in the sidebar | "Add Account...", "Add Account Group", "Add Transaction...", "Print Transactions...", "Import Transactions...", "Export Transactions...", "Remove...", "Refresh Account", "Edit Login Data...", "Look for New Accounts...", "Settings..." |
| Account group in the sidebar | "Add Account...", "Add Account Group", "Print Transactions...", "Export Transactions...", "Remove...", "Refresh Accounts", "Settings..." |
| Portfolio group in the sidebar | The same, with "Print Portfolio Items..." and "Export Portfolio Positions..." |
| Category in the sidebar | "Add Category", "Add Category Group", "Print Transactions...", "Export Transactions...", "Remove...", "Settings..." |
| "Dashboard" | The add commands, "Print Accounts...", "Mark All Transactions as Checked" |
| "Outbox" | "New Batch Transfer...", "Print Outbox...", "Import Outbox...", "Export Outbox..." |
| "Scheduled" | "Refresh Scheduled Payments", "Print Scheduled Payments..." |
| "Templates" | "Add Transfer Template...", "Add Foreign Currency Transfer Template...", "Add Template Group", "New Batch Transfer...", "Print Templates...", "Import Transfer Templates...", "Export Transfer Templates...", "Remove...", "Settings..." |
| "Statements" | "Settings for Statements...", "Import Statements...", "Show in Finder...", "Mark All Statements as Read" |
| Transaction | "Search for" with the counterparty name, "Go to" with the account and the category, "Assign Category" with all categories and "Add category", "Split Transaction" with "Split Amount...", one entry for each VAT rate, "Split from Batch Payment", and "Undo Split Transaction...", "Create Offsetting Entry" with the offline accounts, "Add Comment...", "New from Selection" with "New Bank Transfer..." and "New Transfer Template...", "Add Transaction...", "Edit Transaction...", "Print Transaction...", "Export Transaction...", "Delete Transaction..." |
| Transaction in a category view | The same, with "Remove Transaction from Category" in place of the delete command |
| Portfolio item | "Assign Asset Class", "Add Comment...", "Edit Purchase Price...", "Print Portfolio Item...", "Export Portfolio Position..." |
| Standing order in the scheduled view | "Change Standing Order...", "New from Selection", "Print Standing Order...", "Delete Standing Order..." |

In "Assign Category", the current category has a checkmark. A category that is restricted to another account is disabled (U, C). Strings show more commands that depend on installed integrations and on the selection, for example "Send Transaction to" another app, "Use Transfer Template...", "Use Direct Debit Mandate...", "Open Statement...", and "Show in Finder" (S).

## Views

### Account and account group (U, W, C)

- The chart area has a switch between "Daily balance" and "Monthly average balance". A single account shows a "Refresh Account" button next to the date of the last refresh.
- The list shows one row for each transaction with the date, the amount, the counterparty, the purpose, the category, and more details from the structured purpose, for example the booking text, the end-to-end reference, the mandate reference, and the creditor ID.
- Pending transactions are hatched. The balance in the upper right corner comes from the bank and is not computed from the list.
- A transaction can carry a checkmark and a comment. A transaction with a comment shows a yellow icon.
- A group view can group its transactions by account.

### Category (U, W)

- The chart area has a switch between "Monthly view", "Quarterly view", and "Yearly view".
- The pie chart shows the categories of the selected group.
- The category settings popover has the fields "Name", "Currency", a color control, "Show in diagrams", "Display in sidebar" with "No amount", "Current month", "Current quarter", "Current year", and "Total sum", a budget with an amount and a period of "per month", "per quarter", "per year", or "in total", "Rules for automatic categorization" as one text field, "Restrict to" with an account, and a help button.

### Portfolio (U, S, C)

- The chart area has the balance switch and a menu that selects what the chart shows.
- Each row shows the name of the security, the value, the quantity, the purchase price, the last quote, and the profit or loss as an amount and as a percentage.
- The asset classes are "Stocks", "Funds", "Bonds", "Real estate", "Commodities", "ETFs", "Cryptocurrencies", and "Others".
- The app records the portfolio value once a day and draws a history from these records.

### Payments (U, S, W)

- **Outbox.** "Drafts" holds payments that were saved and not sent. "Sent" holds every order that was transmitted, with the time, the execution date, the TAN method, and also change and delete orders.
- **Scheduled.** The list holds scheduled transfers, standing orders, direct debits that the bank has not yet executed, and SRZ orders. A button "Refresh Scheduled Payments" fetches the list from the bank.
- **Templates.** The list holds transfer templates and, with the add-on, direct debit mandates. Template groups appear below "Templates" in the sidebar.

### Statements (U, S, W)

The view shows a grid of PDF statements, grouped under headings. A button "Settings for Statements" opens the download settings. The download runs at the beginning of the month, on a fixed day, every two weeks, or only on request. Files are stored without encryption in the "Statements" folder.

### Dashboard (S, C)

The dashboard is the first row of the sidebar. It shows one item for each account with its balance and its newest transactions, and it marks pending transactions. Closed accounts do not appear. Longer lists end with a line such as "3 more new transactions...". The status line shows the total of all accounts.

## Dialogs

### Add account (U, W)

The assistant is a sheet with three steps. The first step asks for an "IBAN or Bankleitzahl", or for a choice from "Other". "Other" lists credit card services, "More credit cards...", services that installed extensions provide, and "Offline account / Cash". A country menu sits at the lower left. The second step asks for the login data. The third step lists the accounts to add.

### Account settings (U, S)

The window has the tabs "Account", "Account owner", and "Notes".

- **Account.** Name and icon, "Account type" with "Giro account", "Savings account", "Fixed term deposit", "Loan account", "Credit card", and "Other", "Initial balance" with "Calibrate", the IBAN, the BIC, "Bank name", "Refresh" with "every two hours", "four times a day", "once a day", "once a week", "only manually", and "never", "Remove saved PIN", and "The account has been closed".
- **Account owner.** The name and address of the owner and, for direct debits, the creditor ID.
- **Notes.** Free text and a table of user-defined fields.

### Payment window (U, S, W)

- "From" selects the source account.
- "Action" selects "New bank transfer", "New instant payment", "New foreign currency transfer", "New standing order", one "Transfer to" entry for each own account, "Insert from Pasteboard", and the recently used recipients.
- The fields are "Recipient", IBAN, BIC, "Amount", and "Purpose".
- "Schedule" selects "Now" or "Set date".
- "Confirm using" selects the TAN method.
- A gear menu offers "Save in outbox", "Deduce cash discount", "Set end-to-end reference", "Set purpose code", and "Also save as template". Strings add "Set address", "Set country of bank", and "Set instructions for bank" for other payment kinds.
- The button "Next" stays disabled until the entries are valid.

### Reports (U, S, C)

Both reports use one window with a list of accounts or categories, "Select all" and "Select none", a "Title", "Create as" with "Printout", "PDF file", and "CSV file", and the buttons "Save", "Preview", and "Cancel". The other options differ.

| Report | Options |
|---|---|
| Account balance report | "Amounts" with "Current balance" or "Daily balance from" a date. "Compare with" the "Daily balance from" a second date, and "With absolute and relative change". "Additional information" with "Bank details", "Account owner", and "Today's date". |
| Category report | "Period" with a start and an end date. "Compare with period", and "With absolute and relative change". "Additional information" with "Total sum" and "Today's date". The report can be restricted to an account or account group, and it can hide categories with a sum of zero. |

### Settings (U)

| Tab | Settings |
|---|---|
| General | "Show notification about new versions", "Show MoneyMoney icon in menu bar", "Automatically refresh accounts", "Show banner notification on new transactions", "Play sound on new transactions", "Participate in beta tests and display pre-release versions", "Language" |
| Security | "Change Database Password...", "Lock when main window is closed", "Lock after" a number of "minutes of inactivity", "Unlock automatically at application start", "Unlock with Touch ID", "Unlock with Apple Watch" |
| Payments | "Send templates with double click by default", "Save new payments in outbox by default", "Enable Secoder visualization" |
| PSD2 | The state of the PSD2 online service, with links to its terms and its supported banks |
| Extensions | The paid direct debit add-on, the installed extensions with their version, "Verify digital signatures of extensions", "Restore Purchases" |

## Interfaces to other programs

### AppleScript (S, W)

The dictionary has ten commands.

| Command | Purpose |
|---|---|
| `export accounts`, `export categories` | Return a property list |
| `export transactions` | Parameters for the account, the category, a start and an end date, and the format `csv`, `ofx`, `sta`, `xls`, `numbers`, `camt.053`, `plist`, or the name of an export extension |
| `export portfolio` | Parameters for the account and the asset class. Returns a property list. |
| `create bank transfer`, `create direct debit` | Open a payment window with the given data, or save the payment to the outbox with `into "outbox"` |
| `create batch transfer`, `create batch direct debit` | Open a SEPA XML file |
| `add transaction` | Adds a transaction to an offline account |
| `set transaction` | Sets the checkmark, the category, or the comment of a transaction |

### URL schemes and file types (S)

- The app handles the URL schemes `bank`, `payto`, `moneymoney-app` for OAuth redirects, and `psd2-onlinedienst`.
- The app opens SEPA XML files with the extension `.pain` or `.xml`, also when they are dropped on the Dock icon (C).
- The bundle contains XML schemas for SEPA credit transfers `pain.001` and direct debits `pain.008` in several versions, and for SEPA container files.

### Lua extensions (W)

Three kinds of extension exist. A web banking extension fetches accounts, balances, transactions, and securities. An import extension reads a file format. An export extension writes one. Extensions live in the "Extensions" folder next to the database. The app checks a digital signature and runs an unsigned extension only after the user turns the check off.

### File formats (S, W, C)

| Direction | Formats |
|---|---|
| Import transactions | CSV, QIF, OFX, QFX, MT940, camt.052, camt.053, tab-separated text |
| Export transactions | CSV, OFX 1.6, MT940, camt.053.001.08, Excel `.xlsx`, Numbers, property list |
| Import and export templates and mandates | CSV, SEPA XML |
| Import and export the outbox | SEPA XML |
| Export portfolio positions | CSV |
| Statements | PDF. The app creates a PDF from an MT940 or a text statement. |

### Network (S, W)

The app connects to the bank servers directly. It also asks the developer's service for updates and for current bank server settings, and it sends no personal data in these requests. Only the PSD2 online service passes account data through a server of the developer.

## Not carried over

MonetenMoneten does not copy these parts of MoneyMoney.

| Part of MoneyMoney | Why it has no spec |
|---|---|
| License keys, the trial period, in-app purchases, and the Mac App Store edition | MonetenMoneten is free software ([ADR 0006](../decisions/0006-license-gpl-3.md)) |
| The PSD2 online service of MRH applications GmbH | The optional finAPI subscription takes its place ([ADR 0007](../decisions/0007-optional-finapi-subscription.md)) |
| "Encrypt File for Sending" for the vendor's support | The spec for the log window defines a redacted export for public bug reports instead |
| Built-in, encrypted bank scripts that the vendor updates from its server | Banks without FinTS come through open extensions and the signed catalog |
| Name, icons, artwork, and sounds | These belong to MRH applications GmbH |

## Open points

- The exact content of a dashboard item was not observed.
- One panel in the bundle is named after Spotlight, and one string reads "Search Account". No menu command opens it. It has no spec.
- The strings "Clearing entry for daily balance", "Copy to Pasteboard", and "Copy position to pasteboard" could not be tied to a place in the interface.
- The key derivation and the behavior without a database password were not observed. [ADR 0009](../decisions/0009-database-password-as-in-moneymoney.md) records what MonetenMoneten does.
- Messages during a bank dialog are known as text only. Their order and timing come from FinTS itself.
