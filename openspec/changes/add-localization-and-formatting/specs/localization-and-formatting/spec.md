# Spec Delta

## Purpose

Every label, date, and amount must read the way the user expects on their Mac. This capability defines the languages of the interface and the common rules for showing and entering dates, amounts, currencies, and IBANs, and for the light and dark appearance.

## ADDED Requirements

### Requirement: German and English interface

The app SHALL offer its whole interface in German and in English. That includes menus, labels, messages, tooltips, Accessibility descriptions, and the documents that the app creates, such as printouts and reports.

#### Scenario: German

- **GIVEN** the interface language is German
- **WHEN** the user opens the Account menu
- **THEN** every command is in German

#### Scenario: No mixed languages

- **GIVEN** the interface language is English
- **WHEN** the user opens the settings window
- **THEN** no label is in German

### Requirement: Follow the language of macOS

The app SHALL use German when German is the preferred language of macOS and English in every other case, unless the user has set a language in the app.

#### Scenario: German system

- **GIVEN** macOS is set to German and the user has set no language in the app
- **WHEN** the user starts the app
- **THEN** the interface is German

#### Scenario: French system

- **GIVEN** macOS is set to French
- **WHEN** the user starts the app
- **THEN** the interface is English

### Requirement: Language setting

The app SHALL offer a "Language" menu on the "General" tab of the settings with German and English. A change applies after the next start of the app, and the app says so.

#### Scenario: Switch to English

- **GIVEN** macOS is set to German and the interface is German
- **WHEN** the user sets "Language" to English and restarts the app
- **THEN** the interface is English

### Requirement: Text from a bank stays as received

The app SHALL show text that a bank or an extension delivers in its original wording. That includes the purpose of a transaction, booking texts, names, and messages of the bank server.

#### Scenario: English interface, German bank

- **GIVEN** the interface language is English
- **WHEN** a transaction has the booking text "Lastschrift" and the purpose "Abschlag Strom"
- **THEN** the list shows "Lastschrift" and "Abschlag Strom" unchanged

### Requirement: Dates follow macOS and show four-digit years

The app SHALL show dates in the date format of macOS for the order and form of day and month, and it SHALL always show the year with four digits.

#### Scenario: German format

- **GIVEN** macOS uses the region Germany
- **WHEN** a transaction has the booking date 9 November 2026
- **THEN** the list shows "09.11.2026"

#### Scenario: American format

- **GIVEN** macOS uses the region United States
- **WHEN** a transaction has the booking date 9 November 2026
- **THEN** the list shows the month before the day and the year as 2026

### Requirement: Relative day names

The app SHALL name a day close to today in words where it shows a point in time, such as the last refresh or the next execution. It uses "Today", "Yesterday", "Tomorrow", a number of days ago, and a number of days ahead.

#### Scenario: Refresh today

- **GIVEN** the last refresh ended today at 14:32
- **WHEN** the user looks at the time of the last refresh
- **THEN** it reads "Today, 14:32"

#### Scenario: Refresh the day before

- **GIVEN** the last refresh ended yesterday at 08:05
- **WHEN** the user looks at the time of the last refresh
- **THEN** it reads "Yesterday, 08:05"

### Requirement: Complete a typed day

The app SHALL complete a date field in which the user typed only a day to that day in today's month and year. When that date lies after today and the typed day is more than two greater than today's day, the app moves it one month back, into the previous year when needed. This holds for every date field except a field that expects a future date.

#### Scenario: Day more than two days ahead

- **GIVEN** today is 9 November 2026 and macOS uses the region Germany
- **WHEN** the user types "20" into a date field and leaves the field
- **THEN** the field shows "20.10.2026"

#### Scenario: Day two days ahead

- **GIVEN** today is 9 November 2026 and macOS uses the region Germany
- **WHEN** the user types "11" into a date field and leaves the field
- **THEN** the field shows "11.11.2026"

#### Scenario: Day before today

- **GIVEN** today is 28 November 2026 and macOS uses the region Germany
- **WHEN** the user types "2" into a date field and leaves the field
- **THEN** the field shows "02.11.2026"

#### Scenario: Day in January

- **GIVEN** today is 9 January 2027 and macOS uses the region Germany
- **WHEN** the user types "20" into a date field and leaves the field
- **THEN** the field shows "20.12.2026"

### Requirement: Complete a typed day and month

The app SHALL complete a date field in which the user typed a day and a month to that date in today's year. When that date lies after today, today is in January, February, or March, and the typed month is October, November, or December, the app uses the previous year. This holds for every date field except a field that expects a future date.

#### Scenario: Day and month later this year

- **GIVEN** today is 9 November 2026 and macOS uses the region Germany
- **WHEN** the user types "20.12" into a date field and leaves the field
- **THEN** the field shows "20.12.2026"

#### Scenario: Day and month at the end of the last year

- **GIVEN** today is 15 February 2027 and macOS uses the region Germany
- **WHEN** the user types "20.12" into a date field and leaves the field
- **THEN** the field shows "20.12.2026"

#### Scenario: Day and month outside the turn of the year

- **GIVEN** today is 15 February 2027 and macOS uses the region Germany
- **WHEN** the user types "20.06" into a date field and leaves the field
- **THEN** the field shows "20.06.2027"

### Requirement: Complete a typed day in a field that expects a future date

The app SHALL complete a date field that expects a future date, such as the scheduled date of a payment, in which the user typed only a day to that day in today's month and year. When that date lies before today, the app moves it one month forward, into the next year when needed.

#### Scenario: Day later this month

- **GIVEN** today is 9 November 2026 and macOS uses the region Germany
- **WHEN** the user types "20" into the scheduled date of a transfer and leaves the field
- **THEN** the field shows "20.11.2026"

#### Scenario: Day before today

- **GIVEN** today is 9 November 2026 and macOS uses the region Germany
- **WHEN** the user types "1" into the scheduled date of a transfer and leaves the field
- **THEN** the field shows "01.12.2026"

#### Scenario: Day before today in December

- **GIVEN** today is 28 December 2026 and macOS uses the region Germany
- **WHEN** the user types "2" into the scheduled date of a transfer and leaves the field
- **THEN** the field shows "02.01.2027"

### Requirement: Complete a typed day and month in a field that expects a future date

The app SHALL complete a date field that expects a future date, in which the user typed a day and a month, to that date in today's year. When that date lies before today, today is in October, November, or December, and the typed month is January, February, or March, the app uses the next year.

#### Scenario: Day and month at the start of the next year

- **GIVEN** today is 9 November 2026 and macOS uses the region Germany
- **WHEN** the user types "15.01" into the scheduled date of a transfer and leaves the field
- **THEN** the field shows "15.01.2027"

### Requirement: Reject an impossible date

The app SHALL refuse a date that does not exist or that it cannot read, keep the field in editing, and mark the field.

#### Scenario: 31 November

- **WHEN** the user types "31.11.2026" into a date field and leaves the field
- **THEN** the field is marked as invalid
- **AND** the app does not change the stored date

### Requirement: Pick a date from a calendar

The app SHALL offer a calendar for every date field. A click on a day in the calendar puts that date into the field.

#### Scenario: Pick a day

- **WHEN** the user opens the calendar of a date field and clicks 15 December 2026
- **THEN** the field shows that date

### Requirement: Amounts follow the number format of macOS

The app SHALL show amounts with the grouping separator and the decimal separator of macOS and with as many decimal places as the currency has.

#### Scenario: German format

- **GIVEN** macOS uses the region Germany
- **WHEN** an account has the balance one thousand two hundred thirty-four euros and fifty-six cents
- **THEN** the app shows "1.234,56 €"

#### Scenario: Whole amount

- **GIVEN** macOS uses the region Germany
- **WHEN** a transaction has the amount of exactly 100 euros
- **THEN** the app shows "100,00 €"

### Requirement: Every amount shows its currency

The app SHALL show the currency with every amount. The euro and other currencies with a common symbol show the symbol. Other currencies show their three-letter code.

#### Scenario: Swiss francs

- **WHEN** an account in Swiss francs has a balance of 250 francs
- **THEN** the app shows the amount with "CHF"

#### Scenario: Group with two currencies

- **GIVEN** an account group with one account in euros and one in US dollars
- **WHEN** the app shows a sum for the group
- **THEN** the app shows one sum for each currency and does not add them

### Requirement: Negative amounts are marked

The app SHALL show a negative amount with a leading minus sign and in a color that differs from the color of positive amounts. A positive amount has no sign.

#### Scenario: Withdrawal and deposit

- **WHEN** the list shows a withdrawal of 89 euros and a deposit of 1.250 euros
- **THEN** the withdrawal reads "-89,00 €" in the color for negative amounts
- **AND** the deposit reads "1.250,00 €"

### Requirement: Amounts are aligned in lists

The app SHALL set amounts in the system font with digits of equal width and align them on the right in lists, so that the decimal separators stand below each other.

#### Scenario: Column of amounts

- **WHEN** a list shows the amounts "-5,50 €" and "1.250,00 €" below each other
- **THEN** both decimal commas are at the same horizontal position

### Requirement: Amount entry follows macOS

The app SHALL read an amount that the user types in the number format of macOS. It refuses an entry that it cannot read without doubt and marks the field.

#### Scenario: German entry

- **GIVEN** macOS uses the region Germany
- **WHEN** the user types "1.234,5" into an amount field
- **THEN** the app reads one thousand two hundred thirty-four euros and fifty cents

#### Scenario: Unreadable entry

- **WHEN** the user types "12,3,4" into an amount field
- **THEN** the field is marked as invalid and the app stores no amount

### Requirement: IBANs in groups of four

The app SHALL show an IBAN in groups of four characters with a space between the groups. An IBAN that the user copies from the app has no spaces.

#### Scenario: Display

- **WHEN** the app shows the IBAN DE02120300000000202051
- **THEN** it reads "DE02 1203 0000 0000 2020 51"

#### Scenario: Copy

- **WHEN** the user copies that IBAN from the account settings and pastes it into a text document
- **THEN** the text document shows "DE02120300000000202051"

### Requirement: Singular and plural

The app SHALL use the singular form for a count of one and the plural form for every other count, in both languages.

#### Scenario: One and three

- **WHEN** one list shows 1 transaction and another shows 3 transactions
- **THEN** the status lines read "1 Transaction" and "3 Transactions"

### Requirement: Light and dark appearance

The app SHALL follow the light or dark appearance of macOS in every window, popover, and chart, and it SHALL change with macOS while it is running.

#### Scenario: Switch while running

- **GIVEN** the app is open in the light appearance
- **WHEN** the user switches macOS to the dark appearance
- **THEN** the main window, the settings window, and the charts are dark without a restart

#### Scenario: Readable in both

- **WHEN** the category settings are open in the dark appearance
- **THEN** every label and every field can be read

### Requirement: Booking dates do not move with the time zone

The app SHALL treat the booking date and the value date of a transaction as calendar dates. They stay the same when the time zone of the Mac changes.

#### Scenario: Travel

- **GIVEN** a transaction with the booking date 9 November 2026, stored while the Mac was in Berlin
- **WHEN** the user opens the app with the Mac set to the time zone of Auckland
- **THEN** the transaction still shows 9 November 2026
