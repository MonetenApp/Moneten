WebBanking{version = 1.0, services = {"Demo Statements"}, description = "A made-up service that calls a function Moneten lacks"}

function SupportsBank(protocol, bankCode) return bankCode == "Demo Statements" end
function InitializeSession(protocol, bankCode, username, customer, password, credential) end
function ListAccounts(knownAccounts)
	return {{name = "Demo Statements", accountNumber = "DE02120300000000202051", currency = "EUR", type = AccountTypeGiro}}
end

function RefreshAccount(account, since)
	local statement = ":20:STARTUMS\n:25:12030000/202051\n"
	local hashed = type(MM.bcrypt) == "function" and MM.bcrypt(statement) or statement
	local parsed = MM.parseSwiftMt(hashed)
	return {balance = 0, transactions = parsed}
end

function EndSession() end
