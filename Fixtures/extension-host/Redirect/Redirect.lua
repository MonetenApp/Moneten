WebBanking{version = 1.00, services = {"Redirect Bank"}, description = "Redirect"}

function Plain()
	return Connection():request("GET", "http://bank.example/")
end

function Follow()
	return Connection():request("GET", "https://api.bank.example/start")
end
