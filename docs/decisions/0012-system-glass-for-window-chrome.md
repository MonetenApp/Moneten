# 0012. Keep the Liquid Glass of macOS for the window chrome

Status: Accepted

## Context

The project copies MoneyMoney where a design choice comes up, so that people who switch find what they know. In November 2026 a change made the sidebar opaque gray, measured in MoneyMoney (#E0E0E6, dark #454549). In dark mode it looked dirty next to the glass toolbar of macOS 26, and it was reverted the same day. MoneyMoney draws its window with older materials, and copying them makes the app look out of date on the current macOS.

## Decision

- The sidebar, the toolbar, the title bar, and the window background use the system materials of macOS: Liquid Glass and the standard sidebar and toolbar styles. The app does not fill them with its own colors.
- MoneyMoney parity applies to the content: the header band, the transaction list, the charts, the sheets, and the behavior.
- `scripts/check-ui.py` enforces the rule. It fails on code that hides the sidebar material, puts a color or a material behind the sidebar or the split view, or overrides the toolbar, the title bar, or the window background. `scripts/check.sh` and CI run it. A line may break a rule only with the comment `// chrome-ok: <reason>`.

## Consequences

- A proposal that copies a look of MoneyMoney says whether it touches the window chrome. If it does, it keeps the system material and lists the difference under "Decided for MonetenMoneten".
- A change to the window chrome shows a snapshot in light and dark mode in its pull request before it is merged.
- New macOS versions change the look of the chrome without code changes in the app.
