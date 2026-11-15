## ADDED Requirements

### Requirement: Offer the newest crash report

The app SHALL offer the newest available crash report in a sheet after an unexpected quit.

#### Scenario: Crash diagnostic arrives

- **GIVEN** version 0.1.0 crashed and the system has delivered its diagnostic
- **WHEN** the user starts the app
- **THEN** a sheet says "Moneten quit unexpectedly recently. You can report the crash as an issue on GitHub. The report holds no account data. Read it before you send it."
- **AND** it shows the full report with "Report on GitHub...", "Copy Report", and "Don't Report"

#### Scenario: Crash file without a diagnostic

- **GIVEN** version 0.1.0 started at 10:00 on November 15 and a file named "Moneten-2026-11-15.ips" has a modification time of 10:05
- **AND** the system has delivered no crash diagnostic
- **WHEN** the app starts at 10:06
- **THEN** the sheet shows app version 0.1.0, the macOS version, the crash time 10:05, and "No details were available."
- **AND** it offers "Report on GitHub...", "Copy Report", and "Don't Report"
- **AND** the app reads only crash file names and modification dates, never file contents

#### Scenario: Old files and force quit

- **GIVEN** the previous launch started at 10:00 on November 15
- **WHEN** no crash file exists after 10:00, including after a force quit or power loss
- **THEN** no new crash sheet appears
- **AND** files dated 09:59 and files for a helper or another app do not cause a sheet

#### Scenario: Upgrade and first launch

- **GIVEN** version 0.1.0 saved its launch time 10:00 and versions in the encrypted crash state
- **AND** a crash file is dated 10:05
- **WHEN** version 0.1.1 starts at 10:06
- **THEN** the short report describes version 0.1.0
- **AND** the new launch time replaces the previous launch time only after that check
- **AND** a first launch with no saved launch time records its start and offers no short report

#### Scenario: Delayed details

- **GIVEN** a short report for the crash at 10:05 awaits a decision
- **WHEN** a diagnostic covering 10:00 through 10:05 arrives later
- **THEN** the full report replaces the short report
- **AND** if the user already declined the short report, the diagnostic does not prompt again

#### Scenario: Main window closed

- **GIVEN** only the menu bar is open
- **WHEN** a crash report becomes available
- **THEN** the app opens the main window and presents the sheet

#### Scenario: Normal quit

- **GIVEN** the user quit normally and no earlier report awaits a decision
- **WHEN** the user starts the app
- **THEN** no crash sheet appears

### Requirement: Keep a report until a decision

The app SHALL keep the newest pending report encrypted in its data folder until the user decides.

#### Scenario: The encryption key is lost

- **GIVEN** a saved report from November 15 has no readable key, or its ciphertext cannot be decrypted
- **WHEN** the app reads it
- **THEN** it deletes that file and continues without saved state
- **AND** a new crash on November 16 can be saved and offered

#### Scenario: Decline once

- **GIVEN** the sheet shows a crash from November 15
- **WHEN** the user chooses "Don't Report" and starts the app again
- **THEN** that crash is not offered again, even if the system delivers it again
- **AND** its diagnostic is removed from storage

#### Scenario: Copy or report

- **WHEN** the user chooses "Copy Report" or opens GitHub with an uncut report
- **THEN** the pending report is removed from storage
- **AND** "Copy Report" copies the full report

#### Scenario: Open GitHub with a cut report

- **GIVEN** the report has 500 frames and cannot fit in the GitHub URL
- **WHEN** the user opens GitHub
- **THEN** the full report stays available in the sheet and encrypted storage
- **AND** it stays until the user chooses "Copy Report" or "Don't Report"

### Requirement: Report without personal data

The app SHALL include only the app version, macOS version, exception type, signal, and crashed-thread frames as binary name, binary UUID, and offset when details exist, or versions and the crash time when details are unavailable in a crash report.

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
- **THEN** the browser opens the new issue form with bug-report.yml, version and macos filled in, and the report only in the expected field
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

#### Scenario: Zero patch version

- **WHEN** the Help or crash path builds a report for macOS 15.2.0
- **THEN** it shows "15.2"
- **AND** macOS 15.2.1 remains "15.2.1"

### Requirement: Inject the diagnostic time

The app SHALL use the supplied crash time for an injected debug report.

#### Scenario: Older injected crash

- **GIVEN** the debug clock reads 10:10 on November 15
- **WHEN** the harness injects a report dated 10:05
- **THEN** the saved report time is 10:05
