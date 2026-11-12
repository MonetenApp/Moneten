WebBanking{version = 1.00, services = {"Guard"}, description = "Guard"}

function Check()
	-- The guard of the Amazon extensions: "signed version has no io.open functions".
	if io ~= nil and io.open ~= nil then return "file" else return "none" end
end
