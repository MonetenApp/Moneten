## ADDED Requirements

### Requirement: Mark a TAN that covers only the login

The app SHALL say in the dialog that the TAN is used for the login only when the bank asks for a TAN at login while the user is sending an order.

#### Scenario: Login TAN before a payment

- **GIVEN** the user started an order and the bank first asks for a TAN for the login
- **WHEN** the dialog opens
- **THEN** it says that this TAN is used only for the login and not for the order
