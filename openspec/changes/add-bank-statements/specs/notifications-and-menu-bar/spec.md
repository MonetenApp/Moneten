## ADDED Requirements

### Requirement: Notification about new statements

The app SHALL show one notification when a refresh run has downloaded new PDF statements and the banner setting is on. The notification states the number, for example that 2 new PDF statements have been downloaded. A click opens the "Statements" view.

#### Scenario: Two statements

- **WHEN** a refresh run downloads 2 new statements
- **THEN** the app shows one notification that says 2 new PDF statements have been downloaded

#### Scenario: Click

- **WHEN** the user clicks that notification
- **THEN** the main window comes to the front with "Statements" selected
