# Proposal: Run web banking extensions that are compatible with MoneyMoney

## Why

Many services have no FinTS access, for example brokers, credit card portals, and crypto exchanges. The core team cannot maintain a connection to each of them. A community can, if writing an extension is open to everyone. More than a hundred extensions already exist for the MoneyMoney Web Banking API, and users who switch want to keep the ones they use.

## What Changes

- The app runs Lua 5.4 scripts that register with `WebBanking{}`.
- The app implements the whole documented Web Banking API. That is the entry points, the data structures, the two-factor challenge tables, the objects `Connection`, `HTML`, `JSON`, `PDF`, and `LocalStorage`, and all `MM` functions.
- A `.lua` file in the "Extensions" folder is installed. The settings list the installed extensions.
- Services of an extension appear under "Other" in the add account assistant.
- Each extension runs isolated. It reaches the network and nothing else.
- The app warns before it first runs an extension that does not come from the catalog.
- An optional manifest next to the script lists the hosts the extension contacts and the labels of its login fields.
- The API has no payment functions.

## Capabilities

### New Capabilities

- `web-banking-extensions`: installing, isolating, and running Lua web banking extensions, and the complete API that the app offers to them.

### Modified Capabilities

None.

## Impact

- Milestone: v0.1
- Issues: #14, #15
- Modules: `ExtensionHost` owns the Lua runtime and the API. `ExtensionConnector` starts the host and maps results to `Domain` types. `Storage` keeps `LocalStorage`. `App` owns the settings list, the warning, and the challenge dialogs.
- Depends on the change `add-account-setup` for the assistant, on `add-login-credentials` for storing the login data, on `add-tan-handling` for the dialogs that show a challenge, and on `add-account-refresh` for de-duplication and for when a refresh runs.
- `FetchStatements` delivers documents to the capability `bank-statements`. The app starts to call it when the change `add-bank-statements` is built.
- The signature check and the catalog are in the change `add-extension-catalog`. The command line tool is in the change `add-extension-developer-tools`.
- Decisions: [ADR 0004](../../../docs/decisions/0004-moneymoney-compatible-extension-api.md), [ADR 0008](../../../docs/decisions/0008-payments-only-through-licensed-channels.md), [ADR 0002](../../../docs/decisions/0002-local-first-no-server.md).

## Reference behavior

### Observed in MoneyMoney 2.5.3

- The whole API is documented on the [Web Banking API page](https://moneymoney.app/api/webbanking/). The spec follows that page section by section.
- Extensions live in the "Extensions" folder next to the database. A changed file takes effect without a restart. See [analysis](../../../docs/research/moneymoney-analysis.md#lua-extensions-w).
- The settings tab "Extensions" lists each installed extension with its description and version. See [analysis](../../../docs/research/moneymoney-analysis.md#settings-u).
- The assistant lists the services of extensions under "Other". See [analysis](../../../docs/research/moneymoney-analysis.md#add-account-u-w).
- The login dialog has a user name field, a password field, and up to two more fields. The defaults are "Username" and "Password".
- `LoginFailed` stops the automatic refresh of the affected accounts until the user enters the login data again.
- Output of `print` goes to the log window. `error` stops the script.
- The extension page lists community extensions that return balances, transactions, securities, and quotes ([extensions page](https://moneymoney.app/extensions/)).
- Lua 5.4 is the script language (version history, 2.4.57).

### Decided for Moneten

- The app warns before it first runs an extension that is not from the catalog, and again when the file changes. MoneyMoney instead refuses unsigned extensions until the user turns the signature check off. The signature check arrives with the catalog in v0.3.
- A manifest is optional and is an addition of Moneten ([ADR 0004](../../../docs/decisions/0004-moneymoney-compatible-extension-api.md)). With a manifest, the extension reaches only the listed hosts. Without one, the app asks the user to allow each host at first contact. MoneyMoney does not limit hosts at run time.
- The labels of the login fields come from the manifest. MoneyMoney keeps them in a central bank database.
- A browser approval works for a host that the manifest lists or the user allowed. MoneyMoney needs the host to be enabled by the vendor.
- The app refuses a URL that does not start with `https://`.
- Each extension runs in its own process that is stopped after the session. The Lua functions for files, processes, and loading code are removed. MoneyMoney forbids them only in its review checklist.
- `MM.productName` is "Moneten". `MM.APPSTORE` is always `nil`. `MM.apiVersion` is new.
- `session` never has the value `"payment"`, and the API has no way to send a payment ([ADR 0008](../../../docs/decisions/0008-payments-only-through-licensed-channels.md)).
- When a script defines both login functions, the app calls `InitializeSession2`. The documentation calls it an alternative and does not state the order.
- A challenge during an automatic refresh shows no dialog. The app marks the access and waits for a refresh that the user starts. MoneyMoney's behavior in this case was not observed.
- `LocalStorage` is kept in the encrypted database.
- The settings can remove an extension. The file moves to the Trash. MoneyMoney only lists the installed extensions.
- An extension can ask for a newer API version in its manifest. The app then refuses to load it and says why.
- `EndSession` is called also when a step after the login fails. The documentation does not state this.
