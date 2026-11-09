# Spec Delta

## Purpose

The aggregator subscription is an optional paid service that connects banks which the app cannot reach through FinTS or an extension. This capability defines how a user subscribes, consents, logs in to a bank through the aggregator, and leaves the service, and what happens when the subscription or a bank consent ends. The app never requires the subscription for any other feature.

## ADDED Requirements

### Requirement: Subscription tab in the settings

The app SHALL show a settings tab "Subscription" that explains what the service does, who operates it, that it is optional, and what it costs, with the links "Terms of Use", "Privacy Policy", and "Supported Banks".

#### Scenario: Not subscribed

- **GIVEN** a user who never signed in
- **WHEN** the user opens the settings tab "Subscription"
- **THEN** the tab shows the explanation, the price that the service reports, the three links, and a button "Sign in"
- **AND** the tab says that all other features work without the subscription

### Requirement: Subscription state

The app SHALL show the state of the subscription in the tab as one of four states. "Not subscribed", "Trial" with the days that remain, "Active" with the date of the next renewal or the end date after a cancellation, and "Expired" with the date it ended.

#### Scenario: Active

- **GIVEN** a subscription that renews on 16 September 2027
- **WHEN** the user opens the tab
- **THEN** the tab shows "Active" and "Renews on 16.09.2027"

#### Scenario: Canceled but still paid

- **GIVEN** the user canceled and the paid period ends on 16 September 2027
- **WHEN** the user opens the tab
- **THEN** the tab shows "Active until 16.09.2027" and that it does not renew

#### Scenario: Trial

- **GIVEN** the service reports a trial with 12 days left
- **WHEN** the user opens the tab
- **THEN** the tab shows "Trial" and "12 days remaining"

### Requirement: Sign in to the subscription service

The app SHALL open the sign-in page of the subscription service in the web browser when the user chooses "Sign in", and take over the session when the page redirects back to the app. The app stores the session token in the encrypted database.

#### Scenario: Sign in

- **WHEN** the user chooses "Sign in", signs in on the page, and the page redirects to the app
- **THEN** the app comes to the front and the tab shows the email address of the customer account and the state

#### Scenario: Browser closed

- **WHEN** the user closes the browser page without signing in
- **THEN** the tab still shows "Sign in" and nothing is stored

### Requirement: Sign out

The app SHALL offer "Sign out" in the tab. Signing out deletes the session token from the Mac. The subscription, the bank connections at the aggregator, and all local data stay.

#### Scenario: Sign out and in again

- **GIVEN** a signed-in subscriber with two aggregator accounts
- **WHEN** the user signs out and signs in again
- **THEN** both accounts refresh again without a new bank login

### Requirement: Payment outside the app

The app SHALL not take payment data. "Subscribe" and "Manage subscription" open the website of the service, where the user pays, changes the payment method, or cancels. The app shows the new state when the user returns or reloads the tab.

#### Scenario: Subscribe

- **GIVEN** a signed-in user without a subscription
- **WHEN** the user chooses "Subscribe", pays on the website, and returns to the app
- **THEN** the tab shows "Active" with the renewal date

### Requirement: Explicit consent before the first bank

The app SHALL ask for consent before it connects the first bank through the aggregator. The text names the operator of the subscription service and finAPI as recipients and lists what they receive. The user must tick a box. The app records the date of the consent and shows it in the tab.

#### Scenario: Box not ticked

- **WHEN** the user reaches the consent step and chooses "Next" without ticking the box
- **THEN** the app asks the user to show explicit consent by ticking the box and does not continue

#### Scenario: Consent given

- **WHEN** the user ticks the box and continues on 9 November 2026
- **THEN** the bank login starts
- **AND** the tab shows "Consent given on 09.11.2026"

### Requirement: Aggregator in the assistant

The app SHALL offer the aggregator as an access method in the add account assistant for a bank that the aggregator supports. A user without an active subscription sees what the method is and a link to the settings tab, and cannot continue with it.

#### Scenario: Bank without FinTS

- **GIVEN** an active subscription and a bank that has no FinTS server and that the aggregator supports
- **WHEN** the user enters the IBAN of that bank in the assistant
- **THEN** the assistant offers the access through the subscription

#### Scenario: No subscription

- **GIVEN** no subscription
- **WHEN** the user enters the IBAN of that bank
- **THEN** the assistant says that the bank is reachable through the optional subscription and links to the settings tab
- **AND** the assistant does not start a login

#### Scenario: Bank not supported

- **WHEN** neither FinTS, nor an installed extension, nor the aggregator supports the bank
- **THEN** the assistant does not offer the subscription for it

### Requirement: Bank login in the web form of the aggregator

The app SHALL open the web form of the aggregator for the bank login in a browser window. The user enters the bank login data and the TAN there. The app does not read, store, or log what the user enters in the form. When the form finishes, the window closes and the assistant continues.

#### Scenario: Successful login

- **WHEN** the user logs in to the bank in the web form and approves with a TAN
- **THEN** the window closes and the assistant lists the accounts that the bank reports

#### Scenario: User cancels the form

- **WHEN** the user closes the window before the form finishes
- **THEN** the assistant returns to the choice of the access method and no account is added

#### Scenario: Bank rejects the login

- **WHEN** the web form reports that the bank rejected the login
- **THEN** the assistant shows the message of the form and lets the user try again

### Requirement: Accounts from the aggregator

The app SHALL list the accounts that the aggregator reports for the bank login, let the user select which to add, and then show their balances, transactions, and securities like those of any other account.

#### Scenario: Two accounts

- **GIVEN** the bank login reports a giro account and a portfolio
- **WHEN** the user selects both and finishes
- **THEN** both accounts appear in the sidebar, the giro account with its transactions and the portfolio with its positions

### Requirement: Refresh through the aggregator

The app SHALL refresh aggregator accounts with the same commands and schedule as other accounts. A failure of the subscription service or the aggregator shows as an error on these accounts only, with the reason.

#### Scenario: Service not reachable

- **GIVEN** one aggregator account and one FinTS account
- **WHEN** "Refresh All Accounts" runs while the subscription service is down
- **THEN** the aggregator account shows that the subscription service could not be reached
- **AND** the FinTS account refreshes as usual

### Requirement: Bank consent expires

The app SHALL show on the affected accounts when the consent of the bank for the aggregator has ended, and offer "Renew" which opens the web form again. The refresh of these accounts pauses until the user renews. The app shows a reminder on the accounts 14 days before the end.

#### Scenario: After 180 days

- **GIVEN** a bank consent that ended yesterday
- **WHEN** a refresh runs
- **THEN** the accounts of that bank login show that the bank asks for a new approval, with the button "Renew"
- **AND** after the user renews in the web form, the next refresh fetches the missing transactions

#### Scenario: Reminder

- **GIVEN** a bank consent that ends in 10 days
- **WHEN** the user selects an account of that bank login
- **THEN** the account shows that the approval ends on that date and offers "Renew"

### Requirement: Read-only access

The app SHALL not send payments through the aggregator. An aggregator account is not offered as a source account for a payment. When the bank also has a FinTS server, the app says that the user can switch the access method with "Edit Login Data..." to make payments.

#### Scenario: Transfer from an aggregator account

- **GIVEN** the selected account uses the aggregator and its bank has a FinTS server
- **WHEN** the user opens "New Bank Transfer..."
- **THEN** the app explains that the subscription only reads data and that FinTS can send the transfer after a change in "Edit Login Data..."

### Requirement: Switch the access method of existing accounts

The app SHALL let the user switch existing accounts between the aggregator and another access method with "Edit Login Data...". The accounts keep their transactions, categories, comments, and checkmarks, and the first refresh after the switch creates no duplicates.

#### Scenario: From FinTS to the aggregator

- **GIVEN** a giro account with 500 transactions through FinTS and an active subscription
- **WHEN** the user switches the access to the subscription and logs in through the web form
- **THEN** the account still has its 500 transactions with their categories
- **AND** the next refresh adds only transactions that are new

### Requirement: Expired subscription

The app SHALL keep all accounts and data when the subscription expires. Only the refresh through the aggregator stops. The affected accounts show that the subscription has expired, with a link to the settings tab.

#### Scenario: Expired yesterday

- **GIVEN** a subscription that expired yesterday, one aggregator account, and one FinTS account
- **WHEN** "Refresh All Accounts" runs
- **THEN** the aggregator account shows "Subscription expired" and keeps its transactions, categories, and charts
- **AND** the FinTS account refreshes

#### Scenario: Renewed

- **WHEN** the user subscribes again
- **THEN** the aggregator accounts refresh again and fetch the transactions since the last refresh, as far as the bank provides them

### Requirement: Nothing else depends on the subscription

The app SHALL not check the subscription for any feature outside this capability. No feature is limited, delayed, or marked for users without a subscription.

#### Scenario: User without a subscription

- **GIVEN** a user who never signed in
- **WHEN** the user works with FinTS accounts, extensions, categories, rules, charts, imports, exports, and payments
- **THEN** everything works, and the app shows no hint about the subscription outside the settings tab and the assistant

### Requirement: Stop using the service

The app SHALL offer "Stop using the service..." in the tab. After a confirmation the app deletes the bank connections at the aggregator and turns the aggregator accounts into accounts without a bank access. The confirmation says that data on the Mac stays.

#### Scenario: Stop

- **GIVEN** a subscriber with two aggregator accounts
- **WHEN** the user chooses "Stop using the service..." and confirms
- **THEN** both accounts stay in the sidebar with all transactions and no longer refresh
- **AND** the tab shows that no bank is connected through the subscription

### Requirement: Delete the customer account

The app SHALL offer "Delete customer account..." in the tab. After a confirmation the app asks the service to delete the customer account and all personal data that no law requires the operator to keep, and signs out. The app says that some data is kept for a legal period and links to the privacy policy.

#### Scenario: Delete

- **WHEN** the user chooses "Delete customer account..." and confirms
- **THEN** the app confirms the deletion, names the legal retention, and shows the tab in the state "Not subscribed"
- **AND** all accounts and transactions on the Mac are still there

#### Scenario: Service not reachable

- **WHEN** the deletion request fails because the service cannot be reached
- **THEN** the app says that nothing was deleted and that the user can try again, and the user stays signed in

### Requirement: Data that leaves the Mac

The app SHALL send to the subscription service only the session token and the requests that set up, refresh, renew, or delete a bank connection. The app does not send transactions, categories, comments, rules, or data of accounts from other sources.

#### Scenario: User with FinTS and aggregator accounts

- **GIVEN** a subscriber with three FinTS accounts and one aggregator account
- **WHEN** a refresh runs
- **THEN** the requests to the subscription service concern only the one aggregator account

### Requirement: Identifier for support

The app SHALL show an identifier for support requests with the command "Identifier for customer support..." in the tab. The identifier lets the operator find the customer account and contains no name, email address, or bank data. The user can copy it.

#### Scenario: Copy the identifier

- **WHEN** the user chooses "Identifier for customer support..."
- **THEN** the app shows the identifier with a button "Copy to Pasteboard"

### Requirement: Supported banks

The app SHALL show which banks the aggregator supports through the link "Supported Banks" and in the add account assistant. The list comes from the service and is not built into the app.

#### Scenario: New bank at the aggregator

- **WHEN** the aggregator adds a bank and the user enters an IBAN of that bank next week
- **THEN** the assistant offers the subscription for that bank without an app update
