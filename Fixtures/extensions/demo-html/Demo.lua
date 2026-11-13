WebBanking{version = 1.0, url = "https://www.bank.example/login", services = {"Demo Bank"}, description = "A made-up bank with an HTML login form"}

local connection

function SupportsBank(protocol, bankCode)
	return protocol == ProtocolWebBanking and bankCode == "Demo Bank"
end

function InitializeSession(protocol, bankCode, username, customer, password, credential)
	connection = Connection()
	local login = HTML(connection:get(url))
	login:xpath("//input[@name='user']"):attr("value", username)
	login:xpath("//input[@name='pin']"):attr("value", password)
	local start = HTML(connection:request(login:xpath("//input[@name='login']"):click()))
	if start:xpath("//p[@class='error']"):length() > 0 then
		return LoginFailed
	end
end

function ListAccounts(knownAccounts)
	local accounts = {}
	HTML(connection:get("accounts")):xpath("//tr[@class='account']"):each(function (index, row)
		table.insert(accounts, {
			name = row:xpath(".//td[@class='name']"):text(),
			owner = row:xpath(".//td[@class='owner']"):text(),
			accountNumber = row:xpath(".//td[@class='iban']"):text(),
			iban = row:xpath(".//td[@class='iban']"):text(),
			bic = "BYLADEM1001",
			bankCode = "12030000",
			currency = "EUR",
			type = AccountTypeGiro,
		})
	end)
	return accounts
end

local function amount(text)
	return tonumber((text:gsub("%.", ""):gsub(",", ".")))
end

function RefreshAccount(account, since)
	local page = HTML(connection:get("transactions?account=" .. account.accountNumber))
	local transactions = {}
	page:xpath("//tr[@class='booking']"):each(function (index, row)
		local day, month, year = row:xpath(".//td[@class='date']"):text():match("(%d+)%.(%d+)%.(%d+)")
		table.insert(transactions, {
			transactionId = row:attr("data-id"),
			bookingDate = os.time{year = tonumber(year), month = tonumber(month), day = tonumber(day), hour = 12},
			name = row:xpath(".//td[@class='name']"):text(),
			purpose = row:xpath(".//td[@class='purpose']"):text(),
			amount = amount(row:xpath(".//td[@class='amount']"):text()),
			currency = "EUR",
		})
	end)
	return {balance = amount(page:xpath("//span[@id='balance']"):text()), transactions = transactions}
end

function EndSession()
	connection:get("logout")
	print("Logged out")
end
