# Writes made-up MoneyMoney exports with the structure of a real export, for the debug harness command
# migrationfixture. Run: python3 Fixtures/moneymoney/make.py
import datetime, os, plistlib

here = os.path.dirname(os.path.abspath(__file__))

def day(y, m, d):
	# MoneyMoney stores a booking date as midnight in Europe/Berlin.
	return datetime.datetime(y, m, d) - datetime.timedelta(hours=1)

accounts = [
	{"uuid": "G1", "name": "Private", "group": True, "indentation": 0, "type": "Account group", "balance": [[1734.56, "EUR"]]},
	{"uuid": "A1", "name": "Giro", "group": False, "indentation": 1, "type": "Giro account", "accountNumber": "DE02120300000000202051",
		"bankCode": "BYLADEM1001", "currency": "EUR", "owner": "Erika Mustermann", "portfolio": False, "balance": [[1234.56, "EUR"]]},
	{"uuid": "A2", "name": "Savings", "group": False, "indentation": 1, "type": "Savings account", "currency": "EUR", "portfolio": False,
		"balance": [[500.0, "EUR"]]},
	{"uuid": "A3", "name": "Depot", "group": False, "indentation": 0, "type": "Portfolio", "currency": "EUR", "portfolio": True,
		"balance": [[10000.0, "EUR"]]},
]
categories = [
	{"uuid": "C1", "name": "Household", "group": True, "default": False, "indentation": 0, "currency": "EUR", "rules": ""},
	{"uuid": "C2", "name": "Food", "group": False, "default": False, "indentation": 1, "currency": "EUR", "rules": "REWE OR \"Bäckerei*\"",
		"budget": {"amount": 200.0, "available": 154.1, "period": "monthly"}},
	{"uuid": "C3", "name": "Pets", "group": False, "default": False, "indentation": 1, "currency": "EUR", "rules": ""},
	{"uuid": "C4", "name": "Salary", "group": False, "default": False, "indentation": 0, "currency": "EUR", "rules": "(\"Lohn\" OR \"Gehalt\""},
	{"uuid": "C9", "name": "Sonstiges", "group": False, "default": True, "indentation": 0, "currency": "EUR", "rules": ""},
]
transactions = {"creator": "MoneyMoney", "transactions": [
	{"id": 1, "accountUuid": "A1", "bookingDate": day(2026, 11, 2), "valueDate": day(2026, 11, 2), "amount": -45.9, "currency": "EUR",
		"name": "REWE Markt", "purpose": "KARTENZAHLUNG", "booked": True, "categoryUuid": "C2", "checkmark": True, "comment": "Wocheneinkauf"},
	{"id": 2, "accountUuid": "A1", "bookingDate": day(2026, 11, 3), "amount": -89.0, "currency": "EUR", "name": "Stadtwerke Musterstadt",
		"purpose": "Abschlag", "accountNumber": "DE02120300000000202051", "bankCode": "BYLADEM1001", "endToEndReference": "E2E-1",
		"mandateReference": "M-1", "creditorId": "DE98ZZZ09999999999", "booked": True, "categoryUuid": "C9", "checkmark": False},
	{"id": 3, "accountUuid": "A1", "bookingDate": day(2026, 11, 4), "amount": -10.0, "currency": "EUR", "name": "Kiosk", "purpose": "",
		"booked": False, "categoryUuid": "C9", "checkmark": False},
	{"id": 4, "accountUuid": "A1", "bookingDate": day(2026, 10, 30), "amount": 2500.0, "currency": "EUR", "name": "Beispiel GmbH",
		"purpose": "Gehalt Oktober", "booked": True, "categoryUuid": "C4", "checkmark": True},
	{"id": 5, "accountUuid": "A2", "bookingDate": day(2026, 1, 1), "amount": 0.01, "currency": "EUR", "name": "Zinsen", "purpose": "",
		"booked": True, "categoryUuid": "C9", "checkmark": False},
]}
for name, value in [("accounts", accounts), ("categories", categories), ("transactions", transactions)]:
	with open(os.path.join(here, name + ".plist"), "wb") as f:
		plistlib.dump(value, f, fmt=plistlib.FMT_XML, sort_keys=True)
