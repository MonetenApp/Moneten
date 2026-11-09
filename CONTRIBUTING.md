# Contributing

Thank you for helping. This page explains how to find work, how to propose a change, and what a pull request needs.

## Find something to work on

- The [roadmap](docs/roadmap.md) lists every planned issue by release.
- Issues labeled `kind: prototype` settle open decisions. They are a good start if you like to explore.
- To add a bank or service, write an extension. The author guide arrives with v0.1.
- To request support for a bank, open an issue with the **Bank or service request** template.

## Propose a change

For a bug fix or a small change, open a pull request. For a larger change, open an issue first and describe the problem. A change to a decision in [docs/decisions](docs/decisions/) needs a new decision record.

## What a pull request needs

1. Tests for the behavior you add or change. Tests for FinTS and extensions replay recorded responses from `Fixtures/` and never contact a real bank.
2. A green CI run.
3. Screenshots in light and dark mode for any change to the interface. Use made-up names, IBANs, and amounts, never your own data.
4. No personal data. Remove names, IBANs, account numbers, and amounts from fixtures and logs before you commit them.

## Licensing

By submitting a contribution, you agree that it is licensed under the GNU General Public License v3.0 or later, the same license as the project. There is no contributor license agreement.

## Be kind

Treat everyone with respect. The maintainers remove comments that attack people.
