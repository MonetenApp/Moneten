## ADDED Requirements

### Requirement: The action button follows the view

The app SHALL name the action button in the toolbar after the main action of the current view. It reads "Bank transfer" in account, category, and dashboard views, "Batch transfer" in the outbox, "Standing order" in the scheduled view, and "Add template" in the templates view.

#### Scenario: Outbox

- **WHEN** the user selects "Outbox"
- **THEN** the action button reads "Batch transfer"

#### Scenario: Account

- **WHEN** the user selects the account "Girokonto" and clicks the action button
- **THEN** a payment window opens with "Girokonto" as the source account
