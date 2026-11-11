# Spec Delta

## Purpose

The settings window is the one place for switches that the user sets once. This capability defines the window, its tabs, and the rules that all settings share. Each single setting belongs to the capability that owns its behavior.

## ADDED Requirements

### Requirement: One settings window

The app SHALL open one settings window when the user chooses "Settings..." in the application menu or presses ⌘,. The window has the tabs "General", "Security", "Payments", "Subscription", and "Extensions", and it opens on the tab that was open last.

#### Scenario: Open with the shortcut

- **WHEN** the user presses ⌘,
- **THEN** the settings window opens

#### Scenario: Window already open

- **GIVEN** the settings window is open behind the main window
- **WHEN** the user presses ⌘,
- **THEN** the same window comes to the front and no second window opens

#### Scenario: Last tab

- **GIVEN** the user closed the settings window on the "Security" tab
- **WHEN** the user opens the settings again
- **THEN** the window shows the "Security" tab

### Requirement: A tab appears with its settings

The app SHALL show a tab in the settings window only when the installed version has at least one setting on that tab.

#### Scenario: Version without payments

- **GIVEN** a version of the app without payment features
- **WHEN** the user opens the settings
- **THEN** the window has no "Payments" tab

### Requirement: Changes take effect at once

The app SHALL apply a changed setting at once, without a button to save. When a setting needs a restart of the app, the app says so next to the setting when the user changes it.

#### Scenario: Immediate effect

- **WHEN** the user turns on "Show Moneten icon in menu bar"
- **THEN** the icon appears in the menu bar while the settings window is still open

#### Scenario: Restart needed

- **WHEN** the user changes "Language" from English to German
- **THEN** the app shows that it must be restarted for the change to take effect

### Requirement: Settings survive restarts and updates

The app SHALL keep every setting when the app restarts and when a new version of the app is installed.

#### Scenario: Update

- **GIVEN** "Automatically refresh accounts" is off in version 0.1
- **WHEN** the user installs version 0.2 and starts it
- **THEN** "Automatically refresh accounts" is still off

### Requirement: Settings hold no personal data

The app SHALL store settings outside the encrypted database, so that it can read them before the database is open. A stored setting contains no account name, IBAN, balance, counterparty, or login data.

#### Scenario: Inspect the stored settings

- **GIVEN** an app with an account that has the IBAN DE02120300000000202051
- **WHEN** a person reads the stored settings of the app without the database password
- **THEN** the settings contain neither the IBAN nor the name of the account

#### Scenario: Language before unlock

- **GIVEN** "Language" is German and a database password is set
- **WHEN** the user starts the app
- **THEN** the lock screen is in German

### Requirement: Report a setting that cannot be stored

The app SHALL tell the user when it cannot store a changed setting, and it SHALL show the setting with its earlier value.

#### Scenario: Storage fails

- **WHEN** the user changes "Language" and macOS refuses to store the value
- **THEN** the app shows that the setting could not be stored
- **AND** "Language" shows the earlier value

### Requirement: Explain settings with consequences

The app SHALL show a short explanation below each setting whose effect is not clear from its label alone.

#### Scenario: Payment setting

- **WHEN** the user opens the "Payments" tab
- **THEN** the text below "Save new payments in outbox by default" explains that new transfers are collected in the outbox and are not sent to the bank at once

### Requirement: Settings need an unlocked app

The app SHALL NOT open the settings window while the app is locked, and it SHALL hide an open settings window when the app locks.

#### Scenario: Locked app

- **GIVEN** the app is locked
- **WHEN** the user presses ⌘,
- **THEN** no settings window opens
