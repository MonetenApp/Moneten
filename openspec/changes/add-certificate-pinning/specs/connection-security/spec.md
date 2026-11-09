# Spec Delta

## ADDED Requirements

### Requirement: Known certificates of bank servers

The app SHALL compare the certificate of a bank server with a list of known certificates after the normal validation has passed. A connection whose certificate is on the list for that host proceeds without a question.

#### Scenario: Certificate is on the list

- **GIVEN** the pin list holds the certificate of the FinTS server of "Musterbank"
- **WHEN** the app refreshes an account at "Musterbank" and the server presents that certificate
- **THEN** the refresh proceeds and no sheet appears

### Requirement: Signed pin list that updates between releases

The app SHALL take the list of known certificates from a data file that carries a signature of the project. The file ships with the app and updates between releases. A file with a missing or wrong signature is ignored, and the last valid list stays in use.

#### Scenario: New list arrives

- **GIVEN** "Musterbank" changed its certificate and the project published a new list
- **WHEN** the app has loaded the new list and refreshes the account
- **THEN** the refresh proceeds and no sheet appears

#### Scenario: Tampered list

- **GIVEN** a downloaded list whose signature does not verify
- **WHEN** the app loads it
- **THEN** the app discards it and keeps the list it had before

### Requirement: Ask the user about an unknown certificate

The app SHALL stop before the login and show the sheet "Verify SSL Certificate" when a bank server presents a valid certificate that is neither on the list nor accepted earlier. The sheet names the bank and the server, shows the subject, the issuer, the validity period, and the SHA-256 fingerprint, and asks the user to compare the fingerprint with the records of the bank. The buttons are "Accept" and "Reject".

#### Scenario: Bank renewed its certificate

- **GIVEN** the server of "Musterbank" presents a valid certificate that the list does not hold
- **WHEN** the user refreshes the account
- **THEN** the sheet "Verify SSL Certificate" appears with the SHA-256 fingerprint of the certificate
- **AND** the app has sent no login data yet

### Requirement: Explain likely causes on the sheet

The app SHALL state on the sheet that banks change their certificate about once a year and that antivirus or firewall software on the Mac can also cause the question. When macOS has a proxy server configured, the sheet adds that the proxy is the likely cause.

#### Scenario: No proxy

- **GIVEN** macOS has no proxy configured
- **WHEN** the sheet appears
- **THEN** it contains the note about the yearly change and about antivirus and firewall software
- **AND** it contains no note about a proxy

#### Scenario: Proxy configured

- **GIVEN** macOS has an HTTPS proxy configured
- **WHEN** the sheet appears
- **THEN** it also says that the proxy server is likely responsible

### Requirement: Reject an unknown certificate

The app SHALL end the connection without sending login data when the user chooses "Reject". The account shows that the certificate was rejected. The app asks again at the next refresh that the user starts.

#### Scenario: Reject

- **WHEN** the user chooses "Reject" on the sheet
- **THEN** the refresh of that bank ends with an error that says the certificate was not accepted
- **AND** the transactions and balances of the last refresh stay unchanged

### Requirement: Accept an unknown certificate

The app SHALL continue the connection when the user chooses "Accept", and it SHALL remember the fingerprint for that host. Later connections to the host with the same certificate proceed without a question. A different certificate leads to the sheet again.

#### Scenario: Accept and refresh again

- **GIVEN** the user accepted the certificate of "Musterbank"
- **WHEN** the next refresh runs and the server presents the same certificate
- **THEN** no sheet appears

#### Scenario: Certificate changes again

- **GIVEN** the user accepted a certificate of "Musterbank"
- **WHEN** the server later presents another certificate that is not on the list
- **THEN** the sheet appears again with the new fingerprint

### Requirement: An invalid certificate cannot be accepted

The app SHALL show the sheet only for a certificate that passed the normal validation. A certificate that is expired, issued for another host, or not trusted by macOS ends the connection with an error and without the choice to accept.

#### Scenario: Expired and unknown

- **GIVEN** a server presents an expired certificate that the list does not hold
- **WHEN** the user refreshes the account
- **THEN** the account shows the certificate error
- **AND** no sheet with "Accept" appears

### Requirement: Blocked certificates

The app SHALL refuse a connection whose certificate the list marks as blocked. The error says that the certificate of the bank's server is blocked. The user cannot accept such a certificate, also when the user accepted it earlier.

#### Scenario: Certificate was blocked after acceptance

- **GIVEN** the user accepted a certificate, and a newer list marks it as blocked
- **WHEN** the app refreshes the account
- **THEN** the connection is refused with the error that the certificate is blocked

### Requirement: No certificate question during an automatic refresh

The app SHALL NOT show the certificate sheet during an automatic refresh. It skips the accesses of that bank, marks the accounts as waiting for the user, and shows the sheet at the next refresh that the user starts.

#### Scenario: Background refresh meets a new certificate

- **GIVEN** the automatic refresh runs while the user works in another app
- **WHEN** the server of "Musterbank" presents an unknown certificate
- **THEN** no sheet appears
- **AND** the accounts at "Musterbank" show that the refresh waits for the user

#### Scenario: Manual refresh afterwards

- **WHEN** the user then refreshes "Musterbank"
- **THEN** the sheet "Verify SSL Certificate" appears

### Requirement: Scope of pinning

The app SHALL apply pinning to FinTS servers and to the aggregator. Hosts of extensions get the normal validation and no pinning, and no sheet appears for them.

#### Scenario: Extension host with a new certificate

- **GIVEN** the host of an extension renews its certificate with a valid one
- **WHEN** the app refreshes the account of the extension
- **THEN** the refresh proceeds and no sheet appears

### Requirement: Forget accepted certificates

The app SHALL offer a command on the "Security" tab of the settings that forgets every certificate that the user accepted. Certificates on the signed list are not affected.

#### Scenario: Reset

- **GIVEN** the user accepted certificates for two banks
- **WHEN** the user chooses the command to forget accepted certificates and confirms
- **THEN** the next refresh of either bank shows the sheet again, unless the list holds the certificate by then
