WebBanking{version = 1.00, description = "Removed"}

function OpenFile()
	return io.open("/etc/hosts")
end

function Execute()
	return os.execute("ls")
end

function Require()
	return require("socket")
end
