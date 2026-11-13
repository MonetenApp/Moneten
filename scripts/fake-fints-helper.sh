#!/bin/sh
# A made-up FinTS helper for a debug build: it speaks the JSON lines of Sources/FinTS/HelperProtocol.swift
# for the bank "Musterbank" (12030000) and contacts no bank. Start the app with it:
#   open --env MONETEN_DATA_DIR=<folder> --env MONETEN_DEBUG_DIR=<folder> \
#     --env MONETEN_FINTS_HELPER="$PWD/scripts/fake-fints-helper.sh" dist/Moneten.app
# The login asks for a PIN and a TAN. The PIN has 4 to 10 characters, 0000 is wrong, and any other works.
# The TAN dialog of the login offers to change from pushTAN to mobileTAN, which asks for a TAN medium
# and then for the SMS code. The login lists
# "Girokonto" with the test IBAN, "Tagesgeld", and "Kreditkarte". The state of the access counts the
# refreshes: the second refresh fails "Tagesgeld" with an error of the bank, and the others succeed.
# The login "unterkonten" lists two subaccounts of the account number 9 in place of these accounts.
# The bank directory has two branches of Musterbank, the bank without a FinTS server Neobank Muster
# (99999999), a made-up Sparkasse, and Consorsbank (76030080) and DAB BNP Paribas (70120400) with
# their real FinTS address, so the setup shows the login hint of Consorsbank and none for DAB.
# Musterbank 12030000 has the Bankleitzahl of DKB and shows the hint of DKB. The login of every
# bank goes to this script.
# The app starts the helper with an empty environment.
PATH=/bin:/usr/bin
read -r cmd
field() { printf '%s\n' "$cmd" | sed -n "s/.*\"$1\":\"\([^\"]*\)\".*/\1/p"; }
day() { date -v-"$1"d +%Y-%m-%d; }
# Reads the next answer of the app into $value, or a change of the TAN method into $method, and ends the run on a cancel.
answer() {
	read -r line || exit 0
	case "$line" in *'"type":"cancel"'*) exit 0 ;; esac
	value=$(printf '%s\n' "$line" | sed -n 's/.*"value":"\([^"]*\)".*/\1/p')
	method=$(printf '%s\n' "$line" | sed -n 's/.*"method":"\([^"]*\)".*/\1/p')
}
pin='{"type":"ask","id":1,"kind":"pin","rules":{"minLength":4,"maxLength":10}}'

case "$cmd" in
*'"type":"banks"'*)
	echo '{"type":"banks","banks":['\
'{"code":"12030000","name":"Musterbank","city":"Musterstadt","bic":"BYLADEM1001","url":"https://fints.musterbank.example/fints"},'\
'{"code":"12030001","name":"Musterbank","city":"Beispielstadt","url":"https://fints.musterbank.example/fints"},'\
'{"code":"99999999","name":"Neobank Muster","city":"Musterstadt","bic":"NEOMDEM1XXX"},'\
'{"code":"40099999","name":"Sparkasse Münsterland Muster","city":"Münster","url":"https://banking.s-fints-pt-muster.example/fints30"},'\
'{"code":"70120400","name":"BNP Paribas S.A. Niederlassung Deutschland-Consorsbank","city":"München","bic":"DABBDEMMXXX","url":"https://brokerage-hbci.consorsbank.de/hbci"},'\
'{"code":"76030080","name":"Bnp Paribas S.A. Niederlassung Deutschland - Consorsbank","city":"Nürnberg, Mittelfr","bic":"CSDBDE71XXX","url":"https://brokerage-hbci.consorsbank.de/hbci"}]}'
	;;
*'"type":"accounts"'*)
	echo "$pin"
	answer
	if [ "$value" = 0000 ]; then
		echo '{"type":"ask","id":2,"kind":"pin","rejected":{"code":"9942","text":"PIN falsch. Bitte prüfen Sie Ihre Eingabe."},"rules":{"minLength":4,"maxLength":10}}'
		answer
		exit 0
	fi
	echo '{"type":"ask","id":2,"kind":"tan","purpose":"login","prompt":"Bitte geben Sie die TAN aus Ihrer pushTAN-App ein.","current":"921","methods":[{"id":"921","name":"pushTAN","delivery":"push"},{"id":"901","name":"mobileTAN","medium":true,"delivery":"sms"}]}'
	answer
	if [ "$method" = 901 ]; then
		sleep 2
		echo '{"type":"ask","id":3,"kind":"tanMedium","purpose":"login","media":["Handy privat","Handy Firma"]}'
		answer
		sleep 2
		echo '{"type":"ask","id":4,"kind":"tan","purpose":"login","prompt":"Bitte geben Sie die TAN aus der SMS an '"$value"' ein."}'
		answer
	fi
	echo '{"type":"notice","text":"Wartungsarbeiten am 14.11.2026 von 1 bis 5 Uhr."}'
	case "$cmd" in *'"user":"unterkonten"'*)
		echo '{"type":"accounts","accounts":[{"number":"9","subnumber":"01","product":"Sparkonto","kind":"10","currency":"EUR"},{"number":"9","subnumber":"02","product":"Sparkonto Plus","kind":"10","currency":"EUR"}]}'
		echo '{"type":"state","data":"MA=="}'
		exit 0
	;; esac
	echo '{"type":"accounts","accounts":[{"number":"202051","iban":"DE02120300000000202051","bic":"BYLADEM1001","product":"Girokonto","kind":"1","owner":"Erika Mustermann","currency":"EUR"},{"number":"1234567890","product":"Tagesgeld","kind":"10","owner":"Erika Mustermann","currency":"EUR"},{"number":"4711","product":"Kreditkarte","kind":"50","currency":"EUR"}]}'
	echo '{"type":"state","data":"MA=="}'
	;;
*'"type":"refresh"'*)
	runs=$(field state | base64 -D 2>/dev/null)
	echo "$pin"
	answer
	echo '{"type":"progress","done":0,"of":3}'
	sleep 3
	case "$cmd" in *'"id":"DE02120300000000202051"'*)
		echo "{\"type\":\"result\",\"account\":\"DE02120300000000202051\",\"balance\":{\"amount\":\"2340.15\",\"currency\":\"EUR\",\"date\":\"$(day 0)\"},\"transactions\":{\"from\":\"$(day 90)\",\"rows\":[{\"booked\":\"$(day 9)\",\"value\":\"$(day 9)\",\"amount\":\"3200.00\",\"currency\":\"EUR\",\"name\":\"Beispiel GmbH\",\"iban\":\"DE02120300000000202051\",\"purpose\":\"Gehalt November\",\"bookingText\":\"GUTSCHRIFT\",\"pending\":false},{\"booked\":\"$(day 4)\",\"value\":\"$(day 4)\",\"amount\":\"-950.00\",\"currency\":\"EUR\",\"name\":\"Wohnbau Musterstadt eG\",\"purpose\":\"Miete\",\"endToEnd\":\"MIETE-2026-11\",\"bookingText\":\"DAUERAUFTRAG\",\"pending\":false},{\"booked\":\"$(day 1)\",\"value\":\"$(day 1)\",\"amount\":\"-42.50\",\"currency\":\"EUR\",\"name\":\"Tankstelle Beispiel\",\"purpose\":\"Kartenzahlung\",\"pending\":true}]},\"errors\":[]}"
	;; esac
	echo '{"type":"progress","done":1,"of":3}'
	case "$cmd" in *'"id":"1234567890"'*)
		if [ "$runs" = 1 ]; then
			echo '{"type":"accountFailed","account":"1234567890","code":"9010","text":"Zugang vorübergehend gesperrt"}'
		else
			echo "{\"type\":\"result\",\"account\":\"1234567890\",\"balance\":{\"amount\":\"5012.40\",\"currency\":\"EUR\",\"date\":\"$(day 0)\"},\"transactions\":{\"from\":\"$(day 90)\",\"rows\":[{\"booked\":\"$(day 6)\",\"value\":\"$(day 6)\",\"amount\":\"500.00\",\"currency\":\"EUR\",\"name\":\"Erika Mustermann\",\"purpose\":\"Sparen\",\"pending\":false}]},\"errors\":[]}"
		fi
	;; esac
	echo '{"type":"progress","done":2,"of":3}'
	case "$cmd" in *'"id":"4711"'*)
		echo "{\"type\":\"result\",\"account\":\"4711\",\"balance\":{\"amount\":\"-120.00\",\"currency\":\"EUR\",\"date\":\"$(day 0)\"},\"errors\":[]}"
	;; esac
	echo "{\"type\":\"state\",\"data\":\"$(printf '%s' $(( ${runs:-0} + 1 )) | base64)\"}"
	;;
esac
