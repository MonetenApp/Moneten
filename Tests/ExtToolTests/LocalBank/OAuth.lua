WebBanking{version = 1, services = {"OAuth Bank"}, description = "A made-up bank with an OAuth login with PKCE on bank.localhost"}

local connection, token

function SupportsBank(protocol, bankCode)
	return bankCode == "OAuth Bank"
end

function InitializeSession(protocol, bankCode, username, customer, password)
	connection = Connection()
	local verifier = MM.base64urlencode(MM.random(32))
	local challenge = MM.base64urlencode(MM.hexToBin(MM.sha256(verifier)))
	local authorize = "https://bank.localhost/authorize?client_id=ext&code_challenge=" .. challenge .. "&code_challenge_method=S256&nonce=" .. MM.uuid()
	local code = JSON(connection:get(authorize)):dictionary().code
	local body = "grant_type=authorization_code&code=" .. code .. "&code_verifier=" .. verifier .. "&password=" .. MM.urlencode(password)
	local answer = JSON(connection:request("POST", "https://bank.localhost/token", body, "application/x-www-form-urlencoded")):dictionary()
	if not answer.access_token then
		return LoginFailed
	end
	token = answer.access_token
end

function ListAccounts(knownAccounts)
	local account = JSON(connection:request("GET", "https://bank.localhost/api/accounts", nil, nil, {Authorization = "Bearer " .. token})):dictionary()
	return {{name = account.name, accountNumber = account.number, currency = "EUR", type = AccountTypeGiro}}
end

function RefreshAccount(account, since)
	return {balance = 100, transactions = {}}
end

function EndSession()
end
