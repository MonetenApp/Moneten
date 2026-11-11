# Proposal: Secure every connection and contact only what the user set up

## Why

The app sends bank login data over the network. A user must be able to trust two things. Nobody can read or change what travels between the Mac and the bank, and the app talks to nobody else. Without both, no other security feature of the app counts.

## What Changes

- Every connection uses TLS 1.2 or newer with full certificate validation. There is no fallback to plain HTTP or to older protocol versions, and there is no way to continue after a failed validation.
- Account data travels directly between the Mac and the bank or the service of an extension.
- The app contacts only the servers of accesses that the user set up, the hosts of installed extensions, the update source, and the aggregator when the user subscribed. The app shows this list.
- The app sends no telemetry and no identifiers.
- The app uses the proxy settings of macOS.
- Connection errors say what failed and what the user can do.

## Capabilities

### New Capabilities

- `connection-security`: transport encryption, certificate validation, the set of hosts that the app contacts, proxy use, and connection errors.

### Modified Capabilities

None.

## Impact

- Milestone: v0.1
- Issues: #13, #26
- Modules: `FinTSConnector`, `ExtensionHost`, and later `FinAPIConnector` open connections and follow these rules. `App` shows the list of hosts and the errors.
- Depends on the change `add-account-refresh` for where the error of an account is shown, `add-web-banking-extensions` for the hosts that an extension declares, and `add-software-update` for the update source.
- Decisions: [ADR 0002](../../../docs/decisions/0002-local-first-no-server.md), [ADR 0007](../../../docs/decisions/0007-optional-finapi-subscription.md).

## Reference behavior

### Observed in MoneyMoney 2.5.3

- With FinTS, API access, and web scraping, the data travels directly between the computer and the bank server with no service in between, and the connection is secured with HTTPS as in a web browser ([security page](https://moneymoney.app/security/)).
- Only the PSD2 online service passes data through a server of the developer, and only after explicit consent ([security page](https://moneymoney.app/security/)).
- The bundle contains an Internet Access Policy for firewall tools. It names the developer's service for updates and bank server settings with the note that no personal information is sent, the PSD2 online service, and bank servers in general on port 443. See [analysis](../../../docs/research/moneymoney-analysis.md#network-s-w).
- HTTPS and SOCKS proxy servers are supported (version history, 2.1.6). Strings show errors that quote the answer and the address of the proxy.
- SSLv3 is disabled (version history, 2.2.0). Bank websites that moved to TLS 1.3 are supported (version history, 2.4.69).
- Connections preferred IPv6 over IPv4 in one version, and the next version took that back because of problems (version history, 2.4.30 and 2.4.31).
- FinTS message strings show separate errors for no Internet connection, a server that cannot be reached with its address and port, a timeout, a lost connection, an invalid certificate, and a connection that antivirus or firewall software blocked.

### Decided for Moneten

- The lowest protocol version is TLS 1.2. MoneyMoney's lowest version was not observed.
- No host gets an exception. MoneyMoney's `Info.plist` allows an insecure connection for one credit card domain.
- The app sends no device identifier and no database identifier. MoneyMoney's settings hold both.
- The list of hosts is visible inside the app, in addition to the policy file for firewall tools.
- A connection attempt ends after 30 seconds without an answer. The value in MoneyMoney was not observed.
- The app follows no redirect from HTTPS to HTTP.
- The app lets macOS choose between IPv4 and IPv6 and does not prefer one.
- A failed refresh is not repeated at once. The next scheduled or manual refresh tries again.
- Crash reports are sent only when the user chooses to, as [ADR 0002](../../../docs/decisions/0002-local-first-no-server.md) says.
