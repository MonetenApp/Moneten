# Proposal: Speak German and English and format dates, amounts, and IBANs the way the Mac does

## Why

The users bank in Germany, and many of them use their Mac in German. Others have a German account and prefer English. Both groups must read every label, date, and amount without thinking. A banking app that shows 1,234.56 where the user expects 1.234,56 invites expensive mistakes.

## What Changes

- The interface is available in German and English. It follows the language of macOS, and a setting overrides that.
- Text that comes from a bank stays as the bank sent it.
- Dates follow the date format of macOS and always show the year with four digits.
- Date fields complete a day or a day and month to a full date, and they offer a calendar.
- Amounts follow the number format of macOS, show their currency, and mark negative values.
- IBANs appear in groups of four characters.
- The app follows the light and dark appearance of macOS.

## Capabilities

### New Capabilities

- `localization-and-formatting`: the languages of the interface and the common rules for showing and entering dates, amounts, currencies, and IBANs, and for the appearance.

### Modified Capabilities

None.

## Impact

- Milestone: v0.1
- Issues: #5
- Modules: `App` owns the translations and the formatters. `Domain` owns the money type that every amount uses.
- Depends on the change `add-app-settings` for the "Language" setting.
- The changes `add-categorization-rules` and `add-transaction-search-and-filters` own the matching rules for case and umlauts. The export changes own the number formats inside exported files.
- Decisions: [ADR 0001](../../../docs/decisions/0001-native-mac-app-in-swift.md).

## Reference behavior

### Observed in MoneyMoney 2.5.3

- The app has a German and an English interface. The bundle holds both translations, and English is the base language. The feature page presents the English version for users who have a German account and are not comfortable with German ([feature page](https://moneymoney.app/)).
- The "General" settings have a "Language" menu. See [analysis](../../../docs/research/moneymoney-analysis.md#settings-u). The language can be changed in the settings (version history, 2.2.9), and the interface strings say that a restart is needed.
- Years always show four digits, and the format of the day and the month comes from the system settings of macOS (version history, 2.2.17).
- A day or a day and month typed into a date field is completed with the current, the next, or the previous month (version history, 2.4.1).
- Date fields have a date picker (version history, 2.0.21).
- Amounts use the system font of macOS (version history, 2.3.0).
- The payment window shows the IBAN in groups of four characters (version history, 2.2.5).
- The app supports the dark mode of macOS and follows the system setting (version history, 2.3.8, and [feature page](https://moneymoney.app/)).
- Dates stay correct when the app is used near the date line (version history, 2.1.2).
- The interface strings include "Today", "Yesterday", "Tomorrow", a form for a number of days ago, and a form for a number of days ahead, and they include separate singular and plural forms for counts.
- Lists show amounts with a leading minus sign for withdrawals and with the currency after the number.
- Most of the message strings of the FinTS part exist in German only, so text from a bank appears in the bank's language.

### Decided for Moneten

- With a macOS language other than German or English, the interface is English.
- The rule for completing a date is fixed in the spec as the date closest to today. The version history names the three months and no exact rule.
- Negative amounts carry a minus sign and a color. The colors of MoneyMoney were not observed, because screenshots were blocked.
- Amounts are aligned on the decimal separator in lists. The alignment in MoneyMoney was not observed.
- Amount fields accept the number format of macOS and reject a value that they cannot read without doubt. MoneyMoney's rule for entry was not observed.
- An amount shows as many decimal places as its currency has.
- IBANs appear in groups of four everywhere, not only in the payment window. A copied IBAN has no spaces.
- A booking date is a calendar date and never moves with the time zone of the Mac.
