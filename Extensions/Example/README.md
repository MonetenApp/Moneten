# Example Bank

A made-up web banking extension for the `ext` tool. It shows the parts that most extensions have:

- `InitializeSession` posts a login form and keeps a device identifier in `LocalStorage`.
- `ListAccounts` reads a JSON list.
- `RefreshAccount` reads an HTML page of the last 30 days with `HTML:xpath`.
- `EndSession` logs out.

The service `www.bank.example` does not exist. The recording in `Fixtures/example` replays it:

```sh
swift run --disable-keychain ext test Extensions/Example Fixtures/example/fixture.json Fixtures/example/expected.json
```

All names, IBANs, and amounts are invented.
