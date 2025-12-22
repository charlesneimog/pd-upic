local M = {}

function pd.Class:SvgObjOutlet(outlet, outletId, atoms)
	local str = "<" .. outletId .. ">"
	pd[str] = atoms
	pd._outlet(self._object, outlet, "SvgObj", { str })
end

function M.random_string(len)
	local res = {}
	for i = 1, len do
		res[i] = string.format("%x", math.random(0, 15))
	end
	return table.concat(res)
end

return M
