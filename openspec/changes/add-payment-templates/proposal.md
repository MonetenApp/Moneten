# Proposal: Keep transfer templates and template groups

## Why

People pay the same recipients again and again, often with a purpose that only differs by the month. A template stores the recipient once. Placeholders write the current month into the purpose. Groups of templates are also the base for batch transfers, for example a monthly payroll.

## What Changes

- A view "Templates" under "Payments" that lists transfer templates.
- Commands to create, change, delete, and use a template.
- Template groups in the sidebar, with drag and drop between groups.
- Placeholders in the purpose that the app replaces when a payment is sent.
- "Also save as template" in the payment window and "New Transfer Template..." from a transaction.
- A setting that decides whether a double click on a template edits it or sends it.
- Import and export of templates as CSV and SEPA XML.

## Capabilities

### New Capabilities

- `payment-templates`: stored recipients and payment data, template groups, placeholders, and the import and export of templates.

### Modified Capabilities

None.

## Impact

- Milestone: later
- Issues: none yet
- Modules: `Domain` owns the template type and the placeholder replacement. `Storage` keeps templates in the encrypted database. `Import` reads CSV and SEPA XML files. `App` owns the view and the template window.
- Depends on the change `add-sepa-transfers` for the payment window and the field checks.
- Depends on the change `add-main-window` for the "Payments" section and the add menu.
- The change `add-payment-outbox` adds batch transfers from a template group.
- The change `add-foreign-currency-transfers` adds templates for foreign currency transfers.
- The change `add-direct-debits` stores direct debit mandates in the same groups.
- Decisions: [ADR 0008](../../../docs/decisions/0008-payments-only-through-licensed-channels.md).

## Reference behavior

### Observed in MoneyMoney 2.5.3

- "Templates" is a row under "Payments". Its toolbar button reads "Add template". Its filter "Kind" shows "Transfer Templates". Template groups appear below it. See [main window](../../../docs/research/moneymoney-analysis.md#main-window-u).
- The context menu of "Templates" has "Add Transfer Template...", "Add Template Group", "New Batch Transfer...", "Print Templates...", "Import Transfer Templates...", "Export Transfer Templates...", "Remove...", and "Settings...". See [context menus](../../../docs/research/moneymoney-analysis.md#context-menus-u).
- The address and template management, the context command "Use Transfer Template...", "Also save as template", "New from Selection", and the double click setting are described in the [help](https://moneymoney.app/help/).
- All placeholders with examples are listed on the [templates page](https://moneymoney.app/templates/). They are replaced when a transfer or a batch transfer is submitted. The calendar week arrived in version 2.4.6.
- A double click opens the template for editing since version 2.2.16, and ⌘N sends it. The setting "Send templates with double click by default" arrived in version 2.3.12. See [settings](../../../docs/research/moneymoney-analysis.md#settings-u).
- A postal address can be added with "Set address" (version history, 2.3.4).
- The strings name a template kind for instant payments next to the transfer template.
- Templates can be dragged between groups. Removing a group removes its templates after a warning (strings).
- Import and export use CSV and SEPA XML (version history, 2.2.9). The import recognizes CSV columns by common header keywords. Templates without an IBAN cannot be saved as SEPA XML (strings).
- A template can be reassigned to another source account by opening it ([duplicate account help](https://moneymoney.app/help/dual-account/)).

### Decided for MonetenMoneten

- Placeholders use the forms of the German examples in both interface languages, for example "KW33/2024" and "2. Halbjahr 2024". The purpose goes to a German bank statement, and MoneyMoney documents no English forms.
- An unknown placeholder stays in the purpose as written, and the review step shows it. MoneyMoney's behavior was not observed.
- A CSV row that the import cannot read is skipped and reported with its line number. MoneyMoney's behavior was not observed.
- The settings of a template group hold only its name. The content of MoneyMoney's group settings popover was not observed.
- A template can hold an empty amount. This follows from the template window, which the evidence describes as editable before sending, and was not observed directly.
