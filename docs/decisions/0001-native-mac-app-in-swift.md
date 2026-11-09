# 0001. Build a native Mac app in Swift and SwiftUI

Status: Accepted

## Context

The target users manage their finances on a Mac today, mostly with MoneyMoney, Banking4, or Pecunia. They expect a fast app with native windows, menus, keyboard shortcuts, Touch ID, and the Keychain. Cross-platform toolkits such as Tauri or Electron reach more systems but give up those details. One platform also halves the testing work for a small team.

## Decision

MonetenMoneten is a macOS app written in Swift with SwiftUI. It supports the two most recent major macOS versions. Windows, Linux, and the web are out of scope.

## Consequences

- The app can use the Keychain, Touch ID, XPC services, and later CloudKit without extra layers.
- Contributors need a Mac and Xcode.
- An iPhone and iPad app can reuse `Domain`, `Storage`, and the connectors later. That work starts after v0.3.
