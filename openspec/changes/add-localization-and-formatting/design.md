# Design

## Context

This design covers the languages of the interface, the completion of a partly typed date, and the relative day names of a refresh. The other requirements of the change, such as amount entry and the groups of an IBAN, get their design before their tasks are built.

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

`StarterCategories.make(language:)` already holds both sets. The app picks the set by the language of the interface when it creates the database. A later change of the language renames only what the user has not changed.

When the app opens the database, `StarterCategories.renamed(in:to:)` gives the starter categories that follow the interface language with their new names, and the app stores them in one write before it shows the ledger (#207). The ids stay, so the transactions keep their categories, and the rule of "Salary" is the same in both sets.

The app records where each starter category comes from instead of guessing it from names. `StarterCategories.make(language:)` gives each category a `starterKey`, such as `living.rent`, and migration v33 adds the column to `category`. A rename or a move to another group by the user ends the record: `AppModel.save(category:)` stores what `Ledger.userSaved(_:)` gives, and `Ledger.move(category:into:at:)` clears the key of a category that changes its group. The automatic rename keeps the key. So a category with a key always has the starter name of its key in one of the languages, and that name tells its language, which needs no second column. A category follows while it has a key and the starter name of its key in another language. So a name that the user gave stays, also "Transfers" renamed to "My transfers" and back, and a group that the user built has no key and stays. A database created before v33 has no record and renames nothing. v0.1 has not shipped, and a set from the migration has `sourceID` and no key anyway. A key that came with another name, as from an edited export, keeps that name.

A group follows only with exactly its starter subcategories, one each, each following too, because a group with one more or one less subcategory may be the work of the user. Other settings, such as a color, do not stop the rename, because only the name holds the language. Every new name, that of the default category included, must pass `Ledger.checkCategoryName(_:in:renaming:)`, the rule of #508, so a name that a category of the same group already has in other case or with white space around it keeps the old name. A failed write keeps the old names, writes one line without names to the trail, and does not keep the database closed, and the next open tries again.

Alternative: remove the unchanged set of the other language and add the new set. New ids would move the transactions of the removed categories to the default category.

The migration from MoneyMoney and "Import All Data" replace an untouched starter set. They recognize the set in either language, because a database created in English can open with a German interface and the other way round, and a database of an earlier English-only build has the English set. The name of the default category tells the language of the set, "Uncategorized" or "Unkategorisiert". When the user renamed it, the language of the interface decides. Only that one set counts, so an empty group of the user named like a group of the other set stays.

### A generated account name is a default, not data

"Create offline account" in the import of a file names the new account by its formatted IBAN, or by `Account %@` with the account number when the file has no IBAN. The app writes that name in the language of the interface into the account, as it writes the starter categories. The name is a default that the user sees and may rename. No code finds an account by its name: the import matches by IBAN and account number, and the sync by the identity of the account. So a later change of the language does not rename the account, and a German database may hold an English default name, as it may hold an English starter category.

A localized text is never data otherwise. A key, a value that the app compares, and a text that a process sends to another one stay language-neutral. The host process of an extension finds a refusal of its policy by the English text that the script sees, never by the text that the app shows, and the debug harness chooses a menu item by its place in the menu, because SwiftUI gives a menu item no identifier. Only where the place differs from menu to menu, as for the export item, and for a table column, whose identifier SwiftUI makes new in each run, the harness compares the title with the text of the catalog in the language of the run, the text that the user reads.

Alternative: store an empty name and word it at display. Every view, the export, and the search would then need the rule, for one name that the user can change in one step.

### The error of a refresh is stored as data

The error of the last refresh of an account is not a default that the user may change, so the app stores no text of its own for it. `RefreshError.failure` holds the `SyncFailure` with its values: the case, such as `pinRejected`, and the code and the text that the bank sent, as the bank sent them. `RefreshError.message` and `RefreshError.shownMessage` build the text when a view shows it, so a switch of the language and a restart show the error in the new language. The column `account.refreshError` keeps its JSON. `SyncFailure` encodes `reason` with the name of its case, `code`, `text`, and `accountName` for the answer of the bank, `request` for the request that an automatic refresh could not ask, and `detail` for the text of a network failure, an unsupported request, or a failed save. `noTANMethodOfBank` stores the next step as a value of `SyncFailure.NextStep`, such as `dkbApp`, and no longer as a sentence.

An error stored before #310 has `message` and `code` in place of `failure`. The app reads it as a message of the bank with that code and text, which shows the stored text as before and the code beside it, until the next refresh replaces it. The database needs no migration, because the decoder reads both forms, and "Import All Data" reads an older export file the same way.

The text in `detail` comes from the source of the failure: the FinTS helper, an extension, macOS, or the database. Some of these texts are sentences of a connector, such as the timeout of the FinTS helper, which the connector writes in the language of the refresh. They stay as stored until the next refresh, because turning each of them into a value would move the sentences of every connector into `Domain`.

Five sentences of the connectors go into `bank` as if the bank had sent them, so they too keep the language of the refresh: "The bank sent nothing for this account." in `Sources/FinTS/HelperProtocol.swift`, and in `Sources/ExtensionConnector/ExtensionConnector.swift` the login that returned a value that is not valid, the account that an extension lists twice, the missing list of accounts, and the login page that is not an allowed host. Each needs its own reason with the name of the extension, the account, or the host as values, and `mayAskForNewSetup` must keep its answer for them. Issue #462 tracks it.

Alternative: a migration that clears the old errors. That would also clear `waitsForUser` and `lockedLogins`, so an access whose PIN the bank rejected, or whose login ING locked, would join the automatic refresh again.

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

A day reaches the formatter of `Format.day` and the calendar as noon GMT (`Day.noon`), and both read it in a calendar set to GMT (`Day.calendar(like:)`). The field and its calendar use the Gregorian calendar with the first weekday of the user, because the rules of the completion count Gregorian days, months, and years. A Mac set to the Buddhist calendar shows 2569 elsewhere in the app and 2026 in a date field, which the field reads back. A date from the calendar returns as the day of its noon GMT (`Day(noon:)`). Local midnight does not exist on every day: Samoa skipped 30 December 2011, and its midnight turned into the 31st. Noon GMT exists on every day in every time zone, so the field shows and picks the day that it holds.

The custom period of the transaction list and the sheet for a transaction use the field. The sheet refuses to save while its booking date or its switched-on value date is not a date, as the custom period refuses to apply. The month names of `Format.monthTitle` and `Format.shortMonth` read a day at noon GMT too, so every day of the app reaches a formatter by one rule.

### The rule for an ordinary field

A typed day goes into today's month. It moves one month back only when it is more than two greater than today's day. So the dates of the last weeks, which a user types most often, land in the past. A day up to two greater than today's day stays in the current month, for a cash payment noted ahead. At the end of a month this covers less: on 30 November, "1" gives 01.11.2026, because the day number 1 lies before 30. A typed day and month stay in today's year. Only from January to March does a month from October to December go to the last year.

### The rule for a field that expects a future date

A typed day that is less than today's day moves one month forward. A typed day and month that lie before today move to the next year. A payment cannot be scheduled in the past, so every completed date of such a field lies on or after today.

### A moved date that does not exist

The completion works on the numbers of the day and the month and checks the date only at the end. A date that does not exist after the move is refused like any impossible date, and the field stays in editing. On 9 March 2027, "30" gives 30.02.2027, which does not exist. The app does not move it by another month, because a second move would pick a date that the user did not type, and a marked field shows the problem at once.

### Relative day names of a refresh

`Format.dayAndTime(_:now:calendar:locale:)` in `Sources/Domain/RelativeDay.swift` writes the time of the last refresh and of the bank balance. It is pure: today, the calendar with its time zone, and the locale are parameters, so the tests fix all three. It counts calendar days between the starts of the two days in the calendar, not periods of 24 hours, so a refresh at 23:59 is "Yesterday" one minute after midnight, and a day of 23 or 25 hours at a change of daylight saving time still counts as one day. The day difference picks the form:

- 0 is "Today" with the time, and 1 is "Yesterday" with the time.
- 2 to 6, and every day after today, is the weekday of the locale with the time.
- 7 or more is the date alone, in the style of `Format.day` with a four-digit year.

The time is the short time of the locale without seconds. The weekday comes from the locale, so a German interface on a German Mac shows "Samstag". The catalog holds "Today, %@" and "Yesterday, %@", and the weekday form uses the existing entry "%@, %@".

"Tomorrow", a number of days ago ("vor 3 Tagen"), and a number of days ahead ("in 3 Tagen") belong to the label of the next execution of a scheduled order. That label comes with the change `add-payment-outbox` in v0.2: "Today", "Yesterday", and "Tomorrow" for a difference of up to one day, the number of days from 2 to 999 days, and no label beyond. This change builds none of it, because nothing would call it.

## Risks / Trade-offs

- [A text that a library builds as a `String` without `String(localized:)` stays English.] → The check sees only literals that are looked up. Review a new message of a library for `String(localized:)`, as for any text of the app.
- [The text of a network failure, an unsupported request, or a failed save keeps the language of the refresh, and so do the five sentences of the connectors that are stored as an answer of the bank.] → It changes with the next refresh. Every other part of the error of a refresh follows the language of the app. Issue #462 turns the five sentences into reasons.
- [A day typed more than two days ahead lands in the previous month.] → The field shows the full date at once, and the user can type the month as well.
- [Near the end of a month, a day of the next month needs the month typed.] → The field shows the full date at once, so the user sees 01.11.2026 and can type "1.12" instead.

## Open Questions

None. The list of fields that expect a future date is in the decision "The kind of field is a property of the field".
