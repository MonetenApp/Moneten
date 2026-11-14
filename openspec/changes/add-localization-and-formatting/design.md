# Design

## Context

This design so far covers only the completion of a partly typed date, because its rule needs decisions before code. The other requirements of the change get their design before their tasks are written.

The sheet for a manual transaction in `App/Sources/Views/Sheets.swift` and the custom period in `App/Sources/Views/TransactionsView.swift` use the date picker of the system. That picker edits the day, the month, and the year one at a time. It does not take a day alone and complete it, so the rules of the spec need a date field of the app's own.

## Goals / Non-Goals

**Goals:**

- One rule for completing a date, used by every date field of the app.
- The same result for the same typed text, today, region, and kind of field, so tests can fix all four.

**Non-Goals:**

- Words such as "today" or "heute" in a date field.
- The minimum and maximum of a date field. A field that has them applies them after the completion.

## Decisions

### A pure completion function in `Domain`

The completion is a function in `Domain`. It takes the typed text, today as a `Day`, the order of day, month, and year from the region, and whether the field expects a future date. It returns a `Day`, or nothing when the text is not a date. The date field in `App` calls it when the user leaves the field. A pure function lets the tests set today to 9 November 2026 or 15 February 2027 without a clock.

Alternative: complete the date inside the view. The rule then has no tests outside the running app, and the two kinds of field could drift apart.

### The kind of field is a property of the field

Each date field states whether it expects a future date. The default is no. Only the fields that set it use the forward rules of the two requirements for a field that expects a future date.

### The rule for an ordinary field

A typed day goes into today's month. It moves one month back only when it lies after today and more than two days ahead of today's day. So the dates of the last weeks, which a user types most often, land in the past. Today, tomorrow, and the day after stay in the current month, for a cash payment noted ahead. A typed day and month stay in today's year. Only from January to March does a month from October to December go to the last year.

## Risks / Trade-offs

- [A day typed more than two days ahead lands in the previous month.] → The field shows the full date at once, and the user can type the month as well.

## Open Questions

- Which date fields expect a future date. The spec names the scheduled date of a payment. The forward rules for these fields are the two requirements for a field that expects a future date. Confirm the list of fields and this rule before the windows for transfers, direct debits, and standing orders are built. The rule for an ordinary field does not depend on this answer.
