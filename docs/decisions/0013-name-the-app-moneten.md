# 0013. Name the app Moneten

Status: Accepted

## Context

The app was called MonetenMoneten. The double word echoed MoneyMoney, and its first icon showed two Ms. MoneyMoney's logo since 2025 is a looping "MM" ribbon in blue, so the name and the icon came close to the product the project wants to replace. In November 2026 the owner chose the shorter name Moneten, a German word for money.

The search on 11 November 2026 found no app named Moneten in the App Store of Germany, Austria, Switzerland, or the United States. A learning app about personal finance named "moneten" (App Store ID 6670764019) was listed once and has been removed. On GitHub, a few small hobby projects use the word. The trademark registers of the DPMA and the EUIPO could not be searched automatically. The owner checks them by hand in classes 9, 36, and 42. Moneten is a common word, so a word mark for it alone is weak, and a conflict is more likely with a logo or a longer name.

## Decision

- The app, its bundle, the Xcode target, the scheme, and the Swift package are named Moneten. The bundle identifier is `io.github.alexander-schneider.Moneten`. The environment variables start with `MONETEN_`.
- The icon is one light M on deep blue, drawn by `scripts/make-icon.swift`. Its right leg ends higher than the left one, like a rising balance. It has no second M.
- The repository keeps its name until the owner renames it. GitHub forwards the old links after a rename.

## Consequences

- The data folder is `~/Library/Application Support/Moneten` and the database file is `Moneten.sqlite`. On its first start, the app moves the folder and the files of the old name. It replaces nothing that already exists, and it keeps using the old folder when the move fails.
- The Keychain entries are named "Moneten database key" and "Moneten database password". When an entry of the new name is missing, the app reads the entry of the old name, saves it under the new name, and deletes the old one. macOS asks once whether Moneten may read the old entry, because a new bundle identifier is a new app for the Keychain.
- The settings move once from the old bundle identifier. macOS asks again whether Moneten may control MoneyMoney.
