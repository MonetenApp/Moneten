# Proposal: Automate exports and payment entry with AppleScript

## Why

Accounting apps, budget tools, and users' own scripts read transactions from MoneyMoney through AppleScript and hand payment data to it. A user who switches loses these workflows unless the same commands exist. With the same command names, a script works after one change, the name of the application.

## What Changes

- The app gets a scripting dictionary with ten commands.
- Four commands export accounts, categories, transactions, and portfolio positions.
- Four commands hand over payment data. They open a payment window or save a draft. They never send a payment.
- One command adds a transaction to an offline account. One command sets the checkmark, the category, or the comment of a transaction.
- A setting turns automation off.

## Capabilities

### New Capabilities

- `applescript-automation`: the scripting commands, their parameters, their results, and their errors.

### Modified Capabilities

None.

## Impact

- Milestone: later
- Issues: none yet
- Modules: `App` owns the scripting dictionary and the command handlers. The handlers call the same code as the menu commands.
- Depends on the changes `add-data-export` and `add-more-export-formats` for the file formats, `add-sepa-transfers`, `add-payment-outbox`, and `add-direct-debits` for the payment commands, `add-securities-accounts` for the portfolio export, `add-offline-accounts`, `add-categories`, and `add-transaction-list` for the editing commands, and `add-app-lock` for the behavior while the database is locked.
- A command whose capability is not built yet answers with an error that says so.
- Decisions: [ADR 0008](../../../docs/decisions/0008-payments-only-through-licensed-channels.md).

## Reference behavior

### Observed in MoneyMoney 2.5.3

- The scripting dictionary in the app bundle defines the ten commands with all parameters and their descriptions. See [analysis](../../../docs/research/moneymoney-analysis.md#applescript-s-w).
- The [AppleScript page](https://moneymoney.app/api/applescript/) shows one example for each command.
- `export transactions` returns the path of a temporary file that stays valid until the next restart. With the format `plist` it returns an XML property list.
- The property list of transactions has an array `transactions`. The example on the page reads the keys `booked`, `bookingDate`, `name`, `amount`, and `currency`.
- A transaction has a numeric ID and a category has a UUID. Both come from the property list exports and are the input of `set transaction`.
- Payment commands open a filled window. With `into "outbox"` they save the payment silently to the outbox.
- `add transaction` without a category applies the categorization rules.
- Nested category names are separated with a backslash.
- Categories can be assigned through AppleScript as an alternative to rules (version history, 2.4.49). Checkmarks and comments can be set (version history, 2.3.10). Instant payments and B2B direct debits are supported (version history, 2.4.13).

### Decided for MonetenMoneten

- The keys of the property lists, beyond the five that the page shows, are not documented. The spec uses the field names of the Export API and adds `id`, `accountUuid`, `categoryUuid`, and the top-level key `creator`. Compare these keys with a real export from MoneyMoney before the design starts.
- The keys of the account list, the category list, and the portfolio list are defined here and need the same comparison.
- The order of the lookup for the account parameter is UUID, IBAN, account number, account name, group name. A name that fits several accounts is an error.
- Error messages and the cases in which a command fails are defined here. The website does not describe them.
- A visible setting "Allow automation with AppleScript" turns all commands off. It is on by default. MoneyMoney has only a hidden switch.
- No command sends a payment, also not with `into "outbox"`. This matches the observed behavior and is fixed here as a rule.
- The application name in scripts is "MonetenMoneten".
