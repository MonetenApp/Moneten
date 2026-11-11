# Proposal: Give extension authors a command line tool and a guide

## Why

An author who must click through the app after every change to a script gives up early. Extensions also break when a website changes, and without recorded traffic nobody can test a fix without a real login. A tool that runs, records, and replays an extension outside the app makes extensions cheap to write and safe to change.

## What Changes

- A command line tool named `ext` runs a web banking extension without the app.
- `ext run` asks for login data and TANs in the terminal and prints accounts and transactions as JSON.
- `ext record` saves the HTTP traffic of a run to a fixture file and removes secrets from it.
- `ext test` replays a fixture without network access and compares the result with an expected file.
- The tool returns an exit status that scripts and CI can check.
- The project publishes an author guide with a tutorial, an API reference, and the rules for extensions.

## Capabilities

### New Capabilities

- `extension-developer-tools`: the `ext` command line tool with run, record, and replay, and the author guide.

### Modified Capabilities

None.

## Impact

- Milestone: v0.1
- Issues: #16, #17
- Modules: `ext` in `Tools/ext` owns the commands. It uses `ExtensionHost` so that the API behaves exactly as in the app. Example extensions and their fixtures live in `Extensions/` and `Fixtures/`.
- Depends on the change `add-web-banking-extensions`.
- Decisions: [ADR 0004](../../../docs/decisions/0004-moneymoney-compatible-extension-api.md).

## Reference behavior

### Observed in MoneyMoney 2.5.3

- MoneyMoney has no tool of this kind. An author copies the script into the "Extensions" folder, sets up an account in the app, and reads errors in the log window ([Web Banking API page](https://moneymoney.app/api/webbanking/)).
- The API page gives two tips for authors. `ListAccounts` can return fixed data during development, and HTML pages saved from a browser can be loaded in place of a live connection.

### Decided for Moneten

- The whole capability is new. Its scope comes from the issues #16 and #17.
- Requirements in this capability name the `ext` tool or the project as the actor, because the behavior is not part of the app.
- The names of the commands and options, the JSON output, and the fixture format are defined here for the first time.
- A recording replaces secrets with placeholders before it is written. No option turns that off.
- A replay fixes the clock and the random values, so that a test gives the same result on every run.
- The tool keeps `LocalStorage` in a file next to the script and never touches the database of the app.
