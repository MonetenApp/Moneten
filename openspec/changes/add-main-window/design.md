# Design

## Context

This change is part of the first build of the app. The build is a Swift package with the modules `Domain`, `Storage`, `Import`, and `App`, as [ADR 0010](../../../docs/decisions/0010-swift-package-and-macos-15.md) describes. Everything runs on the Mac, with no server ([ADR 0002](../../../docs/decisions/0002-local-first-no-server.md)).

The app keeps all accounts, categories, and transactions of the open database in one in-memory `Ledger` (module `Domain`). Every change goes to the database through `Store` (module `Storage`) and then to the ledger. Views read the ledger. This keeps filters, sums, and charts fast for some ten thousand transactions without queries per keystroke.

## Decisions

The first build follows the spec where the task list marks a task as checked. Open tasks keep the behavior of the spec as the target.

A new group is stored when its row appears, so "Name a new group in the sidebar" changes only the name. `AppModel.namingRow` names the row in edit mode, and the typed text stays in the row view until Return, Escape, or a move of the focus ends edit mode. A lock while the user types drops the typed text: the group keeps the name it has in the database, and the row is not in edit mode after the unlock. The sheets that come back after an unlock (#503) do not include this edit mode.

The content view takes its colors from `Palette` in `App/Sources/Views/Format.swift`, as fixed sRGB values with a value for "Increase contrast" where the light value is too faint (issue #614). macOS 26 tints the system background colors with the desktop picture: on a Mac with a blue picture the control background of a dark table, #1E1E1E, reached the screen as #21242A. A fixed sRGB color reaches the screen unchanged. `TransactionsView` hides the content background of the tables below it and puts `Palette.list` behind the band, the filter bar, the tables, and the status line, so the transactions and the positions share one background. The selection keeps the accent color of the app, which AppKit draws, and the sidebar and the toolbar keep the system materials (ADR 0012).

## Risks / Trade-offs

Tasks marked as built in part may differ from the spec in the way their note says.
