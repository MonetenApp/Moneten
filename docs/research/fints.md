# FinTS

This page explains how FinTS works and which libraries implement it. It is background for work on `FinTSConnector`.

## What FinTS is

FinTS 3.0, formerly HBCI, is the standard interface that the Deutsche Kreditwirtschaft (DK) defines for banking software. Almost every German bank offers it. The specification is public on [fints.org](https://www.fints.org).

## How a FinTS message looks

The client sends each message as an HTTPS POST to the bank's FinTS URL, Base64 encoded. The bank answers the same way.

A message is a list of segments in a text syntax. An apostrophe ends a segment, `+` separates data elements, `:` separates parts of a group, and `?` escapes these characters. Each segment starts with its name, number, and version. Client segments start with `HK`, bank segments with `HI`. A simplified example:

```
HNHBK:1:3+000000000150+300+0+1'
HKIDN:2:2+280:12030000+userid+0+1'
HKVVB:3:3+0+0+0+PRODUCTID+0.1'
HKSAL:4:7+DE89...:N'
HNHBS:5:1+1'
```

## How a dialog runs

1. The client opens a dialog with its user ID, its product registration number, the PIN, and an `HKTAN` segment for strong customer authentication.
2. The bank answers with the bank parameter data (BPD), which lists supported business transactions, versions, and TAN methods, and the user parameter data (UPD), which lists the user's accounts and permissions. The client caches both.
3. The client sends business transactions. Common ones are `HKSPA` for SEPA account details, `HKSAL` for balances, `HKKAZ` for transactions in MT940, `HKCAZ` for transactions in CAMT, `HKWPD` for securities in MT535, `HKCCS` for a SEPA transfer, `HKIPZ` for an instant transfer, and `HKVPP` for the payee check.
4. If the bank has more data, it returns code `3040` with a touchdown point. The client repeats the request with that point.
5. The client ends the dialog with `HKEND`.

Return codes tell the client what happened. `0010` means success, `0030` means a TAN is needed, and `3920` lists the allowed TAN methods.

## How TANs work

PSD2 requires strong customer authentication. For reading data, most banks ask for it every 90 to 180 days. Some ask at every login. For payments, banks always ask.

1. The client sends the order together with `HKTAN` in process 4.
2. The bank answers with a challenge. It is a text prompt, a photoTAN image, a chipTAN flicker code, or a request to approve in the bank's app (decoupled).
3. For a TAN, the client sends it back with `HKTAN` in process 2. For an app approval, the client polls until the bank reports the result.

Banks implement these steps differently. Most bug reports for FinTS clients come from this part.

## How to register a product

Banks accept only registered FinTS products. Registration with the DK is free and takes several weeks. The product gets a registration number that the client sends in `HKVVB`. Registered vendors also get the institute list with the FinTS URLs of all banks. Community sources point to [fints.org/de/hersteller/produktregistrierung](https://www.fints.org/de/hersteller/produktregistrierung) as the entry point.

## Libraries

Status from GitHub on 9 November 2026.

| Library | Language | License | Last push | Notes |
|---|---|---|---|---|
| [HBCI4Swift](https://github.com/macemmi/HBCI4Swift) | Swift | GPL-2.0-or-later | August 2026 | See [ADR 0003](../decisions/0003-fints-through-hbci4swift.md) |
| [python-fints](https://github.com/raphaelm/python-fints) | Python | LGPL-3.0 | October 2026 | Best documented, good reference |
| [hbci4java](https://github.com/hbci4j/hbci4java) | Java | LGPL-2.1 | October 2026 | Most complete, used by Hibiscus |
| [AqBanking](https://github.com/aqbanking/aqbanking) | C | GPL | September 2026 | Used by GnuCash and KMyMoney |
| [phpFinTS](https://github.com/nemiah/phpFinTS) | PHP | MIT | November 2026 | Used by Firefly III importers |
| [libfintx](https://github.com/libfintx/libfintx) | C# | LGPL-3.0 | November 2026 | Also EBICS |
| [lib-fints](https://github.com/robocode13/lib-fints) | TypeScript | LGPL-2.1 | October 2026 | PIN/TAN only |
| [fints-rs](https://github.com/floffel/fints-rs) | Rust | MIT | October 2026 | Early stage |

Commercial libraries exist from Subsembly, windata, and DataDesign. They do not fit an open source project.
