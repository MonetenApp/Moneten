#!/bin/sh
# Checks that the debug log holds no personal data. It drives the debug build of dist/Moneten.app
# (scripts/build-app.sh debug) through the debug harness against scripts/fake-fints-helper.sh: a start that
# fails on a data folder whose path holds a name, a login with a wrong PIN, the setup of the made-up bank
# with its TAN dialog, two refreshes (the second fails an account with an error of the bank), a refresh of
# one account that fails the access with a return code that holds a name, the transactions, the status, the
# error popover, and the state of each account, an account filter, a snapshot, and a key in the main window
# while the selected row has a new category. An import of all data fails on a file with a name as a day, and
# an export fails on a path that holds a name. A rule with a name or an IBAN as its amount fails to parse, a
# command and two snapshots have a name as their name, and an extension and a fixture fail to load from a
# path that holds a name. A made-up extension without a fixture then prints, sets a status, returns a value,
# fails a refresh, and fails a run with an error that names a person. The check fails when debug.log holds
# an IBAN, an account number, an amount, a balance, a name, a purpose, a booking text, a category name, the
# login name, the PIN, the TAN, the password, a text of the bank, or a text of the extension. It also
# imports a CSV file whose name, rows, and value date hold made-up personal data and a text of the bank.
# Round 2 of issue #188 added a full import with an access named after a person, a local extension whose
# file is named after a person, a catalog folder under a path with a name, and a name as the argument of
# "key", "mainkey", and "filterbar". The log names an extension by the first 8 hex digits of the SHA-256
# of its name, which `digest` computes here, so the check compares the hash and never the name.
# Issue #300 added three exports right after a sheet closes, whose alerts close at once.
# The check also opens CSV previews, one that fails and one whose rows go to another account that the import
# asks about, and reads their state and rows. The handoff compares the sums of the stored amounts and days with
# the sums the check expects, so the log says "ok" or "differs" and never holds an amount.
# Before a key or a text goes to a sheet, the check waits until the sheet window shows ("topsheet") and the field
# has the focus ("splitui focus=amount", "focusfield"), because a loaded Mac shows them a moment after the model state.
# The app runs with a temporary data folder and a password, so it never opens the real database, with a
# throwaway keychain file in MONETEN_KEYCHAIN_PATH, so it never opens the login keychain, and as a copy under
# its own bundle ID, so it leaves an installed Moneten alone. The check fails unless the entries of the app
# land in that keychain file.
# Each run has a bundle ID of its own, whose settings the end of the run deletes, so runs from several
# worktrees at once never share the saved filter bar or another setting.
set -e
cd "$(dirname "$0")/.."
BUILT=dist/Moneten.app
[ -d "$BUILT" ] || { echo "No $BUILT. Run scripts/build-app.sh debug first." >&2; exit 1; }
BUNDLE_ID=io.github.alexander-schneider.Moneten.check-debug-log
LOGIN=emuster42
PIN=97314
MIGRATION_UNKNOWN=MigrationSyntheticArgument9271

NOTIFY=.build/check-debug-log-notify
if [ ! -x "$NOTIFY" ] || [ scripts/check-debug-log.sh -nt "$NOTIFY" ]; then
	mkdir -p .build
	cat > "$NOTIFY.swift" <<-'EOF'
	import Foundation
	let a = CommandLine.arguments
	DistributedNotificationCenter.default().postNotificationName(Notification.Name("io.github.moneten.debug"), object: a[1],
		userInfo: ["command": a[2], "argument": a.count > 3 ? a[3] : ""], deliverImmediately: true)
	EOF
	swiftc -o "$NOTIFY" "$NOTIFY.swift"
fi

WORK="$(mktemp -d "$PWD/.build/check-debug-log.XXXXXX")"
BUNDLE_ID="$BUNDLE_ID.${WORK##*.}"
finish() {
	if [ -n "$PID" ]; then
		kill "$PID" 2>/dev/null || true
		wait "$PID" 2>/dev/null || true
	fi
	scripts/forget-bundle.sh "$BUNDLE_ID" "$APP"
	rm -f "$KEYCHAIN"
	[ -n "$KEEP" ] && echo "The log stays in $WORK/debug." || rm -rf "$WORK"
}
trap finish EXIT
# The keychain file of the run, created and unlocked by its path. `security create-keychain` leaves the default
# keychain and the search list of the user alone. The end of the run removes the file itself, because
# `security delete-keychain` edits the search list.
KEYCHAIN="$WORK/check-debug-log.keychain-db"
security create-keychain -p check-debug-log "$KEYCHAIN"
security unlock-keychain -p check-debug-log "$KEYCHAIN"
security set-keychain-settings "$KEYCHAIN"
# Without a banner, the app never asks for the permission to notify, so a run leaves no entry in the
# Notifications settings. The end of the run deletes the domain again.
defaults write "$BUNDLE_ID" showBannerNotificationOnNewTransactions -bool NO
LOG="$WORK/debug/debug.log"
APP="$WORK/Moneten.app"
DATA="$WORK/Erika Mustermann"
mkdir -p "$DATA/Database/Moneten.sqlite"
ditto "$BUILT" "$APP"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $BUNDLE_ID" "$APP/Contents/Info.plist"
codesign --force --sign - --entitlements App/Moneten.entitlements "$APP" 2>/dev/null
MONETEN_DATA_DIR="$DATA" MONETEN_DEBUG_DIR="$WORK/debug" MONETEN_KEYCHAIN_PATH="$KEYCHAIN" MONETEN_FINTS_HELPER="$PWD/scripts/fake-fints-helper.sh" MONETEN_DEBUG_NO_IDLE_LOCK=1 \
	"$APP/Contents/MacOS/Moneten" -ApplePersistenceIgnoreState YES -AppleLocale de_DE >"$WORK/app.log" 2>&1 &
PID=$!

cat >"$WORK/Check.lua" <<-'EOF'
	WebBanking{version = 1.0, services = {"Check Bank"}, description = "Made-up data for scripts/check-debug-log.sh"}
	function SupportsBank(protocol, bankCode) return bankCode == "Check Bank" end
	function InitializeSession(protocol, bankCode, username, customer, password)
		if (LocalStorage.runs or 0) >= 2 then error("Erika Mustermann") end
	end
	function ListAccounts(knownAccounts)
		return {{name = "Extrakonto", owner = "Erika Mustermann", accountNumber = "5550001", currency = "EUR", type = AccountTypeGiro}}
	end
	function RefreshAccount(account, since)
		LocalStorage.runs = (LocalStorage.runs or 0) + 1
		print("Konto von Erika Mustermann")
		MM.printStatus("Erika Mustermann")
		return {balance = 815.47, transactions = {}}
	end
	function EndSession() end
	function Result()
		print("Erika Mustermann")
		MM.printStatus("Erika Mustermann")
		return {owner = "Erika Mustermann", accountNumber = "5550001"}
	end
	function Fail()
		error("Konto 5550001 von Erika Mustermann")
	end
EOF

send() {
	"$NOTIFY" "$WORK/debug" "$@"
}

# The hash of LogValue.hash in App/Sources/DebugLog.swift.
digest() {
	printf %s "$1" | shasum -a 256 | cut -c1-8
}

alive() {
	case "$(ps -o stat= -p "$PID")" in "" | Z*) return 1 ;; esac
}

lines() {
	{ wc -l <"$LOG"; } 2>/dev/null || echo 0
}

# Waits up to 30 seconds for a line after the first $seen lines of the log that matches $1. While it waits, it sends the
# command in $2 and the rest every half second, or nothing when $2 is missing.
waitfor() {
	pattern=$1
	shift
	deadline=$(($(date +%s) + 30))
	while :; do
		[ $# = 0 ] || send "$@"
		sleep 0.5
		tail -n +"$((seen + 1))" "$LOG" 2>/dev/null | grep -q "$pattern" && return
		alive || { echo "The app exited while waiting for \"$pattern\"." >&2; tail -20 "$WORK/app.log" >&2; exit 1; }
		if [ "$(date +%s)" -ge "$deadline" ]; then
			echo "No \"$pattern\" after 30 seconds. The end of the log:" >&2
			tail -5 "$LOG" >&2
			exit 1
		fi
	done
}

# Sends the command in $2 and the rest every half second until a line written after the first send matches $1, for up
# to 30 seconds. The app can get the command more than once, so poll sends only a command that reads, such as "state"
# or "alertstate". A command that changes state goes out once, with send or once (issue #510).
# With $from set to a count of lines from before an earlier send, it looks at the lines after that send instead.
poll() {
	pattern=$1
	shift
	seen=${from:-$(lines)}
	from=
	waitfor "$pattern" "$@"
}

# Sends the command in $2 and the rest once and waits up to 30 seconds for a line written after the send that matches $1.
# It is for a command that changes state and logs what it did, such as an export, a drop, or a crash report decision.
once() {
	pattern=$1
	shift
	seen=$(lines)
	send "$@"
	waitfor "$pattern"
}

# Waits until the main window shows an alert, then closes it with one "alert". A second "alert" could close the next one.
closealert() {
	poll "^alertstate title=[0-9a-f]" alertstate
	once "^alert title=[0-9a-f]" alert
}

# Puts the focus in the first field of the sheet on top once the field shows, and waits until it has the focus.
focusfirst() {
	poll "^focusfield count=[1-9]" focusfield
	send focusfield 0
	poll "^focusfield .*position=0 editor=true$" focusfield
}

poll "^phase=failed" state
rmdir "$DATA/Database/Moneten.sqlite"
send create check-debug-log
poll "phase=unlocked" state
# ⌘, opens the settings while the app is unlocked, and a lock closes them. While the app is locked, ⌘, opens nothing.
send settings open
poll "^settings window=true .* tab=general " settings state
send lock
poll "^settings window=false sheet=false visible=false " settings state
send settings open
sleep 2
poll "^settings window=false sheet=false visible=false " settings state
send unlock check-debug-log
poll "phase=unlocked" state
# A lock also closes the settings while the password prompt of an unlock setting waits on the "Security" tab, and the
# prompt does not come back with the next unlock.
send settings open
poll "^settings window=true .* tab=general " settings state
send settings "tab security"
# The "Security" tab shows four switches and "General" six. A press before the tab shows would turn a switch of "General".
poll "^settings window=true .* tab=security switches=[a-z]*,[a-z]*,[a-z]*,[a-z]* stored=" settings state
send settings "press 1"
poll "^settings window=true sheet=true " settings state
send lock
poll "^settings window=false sheet=false visible=false " settings state
poll "^windows scenes=main$" windows
send unlock check-debug-log
poll "phase=unlocked" state
send settings open
poll "^settings window=true sheet=false visible=true tab=security " settings state
send settings "tab general"
poll "^settings window=true .* tab=general " settings state
# The window that macOS keeps after a close closes again when something puts it on screen while the app is locked. The
# lock also closes the settings, so the checks below run without them.
send lock
poll "^settings window=false sheet=false visible=false " settings state
send settings force
sleep 2
poll "^settings window=false sheet=false visible=false " settings state
if grep -q "^settings force found=false" "$LOG"; then echo "\"settings force\" found no settings window to show." >&2; exit 1; fi
send unlock check-debug-log
poll "phase=unlocked" state
cat >"$DATA/export.json" <<-'EOF'
	{"format": "moneten-export", "version": 1, "exportedAt": "2026-11-14T23:46:40.000Z", "accountGroups": [], "accounts": [],
	"accesses": [], "categories": [], "transactions": [], "deletedTransactions": [], "holdings": [],
	"portfolioValues": [{"accountID": "6F1C2A1E-0000-4000-8000-000000000001", "day": "Erika Mustermann", "value": "1.00", "currency": "EUR"}]}
EOF
once "^importall " importall "$DATA/export.json"
# A full import of the empty database with an access named after a person, which only a full import can name freely.
once "^exportall done$" exportall "$DATA/start.json"
python3 -I - "$DATA/start.json" "$DATA/access.json" <<-'EOF'
	import json, sys
	data = json.load(open(sys.argv[1]))
	data["accesses"] = [{"id": "6F1C2A1E-0000-4000-8000-000000000002", "connector": {"extension": {"id": "Erika Mustermann"}},
		"bankName": "Erika Mustermann Private Access", "userID": "emuster42"}]
	json.dump(data, open(sys.argv[2], "w"))
EOF
once "^importall done$" importall "$DATA/access.json"
poll "^ext access 0 source=extension state=idle$" extstate
once "^exportall " exportall "$DATA/missing/export.json"
closealert
# An export right after a sheet closes, and its alert closed as fast as the harness can. The alert waits until the
# sheet has slid out, so the close never meets the slide in AppKit (issue #300). The last run waits for the alert.
for run in 1 2 3; do
	send sheet exportAllData
	poll "^topsheet shown=true$" topsheet
	start=$(lines)
	send sheet ""
	send exportall "$WORK/fast.json"
	from=$start
	poll "^exportall done$" alertstate
	[ "$run" = 3 ] && poll "^alertstate title=[0-9a-f]* shown=true$" alertstate
	closealert
done
send sheet newAccount
send setup "entry 12030000"
send setup next
poll "setup step=login" setup
send setup "login $LOGIN"
send setup "pin 0000"
send setup next
poll "setup step=login .* error=[^-]" setup
send setup "pin $PIN"
send setup next
poll "dialog=true" setup
poll "^ext prompt tan" extprompt
send answer 123456
poll "setup step=accounts" setup
send setup next
poll "status line=.* accesses=2" status
send refresh all
poll "status account=2 kind=[a-zA-Z]* refreshing=false refreshedAt=set" status
send refresh all
poll "status account=1 kind=savings refreshing=false .*error=[^-]" status
for account in Girokonto Tagesgeld Kreditkarte; do
	poll "^rows " rows "$account"
done
once "^snapshot .*error" errorsnapshot Tagesgeld
poll "^ext account savings .*failed=" extstate
send refresh Kreditkarte
poll "^ext access [0-9] source=fints state=failed failure=bank code=invalid$" extstate
poll "status account=2 kind=creditCard refreshing=false .*error=invalid " status
send select Girokonto
once "^filterbar account .*account=[0-9]" filterbar "account Tagesgeld"
once "^filterbar account .*account=all" filterbar account
poll "^phase=" state
send search Miete
poll "^phase=.*visible=1 " state
once "^split saved=true parts=2" split 25,00
poll "^splitstate parts=2 pending=0 selected=[0-9]* checked=0 review=none sheet=none$" splitstate
send search ""
poll "^phase=" state
send selectRows 1
once "^exportcontextcsv rows=" exportcontextcsv "$DATA/context.csv"
poll "^exportstatus running=false" exportstatus
once "^exportcsv rows=" exportcsv "$DATA/rows.csv"
send cancelexport
poll "^exportstatus running=false" exportstatus
once "^snapshot " snapshot check
printf '%s\n' "Buchungstag;Valuta;Empfänger;Verwendungszweck;Betrag" "09.11.2026;Wartungsarbeiten;Erika Mustermann;Gehalt November;4.711,23" \
	"10.11.2026;10.11.2026;Wohnbau Musterstadt eG;Miete;-950,00" >"$WORK/Erika Mustermann.csv"
send filterbar "pin on"
send filterbar "amount withdrawals"
poll "^pin=true period=all status=all amount=withdrawals filter=amount category=all account=all saved=true$" state
once "^csvhandoff prepared$" csvhandoff prepare
for header in "" "Date;Name;Amount"; do
	printf '%s\n' "$header" '03/04/2026;Kiosk;1,234' '05/06/2026;Kiosk;2,345' >"$WORK/handoff.csv"
	send importfile "$WORK/handoff.csv"
	poll "^csv state " csv state
	send csv "column 0=bookingDate"
	send csv "column 1=name"
	send csv "column 2=amount"
	send csv "date monthDayYear"
	send csv "decimal point"
	poll "^csv state .*date=monthDayYear .*count=2 canImport=true" csv state
	send csvhandoff confirm
	poll "^importanswer .*otherPosition=[0-9]" importanswer
	start=$(lines)
	send importanswer named
	from=$start
	poll "^importfile done" state
	closealert
	poll "^csvhandoff accounts=1 count=2 amounts=ok days=ok$" csvhandoff "state 3579 40520810"
done
send importfile "$WORK/Erika Mustermann.csv"
poll "^csv state .*canImport=true" csv state
# A file import holds back neither the commands nor the settings and extensions. Only a migration that stores does.
poll "^menucommands enabled=true transferring=true migration=false$" menucommands
poll "^csv rows" csv rows
poll "^pin=true period=all status=all amount=withdrawals filter=amount category=all account=all saved=true$" state
poll "^topsheet shown=true$" topsheet
start=$(lines)
send key return
from=$start
poll "^importfile done" state
closealert
send importfile "$WORK/Erika Mustermann.csv"
poll "^csv state .*canImport=true" csv state
poll "^topsheet shown=true$" topsheet
start=$(lines)
send key return
from=$start
poll "^importfile done" state
closealert
poll "^pin=true period=all status=all amount=withdrawals filter=amount category=all account=all saved=true$" state
send filterbar "pin off"
poll "^rows " rows Girokonto
once "^gave up$" search "currency:/^+?49/"
send search ""
cat >"$WORK/Erika Mustermann.xml" <<-'EOF'
	<?xml version="1.0" encoding="UTF-8"?>
	<Document xmlns="urn:iso:std:iso:20022:tech:xsd:camt.053.001.08"><BkToCstmrStmt><Stmt>
	<Acct><Id><IBAN>DE02120300000000202051</IBAN></Id></Acct>
	<Ntry><Amt Ccy="EUR">1.00</Amt><CdtDbtInd>DBIT</CdtDbtInd><BookgDt><Dt>2026-11-03</Dt></BookgDt></Ntry>
	</Stmt></BkToCstmrStmt></Document>
EOF
send select Tagesgeld
poll "^phase=" state
send importfile "$WORK/Erika Mustermann.xml"
poll "^importanswer .*other" importanswer
start=$(lines)
send importanswer selected
from=$start
poll "^importfile done" state
closealert
send select Girokonto
poll "^phase=" state
for part in explicit missing repeat later; do
	attribute=' Ccy="EUR"'
	[ "$part" = explicit ] && attribute=' Ccy="USD"'
	case "$part" in missing | repeat) attribute='' ;; esac
	account=0099887766
	[ "$part" = repeat ] && account='99 88 77 66'
	cat >"$WORK/Erika Mustermann-$part.xml" <<-EOF
		<?xml version="1.0" encoding="UTF-8"?>
		<Document xmlns="urn:iso:std:iso:20022:tech:xsd:camt.053.001.08"><BkToCstmrStmt><Stmt>
		<Acct><Id><Othr><Id>$account</Id></Othr></Id></Acct>
		<Ntry><Amt$attribute>1.00</Amt><CdtDbtInd>DBIT</CdtDbtInd><BookgDt><Dt>2026-11-04</Dt></BookgDt></Ntry>
		</Stmt></BkToCstmrStmt></Document>
	EOF
done
send importfile "$WORK/Erika Mustermann-explicit.xml|$WORK/Erika Mustermann-missing.xml|$WORK/Erika Mustermann-repeat.xml|$WORK/Erika Mustermann-later.xml"
poll "^importanswer .*fileIndex=0 " importanswer
send importanswer named
poll "^importanswer .*fileIndex=1 " importanswer
send importanswer named
poll "^importanswer .*fileIndex=3 " importanswer
start=$(lines)
send importanswer selected
from=$start
poll "^importfile done" state
closealert
# A preview whose rows hold names and purposes, and whose problem names a cell of the file.
printf '%s\n' "Buchungstag;Empfänger;Verwendungszweck;Betrag" "11.11.2026;Tankstelle Beispiel;Kartenzahlung;-42,50" \
	"Miete 12;Beispiel GmbH;Sparen;-1,00" >"$WORK/Kontoauszug.csv"
send importfile "$WORK/Kontoauszug.csv"
poll "^csv state .*problem=line line=3 " csv state
poll "^csv rows" csv rows
poll "^topsheet shown=true$" topsheet
start=$(lines)
send key escape
from=$start
poll "^importfile done" state
closealert
send selectRows 1
send newcategory Haushaltskasse
poll "selection=category" state
send selectRows 1
once "^mainkey escape .*category=[0-9]" mainkey escape
once "^droprows category=" droprows Haushaltskasse
once "^movecategory position=" movecategory "Haushaltskasse||0"
once "^dropcategory hover=false" dropcategory "Haushaltskasse|Haushaltskasse"
once "^rule error=RuleSyntaxError position=1$" rule "Haushaltskasse|amount>Mustermann"
once "^rule error=RuleSyntaxError position=1$" rule "Haushaltskasse|amount>DE02120300000000202051"
poll "^unknown command$" "Erika Mustermann"
once "^snapshot window 0 " snapshot erika-mustermann
once "^snapshot sidebar " sidebarsnapshot "Erika Mustermann"
once "^ext error=PackageProblem$" extrun "$DATA/Erika Mustermann.lua|Result|"
once "^ext error=NSError$" extrun "$WORK/Check.lua|Result|$DATA/fixture.json"
once "^ext error=PackageProblem$" extaccess "$DATA/Erika Mustermann.lua||Check Bank"
once "^ext error=NSError$" extaccess "$WORK/Check.lua|$DATA/fixture.json|Check Bank"

send extfile "$WORK/Check.lua"
once "^ext allowed unverified extension=$(digest Check)$" extconfirm
send extaccess "Check||Check Bank"
poll "^ext prompt login" extprompt
# The status line names the bank of the access that waits for the login.
poll "^status line=set " status
send extlogin "$LOGIN|check-debug-log"
poll "^ext account giro rows=0 balance=ok" extstate 81547
# A refresh that comes while the access still refreshes adds nothing and is dropped, so each refresh waits for the run
# before it to end. A line that a send writes once is looked for from before that send, as it can come before the poll.
poll "^ext access 0 source=extension state=finished$" extstate
start=$(lines)
send extrefresh "Check||"
from=$start
poll "^ext print extension=$(digest Check) " extstate
poll "^ext access 0 source=extension state=finished$" extstate
send extrefresh "Check||"
poll "^ext access [0-9] source=extension state=failed" extstate
start=$(lines)
send extrun "$WORK/Check.lua|Result|"
from=$start
poll "^ext result" state
from=$(lines)
send extrun "$WORK/Check.lua|Fail|"
# Only the name of the error type and nothing after it.
poll "^ext error=ScriptError$" state
# A local extension takes its name from its file, here the name of a person.
cp "$WORK/Check.lua" "$WORK/Erika Mustermann.lua"
start=$(lines)
send extrun "$WORK/Erika Mustermann.lua|Result|"
from=$start
poll "^ext print extension=$(digest "Erika Mustermann") characters=16$" state
from=$start
poll "^ext result object count=2$" state
# A catalog in a folder that does not exist, under a path with a name: the error quotes the path.
once "^ext catalog unreachable error=" extcatalog "file://$WORK/Erika%20Mustermann/catalog/"
# A name as the argument of a command that takes one of a few words.
send sheet changePassword
poll "^key rejected$" key "Erika Mustermann"
send sheet ""
send select Girokonto
poll "visible=[1-9]" state
poll "^mainkey rejected$" mainkey "Erika Mustermann"
poll "^filterbar rejected$" filterbar "Mustermann Erika"
send sheet ""
send alert
# The seed stores its accounts and rows in a task, which takes longer than any fixed wait on a loaded Mac.
start=$(lines)
send seed
from=$start
poll "^seed done$" state
send select Girokonto
send search Stadtwerke
poll "^phase=.*visible=[1-9][0-9]* " state
# Each "type" into the split sheet waits for the amount field to have the focus, which comes a moment after the
# sheet shows. Text typed before that goes nowhere, and the poll for "Next Split" times out on a loaded Mac.
send sheet split
poll "^splitui amountLabel=true nextLabel=true nextEnabled=false .*focus=amount sheet=split$" splitui
send type 25,00
poll "^splitui amountLabel=true nextLabel=true nextEnabled=true .*sheet=split$" splitui
send splitnext
poll "^splitui .*nextEnabled=false .*focus=amount sheet=split$" splitui
send key tab
send key return
poll "^splitstate parts=2 .*sheet=none$" splitstate
send selectRows 2
once "^deleteparts refused=true selected=2$" deleteparts
send alert
poll "^topsheet shown=false$" topsheet
once "^undosplit sheet=undoSplit$" undosplit
poll "^topsheet shown=true$" topsheet
send key escape
poll "^splitstate parts=2 .*sheet=none$" splitstate
poll "^topsheet shown=false$" topsheet
once "^undosplit sheet=undoSplit$" undosplit
poll "^topsheet shown=true$" topsheet
send key return
poll "^splitstate parts=0 .*sheet=none$" splitstate
for value in 0,00 89,00 abc; do
	send sheet split
	poll "^splitui .*nextEnabled=false .*focus=amount sheet=split$" splitui
	send type "$value"
	poll "^splitui .*nextEnabled=false .*sheet=split$" splitui
	send key escape
	# The next sheet must not find this one still closing, with its field and the focus.
	poll "^splitui amountLabel=false .*focus=none sheet=none$" splitui
done
for entry in 5,00 +5,00 -5,00; do
	send sheet split
	poll "^splitui .*nextEnabled=false .*focus=amount sheet=split$" splitui
	send type 100,00
	poll "^splitui .*nextEnabled=true .*sheet=split$" splitui
	send splitnext
	poll "^splitui .*nextEnabled=false .*focus=amount sheet=split$" splitui
	send type "$entry"
	send key return
	poll "^splitstate parts=3 .*sheet=none$" splitstate
	once "^exportall done$" exportall "$WORK/remainder.json"
	python3 - "$WORK/remainder.json" "$entry" <<-'EOF'
	import json, sys
	data = json.load(open(sys.argv[1]))
	ids = {row["id"] for row in data["transactions"] if row["name"] == "Stadtwerke Musterstadt"}
	parts = sorted((part for part in data["splitParts"] if part["transactionID"] in ids), key=lambda part: part["position"])
	expected = ["-100.00", "-5.00", "16.00"] if sys.argv[2] == "-5,00" else ["-100.00", "5.00", "6.00"]
	assert [part["amount"] for part in parts] == expected
	assert [part["position"] for part in parts] == [0, 1, 2]
	EOF
	send alert
	poll "^topsheet shown=false$" topsheet
	once "^undosplit sheet=undoSplit$" undosplit
	poll "^topsheet shown=true$" topsheet
	send key return
	poll "^splitstate parts=0 .*sheet=none$" splitstate
done
send split 7%
poll "^splitstate parts=2 .*sheet=none$" splitstate
poll "^topsheet shown=false$" topsheet
once "^undosplit sheet=undoSplit$" undosplit
poll "^topsheet shown=true$" topsheet
send key return
poll "^splitstate parts=0 .*sheet=none$" splitstate
send split 19%
poll "^splitstate parts=2 .*sheet=none$" splitstate
once "^snapshot split-menu " splitmenusnapshot
send split 5,00
poll "^splitstate parts=3 .*sheet=none$" splitstate
send vatsettings
poll "^vatstate rates=2 matches=true error=false$" vatstate "1900,700"
focusfirst
send type 20
# Each press of Save goes out once: a second Save finds the field empty and shows the error, and poll sends its
# command again every half second while a loaded Mac has not yet answered the first.
send vatbutton save
poll "^vatstate rates=3 matches=true error=false$" vatstate "1900,700,2000"
send vatbutton change-1
focusfirst
send type 8,1
send vatbutton save
poll "^vatstate rates=3 matches=true error=false$" vatstate "1900,810,2000"
focusfirst
send type 7,125
send vatbutton save
poll "^vatstate rates=3 matches=true error=true$" vatstate "1900,810,2000"
send vatbutton change-0
send vatbutton cancel
focusfirst
send type "Erika Mustermann"
send vatbutton save
poll "^vatstate rates=3 matches=true error=true$" vatstate "1900,810,2000"
for count in 2 1 0; do
	send vatbutton remove-0
	poll "^vatstate rates=$count " vatstate
done
poll "^vatstate rates=0 matches=true error=false$" vatstate
once "^snapshot split-menu " splitmenusnapshot
for rate in 19 7; do
	focusfirst
	send type "$rate"
	send vatbutton save
done
poll "^vatstate rates=2 matches=true error=false$" vatstate "1900,700"
send vatclose
send search ""
poll "^migrationfailure: unknown failure$" migrationfailure "$MIGRATION_UNKNOWN"
# "Look for New Accounts..." on an account named in the argument: the log names neither the account nor the access.
once "^lookfornew setup=true$" lookfornew Girokonto
poll "^setup purpose=newAccounts " setup ""
send setup cancel
closealert
# Each Return goes out once, after the sheet shows the step that it confirms. A second Return would confirm the next step.
send migrationfixture "$PWD/Fixtures/moneymoney"
poll "^migrationstate step=intro$" migrationstate
poll "^topsheet shown=true$" topsheet
start=$(lines)
send key return
from=$start
poll "^migrationstate step=summary$" migrationstate
from=$start
poll "^migration step=5 completed=5 total=5$" migrationstate
start=$(lines)
send key return
from=$start
poll "^migrationstate step=done$" migrationstate
from=$start
poll "^migration step=6 completed=5 total=5$" migrationstate
send key return
poll "^migrationstate step=none$" migrationstate
once "^crash inject frames=1 pending=true" crashinject private
once "^crash url characters=" crashurl
for value in DE02120300000000202051 "Erika Mustermann" /Users/erika; do
	if grep -F -- "$value" "$WORK/debug/crash-report.txt" "$WORK/debug/crash-url.txt"; then
		echo "The crash report contains personal data." >&2
		exit 1
	fi
done
once "^crash decision pending=false copied=true" crashdecision copy
once "^crash inject frames=3 pending=true" crashinject
once "^crash decision pending=false copied=false" crashdecision decline
once "^crash inject frames=500 pending=true timeMatches=true" crashinject "long|1800000000"
once "^crash decision pending=false copied=true" crashdecision copy
# The password of "Unlock automatically" goes into the keychain file of the run, as the crash report key did at launch.
once "^security setting=unlockAutomatically result=changed .*keychainAutomatic=true" security "unlockAutomatically on check-debug-log"
send quit
for service in "Moneten crash report key" "Moneten database password for automatic unlock"; do
	security find-generic-password -s "$service" "$KEYCHAIN" >/dev/null \
		|| { echo "The keychain file of the run holds no entry \"$service\"." >&2; exit 1; }
done

found=0
for value in "25,00" "20,00" "30,00" "Synthetic extra" DE02120300000000202051 "DE02 1203" 202051 1234567890 0099887766 "99 88 77 66" 4711 5550001 "$LOGIN" "$PIN" "$MIGRATION_UNKNOWN" 123456 1800000000 check-debug-log \
	"Private" "Giro" "Savings" "Depot" "Household" "Food" "Pets" "Salary" "Sonstiges" "REWE Markt" "KARTENZAHLUNG" "Wocheneinkauf" "Stadtwerke Musterstadt" "Abschlag" "E2E-1" "M-1" "DE98ZZZ09999999999" "Gehalt Oktober" "Zinsen" "Synthetic migration" \
	234015 501240 12000 12500 320000 95000 4250 229765 471123 "4711,23" 81547 815.47 1234 2345 3579 2500 92500 \
	"Baumarkt Beispiel" "Weekly shop" "REWE SAGT DANKE" "REWE receipt" "Receipt" "demo-split" "Handoff Synthetic" 88776655 Kiosk \
	Girokonto Tagesgeld Kreditkarte Extrakonto "Erika Mustermann" Erika Mustermann erika-mustermann "Private Access" Musterbank "Check Bank" \
	"Beispiel GmbH" "Wohnbau Musterstadt" "Tankstelle Beispiel" /Users/erika \
	"Gehalt November" Miete Kartenzahlung Sparen Haushaltskasse MIETE-2026-11 GUTSCHRIFT DAUERAUFTRAG \
	"8,1" "7,125" "1900,700" "1900,810,2000" "1900,700,2000" "0,00" "89,00" "100,00" "5,00" "+5,00" "-5,00" abc "Stadtwerke Musterstadt" "Streaming Dienst" Electricity Groceries \
	"Zugang vorübergehend gesperrt" "PIN falsch" Wartungsarbeiten pushTAN-App "currency:/^+?49/"; do
	if grep -n -w -F -- "$value" "$LOG" >&2; then
		echo "debug.log holds \"$value\"." >&2
		found=1
	fi
done
[ "$found" = 0 ] && echo "debug.log holds no personal data in $(wc -l <"$LOG" | tr -d ' ') lines."
exit $found
