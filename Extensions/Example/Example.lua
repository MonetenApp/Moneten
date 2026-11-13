WebBanking{version = 1.0, url = "https://www.bank.example", services = {"Example Bank"}, description = "A made-up bank for the ext tool"}

local connection

function SupportsBank(protocol, bankCode)
	return protocol == ProtocolWebBanking and bankCode == "Example Bank"
end

function InitializeSession(protocol, bankCode, username, customer, password, credential)
	LocalStorage.deviceId = LocalStorage.deviceId or MM.uuid()
	connection = Connection()
	local body = "username=" .. MM.urlencode(username) .. "&password=" .. MM.urlencode(password)
	local answer = JSON(connection:request("POST", url .. "/login", body, "application/x-www-form-urlencoded", {["X-Device"] = LocalStorage.deviceId})):dictionary()
	if answer.ok ~= true then
		return LoginFailed
	end
end

function ListAccounts(knownAccounts)
	local accounts = {}
	local list = JSON(connection:request("GET", url .. "/api/accounts", nil, nil, {["X-Request-Id"] = MM.uuid()})):dictionary()
	for _, account in ipairs(list.accounts) do
		table.insert(accounts, {
			name = account.name,
			owner = account.owner,
			accountNumber = account.number,
			iban = account.iban,
			bic = account.bic,
			currency = account.currency,
			type = AccountTypeGiro,
		})
	end
	return accounts
end

local function amount(text)
	return tonumber((text:gsub("%.", ""):gsub(",", ".")))
end

function RefreshAccount(account, since)
	local from = os.date("%Y-%m-%d", MM.date(os.time(), "-30D"))
	local page = HTML(connection:get(url .. "/accounts/" .. account.accountNumber .. "/transactions?from=" .. from))
	local transactions = {}
	page:xpath("//tr[@class='booking']"):each(function (index, row)
		local day, month, year = row:xpath(".//td[@class='date']"):text():match("(%d+)%.(%d+)%.(%d+)")
		table.insert(transactions, {
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
	connection:get(url .. "/logout")
end
