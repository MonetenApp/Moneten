WebBanking{version = 1.0, description = "Uses the names that signed extensions use and the API page does not list"}

function Check()
	local connection = Connection()
	connection.redirects = false
	local content, charset, mimeType, filename, headers = connection:get("https://www.bank.example/login")
	local sequence = MM.derdecode(MM.hexToBin("3006020101020102"))
	local integers = MM.derdecode(sequence[1][2])
	return {
		location = headers["Location"],
		redirects = connection.redirects,
		sequenceTag = sequence[1][1],
		integers = {MM.binToHex(integers[1][2]), MM.binToHex(integers[2][2])},
		hello = MM.base64urldecode("SGVsbG8"),
		guarded = type(MM.bcrypt) == "function",
	}
end
