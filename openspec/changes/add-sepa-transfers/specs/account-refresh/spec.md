## ADDED Requirements

### Requirement: Refresh after a payment

The app SHALL refresh an account after the bank accepted a payment from that account, so that the payment appears in the list.

#### Scenario: Transfer sent

- **WHEN** the bank accepts a transfer of 120,00 € from "Giro"
- **THEN** the app refreshes "Giro" without a command
