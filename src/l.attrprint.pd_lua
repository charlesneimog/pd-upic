--╭─────────────────────────────────────╮
--│          Object Definition          │
--╰─────────────────────────────────────╯
local attrPrint = pd.Class:new():register("l.attrprint")
local dddd = require("dddd")

-- ─────────────────────────────────────
function attrPrint:initialize(_, _)
	self.inlets = 1
	return true
end

-- ─────────────────────────────────────
local function attrprint(k, v)
	-- check if v is table
	if type(v) == "table" then
		for index, value in ipairs(v) do
			attrprint(index, value)
		end
	else
		pd.post(k .. ": " .. v)
	end
end
-- ─────────────────────────────────────
function attrPrint:in_1_dddd(x)
	local id = x[1]
	local obj = dddd:new_fromid(self, id):get_table()

	if obj == nil then
		self:error("[u.attrprint] No object found!")
		return
	end
	for k, v in pairs(obj) do
		attrprint(k, v)
	end
end
