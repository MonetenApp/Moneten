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
| Consorsbank, DAB BNP Paribas | HKSAL and HKKAZ need HKTAN although the bank parameters say `needtan=N`. HKWPD must stay without HKTAN | Send HKSAL, HKKAZ, and HKCAZ with HKTAN, and HKWPD without HKTAN, on every access to the server `brokerage-hbci.consorsbank.de`, which both Bankleitzahlen share (`tanRules` in `Tools/FinTSHelper/FinTSHelper.java`) | [hbci4j/hbci4java#155](https://github.com/hbci4j/hbci4java/issues/155) |
| Consorsbank | The account information carries no BIC | The BIC of the bank directory of hbci4java (`dialog` in `Tools/FinTSHelper/FinTSHelper.java`) | None |
| DKB | A credit card allows no statement (HKKAZ, HKCAZ), only the card statement DKKKU | Send only DKKKU for an account that allows it and no statement, and take the balance from its answer (`jobs` and `card` in `Tools/FinTSHelper/FinTSHelper.java`) | None |
| Banks with DKKKU | hbci4java 4.1.17 drops the field `finalized` of each card row, and a row that it cannot read, such as an original amount with three decimals, fails the whole dialog | `CardJob` leaves the answer DIKKU as raw data, and `cardRows` reads the rows from it: `finalized` N makes a row pending, and a row that does not read fails only the card | None yet |

## Test plan for the bank runs of issue #11

Each run takes a few minutes and contacts only the bank under test. It uses a debug build with a throwaway data folder, so it never touches the real database. The debug log holds no names, IBANs, account numbers, purposes, PINs, or TANs (`scripts/check-debug-log.sh` checks that), so its status lines can go into the issue.

### Setup, once

1. Put the product registration number into the login Keychain, if it is not there: `security add-generic-password -s 'Moneten FinTS product ID' -a moneten -w` (it asks for the number).
2. Build: `scripts/build-app.sh debug`. The build bundles the FinTS helper and the product ID.
3. Quit every running Moneten, also one that runs from another folder, and check that none is left: `pgrep -x Moneten` must print nothing. A plain `open` brings a running instance to the front, and that instance keeps its own data folder, which can be the real one.
4. Start a separate instance with a throwaway folder and the debug harness, without `MONETEN_FINTS_HELPER`, so the real helper runs. The binary started directly is always a new instance, and its stderr keeps the masked diagnostics of the FinTS helper in `$RUN/helper.log`:

   ```sh
   RUN=$(mktemp -d); mkdir "$RUN/debug"
   MONETEN_DATA_DIR="$RUN/data" MONETEN_DEBUG_DIR="$RUN/debug" dist/Moneten.app/Contents/MacOS/Moneten 2>"$RUN/helper.log" &
   ```

5. Make the command for the harness, as `scripts/check-debug-log.sh` does, and create the database with a password, so the run leaves no Keychain item:

   ```sh
   cat > .build/notify.swift <<'EOF'
   import Foundation
   let a = CommandLine.arguments
   DistributedNotificationCenter.default().postNotificationName(Notification.Name("io.github.moneten.debug"), object: a[1],
   	userInfo: ["command": a[2], "argument": a.count > 3 ? a[3] : ""], deliverImmediately: true)
   EOF
   swiftc -o .build/notify .build/notify.swift
   send() { .build/notify "$RUN/debug" "$@"; }
   send create bank-test
   ```

6. Before any step with the bank, check that the instance with the throwaway folder answered: `ls "$RUN/data/Database/Moneten.sqlite"` shows the new database, and `send status` writes lines into `$RUN/debug/debug.log`. If either is missing, stop, quit Moneten, and start again at step 3.

After each step, `send status` writes one line per account into `$RUN/debug/debug.log`: its kind, the error, whether it has a balance, the number of rows, and `historyStart`. The log holds no amounts, so read the balance and the rows in the window. Copy the lines of the run into issue #11.

### Run 1: a savings bank with pushTAN

1. "Add Account..." (or `send sheet newAccount`), search the savings bank by its Bankleitzahl, enter the login name and the PIN. Approve the login in the pushTAN app.
2. Expected: the dialog says "to allow the login", closes by itself after the approval, and the account list shows every account with its type. Record the types (giro, savings, credit card, portfolio) and whether a credit card is in the list.
3. Add all accounts. The first refresh asks for the full history. When the bank asks for a second approval "to allow the download of transactions", approve it once and note whether the list then starts more than 90 days ago (`historyStart`).
4. `send refreshenforced all`, and this time click "Cancel" in the dialog for the download. Expected: no error on the account and the last 90 days. The note "Older transactions may be missing." comes with #264, so record what shows. Record whether the bank asked for the approval at all.
5. `send refresh all` again within a few minutes. Expected: no dialog after the login, or only the login approval.
6. Decline one login approval in the pushTAN app. Expected: "The required authorization was not carried out." Record the code that `send status` shows.

### Run 2: a direct bank with an approval in its app (DKB or Consorsbank)

1. Add the login as in run 1, with the approval in the bank's app. At DKB, record whether 9078 "FinTS-Produkt ist nicht registriert" still comes.
2. At DKB, add a credit card if the bank lists one. Expected: the card shows a balance and transactions from the card statement, and a payment that is not final yet, such as a reservation, shows as pending. Record the line `FinTSHelper: card statement finalized ...` of `$RUN/helper.log`: it counts the values of `finalized` that the bank sent (N, J, or none) and the distinct references of the rows, without any data of a row. Refresh again after a pending row became final and record the line again. If the card fails, record its error.
3. At Consorsbank, refresh the giro account and the depot. Expected: balance, transactions, and the value of the depot, without 9075.

### Run 3: another TAN method (chipTAN, photoTAN, or smsTAN)

1. Add the login with a bank or a method that types a TAN: chipTAN optical (the flicker code), chipTAN QR, photoTAN, or smsTAN with a TAN medium.
2. Expected: the dialog shows the flicker code or the image, or asks for the TAN medium and then for the SMS code. Type a wrong TAN once. Expected: "The bank did not accept the entered TAN" with the code of the bank (9941 or another), and no second request.
3. Change the method inside the dialog, if the bank offers two. Expected: a new challenge with the new method.

### Run 4: ING (issue #235)

1. Add the ING login and refresh the giro account. Record whether the bank parameters allow CAMT (HKCAZ) and SEPA transfers (HKCCS), and how ING lists photoTAN and "Banking to go" among its TAN methods.
2. If ING sends MT942, record one pending row and its booked version: is the entry date of the `:61:` line the day on which ING books the row?
3. Only with an access that has not logged in on www.ing.de for 90 days: record the code and the text of the lock. Expected: 9942 "Bitte erneuern Sie ihre Authentifizierung. Einfach unter ING.de einloggen." and the hint of the app.
4. During the lock, refresh by hand two or three times and record after each one whether ING counts the login toward the block of the PIN, for example a warning of a block to come, or 3938 or 9930 at the next login. The automatic refresh pauses after 3 such refreshes in a row (`RefreshError.lockedLoginLimit`), and this step decides whether that limit can go.
5. Log in on www.ing.de with the QR log-in once, and with the user name and the password once. Record which one unlocks FinTS, and after how long.

### What each run records

- The return codes that the bank sends for a declined approval, a wrong TAN, and a blocked access, when they occur. The app maps 9941, 9943, 9948, and 9951 (`HelperError` in `Sources/FinTS/HelperProtocol.swift`), and a code it does not know shows as the text of the bank.
- The code of a PIN change that the bank requires, if one comes. No source names it yet (task 1.23 of add-fints-banking).
- What a login without a TAN method for FinTS shows. The app means to show "There are no available TAN methods.", so record the text that shows.
- The account types of the login, and the error line of `send status` for each account that fails.

## What follows

1. Issue #11 goes on with `Tools/FinTSProbeJava`: DKB once the product number reaches it, then a Sparkasse. Every test reads the bank parameters for securities holdings (HKWPD) and transactions (HKWDU).
2. Trade Republic is a built-in provider, not a MoneyMoney extension. It needs its own decision record before it is built.
3. PayPal is a candidate for the first real extension of issue #15, because it needs only HTTPS.
