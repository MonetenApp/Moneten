# Spec Delta

## Purpose

A banking app must stay current, and the user must be able to trust every version of it. This capability defines how the app proves where it comes from, how it finds, checks, and installs new versions, and how its bank data files stay current between releases.

## ADDED Requirements

### Requirement: Signed and notarized app

The app SHALL be signed with the Developer ID of the project and notarized by Apple, so that macOS opens a freshly downloaded copy without a warning about an unidentified developer.

#### Scenario: First open after download

- **GIVEN** a Mac with the default security settings of macOS
- **WHEN** the user downloads the app from the release page and opens it
- **THEN** macOS asks only whether to open an app that was downloaded from the internet
- **AND** macOS names the project as the developer

### Requirement: Check for updates on request

The app SHALL offer "Check for Updates..." in the application menu. The command shows "Checking for updates..." and then either the update window or the message that the app is up to date.

#### Scenario: No newer version

- **GIVEN** version 0.1.2 is installed and is the newest version
- **WHEN** the user chooses "Check for Updates..."
- **THEN** the app shows "You're up-to-date!" and names version 0.1.2 as the newest version available

#### Scenario: Newer version

- **GIVEN** version 0.1.2 is installed and version 0.1.3 is published
- **WHEN** the user chooses "Check for Updates..."
- **THEN** the update window offers version 0.1.3

### Requirement: Check for updates automatically

The app SHALL look for a new version at launch and then once a day while it runs, if the setting "Show notification about new versions of Moneten" is on. The setting is on by default. With the setting off, the app looks for a new version only on request, and once at launch on a macOS that the installed version was not checked with.

#### Scenario: Setting on

- **GIVEN** the setting is on and version 0.1.3 was published yesterday
- **WHEN** the user starts version 0.1.2
- **THEN** the update window appears

#### Scenario: Setting off

- **GIVEN** the setting is off
- **WHEN** the user starts the app and uses it for two days
- **THEN** the app sends no request for a new version

### Requirement: Update window

The app SHALL announce a new version in a window that names the new version and the installed version, shows the release notes, and offers "Install" and "Remind Me Later".

#### Scenario: Release notes

- **WHEN** the update window appears for version 0.1.3
- **THEN** the window shows what changed in version 0.1.3
- **AND** the buttons "Install" and "Remind Me Later" are available

#### Scenario: Release notes cannot be loaded

- **WHEN** the release notes cannot be loaded
- **THEN** the window says that the release notes could not be displayed
- **AND** "Install" still works

### Requirement: Release notes match the release page

The app SHALL show in the update window, for each version it lists, the same release notes that the release page of the project shows for that version, headed by the version number and the release date.

#### Scenario: Same entries as the release page

- **GIVEN** the release page of version 0.1.3 from 2026-11-20 lists "Larger display of photoTAN images" and "Fixed the sum of a split transaction"
- **WHEN** the update window offers version 0.1.3
- **THEN** the release notes start with the heading for version 0.1.3 and the date 2026-11-20
- **AND** they list "Larger display of photoTAN images" and "Fixed the sum of a split transaction"

#### Scenario: Link in an entry

- **GIVEN** an entry of version 0.1.3 links "Creating transfers" to https://github.com/alexander-schneider/Moneten/wiki/Transfers
- **WHEN** the user clicks "Creating transfers" in the update window
- **THEN** https://github.com/alexander-schneider/Moneten/wiki/Transfers opens in the default browser

### Requirement: Release notes of skipped versions

The app SHALL show in the update window the release notes of every version that is newer than the installed version, up to the offered version, newest first. When the offered version is a stable version, the notes of pre-release versions are left out. The notes of a pre-release version of a stable version that the window lists are left out too, because the stable version lists them.

#### Scenario: Two versions skipped

- **GIVEN** version 0.1.1 is installed and versions 0.1.2 and 0.1.3 are published
- **WHEN** the update window offers version 0.1.3
- **THEN** the window shows the notes of version 0.1.3 and then those of version 0.1.2
- **AND** the window shows no notes of version 0.1.1

#### Scenario: Stable version after pre-releases

- **GIVEN** version 0.1.3 is installed and versions 0.2.0-beta.1 and 0.2.0 are published
- **WHEN** the update window offers version 0.2.0
- **THEN** the window shows the notes of version 0.2.0 only

#### Scenario: Pre-release offered

- **GIVEN** version 0.1.3 is installed, the beta setting is on, and versions 0.2.0-beta.1 and 0.2.0-beta.2 are published
- **WHEN** the update window offers version 0.2.0-beta.2
- **THEN** the window shows the notes of version 0.2.0-beta.2 and then those of version 0.2.0-beta.1

#### Scenario: Pre-release offered after a stable version

- **GIVEN** version 0.1.3 is installed, the beta setting is on, and versions 0.2.0-beta.1, 0.2.0, and 0.2.1-beta.1 are published
- **WHEN** the update window offers version 0.2.1-beta.1
- **THEN** the window shows the notes of version 0.2.1-beta.1 and then those of version 0.2.0
- **AND** the window shows no separate notes of version 0.2.0-beta.1

### Requirement: Remind later

The app SHALL close the update window without changes when the user chooses "Remind Me Later", and it SHALL offer the same version again at the next automatic check.

#### Scenario: Postpone

- **WHEN** the user chooses "Remind Me Later" for version 0.1.3 and starts the app the next day
- **THEN** the update window offers version 0.1.3 again

### Requirement: Download and install

The app SHALL, after "Install", download the update with visible progress, install it in place of the running version, and start the new version. The data folder is not changed by the installation.

#### Scenario: Successful update

- **GIVEN** version 0.1.2 with 3 accounts
- **WHEN** the user chooses "Install" for version 0.1.3
- **THEN** the app shows "Downloading update..." with progress
- **AND** version 0.1.3 starts and shows the 3 accounts after the user has unlocked it

### Requirement: Verify the update before installing it

The app SHALL install an update only when the download carries a signature made with the update key of the project and the new app inside has a valid code signature. The app discards any other download.

#### Scenario: Manipulated download

- **GIVEN** a download whose content was changed on the way
- **WHEN** the app checks the download
- **THEN** the app does not install it and shows that it could not install the update
- **AND** the running version keeps working

### Requirement: No update during a bank dialog

The app SHALL NOT quit for an update while a refresh, a bank dialog, or a payment is in progress. It installs the update when that work has ended.

#### Scenario: Payment in progress

- **GIVEN** the user is entering a TAN for a transfer
- **WHEN** a downloaded update is ready to install
- **THEN** the app waits until the transfer has ended before it restarts

### Requirement: Report a failed check

The app SHALL tell the user when a requested check for updates fails, with the reason, and it SHALL name the release page for a manual check. A failed automatic check shows no message and is tried again at the next launch.

#### Scenario: No network on request

- **GIVEN** the Mac is offline
- **WHEN** the user chooses "Check for Updates..."
- **THEN** the app shows that it could not check for updates and why
- **AND** the message names the release page of the project

#### Scenario: No network at launch

- **GIVEN** the Mac is offline
- **WHEN** the user starts the app
- **THEN** no update message appears

### Requirement: Report a failed installation

The app SHALL keep the running version intact when an update cannot be installed. It shows that the update could not be installed and offers the manual download from the release page.

#### Scenario: No permission to replace the app

- **GIVEN** the user account must not write to the Applications folder
- **WHEN** the installation of the update fails
- **THEN** the app shows that it could not install the update
- **AND** the installed version still starts

### Requirement: Ask to move the app to the Applications folder

The app SHALL refuse to update itself while macOS runs it from a temporary, read-only location, and it SHALL ask the user to move the application file to the Applications folder first.

#### Scenario: Started from the Downloads folder

- **GIVEN** the user started the app from the Downloads folder right after the download
- **WHEN** the user chooses "Install" in the update window
- **THEN** the app asks the user to drag the application file to the Applications folder and to start the update from there

### Requirement: Warn about several copies

The app SHALL warn the user at launch when it finds more than one copy of the app on the Mac. The warning names the places of the copies and asks the user to delete the unused ones. Copies on a disk image, on a read-only volume, and in the Trash do not count.

#### Scenario: Old copy in Downloads

- **GIVEN** version 0.1.3 in the Applications folder and version 0.1.1 in the Downloads folder
- **WHEN** the user starts version 0.1.3
- **THEN** the app warns that several copies are installed and names both places

#### Scenario: Disk image still mounted

- **GIVEN** version 0.1.3 in the Applications folder and the disk image of version 0.1.3 still mounted
- **WHEN** the user starts version 0.1.3
- **THEN** the app shows no warning about several copies

### Requirement: Report a damaged application file

The app SHALL, when it finds at launch that its own application file is damaged, ask the user to move the file to the Trash and install the app again. The message says that the accounts stay, because the data is stored in another place.

#### Scenario: Incomplete copy

- **GIVEN** an application file that was copied incompletely
- **WHEN** the user starts the app and the app can still show a window
- **THEN** the app shows the message and opens no database

### Requirement: Respect the system requirements of a new version

The app SHALL NOT offer a new version that the installed macOS cannot run. It tells the user which version of macOS the newest version needs, and the installed version keeps working.

#### Scenario: macOS too old

- **GIVEN** a Mac with macOS 14 and a newest version of the app that needs macOS 15
- **WHEN** the user chooses "Check for Updates..."
- **THEN** the app shows that the newest version needs macOS 15 or later
- **AND** the app offers no installation

### Requirement: Warn on an untested macOS

The app SHALL tell the user at launch when the installed version of the app was released before the major version of macOS that is running, and that it has not been checked with that macOS. The app then looks for an update, also when the automatic check is off.

#### Scenario: New macOS

- **GIVEN** version 0.1.2 was released for macOS 15 and the Mac was upgraded to macOS 16
- **WHEN** the user starts the app
- **THEN** the app shows that version 0.1.2 has not been checked with macOS 16
- **AND** the app looks for a newer version

### Requirement: Pre-release versions on request

The app SHALL offer pre-release versions as updates only while "Participate in beta tests and display pre-release versions" is on. The setting is off by default.

#### Scenario: Beta on

- **GIVEN** version 0.1.3 is installed, the setting is on, and the pre-release 0.2.0-beta.1 is published
- **WHEN** the app checks for updates
- **THEN** the update window offers 0.2.0-beta.1 and marks it as a pre-release

#### Scenario: Beta off

- **GIVEN** the same versions and the setting is off
- **WHEN** the app checks for updates
- **THEN** the app shows that it is up to date

#### Scenario: Leave the beta

- **GIVEN** 0.2.0-beta.1 is installed
- **WHEN** the user turns the setting off
- **THEN** the app stays on 0.2.0-beta.1 and next offers the stable version 0.2.0

### Requirement: Update requests send no personal data

The app SHALL send only the version of the app, the version of macOS, and the processor type when it looks for a new version or for new data files. It sends no identifier of the user, of the installation, or of any account.

#### Scenario: Inspect the request

- **WHEN** a person records the network traffic of an update check
- **THEN** the request contains the app version, the macOS version, and the processor type
- **AND** the request contains no user name, no installation identifier, and no bank data

### Requirement: Bank data files update between releases

The app SHALL update its list of banks with their server addresses and its BIC directory between releases of the app. It looks for new files at most once a day, installs a file only when its signature was made with the update key of the project, and keeps its current files otherwise.

#### Scenario: Bank changes its server address

- **GIVEN** a bank moved its FinTS server and the project published a new bank list
- **WHEN** the app has run for a day
- **THEN** the app uses the new address without an update of the app

#### Scenario: Unsigned file

- **WHEN** the app downloads a bank list with a wrong signature
- **THEN** the app keeps its current bank list
- **AND** the log holds an entry about the rejected file

### Requirement: Mark pre-release versions

The app SHALL show the build number next to the version number in "About Moneten", and it SHALL mark a pre-release version as a pre-release there.

#### Scenario: Pre-release

- **WHEN** the user opens "About Moneten" in version 0.2.0-beta.1
- **THEN** the window shows "0.2.0-beta.1", the build number, and a mark that this is a pre-release
