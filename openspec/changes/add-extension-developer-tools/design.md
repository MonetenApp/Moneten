# Design

## Context

The `ext` tool runs a web banking extension outside the app ([ADR 0015](../../../docs/decisions/0015-extension-program.md)). The app runs each session in its own host process through `ExtensionHostClient`, and `ExtensionConnector` calls the entry points, turns challenge tables into requests to the user, and checks the result tables. `ext` uses both unchanged, so a script meets the same host limits, the same Lua environment, and the same order of entry points as in the app.

The recording format is a contract. The catalog checks of `MonetenApp/moneten-extensions` replay each package with `ext test`, and the compatibility tests of the app replay recordings of published extensions. Both read the format below.

## Decisions

### One binary

`ext` starts its own binary again as the host process, with a hidden argument, and talks to it through `ExtensionHostClient` as the app talks to `MonetenExtensionHost`. One file is the whole tool. The host process of `ext` has no App Sandbox. The host limit, the HTTPS rule, and the removed Lua functions do not depend on the sandbox, because the host code applies them before any request.

### Commands

| Command | What it does |
|---|---|
| `ext run <script> [--service <name>] [--storage <file>] [--fresh] [--trust <certificate>]` | Runs the script against the network and prints the result as JSON. |
| `ext record <script> <fixture> [--service <name>] [--trust <certificate>]` | Runs the script against the network and writes the fixture. |
| `ext test <script> <fixture> <expected> [--service <name>] [--update]` | Replays the fixture and compares the result with the expected file. |
| `ext --help`, `ext <command> --help`, `ext --version` | Help and the versions of the tool and of the API. |

`<script>` is a `.lua` file, with an optional manifest of the same base name next to it, or a package folder with `manifest.json`.

`--trust` names a certificate in PEM or DER that HTTPS trusts in addition to those of the system, for a test server of the author. The host limit and the HTTPS rule stay. The app has no such option.

The service is the `--service` option, the recorded service during `ext test`, the only service of the script, or the answer to a numbered list of the services that `WebBanking{}` registers.

### Exit status

| Status | Meaning |
|---|---|
| 0 | The command succeeded, or the test passed. |
| 1 | The test found a difference. |
| 2 | The script, the login, or the replay failed: an error of the script, a rejected login, a refused host, a request that the fixture lacks, or an account that failed. |
| 64 | The arguments are wrong, or a file cannot be read. |

Each failure prints one line on standard error that says what failed.

### Output

Standard output gets one JSON document with sorted keys. `print`, the status, the prompts, and the messages of the tool go to standard error.

```json
{
  "accounts": [
    {
      "accountNumber": "0123456789",
      "balance": 1520.4,
      "currency": "EUR",
      "iban": "DE02120300000000202051",
      "name": "Giro",
      "transactions": [
        { "amount": -89, "bookingDate": 1794268800, "name": "Erika Mustermann", "purpose": "Rent" }
      ],
      "type": "AccountTypeGiro"
    }
  ]
}
```

Each entry of `accounts` is the table that `ListAccounts` returned for the account, with the fields of the table that `RefreshAccount` returned added to it. A field of the second table replaces a field of the same name. When the app would fail the account, the entry has the field `error` with the message that the app shows, and the command prints the message and exits with status 2. The values are the values of the script: amounts are numbers and dates are timestamps.

### Login data and storage

`ext run` and `ext record` ask for the login fields of the manifest for the service, or for "Username" and "Password". `EXT_USERNAME` and `EXT_PASSWORD` replace the first two fields without a question. A secret field does not echo. The tool keeps login data in memory only.

`ext run` keeps `LocalStorage` and the value of `MM.deviceUuid` in `<script>.storage.json` next to the script or package, or in the file of `--storage`. `--fresh` starts with an empty storage and a new device identifier. The file can hold cookies and tokens that the script keeps, so it belongs in `.gitignore`, and only its owner can read it (mode 0600). A package folder `My.Bank` keeps `My.Bank.storage.json`.

`ext record` and `ext test` start with an empty `LocalStorage` and do not read or write the storage file. A replay then depends on the fixture alone, as the set-up of a new access in the app does.

### Clock and random values

During `ext record` and `ext test`, the clock of the script starts at the start time of the fixture and moves forward only by the seconds of `MM.sleep`. `os.time`, `os.date`, `MM.time`, `MM.date`, `MM.gmtOffset`, and the expiry of cookies read this clock. `MM.sleep` waits during `ext record` and returns at once during `ext test`. Because the clock is the same in both, a request whose address holds the time, such as a cache parameter, matches its recording. The clock stands still while the author answers a challenge during `ext record`, so a server that checks a signed time stamp of the script can refuse a request after a long pushTAN. Such a script needs a recording with a quick answer.

`ext record` writes the values of `MM.random` and `MM.uuid` to the fixture in order. It keeps a value only when a request address holds it as bytes, hex, Base64, Base64url, or UUID, because the replay needs the same address to find the exchange. Of any other value, such as the key and the IV of an encryption whose result stands in a body, the fixture holds only the kind and the length: with the key, anyone who has the fixture could read what it hid. `ext test` returns the values in the same order, and counter values of the same length in place of a withheld one, which works because a replay does not compare request bodies. When a changed script asks for more values than the fixture has, the next values come from a counter, so the test stays repeatable. The random seed of the RSA padding is never recorded: with it, anyone who has the fixture could test each guess of a short secret, such as a PIN, against the encrypted block. A replay pads with counter values, because it does not compare request bodies. The expiry of a cookie with `Max-Age` counts on the clock of the session.

The fixture also holds the time zone and the values of `MM.language`, `MM.localizeAmount`, and the other values of the environment. `ext test` uses them, so a test gives the same result in every time zone and language. A fixture without a time zone replays in UTC.

### Fixture format

A fixture is one JSON object in UTF-8. The hand-written fixtures of the tests use only `exchanges` and leave out the fields of the request other than `method` and `url`. The fields:

| Field | Type | Meaning |
|---|---|---|
| `format` | integer | 1 |
| `service` | string | The service that the run used |
| `startTime` | number | Seconds since 1970-01-01 UTC, the start of the clock |
| `timeZone` | string | IANA name, for example "Europe/Berlin" |
| `environment` | object | `productVersion`, `productBuild`, `variant`, `language`, `locale`, `deviceUuid`, `country` |
| `answers` | array | The answers of the run, in order |
| `random` | array | The random values of the run, in order |
| `exchanges` | array | The requests and responses, in the order the script sent them |

An answer is an object with one key.

| Answer | Example |
|---|---|
| Login data | `{"login": ["{{username}}", "{{password}}"]}` |
| A typed TAN, a code of a browser login, or a captcha | `{"tan": "{{answer1}}"}` |
| A TAN method | `{"tanMethod": "1"}` |
| A TAN medium | `{"tanMedium": "Phone"}` |
| A new host of an extension without a manifest | `{"host": "allowed"}` |

A random value is `{"bytes": "<Base64>"}` or `{"uuid": "<lower-case UUID>"}`. A withheld value is `{"withheld": <number of bytes>}` or `{"withheld": "uuid"}`.

An exchange:

```json
{
  "request": {
    "method": "POST",
    "url": "https://bank.example/login",
    "headers": { "Content-Type": "application/x-www-form-urlencoded" },
    "body": "username={{username}}&password={{password}}"
  },
  "response": {
    "status": 302,
    "headers": { "Location": "/accounts", "Set-Cookie": "SESSION={{cookie1}}; Path=/; Secure" },
    "body": ""
  }
}
```

A body that is not UTF-8 is `base64Body` in place of `body`. A replay answers each request with the first unused exchange of the same method and URL. Placeholders in the URL count as equal in their plain and their percent-encoded form. Any other percent-encoding counts as it is, so `a%2Fb` is not `a/b`. Headers and bodies of requests do not take part in the match.

### Placeholders

`Scrubber` replaces each secret with a named placeholder before the fixture is written. No option turns this off.

| Kind | Source | Placeholder |
|---|---|---|
| username | the first login field | `{{username}}` |
| password | each secret login field | `{{password}}`, `{{password2}}` |
| login | each other login field | `{{login3}}` |
| answer | each typed TAN, code of a browser login, or captcha answer | `{{answer1}}` |
| cookie | each value of `Set-Cookie` and `Cookie` | `{{cookie1}}` |
| authorization | each value of `Authorization` and `Proxy-Authorization` | `Bearer {{token1}}`, `Basic {{authorization1}}` |
| token | each value of a header, JSON key, form field, query or fragment parameter, HTML field, or meta tag whose name holds token, secret, session, csrf, xsrf, password, passwd, jwt, apikey, api-key, api_key, or subscription-key, or is sid, pin, otp, tan, code_verifier, nonce, auth, or x-auth, and each value of a query or form field `code` | `{{token1}}` |

The scrubber searches every URL, header, body, and answer for each secret in its plain form, percent-encoded in UTF-8 and in ISO-8859-1 with upper-case and lower-case digits, form-encoded, JSON-escaped, HTML-escaped, and in Base64 and Base64url with and without padding, and the login name and password together in Basic form. The forms can mix within one value, such as `J&uuml;rgen` or `J\u00FCrgen`, and login values and answers match in any case of their letters, also encoded, such as `%47` or `\u0047` for the `g` of a password. JSON escapes include `\t`, `\n`, `\r`, `\b`, and `\f`. A body that is not UTF-8 is searched as ISO-8859-1, also for tokens, and the value of an HTML field counts with its entities decoded, so `abc&#45;12345` also finds `abc-12345`. A quoted cookie value counts without its quotes. A match must not have a letter or digit of the ASCII alphabet right before or after it, so a PIN `12345` stays in `123456.78`. In a JSON body of a response, a login value or an answer is replaced only inside strings, so an amount that equals a TAN stays a number. In a JSON body of a request, a login value or an answer that is a number becomes the placeholder as a string, such as `{"pin":"{{password}}"}`. A JSON number under a token name becomes the placeholder as a string, also when the token was found as text before. A password with fewer than 8 characters or only digits, such as a PIN, is replaced only in requests: in a response, the text around its placeholder, such as `01.03.{{password}}`, would show it. When a response holds such a password, the tool writes no fixture. The scheme and the host of a URL stay as they are, and so does each path segment that stands in the script, such as `/login` for the user name "login". A cookie value with fewer than 6 characters is replaced only in the cookie headers. A value with fewer than 6 characters, with a space, of letters only, that starts with a date, or under a name that ends in "type" is no token. A URL gets the placeholder percent-encoded, a header or body gets it plain.

During a replay, the login fields, the TANs, and the codes are the placeholders themselves. A script then sends the same placeholders that the fixture holds.

Before it writes the file, the tool checks the result for each secret that it searches everywhere, in each of these forms, in the strings and the numbers of request bodies, in token numbers of responses, and in the random values that it keeps. When one is still there, it writes nothing and fails. A run that fails writes no fixture either, so a failed login keeps the last good recording. It prints the replaced values by kind, such as "Replaced 1 username, 1 password, 2 cookies", and reminds the author that names, IBANs, and amounts are still in the fixture.

### Expected file and differences

The expected file has the format of the output of `ext run`. `ext test` compares the two documents. Numbers are equal when their values are equal, so `-89`, `-89.0`, and `-89.00` are the same. Each difference prints one line with its JSON Pointer and both values:

```
/accounts/0/transactions/0/amount: expected -89, got -98
```

A passing test prints "PASS 1 account, 4 transactions". `--update` writes the result to the expected file.

## Risks / Trade-offs

- A secret that a script hides in a way of its own, such as a hash or a Base64 block that holds more than the secret, stays in the fixture. The reminder after each recording and the review of the catalog cover it.
- A fixture of a changed script can lack a request, a random value, or an answer. The test then fails with the method and the URL, or uses counter values, and the author records again.
- The waits of a decoupled approval keep their pause of one second between calls during a replay.
- A login value or an answer that a server sends back in a response as a JSON number, or glued to letters or digits, stays in the fixture. A password with fewer than 8 characters or only digits stops the recording instead. Replacing it there would turn amounts and identifiers into placeholders and break the replay.
- During a replay, a question about a new host that the recording did not answer is allowed. The replay reaches no network, and the missing request then fails with its method and URL.
