## ADDED Requirements

### Requirement: Country menu

The app SHALL offer a country menu in the first step with the entries for Germany, Austria, and the European Union. The selected country decides which banks the app finds and which services "Other" lists. The menu starts with Germany.

#### Scenario: Service of another country

- **GIVEN** an installed extension declares a service for Austria only
- **WHEN** the user selects Austria in the country menu
- **THEN** "Other" lists that service
- **AND** "Other" does not list it while Germany is selected

### Requirement: Choose the access method

The app SHALL show the access methods that are possible for the bank under "Access with" when there is more than one, and it SHALL let the user choose one. A method that the app knows and that the bank does not offer is listed as disabled with its reason.

#### Scenario: Bank with FinTS and an extension

- **GIVEN** "Musterbank" offers FinTS with a TAN method, and an installed extension also supports "Musterbank"
- **WHEN** the user enters the Bankleitzahl of "Musterbank"
- **THEN** "Access with" lists "FinTS/HBCI with TAN method" and the extension
- **AND** "FinTS/HBCI with TAN method" is selected

#### Scenario: Only one method

- **GIVEN** "Musterbank" offers only FinTS with a TAN method and no extension supports it
- **WHEN** the user enters its Bankleitzahl
- **THEN** the app shows no choice and continues with FinTS

### Requirement: Switch the access method and keep the history

The app SHALL let the user choose another access method for an existing access in "Edit Login Data...". After the switch every account keeps its transactions, categories, comments, and settings.

#### Scenario: From an extension to FinTS

- **GIVEN** the account "Giro" with 1,200 transactions uses an extension, and the bank now offers FinTS
- **WHEN** the user chooses "Edit Login Data...", selects "FinTS/HBCI with TAN method", enters the login data, and confirms
- **THEN** "Giro" still has its 1,200 transactions
- **AND** the next refresh of "Giro" runs through FinTS

#### Scenario: Account not available with the new method

- **GIVEN** an access with a giro account and a credit card
- **WHEN** the user switches to a method through which the bank reports only the giro account
- **THEN** the app says that the credit card is not available with the new method and asks whether to continue
- **AND** when the user continues, the credit card stays in the app with its transactions and is no longer refreshed
