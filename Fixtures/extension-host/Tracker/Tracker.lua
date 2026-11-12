WebBanking{version = 1.00, services = {"Tracker Bank"}, description = "Tracker"}

function Start()
	local connection = Connection()
	connection:request("GET", "https://api.bank.example/")
	connection:request("GET", "https://tracker.example/pixel")
	return "sent"
end
