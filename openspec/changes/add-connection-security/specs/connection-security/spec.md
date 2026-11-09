# Spec Delta

## Purpose

The app sends bank login data and receives account data over the network. This capability defines how every connection is protected, which hosts the app contacts, how it uses a proxy, and what the user sees when a connection fails.

## ADDED Requirements

### Requirement: Direct connections

The app SHALL exchange login data and account data directly with the server of the bank or with the service that an extension connects to. No server of the project and no other intermediary sees this data. The only exception is the aggregator, and only for accounts that the user connected through the subscription.

#### Scenario: FinTS refresh

- **GIVEN** an account with FinTS access at "Musterbank"
- **WHEN** the app refreshes the account
- **THEN** every connection of that refresh goes to the FinTS address of "Musterbank"

#### Scenario: No subscription

- **GIVEN** the user has no subscription
- **WHEN** the app refreshes all accounts
- **THEN** the app opens no connection to the aggregator

### Requirement: Encrypted transport only

The app SHALL use TLS 1.2 or a newer version for every network connection. It SHALL NOT open a connection without encryption, and it SHALL NOT fall back to an older protocol version when a server refuses the handshake.

#### Scenario: Server offers only an old protocol

- **GIVEN** a server that supports nothing newer than TLS 1.0
- **WHEN** the app connects to it
- **THEN** the connection fails
- **AND** the app sends no login data

#### Scenario: Plain HTTP address

- **GIVEN** an extension that requests an address that starts with `http://`
- **WHEN** the extension sends the request
- **THEN** the app refuses the request and reports an error to the extension

### Requirement: Certificate validation

The app SHALL validate the certificate of every server before it sends any data. The certificate must be issued for the host name, be within its validity period, and chain to a root that macOS trusts.

#### Scenario: Expired certificate

- **GIVEN** the FinTS server of a bank presents a certificate that expired yesterday
- **WHEN** the app refreshes an account at that bank
- **THEN** the connection stops before the login
- **AND** the account shows an error that says the certificate of the bank's server is invalid and names the server address

#### Scenario: Wrong host name

- **GIVEN** a server presents a valid certificate for another host name
- **WHEN** the app connects
- **THEN** the connection stops and the app sends no login data

### Requirement: No way around a failed validation

The app SHALL NOT offer to continue after a failed certificate validation, and no setting turns the validation off. This also holds for connections of extensions.

#### Scenario: User wants to continue

- **GIVEN** a refresh failed because of an invalid certificate
- **WHEN** the user reads the error
- **THEN** the error offers no button that continues with the connection

#### Scenario: Extension asks to skip the check

- **GIVEN** an extension that connects to a host with a self-signed certificate
- **WHEN** the extension sends a request
- **THEN** the request fails with a certificate error and the extension cannot override it

### Requirement: No downgrade through redirects

The app SHALL NOT follow a redirect from an encrypted address to an address without encryption.

#### Scenario: Redirect to HTTP

- **GIVEN** a server answers a request to `https://bank.example/login` with a redirect to `http://bank.example/login`
- **WHEN** the app receives the redirect
- **THEN** the app does not open the second address and reports an error

### Requirement: Contact only known hosts

The app SHALL open connections only to the bank servers of accesses that the user set up, to the hosts that an installed extension declares, to the update source, and to the aggregator when the user subscribed. It contacts a bank or an extension host only for an access of the user.

#### Scenario: Fresh installation

- **GIVEN** a fresh installation with no account
- **WHEN** the app runs for an hour with the update check on
- **THEN** the only host that the app contacted is the update source

#### Scenario: Access removed

- **GIVEN** the user removed the only access at "Musterbank"
- **WHEN** the next automatic refresh runs
- **THEN** the app opens no connection to "Musterbank"

### Requirement: Show the hosts that the app contacts

The app SHALL show a list of every host that it contacts, with the reason for each, in a place that the user can open from the Help menu or the settings. The app SHALL also carry this list as an Internet Access Policy that firewall tools can read.

#### Scenario: Read the list

- **GIVEN** accounts at "Musterbank" through FinTS and one extension for "Beispiel Broker"
- **WHEN** the user opens the list of connections
- **THEN** the list shows the FinTS host of "Musterbank" with the reason that it is the user's bank, the host of "Beispiel Broker" with the name of the extension, and the update source

#### Scenario: Firewall tool

- **GIVEN** a firewall tool that reads Internet Access Policies
- **WHEN** the app connects to the update source for the first time
- **THEN** the tool can show the purpose of that connection from the policy of the app

### Requirement: No telemetry

The app SHALL send no usage data, no analytics, and no crash report on its own. A crash report leaves the Mac only when the user sends it.

#### Scenario: Normal use

- **WHEN** the user works with the app for a day
- **THEN** the app sends nothing to a server of the project except the update check

#### Scenario: Crash

- **GIVEN** the app crashed
- **WHEN** the user starts it again
- **THEN** the app sends no report unless the user chooses to send one

### Requirement: No personal data outside bank connections

The app SHALL send no account data, no login data, and no identifier of the device, the installation, or the database in a request to the update source or to any host that is not the bank or service of the access in use.

#### Scenario: Update check

- **WHEN** the app checks for an update
- **THEN** the request carries the app version and the macOS version
- **AND** it carries no identifier that is the same from one check to the next

### Requirement: Use the proxy settings of macOS

The app SHALL send its connections through the HTTPS or SOCKS proxy that is set in the macOS network settings. Certificate validation still applies to the certificate of the bank's server. When the proxy refuses a connection, the error quotes the answer of the proxy and its address.

#### Scenario: SOCKS proxy

- **GIVEN** macOS is set to a SOCKS proxy
- **WHEN** the app refreshes an account
- **THEN** the connection to the bank runs through the proxy and the refresh succeeds

#### Scenario: Proxy refuses

- **GIVEN** an HTTPS proxy that answers "403 Forbidden" for the bank's host
- **WHEN** the app refreshes the account
- **THEN** the account shows an error with the answer "403 Forbidden" and the address of the proxy

#### Scenario: Proxy replaces the certificate

- **GIVEN** a proxy that presents its own certificate for the bank's host and that macOS does not trust
- **WHEN** the app refreshes the account
- **THEN** the connection stops with a certificate error
- **AND** the error notes that a proxy is configured and is the likely cause

### Requirement: IPv4 and IPv6

The app SHALL reach a server over IPv4 or IPv6, whichever the network offers. When one of them fails, the app uses the other without an action from the user.

#### Scenario: Broken IPv6 route

- **GIVEN** a bank host with addresses for IPv4 and IPv6, and a network whose IPv6 route does not work
- **WHEN** the app refreshes the account
- **THEN** the refresh succeeds over IPv4

### Requirement: Connection errors name the cause

The app SHALL tell these causes apart in the error of an account. They are no Internet connection, a server that cannot be reached, a lost connection, a timeout, an invalid certificate, and a connection that security software on the Mac blocked. The error names the bank and, where it helps, the server address and port, and it says what the user can check.

#### Scenario: Mac is offline

- **GIVEN** the Mac has no network
- **WHEN** the user refreshes all accounts
- **THEN** each account shows that there is no Internet connection
- **AND** the app does not show one dialog for each account

#### Scenario: Bank server down

- **GIVEN** the Mac is online and the FinTS server of "Musterbank" does not accept connections
- **WHEN** the user refreshes the account
- **THEN** the account shows that the app cannot connect to the FinTS server of "Musterbank", with the server address and port 443, and the advice to check Internet, firewall, and antivirus settings

#### Scenario: Blocked by security software

- **GIVEN** a firewall tool on the Mac denies the connection of the app
- **WHEN** the user refreshes the account
- **THEN** the account shows that antivirus or firewall software blocked the connection and that the app cannot reach the bank until the user allows it

### Requirement: Timeouts

The app SHALL end a connection that receives no answer for 30 seconds and show a timeout error for the account. The user can cancel a waiting connection at any time. A timeout of one bank does not delay the refresh of other banks.

#### Scenario: Server does not answer

- **GIVEN** the server of "Musterbank" accepts the connection and then sends nothing
- **WHEN** 30 seconds have passed
- **THEN** the account shows that the connection to the bank timed out and that the user can try again later

#### Scenario: Other banks continue

- **GIVEN** a refresh of all accounts in which "Musterbank" does not answer
- **WHEN** the refresh runs
- **THEN** the accounts of the other banks finish their refresh without waiting for "Musterbank"

### Requirement: No immediate repeat after a connection error

The app SHALL NOT repeat a failed refresh of an access on its own within the same refresh run. The next scheduled refresh or the next refresh that the user starts tries again.

#### Scenario: Timeout during an automatic refresh

- **GIVEN** the automatic refresh of "Musterbank" timed out at 10:00 and the interval is two hours
- **WHEN** the app keeps running
- **THEN** the app contacts "Musterbank" again at 12:00 and not before, unless the user starts a refresh
