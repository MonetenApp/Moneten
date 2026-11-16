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

A new text with a count, such as `%lld transactions`, has one entry with the plural variations "one" and "other" in each language. Code that already chooses between a literal for one and a literal for other counts, such as "1 new transaction" and `%lld new transactions`, keeps both entries. German and English have the same two forms, so both ways read correctly.

### The check reads what the compiler extracts

`scripts/check.sh` already builds the app for Periphery. That build sets `SWIFT_EMIT_LOC_STRINGS`, so the compiler writes the key of every literal that is looked up, in the app and in the libraries, to a `.stringsdata` file. `scripts/check-localization.py` reads these files and the catalog. It fails when a key is missing from the catalog, when a key has no German value, and when the catalog holds a key that no code uses. With `--update`, it adds the missing keys with an empty German value and removes the unused ones, so a contributor without the Xcode editor can add a text and then write its German value.

Keys of the libraries carry the extraction state `manual` in the catalog, so Xcode keeps them when it updates the catalog from the sources of the app.

### The language comes from macOS or from the setting

The "Language" menu on the "General" tab stores `AppleLanguages` with `de` or `en` in the defaults of the app. macOS reads this value at the start of the app, so a change applies at the next start, and the menu says so. Without a stored value, the app reads the preferred languages of macOS at the start. When the first one is neither German nor English, the app sets English for this run, so a French Mac shows English even when German is the second language on that Mac. The setting lives outside the database, so the lock screen is already in the chosen language.

The formats of dates and numbers follow the region of macOS and not the language of the app. An English interface on a Mac in the region Germany shows 1.234,56 € and 09.11.2026.

### Starter categories follow the language at creation

`StarterCategories.make(language:)` already holds both sets. The app picks the set by the language of the interface when it creates the database. A later change of the language does not rename them, because the user may have changed them.

The migration from MoneyMoney and "Import All Data" replace an untouched starter set. They recognize the set in either language, because a database created in English can open with a German interface and the other way round, and a database of an earlier English-only build has the English set. The name of the default category tells the language of the set, "Uncategorized" or "Unkategorisiert". When the user renamed it, the language of the interface decides. Only that one set counts, so an empty group of the user named like a group of the other set stays.

### A generated account name is a default, not data

"Create offline account" in the import of a file names the new account by its formatted IBAN, or by `Account %@` with the account number when the file has no IBAN. The app writes that name in the language of the interface into the account, as it writes the starter categories. The name is a default that the user sees and may rename. No code finds an account by its name: the import matches by IBAN and account number, and the sync by the identity of the account. So a later change of the language does not rename the account, and a German database may hold an English default name, as it may hold an English starter category.

A localized text is never data otherwise. A key, a value that the app compares, and a text that a process sends to another one stay language-neutral. The host process of an extension finds a refusal of its policy by the English text that the script sees, never by the text that the app shows, and the debug harness chooses a menu item by its place in the menu, because SwiftUI gives a menu item no identifier. Only where the place differs from menu to menu, as for the export item, and for a table column, whose identifier SwiftUI makes new in each run, the harness compares the title with the text of the catalog in the language of the run, the text that the user reads.

Alternative: store an empty name and word it at display. Every view, the export, and the search would then need the rule, for one name that the user can change in one step.

### A pure completion function in `Domain`

The completion is a function in `Domain`. It takes the typed text, today as a `Day`, the order of day, month, and year from the region, and whether the field expects a future date. It returns a `Day`, or nothing when the text is not a date. The date field in `App` calls it while the user types and when the user leaves the field. A pure function lets the tests set today to 9 November 2026 or 15 February 2027 without a clock. It is `Day(typed:today:order:expectsFuture:)` in `Sources/Domain/DateCompletion.swift`, and `DateOrder(locale:)` gives the order of a region.

Alternative: complete the date inside the view. The rule then has no tests outside the running app, and the two kinds of field could drift apart.

### The kind of field is a property of the field

Each date field states whether it expects a future date. The default is no. Only the fields that set it use the forward rules of the two requirements for a field that expects a future date.

These fields expect a future date:

- The execution date of a transfer, an instant payment, and a foreign currency transfer, when "Schedule" is set to "Set date".
- The first and the last execution date of a standing order, and the date of a change to a standing order.
- The due date of a direct debit and of a batch direct debit.

Each of them is an order that the bank carries out later, and a bank refuses an order for a day in the past. Every other date field is ordinary: the booking date and the value date of a transaction, the ends of a custom period, and the dates of a report and of an export. These record or select something that has already happened. Today the app has only ordinary fields. The windows for payments set the kind when they are built.

### Reading the typed text

The completion reads the text in the order of the numeric date of the region, which `Format.day` shows: day, month, and year in Germany, and month, day, and year in the United States. It tries a full date first and a partial date second.

A full date has three numbers. They are separated by ".", "/", "-", ",", or spaces, and a run of separators counts as one, so "20. 10. 2026" reads. A first number of four digits is always the year of an ISO date, such as 2026-11-09. Four to eight digits without a separator are also a full date: four to six digits hold a two-digit year, and seven or eight digits a four-digit year, at the end, or at the start in a region that writes the year first. So "201226" is 20.12.2026. The digits left for the day and the month follow the order of the region. Two digits are a one-digit day and month, and of three digits the month takes two when they lie from 01 to 12, so "11226" is 01.12.2026. A year has two or four digits. A two-digit year below 80 lies in the 2000s, from 80 on in the 1900s.

A partial date is a day, or a day and a month, separated by "." or "/". A separator at the end is ignored, so "20.12." reads as "20.12". A day and a month have one or two digits and keep the order of the region, so "12/20" is 20 December in the United States. A region that writes the year first takes a day alone but no day and month. Letters, an empty part, and a day or a month out of range make the text unreadable, and so does a day and month with "-", ",", or a space, such as "20,12".

A typed year is not limited, and a date before 1970 stays as typed.

### The date field of the app

`DateField` in `App/Sources/Views/DateField.swift` is a text field with a button for the calendar. It binds an optional `Day`, which follows the text while the user types. So a click on a button of the sheet uses the completed date even though the field still has the focus. The day is nil while the text is not a date, and the sheet does not confirm then. When the user leaves the field with Tab, Return, or a click elsewhere, the field shows the full date in the format of the region. When the text is not a date, the field shows it in red with a red frame, takes the focus back, and leaves the bound day as nil, so the sheet stores no date until the user corrects the text.

The calendar is the graphical date picker of the system in a popover. It starts at the date of the field, or at today while the field holds no date. Every date that the picker sets goes into the field and ends the mark. The picker also sets its date when the user moves to another month, and whether its arrows do so is not documented. So a date in the month on show, which is a click on a day, also closes the popover, and a date in another month leaves the popover open.

The custom period of the transaction list uses the field. The sheet for a transaction keeps the date picker of the system until the open change for manual transactions, which rewrites that sheet, is merged. Its booking date and value date then move to the field.

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

None. The list of fields that expect a future date is in the decision "The kind of field is a property of the field".
