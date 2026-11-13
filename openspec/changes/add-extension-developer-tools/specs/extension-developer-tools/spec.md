# Spec Delta

## Purpose

Authors of extensions need to run and test a script without the app and without a real login on every change. This capability defines the `ext` command line tool, which runs an extension, records its HTTP traffic, and replays a recording as a test, and the author guide that the project publishes.

## ADDED Requirements

### Requirement: Run an extension outside the app

The `ext` tool SHALL run a web banking extension with the command `ext run <script>` and offer the script the same API with the same behavior as the app. The tool goes through the same order of entry points as the app does for a new bank access.

#### Scenario: Run the template

- **GIVEN** `Demo.lua` registers the service "Premium Account" and returns one account with one transaction
- **WHEN** the author runs `ext run Demo.lua`
- **THEN** the tool calls `SupportsBank`, the login function, `ListAccounts`, `RefreshAccount`, and `EndSession`
- **AND** the tool prints the account and the transaction

#### Scenario: Script with several services

- **GIVEN** a script with `services = {"Broker", "Broker Business"}`
- **WHEN** the author runs `ext run Broker.lua` without the option `--service`
- **THEN** the tool lists both services and asks which one to use

### Requirement: Login data in the terminal

The `ext` tool SHALL ask for the login data in the terminal with the field labels from the manifest, or with "Username" and "Password" when there is no manifest. The tool does not show a password while the author types it, and it does not write login data to any file.

#### Scenario: Hidden password

- **WHEN** the author runs `ext run Demo.lua` and types the password
- **THEN** the terminal shows no characters for the password

#### Scenario: Login data from the environment

- **GIVEN** the environment variables `EXT_USERNAME` and `EXT_PASSWORD` are set
- **WHEN** the author runs `ext run Demo.lua`
- **THEN** the tool does not ask and uses these values

### Requirement: Challenges in the terminal

The `ext` tool SHALL handle every kind of challenge table in the terminal. It prints the title and the text, asks for an entry when the challenge has a `label`, offers a numbered list for `tanMethods`, saves an image to a temporary file and prints its path, prints a URL for a browser approval and waits for the redirect, and repeats the call for a decoupled challenge until the script returns.

#### Scenario: TAN entry

- **WHEN** the login function returns `{title="Enter the code from the SMS.", label="Code"}`
- **THEN** the tool prints the title and the prompt "Code" and passes the typed text in `credentials[1]`

#### Scenario: Choice of method

- **WHEN** the function returns `tanMethods` with "pushTAN" and "mobileTAN"
- **THEN** the tool prints "1 pushTAN" and "2 mobileTAN" and asks for a number

#### Scenario: Decoupled approval

- **WHEN** the function returns `{challenge="Confirm in your banking app.", poll=true}`
- **THEN** the tool prints the text and "Waiting for approval", and calls the function again until it returns `nil` or an error message

### Requirement: Result as JSON

The `ext` tool SHALL print the result of a run as one JSON document on standard output. The document holds the accounts, and for each account the balances, the transactions, and the securities with the field names of the API. Output of `print` and status messages go to standard error.

#### Scenario: Pipe into another program

- **WHEN** the author runs `ext run Demo.lua > result.json`
- **THEN** `result.json` is valid JSON with one entry in `accounts`
- **AND** lines that the script printed appear in the terminal and not in the file

### Requirement: Same limits as in the app

The `ext` tool SHALL apply the host limits of the manifest, the HTTPS rule, and the removed Lua functions exactly as the app does, and report a violation as an error.

#### Scenario: Host outside the manifest

- **GIVEN** a manifest that lists only `api.broker.example`
- **WHEN** the script requests `https://tracker.example/pixel` during `ext run`
- **THEN** the tool stops with an error that names `tracker.example`

### Requirement: LocalStorage of the tool

The `ext` tool SHALL keep `LocalStorage` between runs in a file next to the script, or in the file given with `--storage`. The tool never reads or writes the database of the app. The option `--fresh` starts with an empty storage.

#### Scenario: Device registration survives

- **GIVEN** the first run stores `LocalStorage.deviceId`
- **WHEN** the author runs `ext run Demo.lua` again
- **THEN** the script finds `LocalStorage.deviceId`

#### Scenario: Fresh start

- **WHEN** the author runs `ext run --fresh Demo.lua`
- **THEN** `LocalStorage` is empty at the start of the run

### Requirement: Record a run

The `ext` tool SHALL save every HTTP request and response of a run to a fixture file with the command `ext record <script> <fixture>`. The fixture also holds the answers that the author gave to challenges, the start time, and the random values that the script received. It keeps a random value when a request address holds it or when a replay of the scrubbed fixture needs it, never one that the script used as a key, and holds only the kind and the length of any other random value.

#### Scenario: Record a refresh

- **WHEN** the author runs `ext record Demo.lua Fixtures/demo.json` and the script sends 4 requests
- **THEN** the fixture holds 4 pairs of request and response in the order they were sent

### Requirement: Recordings contain no secrets

The `ext` tool SHALL replace the login data, the answers to challenges, cookies, `Authorization` headers, and tokens in bodies with named placeholders before it writes a fixture. No option turns this off. The tool prints a list of the replaced values by kind, without the values.

#### Scenario: Password in a form body

- **GIVEN** the password "geheim123"
- **WHEN** the script posts `username=erika&password=geheim123` during `ext record`
- **THEN** the fixture contains `username={{username}}&password={{password}}`
- **AND** the text "geheim123" is nowhere in the fixture

#### Scenario: Session cookie

- **WHEN** a response sets the cookie `SESSION=abc123`
- **THEN** the fixture holds a placeholder for the cookie value in the response and in every later request

#### Scenario: Key of an encryption

- **WHEN** the script encrypts the password with a key and an IV of `MM.random` and posts the result
- **THEN** the fixture holds only the lengths of the key and the IV
- **AND** `ext test` replays the run with other values of the same lengths

#### Scenario: Login with PKCE

- **WHEN** the script sends the hash of a verifier of `MM.random` in an address and the verifier in a body
- **THEN** the fixture keeps the verifier, and `ext test` replays the login

#### Scenario: Short password in a response

- **GIVEN** the password "2025"
- **WHEN** a response of the run holds "01.03.2025"
- **THEN** the tool writes no fixture and says that the password is short or only digits

### Requirement: Warning about personal data in a recording

The `ext` tool SHALL remind the author after each recording that the fixture still holds account data such as names, IBANs, and amounts, and that the author must replace them with invented data before the file is shared or committed.

#### Scenario: After a recording

- **WHEN** `ext record` finishes
- **THEN** the tool prints the reminder and the path of the fixture

### Requirement: Replay a recording as a test

The `ext` tool SHALL run the script against a fixture with the command `ext test <script> <fixture> <expected>`. The tool answers each request from the fixture, compares the JSON result with the expected file, and reports each difference by its path in the document.

#### Scenario: Result matches

- **WHEN** the author runs `ext test Demo.lua Fixtures/demo.json Fixtures/demo.expected.json` and the result equals the expected file
- **THEN** the tool prints that the test passed and exits with status 0

#### Scenario: Amount differs

- **GIVEN** the expected file has the amount -89.00 for the first transaction
- **WHEN** the script returns -98.00
- **THEN** the tool prints the path of the amount with both values and exits with a status other than 0

#### Scenario: Create the expected file

- **WHEN** the author runs `ext test` with the option `--update`
- **THEN** the tool writes the current result to the expected file and says so

### Requirement: No network during a replay

The `ext` tool SHALL send no request to the network during `ext test`. A request that the fixture does not hold fails with an error that names the method and the URL.

#### Scenario: Script asks for a new page

- **GIVEN** a fixture without a response for `GET https://bank.example/accounts/2`
- **WHEN** the changed script requests that URL during `ext test`
- **THEN** the test fails with a message that names `GET https://bank.example/accounts/2`

### Requirement: Repeatable replays

The `ext` tool SHALL give a script the recorded start time through `os.time`, `MM.time`, and `MM.date`, the recorded values of `MM.random` and `MM.uuid`, and the recorded answers to challenges during a replay. `MM.sleep` returns at once.

#### Scenario: Same result on another day

- **GIVEN** a fixture recorded on 9 November 2026 with a script that requests the last 30 days
- **WHEN** the test runs three months later
- **THEN** the script computes the same date range and the test passes

### Requirement: Exit status

The `ext` tool SHALL exit with status 0 when a command succeeds and with a status other than 0 when the script stops with an error, when the login is rejected, when a test differs, or when the arguments are wrong. Each failure prints one line that says what failed.

#### Scenario: Rejected login

- **WHEN** the login function returns `LoginFailed` during `ext run`
- **THEN** the tool prints that the service rejected the login data and exits with a status other than 0

#### Scenario: Use in CI

- **WHEN** a CI job runs `ext test` for the example extension and the test passes
- **THEN** the job step succeeds without any input

### Requirement: Help and version

The `ext` tool SHALL print its commands and options with `ext --help`, and its version and the API version it implements with `ext --version`.

#### Scenario: Version

- **WHEN** the author runs `ext --version`
- **THEN** the tool prints its version and the API version, for example "API version 1"

### Requirement: Author guide

The project SHALL publish an author guide in the public catalog repository `MonetenApp/moneten-extensions`, where authors submit their packages. The guide has a tutorial that builds an extension for a public JSON API step by step, a reference of the API that lists every difference from the published Web Banking API, a description of the manifest, and the rules that every extension follows.

#### Scenario: Follow the tutorial

- **WHEN** a developer follows the tutorial from the first to the last step
- **THEN** the developer has an extension that `ext run` executes and that returns one account with transactions

#### Scenario: Look up a difference

- **WHEN** a developer looks up browser approvals in the reference
- **THEN** the reference names the final redirect addresses `https://service.moneymoney-app.com/1/redirect`, `moneymoney-app://oauth`, and `moneten://oauth`
- **AND** it says that a catalog package lists the login host in its manifest, and marks both as differences from the published Web Banking API

### Requirement: Replay in the catalog checks

The project SHALL run `ext test` with the recording of every catalog package in the checks of the catalog repository. The checks build `ext` from the app repository at a pinned commit. A package whose replay fails does not enter the catalog.

#### Scenario: Changed amount in a pull request

- **GIVEN** a pull request changes the amount of the first transaction in the expected file of the package "Broker" from -89.00 to -98.00
- **WHEN** the checks of the catalog repository run
- **THEN** the replay check fails and names the path of the amount with both values
- **AND** the pull request cannot be merged

### Requirement: Rules for extensions in the guide

The project SHALL state these rules in the guide. An extension only reads data. It contacts only the hosts in its manifest and only through HTTPS. It sends login data only to the service. It does no tracking. It writes no login data, cookies, or tokens to the log and stores no passwords in `LocalStorage`.

#### Scenario: Rules are checkable

- **WHEN** a reviewer reads an extension against the guide
- **THEN** each rule can be answered with yes or no from the script and its manifest

### Requirement: Example extension with a test

The project SHALL keep at least one example extension in the repository with a fixture and an expected result, and run `ext test` for it in CI.

#### Scenario: Change breaks the API

- **WHEN** a code change alters how `HTML:xpath` behaves and the example depends on it
- **THEN** the CI run fails at the test of the example extension
