# Design

## Context

This change is part of the first build of the app. The build is a Swift package with the modules `Domain`, `Storage`, `Import`, and `App`, as [ADR 0010](../../../docs/decisions/0010-swift-package-and-macos-15.md) describes. Everything runs on the Mac, with no server ([ADR 0002](../../../docs/decisions/0002-local-first-no-server.md)).

The app keeps all accounts, categories, and transactions of the open database in one in-memory `Ledger` (module `Domain`). Every change goes to the database through `Store` (module `Storage`) and then to the ledger. Views read the ledger. This keeps filters, sums, and charts fast for some ten thousand transactions without queries per keystroke.

## Decisions

The first build follows the spec where the task list marks a task as checked. Open tasks keep the behavior of the spec as the target.

### Tabs of version 0.1

Version 0.1 has the tabs "General" and "Security", in this order. It has no payments and no subscription, so "Payments" and "Subscription" do not appear. `SettingsTab` lists the tabs of the build, and a later release adds a case with the first setting of its tab. The two settings of `software-update` join "General" with that capability, because a switch without the updater would do nothing.

### A setting that macOS does not keep

`UserDefaults.set` never fails. macOS keeps another value when a configuration profile forces the key or a launch argument overrides it. The check sees what the defaults of the process read back, not whether the value reaches the disk. `UserDefaults.storeSetting(_:forKey:inDomain:)` in `Storage` writes a value and reads it back, and the window reports a value that does not read back. A switch reads the value in effect now. "Language" reads the defaults of the app, because macOS takes `AppleLanguages` from there at the next start, and the arguments of the run can hold another language. The message appears below the setting, and the control shows the value that applies.

Every setting of the "Security" tab changes through `AppModel.changeSecurity` of `add-app-lock`, after the database password. The lock settings write through `Store`, and the unlock settings write or delete their Keychain entry. A failed write shows the error below the unlock settings, and each control shows the value that the database and the Keychain hold.

### Settings need an unlocked app

The item "Settings..." replaces the item of the system and is off while the app is not unlocked, so ⌘, does nothing then. From macOS 26 on, the settings scene adds its own item after the group `.appSettings`, so the scene removes its commands with `commandsRemoved()` (issue #554). The settings window closes when the app leaves the state "unlocked", for example on a lock with ⌃⌘L or after inactivity, and when it comes on screen while the app is locked: one turn after it appears, because SwiftUI shows the window after `onAppear`, and whenever a window that macOS kept comes back. A password prompt on the "Security" tab closes with it and does not come back after the unlock. macOS does not restore the window at the launch.

## Risks / Trade-offs

Tasks marked as built in part may differ from the spec in the way their note says.
