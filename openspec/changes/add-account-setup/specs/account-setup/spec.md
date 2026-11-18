# Spec Delta

## Purpose

The account setup brings bank accounts into the app. This capability defines the assistant that adds accounts, the search for accounts that a bank adds later, and the change of the login data of an existing access.

## ADDED Requirements

### Requirement: Assistant with three steps

The app SHALL add accounts through an assistant that opens as a sheet on the main window. The assistant has three steps in a fixed order. The steps are the bank, the login data, and the accounts. Under its title the assistant names the step on screen and its number. Each step has "Cancel" and "Next", and the second and third step have "Back". The field of a new step takes the keyboard focus, except the bank step after "Back" when a bank is chosen.

#### Scenario: Open the assistant from the menu

- **WHEN** the user chooses "Add Account..." in the Account menu
- **THEN** the assistant opens with the title "Add Account", the line "Step 1 of 3: Bank", and the field "Bank, IBAN, or Bankleitzahl"

#### Scenario: Open the assistant from the sidebar

- **WHEN** the user chooses "Add account" in the menu under the sidebar, or "Add Account..." in the context menu of an account
- **THEN** the same assistant opens

#### Scenario: Go back one step

- **GIVEN** the assistant shows the login data step for "Musterbank" with the user ID "erika77"
- **WHEN** the user clicks "Back"
- **THEN** the assistant shows "Step 1 of 3: Bank" with the entry and the bank that the user chose before
- **AND** no field has the keyboard focus, so a user ID typed now changes nothing

#### Scenario: Go back and forth

- **GIVEN** the user went back from the login data step for "Musterbank" with the user ID "erika77"
- **WHEN** the user clicks "Next"
- **THEN** the assistant shows "Step 2 of 3: Login data" with "erika77" in the user ID field and the keyboard focus in the PIN field

### Requirement: Find the bank by name, IBAN, or Bankleitzahl

The app SHALL find the bank from a name, an IBAN, or a Bankleitzahl that the user enters in the first step, and it SHALL show the name of the bank before the user continues. The entry can contain spaces and lower case letters. For a name or the start of a Bankleitzahl, the app lists the banks of the bank directory that match, each with its place and its Bankleitzahl, and the user chooses one. The chosen bank puts its Bankleitzahl into the field.

#### Scenario: IBAN entered

- **WHEN** the user enters "de02 1203 0000 0000 2020 51"
- **THEN** the app shows the name of the bank with the Bankleitzahl 12030000
- **AND** "Next" is enabled

#### Scenario: Bankleitzahl entered

- **WHEN** the user enters "12030000"
- **THEN** the app shows the name of the same bank

#### Scenario: Name entered

- **GIVEN** the bank directory lists "Consorsbank" twice, in München with the Bankleitzahl 70120400 and in Nürnberg with 76030080
- **WHEN** the user enters "consors"
- **THEN** the list shows both banks with their places and Bankleitzahlen, the bank in Nürnberg first and highlighted, because 76030080 is the Bankleitzahl that Consorsbank names as its own
- **AND** "Next" chooses it and shows it under the field with "Nürnberg · 76030080", and the down arrow highlights the bank in München

#### Scenario: Umlauts and accents

- **WHEN** the user enters "munchen", "muenchen", or "München"
- **THEN** the list shows the same banks of the place München

#### Scenario: Part of a word

- **GIVEN** the bank directory lists "Sparkasse Freiburg-Nördlicher Breisgau" and "Stadtsparkasse München"
- **WHEN** the user enters "sparkasse"
- **THEN** the list shows both banks, "Sparkasse Freiburg-Nördlicher Breisgau" first, because its name starts with the entry

#### Scenario: Short name of a bank

- **WHEN** the user enters "DKB"
- **THEN** the list shows "Deutsche Kreditbank Berlin"

#### Scenario: Start of a Bankleitzahl in groups

- **WHEN** the user enters "760 30"
- **THEN** the list shows the banks whose Bankleitzahl starts with 76030, Consorsbank 76030080 first

#### Scenario: Brand of a bank

- **GIVEN** the bank directory names the Bankleitzahl 83065408 "VR-Bank Altenburger Land" and 51090000 "Wiesbadener Volksbank", and Skatbank and Ordensbank are brands of these two banks
- **WHEN** the user enters "skatbank"
- **THEN** the list starts with "VR-Bank Altenburger Land / Skatbank" with 83065408
- **AND** "ordensbank" lists "Wiesbadener Volksbank / Ordensbank" with 51090000 first

#### Scenario: Short name of a bank with a FinTS address

- **GIVEN** the bank directory names the Bankleitzahl 30060601 "Deutsche Apotheker- und Ärztebank eG" with a FinTS address, and other Bankleitzahlen "apoBank" without one
- **WHEN** the user enters "apobank"
- **THEN** the list starts with "Deutsche Apotheker- und Ärztebank eG" with 30060601

#### Scenario: Brand on the Bankleitzahl of another bank

- **GIVEN** the bank directory names the Bankleitzahl 10010010 "Postbank" in Berlin, and FYRST is the business brand of Postbank on the same Bankleitzahl
- **WHEN** the user enters "fyrst"
- **THEN** the list shows "Postbank / FYRST" with "Berlin · 10010010"
- **AND** "postbank" lists it too

#### Scenario: Brands of flatexDEGIRO Bank

- **GIVEN** the bank directory names the Bankleitzahl 10130800 "biw Bank für Investments und Wertpapiere", and flatex, DEGIRO, and ViTrade are brands of flatexDEGIRO Bank on the Bankleitzahlen 10130800, 30330800, and 76030800
- **WHEN** the user enters "degiro"
- **THEN** the list shows 10130800 as "flatexDEGIRO Bank (flatex, DEGIRO, ViTrade)"
- **AND** "flatex" and "vitrade" list it too
- **AND** the neighbor 10130600 "Isbank AG" keeps its name

#### Scenario: Old entry of a merged bank

- **GIVEN** the bank directory lists "Sparkasse Bonn -alt-" and "Sparkasse KölnBonn"
- **WHEN** the user enters "sparkasse bonn"
- **THEN** "Sparkasse KölnBonn" comes before "Sparkasse Bonn -alt-"

#### Scenario: Several Bankleitzahlen of one bank

- **GIVEN** the bank directory lists comdirect with eight Bankleitzahlen, of which comdirect names four as its own
- **WHEN** the user enters "comdirect"
- **THEN** the four come first, so "Next" chooses 20041111

#### Scenario: No bank matches

- **WHEN** the user enters "keine bank"
- **THEN** the app says that no bank matches “keine bank”

#### Scenario: Empty field

- **WHEN** the user clicks "Next" with an empty field and "Other" not selected
- **THEN** the app asks for the name of the bank, an IBAN, or a Bankleitzahl and stays on the first step

### Requirement: Check the IBAN before any connection

The app SHALL check an IBAN for its country code, its length for that country, and its checksum, and it SHALL name the failed check. The app contacts no bank while the IBAN is invalid.

#### Scenario: Wrong checksum

- **WHEN** the user enters "DE03120300000000202051"
- **THEN** the app says that the checksum of the IBAN is invalid and asks the user to look for typing errors

#### Scenario: Too short

- **WHEN** the user enters "DE0212030000000020205"
- **THEN** the app says that an IBAN with the country code DE has 22 characters

#### Scenario: Unknown country code

- **WHEN** the user enters an IBAN that starts with "XX"
- **THEN** the app says that the IBAN starts with an unexpected country code

### Requirement: Point customers of 1822direkt to its Bankleitzahl

The app SHALL tell the user in the first step that a customer of 1822direkt enters the Bankleitzahl 50050222 in place of the IBAN, when the entered IBAN carries the Bankleitzahl 50050201. 1822direkt gives its customers IBANs with the Bankleitzahl of Frankfurter Sparkasse, and its FinTS server has the Bankleitzahl 50050222. A Bankleitzahl that the user enters or chooses gets no such note.

#### Scenario: IBAN with the Bankleitzahl of Frankfurter Sparkasse

- **GIVEN** the bank directory lists 50050201 as "Frankfurter Sparkasse" and 50050222 as "1822direkt (PIN/TAN)"
- **WHEN** the user enters "DE24500502010000202051"
- **THEN** the app shows "Frankfurter Sparkasse"
- **AND** the app says that a customer of 1822direkt enters the Bankleitzahl 50050222 in place of the IBAN

#### Scenario: Bankleitzahl of Frankfurter Sparkasse

- **WHEN** the user enters "50050201"
- **THEN** the app shows "Frankfurter Sparkasse" without that note

### Requirement: Check the Bankleitzahl

The app SHALL reject a Bankleitzahl that is not in the bank directory, also when it is part of an IBAN, and SHALL never say that a Bankleitzahl in the bank directory is outdated.

#### Scenario: Unknown Bankleitzahl

- **WHEN** the user enters "00000000"
- **THEN** the app says that the Bankleitzahl is invalid

#### Scenario: Bankleitzahl of a merged bank is not called outdated

- **GIVEN** the bank directory lists 21099999 as "Sparkasse Altstadt -alt-" with a FinTS address
- **WHEN** the user enters an IBAN that contains 21099999
- **THEN** the app does not say that the IBAN or the Bankleitzahl is outdated
- **AND** the app does not ask for another IBAN

### Requirement: Note for the Bankleitzahl of a merged bank

The app SHALL accept a Bankleitzahl that the bank directory lists for a bank that merged, as it accepts any Bankleitzahl with a FinTS address, and SHALL show a note in the first step that the bank merged and the login may need another Bankleitzahl.

#### Scenario: IBAN of a merged bank

- **GIVEN** the bank directory lists 21099999 as "Sparkasse Altstadt -alt-" with a FinTS address
- **WHEN** the user enters "DE07 2109 9999 0000 2020 51"
- **THEN** the app shows "Sparkasse Altstadt -alt-" and the note "This Bankleitzahl belongs to a bank that merged. If the login fails, ask your bank which Bankleitzahl it uses for online banking now."
- **AND** "Next" leads to the login data

#### Scenario: Merged bank entered or chosen

- **GIVEN** the bank directory lists 21099999 as "Sparkasse Altstadt -alt-" and 21099990 as "Raiffeisenbank Altdorf -alt", both with a FinTS address
- **WHEN** the user enters "21099990", or chooses "Sparkasse Altstadt -alt-" among the matches for "Altstadt"
- **THEN** the app shows the bank with the same note
- **AND** "Next" leads to the login data

#### Scenario: Merged bank without a FinTS server

- **GIVEN** the bank directory lists 21099999 as "Sparkasse Altstadt -alt-" without a FinTS address
- **WHEN** the user enters "21099999"
- **THEN** the app says that this bank does not provide a FinTS/HBCI server and shows no note
- **AND** the assistant stays on the first step

### Requirement: Country menu

The app SHALL offer a country menu in the first step with the entries for Germany, Austria, and the European Union. The selected country decides which banks the app finds and which services "Other" lists. The menu starts with Germany.

#### Scenario: Service of another country

- **GIVEN** an installed extension declares a service for Austria only
- **WHEN** the user selects Austria in the country menu
- **THEN** "Other" lists that service
- **AND** "Other" does not list it while Germany is selected

### Requirement: Other services

The app SHALL offer the choice "Other" in the first step as an alternative to the IBAN field. "Other" lists every service that an installed web banking extension declares, in alphabetical order, and "Offline account / Cash" as the last entry.

#### Scenario: Extension service

- **GIVEN** an installed extension declares the service "Musterbroker"
- **WHEN** the user selects "Other" and opens its menu
- **THEN** the menu contains "Musterbroker" and "Offline account / Cash"

#### Scenario: Offline account

- **WHEN** the user selects "Offline account / Cash" and clicks "Next"
- **THEN** the assistant asks for the name and the currency of the account and contacts no bank

### Requirement: Choose the access method

The app SHALL show the access methods that are possible for the bank under "Access with" when there is more than one, and it SHALL let the user choose one. A method that the app knows and that the bank does not offer is listed as disabled with its reason.

#### Scenario: Bank with FinTS and an extension

- **GIVEN** "Musterbank" offers FinTS with a TAN method, and an installed extension also supports "Musterbank"
- **WHEN** the user enters the Bankleitzahl of "Musterbank"
- **THEN** "Access with" lists "FinTS/HBCI with TAN method" and the extension
- **AND** "FinTS/HBCI with TAN method" is selected

#### Scenario: Only one method

- **GIVEN** "Musterbank" offers only FinTS with a TAN method and no extension supports it
- **WHEN** the user enters its Bankleitzahl
- **THEN** the app shows no choice and continues with FinTS

### Requirement: Explain why a bank cannot be added

The app SHALL tell the user why no access is possible when it finds the bank and knows no way to reach it. The message names the bank and the ways that would work, which are an extension for that bank or the optional subscription.

#### Scenario: Bank without a FinTS server

- **GIVEN** the bank directory lists "Neobank Muster" without a FinTS address, and no installed extension supports it
- **WHEN** the user enters an IBAN of "Neobank Muster" and clicks "Next"
- **THEN** the app says that this bank does not provide a FinTS/HBCI server
- **AND** the app says that an extension can add support for the bank
- **AND** the assistant stays on the first step

### Requirement: Ask for the login data in the words of the bank

The app SHALL ask for the login data in the second step with the field names that the bank or the extension uses, and it SHALL mark which fields are optional. "Next" stays disabled until every required field has a value.

#### Scenario: Bank with its own field name

- **GIVEN** "Musterbank" calls its login name "VR-NetKey or alias"
- **WHEN** the assistant shows the second step
- **THEN** the first field has the label "VR-NetKey or alias" and the second field has the label "PIN"

#### Scenario: Consorsbank

- **GIVEN** the user chose Consorsbank with the Bankleitzahl 76030080
- **WHEN** the assistant shows the second step
- **THEN** the first field has the label "Account number + 001"
- **AND** the line under it says that Consorsbank expects the account number followed by the three-digit Berechtigtennummer, usually 001

#### Scenario: Other bank on the same FinTS server

- **GIVEN** the user chose DAB BNP Paribas with the Bankleitzahl 70120400, which uses the FinTS server of Consorsbank
- **WHEN** the assistant shows the second step
- **THEN** the first field has the label "User ID" and no hint, because no page of the bank confirms its login

#### Scenario: Savings bank

- **GIVEN** the user chose a Sparkasse whose FinTS address is on the servers of the savings banks
- **WHEN** the assistant shows the second step
- **THEN** the first field has the label "Login name or Legitimations-ID"

#### Scenario: Cooperative bank

- **GIVEN** the user chose Wiesbadener Volksbank with the Bankleitzahl 51090000, whose FinTS address is on the host `fints2.atruvia.de`
- **WHEN** the assistant shows the second step
- **THEN** the first field has the label "VR-NetKey or alias"
- **AND** the line under it says that a Volksbank or Raiffeisenbank expects the VR-NetKey or the alias of its online banking

#### Scenario: Sparda-Bank on the servers of the cooperative banks

- **GIVEN** the user chose Sparda-Bank Baden-Württemberg with the Bankleitzahl 60090800, whose FinTS address is on the host `fints2.atruvia.de`
- **WHEN** the assistant shows the second step
- **THEN** the first field has the label "User ID" and no hint, because a Sparda-Bank calls its login name differently

#### Scenario: Commerzbank

- **GIVEN** the user chose Commerzbank with the Bankleitzahl 50040000, whose FinTS address is on the host `fints.commerzbank.de`
- **WHEN** the assistant shows the second step
- **THEN** the first field has the label "Participant number"
- **AND** the line under it says that Commerzbank expects the 10-digit participant number, and that Commerzbank must switch on "FinTS/HBCI with photoTAN" for the user

#### Scenario: Deutsche Bank

- **GIVEN** the user chose Deutsche Bank with the Bankleitzahl 37070060, whose FinTS address is on the host `fints.deutsche-bank.de`
- **WHEN** the assistant shows the second step
- **THEN** the first field has the label "Deutsche Bank ID"
- **AND** the line under it says that the Deutsche Bank ID is the branch and account number without the subaccount number, unless the user chose an ID of their own

#### Scenario: Postbank and FYRST

- **GIVEN** the user chose Postbank with the Bankleitzahl 10010010, whose FinTS address is on the host `hbci.postbank.de`
- **WHEN** the assistant shows the second step
- **THEN** the first field has the label "Postbank ID"
- **AND** the line under it says that a business profile needs the Postbank ID followed by "#" and the profile name, in the form `Postbank-ID#Profil`

#### Scenario: norisbank

- **GIVEN** the user chose norisbank with the Bankleitzahl 10077777, whose FinTS address is on the host `fints.norisbank.de`
- **WHEN** the assistant shows the second step
- **THEN** the first field has the label "User ID" and no hint, because no public page of the bank names its FinTS login

#### Scenario: Baader Bank and the brokers on it

- **GIVEN** the user chose Baader Bank with the Bankleitzahl 70033100, whose FinTS address is `https://fints.baaderbank.de`
- **WHEN** the assistant shows the second step
- **THEN** the first field has the label "Stammnummer"
- **AND** the line under it says that Baader Bank expects the Stammnummer that the broker gives the user, and links to `https://konto.baaderbank.de/`

#### Scenario: Bank on the FinTS server of Baader Bank with another Bankleitzahl

- **GIVEN** the user chose a bank with the Bankleitzahl 70033199, whose FinTS address is on the host `FINTS.BAADERBANK.DE`
- **WHEN** the assistant shows the second step
- **THEN** the first field has the label "Stammnummer", because the app finds this hint by the host of the FinTS address and compares the host in lower case

#### Scenario: Bank on another host

- **GIVEN** the user chose a bank whose FinTS address is on the host `fints.baaderbank.de.example.com`
- **WHEN** the assistant shows the second step
- **THEN** the first field has the label "User ID" and no hint

#### Scenario: Optional customer ID

- **GIVEN** "Musterbank" accepts a customer ID in addition to the user ID
- **WHEN** the user fills in "User ID" and "PIN" and leaves the customer ID empty
- **THEN** "Next" is enabled

### Requirement: Send a login name of 17 digits to a savings bank as 16 digits

The app SHALL send and store the first 16 digits of a login name that has exactly 17 digits, when the bank is on the FinTS servers of the savings banks. A bank is on these servers when the part of its FinTS host before ".de" starts with "s-fints-pt-" or is "s-hbci". Any other login name, and any login name at another bank, stays as the user typed it. Two login names that agree in this form are the same login.

#### Scenario: Login name of 17 digits

- **GIVEN** the user chose a Sparkasse with the FinTS address "https://banking-hs6.s-fints-pt-hs.de/fints30"
- **WHEN** the user enters the login name "12345678901234567" and clicks "Next"
- **THEN** the app sends the login name "1234567890123456"
- **AND** the access stores the login name "1234567890123456"

#### Scenario: Login name of 17 characters with a letter

- **GIVEN** the user chose a Sparkasse with the FinTS address "https://banking-hs6.s-fints-pt-hs.de/fints30"
- **WHEN** the user enters the login name "1234567890123456A" and clicks "Next"
- **THEN** the app sends and stores "1234567890123456A"

#### Scenario: Login name of 17 digits at another bank

- **GIVEN** the user chose "Musterbank" with the FinTS address "https://fints.musterbank.example/fints"
- **WHEN** the user enters the login name "12345678901234567" and clicks "Next"
- **THEN** the app sends and stores "12345678901234567"

#### Scenario: New login name of 17 digits in "Edit Login Data..."

- **GIVEN** an access of a Sparkasse with the FinTS address "https://banking-hs6.s-fints-pt-hs.de/fints30"
- **WHEN** the user enters the login name "12345678901234567" in "Edit Login Data..." and clicks "Next"
- **THEN** the app sends and stores "1234567890123456"

#### Scenario: Access of 17 digits that the app stored before

- **GIVEN** an access of a Sparkasse with the FinTS address "https://banking-hs6.s-fints-pt-hs.de/fints30" stores the login name "12345678901234567"
- **WHEN** the app refreshes the access
- **THEN** the app sends "1234567890123456" to the bank

#### Scenario: Same login with 16 digits

- **GIVEN** an access of a Sparkasse with the FinTS address "https://banking-hs6.s-fints-pt-hs.de/fints30" stores the login name "12345678901234567"
- **WHEN** the user adds an account of the same bank with the login name "1234567890123456"
- **THEN** the setup joins the access that the app has, and the app keeps one access with the login name "1234567890123456"

### Requirement: Check the format of login fields

The app SHALL check each login field against the format that the bank directory or the extension declares for it, before it contacts the bank, and name the field and the broken rule. Formats cover digits only, a minimum and a maximum length, an exact length, characters that are not allowed, an email address, a date, and a phone number with or without a country code.

#### Scenario: User ID with a fixed length

- **GIVEN** "Musterbank" declares a user ID of exactly 10 digits
- **WHEN** the user enters "12345" and clicks "Next"
- **THEN** the app says that the user ID must be 10 digits long and stays on the second step

#### Scenario: Date of birth

- **GIVEN** an extension declares a field "Date of birth" as a date
- **WHEN** the user enters "1.2.80"
- **THEN** the app says that the date of birth must be in the format DD.MM.YYYY

#### Scenario: Long alias at a cooperative bank

- **GIVEN** the chosen bank has its FinTS address on a host that ends in `.atruvia.de` or `.bankenit.de`
- **WHEN** the user enters a login name of 31 characters and clicks "Next"
- **THEN** the app says that the FinTS server of the bank accepts no alias longer than 30 characters and that the user changes the alias in the online banking of the bank first
- **AND** the app sends nothing to the bank and stays on the second step

#### Scenario: Six character PIN at a cooperative bank

- **GIVEN** the chosen bank has its FinTS address on a host that ends in `.atruvia.de` or `.bankenit.de`, and its bank parameters require a PIN of at least 8 characters
- **WHEN** the user enters the PIN "123456"
- **THEN** the app says that the FinTS server of the bank no longer accepts PINs of 6 characters and that the user sets a longer PIN in the online banking of the bank first
- **AND** the app sends nothing to the bank
- **AND** the PIN sheet of a refresh shows the same message for the same PIN

### Requirement: Send the login name in the form that the bank expects

The app SHALL send and store a VR-Kennung in capitals and without spaces when the FinTS address of the bank is on a host that ends in `.atruvia.de` or `.bankenit.de`, or on the host `fints.apobank.de`. A VR-Kennung is a login name that starts with "VRK" in any case and has only digits after it once the spaces are removed. Any other login name stays as the user typed it. Two login names that agree in this form are the same login.

#### Scenario: VR-Kennung in lower case

- **GIVEN** the user chose Wiesbadener Volksbank on the host `fints2.atruvia.de`
- **WHEN** the user enters the login name "vrk 12345678" and clicks "Next"
- **THEN** the app sends "VRK12345678" to the bank
- **AND** the access stores "VRK12345678" as its login name

#### Scenario: Alias that starts with the same letters

- **GIVEN** the user chose Wiesbadener Volksbank on the host `fints2.atruvia.de`
- **WHEN** the user enters the login name "vrkonto1"
- **THEN** the app sends "vrkonto1"

#### Scenario: Bank on another server

- **GIVEN** the user chose a bank whose FinTS address is on another host
- **WHEN** the user enters the login name "vrk12345678"
- **THEN** the app sends "vrk12345678"

#### Scenario: Access that the app stored before

- **GIVEN** an access to a bank on `fints1.atruvia.de` stores the login name "vrk12345678"
- **WHEN** the app refreshes the access
- **THEN** the app sends "VRK12345678" to the bank

#### Scenario: Same login in another case

- **GIVEN** an access to Wiesbadener Volksbank on `fints2.atruvia.de` stores the login name "vrk12345678"
- **WHEN** the user adds an account of the same bank with the login name "VRK12345678"
- **THEN** the setup joins the access that the app has, and the app keeps one access with the login name "VRK12345678"

### Requirement: Send a login name of 8 digits to Commerzbank as the participant number

The app SHALL send and store "00" followed by the login name when the login name has exactly 8 digits and the FinTS address of the bank is on the host `fints.commerzbank.de` or `hbci.commerzbank.de`. Any other login name, and any login name at another bank, stays as the user typed it. Two login names that agree in this form are the same login.

#### Scenario: Login name of 8 digits

- **GIVEN** the user chose Commerzbank with the FinTS address "https://fints.commerzbank.de/fints"
- **WHEN** the user enters the login name "12345678" and clicks "Next"
- **THEN** the app sends the login name "0012345678"
- **AND** the access stores the login name "0012345678"

#### Scenario: Participant number of 10 digits

- **GIVEN** the user chose Commerzbank with the FinTS address "https://fints.commerzbank.de/fints"
- **WHEN** the user enters the login name "0012345678"
- **THEN** the app sends "0012345678"

#### Scenario: Login name with letters

- **GIVEN** the user chose Commerzbank with the FinTS address "https://fints.commerzbank.de/fints"
- **WHEN** the user enters the login name "mueller7"
- **THEN** the app sends "mueller7"

#### Scenario: Login name of 8 digits at another bank

- **GIVEN** the user chose comdirect with the FinTS address "https://fints.comdirect.de/fints"
- **WHEN** the user enters the login name "12345678"
- **THEN** the app sends "12345678"

#### Scenario: Access of 8 digits that the app stored before

- **GIVEN** an access of Commerzbank with the FinTS address "https://fints.commerzbank.de/fints" stores the login name "12345678"
- **WHEN** the app refreshes the access
- **THEN** the app sends "0012345678" to the bank
- **AND** a second setup with the login name "0012345678" joins that access

### Requirement: Send the login name of Deutsche Bank, Postbank, and norisbank without spaces

The app SHALL send and store the login name without any space when the FinTS address of the bank is on a host that ends in `.deutsche-bank.de`, `.postbank.de`, or `.norisbank.de`. Users copy the number in groups from the bank card or the letter of the bank, and the FinTS login of these banks has no spaces. Two login names that agree without spaces are the same login.

#### Scenario: Branch and account number in groups

- **GIVEN** the user chose Deutsche Bank with the FinTS address `https://fints.deutsche-bank.de/`
- **WHEN** the user enters the login name "123 4567890" and clicks "Next"
- **THEN** the app sends "1234567890" to the bank
- **AND** the access stores "1234567890" as its login name

#### Scenario: Postbank ID with a space

- **GIVEN** the user chose Postbank with the FinTS address `https://hbci.postbank.de/banking/hbci.do`
- **WHEN** the user enters the login name "erika muster#Profil" and clicks "Next"
- **THEN** the app sends and stores "erikamuster#Profil"

#### Scenario: Access that the app stored before

- **GIVEN** an access to norisbank on `fints.norisbank.de` stores the login name "123 4567890"
- **WHEN** the app refreshes the access
- **THEN** the app sends "1234567890" to the bank

#### Scenario: Same login in groups

- **GIVEN** an access to Deutsche Bank on `fints.deutsche-bank.de` stores the login name "1234567890"
- **WHEN** the user adds an account of the same bank with the login name "123 4567890"
- **THEN** the setup joins the access that the app has

#### Scenario: Bank on another server

- **GIVEN** the user chose "Musterbank" with the FinTS address "https://fints.musterbank.example/fints"
- **WHEN** the user enters the login name "123 4567890"
- **THEN** the app sends "123 4567890"

### Requirement: Show a login name of Deutsche Bank and norisbank as branch and account number

The app SHALL show a stored login name of exactly 10 digits as the branch number of 3 digits, a space, and the account number of 7 digits, when the FinTS address of the bank is on a host that ends in `.deutsche-bank.de` or `.norisbank.de`. The user then recognizes the number of the bank card. The app sends and stores the login name without the space.

#### Scenario: Edit Login Data

- **GIVEN** an access to norisbank on `fints.norisbank.de` stores the login name "1234567890"
- **WHEN** the user opens "Edit Login Data..."
- **THEN** the login name field reads "123 4567890"
- **AND** saving without a change keeps the login name "1234567890"

#### Scenario: PIN dialog

- **GIVEN** an access to Deutsche Bank on `fints.deutsche-bank.de` stores the login name "1234567890"
- **WHEN** a refresh asks for the PIN
- **THEN** the dialog shows the user ID "123 4567890"

#### Scenario: Postbank

- **GIVEN** an access to Postbank on `hbci.postbank.de` stores the login name "1234567890"
- **WHEN** a refresh asks for the PIN
- **THEN** the dialog shows the user ID "1234567890"

#### Scenario: Deutsche Bank ID of the user's choice

- **GIVEN** an access to Deutsche Bank on `fints.deutsche-bank.de` stores the login name "erikamuster"
- **WHEN** a refresh asks for the PIN
- **THEN** the dialog shows the user ID "erikamuster"

### Requirement: Show what the bank requires before the first login

The app SHALL show a hint in the second step when the app, the bank directory, or the extension holds a note for the bank, for example that the user must apply for the FinTS access first or must set up a TAN method on the bank website first.

#### Scenario: Access must be requested

- **GIVEN** the note for "Musterbank" says that the FinTS access must be requested from the bank
- **WHEN** the assistant shows the second step
- **THEN** the app shows that note above the fields

#### Scenario: Savings bank

- **GIVEN** the user chose a Sparkasse with the FinTS address "https://banking-hs6.s-fints-pt-hs.de/fints30"
- **WHEN** the assistant shows the second step
- **THEN** the app shows above the fields that the user logs in with the login name and the PIN of the online banking of the Sparkasse
- **AND** the app says that the user sets up a TAN method such as pushTAN or chipTAN in the online banking before the first login

#### Scenario: Commerzbank

- **GIVEN** the user chose Commerzbank with the Bankleitzahl 50040000, whose FinTS address is on the host `fints.commerzbank.de`
- **WHEN** the assistant shows the second step
- **THEN** the app shows above the fields that the user requests the access at "https://www.commerzbank.de/hbci" first
- **AND** the app says that Commerzbank must switch on "FinTS/HBCI with photoTAN" for the user, also when the user already uses photoTAN on the website

#### Scenario: comdirect

- **GIVEN** the user chose comdirect with the Bankleitzahl 20041111, whose FinTS address is on the host `fints.comdirect.de`
- **WHEN** the assistant shows the second step
- **THEN** the app shows above the fields that the user sets up a TAN method such as photoTAN on the website of comdirect first
- **AND** the app says that comdirect needs about two business days before its FinTS server accepts the method, and that the user tries again later with "Edit Login Data..."

#### Scenario: flatexDEGIRO Bank

- **GIVEN** the user chose the bank of 10130800, 30330800, or 76030800
- **WHEN** the assistant shows the second step
- **THEN** the app shows above the fields that the FinTS access of flatexDEGIRO Bank serves flatex accounts
- **AND** the app says that DEGIRO and ViTrade offer no FinTS access, so their accounts cannot be added with FinTS
- **AND** the neighbor 76030080 of Consorsbank shows only its own hint

#### Scenario: Baader Bank

- **GIVEN** the user chose Baader Bank with the Bankleitzahl 70033100, whose FinTS address is `https://fints.baaderbank.de`
- **WHEN** the assistant shows the second step
- **THEN** the app shows above the fields that the user requests the FinTS access and its PIN at `https://konto.baaderbank.de/` first

#### Scenario: Credit card

- **WHEN** the user opens the help of the first step
- **THEN** the help says that a credit card is added with the Bankleitzahl of the bank that issued the card, or with "Look for New Accounts..." on the giro account of that bank

### Requirement: Report a failed login without leaving the assistant

The app SHALL show the message of the bank when the login fails, keep the user on the second step with the entries intact except for the PIN, and store nothing.

#### Scenario: Wrong PIN

- **WHEN** the user enters a wrong PIN and clicks "Next"
- **THEN** the app shows that the bank did not accept the PIN or the user ID, with the text that the bank sent
- **AND** the app says that many banks give this answer also for a wrong user ID, and that more wrong attempts can block the access
- **AND** the PIN field is empty and the user ID is still filled in
- **AND** the app does not try the login again by itself

#### Scenario: Wrong user ID that the bank reports as a wrong PIN

- **GIVEN** the user chose Consorsbank and entered the account number without "001"
- **WHEN** the bank answers "PIN ungültig"
- **THEN** the message asks the user to check the user ID as well and repeats that Consorsbank expects the account number followed by the Berechtigtennummer

#### Scenario: Commerzbank rejects the first login

- **GIVEN** the user chose Commerzbank with the Bankleitzahl 50040000
- **WHEN** the bank answers the first login with the code 9942 and the text "PIN ungültig"
- **THEN** the message repeats that Commerzbank expects the 10-digit participant number and must switch on "FinTS/HBCI with photoTAN" for the user

#### Scenario: Baader Bank rejects the first login

- **GIVEN** the user chose Baader Bank with the Bankleitzahl 70033100, whose FinTS address is `https://fints.baaderbank.de`
- **WHEN** the bank answers the first login with the code 9942 and the text "PIN ungültig"
- **THEN** the message says that the Stammnummer may not be valid, that Baader Bank expects the Stammnummer from the broker, and that the user requests the FinTS access first
- **AND** the app stays on the second step

#### Scenario: Login name is an alias that the bank rejects

- **WHEN** the bank rejects the alias "erika.m"
- **THEN** the app asks for the user ID in place of the alias

### Requirement: Progress and cancel during setup

The app SHALL show the progress text "Setting up Accounts" with the current step of the bank dialog while it talks to the bank, and it SHALL let the user cancel at any time. A canceled setup leaves no access, no account, and no saved PIN.

#### Scenario: Cancel while the bank asks for a TAN

- **GIVEN** the bank asks for a TAN during the first login
- **WHEN** the user cancels the TAN dialog and then clicks "Cancel" in the assistant
- **THEN** the sidebar shows no new account
- **AND** a new start of the assistant begins with empty fields

### Requirement: Select the accounts to add

The app SHALL list in the third step every account that the bank reports for the login, with the name, the account type, the IBAN or account number, and the currency. All accounts are selected at first. The user selects which ones to add and needs at least one.

#### Scenario: Three accounts found

- **GIVEN** the bank reports a giro account, a savings account, and a portfolio for the login
- **WHEN** the assistant shows the third step
- **THEN** the list has three rows and all three are selected

#### Scenario: Nothing selected

- **WHEN** the user deselects all accounts
- **THEN** the button that finishes the assistant is disabled

#### Scenario: Bank reports no account

- **WHEN** the login succeeds and the bank reports no account
- **THEN** the app says that the bank reported no accounts for this login, and suggests the user ID in place of an alias or a request for FinTS access at the bank

### Requirement: Do not add an account twice

The app SHALL mark an account in the third step as already present when the app has the same account with a bank access or as an offline account, also a closed one, and it SHALL not add that account again. A closed account without a bank access is left as it is, and the account of the bank is added as a new account.

#### Scenario: Existing giro account

- **GIVEN** the app already has the account with the IBAN DE02120300000000202051
- **WHEN** the bank reports that IBAN again together with a new savings account
- **THEN** the row of the giro account is marked as already present and cannot be selected
- **AND** only the savings account is added

### Requirement: Tell the accounts of a bank apart

The app SHALL treat two accounts as the same account only when they have the same currency and the same IBAN. When one of them has no IBAN, they are the same when they have the same currency, account number, and Bankleitzahl, and, when the account in the app has a bank access, the same ID at the bank. The ID at the bank is the IBAN when the bank reports one, and else the account number with the subaccount number.

#### Scenario: Same IBAN in another currency

- **GIVEN** the app has the offline account "Giro USD" in USD with the IBAN DE02120300000000202051
- **WHEN** the bank reports that IBAN in EUR
- **THEN** the row is not marked as present
- **AND** the setup adds a new account in EUR and leaves "Giro USD" as it is

#### Scenario: Closed account without a bank access

- **GIVEN** the app has the closed migrated account "Giro (alt)" in EUR with the IBAN DE02120300000000202051, and no other account with that IBAN
- **WHEN** the bank reports that IBAN in EUR
- **THEN** the row is not marked as present
- **AND** the setup adds a new account and leaves "Giro (alt)" closed and without a bank access

#### Scenario: Another subaccount of the same account number

- **GIVEN** the app has the account "Sparkonto" with a bank access, the account number 9, and the subaccount number 01 at the Bankleitzahl 12030000
- **WHEN** the bank reports the subaccounts 01 and 02 of the account number 9
- **THEN** the row of subaccount 01 is marked as already present
- **AND** the row of subaccount 02 can be selected and is added as a new account

### Requirement: Finish the setup

The app SHALL, when the user finishes the assistant, add the selected accounts to the sidebar under one access, select the first new account, and start the first refresh of the new accounts.

#### Scenario: Two accounts added

- **WHEN** the user finishes the assistant with a giro account and a savings account selected
- **THEN** both accounts appear in the sidebar with the names that the bank reported
- **AND** the app starts a refresh that fetches their balances and transactions

#### Scenario: Assistant opened on a group

- **GIVEN** the user opened the assistant from the context menu of the account group "Private"
- **WHEN** the user finishes the assistant
- **THEN** the new accounts are in the group "Private"

### Requirement: Look for new accounts

The app SHALL offer "Look for New Accounts..." for an account with a FinTS access. The command asks the bank for the accounts of that login and opens the account selection with only the accounts that the app does not have yet.

#### Scenario: New credit card

- **GIVEN** the bank added a credit card to the login of the giro account "Giro"
- **WHEN** the user chooses "Look for New Accounts..." on "Giro"
- **THEN** the app shows the progress text "Looking for new Accounts"
- **AND** the selection lists the credit card and not "Giro"

#### Scenario: No new account

- **WHEN** the bank reports only accounts that the app already has
- **THEN** the app says that there are no new accounts

#### Scenario: Access that is being refreshed

- **GIVEN** the app refreshes the access of "Giro"
- **WHEN** the user chooses "Look for New Accounts..." on "Giro"
- **THEN** the login of the command starts when the refresh has ended, so the bank never has two sessions of one login

#### Scenario: Service of an extension

- **WHEN** the user opens the menu of an account that uses the service of an extension
- **THEN** "Look for New Accounts..." is disabled, because "Add Account..." with that service adds only the accounts that the app does not have yet

### Requirement: Edit the login data of an access

The app SHALL offer "Edit Login Data..." for an account with a FinTS access. The command opens the login data step with the stored values except secrets, lets the user change every field, and applies the change to all accounts of that access. The login of the command starts without the stored state of the access, as the first login of a setup does.

#### Scenario: New user ID

- **GIVEN** the bank gave the user a new user ID
- **WHEN** the user chooses "Edit Login Data...", enters the new user ID and the PIN, and confirms
- **THEN** the next refresh of all accounts of that access uses the new user ID

#### Scenario: Login data is checked first

- **WHEN** the user confirms changed login data that the bank rejects
- **THEN** the app shows the message of the bank
- **AND** the app keeps the old login data

#### Scenario: Rejected PIN removes the saved PIN

- **GIVEN** the access has a saved PIN
- **WHEN** the bank rejects the PIN that the user entered in "Edit Login Data..."
- **THEN** the app removes the saved PIN, so the next refresh asks for the PIN

#### Scenario: Login of another access

- **GIVEN** the app has two accesses at Musterbank with the user IDs "erika77" and "max55"
- **WHEN** the user enters "max55" in "Edit Login Data..." of the access "erika77"
- **THEN** the app says that another bank access uses this login already and contacts no bank

#### Scenario: Extension

- **WHEN** the user opens the menu of an account that uses the service of an extension
- **THEN** "Edit Login Data..." is disabled, because the extension asks for its login data in its own dialog

### Requirement: Switch the access method and keep the history

The app SHALL let the user choose another access method for an existing access in "Edit Login Data...". After the switch every account keeps its transactions, categories, comments, and settings.

#### Scenario: From an extension to FinTS

- **GIVEN** the account "Giro" with 1,200 transactions uses an extension, and the bank now offers FinTS
- **WHEN** the user chooses "Edit Login Data...", selects "FinTS/HBCI with TAN method", enters the login data, and confirms
- **THEN** "Giro" still has its 1,200 transactions
- **AND** the next refresh of "Giro" runs through FinTS

#### Scenario: Account not available with the new method

- **GIVEN** an access with a giro account and a credit card
- **WHEN** the user switches to a method through which the bank reports only the giro account
- **THEN** the app says that the credit card is not available with the new method and asks whether to continue
- **AND** when the user continues, the credit card stays in the app with its transactions and is no longer refreshed

### Requirement: Reinitialize an access after an aborted authentication

The app SHALL tell the user to use "Edit Login Data..." when a bank reports that the access must be set up again, for example after an aborted two-factor authentication or a new TAN method, and running the command with unchanged values SHALL perform that setup. Banks use different codes for this, so the error of an account names the command whenever the whole FinTS access failed with a message of the bank, also after the login, or the two-factor authentication did not finish.

#### Scenario: TAN method changed at the bank

- **GIVEN** the user moved from chipTAN to pushTAN on the bank website
- **WHEN** the next refresh fails with a message of the bank about the TAN method
- **THEN** the account error names "Edit Login Data..." as the next step
- **AND** after the user runs the command and confirms, the app offers the new TAN methods of the bank

#### Scenario: Aborted authentication

- **WHEN** the refresh of an access fails because the user did not approve the login in the app of the bank in time
- **THEN** the account error names "Edit Login Data..." as the next step

#### Scenario: Login replaced by a new one at Deutsche Bank

- **GIVEN** a Deutsche Bank access on `fints.deutsche-bank.de` with a saved PIN
- **WHEN** a refresh fails with the code 9940 or 3960 and the text "Bitte melden Sie sich im Online-Banking an oder kontaktieren den Support."
- **THEN** the account error shows the text of the bank and says to enter the new login of the bank with "Edit Login Data..."
- **AND** the app keeps the saved PIN and opens no PIN sheet, and the automatic refresh leaves the access out until the user refreshes it by hand
- **AND** the same answer on `hbci.postbank.de` or `fints.norisbank.de` does the same, and on the host of another bank it gives the error of the bank alone

#### Scenario: Error of one account

- **WHEN** the login of an access works and the bank rejects the request of one of its accounts with "9010 Zugang vorübergehend gesperrt"
- **THEN** the error of that account does not name "Edit Login Data..."

#### Scenario: Network error

- **WHEN** the refresh of an access fails because the bank cannot be reached
- **THEN** the account error does not name "Edit Login Data..."

### Requirement: List of supported banks

The app SHALL show a list of the banks and services it can reach, with a search field, the access methods for each entry, and the note that belongs to the entry. The Help menu opens the list.

#### Scenario: Search for a bank

- **WHEN** the user opens the list and types "Muster"
- **THEN** the list shows "Musterbank" with "FinTS/HBCI with TAN method"

#### Scenario: Service from an extension

- **GIVEN** an installed extension declares the service "Musterbroker"
- **WHEN** the user opens the list
- **THEN** the list contains "Musterbroker" with the name of the extension as its access method

#### Scenario: Bank that the app cannot reach

- **GIVEN** the bank directory lists "Neobank Muster" without a FinTS address
- **WHEN** the user opens the list and types "Muster"
- **THEN** the list does not show "Neobank Muster"

#### Scenario: Merged bank in the list

- **GIVEN** the bank directory lists 21099999 as "Sparkasse Altstadt -alt-" with a FinTS address
- **WHEN** the user opens the list and types "Altstadt"
- **THEN** the list shows "Sparkasse Altstadt -alt-" with "FinTS/HBCI with TAN method" and the note of a merged bank

#### Scenario: flatexDEGIRO Bank in the list

- **GIVEN** the bank directory lists 10130800 with a FinTS address
- **WHEN** the user opens the list and types "degiro"
- **THEN** the list shows "flatexDEGIRO Bank (flatex, DEGIRO, ViTrade)" with "FinTS/HBCI with TAN method"
- **AND** its note says that the FinTS access serves flatex accounts, and that DEGIRO and ViTrade accounts cannot be added with FinTS

#### Scenario: Savings bank in the list

- **GIVEN** the bank directory lists 70150000 as "Stadtsparkasse München" on a FinTS server of the savings banks
- **WHEN** the user opens the list and types "Stadtsparkasse München"
- **THEN** the note of the bank is the help of its login name, not the note before the first login

#### Scenario: Bank directory that does not load

- **GIVEN** an installed extension declares the service "Musterbroker", and the bank directory fails to load
- **WHEN** the user opens the list
- **THEN** the list says that the bank directory could not be loaded and still shows "Musterbroker"

#### Scenario: Move through the list with the keyboard

- **GIVEN** the list shows 500 banks
- **WHEN** the user types in the search field and presses Down Arrow
- **THEN** the first entry of the list is selected and the search field keeps its text
- **AND** Down Arrow, Up Arrow, Page Down, Page Up, Home, and End move the selection and scroll the list so that the selected entry is visible

#### Scenario: An arrow key with a modifier key stays with the system

- **GIVEN** the search field has the text "Muster" and the cursor after "Mu"
- **WHEN** the user presses Command-Down Arrow
- **THEN** the cursor moves to the end of "Muster", the search field keeps the focus, and no entry is selected
- **AND** an arrow, page, Home, or End key with Command, Option, Control, or Shift in the list leaves the selection unchanged

#### Scenario: Each entry is one element for assistive technologies

- **WHEN** VoiceOver reads the list
- **THEN** each bank is one element with its name, its place and Bankleitzahl, its access method, and its whole note
