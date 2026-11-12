local open = io.open

WebBanking{version = 1.00, services = {"Shop"}, description = "Shop"}

function Check()
	return {open = open == nil and "nil" or "function", io = type(io)}
end
