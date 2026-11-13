# Bank access for the first test banks

This page records, as of 2026-11-11, how the app can reach five German banks through FinTS, and Trade Republic and PayPal, which have no FinTS. It decides what the first bank tests of issue #11 run against. The sources are listed per row. "Unknown" means no public source says it; the bank parameter data (BPD) of a live connection settles it.

## FinTS banks

The URLs come from the bank list of hbci4java (`blz.properties`, changed 2026-10-19), which Hibiscus uses. All are FinTS 3.0.

| Bank | FinTS for third-party software | Server | TAN methods | Securities holdings over FinTS |
|---|---|---|---|---|
| DKB | Yes ([DKB](https://www.dkb.de/geschaeftskunden/electronic-banking)) | `https://fints.dkb.de/fints`. The old server was switched off on 2024-11-25 ([ifun.de](https://www.ifun.de/dkb-neue-freigabemethoden-und-serverwechsel-fuer-finanzsoftware-243660/)) | DKB app (decoupled), chipTAN. Every login and every download needs an approval | Unknown. DKB moves its securities business to Upvest from late 2026 |
| Consorsbank | Yes ([FAQ](https://www.consorsbank.de/web/Wissen/FAQ/kontokarten/HBCI-Schnittstelle-Konto-und-Zahlungsverkehrsprogramm)) | `https://brokerage-hbci.consorsbank.de/hbci` | Consorsbank app (push) since August 2025. A TAN at every login | Yes, holdings ([FAQ](https://www.consorsbank.de/web/Wissen/FAQ/kontokarten/HBCI-Schnittstelle-unterstuetzte-Funktionen)). Securities transactions not listed |
| flatex | Only for the clearing account ([Lexware](https://help.lexware.de/de-form/articles/661667-lexware-office-flatex-anbinden)) | `https://konto.biw-bank.de/hbci/` (hbci4java only) | Unknown | Unknown. flatex documents only a CSV export of depot transactions |
| HypoVereinsbank | Yes, after switching it on in online banking ([fino](https://kws.help.fino.digital/en/support/solutions/articles/80000616994-hypovereinsbank-unicredit)) | `https://hbci-01.hypovereinsbank.de/bank/hbci` | photoTAN, appTAN | Unknown. Transactions start at the first FinTS download |
| Sparkasse | Yes ([fino](https://depotwechsel.help.fino.digital/en/support/solutions/articles/80000616998-sparkasse)) | One server per region, such as `https://banking-be3.s-fints-pt-be.de/fints30` | pushTAN, chipTAN | Unknown |

Every bank asks for a decoupled approval or a TAN at login, so the first FinTS test needs decoupled TAN handling from the start (`NEED_PT_DECOUPLED` in hbci4java).

## Trade Republic

Trade Republic has no FinTS and no official API. MoneyMoney reads it through its own built-in code, not through an extension ([MoneyMoney](https://moneymoney.app/banken/)).

- The open-source reference is [pytr](https://github.com/pytr-org/pytr) (MIT). It logs in like the web app: `POST /api/v2/auth/web/login` with phone number and PIN, approved in the app. Login v1 needs a token from a JavaScript bot challenge.
- Balances, the timeline, transactions, and positions come only over a WebSocket (`wss://api.traderepublic.com`), as subscriptions with full answers and deltas. There is no REST equivalent.
- The extension API of MoneyMoney has no WebSocket. So Trade Republic needs either a built-in provider in Swift (`URLSessionWebSocketTask`) or a WebSocket call in the extension API that goes beyond MoneyMoney's.
- pytr broke about every one to three months in 2026 and was fixed within days each time (issues #319, #335, #393, #413). A provider for Trade Republic needs the same upkeep.
- Fallback: import the PDF or CSV documents of Trade Republic.

## PayPal

- PayPal's REST Transaction Search needs a business account in production ([PayPal](https://developer.paypal.com/api/rest/reference/policiesandguidelines)).
- MoneyMoney uses the classic API (NVP, `TransactionSearch` and `GetBalance` at `api-3t.paypal.com/nvp`) with an API signature that the user creates for the own account ([MoneyMoney](https://moneymoney.app/banken/paypal/)). This is a plain HTTPS POST and fits the extension API.
- PayPal marks the classic credentials as deprecated. MoneyMoney writes that PayPal will offer no official interface for personal accounts.
- PSD2 access to PayPal is only for licensed providers. finAPI lists PayPal as an API connection.
- Fallback: the CSV download of the PayPal activity.

## First FinTS test, 11 November 2026

The product registration number arrived on 11 November 2026. The FinTSProbe of issue #11, a Swift probe on HBCI4Swift, ran against two banks the same day. The HBCI4Swift findings below are historical: ADR 0014 replaced HBCI4Swift, and issue #107 removed the Swift probe.

- **DKB** answered 9078 "FinTS-Produkt ist nicht registriert". The DK hands new numbers to the banks about once a week, and each bank takes days to weeks. The PIN is not checked before this answer.
- **Consorsbank** first answered 9010 "Ungültiger Signaturaufbau: Fehler im Segmentaufbau". HBCI4Swift sent the security profile `PIN:2` in the encryption head (HNVSK) and `PIN:1` in the signature head (HNSHK) for security function 999. Consorsbank checks that both match. Hibiscus had the same error with Consorsbank in 2019 ([forum](https://homebanking-hilfe.de/forum/topic.php?t=23128&page=7)). With `PIN:1` in both heads for 999, the dialog works. The fix is one line in `HBCISecurityMethodPinTan.swift`. It goes to the author as a pull request.
- With the fix, Consorsbank works with the decoupled Consorsbank app (security function 901). The login name is the account number followed by the three-digit Berechtigtennummer, usually `001` ([FAQ](https://www.consorsbank.de/web/Wissen/FAQ/kontokarten/HBCI-Schnittstelle-Konto-und-Zahlungsverkehrsprogramm)). The bank sent 3 accounts: 2 accounts with an IBAN, which allow AccountBalance, Statements, SepaInfo, SepaTransfer, and SepaInstantPayment, and a depot that allows only CustodyAccountBalance.
- The account information carries no BIC. HKKAZ from version 7 needs IBAN and BIC, and HBCI4Swift drops the order without an error when the BIC is missing. The probe fills it in with `--bic`. The connector of issue #13 has to take it from a bank directory by bank code. For BLZ 76030080 it is `CSDBDE71XXX`.
- Consorsbank offers MT940 only, not CAMT. 90 days arrived without a further approval: 8 and 22 transactions. Every row has a purpose, a booking text, and a value date. No row has the IBAN or BIC of the other party, an end-to-end ID, or a mandate. Rules for Consorsbank accounts can therefore match on name and purpose, not on IBAN. The currency is on the statement, not on the row.

### The same test with hbci4java

`Tools/FinTSProbeJava` ran the same test with hbci4j-core 4.1.17 ([ADR 0014](../decisions/0014-fints-through-hbci4java.md)).

- Login, synchronization, and the decoupled method 901 worked without changes to the library. hbci4java sends `PIN:1` in both security heads for 999.
- The account information again has no BIC. hbci4java has it in its bank directory.
- The depot allows HKWPD. 24 positions arrived, each with ISIN, WKN, name, price, quantity, and value.
- Balance and transactions failed with 9075 "Starke Authentifizierung erforderlich". The dialog initialization with HKTAN for HKIDN gets 3076, no SCA required. The bank parameters mark HKSAL, HKKAZ, and HKWPD with `needtan=N`, so hbci4java sends them without HKTAN, and Consorsbank rejects HKSAL and HKKAZ. Marked `needtan=J`, HKSAL and HKKAZ go with HKTAN, the bank answers 3076 again, and balance and transactions arrive: the same 8 and 22 rows, with the currency on every row. HKWPD with HKTAN fails with 9160 "Erforderliche Auftragsreferenz fehlt", so holdings stay without HKTAN. Reported as [hbci4j/hbci4java#155](https://github.com/hbci4j/hbci4java/issues/155).
- The booking dates differ by one day from the Swift probe. The Swift probe prints dates in UTC, which shows midnight in Germany as the day before. The connector keeps booking dates as calendar days without a time zone.

### Workarounds for bank quirks

| Bank | Quirk | Workaround in the helper | Upstream |
|---|---|---|---|
| Consorsbank | HKSAL and HKKAZ need HKTAN although the bank parameters say `needtan=N`. HKWPD must stay without HKTAN | Send HKSAL, HKKAZ, and HKCAZ with HKTAN, and HKWPD without HKTAN (`TAN_RULES` in `Tools/FinTSHelper/FinTSHelper.java`) | [hbci4j/hbci4java#155](https://github.com/hbci4j/hbci4java/issues/155) |

## What follows

1. Issue #11 goes on with `Tools/FinTSProbeJava`: DKB once the product number reaches it, then a Sparkasse. Every test reads the bank parameters for securities holdings (HKWPD) and transactions (HKWDU).
2. Trade Republic is a built-in provider, not a MoneyMoney extension. It needs its own decision record before it is built.
3. PayPal is a candidate for the first real extension of issue #15, because it needs only HTTPS.
