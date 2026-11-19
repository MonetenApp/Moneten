## MODIFIED Requirements

### Requirement: Only the listed version runs

The app SHALL let an installed catalog extension run only while the accepted index lists its installed version. The index lists one version of each package. An installed version that is not the listed version does not run. When the listed version is newer, its refreshes stop with a message that says to install the update, and the "Extensions" window offers the update. When the listed version is older, the message says so and the window offers no update.

#### Scenario: Update waits for the user

- **GIVEN** "Broker" 2.31 is installed and the update to 2.32 waits for the user
- **AND** the accepted index lists only 2.32
- **WHEN** a refresh of "Broker Depot" starts
- **THEN** "Broker" does not run, and "Broker Depot" says "Version 2.31 of Broker is no longer in the catalog. Open Extensions and install the update."
- **AND** the window shows "Broker" with the badge "Update Needed" and the button "Update" or "Review Update"

#### Scenario: Automatic update failed

- **GIVEN** "Broker" 2.31 is installed, "Update extensions automatically" is on, and the accepted index lists only 2.32
- **AND** 2.32 adds no host and no login field
- **WHEN** the download of 2.32 fails, because the Mac is offline or a file does not match its digest
- **THEN** the window shows "Broker" with the badge "Update Needed" and the button "Update"
- **AND** "Update" downloads 2.32 again and installs it when every file matches

#### Scenario: Listed version

- **GIVEN** "Broker" 2.32 is installed and the accepted index lists 2.32
- **WHEN** a refresh of "Broker Depot" starts
- **THEN** "Broker" 2.32 runs after its files match the digests that the index lists

#### Scenario: The catalog lists an older version

- **GIVEN** "Broker" 1.1 is installed
- **AND** the accepted index lists only 1.0
- **WHEN** a refresh of "Broker Depot" starts
- **THEN** "Broker" does not run, and "Broker Depot" says "The catalog lists version 1.0 of Broker, which is older than the installed version 1.1. There is no update to install."
- **AND** the window shows "Broker" with the badge "Stopped" and without the button "Update" or "Review Update"
