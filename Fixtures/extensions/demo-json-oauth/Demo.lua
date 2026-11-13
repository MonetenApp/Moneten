WebBanking{version = 1.0, services = {"Demo Broker", "Demo Broker Three"}, description = "A made-up broker with an OAuth login"}

local connection = Connection()

local function token(form)
	local content = connection:request("POST", "https://api.broker.example/token", form, "application/x-www-form-urlencoded", {Accept = "application/json"})
	return JSON(content):dictionary()
end

local function api(path)
	local content = connection:request("GET", "https://api.broker.example" .. path, nil, nil,
		{Accept = "application/json", Authorization = "Bearer " .. LocalStorage.session.accessToken})
	return JSON(content):dictionary()
end

local function authorize(final)
	return {challenge = "https://auth.broker.example/authorize?client_id=demo&final=" .. final .. "&state=xyz", state = "xyz"}
end

function SupportsBank(protocol, bankCode)
	return protocol == ProtocolWebBanking and (bankCode == "Demo Broker" or bankCode == "Demo Broker Three")
end

function InitializeSession2(protocol, bankCode, step, credentials, interactive)
	if step == 1 and LocalStorage.session then
		local answer = token("grant_type=refresh_token&refresh_token=" .. MM.urlencode(LocalStorage.session.refreshToken, "UTF-8"))
		LocalStorage.session.accessToken = answer.access_token
		LocalStorage.session.device.runs = LocalStorage.session.device.runs + 1
		print("LocalStorage kept, run " .. LocalStorage.session.device.runs)
		return nil
	end
	if step == 1 then
		print("LocalStorage empty")
		return authorize(1)
	end
	print("Code with " .. #credentials[1] .. " characters at step " .. step)
	if bankCode == "Demo Broker Three" and step < 4 then
		return authorize(step)
	end
	local answer = token("grant_type=authorization_code&code=" .. MM.urlencode(credentials[1], "UTF-8"))
	LocalStorage.session = {refreshToken = answer.refresh_token, accessToken = answer.access_token, device = {name = "Demo device", runs = 1}}
end

function ListAccounts(knownAccounts)
	local accounts = {}
	for _, account in ipairs(api("/accounts").accounts) do
		table.insert(accounts, {name = account.name, owner = account.owner, accountNumber = account.id, currency = account.currency, type = AccountTypeSavings})
	end
	return accounts
end

function RefreshAccount(account, since)
	local answer = api("/accounts/" .. account.accountNumber .. "/transactions")
	local transactions = {}
	for _, item in ipairs(answer.items) do
		table.insert(transactions, {transactionId = item.id, bookingDate = item.booked_at, name = item.counterparty, purpose = item.reference, amount = item.amount})
	end
	return {balance = answer.balance, transactions = transactions}
end

function EndSession()
	print("EndSession")
end
