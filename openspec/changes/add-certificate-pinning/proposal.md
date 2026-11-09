# Proposal: Pin the certificates of bank servers

## Why

Certificate validation trusts every certificate authority that macOS trusts. One wrongly issued certificate, or a root that security software added to the Mac, is enough to read a bank login. Pinning closes that gap. The app accepts a bank server only with a certificate that it already knows, and it asks the user when the certificate is new.

## What Changes

- The app compares the certificate of a bank server with a signed list of known certificates, in addition to the normal validation.
- For a certificate that is not on the list, a sheet shows the certificate and its SHA-256 fingerprint. The user compares it with the records of the bank and chooses "Accept" or "Reject".
- An accepted certificate is remembered for its host.
- The list can block a certificate.
- The list updates between app releases and carries a signature.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `connection-security`: adds the pinning of bank server certificates and the check of unknown certificates by the user. The change `add-connection-security` introduces the capability.

## Impact

- Milestone: later
- Issues: none yet
- Modules: `FinTSConnector` and `FinAPIConnector` check the pin of each connection. `Storage` keeps the accepted fingerprints. `App` owns the sheet and the reset command.
- Depends on the change `add-connection-security` for the validation that runs first, `add-software-update` for the signed data files that update between releases, `add-account-refresh` for the state of an account that waits for the user, and `add-app-settings` for the "Security" tab.
- Decisions: none apply.

## Reference behavior

### Observed in MoneyMoney 2.5.3

- The app checks SSL certificates not only for formal correctness but also against a whitelist. When the app does not know the certificate of a server yet, it shows the certificate for confirmation, and the user can compare its fingerprint with the records of the bank or reject the connection ([security page](https://moneymoney.app/security/)).
- The whitelist is fetched online (version history, 2.1.8).
- The bundle contains a sheet for the certificate check. Strings show the title "Verify SSL Certificate", "SHA256 fingerprint of" a server, the buttons "Accept" and "Reject", a note that banks change their certificate once a year and that antivirus or firewall software can cause the message, and a note that a proxy server is likely responsible when macOS has one configured. See [analysis](../../../docs/research/moneymoney-analysis.md#windows-sheets-and-popovers-s).
- FinTS message strings show an error for a certificate that is blacklisted, and an error for a certificate that does not match its entry in the whitelist yet, with the advice to try again the next day.

### Decided for MonetenMoneten

- The pin list ships with the app and updates through the signed data files of the update source. MoneyMoney fetches its list from the vendor's service.
- The sheet appears only after the normal validation passed. A certificate that macOS rejects cannot be accepted.
- A certificate that differs from the entry in the list is treated like an unknown certificate, and the user decides. MoneyMoney refuses such a connection and asks the user to wait for a list update.
- During an automatic refresh the app does not show the sheet. The account waits for the next refresh that the user starts.
- Pinning covers FinTS servers and the aggregator. Hosts of extensions are validated but not pinned.
- A command in the "Security" tab forgets all accepted certificates. MoneyMoney has a hidden preference for that.
- The sheet shows the subject, the issuer, and the validity period next to the fingerprint. Only the fingerprint was observed.
