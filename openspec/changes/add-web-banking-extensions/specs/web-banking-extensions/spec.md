# Spec Delta

## Purpose

Web banking extensions are Lua scripts that fetch accounts, balances, transactions, and securities from services without FinTS. This capability defines how the app installs, isolates, and runs these scripts, and the complete programming interface that the app offers to them. The interface is compatible with the Web Banking API that MoneyMoney publishes, so that extensions written for MoneyMoney run without changes.

## ADDED Requirements

### Requirement: Install by file

The app SHALL treat every `.lua` file and every package folder in the "Extensions" folder of the data folder as one installed extension. A package folder holds `manifest.json`, one or more Lua files, and a README. An extension that the user copies into the folder or adds with "Install from File..." is marked "Unverified". A change takes effect without a restart of the app.

#### Scenario: Add a file while the app runs

- **GIVEN** the app is running and the "Extensions" window is open
- **WHEN** the user copies `Demo.lua` into the "Extensions" folder
- **THEN** the extension "Demo" appears in the list without a restart
- **AND** the list marks it "Unverified"

#### Scenario: Install a package from a file

- **WHEN** the user chooses "Install from File..." and picks the folder `Broker` with `manifest.json`, `Broker.lua`, `Parser.lua`, and `README.md`
- **AND** the user confirms the warning
- **THEN** the folder is in the "Extensions" folder
- **AND** the list shows one extension "Broker" marked "Unverified"

#### Scenario: Remove a file

- **GIVEN** the extension "Demo" is installed
- **WHEN** the user deletes `Demo.lua` from the "Extensions" folder
- **THEN** the extension disappears from the list
- **AND** its services disappear from the add account assistant

### Requirement: Registration with WebBanking

The app SHALL accept a script as a web banking extension when the script calls `WebBanking{}` with a numeric `version`. The fields `url`, `services`, and `description` are optional. The script text is UTF-8.

#### Scenario: Valid registration

- **WHEN** a script starts with `WebBanking{version = 1.00, url = "https://bank.example/onlinebanking", services = {"Premium Account"}, description = "Demo"}`
- **THEN** the app lists the extension with the description "Demo" and the version 1.00

#### Scenario: Missing version

- **WHEN** a script calls `WebBanking{services = {"Premium Account"}}` without `version`
- **THEN** the app does not offer the service "Premium Account"
- **AND** the log names the file and says that `version` is missing

### Requirement: Scripts load without errors

The app SHALL load a script once to read its registration. A script with a syntax error or a run-time error at load time is not usable, and the app shows the file name, the line, and the message in the log and in the list of extensions.

#### Scenario: Syntax error

- **WHEN** `Broken.lua` has a syntax error in line 12
- **THEN** the list of extensions shows "Broken" as not usable with the message for line 12
- **AND** no service of that file is offered

### Requirement: List of installed extensions

The app SHALL list all installed extensions under "Installed" in the window that the menu item "Extensions" opens. Each row shows the name, the description, and the version, and "Unverified" for an extension installed from a file. The name is the file name without `.lua`, or the name of the package folder.

#### Scenario: Two extensions

- **GIVEN** the files `Demo.lua` with version 1.00 and `Broker.lua` with version 2.31 are installed
- **WHEN** the user chooses the menu item "Extensions"
- **THEN** the "Extensions" window lists "Demo" with "Version 1.00" and "Broker" with "Version 2.31" under "Installed", each with its description

### Requirement: Remove an extension

The app SHALL let the user remove an installed extension in the "Extensions" window. The app moves the file or the package folder to the Trash. Accounts that used the extension keep their transactions and show that their extension is missing.

#### Scenario: Remove an extension that an account uses

- **GIVEN** the account "Broker Depot" uses the extension "Broker"
- **WHEN** the user removes "Broker" in the "Extensions" window and confirms
- **THEN** `Broker.lua` is in the Trash
- **AND** the account "Broker Depot" still shows its data and reports at the next refresh that the extension "Broker" is not installed

### Requirement: Warning before the first run

The app SHALL warn the user before the first run of an extension installed from a file, and run it only after the user agrees. The warning says that the script receives the login data of the service and that nobody from the project has reviewed it. It lists the hosts of the manifest, or says that the app asks before each host. The app warns again when any file of the extension changes, the manifest included.

#### Scenario: Install from a file

- **WHEN** the user chooses "Install from File..." and picks `Demo.lua`
- **THEN** the app shows the warning with the buttons "Cancel" and "Install"
- **AND** after "Install" the list shows "Demo" marked "Unverified"

#### Scenario: First use of a copied file

- **GIVEN** the user copied `Demo.lua` into the "Extensions" folder
- **WHEN** the user picks the service "Premium Account" in the add account assistant
- **THEN** the app shows the warning with the buttons "Cancel" and "Continue"
- **AND** the script does not run before the user chooses "Continue"

#### Scenario: Changed file

- **GIVEN** the user allowed `Demo.lua` yesterday
- **WHEN** the file content changes and a refresh starts
- **THEN** the app does not run the script and asks for the confirmation again
- **AND** "Demo" stays marked "Unverified" after the confirmation

#### Scenario: Hosts of a manifest in the warning

- **GIVEN** the user copied `Demo.lua` and `Demo.json`, which lists the host `api.demo.example`
- **WHEN** the user picks the service "Premium Account" in the add account assistant
- **THEN** the warning names `api.demo.example` as the host that "Demo" may contact without asking

#### Scenario: Changed manifest

- **GIVEN** the user allowed `Demo.lua` with `Demo.json`, which lists only `api.demo.example`
- **WHEN** a program adds `collect.evil.example` to `Demo.json` and a refresh starts
- **THEN** the app does not run the script and shows the warning again with `api.demo.example` and `collect.evil.example`

### Requirement: Services in the assistant

The app SHALL offer every name in the `services` array of an installed extension under "Other" in the add account assistant.

#### Scenario: Service appears

- **GIVEN** an installed extension with `services = {"Premium Account"}`
- **WHEN** the user opens "Add Account..." and opens the menu "Other"
- **THEN** the menu contains "Premium Account"

### Requirement: Login fields

The app SHALL ask for the login data of an extension service in a dialog with a user name field, a password field, and up to two more fields. Without a manifest the dialog has the fields "Username" and "Password".

#### Scenario: Default fields

- **GIVEN** an extension without a manifest
- **WHEN** the user picks its service in the assistant and continues
- **THEN** the dialog shows the fields "Username" and "Password"

#### Scenario: Fields from the manifest

- **GIVEN** a manifest that names the fields "Email address", "API key", and no password
- **WHEN** the user picks the service in the assistant and continues
- **THEN** the dialog shows "Email address" and "API key" and no password field

### Requirement: Manifest

The app SHALL read `manifest.json` in a package folder, and a JSON file next to a single `.lua` file with the same base name, such as `Demo.json` next to `Demo.lua`. A single file may omit it. `files` lists the Lua files of a package in load order. `hosts` lists exact host names without wildcards. `services` lists the login field labels of each service. `kinds` lists the data, from balances, transactions, securities, and statements. `apiVersion` is the lowest API version needed.

#### Scenario: Manifest found

- **GIVEN** the package folder `Broker` with a manifest that lists the host `api.broker.example`
- **WHEN** the user opens the details of "Broker" in the "Extensions" window
- **THEN** the app shows `api.broker.example` as the only host the extension contacts

#### Scenario: Manifest next to a single file

- **GIVEN** the "Extensions" folder holds `Demo.lua` and `Demo.json`, which lists the host `api.demo.example` and the login field "API key"
- **WHEN** the user sets up the service of "Demo" and the script calls `connection:get("https://tracker.example/pixel")`
- **THEN** the login dialog shows the field "API key"
- **AND** the request is not sent and the refresh ends with an error that names `tracker.example`

#### Scenario: Newer API needed

- **GIVEN** a manifest that needs API version 3 and an app that offers API version 2
- **WHEN** the app loads the extension
- **THEN** the extension is not usable and the list says that it needs a newer version of the app

#### Scenario: Wildcard host

- **GIVEN** a manifest that lists the host `*.broker.example`
- **WHEN** the app loads the package
- **THEN** the extension is not usable and the list says that a host name must be exact

#### Scenario: Folder without a manifest

- **GIVEN** the folder `Broker` in the "Extensions" folder has no `manifest.json`
- **WHEN** the app reads the "Extensions" folder
- **THEN** the list shows "Broker" as not usable because the manifest is missing

### Requirement: Host limits of a manifest

The app SHALL let an extension with a manifest contact only the hosts in the manifest, matched by the exact name, and check the target of every HTTP redirect the same way. A blocked request is not sent and fails with an error that names the host.

#### Scenario: Host not in the manifest

- **GIVEN** a manifest that lists only `api.broker.example`
- **WHEN** the script calls `connection:get("https://tracker.example/pixel")`
- **THEN** the request is not sent
- **AND** the refresh ends with an error that names `tracker.example`

#### Scenario: Other host of the same domain

- **GIVEN** a manifest that lists only `api.broker.example`
- **WHEN** the script calls `connection:get("https://login.broker.example/")`
- **THEN** the request is not sent and the error names `login.broker.example`

#### Scenario: Redirect to another host

- **GIVEN** a manifest that lists only `api.broker.example`
- **WHEN** `https://api.broker.example/start` answers with status 302 and `Location: https://evil.example/`
- **THEN** the app does not request `https://evil.example/`
- **AND** the refresh ends with an error that names `evil.example`

### Requirement: Host prompts without a manifest

The app SHALL ask the user before an extension without a manifest contacts a host for the first time, and remember the answer for that extension. Each redirect target counts as a contact: the app follows a redirect to a new host only after "Allow". In a session with `interactive` false, the app sends nothing to a new host, shows no dialog, ends the session, and marks the accounts as waiting for an approval.

#### Scenario: No manifest, new host

- **GIVEN** an extension without a manifest, during a refresh that the user started
- **WHEN** the script contacts `www.bank.example` for the first time
- **THEN** the app asks whether "Demo" may contact `www.bank.example`
- **AND** after "Allow" the request is sent and the app does not ask again for this host

#### Scenario: Redirect to a new host

- **GIVEN** "Demo" has no manifest and the user allowed only `www.bank.example`
- **WHEN** `https://www.bank.example/start` answers with status 302 and `Location: https://login.bank.example/`
- **THEN** the app asks whether "Demo" may contact `login.bank.example` before it requests that address
- **AND** after "Deny" the app sends no request to `login.bank.example` and the refresh ends with an error that names it

#### Scenario: New host in an automatic refresh

- **GIVEN** "Demo" has no manifest and the user allowed only `www.bank.example`
- **WHEN** an automatic refresh runs and the script contacts `api.bank.example`
- **THEN** no dialog appears and no request goes to `api.bank.example`
- **AND** the accounts say that "Demo" waits for an approval and that the user must start the refresh

### Requirement: Exact host names

The app SHALL send a request of an extension only to an exact host name over HTTPS on port 443, with a manifest and without one, and also after a redirect. An IP address in any notation, `localhost`, a name without a dot, a trailing dot, a percent sign in the host, a user name or a password in the URL, and any other port fail at once. The app asks no question and sends nothing.

#### Scenario: IP address without a manifest

- **GIVEN** "Demo" has no manifest
- **WHEN** line 3 of `Demo.lua` calls `connection:get("https://127.0.0.1/")`
- **THEN** no dialog appears and no request is sent
- **AND** the script stops with "Demo.lua:3: Moneten sends requests only to a plain host name on the HTTPS port, not to https://127.0.0.1/."

#### Scenario: Other port

- **GIVEN** a manifest that lists only `api.broker.example`
- **WHEN** the script calls `connection:get("https://api.broker.example:8443/")`
- **THEN** no request is sent and the error names `https://api.broker.example:8443/`

#### Scenario: User name in the address

- **GIVEN** "Demo" has no manifest
- **WHEN** the script calls `connection:get("https://user:pass@www.bank.example/")`
- **THEN** no dialog appears and no request is sent

#### Scenario: Redirect to an IP address

- **GIVEN** "Demo" has no manifest and the user allowed `www.bank.example`
- **WHEN** `https://www.bank.example/local` answers with status 302 and `Location: https://127.0.0.1/`
- **THEN** the app asks no question and sends nothing to `127.0.0.1`
- **AND** the error names `https://127.0.0.1/`

#### Scenario: IP address in a manifest

- **GIVEN** a manifest that lists the host `192.168.0.1`
- **WHEN** the app loads the extension
- **THEN** the extension is not usable and the list says "A host name must be exact: 192.168.0.1."

### Requirement: Special-use host names

The app SHALL treat a name under the special-use domains `localhost`, `local`, `home.arpa`, `internal`, `test`, and `invalid` as not an exact host name, in a manifest, in the host dialog, after a redirect, and in a browser login. Such a name reaches the Mac, the local network, or nowhere. Names under `example` stay allowed. The app checks the name, not the address that the name resolves to.

#### Scenario: Name under localhost

- **GIVEN** "Demo" has no manifest and the user allowed `bank.localhost` in an earlier version of the app
- **WHEN** line 3 of `Demo.lua` calls `connection:get("https://bank.localhost/")`
- **THEN** no dialog appears and no request is sent
- **AND** the script stops with "Demo.lua:3: Moneten sends requests only to a plain host name on the HTTPS port, not to https://bank.localhost/."

#### Scenario: Name under local in a manifest

- **GIVEN** a manifest that lists the host `printer.local`
- **WHEN** the app loads the extension
- **THEN** the extension is not usable and the list says "A host name must be exact: printer.local."

#### Scenario: Browser login on a stored special-use name

- **GIVEN** "Demo" has no manifest and the app stored "Allow" for `auth.bank.local`
- **WHEN** the login function returns `{challenge="https://auth.bank.local/authorize?state=s1", state="s1"}`
- **THEN** no browser window opens

#### Scenario: Public name with a private address

- **GIVEN** the user allowed `www.bank.example` and the name resolves to 192.168.0.10
- **WHEN** the script calls `connection:get("https://www.bank.example/")`
- **THEN** the app connects to 192.168.0.10
- **AND** the request succeeds only when the server shows a certificate that the system trusts for `www.bank.example`

### Requirement: Default answer of the host dialog

The app SHALL make "Deny" the default button of the dialog that asks whether an extension may contact a new host. A slip of the Return key never sends login data to a new host. Escape answers "Deny", so the dialog always ends with an answer.

#### Scenario: Return in the host dialog

- **GIVEN** the dialog "Allow “Demo” to contact www.bank.example?" is open
- **WHEN** the user presses Return
- **THEN** the app sends nothing to `www.bank.example` and the refresh ends with an error that names it

#### Scenario: Escape in the host dialog

- **GIVEN** the dialog "Allow “Demo” to contact www.bank.example?" is open
- **WHEN** the user presses Escape
- **THEN** the app counts the answer as "Deny" and sends nothing to `www.bank.example`

### Requirement: Headers of a redirect to another host

The app SHALL forward only the headers `Accept`, `Accept-Language`, and `User-Agent` of the original request, and no body, when it follows a redirect to another host or port. A 307 or 308 on the same host and port keeps the method, the body, and every header. A 303, and a 301 or 302 after any method other than GET, become a GET without a body and without `Content-Type`. Each hop also gets the cookies of the run that match its address.

#### Scenario: 307 to another host

- **GIVEN** a manifest that lists `api.broker.example` and `auth.broker.example`
- **WHEN** the script posts `user=demo&pin=1234` to `https://api.broker.example/login` with the headers `Authorization: Bearer secret`, `Cookie: session=1`, `X-API-Key: bank-key-4711`, and `Accept: text/html`
- **AND** the server answers with status 307 and `Location: https://auth.broker.example/next`
- **THEN** the app sends a POST without a body to `https://auth.broker.example/next`
- **AND** of the headers of the script only `Accept: text/html` goes along, with the `User-Agent` and `Accept-Language` of the connection

#### Scenario: 308 on the same host

- **GIVEN** the same request as in the scenario before
- **WHEN** the server answers with status 308 and `Location: https://api.broker.example/next`
- **THEN** the app sends a POST to `https://api.broker.example/next` with the body `user=demo&pin=1234` and every header of the first request

#### Scenario: 302 after a POST to another host

- **GIVEN** the same request as in the first scenario
- **WHEN** the server answers with status 302 and `Location: https://auth.broker.example/next`
- **THEN** the app sends a GET without a body to `https://auth.broker.example/next` with only `Accept`, `Accept-Language`, and `User-Agent`

### Requirement: Isolation

The app SHALL run each extension session in its own process that can reach the network and nothing else. The script cannot read or write files, start programs, or read the data of another bank access. The process ends when the session ends.

#### Scenario: No file access

- **WHEN** line 4 of `Demo.lua` calls `io.open("/etc/hosts")`
- **THEN** the script stops with an error that begins with "Demo.lua:4: io.open is not available"
- **AND** the refresh ends with that error

#### Scenario: Other access is invisible

- **GIVEN** two bank accesses that use the same extension
- **WHEN** the script runs for the first access
- **THEN** `LocalStorage` and the login data contain only the values of the first access

### Requirement: Memory of a session

The app SHALL limit the memory of an extension session to 256 MB. The bytes of each `JSON`, `HTML`, and `PDF` object count toward the limit for as long as the script keeps the object. An allocation past the limit raises a memory error, which `pcall` can catch, and the session stays usable. While a function of the app runs, the session may use 64 MB more. Past that, the app stops the process.

#### Scenario: Large text

- **WHEN** `RefreshAccount` builds a text of 300 MB with `string.rep`
- **THEN** the call fails with "The extension needs more than 256 MB of memory."
- **AND** the refresh ends with that error

#### Scenario: Kept JSON documents

- **WHEN** a script keeps 200 `JSON` objects that each hold a document of 2 MB
- **THEN** the call fails with the error "not enough memory"

#### Scenario: Caught memory error

- **WHEN** a script runs `local ok = pcall(string.rep, "x", 300 * 1048576)` and then returns `ok`
- **THEN** the call returns `false`

#### Scenario: Function of the app past the headroom

- **GIVEN** the script of "Demo" holds 250 MB
- **WHEN** it calls `JSON(text):dictionary()` and the table of the result needs 100 MB
- **THEN** the app stops the process with "Demo needs more memory than Moneten allows, so Moneten stopped it."
- **AND** the refresh ends with that error

### Requirement: Processor time of a session

The app SHALL stop an extension session after 60 seconds of processor time in total.

#### Scenario: Endless loop

- **WHEN** `RefreshAccount` runs `while true do end`
- **THEN** the session stops after 60 seconds of processor time with "Demo used more than 60 seconds of processor time, so Moneten stopped it."

### Requirement: Silent extension

The app SHALL stop an extension session whose process sends nothing for 180 seconds while no dialog waits for the user. Output of `print` up to its limit, a status, the start and the end of each request, and each second of `MM.sleep` count as signs of life. The time that a dialog waits for the user does not count.

#### Scenario: Process that hangs

- **WHEN** the process of "Demo" sends nothing for 180 seconds during `RefreshAccount`
- **THEN** the app stops the process with "The extension did not respond for 180 seconds, so Moneten stopped it."

#### Scenario: Long sleep

- **WHEN** a script calls `MM.sleep(250)`
- **THEN** the session is not stopped and the script continues after 250 seconds

#### Scenario: Dialog open for ten minutes

- **GIVEN** the host dialog for `www.bank.example` is open for ten minutes
- **WHEN** the user then clicks "Allow"
- **THEN** the session continues and the request is sent

### Requirement: Size of a response

The app SHALL refuse a response body larger than 32 MB. The request fails, and the error names the host.

#### Scenario: Large download

- **WHEN** `https://www.bank.example/export` answers with a body of 40 MB
- **THEN** the call fails with an error that ends with "The answer of www.bank.example is larger than 32 MB."

### Requirement: Output of print

The app SHALL keep at most 4 MB of `print` output for one extension session, where each line counts 64 bytes more than its text. The app drops the rest, writes one line to the log that says so, and lets the script continue.

#### Scenario: Too much output

- **WHEN** a script prints 5,000 lines of 1,000 characters and then returns "done"
- **THEN** the log has the lines up to 4 MB, followed by "Moneten drops the rest of the output of print, because Demo printed more than 4 MB."
- **AND** the call returns "done"

### Requirement: Lua runtime

The app SHALL run scripts with Lua 5.4 and the standard libraries for strings, tables, math, UTF-8, and coroutines. `os` has only `time`, `date`, `clock`, and `difftime`. `io` is an empty table. `debug`, `package`, `load`, `loadstring`, `dofile`, `loadfile`, `require`, and `string.dump` are absent. A read of a removed name gives `nil`, and a call of it stops the script with "is not available" and the name.

#### Scenario: Standard library

- **WHEN** a script calls `os.time{year=2026, month=11, day=9}`, `os.date("%Y-%m-%d", 0)`, and `string.format("%.2f", 42)`
- **THEN** all three calls work as in Lua 5.4

#### Scenario: Removed function

- **WHEN** line 7 of `Demo.lua` calls `require("socket")`
- **THEN** the script stops with an error that begins with "Demo.lua:7: require is not available"

#### Scenario: File function read at load time

- **GIVEN** `Shop.lua` starts with the line `local open = io.open`
- **WHEN** the app loads the script
- **THEN** `open` is `nil`
- **AND** the script registers without an error

#### Scenario: Guarded file access

- **WHEN** a script runs `if io ~= nil and io.open ~= nil then return "file" else return "none" end`
- **THEN** the result is "none"

### Requirement: Global variables

The app SHALL define the globals `version`, `url`, `services`, and `description` with the values from `WebBanking{}`, and `extensionName` with the name of the extension.

#### Scenario: Read the registration

- **GIVEN** the file `Demo.lua` with `WebBanking{version = 1.00, description = "Demo"}`
- **WHEN** the script calls `print(extensionName, version, description)`
- **THEN** the log shows "Demo", 1.0, and "Demo"

### Requirement: Output and errors of a script

The app SHALL write the output of `print` to the log. A call of `error` stops the script. The app shows the message in the log and, when a dialog or an account is waiting for the result, also there.

#### Scenario: Print

- **WHEN** a script calls `print("Fetching page 2")`
- **THEN** the log shows "Fetching page 2" with the name of the extension

#### Scenario: Error during refresh

- **WHEN** a script calls `error("Unexpected page")` in `RefreshAccount`
- **THEN** the account shows a failed refresh with the message "Unexpected page"

### Requirement: Length of error messages

The app SHALL cut an error message of an API function that quotes data of the script after at most 1,000 bytes, at a character boundary, and add "…". The position of the error in the script comes before the message.

#### Scenario: Huge method

- **WHEN** line 4 of `Demo.lua` calls `connection:request(string.rep("x", 1048576), "https://api.bank.example/")`
- **THEN** the error begins with "Demo.lua:4: connection:request does not know the method XXX"
- **AND** after the position the message has at most 1,000 bytes followed by "…"

### Requirement: Order of calls

The app SHALL call the entry points in a fixed order. For a new bank access the order is `SupportsBank`, the login function, `ListAccounts`, `RefreshAccount` for each account, and `EndSession`. For a refresh the order is `SupportsBank`, the login function, `RefreshAccount` for each account, and `EndSession`.

#### Scenario: Refresh of two accounts

- **GIVEN** a bank access with two accounts
- **WHEN** a refresh runs
- **THEN** the script receives `SupportsBank`, one login, two calls of `RefreshAccount`, and `EndSession`, in this order

#### Scenario: Failure after login

- **WHEN** the login succeeds and `RefreshAccount` stops with an error
- **THEN** the app still calls `EndSession`

### Requirement: One call at a time

The app SHALL run one call of an extension session at a time. A second call while the first runs fails, does not reach the script, and leaves the first call running.

#### Scenario: Second call during a refresh

- **GIVEN** `RefreshAccount` of "Demo" runs for the account "Giro A"
- **WHEN** the app calls `RefreshAccount` of the same session for "Giro B" before the first call returns
- **THEN** the second call fails with "Another call of this extension session is still running."
- **AND** the first call returns its result

### Requirement: SupportsBank

The app SHALL call `SupportsBank(protocol, bankCode)` to find the extension for a bank access. `protocol` is `ProtocolWebBanking` or `ProtocolFinTS`. `bankCode` is a service name or a Bankleitzahl. The extension is responsible when it returns `true` or a URL, and not responsible when it returns `false`.

#### Scenario: Service name

- **WHEN** the app calls `SupportsBank(ProtocolWebBanking, "Premium Account")` and the script returns `true`
- **THEN** the app uses this extension for the access

#### Scenario: URL as answer

- **WHEN** the script returns `"https://bank.example/login"`
- **THEN** the app uses this extension, and the global `url` has that value for the rest of the session

### Requirement: Extensions add accounts to a FinTS access

The app SHALL ask the installed extensions with `ProtocolFinTS` and the Bankleitzahl when a FinTS access is set up or refreshed. A responsible extension can add accounts that the bank does not offer through FinTS. `ListAccounts` then receives the accounts that are already known.

#### Scenario: Credit card next to a giro account

- **GIVEN** a FinTS access with the Bankleitzahl 12030000 and one giro account, and an extension that returns `true` for `SupportsBank(ProtocolFinTS, "12030000")`
- **WHEN** the user runs "Look for New Accounts..."
- **THEN** `ListAccounts` receives the giro account in `knownAccounts`
- **AND** a credit card account that the script returns is offered to the user

### Requirement: InitializeSession

The app SHALL call `InitializeSession(protocol, bankCode, username, customer, password, credential)` to log in when the script does not define `InitializeSession2`. `customer` and `credential` hold the second and third field and are empty when the access has no such field. No return value or `nil` means success, `LoginFailed` means rejected login data, and a string is an error message.

#### Scenario: Success

- **WHEN** `InitializeSession` returns nothing
- **THEN** the app continues with the next entry point

#### Scenario: Error message

- **WHEN** `InitializeSession` returns `"The service is under maintenance."`
- **THEN** the session ends and the accounts of the access show that message

### Requirement: Rejected login data stops automatic refresh

The app SHALL, after a login function returns `LoginFailed`, tell the user that the login data was rejected and stop every automatic refresh of the accounts of that access until the user enters the login data again.

#### Scenario: Wrong password

- **GIVEN** an access with a saved password that the service no longer accepts
- **WHEN** the login returns `LoginFailed` during an automatic refresh
- **THEN** the accounts show that the login failed
- **AND** the next automatic refresh skips this access
- **AND** after the user enters the login data with "Edit Login Data...", the refresh runs again

### Requirement: InitializeSession2

The app SHALL call `InitializeSession2(protocol, bankCode, step, credentials, interactive, hbciTanMethods, session)` when the script defines it. The first call has `step` 1 and the login data in `credentials` in the order of the dialog fields. The function returns `nil`, `LoginFailed`, an error message, or a challenge table.

#### Scenario: First call

- **GIVEN** an access with the fields "Username" and "Password"
- **WHEN** a refresh that the user started logs in
- **THEN** the script receives `step` 1, `credentials` with the user name at index 1 and the password at index 2, `interactive` true, and `session` "refresh"

#### Scenario: Both login functions exist

- **WHEN** a script defines `InitializeSession` and `InitializeSession2`
- **THEN** the app calls only `InitializeSession2`

### Requirement: Session reason

The app SHALL pass the reason of the session in `session` as `"refresh"`, `"new account"`, `"statement"`, or `"tan media"`. The app never passes `"payment"`. `hbciTanMethods` holds the TAN methods of the FinTS access for `ProtocolFinTS` and is an empty array otherwise.

#### Scenario: Account setup

- **WHEN** the user adds a service in the assistant
- **THEN** the script receives `session` "new account"

### Requirement: Challenge tables

The app SHALL treat a returned table as a two-factor challenge when at least one of the fields `challenge`, `label`, `tanMethod`, or `tanMethods` is set. The app reads the fields `challenge`, `label`, `title`, `poll`, `tanMethod`, `tanMethods`, `button`, `startCode`, `appToApp`, and `state`.

#### Scenario: Shortest challenge

- **WHEN** the login function returns `{label="mobileTAN"}`
- **THEN** the app shows a dialog with one entry field labeled "mobileTAN"

#### Scenario: Title and button

- **WHEN** the function returns `{title="Enter the code from the SMS.", label="Code", button="next"}`
- **THEN** the dialog shows the title above the field and its confirm button reads "Next"

#### Scenario: Table without challenge fields

- **WHEN** the login function returns `{foo="bar"}`
- **THEN** the app does not show a dialog and ends the session with an error that says that the return value is not valid

### Requirement: Follow-up calls after a challenge

The app SHALL call the same function again after each challenge. `step` grows by 1, or by 2 when the challenge named a `tanMethod` directly. `credentials[1]` holds the answer of the user, `credentials[2]` a localized cancel message, and `credentials[3]` is true while another polling attempt is allowed.

#### Scenario: Entered code

- **GIVEN** the script returned `{label="Code"}` at `step` 1
- **WHEN** the user enters "123456" and confirms
- **THEN** the app calls the function with `step` 2 and `credentials[1]` "123456"

#### Scenario: Direct TAN method

- **GIVEN** the script returned `{label="Code", tanMethod={name="SMS", tanLength=6}}` at `step` 1
- **WHEN** the user enters the code
- **THEN** the app calls the function with `step` 3

#### Scenario: User cancels

- **WHEN** the user cancels the dialog
- **THEN** the session ends, the app calls `EndSession` if the login already succeeded, and the accounts show that the user canceled

### Requirement: Entry of a TAN or code

The app SHALL show an instruction text and an entry field for a challenge with a text in `challenge` and a `label`. A `tanMethod` sets the length and the allowed characters. Without a `tanMethod` the field accepts any text. The app removes HTML tags from the text.

#### Scenario: Six digits

- **GIVEN** the challenge `{title="Enter the code.", label="Code", tanMethod={name="SMS", tanLength=6, isNumeric=true}}`
- **WHEN** the user types "12a456"
- **THEN** the field does not accept the letter, and the confirm button stays disabled until six digits are entered

### Requirement: Image challenge

The app SHALL show the image when `challenge` holds the binary data of a PNG or JPEG image, for example a photoTAN graphic or an image captcha. With a `label` the dialog also has an entry field.

#### Scenario: photoTAN image

- **WHEN** the function returns `{label="photoTAN", challenge=image}` and `image` is PNG data
- **THEN** the dialog shows the image and an entry field labeled "photoTAN"

### Requirement: QR code challenge

The app SHALL draw a QR code when `challenge` is an `https://` URL and `tanMethod.name` equals `MM.localizeText("QR Code")`. Without a `label` the app treats the challenge as a decoupled method. With a `label` the dialog also has an entry field.

#### Scenario: QR code with polling

- **WHEN** the function returns `{challenge="https://bank.example/qr/abc", tanMethod={name=MM.localizeText("QR Code")}, poll=true}`
- **THEN** the dialog shows the QR code and a waiting notice
- **AND** the app calls the function again until it returns `nil` or an error

#### Scenario: Other method name

- **WHEN** the function returns the same URL with `tanMethod={name="Scan"}` and a `label`
- **THEN** the dialog shows the URL as text and the entry field, and no QR code

### Requirement: Decoupled challenge

The app SHALL show a waiting notice with a cancel button for a challenge with `poll=true` and no `label`. The app calls the function again and again with the same `step` until it returns `nil` or an error message. The app sets `credentials[3]` to false for the last allowed attempt.

#### Scenario: Approval in the banking app

- **GIVEN** the script returns `{challenge="Confirm the login in your banking app.", poll=true}`
- **WHEN** the user approves in the banking app and the script returns `nil` at the next call
- **THEN** the dialog closes and the session continues

#### Scenario: No approval in time

- **WHEN** the app calls the function with `credentials[3]` false and the script returns `credentials[2]`
- **THEN** the session ends with the localized cancel message

#### Scenario: Known app method

- **WHEN** the challenge has `tanMethod={name="pushTAN"}` and no `title`
- **THEN** the app shows its own instruction text for pushTAN

### Requirement: Choice of the TAN method

The app SHALL show a selection dialog for a challenge with `tanMethods`, and ignore `challenge`, `label`, and `tanMethod` of that table. The next call receives the table of the chosen method in `credentials[1]`. The app remembers the choice by `hbciMethod` for the access and preselects it next time.

#### Scenario: Two methods

- **GIVEN** the challenge `{tanMethods={{name="pushTAN", hbciMethod="700"}, {name="mobileTAN", hbciMethod="701", mediumName="+49 *** 4567"}}}`
- **WHEN** the user chooses "mobileTAN"
- **THEN** the next call has `credentials[1].name` "mobileTAN", `credentials[1].hbciMethod` "701", and a `label` that the app derived from the name
- **AND** at the next login "mobileTAN" is preselected

#### Scenario: Method with an error message

- **WHEN** a method has `errorMessage="Activate this method on the website first."`
- **THEN** the dialog shows the method with that message and the user cannot choose it

#### Scenario: Push already triggered

- **WHEN** the table has `tanMethods` and `poll=true`
- **THEN** the selection dialog stays open while the app polls the function for the first app method in the list

### Requirement: TAN method tables

The app SHALL read these fields of a TAN method table. `name` is required. `mediumName`, `hbciMethod`, `errorMessage`, `tanLength` with the default 6, `minLength`, `maxLength`, `isNumeric` with the default true, `isUppercase`, and `isPreferred` are optional. The app adds `label` to the tables that it passes to the script.

#### Scenario: Letters allowed

- **GIVEN** a challenge with `tanMethod={name="Code", minLength=4, maxLength=8, isNumeric=false}`
- **WHEN** the user types "ab12"
- **THEN** the field shows "AB12" and the confirm button is enabled

#### Scenario: Preferred method

- **WHEN** `tanMethods` holds a method with `isPreferred=true` and the user has not chosen before
- **THEN** that method is preselected

### Requirement: Captcha challenge

The app SHALL show a captcha in an embedded browser when `challenge` is the script URL of Google reCAPTCHA, hCaptcha, FriendlyCaptcha, or Amazon WAF, also when the table has a `label`. The URL carries the `sitekey`, and optionally `type=checkbox` and `referer`. The page of `referer` loads with a lower-case scheme and host, without port 443, and with `/` for an empty path. The app tries an invisible variant first. The next call receives the token in `credentials[1]`.

#### Scenario: Visible reCAPTCHA

- **WHEN** the function returns `{challenge="https://www.recaptcha.net/recaptcha/api.js?sitekey=KEY&type=checkbox&referer=https%3A%2F%2Fbank.example%2Flogin"}`
- **THEN** the app shows the checkbox captcha for the page `https://bank.example/login`
- **AND** after the user solves it, the next call has the token in `credentials[1]`

#### Scenario: Captcha next to a label

- **WHEN** the function returns `{challenge="https://abc123.token.awswaf.com/abc123/def/challenge.js?sitekey=KEY&referer=https%3A%2F%2Fbank.example", label="Bot-Prüfung"}`
- **THEN** the app shows the Amazon WAF captcha for the page `https://bank.example/`, not an entry field
- **AND** after the user solves it, the next call has the token in `credentials[1]`

#### Scenario: Captcha page in its canonical form

- **WHEN** the function returns `{challenge="https://www.recaptcha.net/recaptcha/api.js?sitekey=KEY&referer=HTTPS%3A%2F%2FBank.Example%3A443"}`
- **THEN** the captcha window loads the page `https://bank.example/`

### Requirement: Approval in a browser window

The app SHALL open any other `https://` URL in `challenge` in its own browser window when the host is allowed for the extension. When the website redirects to `https://service.moneymoney-app.com/1/redirect`, `moneymoney-app://oauth`, or `moneten://oauth`, the app closes the window without contacting that address. It passes the first of `code`, `access_token`, `auth_code`, `authorization_code`, and `tokenid` in `credentials[1]`, or ends the session with an error.

#### Scenario: OAuth authorization

- **GIVEN** the function returns `{challenge="https://auth.broker.example/authorize?client_id=abc", state="xyz"}`
- **WHEN** the user signs in and the website redirects to `moneten://oauth?code=4711&state=xyz`
- **THEN** the next call has `credentials[1]` "4711"

#### Scenario: Final address is never contacted

- **GIVEN** the browser window shows the login of `auth.broker.example`
- **WHEN** the website redirects to `https://service.moneymoney-app.com/1/redirect?code=4711&state=xyz`
- **THEN** the app closes the window and sends no request to `service.moneymoney-app.com`
- **AND** the next call has `credentials[1]` "4711"

#### Scenario: Other parameter name

- **WHEN** the website redirects to `moneymoney-app://oauth?authorization_code=4711&state=xyz`
- **THEN** the next call has `credentials[1]` "4711"

#### Scenario: No known parameter

- **WHEN** the website redirects to `moneten://oauth?ticket=4711&state=xyz`
- **THEN** the app closes the window and the session ends with an error that names the parameters it reads

#### Scenario: State is missing

- **WHEN** the table has no `state` and the URL has no `state` parameter
- **THEN** the app appends a random `state` value to the URL and accepts only a redirect with that value

#### Scenario: Host not allowed

- **WHEN** the URL has a host that the manifest does not list
- **THEN** the session ends with an error that names the host

### Requirement: App-to-app challenge

The app SHALL show the URL in `challenge` as a QR code and not open it in a browser when `appToApp` holds the name of a banking app. The instruction text names that app.

#### Scenario: Start the banking app by phone camera

- **WHEN** the function returns `{challenge="https://bank.example/app/approve/abc", appToApp="Example Banking", poll=true}`
- **THEN** the dialog shows a QR code and asks the user to scan it with the phone to open "Example Banking"

### Requirement: Start code of a chipTAN challenge

The app SHALL put the value of `startCode` into the instruction text that it creates for a chipTAN method.

#### Scenario: Manual chipTAN

- **WHEN** the function returns `{label="TAN", startCode="88123456", tanMethod={name="chipTAN manuell"}}`
- **THEN** the instruction text contains the start code 88123456

### Requirement: Challenges in the background

The app SHALL pass `interactive` as true when the user started the session and as false for an automatic refresh. When a script returns a challenge in a session with `interactive` false, the app shows no dialog, ends the session, and marks the accounts as waiting for an approval.

#### Scenario: Automatic refresh needs a TAN

- **GIVEN** an automatic refresh in the background
- **WHEN** the login function returns `{label="TAN"}`
- **THEN** no dialog appears
- **AND** the accounts say that the service asks for an approval and that the user must start the refresh

### Requirement: ListAccounts

The app SHALL call `ListAccounts(knownAccounts)` during setup and expect an array of account tables or an error message. The app ignores an account without `accountNumber`.

#### Scenario: One account

- **WHEN** `ListAccounts` returns `{{name="Premium Account", owner="Erika Mustermann", accountNumber="111222333444", bankCode="80007777", currency="EUR", type=AccountTypeGiro}}`
- **THEN** the assistant offers one giro account "Premium Account" in EUR

#### Scenario: Missing account number

- **WHEN** one of two returned accounts has no `accountNumber`
- **THEN** the assistant offers only the other account

### Requirement: Account tables

The app SHALL read and pass the account fields `name`, `owner`, `accountNumber`, `subAccount`, `portfolio`, `bankCode`, `currency`, `iban`, `bic`, and `type`. The values of `type` are `AccountTypeGiro`, `AccountTypeSavings`, `AccountTypeFixedTermDeposit`, `AccountTypeLoan`, `AccountTypeCreditCard`, `AccountTypePortfolio`, and `AccountTypeOther`.

#### Scenario: Portfolio

- **WHEN** an account table has `portfolio=true` and `type=AccountTypePortfolio`
- **THEN** the app creates a portfolio account

#### Scenario: Same table at refresh

- **WHEN** the app calls `RefreshAccount` for an account that `ListAccounts` returned with `subAccount="01"`
- **THEN** the `account` parameter has `subAccount` "01" and the other fields as returned

### Requirement: Account type when the script gives none

The app SHALL derive the account type from the account number and the name when `type` is missing. An account number with 16 characters or with masked digits counts as a credit card. A given type is taken as it is. The app sets the type only when it creates the account and does not change it at a refresh.

#### Scenario: Masked number

- **WHEN** an account has `accountNumber="5232 xxxx xxxx 1234"` and no `type`
- **THEN** the app creates a credit card account

#### Scenario: Type changed by the user

- **GIVEN** the user changed the type of an account to "Savings account"
- **WHEN** a refresh runs
- **THEN** the type stays "Savings account"

### Requirement: RefreshAccount

The app SHALL call `RefreshAccount(account, since, isKnownTransactionId, step, credentials, interactive)` for each account. `since` is the booking day from which transactions are needed as a POSIX time stamp, and 0 for a portfolio. The function returns a result table, a challenge table, or an error message.

#### Scenario: Balance and transactions

- **WHEN** the function returns `{balance=42.00, transactions={{bookingDate=1325764800, purpose="Hello World!", amount=42.00}}}`
- **THEN** the account shows the balance 42,00 € and one transaction with the purpose "Hello World!" on 5 January 2012

#### Scenario: Challenge for one account

- **WHEN** the function returns `{label="TAN"}` at `step` 1
- **THEN** the app shows the dialog and calls the function for the same account with `step` 2 and the answer in `credentials[1]`

### Requirement: Result table of RefreshAccount

The app SHALL read the fields `balance`, `balances`, `pendingBalance`, `transactions`, `securities`, and `bonusPoints`. `balances` is an array of pairs of an amount and a currency for an account with balances in several currencies.

#### Scenario: Several currencies

- **WHEN** the function returns `balances={{100.00, "EUR"}, {25.50, "USD"}}`
- **THEN** the account shows both balances with their currency

#### Scenario: Pending sum and bonus points

- **WHEN** the function returns `pendingBalance=-19.99` and `bonusPoints=1200`
- **THEN** the account shows a pending sum of -19,99 € and 1.200 bonus points

### Requirement: Missing parts of a result

The app SHALL show an error for the account when the result of a portfolio has no `securities`, or when the result of another account has no balance or no `transactions`. The message says which part could not be fetched.

#### Scenario: No transactions field

- **WHEN** the result of a giro account is `{balance=10.00}`
- **THEN** the account shows that the transactions could not be fetched
- **AND** the balance 10,00 € is stored

### Requirement: Transaction tables

The app SHALL read these transaction fields. `amount` and `bookingDate` are required. `name`, `accountNumber`, `bankCode`, `currency`, `valueDate`, `purpose`, `bookingText`, `endToEndReference`, `mandateReference`, `creditorId`, `returnReason`, and `booked` are optional. Dates are POSIX time stamps. Lines of the purpose are separated by line breaks.

#### Scenario: Full transaction

- **WHEN** a transaction has `name="Stadtwerke Musterstadt"`, `accountNumber="DE02120300000000202051"`, `bankCode="BYLADEM1001"`, `amount=-89.00`, `currency="EUR"`, `bookingDate=1794182400`, `purpose="Abschlag\nNovember"`, and `endToEndReference="E2E-1"`
- **THEN** the list shows a withdrawal of 89,00 € to "Stadtwerke Musterstadt" with a purpose of two lines
- **AND** the details show the IBAN, the BIC, and the end-to-end reference

#### Scenario: Missing amount

- **WHEN** one transaction in the array has no `amount`
- **THEN** the account shows an error that says that a transaction has no amount

### Requirement: Booking codes of a transaction

The app SHALL read and store the optional transaction fields `transactionCode`, `textKeyExtension`, `purposeCode`, `bookingKey`, `primanotaNumber`, and `batchReference`.

#### Scenario: SEPA purpose code

- **WHEN** a transaction has `purposeCode="SALA"` and `transactionCode=153`
- **THEN** both values are stored with the transaction and are part of every export that has these fields

### Requirement: Pending transactions from extensions

The app SHALL store a transaction with `booked=false` as pending and a transaction with `booked=true` or without the field as booked.

#### Scenario: Card authorization

- **WHEN** a transaction has `booked=false`
- **THEN** the list shows it as pending

### Requirement: New and known transactions

The app SHALL store a returned transaction as new when the database does not hold it and discard it as a duplicate otherwise. The script returns the newest transactions first, and the app accepts any order.

#### Scenario: Second refresh returns the same rows

- **GIVEN** a refresh stored 5 transactions
- **WHEN** the next refresh returns the same 5 transactions and 1 more
- **THEN** the account has 6 transactions

### Requirement: Transaction identifiers

The app SHALL store `transactionId` for booked transactions and pass the function `isKnownTransactionId` to `RefreshAccount`. The function returns the stored transaction with the fields `name`, `accountNumber`, `purpose`, `amount`, `currency`, `bookingDate`, `valueDate`, and `booked`, or `nil` when the identifier is empty, unknown, known only for a pending transaction, or stored more than once in the account.

#### Scenario: Stop paging at a known transaction

- **GIVEN** a booked transaction with `transactionId` "T-100" is stored for the account
- **WHEN** the script calls `isKnownTransactionId("T-100")`
- **THEN** the call returns a table with the amount and the booking date of that transaction

#### Scenario: Unknown identifier

- **WHEN** the script calls `isKnownTransactionId("T-999")` and no such transaction is stored
- **THEN** the call returns `nil`

### Requirement: Scope of an error in RefreshAccount

The app SHALL limit an error message from the first call of `RefreshAccount` to that account and continue with the next account. An error message from a follow-up call after a challenge ends the whole session.

#### Scenario: One account fails

- **GIVEN** an access with the accounts A and B
- **WHEN** `RefreshAccount` returns `"Account is closed."` for A at `step` 1
- **THEN** A shows the message and the app calls `RefreshAccount` for B

#### Scenario: Failure after a challenge

- **WHEN** `RefreshAccount` returns an error message for A at `step` 2
- **THEN** the app does not call `RefreshAccount` for B and calls `EndSession`

### Requirement: Security tables

The app SHALL read these fields of a security. `name`, `isin`, `securityNumber`, `quantity`, `currencyOfQuantity`, `purchasePrice`, `currencyOfPurchasePrice`, `exchangeRateOfPurchasePrice`, `price`, `currencyOfPrice`, `exchangeRateOfPrice`, `amount`, `originalAmount`, `currencyOfOriginalAmount`, `market`, and `tradeTimestamp`.

#### Scenario: Shares

- **WHEN** a result has `securities={{name="Muster AG", isin="DE0001234567", quantity=10, price=12.50, purchasePrice=10.00, amount=125.00, market="Xetra", tradeTimestamp=1794182400}}`
- **THEN** the portfolio shows "Muster AG" with 10 shares, the last quote 12,50 €, and the value 125,00 €

#### Scenario: Nominal amount

- **WHEN** a security has `quantity=5000` and `currencyOfQuantity="EUR"`
- **THEN** the app shows the quantity as a nominal amount of 5.000,00 € and not as a number of shares

### Requirement: FetchStatements

The app SHALL call the optional function `FetchStatements(accounts, knownIdentifiers, step, credentials, interactive)` once per session with all affected accounts when statements are downloaded for the access. `knownIdentifiers` has the identifiers of documents that are already stored as keys. The function returns a table with the array `statements`, a challenge table, or an error message.

#### Scenario: Script without the function

- **WHEN** a script does not define `FetchStatements`
- **THEN** the app does not offer a statement download for accesses that use this extension

#### Scenario: Known document

- **GIVEN** a stored document with the identifier "doc-17"
- **WHEN** the app calls `FetchStatements`
- **THEN** `knownIdentifiers["doc-17"]` is set
- **AND** a returned document with that identifier is not stored twice

### Requirement: Statement tables

The app SHALL read the statement fields `pdf`, `identifier`, `name`, `filename`, `creationDate`, `timezone`, and `account`. `pdf` is required and holds a PDF document or a ZIP archive, from which the app takes every PDF file. Without `account` the document belongs to the current account.

#### Scenario: ZIP archive

- **WHEN** `pdf` holds a ZIP archive with three PDF files
- **THEN** the app stores three statements

#### Scenario: Not a PDF

- **WHEN** `pdf` holds an HTML page
- **THEN** the app stores nothing and reports that the downloaded file is not in PDF format

### Requirement: EndSession

The app SHALL call `EndSession()` at the end of every session with a successful login. An error message from `EndSession` goes to the log and does not undo the data that was fetched.

#### Scenario: Logout fails

- **WHEN** `EndSession` returns `"Logout failed."` after a successful refresh
- **THEN** the new transactions stay stored and the log shows the message

### Requirement: Connection requests

The app SHALL offer `Connection()` and `connection:request(method, url, postContent, postContentType, headers)` with the methods GET, POST, PUT, PATCH, and DELETE. The call returns `content`, `charset`, `mimeType`, `filename`, and `headers`. The first URL must be absolute. A later URL can be relative to the last requested URL.

#### Scenario: Form post

- **WHEN** a script calls `connection:request("POST", "https://bank.example/login", "username=foo&password=bar", "application/x-www-form-urlencoded; charset=UTF-8")`
- **THEN** the call returns the page content, the character set "UTF-8", and the MIME type "text/html"

#### Scenario: Relative URL

- **GIVEN** the last request went to `https://bank.example/onlinebanking/start`
- **WHEN** the script calls `connection:get("accounts")`
- **THEN** the app requests `https://bank.example/onlinebanking/accounts`

#### Scenario: Plain HTTP

- **WHEN** a script requests `http://bank.example/`
- **THEN** the request is not sent and the script stops with an error

### Requirement: HTTP errors

The app SHALL stop the script and show an error when the server answers a request with an HTTP error status. When the request header `Accept` is `application/json`, the app returns the response to the script and does not stop it.

#### Scenario: Error page

- **WHEN** a request without an `Accept` header gets the status 503
- **THEN** the script stops and the account shows an error with the status 503

#### Scenario: JSON API

- **WHEN** a request with `headers={Accept="application/json"}` gets the status 401 and a JSON body
- **THEN** the call returns the body and the script continues

### Requirement: Connection shortcuts and state

The app SHALL offer `connection:get(url)`, `connection:post(url, postContent, postContentType)`, `connection:close()`, and `connection:getBaseURL()`, which returns the last requested URL. `get` and `post` return the same five values as `request`. A connection follows HTTP redirects unless the script sets `connection.redirects` to `false`. Open connections close when the script ends. The character set and MIME type come from the response header and from `<meta>` tags.

#### Scenario: Base URL

- **WHEN** a script calls `connection:get("https://bank.example/a/b")` and then `connection:getBaseURL()`
- **THEN** the second call returns "https://bank.example/a/b"

#### Scenario: Headers from a shortcut

- **WHEN** a script calls `local content, charset, mimeType, filename, headers = connection:get("https://bank.example/a")`
- **THEN** `headers` holds the response headers, for example `headers["Content-Type"]` "text/html; charset=UTF-8"

#### Scenario: Redirect not followed

- **GIVEN** the script sets `connection.redirects = false`
- **WHEN** `connection:get("https://bank.example/login")` gets the status 302 with `Location: https://bank.example/portal?code=X`
- **THEN** the call returns without requesting `https://bank.example/portal?code=X`
- **AND** `headers["Location"]` is "https://bank.example/portal?code=X"

### Requirement: Cookies

The app SHALL keep one cookie store per script run that all connections of the run share. The app fills it from response headers and `<meta>` tags and clears it after the run. `connection:setCookie(cookie)` adds or changes a cookie in the format of `Set-Cookie`. `connection:getCookies()` returns the cookies for the last requested URL in the format of the `Cookie` header.

#### Scenario: Set and read

- **GIVEN** the last request went to `https://bank.example/`
- **WHEN** the script calls `connection:setCookie("SESSION=foobar; path=/")` and then `connection:getCookies()`
- **THEN** the result contains "SESSION=foobar"

#### Scenario: New run

- **WHEN** the next refresh starts a new run
- **THEN** the cookie store is empty unless the script restored a connection from `LocalStorage`

### Requirement: User agent and language of a connection

The app SHALL send the value of `connection.useragent` as the `User-Agent` header and the value of `connection.language` as the `Accept-Language` header. The default language is the language of macOS.

#### Scenario: Custom user agent

- **WHEN** a script sets `connection.useragent = "Mozilla/5.0 (compatible; " .. MM.productName .. "/" .. MM.productVersion .. ")"` and sends a request
- **THEN** the request has that `User-Agent` header

### Requirement: HTML documents

The app SHALL offer `HTML(content, charset)` to parse an HTML document. Without `charset` the character set comes from the `<meta>` tags. `html:xpath(query)` selects elements with an XPath 1.0 expression with tag and attribute names in lower case. `html:html()` returns new formatted HTML in UTF-8.

#### Scenario: Fill a login form

- **GIVEN** `html = HTML(connection:get("https://bank.example/login"))`
- **WHEN** the script calls `html:xpath("//input[@name='pin']"):attr("value", "12345")`
- **THEN** the input field `pin` has the value "12345" in the document

### Requirement: Element lists

The app SHALL offer these methods on the result of `xpath`. `length()`, `get(n)` with an index from 1 and an empty list for an invalid index, `each(function (index, element))` which stops when the function returns false, `reverse()`, `children()`, and `xpath(query)` with a relative expression that starts with a period.

#### Scenario: Iterate rows

- **GIVEN** a table with 3 rows
- **WHEN** the script calls `html:xpath("//tr"):each(function (index, element) print(index .. "=" .. element:text()) end)`
- **THEN** the log has three lines that start with "1=", "2=", and "3="

#### Scenario: Invalid index

- **WHEN** the script calls `elements:get(5):length()` on a list with 2 elements
- **THEN** the result is 0

### Requirement: Element content and attributes

The app SHALL offer `text()` for the combined text of the elements and their children, `attr(attribute)` to read an attribute of the first element, and `attr(attribute, value)` to set an attribute on all elements.

#### Scenario: Read text and link

- **GIVEN** the element `<a href="/logout">Log <b>out</b></a>`
- **WHEN** the script calls `text()` and `attr("href")`
- **THEN** the results are "Log out" and "/logout"

### Requirement: Form helpers

The app SHALL offer `val()` for the value of a form field, `select(value)` to choose one option of a `<select>` list, `click()` on a link, submit button, or image button, and `submit()` on a form. `click` and `submit` return `method`, `url`, `postContent`, and `postContentType` for `connection:request`. `val` and `select` respect `disabled`.

#### Scenario: Submit a login form

- **GIVEN** a form with the method POST, the action `/login`, and the filled fields `user` and `pin`
- **WHEN** the script calls `connection:request(html:xpath("//input[@name='loginbutton']"):click())`
- **THEN** the app posts `user` and `pin`, URL-encoded, to `/login`, with the value of the clicked button

#### Scenario: Form without a button

- **WHEN** the script calls `html:xpath("//form"):submit()`
- **THEN** the returned parameters contain the input values and no value of a submit button

### Requirement: JSON

The app SHALL offer `JSON(json):dictionary()` to turn a JSON document into Lua tables, and `JSON():set(fields):json()` to turn Lua tables into a JSON document.

#### Scenario: Parse

- **WHEN** a script calls `JSON('{"balance": 42.5, "items": [1, 2]}'):dictionary()`
- **THEN** the result is a table with `balance` 42.5 and `items` with the two elements 1 and 2

#### Scenario: Create

- **WHEN** a script calls `JSON():set({user="foo"}):json()`
- **THEN** the result is a JSON document with the member `user` and the value "foo"

### Requirement: PDF text

The app SHALL offer `PDF(pdf):text()`, which returns the plain text of a PDF document as well as the document allows.

#### Scenario: Statement text

- **GIVEN** `pdf` holds a PDF with the line "Kontostand 1.234,56 EUR"
- **WHEN** the script calls `PDF(pdf):text()`
- **THEN** the result contains "Kontostand 1.234,56 EUR"

### Requirement: LocalStorage

The app SHALL offer the global table `LocalStorage`, whose content survives the run. The storage is separate for each bank access, is saved after the run, and is restored at the next run. It is empty after the access is set up again. The app keeps it inside the encrypted database.

#### Scenario: Device key

- **GIVEN** the first run sets `LocalStorage.deviceKey` to a key table
- **WHEN** the next refresh runs
- **THEN** `LocalStorage.deviceKey` has the same value

#### Scenario: Access set up again

- **WHEN** the user removes the accounts of the access and adds the service again
- **THEN** `LocalStorage.deviceKey` is `nil` in the first run

### Requirement: Values that LocalStorage keeps

The app SHALL save numbers, booleans, strings with any bytes, and nested tables as they are. A `Connection` object is saved with its last URL, cookies, user agent, and language. An `HTML` object is saved as HTML text and parsed again. Functions and other objects are not saved and are `nil` at the next run.

#### Scenario: Session survives a restart

- **GIVEN** a run stores `LocalStorage.connection = connection` after the login
- **WHEN** the app restarts and the next run calls `LocalStorage.connection:get("/accounts")`
- **THEN** the request goes to the same host with the cookies of the earlier run

#### Scenario: Function value

- **WHEN** a run stores a function in `LocalStorage.callback`
- **THEN** `LocalStorage.callback` is `nil` at the next run

### Requirement: Status, debug output, and sleep

The app SHALL offer `MM.printStatus(...)`, which writes to the log and shows the text as the status of the running session, `MM.printDebug(...)`, which writes a debug line to the log only, and `MM.sleep(seconds)`, which pauses the script.

#### Scenario: Status line

- **WHEN** a script calls `MM.printStatus("Loading page", 2)` during a refresh
- **THEN** the refresh status of the account shows "Loading page 2" and the log has the same line

### Requirement: Longest sleep

The app SHALL end each call of `MM.sleep` after at most 300 seconds. A script that needs a longer wait calls it again. A value of 0 or less returns at once.

#### Scenario: Sleep of an hour

- **WHEN** a script calls `MM.sleep(3600)`
- **THEN** the call returns after 300 seconds

### Requirement: Localization helpers

The app SHALL offer `MM.localizeText(str)`, which returns the translation of an English interface text or the text itself when the app has none, `MM.localizeDate(format, date)`, `MM.localizeNumber(format, num)`, and `MM.localizeAmount(format, amount, currency)`. `format` is optional and follows Unicode Technical Standard 35.

#### Scenario: German interface

- **GIVEN** the app runs in German
- **WHEN** a script calls `MM.localizeText("QR Code")` and `MM.localizeAmount(1234.5, "EUR")`
- **THEN** the results are the German name of the QR code method and "1.234,50 €"

#### Scenario: Unknown text

- **WHEN** a script calls `MM.localizeText("Fnord")`
- **THEN** the result is "Fnord"

#### Scenario: Number format

- **WHEN** a script calls `MM.localizeNumber("0.00;-0.00", -5)`
- **THEN** the result is "-5,00" in a German locale

### Requirement: Time helpers

The app SHALL offer `MM.time()`, which returns the current POSIX time with milliseconds as a fraction, `MM.timezone()`, which returns the name of the local time zone or "GMT", and `MM.gmtOffset(timezone, timestamp)`, which returns the offset from GMT in seconds with daylight saving time.

#### Scenario: Offset in summer

- **WHEN** a script calls `MM.gmtOffset("Europe/Berlin", 1783677600)` for a day in July 2026
- **THEN** the result is 7200

### Requirement: Date calculations

The app SHALL offer `MM.date` in four forms. Without parameters it returns the current time as a whole POSIX time stamp. With an offset such as `"-30D"` or `"1M"` it shifts a time stamp by days, weeks, months, quarters, or years. With `"*t"` it returns a table with `timestamp`, `year`, `month`, `day`, and `isBusinessDay`. With a table it builds a time stamp from `year`, `month`, `day`, `hour`, `min`, `sec`, `from`, and `to`.

#### Scenario: One month back

- **WHEN** a script calls `MM.date(nil, "-1M")` on 9 November 2026
- **THEN** the result is a time stamp on 9 October 2026

#### Scenario: Bank holiday

- **GIVEN** a bank access in Germany
- **WHEN** a script calls `MM.date(MM.date{year=2026, month=12, day=25}, "*t")`
- **THEN** the table has `day` 25 and `isBusinessDay` false

#### Scenario: Defaults of the table form

- **WHEN** a script calls `MM.date{year=2026, month=9, day=3, from="Europe/Berlin"}`
- **THEN** the result is the time stamp of 12:00 on 3 September 2026 in Berlin

### Requirement: Text encoding helpers

The app SHALL offer `MM.urlencode(str, charset)` with the default character set ISO-8859-1, `MM.urldecode(urlencoded)`, `MM.toEncoding(charset, str, bom)`, `MM.fromEncoding(charset, data)`, `MM.utf8len(str)`, `MM.utf8sub(str, start, end)`, and `MM.utf8lower(str)`.

#### Scenario: URL encoding

- **WHEN** a script calls `MM.urlencode("Müller")` and `MM.urlencode("Müller", "UTF-8")`
- **THEN** the results are "M%FCller" and "M%C3%BCller"
- **AND** `MM.urldecode("M%FCller")` returns "Müller"

#### Scenario: Characters and bytes

- **WHEN** a script calls `MM.utf8len("Bäcker")`, `MM.utf8sub("Bäcker", 2, 3)`, and `MM.utf8lower("BÄCKER")`
- **THEN** the results are 6, "äc", and "bäcker"

### Requirement: Binary encoding helpers

The app SHALL offer `MM.base64(data, linebreaks)`, `MM.base64urlencode(data)` without padding, `MM.base64decode(encoded)`, which also accepts the URL-safe form and line breaks, `MM.binToHex(data)` with upper case output, and `MM.hexToBin(hex)`, which ignores case and colons and returns `nil` for invalid input.

#### Scenario: Round trip

- **WHEN** a script calls `MM.base64decode(MM.base64urlencode("\xfb\xff"))`
- **THEN** the result is the two bytes FB FF, and the encoded text is "-_8"

#### Scenario: Invalid hex

- **WHEN** a script calls `MM.hexToBin("XY")`
- **THEN** the result is `nil`

### Requirement: Hashes and message authentication codes

The app SHALL offer `MM.sha512`, `MM.sha256`, `MM.sha1`, `MM.sha3_256`, and `MM.md5`, which return the hash as hexadecimal text in upper case, and `MM.hmac512`, `MM.hmac384`, `MM.hmac256`, and `MM.hmac1` with the parameters `key` and `data`, which return binary data.

#### Scenario: SHA-256 of an empty text

- **WHEN** a script calls `MM.sha256("")`
- **THEN** the result is "E3B0C44298FC1C149AFBF4C8996FB92427AE41E4649B934CA495991B7852B855"

#### Scenario: HMAC as hex

- **WHEN** a script calls `MM.binToHex(MM.hmac256("key", "data"))`
- **THEN** the result is 64 hexadecimal characters

### Requirement: Random values

The app SHALL offer `MM.random(length)`, which returns that many random bytes from a cryptographic source, and `MM.uuid()`, which returns a random version 4 UUID in lower case.

#### Scenario: Nonce

- **WHEN** a script calls `MM.random(16)` twice
- **THEN** each result has 16 bytes and the two results differ

### Requirement: Environment values

The app SHALL offer `MM.productName` with the value "Moneten", `MM.productVersion` as text, `MM.productBuild` as a number, `MM.apiVersion` as a number, `MM.language` with the language code of the interface, and `MM.deviceUuid` with a random identifier that the app creates once and keeps.

#### Scenario: Stable device identifier

- **WHEN** two refreshes on different days read `MM.deviceUuid`
- **THEN** both get the same UUID

#### Scenario: Language

- **GIVEN** the interface language is German
- **WHEN** a script reads `MM.language`
- **THEN** the value is "de"

### Requirement: Build variant values

The app SHALL set exactly one of `MM.DEBUG`, `MM.BETA`, and `MM.RETAIL` to an empty string and the others to `nil`. `MM.APPSTORE` is always `nil`.

#### Scenario: Release build

- **WHEN** a script in a release build evaluates `MM.RETAIL ~= nil` and `MM.DEBUG ~= nil`
- **THEN** the results are true and false

### Requirement: RSA functions

The app SHALL offer `MM.rsaGenerateKeys(bits)` for 512 to 4096 bits, `MM.rsaSign` and `MM.rsaVerify` with the algorithm `"pkcs1-v1_5 sha256"`, `MM.rsaEncrypt` and `MM.rsaDecrypt` with `"pkcs1-oaep sha256"` or `"pkcs1-oaep sha512"`, `MM.rsaEncrypt` also with `"pkcs1-oaep sha256 sha1"`, and `MM.rsaPkcs1(modulus, exponent, data)`. Key tables use the binary fields `n`, `e`, `d`, `p`, `q`, `dmp1`, `dmq1`, and `iqmp`.

#### Scenario: Sign and verify

- **GIVEN** `key = MM.rsaGenerateKeys(2048)`
- **WHEN** a script calls `MM.rsaVerify(key, "data", MM.rsaSign(key, "data", "pkcs1-v1_5 sha256"), "pkcs1-v1_5 sha256")`
- **THEN** the result is true, and the signature has 256 bytes

#### Scenario: Unknown algorithm

- **WHEN** a script calls `MM.rsaSign(key, "data", "pss sha256")`
- **THEN** the result is `nil`

#### Scenario: Invalid key length

- **WHEN** a script calls `MM.rsaGenerateKeys(128)`
- **THEN** the result is `nil`

### Requirement: Elliptic curve functions

The app SHALL offer `MM.ecGenerateKeys(curve)` for named curves such as `"prime256v1"` and for `"ed25519"`, and `MM.ecSign` and `MM.ecVerify` with the algorithms `"ecdsa sha256"`, `"ecdsa sha512"`, and `"eddsa"`. ECDSA key tables have `curve`, `x`, `y`, and `d`. Ed25519 key tables have `curve`, `x`, and `d`. ECDSA signatures are DER-encoded. EdDSA signatures are 64 raw bytes.

#### Scenario: Ed25519 signature

- **GIVEN** `key = MM.ecGenerateKeys("ed25519")`
- **WHEN** a script calls `MM.ecSign(key, "message", "eddsa")`
- **THEN** the result has 64 bytes, and `MM.ecVerify(key, "message", signature, "eddsa")` is true

#### Scenario: Unknown curve

- **WHEN** a script calls `MM.ecGenerateKeys("fnord")`
- **THEN** the result is `nil`

#### Scenario: Wrong data

- **WHEN** a script verifies a valid signature against other data
- **THEN** `MM.ecVerify` returns false

### Requirement: AES functions

The app SHALL offer `MM.aes256encrypt(key, iv, data, algorithm, aad)` and `MM.aes256decrypt(key, iv, encrypted, algorithm, aad, tag)` with a key of 32 bytes. The algorithm is `"aes256 cbc"` by default, with a 16 byte vector and PKCS#7 padding, or `"aes256 gcm"`, with a 12 byte vector, required `aad`, and a 16 byte tag as the second result of the encryption.

#### Scenario: CBC round trip

- **WHEN** a script encrypts "secret" with a 32 byte key and a 16 byte vector and decrypts the result with the same values
- **THEN** the result is "secret"

#### Scenario: GCM with a wrong tag

- **WHEN** a script calls `MM.aes256decrypt` with `"aes256 gcm"` and a changed tag
- **THEN** the result is `nil`

#### Scenario: Wrong key length

- **WHEN** a script calls `MM.aes256encrypt` with a key of 16 bytes
- **THEN** the result is `nil`

### Requirement: Key format functions

The app SHALL offer `MM.pkcs8decode(data)`, which reads a private or public RSA, EC, or Ed25519 key from PEM or DER and returns a key table with the field `type`, `MM.rsaPkcs8(key)`, which returns the public key as a PEM block, and `MM.rsaPkcs8decode(pem)`, which returns `n` and `e` of a public RSA key. Each returns `nil` when it cannot read the key.

#### Scenario: API key pasted by the user

- **GIVEN** `apiKeyPem` holds an Ed25519 private key in PEM format
- **WHEN** a script calls `MM.pkcs8decode(apiKeyPem)`
- **THEN** the result is a table with `type` "ed25519" and the fields `curve`, `x`, and `d`

#### Scenario: Not a key

- **WHEN** a script calls `MM.pkcs8decode("hello")`
- **THEN** the result is `nil`

### Requirement: DER decoding

The app SHALL offer `MM.derdecode(data)`, which reads the DER elements at the top level of a binary string and returns an array with one table per element. Each table holds the tag byte as a number at index 1 and the content bytes as a string at index 2. It does not descend into an element. The result is `nil` when an element is cut off or its length is not definite.

#### Scenario: Sequence and null

- **WHEN** a script calls `MM.derdecode(MM.hexToBin("30060201010401000500"))`
- **THEN** the result has 2 elements
- **AND** the first has the tag 48 and the content `MM.hexToBin("020101040100")`, the second has the tag 5 and the content ""

#### Scenario: Nested element

- **WHEN** a script calls `MM.derdecode(MM.hexToBin("020101040100"))`
- **THEN** the result is `{{2, MM.hexToBin("01")}, {4, MM.hexToBin("00")}}`

#### Scenario: Cut-off data

- **WHEN** a script calls `MM.derdecode(MM.hexToBin("3006020101"))`
- **THEN** the result is `nil`

### Requirement: Undocumented functions in use

The app SHALL offer `MM.derdecode`, `MM.base64urldecode`, `connection.redirects`, the fifth return value of `connection:get`, `elements:html()`, and `JSON(json):array()`, because published extensions use them. `elements:html()` returns the markup of each element in turn. `JSON(json):array()` returns the same as `JSON(json):dictionary()`. A call of any other function that the app does not offer stops the script with an error that names the function and the line. A read of such a name gives `nil`.

#### Scenario: URL-safe Base64

- **WHEN** a script calls `MM.base64urldecode("SGVsbG8")`
- **THEN** the result is "Hello"

#### Scenario: Markup of an element

- **GIVEN** a document with `<div data-id="302-1"><b>Order</b></div>`
- **WHEN** a script calls `html:xpath("//div"):html()`
- **THEN** the result is `<div data-id="302-1"><b>Order</b></div>`

#### Scenario: Unknown function

- **GIVEN** line 12 of `Demo.lua` calls `MM.parseSwiftMt(data)`
- **WHEN** the script runs during a refresh
- **THEN** the script stops and the account shows an error that names `MM.parseSwiftMt` and line 12

#### Scenario: Guarded use

- **WHEN** a script tests `type(MM.bcrypt) == "function"`
- **THEN** the test is false and the script continues

### Requirement: Packages

The app SHALL install, update, and remove a package as one unit. All Lua files of a package run in the same Lua state during a session. A package whose `files` names a file that is missing or cannot be read is not usable.

#### Scenario: Remove a package

- **GIVEN** the package "Broker" with `Broker.lua` and `Parser.lua` is installed
- **WHEN** the user removes "Broker" in the "Extensions" window and confirms
- **THEN** the whole folder `Broker` is in the Trash

#### Scenario: Replace a package

- **GIVEN** the package "Broker" is installed from a file
- **WHEN** the user installs a new folder `Broker` with "Install from File..." in which `Parser.lua` changed and `Old.lua` is gone
- **THEN** the "Extensions" folder holds only the files of the new folder

#### Scenario: Missing file

- **GIVEN** the manifest of "Broker" lists `Parser.lua` and the folder has no such file
- **WHEN** the app loads the package
- **THEN** "Broker" is not usable and the list names `Parser.lua`

### Requirement: No payments through extensions

The app SHALL not offer any function, entry point, or session reason that sends a payment through an extension. An account that an extension provides is read-only in the app.

#### Scenario: Payment commands

- **GIVEN** the selected account comes from an extension
- **WHEN** the user opens "New Bank Transfer..."
- **THEN** the account is not offered as the source account

#### Scenario: Script with a payment function

- **WHEN** a script written for another app defines extra functions for payments
- **THEN** the app never calls them, and the extension still works for reading

### Requirement: Errors of an extension appear on the account

The app SHALL show every error of an extension session on the affected accounts with the message of the script, the name of the extension, and the time, and write it to the log. An error in one access does not stop the refresh of other accesses.

#### Scenario: Two services

- **GIVEN** one access with the extension "Demo" and one FinTS access
- **WHEN** the script of "Demo" stops with an error during "Refresh All Accounts"
- **THEN** the "Demo" accounts show the error
- **AND** the FinTS accounts refresh as usual
