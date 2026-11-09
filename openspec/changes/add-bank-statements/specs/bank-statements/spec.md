# Spec Delta

## Purpose

Banks deliver account statements as PDF documents. This capability defines when the app downloads them, how it stores them as files that stay readable without the app, and how the user views and manages them in the "Statements" view.

## ADDED Requirements

### Requirement: Statements view

The app SHALL show all statements in the view "Statements" in the sidebar section "Documents" as a grid. Each item shows a preview of the first page and a title with the kind of statement, its number or period, its date, and its account. The newest statement comes first.

#### Scenario: Open the view

- **GIVEN** the account "Girokonto" has the statements 9/2026 from 01.10.2026 and 10/2026 from 02.11.2026
- **WHEN** the user selects "Statements"
- **THEN** the grid shows two items
- **AND** the first item is the statement 10/2026 from 02.11.2026 for "Girokonto"

#### Scenario: No statements

- **GIVEN** no statement has been downloaded or imported
- **WHEN** the user selects "Statements"
- **THEN** the view shows "No bank statements found." and a hint to open "Settings for Statements"

### Requirement: Statement kinds

The app SHALL distinguish the kinds "Account Statement", "Credit Card Statement", and "Portfolio Statement" and show the kind in the title of each statement. The kind follows the type of the account.

#### Scenario: Credit card account

- **WHEN** the app downloads a statement for an account of the type "Credit card"
- **THEN** the title of the statement starts with "Credit Card Statement"

### Requirement: Turn on the download for each account

The app SHALL offer "Settings for Statements..." with one row for each account whose access can deliver statements. For each account the user chooses under "Automatic download" between "every month", "every two weeks", "on a fixed day", and "Manual download". A new account starts with "Manual download".

#### Scenario: Activate an account

- **GIVEN** the account "Girokonto" has the setting "Manual download"
- **WHEN** the user opens "Settings for Statements...", selects "every month" for "Girokonto", and closes the settings
- **THEN** the app downloads the statements of "Girokonto" automatically from then on

#### Scenario: Account without statements

- **GIVEN** an offline account "Bargeld"
- **WHEN** the user opens "Settings for Statements..."
- **THEN** the list does not offer a download for "Bargeld"

### Requirement: Monthly download

The app SHALL, for the setting "every month", look for new statements from the first day of each month on and repeat the attempt once a day until a new statement has arrived. The settings say so next to the choice.

#### Scenario: Statement arrives on the third day

- **GIVEN** the setting "every month" and no new statement on 1 and 2 December 2026
- **WHEN** the bank provides the statement on 3 December 2026
- **THEN** the app tries on 1, 2, and 3 December and downloads the statement on 3 December
- **AND** the app does not try again before 1 January 2027

### Requirement: Download on a fixed day

The app SHALL, for the setting "on a fixed day", look for new statements once a month on the day of the month that the user selects. When the app does not run on that day, the download moves to the next day on which the app runs. The settings say so next to the choice.

#### Scenario: Fixed day

- **GIVEN** the setting "on a fixed day" with the 5th day
- **WHEN** a refresh runs on 5 December 2026
- **THEN** the app looks for new statements once
- **AND** it does not look again before 5 January 2027

#### Scenario: App not running on the day

- **GIVEN** the setting "on a fixed day" with the 5th day, and the app does not run from 4 to 7 December 2026
- **WHEN** the user starts the app on 8 December 2026 and a refresh runs
- **THEN** the app looks for new statements on 8 December

### Requirement: Download every two weeks

The app SHALL, for the setting "every two weeks", look for new statements when 14 days have passed since the last attempt.

#### Scenario: Two weeks later

- **GIVEN** the setting "every two weeks" and the last attempt on 1 December 2026
- **WHEN** a refresh runs on 15 December 2026
- **THEN** the app looks for new statements

#### Scenario: Too early

- **GIVEN** the last attempt on 1 December 2026
- **WHEN** a refresh runs on 10 December 2026
- **THEN** the app does not look for statements

### Requirement: Download on request

The app SHALL download the statements of an account at once when the user chooses "Download now" for it, with every setting. With "Manual download" this is the only way a download starts. The app then reports how many new PDF statements it downloaded, or that there were no new PDF statements.

#### Scenario: Two new statements

- **GIVEN** the bank holds two statements that the app has not downloaded
- **WHEN** the user chooses "Download now" for the account
- **THEN** the app downloads both and reports that 2 new PDF statements have been downloaded

#### Scenario: Nothing new

- **WHEN** the user chooses "Download now" and the bank holds no new statement
- **THEN** the app reports that there were no new PDF statements

### Requirement: Due downloads run inside a refresh

The app SHALL run a due automatic download during the refresh of the account, in the same bank session as the balance and the transactions. It starts no separate login for statements.

#### Scenario: Refresh on a due day

- **GIVEN** the account "Girokonto" with the setting "on a fixed day" and today is that day
- **WHEN** the automatic refresh of "Girokonto" runs
- **THEN** the app fetches the balance, the transactions, and the new statements with one login

### Requirement: A statement download that needs a TAN waits for the user

The app SHALL NOT ask for a TAN for a statement download during an automatic refresh. It postpones the download to the next refresh or "Download now" that the user starts, and the TAN dialog then names the statement download as its purpose.

#### Scenario: Bank asks for a TAN in the background

- **GIVEN** a statement download is due and the bank requires a TAN for it
- **WHEN** the automatic refresh runs
- **THEN** the app fetches the transactions, skips the statements, and shows no TAN dialog

#### Scenario: Manual refresh afterwards

- **GIVEN** a postponed statement download
- **WHEN** the user refreshes the account
- **THEN** the app shows the TAN dialog with the purpose that PDF statements are downloaded
- **AND** the dialog adds the hint that a download on a fixed day needs this confirmation only once a month
- **AND** the app downloads the statements after the TAN

### Requirement: Each statement is stored once

The app SHALL store a statement only once. A statement that the bank or an extension delivers again, with the same identifier or the same account, number, and date, is not stored a second time and not counted as new.

#### Scenario: Bank delivers an old statement again

- **GIVEN** the statement 10/2026 of "Girokonto" is already stored
- **WHEN** the bank delivers the statements 10/2026 and 11/2026
- **THEN** the app stores only 11/2026 and reports 1 new PDF statement

### Requirement: Acknowledge a fetched statement

The app SHALL confirm the receipt of a statement to the bank when the bank asks for a confirmation, after the file is stored. Without a stored file the app sends no confirmation.

#### Scenario: File stored

- **GIVEN** a bank that marks a statement as collected only after a confirmation
- **WHEN** the app has stored the PDF file
- **THEN** the app sends the confirmation to the bank

#### Scenario: File could not be stored

- **WHEN** the app cannot write the PDF file
- **THEN** the app sends no confirmation, so that the bank offers the statement again at the next download

### Requirement: Statements are stored as plain PDF files

The app SHALL store each statement as a PDF file in the "Statements" folder of the data folder, in one subfolder for the bank and one for the account. The files are not encrypted, so that Finder and other apps can open them without the app. The settings for statements say that the files are stored without encryption.

#### Scenario: Stored file

- **WHEN** the app downloads the statement 10/2026 from 02.11.2026 for the account "Girokonto" at "Musterbank"
- **THEN** a PDF file exists under "Statements/Musterbank/Girokonto"
- **AND** its file name contains the date 2026-11-02 and the number 10
- **AND** Preview opens the file without a password

### Requirement: Statements that are not PDF

The app SHALL create a PDF file from a statement that the bank delivers as text or as an MT940 statement. When it cannot create the PDF, it stores nothing and shows an error.

#### Scenario: MT940 statement

- **GIVEN** a bank that delivers statements only in MT940
- **WHEN** the app downloads a statement
- **THEN** the "Statements" view shows it as a PDF with the booked transactions and the opening and closing balance

#### Scenario: Conversion fails

- **WHEN** the app cannot create a PDF from a delivered text document
- **THEN** the app shows that it could not generate the PDF file and adds no item to the view

### Requirement: Reject downloads that are not statements

The app SHALL check that a downloaded document is a PDF before it stores it. A document in another format is not stored, and the app shows an error that names the file.

#### Scenario: Office file in place of a PDF

- **WHEN** the bank delivers a file "Auszug.docx" for a statement
- **THEN** the app shows that the downloaded file "Auszug.docx" is not in PDF format
- **AND** the view shows no new item

### Requirement: Storage errors

The app SHALL show an error that names the folder when it cannot create or write the statement folder, and it SHALL verify each written file by reading it back. A failed write leaves no partial file and no item in the view.

#### Scenario: Folder is write-protected

- **GIVEN** the "Statements" folder has no write permission
- **WHEN** the app downloads a statement
- **THEN** the app shows that it could not access the storage location, with the path of the folder and the advice to check the permissions
- **AND** the view shows no new item

### Requirement: Documents from extensions

The app SHALL show the documents that a web banking extension returns for its accounts in the "Statements" view, with the name, the date, and the account that the extension gives. The app unpacks a ZIP archive and stores each PDF inside it as one statement.

#### Scenario: Extension returns a ZIP archive

- **GIVEN** an extension returns one document as a ZIP archive with 3 PDF files
- **WHEN** the download ends
- **THEN** the view shows 3 new statements for the account of the extension

#### Scenario: Extension without document support

- **GIVEN** an extension that does not offer documents
- **WHEN** the user opens "Settings for Statements..."
- **THEN** the accounts of that extension are not offered for a download

### Requirement: Read and unread statements

The app SHALL mark a newly downloaded statement as unread and show the marker on its item. Opening a statement marks it as read. The user can mark a statement as unread again.

#### Scenario: Open an unread statement

- **GIVEN** an unread statement
- **WHEN** the user opens it
- **THEN** the marker disappears and the statement counts as read

#### Scenario: Mark as unread

- **GIVEN** a read statement
- **WHEN** the user marks it as unread through its context menu
- **THEN** the item shows the unread marker again

### Requirement: Mark all statements as read

The app SHALL mark every statement as read when the user chooses "Mark All Statements as Read" in the File menu or in the context menu of "Statements".

#### Scenario: Three unread statements

- **GIVEN** 3 unread statements
- **WHEN** the user chooses "Mark All Statements as Read"
- **THEN** no statement is unread and the count next to "Statements" disappears

### Requirement: Count of unread statements in the sidebar

The app SHALL show the number of unread statements next to "Statements" in the sidebar.

#### Scenario: New statements arrive

- **GIVEN** no unread statements
- **WHEN** a refresh downloads 2 statements
- **THEN** the sidebar shows the count 2 next to "Statements"

### Requirement: Filter statements

The app SHALL offer the filters "Period", "Status" with "Show All", "Read", and "Unread", and "Account" in the "Statements" view. The status line shows the number of statements in the grid. A hint says when a filter is active and entries might be hidden.

#### Scenario: Filter by account

- **GIVEN** 12 statements for "Girokonto" and 4 for "Kreditkarte"
- **WHEN** the user selects "Kreditkarte" in the filter "Account"
- **THEN** the grid shows 4 statements and the status line reads "4 Statements"

#### Scenario: Unread only

- **GIVEN** 16 statements of which 2 are unread
- **WHEN** the user selects "Unread" in the filter "Status"
- **THEN** the grid shows the 2 unread statements

### Requirement: Open a statement

The app SHALL open the PDF file of a statement in the default PDF application of the Mac when the user double-clicks the item or chooses "Open Statement...". With several selected items the command reads "Open Statements..." and opens all of them.

#### Scenario: Double click

- **WHEN** the user double-clicks a statement
- **THEN** the default PDF application shows the file

#### Scenario: File is missing

- **GIVEN** the user deleted the PDF file of a statement in Finder
- **WHEN** the user opens the statement in the app
- **THEN** the app shows that it could not open the statement because the file is missing

### Requirement: Show statements in Finder

The app SHALL reveal the PDF file of a selected statement with "Show in Finder", and it SHALL open the "Statements" folder with "Show in Finder..." in the context menu of "Statements".

#### Scenario: Reveal one file

- **WHEN** the user chooses "Show in Finder" for a statement
- **THEN** Finder opens the folder of the account with the file selected

### Requirement: Services for a statement

The app SHALL include the macOS Services menu in the context menu of a statement, so that the user can hand the PDF file to another app.

#### Scenario: Send by mail through a service

- **GIVEN** a service that creates an email with an attachment is enabled in macOS
- **WHEN** the user opens the context menu of a statement and chooses that service
- **THEN** the service receives the PDF file of the statement

### Requirement: Delete statements

The app SHALL delete the selected statements with "Delete Statement..." or "Delete Statements..." after a confirmation that states the number of statements and that deleted statements cannot be restored. Deleting removes the item and the PDF file.

#### Scenario: Delete two statements

- **GIVEN** 2 selected statements
- **WHEN** the user chooses "Delete Statements..." and confirms
- **THEN** both items and both PDF files are gone

#### Scenario: Cancel

- **WHEN** the user chooses "Delete Statement..." and cancels
- **THEN** the statement and its file stay

### Requirement: Import PDF statements

The app SHALL import PDF files as statements with "Import Statements..." and when the user drags PDF files into the "Statements" view. The user chooses the account and confirms the date of each statement. The app copies the files into the "Statements" folder and reports the number of imported statements. A file that is not a PDF is rejected with a message that names it.

#### Scenario: Drag three PDFs

- **WHEN** the user drags 3 PDF files into the view, chooses the account "Girokonto", and confirms
- **THEN** the view shows 3 more statements for "Girokonto"
- **AND** the app reports that it imported 3 statements
- **AND** the original files stay where they were

#### Scenario: Wrong file type

- **WHEN** the user imports the file "Auszug.txt"
- **THEN** the app shows that the file "Auszug.txt" is not in PDF format and imports nothing from it

### Requirement: Assign statements to another account

The app SHALL let the user move the selected statements to another account with "Assign Account" in the context menu. The PDF files move to the folder of the new account.

#### Scenario: Merge a duplicate account

- **GIVEN** 24 statements of the account "Girokonto alt"
- **WHEN** the user selects all 24, chooses "Assign Account", and picks "Girokonto"
- **THEN** the 24 statements belong to "Girokonto"
- **AND** their files are in the folder of "Girokonto"

### Requirement: Statements outlive their account

The app SHALL keep the statements and their PDF files when the user removes an account. The statements stay in the view without an account until the user assigns them to another account or deletes them.

#### Scenario: Remove an account

- **GIVEN** the account "Girokonto alt" with 24 statements
- **WHEN** the user removes the account
- **THEN** the 24 PDF files still exist
- **AND** the view still shows the 24 statements

### Requirement: Bank does not deliver statements

The app SHALL show a clear message for an account when the bank does not provide PDF statements for it, or when the bank delivers them only after the customer applied for it. The message says which of the two applies when the bank tells, and what the user can do.

#### Scenario: Not activated at the bank

- **GIVEN** a bank that delivers statements to financial software only after an application
- **WHEN** the user chooses "Download now"
- **THEN** the app shows that the bank either does not support the download or requires an application first, and names the bank

#### Scenario: Offline account

- **WHEN** a statement download is requested for an offline account
- **THEN** the app shows that statements cannot be downloaded from offline accounts
