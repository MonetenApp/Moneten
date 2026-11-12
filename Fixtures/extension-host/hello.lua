WebBanking{version = 1.00, services = {"Hello Bank"}, description = "Hello"}

function Hello()
	print("Saying hello")
	return {greeting = "Hello from " .. extensionName, version = version, sum = 1 + 2, list = {"a", "b"}}
end
