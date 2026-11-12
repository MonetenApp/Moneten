WebBanking{version = 1.00, description = "Slow"}

function Wait()
	local started = os.clock()
	while os.clock() - started < 3 do end
	return "done"
end
