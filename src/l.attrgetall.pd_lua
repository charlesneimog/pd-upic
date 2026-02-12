--╭─────────────────────────────────────╮
--│          Object Definition          │
--╰─────────────────────────────────────╯
local attrgetall = pd.Class:new():register("l.attrgetall")
local dddd = require("dddd")

-- ─────────────────────────────────────
function attrgetall:initialize(_, argv)
	self.inlets = 1
	self.outlets = 1
	self.level = argv[1] or 1
	return true
end

--╭─────────────────────────────────────╮
--│               Helpers               │
--╰─────────────────────────────────────╯
local function print_table(t, indent, maxindent)
	indent = indent or 0
	local prefix = string.rep("  ", indent) -- Indentation for nested tables

	if indent > maxindent then
		return
	end

	for k, v in pairs(t) do
		if type(v) == "table" then
			pd.post(prefix .. k .. ": {")
			print_table(v, indent + 1, maxindent)
			pd.post(prefix .. "}")
		else
			pd.post(prefix .. k, v)
		end
	end
end

--╭─────────────────────────────────────╮
--│               Methods               │
--╰─────────────────────────────────────╯
function attrgetall:in_1_dddd(x)
	local id = x[1]
	local obj = dddd:new_fromid(self, id):get_table()

	-- Print all attributes
	for k, v in pairs(obj) do
		if type(v) == "table" then
			pd.post(k .. ": {")
			print_table(v, 1, self.level)
			pd.post("}")
		else
			pd.post(k, v)
		end
	end
end
