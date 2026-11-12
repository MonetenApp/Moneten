# Proposal: Run web banking extensions that are compatible with MoneyMoney

## Why

Many services have no FinTS access, for example brokers, credit card portals, and crypto exchanges. The core team cannot maintain a connection to each of them. A community can, if writing an extension is open to everyone. More than a hundred extensions already exist for the MoneyMoney Web Banking API, and users who switch want to keep the ones they use.

## What Changes

- The app runs Lua 5.4 scripts that register with `WebBanking{}`.
- The app implements the whole documented Web Banking API. That is the entry points, the data structures, the two-factor challenge tables, the objects `Connection`, `HTML`, `JSON`, `PDF`, and `LocalStorage`, and all `MM` functions.
- A `.lua` file or a package folder in the "Extensions" folder is installed. A package holds a manifest, one or more Lua files, and a README, and is installed, updated, and removed as one unit.
- The window that the menu item "Extensions" opens lists the installed extensions and removes them.
- Services of an extension appear under "Other" in the add account assistant.
- Each extension runs isolated. It reaches the network and nothing else.
- An extension installed from a file runs after a warning and stays marked "Unverified".
- A manifest lists the Lua files, the hosts, the labels of the login fields, the kinds of data, and the API version. An extension with a manifest reaches only its hosts. Without one, the app asks before each new host.
- `io` is a table without file functions, so a script that tests for `io.open` still loads.
- The browser window for logins ends at three redirect addresses and never contacts them.
- The app offers the undocumented names that published extensions use. Any other unknown name stops the script with an error that names it.
- The API has no payment functions.

## Capabilities

### New Capabilities

- `web-banking-extensions`: installing, isolating, and running Lua web banking extensions, and the complete API that the app offers to them.

### Modified Capabilities

None.

## Impact

- Milestone: v0.1
- Issues: #14, #15, #42
- Modules: `ExtensionHost` owns the Lua runtime and the API. `ExtensionConnector` starts the host and maps results to `Domain` types. `Storage` keeps `LocalStorage`. `App` owns the "Extensions" window, the warning, and the challenge dialogs.
- Depends on the change `add-account-setup` for the assistant, on `add-login-credentials` for storing the login data, on `add-tan-handling` for the dialogs that show a challenge, and on `add-account-refresh` for de-duplication and for when a refresh runs.
- `FetchStatements` delivers documents to the capability `bank-statements`. The app starts to call it when the change `add-bank-statements` is built.
- The catalog is in the change `add-extension-catalog`. The command line tool is in the change `add-extension-developer-tools`.
- Decisions: [ADR 0004](../../../docs/decisions/0004-moneymoney-compatible-extension-api.md), [ADR 0015](../../../docs/decisions/0015-extension-program.md), [ADR 0008](../../../docs/decisions/0008-payments-only-through-licensed-channels.md), [ADR 0002](../../../docs/decisions/0002-local-first-no-server.md).

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

- Files from outside the catalog run after a warning, at the install and again when the file changes, and stay marked "Unverified". MoneyMoney refuses unsigned files until the user turns its signature check off ([ADR 0015](../../../docs/decisions/0015-extension-program.md)).
- A manifest is an addition of Moneten. It is optional for an extension installed from a file and required in the catalog ([ADR 0015](../../../docs/decisions/0015-extension-program.md)). With a manifest, the extension reaches only the listed hosts, by exact name and also after a redirect. Without one, the app asks the user to allow each host at first contact. The documentation of MoneyMoney states no host limit for requests of `Connection`.
- The labels of the login fields come from the manifest. MoneyMoney keeps them in a central bank database.
- A browser approval works for a host that the manifest lists or the user allowed. MoneyMoney needs the host to be enabled by the vendor.
- The app refuses a URL that does not start with `https://`.
- Each extension runs in its own process that is stopped after the session. `io` has no file functions in every mode, and the functions for processes and for loading code are absent. MoneyMoney forbids them in its review checklist and appears to keep `io.open` for unsigned files. Signed MoneyMoney extensions test for `io.open` or read it at load time, and they load in Moneten.
- `MM.productName` is "Moneten". `MM.APPSTORE` is always `nil`. `MM.apiVersion` is new.
- `session` never has the value `"payment"`, and the API has no way to send a payment ([ADR 0008](../../../docs/decisions/0008-payments-only-through-licensed-channels.md)).
- When a script defines both login functions, the app calls `InitializeSession2`. The documentation calls it an alternative and does not state the order.
- A challenge during an automatic refresh shows no dialog. The app marks the access and waits for a refresh that the user starts. MoneyMoney's behavior in this case was not observed.
- `LocalStorage` is kept in the encrypted database.
- The "Extensions" window lists the installed extensions and removes one to the Trash. MoneyMoney lists them in a settings tab and has no command to remove one.
- An extension can be a package of several Lua files with a manifest and a README. Every MoneyMoney extension is a single `.lua` file, and that form stays allowed.
- The browser window treats `https://service.moneymoney-app.com/1/redirect`, `moneymoney-app://oauth`, and `moneten://oauth` as final and never contacts them. The documentation names no address. Published extensions use the first two.
- The app reads `code`, `access_token`, `auth_code`, `tokenid`, or a similar parameter from the final address, as the documentation allows.
- `connection:get` and `connection:post` return the same five values as `connection:request`. The documentation lists three. A signed extension reads the fifth.
- The app offers `MM.derdecode`, `MM.base64urldecode`, and `connection.redirects`, which signed extensions use and the documentation does not list. A call of any other name that the app does not offer stops the script with an error that names it. MoneyMoney's behavior for an unknown name was not observed.
- An extension can ask for a newer API version in its manifest. The app then refuses to load it and says why.
- `EndSession` is called also when a step after the login fails. The documentation does not state this.
