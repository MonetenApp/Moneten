#!/bin/sh
# Checks that the debug log holds no personal data. It drives the debug build of dist/Moneten.app
# (scripts/build-app.sh debug) through the debug harness against scripts/fake-fints-helper.sh: a start that
# fails on a data folder whose path holds a name, a login with a wrong PIN, the setup of the made-up bank
# with its TAN dialog, two refreshes (the second fails an account with an error of the bank), the
# transactions, the status, the error popover, and the state of each account, a snapshot, and a key in the
# main window while the selected row has a new category. An import of all data fails on a file with a name
# as a day, and an export fails on a path that holds a name. A made-up extension without a fixture then
# prints, sets a status, returns a value, and fails a refresh. The check fails when debug.log holds an IBAN,
# an account number, a name, a purpose, a booking text, a category name, the login name, the PIN, the TAN,
# the password, a text of the bank, or a text of the extension.
# It also imports a CSV file whose name, rows, and value date hold made-up personal data and a text
# of the bank.
# The app runs with a temporary data folder and a password, so it never opens the real database and
# leaves no Keychain item, and as a copy under its own bundle ID, so it leaves an installed Moneten alone.
set -e
cd "$(dirname "$0")/.."
BUILT=dist/Moneten.app
[ -d "$BUILT" ] || { echo "No $BUILT. Run scripts/build-app.sh debug first." >&2; exit 1; }
BUNDLE_ID=io.github.alexander-schneider.Moneten.check-debug-log
LOGIN=emuster42
PIN=97314

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
finish() {
	if [ -n "$PID" ]; then kill "$PID" 2>/dev/null || true; fi
	[ -n "$KEEP" ] && echo "The log stays in $WORK/debug." || rm -rf "$WORK"
}
trap finish EXIT
LOG="$WORK/debug/debug.log"
APP="$WORK/Moneten.app"
DATA="$WORK/Erika Mustermann"
mkdir -p "$DATA/Database/Moneten.sqlite"
ditto "$BUILT" "$APP"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $BUNDLE_ID" "$APP/Contents/Info.plist"
codesign --force --sign - --entitlements App/Moneten.entitlements "$APP" 2>/dev/null
MONETEN_DATA_DIR="$DATA" MONETEN_DEBUG_DIR="$WORK/debug" MONETEN_FINTS_HELPER="$PWD/scripts/fake-fints-helper.sh" \
	"$APP/Contents/MacOS/Moneten" -lockAfterInactivity NO -ApplePersistenceIgnoreState YES >"$WORK/app.log" 2>&1 &
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
		return {balance = 12.5, transactions = {}}
	end
	function EndSession() end
	function Result()
		print("Erika Mustermann")
		MM.printStatus("Erika Mustermann")
		return {owner = "Erika Mustermann", accountNumber = "5550001"}
	end
EOF

send() {
	"$NOTIFY" "$WORK/debug" "$@"
}

alive() {
	case "$(ps -o stat= -p "$PID")" in "" | Z*) return 1 ;; esac
}

# Sends the command in $2 and the rest until a line written after the first send matches $1, for up to 30 seconds.
poll() {
	pattern=$1
	shift
	seen=$({ wc -l <"$LOG"; } 2>/dev/null || echo 0)
	deadline=$(($(date +%s) + 30))
	while :; do
		send "$@"
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

poll "^phase=failed" state
rmdir "$DATA/Database/Moneten.sqlite"
send create check-debug-log
poll "phase=unlocked" state
cat >"$DATA/export.json" <<-'EOF'
	{"format": "moneten-export", "version": 1, "exportedAt": "2026-11-14T23:46:40.000Z", "accountGroups": [], "accounts": [],
	"accesses": [], "categories": [], "transactions": [], "deletedTransactions": [], "holdings": [],
	"portfolioValues": [{"accountID": "6F1C2A1E-0000-4000-8000-000000000001", "day": "Erika Mustermann", "value": "1.00", "currency": "EUR"}]}
EOF
poll "^importall " importall "$DATA/export.json"
poll "^exportall " exportall "$DATA/missing/export.json"
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
poll "status line=.* accesses=1" status
send refresh all
poll "status #2 [a-zA-Z]* refreshing=false refreshedAt=[^-]" status
send refresh all
poll "status #1 savings refreshing=false .*error=[^-]" status
for account in Girokonto Tagesgeld Kreditkarte; do
	poll "^rows " rows "$account"
done
poll "^snapshot .*error" errorsnapshot Tagesgeld
poll "^ext account savings .*failed=" extstate
send select Girokonto
poll "^phase=" state
send selectRows 1
poll "^exportcontextcsv rows=" exportcontextcsv "$DATA/context.csv"
poll "^exportstatus running=false" exportstatus
poll "^exportcsv rows=" exportcsv "$DATA/rows.csv"
send cancelexport
poll "^exportstatus running=false" exportstatus
poll "^snapshot " snapshot check
printf '%s\n' "Buchungstag;Valuta;Empfänger;Verwendungszweck;Betrag" "09.11.2026;Wartungsarbeiten;Erika Mustermann;Gehalt November;1.250,00" \
	"10.11.2026;10.11.2026;Wohnbau Musterstadt eG;Miete;-950,00" >"$WORK/Erika Mustermann.csv"
send importfile "$WORK/Erika Mustermann.csv"
poll "^importfile done" state
poll "^alert " alert
poll "^rows " rows Girokonto
poll "^gave up$" search "currency:/^+?49/"
send search ""
send selectRows 1
send newcategory Haushaltskasse
poll "selection=.*SidebarSelection.category" state
send selectRows 1
poll "^mainkey escape .*category=[^d]" mainkey escape
poll "^droprows category=" droprows Haushaltskasse
poll "^movecategory position=" movecategory "Haushaltskasse||0"
poll "^dropcategory hover=false" dropcategory "Haushaltskasse|Haushaltskasse"

send extfile "$WORK/Check.lua"
poll "^ext allowed Check" extconfirm
send extaccess "Check||Check Bank"
poll "^ext prompt login" extprompt
send extlogin "$LOGIN|check-debug-log"
poll "^ext account giro rows=0 balance=1250" extstate
send extrefresh "Check||"
poll "^ext print Check" extstate
send extrefresh "Check||"
poll "^ext access Check Bank state=failed" extstate
send extrun "$WORK/Check.lua|Result|"
poll "^ext result" state
send quit

found=0
for value in DE02120300000000202051 "DE02 1203" 202051 1234567890 4711 5550001 "$LOGIN" "$PIN" 123456 check-debug-log \
	Girokonto Tagesgeld Kreditkarte Extrakonto "Erika Mustermann" "Beispiel GmbH" "Wohnbau Musterstadt" "Tankstelle Beispiel" \
	"Gehalt November" Miete Kartenzahlung Sparen Haushaltskasse MIETE-2026-11 GUTSCHRIFT DAUERAUFTRAG \
	"Zugang vorübergehend gesperrt" "PIN falsch" Wartungsarbeiten pushTAN-App "currency:/^+?49/"; do
	if grep -n -w -F -- "$value" "$LOG" >&2; then
		echo "debug.log holds \"$value\"." >&2
		found=1
	fi
done
[ "$found" = 0 ] && echo "debug.log holds no personal data in $(wc -l <"$LOG" | tr -d ' ') lines."
exit $found
