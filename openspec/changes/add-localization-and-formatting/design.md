# Design

## Context

This design covers the languages of the interface and the completion of a partly typed date. The other requirements of the change, such as amount entry and the groups of an IBAN, get their design before their tasks are built.

Today every text of the interface is English. SwiftUI already looks up the literal labels of `Text`, `Button`, and similar views, but the app has no translation, so the lookup finds nothing. Many texts are not looked up at all: a `String` built in code, an alert of the app, the title of a notification, and the messages that the libraries `Domain`, `Sync`, `Storage`, `Import`, `FinTS`, `ExtensionHost`, `ExtensionConnector`, and `ExtensionCatalog` write for the user.

The sheet for a manual transaction in `App/Sources/Views/Sheets.swift` and the custom period in `App/Sources/Views/TransactionsView.swift` use the date picker of the system. That picker edits the day, the month, and the year one at a time. It does not take a day alone and complete it, so the rules of the spec need a date field of the app's own.

## Goals / Non-Goals

**Goals:**

- Every text that the app writes itself exists in English and German, and a check fails when a new text has no German translation.
- One term for one thing in each language.
- One rule for completing a date, used by every date field of the app.
- The same result for the same typed text, today, region, and kind of field, so tests can fix all four.

**Non-Goals:**

- A third language. The catalog allows one later.
- Translating text from a bank, an extension, or macOS, such as a bank message or a system error.

- Words such as "today" or "heute" in a date field.
- The minimum and maximum of a date field. A field that has them applies them after the completion.

## Decisions

### One String Catalog in the app

The app target holds `App/Resources/Localizable.xcstrings`, with English as the development language and German as the second language. The key of an entry is its English text, as Swift writes it for a literal, for example `%lld new transactions` for an interpolated count. A key without a German value shows its English text.

The libraries have no catalog of their own. A library writes a text for the user with `String(localized:)`, which reads the main bundle. In the app that bundle is the app with its catalog. In the tests of the package it is the test runner without a catalog, so the tests read English. So the package still builds with the Command Line Tools alone, which cannot compile a catalog.

Alternative: one catalog in each library with `defaultLocalization` in `Package.swift`. That adds a resource bundle to each library and the tool for the catalog to every build of the package, for a few hundred texts.

### Literals are looked up, values are not

A text of the app is a literal in the code: `Text("Balance")`, `String(localized: "Could not save the account.")`, or a parameter of the type `LocalizedStringKey` or `LocalizedStringResource`. A value that comes from the database, a bank, or an extension, such as an account name, reaches a view with `Text(verbatim:)` or as a `String`, which SwiftUI does not look up. The debug harness and the perf check write only to their log, so their texts stay English and outside the catalog.

### Counts use the plural rules of the catalog

A text with a count, such as `%lld new transactions`, has one entry with the variations "one" and "other" in each language. Code does not choose between a singular and a plural literal.

### The check reads what the compiler extracts

`scripts/check.sh` already builds the app for Periphery. That build sets `SWIFT_EMIT_LOC_STRINGS`, so the compiler writes the key of every literal that is looked up, in the app and in the libraries, to a `.stringsdata` file. `scripts/check-localization.py` reads these files and the catalog. It fails when a key is missing from the catalog, when a key has no German value, and when the catalog holds a key that no code uses. With `--update`, it adds the missing keys with an empty German value and removes the unused ones, so a contributor without the Xcode editor can add a text and then write its German value.

Keys of the libraries carry the extraction state `manual` in the catalog, so Xcode keeps them when it updates the catalog from the sources of the app.

### The language comes from macOS or from the setting

The "Language" menu on the "General" tab stores `AppleLanguages` with `de` or `en` in the defaults of the app. macOS reads this value at the start of the app, so a change applies at the next start, and the menu says so. Without a stored value, the app reads the preferred languages of macOS at the start. When the first one is neither German nor English, the app sets English for this run, so a French Mac shows English even when German is the second language on that Mac. The setting lives outside the database, so the lock screen is already in the chosen language.

The formats of dates and numbers follow the region of macOS and not the language of the app. An English interface on a Mac in the region Germany shows 1.234,56 € and 09.11.2026.

### Starter categories follow the language at creation

`StarterCategories.make(language:)` already holds both sets. The app picks the set by the language of the interface when it creates the database. A later change of the language does not rename them, because the user may have changed them.

### A pure completion function in `Domain`

The completion is a function in `Domain`. It takes the typed text, today as a `Day`, the order of day, month, and year from the region, and whether the field expects a future date. It returns a `Day`, or nothing when the text is not a date. The date field in `App` calls it when the user leaves the field. A pure function lets the tests set today to 9 November 2026 or 15 February 2027 without a clock.

Alternative: complete the date inside the view. The rule then has no tests outside the running app, and the two kinds of field could drift apart.

### The kind of field is a property of the field

Each date field states whether it expects a future date. The default is no. Only the fields that set it use the forward rules of the two requirements for a field that expects a future date.

### The rule for an ordinary field

A typed day goes into today's month. It moves one month back only when it is more than two greater than today's day. So the dates of the last weeks, which a user types most often, land in the past. A day up to two greater than today's day stays in the current month, for a cash payment noted ahead. At the end of a month this covers less: on 30 November, "1" gives 01.11.2026, because the day number 1 lies before 30. A typed day and month stay in today's year. Only from January to March does a month from October to December go to the last year.

### The rule for a field that expects a future date

A typed day that is less than today's day moves one month forward. A typed day and month that lie before today move to the next year. A payment cannot be scheduled in the past, so every completed date of such a field lies on or after today.

### A moved date that does not exist

The completion works on the numbers of the day and the month and checks the date only at the end. A date that does not exist after the move is refused like any impossible date, and the field stays in editing. On 9 March 2027, "30" gives 30.02.2027, which does not exist. The app does not move it by another month, because a second move would pick a date that the user did not type, and a marked field shows the problem at once.

## Risks / Trade-offs

- [A text that a library builds as a `String` without `String(localized:)` stays English.] → The check sees only literals that are looked up. Review a new message of a library for `String(localized:)`, as for any text of the app.
- [A text stored in the database, such as the error of the last refresh, keeps the language in which it was written.] → It changes with the next refresh.
- [A day typed more than two days ahead lands in the previous month.] → The field shows the full date at once, and the user can type the month as well.
- [Near the end of a month, a day of the next month needs the month typed.] → The field shows the full date at once, so the user sees 01.11.2026 and can type "1.12" instead.

## Open Questions

- Which date fields expect a future date. The spec names the scheduled date of a payment. The forward rules for these fields are the two requirements for a field that expects a future date. Confirm the list of fields and this rule before the windows for transfers, direct debits, and standing orders are built. The rule for an ordinary field does not depend on this answer.
