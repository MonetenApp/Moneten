WebBanking{version = 1.00, services = {"Demo Bank"}, description = "Demo"}

function Start()
	local content = Connection():request("GET", "https://www.bank.example/login")
	return content
end
