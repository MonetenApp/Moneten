## ADDED Requirements

### Requirement: Offer the newest crash report

The app SHALL offer the newest available crash report in a sheet after an unexpected quit.

#### Scenario: Crash diagnostic arrives

- **GIVEN** version 0.1.0 crashed and the system has delivered its diagnostic
- **WHEN** the user starts the app
- **THEN** a sheet says "Moneten quit unexpectedly the last time it ran. You can report the crash as an issue on GitHub. The report holds no account data. Read it before you send it."
- **AND** it shows the full report with "Report on GitHub...", "Copy Report", and "Don't Report"

#### Scenario: Normal quit

- **GIVEN** the user quit normally and no earlier report awaits a decision
- **WHEN** the user starts the app
- **THEN** no crash sheet appears

### Requirement: Keep a report until a decision

The app SHALL keep the newest pending diagnostic encrypted in its data folder until the user chooses one of the three actions.

#### Scenario: Decline once

- **GIVEN** the sheet shows a crash from November 15
- **WHEN** the user chooses "Don't Report" and starts the app again
- **THEN** that crash is not offered again, even if the system delivers it again
- **AND** its diagnostic is removed from storage

#### Scenario: Copy or report

- **WHEN** the user chooses "Copy Report" or "Report on GitHub..."
- **THEN** the pending diagnostic is removed from storage
- **AND** "Copy Report" copies the full report

### Requirement: Report without personal data

The app SHALL include only the app version, macOS version, exception type, signal, and crashed-thread frames as binary name, binary UUID, and offset in a crash report.

#### Scenario: Diagnostic contains personal text

- **GIVEN** diagnostic text fields contain "DE02120300000000202051", "Erika Mustermann", and "/Users/erika"
- **WHEN** the app builds the report
- **THEN** none of those values appears in it
- **AND** no free error text, home path, device identifier, installation identifier, or database identifier appears in it

### Requirement: Share only on request

The app SHALL send nothing without an explicit user action.

#### Scenario: Relaunch after a crash

- **WHEN** the app starts after a crash
- **THEN** it sends no report and opens no browser

#### Scenario: Open GitHub

- **WHEN** the user chooses "Report on GitHub..."
- **THEN** the browser opens the new issue form with bug-report.yml, version and macos filled in, and the report in the body
- **AND** the user submits the issue in the browser if they choose

#### Scenario: Long report

- **GIVEN** a report has 500 frames
- **WHEN** the user opens GitHub
- **THEN** the encoded URL has fewer than 8,000 characters
- **AND** a shortened report ends at a whole frame and says it was shortened
- **AND** "Copy Report" still provides all 500 frames

### Requirement: Prefill issue versions

The app SHALL fill the app and macOS versions in the bug report form opened by "Report an Issue..." in Help.

#### Scenario: Help without a crash

- **WHEN** the user chooses "Report an Issue..." in version 0.1.0 on macOS 15.2
- **THEN** the form's version field is "0.1.0" and its macos field is "15.2"
