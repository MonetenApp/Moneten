WebBanking{version = 1, services = {"Local Bank"}, description = "A made-up bank on bank.localhost"}

local connection, token

function SupportsBank(protocol, bankCode)
	return bankCode == "Local Bank"
end

function InitializeSession(protocol, bankCode, username, customer, password)
	connection = Connection()
	local body = "username=" .. MM.urlencode(username) .. "&password=" .. MM.urlencode(password)
	local answer = JSON(connection:request("POST", "https://bank.localhost/login", body, "application/x-www-form-urlencoded")):dictionary()
	if not answer.ok then
		return LoginFailed
	end
	token = answer.access_token
	LocalStorage.runs = (LocalStorage.runs or 0) + 1
end

local function get(path)
	return JSON(connection:request("GET", "https://bank.localhost" .. path, nil, nil, {Authorization = "Bearer " .. token})):dictionary()
end

function ListAccounts(knownAccounts)
	local account = get("/api/accounts")
	return {{name = account.name .. " " .. LocalStorage.runs, accountNumber = account.number, currency = "EUR", type = AccountTypeGiro}}
end

function RefreshAccount(account, since)
	local first = get("/api/transactions?from=" .. os.date("%Y-%m-%d", MM.date(os.time(), "-30D")))
	local second = get(first.next)
	local transactions = {}
	for _, row in ipairs(first.rows) do table.insert(transactions, row) end
	for _, row in ipairs(second.rows) do table.insert(transactions, row) end
	return {balance = 100, transactions = transactions}
end

function EndSession()
	connection:get("https://bank.localhost/logout")
end
