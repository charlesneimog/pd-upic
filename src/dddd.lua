local M = {}
M.__index = M
_G.dddd_outlets = _G.dddd_outlets or {}

-- ─────────────────────────────────────
local function random_string()
	local res = {}
	for i = 1, 12 do
		res[i] = string.format("%x", math.random(0, 15))
	end
	return table.concat(res)
end

-- ─────────────────────────────────────
-- Create a new dddd from pd atoms
function M:new(pdobj, atoms)
	local obj = setmetatable({}, self)
	obj.atoms = atoms or {}
	obj.table = self:table_from_atoms(atoms)
	obj.pdobj = pdobj
	obj.depth = self:get_depth(obj.table)
	return obj
end

-- ─────────────────────────────────────
-- Create a new dddd from a table
function M:new_fromtable(pdobj, t)
	local obj = setmetatable({}, self)
	obj.pdobj = pdobj
	obj.table = t
	obj.depth = self:get_depth(obj.table)
	return obj
end

-- ─────────────────────────────────────
function M:settype(typename)
	self.type = typename
end

-- ─────────────────────────────────────
function M:asserttype(typename)
	if typename ~= self.type then
		self.pdobj:error("[" .. self.pdobj._name .. "] Expected type " .. self.type .. " received type " .. typename)
		error("[" .. self.pdobj._name .. "] Expected type " .. self.type .. " received type " .. typename)
	end
end

-- ─────────────────────────────────────
function M:new_fromid(pdobj, id)
	local obj = setmetatable({}, self)
	obj.atoms = {}
	local stored = _G.dddd_outlets[id]
	if stored == nil then
		error("dddd outlet id " .. tostring(id) .. " not found")
	end

	-- We store the *dddd instance* in _G.dddd_outlets (see M:output).
	-- Consumers expect `get_table()` to return the underlying payload table
	-- (e.g. the SVG DOM node with `.attr`).
	if type(stored) == "table" and type(stored.get_table) == "function" then
		obj.table = stored:get_table()
	else
		obj.table = stored
	end

	obj.depth = self:get_depth(obj.table)
	obj._id = random_string()
	obj.pdobj = pdobj
	return obj
end

-- ─────────────────────────────────────
function M.get_ddddfromid(pdobj, id)
	local original = _G.dddd_outlets[id]
	if not original then
		error("dddd with id " .. tostring(id) .. " not found")
	end

	local function deep_copy_table(obj)
		if type(obj) ~= "table" then
			local copy = obj
			return copy
		else
			local copy = {}
			for k, v in pairs(obj) do
				copy[k] = v
			end
			return copy
		end
	end

	local cloned_table = deep_copy_table(original:get_table())
	local cloned = M:new_fromtable(pdobj, cloned_table)
	return cloned
end

-- ─────────────────────────────────────
function M:output(i)
	local id = random_string()
	local str = "<" .. id .. ">"
	_G.dddd_outlets[str] = self
	pd._outlet(self.pdobj._object, i, "dddd", { str })
	_G.dddd_outlets[str] = nil -- clear memory
end

-- ─────────────────────────────────────
function M:get_depth(tbl)
	if type(tbl) ~= "table" then
		return 0
	end
	local max_depth = 0
	for _, v in ipairs(tbl) do
		local d = self:get_depth(v)
		if d > max_depth then
			max_depth = d
		end
	end
	return max_depth + 1
end

-- ─────────────────────────────────────
function M:to_table(str)
	local list_b = str:match("^%s*(%b[])%s*$")
	local result
	if list_b then
		result = self:parse_list(list_b, 1)
	end

	local list_p = str:match("^%s*(%b())%s*$")
	if list_p then
		result = self:parse_list(list_p, 1)
	end
	return result
end

-- ─────────────────────────────────────
function M:table_from_atoms(atoms)
	local parts = {}
	if type(atoms) == "table" then
		for _, v in ipairs(atoms) do
			table.insert(parts, tostring(v))
		end
	else
		self._s_open = "("
		self._s_close = ")"
		self.table = atoms
		return self.table
	end

	local str = table.concat(parts, " ")
	local open, _ = self:check_brackets(str)

	local list_str
	if open == "(" then
		list_str = "(" .. str .. ")"
		self._s_open = "("
		self._s_close = ")"
	elseif open == "[" then
		list_str = "[" .. str .. "]"
		self._s_open = "["
		self._s_close = "]"
	else
		return
	end

	self.table = self:to_table(list_str)
	return self.table
end

-- ─────────────────────────────────────
function M:print()
	if type(self.table) ~= "table" then
		return
	end

	local parts = {}
	for _, v in ipairs(self.table) do
		if type(v) == "table" then
			table.insert(parts, self:to_string(v))
		else
			table.insert(parts, tostring(v))
		end
	end
	pd.post(table.concat(parts, " "))
end

-- ─────────────────────────────────────
function M:to_string(tbl)
	if type(tbl) ~= "table" then
		return tostring(tbl)
	end

	local parts = {}
	for _, v in ipairs(tbl) do
		if type(v) == "table" then
			table.insert(parts, self:to_string(v))
		else
			table.insert(parts, tostring(v))
		end
	end

	if self._s_open == nil or self._s_close == nil then
		self._s_open = "("
		self._s_close = ")"
	end

	return self._s_open .. table.concat(parts, " ") .. self._s_close
end

-- ─────────────────────────────────────
function M:check_brackets(str)
	local thereis_b = str:find("%[") or str:find("%]")
	local thereis_p = str:find("%(") or str:find("%)")

	if thereis_b and thereis_p then
		error("mixed brackets and parenthesis are not allowed")
	elseif not thereis_b and not thereis_p then
		return "[", "]"
	elseif thereis_b then
		return "[", "]"
	elseif thereis_p then
		return "(", ")"
	else
		return nil, nil
	end
end

-- ─────────────────────────────────────
function M:parse_list(str, i)
	local result = {}
	local token = ""
	i = i + 1

	local char_open, char_close = self:check_brackets(str)

	while i <= #str do
		local ch = str:sub(i, i)

		if ch == char_open then
			local sublist
			sublist, i = self:parse_list(str, i)
			table.insert(result, sublist)
		elseif ch == char_close then
			if token ~= "" then
				local num = tonumber(token)
				table.insert(result, num or token)
				token = ""
			end
			return result, i
		elseif ch == " " or ch == "\t" or ch == "\n" then
			if token ~= "" then
				local num = tonumber(token)
				table.insert(result, num or token)
				token = ""
			end
		else
			token = token .. ch
		end

		i = i + 1
	end

	return result, i
end

-- ─────────────────────────────────────
function M:get_table()
	return self.table
end

return M
