WebBanking{version = 1.0, services = {"Demo TAN", "Demo Push", "Demo Methods", "Demo Captcha", "Demo Broken"},
	description = "A made-up JSON service with two-factor challenges"}

local connection = Connection()
local slug
local waiting = false

local function api(method, path, body)
	local content = connection:request(method, "https://api.bank.example" .. path, body and JSON():set(body):json() or nil,
		body and "application/json" or nil, {Accept = "application/json"})
	return JSON(content):dictionary()
end

function SupportsBank(protocol, bankCode)
	return protocol == ProtocolWebBanking and bankCode:sub(1, 5) == "Demo "
end

function InitializeSession2(protocol, bankCode, step, credentials, interactive)
	slug = bankCode:sub(6):lower()
	if step == 1 and not waiting then
		local answer = api("POST", "/login/" .. slug, {user = credentials[1], password = credentials[2]})
		if answer.error then
			return LoginFailed
		end
		if slug == "push" then
			waiting = true
			return {title = "Confirm the login in the Demo app.", challenge = "Open the Demo app on your phone and confirm the login.", poll = true}
		elseif slug == "methods" then
			return {tanMethods = {
				{name = "pushTAN", hbciMethod = "700"},
				{name = "mobileTAN", hbciMethod = "701", mediumName = "+49 *** 4567"},
				{name = "chipTAN", hbciMethod = "702", errorMessage = "Activate this method on the website first."},
			}}
		elseif slug == "captcha" then
			return {challenge = "https://www.recaptcha.net/recaptcha/api.js?sitekey=demo-site-key&type=checkbox&referer=" ..
				MM.urlencode("https://www.bank.example/login", "UTF-8")}
		elseif slug == "tan" then
			return {title = "Enter the code from the SMS.", label = "mobileTAN", button = "next"}
		end
		return nil
	end
	if waiting then
		local status = api("GET", "/login/push/status")
		print("Approval status " .. status.status)
		if status.status == "pending" then
			return credentials[3] and {title = "Confirm the login in the Demo app.", challenge = "Open the Demo app on your phone and confirm the login.", poll = true}
				or credentials[2]
		end
		waiting = false
		return nil
	end
	if slug == "methods" and type(credentials[1]) == "table" then
		print("Chosen method " .. credentials[1].hbciMethod .. " " .. credentials[1].label)
		return {label = credentials[1].label, challenge = "We sent a code to " .. (credentials[1].mediumName or "your phone") .. "."}
	end
	if slug == "captcha" then
		print("Captcha token with " .. #credentials[1] .. " characters")
	end
	local answer = api("POST", "/tan/" .. slug, {tan = credentials[1]})
	if not answer.ok then
		return "The code was not accepted."
	end
end

function ListAccounts(knownAccounts)
	local accounts = {}
	for _, account in ipairs(api("GET", "/accounts/" .. slug).accounts) do
		table.insert(accounts, {name = account.name, owner = account.owner, accountNumber = account.number, currency = "EUR", type = AccountTypeGiro})
	end
	return accounts
end

function RefreshAccount(account, since)
	local answer = api("GET", "/accounts/" .. slug .. "/" .. account.accountNumber .. "/transactions")
	if answer.error then
		return answer.error
	end
	local transactions = {}
	for _, item in ipairs(answer.transactions) do
		table.insert(transactions, {transactionId = item.id, bookingDate = item.date, name = item.name, purpose = item.purpose, amount = item.amount})
	end
	return {balance = answer.balance, transactions = transactions}
end

function EndSession()
	api("POST", "/logout")
	print("EndSession")
end
