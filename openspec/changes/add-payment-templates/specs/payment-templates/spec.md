# Spec Delta

## Purpose

A template stores a recipient and payment data for reuse. This capability defines templates, template groups, placeholders in the purpose, how a template becomes a payment, and the import and export of templates.

## ADDED Requirements

### Requirement: The view "Templates"

The app SHALL show a view "Templates" under "Payments" in the sidebar. The view lists every transfer template with the recipient, the IBAN, the amount, the purpose, and the source account. The toolbar button of the view reads "Add template". The status line shows the number of templates.

#### Scenario: List of templates

- **GIVEN** the templates "Miete" and "Stadtwerke"
- **WHEN** the user selects "Templates"
- **THEN** the list shows both templates and the status line shows "2 Transfer Templates"

#### Scenario: No templates

- **GIVEN** no template exists
- **WHEN** the user selects "Templates"
- **THEN** the view says that there are no transfer templates

### Requirement: Create a transfer template

The app SHALL open a template window through "New Transfer Template..." in the Payment menu, "Add Transfer Template..." in the context menu, and the toolbar button "Add template". A template holds the recipient name, the IBAN, the BIC, the purpose, an optional amount, and an optional source account. The field checks of a transfer apply to the fields that are filled.

#### Scenario: Template with a fixed amount

- **WHEN** the user creates a template for "Erika Mustermann" with the IBAN DE02120300000000202051, the amount 950,00 €, and the purpose "Miete"
- **THEN** the template appears in the list

#### Scenario: Template without an amount

- **WHEN** the user creates a template for "Stadtwerke Musterstadt" and leaves the amount empty
- **THEN** the app saves the template

#### Scenario: Invalid IBAN

- **WHEN** the user enters the IBAN DE02120300000000202052 in a template
- **THEN** the app shows the checksum error and does not save the template

### Requirement: Templates for instant payments

The app SHALL let a template hold the payment kind "bank transfer" or "instant payment". A payment from an instant payment template opens the payment window with the action "New instant payment".

#### Scenario: Instant payment template

- **GIVEN** a template for "Max Mustermann" with the kind instant payment
- **WHEN** the user uses the template
- **THEN** the payment window opens with the action "New instant payment"

### Requirement: Change a template

The app SHALL open a template with its values through "Change Transfer Template..." and save the changed values. A template can be moved to another source account this way.

#### Scenario: Recipient has a new IBAN

- **GIVEN** the template "Miete" with the IBAN DE89370400440532013000
- **WHEN** the user changes the IBAN to DE02120300000000202051 and saves
- **THEN** the list shows the new IBAN

#### Scenario: Assign another source account

- **GIVEN** the template "Miete" with the source account "Giro alt"
- **WHEN** the user opens the template, chooses "Giro neu" as the source account, and saves
- **THEN** a transfer from this template starts from "Giro neu"

### Requirement: Delete templates

The app SHALL delete the selected templates through "Delete Transfer Template..." after a confirmation. The confirmation states the number of templates and that deleted templates cannot be restored.

#### Scenario: Delete three templates

- **WHEN** the user selects 3 templates and chooses "Delete Transfer Templates..."
- **THEN** the app asks whether to delete 3 selected transfer templates and says that they cannot be restored
- **AND** the templates are removed after the user confirms

### Requirement: Postal address in a template

The app SHALL let the user add a postal address to a template through "Set address" in the gear menu of the template window. The address has a street, a place, and a country.

#### Scenario: Add an address

- **WHEN** the user chooses "Set address" and enters "Musterstraße 1", "12345 Musterstadt", and Germany
- **THEN** the template stores the address and shows it when the template is opened again

### Requirement: Template groups

The app SHALL let the user create template groups through "Add Template Group" in the Payment menu, in the add menu below the sidebar, and in the context menu of "Templates". A group appears below "Templates" in the sidebar. Selecting a group lists only its templates. The user renames a group in "Template Group Settings...".

#### Scenario: Create a group

- **WHEN** the user chooses "Add Template Group" and names the group "Gehälter"
- **THEN** "Gehälter" appears below "Templates" in the sidebar

#### Scenario: Rename a group

- **WHEN** the user opens "Template Group Settings..." for "Gehälter" and changes the name to "Löhne"
- **THEN** the sidebar shows "Löhne"

### Requirement: Move templates between groups

The app SHALL move a template to a group when the user drags it onto the group in the sidebar. A template belongs to one group or to no group.

#### Scenario: Drag into a group

- **GIVEN** the template "Max Mustermann" in no group
- **WHEN** the user drags it onto the group "Gehälter"
- **THEN** the template is listed in "Gehälter" and no longer in the ungrouped list

### Requirement: Remove a template group

The app SHALL remove a template group through "Remove Template Group..." after a confirmation. The confirmation names the group and says that all templates of the group are removed as well.

#### Scenario: Remove a group with templates

- **GIVEN** the group "Gehälter" with 12 templates
- **WHEN** the user chooses "Remove Template Group..." and confirms
- **THEN** the group and its 12 templates are removed

#### Scenario: Cancel

- **WHEN** the user cancels the confirmation
- **THEN** the group and its templates stay

### Requirement: Placeholders for the current period

The app SHALL replace placeholders in the purpose of a template when a payment from the template is submitted. The placeholders are `@MM/YYYY@` for the month, `@MMMM YYYY@` for the month name, `@QQ/YYYY@` for the quarter, `@HHHH YYYY@` for the half-year, `@YYYY@` for the year, `@WW/YYYY@` for the calendar week, `@DD.MM.YYYY@` for the date, and `@hh:mm@` for the time.

#### Scenario: Month and year

- **GIVEN** a template with the purpose "Miete @MM/YYYY@"
- **WHEN** the user submits a transfer from the template on 15 August 2024
- **THEN** the bank receives the purpose "Miete 08/2024"

#### Scenario: All period placeholders

- **GIVEN** the date 15 August 2024 and the time 09:41
- **WHEN** the app replaces `@MMMM YYYY@`, `@QQ/YYYY@`, `@HHHH YYYY@`, `@YYYY@`, `@WW/YYYY@`, `@DD.MM.YYYY@`, and `@hh:mm@`
- **THEN** the results are "August 2024", "Q3/2024", "2. Halbjahr 2024", "2024", "KW33/2024", "15.08.2024", and "09:41"

### Requirement: Placeholders for the previous and the next period

The app SHALL accept the suffixes `-1` and `+1` after the year in the placeholders for month, month name, quarter, half-year, year, and calendar week. `-1` gives the previous period and `+1` gives the next period.

#### Scenario: Previous month across a year

- **GIVEN** a template with the purpose "Abrechnung @MM/YYYY-1@"
- **WHEN** the user submits a transfer from the template on 10 January 2025
- **THEN** the bank receives the purpose "Abrechnung 12/2024"

#### Scenario: Next half-year

- **GIVEN** the date 15 August 2024
- **WHEN** the app replaces `@HHHH YYYY+1@`
- **THEN** the result is "1. Halbjahr 2025"

### Requirement: The review shows the replaced purpose

The app SHALL show the purpose with all placeholders replaced in the review step of a payment from a template. Text between two `@` signs that is not a known placeholder stays as written.

#### Scenario: Check before sending

- **GIVEN** a template with the purpose "Miete @MMMM YYYY@" on 3 November 2026
- **WHEN** the review step appears
- **THEN** it shows the purpose "Miete November 2026"

#### Scenario: Unknown placeholder

- **GIVEN** a template with the purpose "Beitrag @XYZ@"
- **WHEN** the review step appears
- **THEN** it shows the purpose "Beitrag @XYZ@"

### Requirement: Use a template

The app SHALL open the payment window filled with the data of a template through "Use Transfer Template..." in the context menu and through ⌘N while a template is selected. The transfer then follows the normal checks, the payee check, and the confirmation. The template stays unchanged when the user edits the payment window.

#### Scenario: Pay the rent

- **GIVEN** the template "Miete" with 950,00 € to "Erika Mustermann"
- **WHEN** the user chooses "Use Transfer Template..."
- **THEN** the payment window shows the recipient, the IBAN, the amount 950,00 €, and the purpose of the template

#### Scenario: Template without an amount

- **GIVEN** a template without an amount
- **WHEN** the user uses the template
- **THEN** the amount field is empty and "Next" stays disabled until the user enters an amount

### Requirement: Use several templates

The app SHALL let the user use several selected templates at once. The app opens one payment window after the other, and, when batch transfers are available, it offers to send the templates as one batch transfer instead.

#### Scenario: Two templates as single transfers

- **WHEN** the user selects 2 templates, chooses "Use Transfer Templates...", and chooses to send them as transfers
- **THEN** the payment window for the first template opens
- **AND** the payment window for the second template opens after the first one is sent or closed

### Requirement: Double click on a template

The app SHALL decide by the setting "Send templates with double click by default" what a double click on a template does. With the setting on, the payment window opens and the user confirms the payment data. With the setting off, the template window opens for editing. The setting is off by default.

#### Scenario: Setting off

- **GIVEN** the setting is off
- **WHEN** the user double-clicks the template "Miete"
- **THEN** the template window opens for editing

#### Scenario: Setting on

- **GIVEN** the setting is on
- **WHEN** the user double-clicks the template "Miete"
- **THEN** the payment window opens with the data of the template

### Requirement: Save a payment as a template

The app SHALL offer "Also save as template" in the gear menu of the payment window. When the option is on, the app saves the recipient, the IBAN, the BIC, the amount, and the purpose as a new template when the order is sent.

#### Scenario: First payment to a new recipient

- **GIVEN** the option "Also save as template" is on
- **WHEN** the user sends a transfer of 49,90 € to "Stadtwerke Musterstadt"
- **THEN** a template for "Stadtwerke Musterstadt" with 49,90 € appears in "Templates"

#### Scenario: Order is not sent

- **GIVEN** the option is on
- **WHEN** the user closes the payment window without sending
- **THEN** no template is created

### Requirement: New template from a transaction

The app SHALL offer "New from Selection" with "New Transfer Template..." in the context menu of a transaction and of a scheduled order. The template window opens with the counterparty name, the IBAN, the BIC, and the purpose of the selected row.

#### Scenario: Template from an incoming payment

- **GIVEN** a transaction from "Max Mustermann" with the IBAN DE02120300000000202051
- **WHEN** the user chooses "New from Selection" and "New Transfer Template..."
- **THEN** the template window shows "Max Mustermann" and the IBAN DE02120300000000202051

### Requirement: Import templates

The app SHALL import transfer templates from CSV files and SEPA XML files through "Import Transfer Templates...". In a CSV file the app finds the columns for name, IBAN, BIC, amount, and purpose by their header keywords in German or English. The templates enter the selected group. The app then reports the number of imported templates.

#### Scenario: CSV with German headers

- **GIVEN** a CSV file with the columns "Name", "IBAN", "Betrag", and "Verwendungszweck" and 25 rows
- **WHEN** the user imports the file into the group "Gehälter"
- **THEN** the group holds 25 new templates
- **AND** the app reports "Imported 25 transfer templates."

#### Scenario: SEPA XML file

- **GIVEN** a SEPA credit transfer file with 3 positions
- **WHEN** the user imports the file
- **THEN** the app creates one template for each position

### Requirement: Report problems during the import of templates

The app SHALL reject a file in another format with a message that names CSV and SEPA XML as the supported formats. The app skips a row that has no readable IBAN or account number and reports the line number of each skipped row.

#### Scenario: Unsupported format

- **WHEN** the user chooses a PDF file in "Import Transfer Templates..."
- **THEN** the app says that files in this format cannot be imported and names CSV and SEPA XML

#### Scenario: Row without an IBAN

- **GIVEN** a CSV file with 10 rows where row 4 has an empty IBAN
- **WHEN** the user imports the file
- **THEN** the app imports 9 templates and reports that line 4 was skipped

### Requirement: Export templates

The app SHALL export the selected templates, or all templates of the selected group when none is selected, through "Export Transfer Templates..." as a CSV file or as a SEPA XML file. A CSV file that the app exported can be imported again without loss.

#### Scenario: Export a group as CSV

- **GIVEN** the group "Gehälter" with 12 templates
- **WHEN** the user exports the group as CSV
- **THEN** the file holds 12 rows with name, IBAN, BIC, amount, and purpose

#### Scenario: Round trip

- **WHEN** the user exports a group as CSV and imports the file into an empty group
- **THEN** the new group holds templates with the same values

### Requirement: Limits of the SEPA XML export

The app SHALL write a SEPA XML file only from templates that have an IBAN and are in euro. For another selection the app says which templates to deselect.

#### Scenario: Template with a Bankleitzahl

- **GIVEN** the selection contains a template with an account number and a Bankleitzahl in place of an IBAN
- **WHEN** the user exports the selection as SEPA XML
- **THEN** the app asks the user to select only templates with an IBAN

### Requirement: Template commands follow the selection

The app SHALL enable the commands to change and to use a template only when a template is selected, and the commands for a group only when a group is selected.

#### Scenario: Nothing selected

- **GIVEN** no template is selected in "Templates"
- **WHEN** the user opens the context menu of the list
- **THEN** it offers "New Transfer Template..." and no command to change, use, or delete
