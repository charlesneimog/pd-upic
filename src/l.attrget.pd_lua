--╭─────────────────────────────────────╮
--│          Object Definition          │
--╰─────────────────────────────────────╯
local attrGet = pd.Class:new():register("l.attrget")
local dddd = require("dddd")

-- ─────────────────────────────────────
function attrGet:initialize(_, argv)
	self.inlets = 1
	self.objects = {}
	self.outletId = tostring(self._object):match("userdata: (0x[%x]+)")
	if argv[1] == nil then
		self:error("[u.attrfilter] No filter provided!")
		return false
	end
	self.attr = argv
	self.outlets = #argv
	return true
end

-- ─────────────────────────────────────
function attrGet:in_1_dddd(x)
	local id = x[1]
	local dddd_table = dddd:new_fromid(self, id)
    local obj = dddd_table:get_table()

	if obj == nil then
		self:error("[l.attrget] No object found!")
		return
	end

	for i = #self.attr, 1, -1 do
		local objvalue = obj.attr[self.attr[i]]
		if self.attr[i] == "childs" then
			for _, v in pairs(obj.attr.childs) do
				local out_dddd = dddd:new_fromtable(self, v)
				out_dddd:output(1)
			end
			return
		end

		if objvalue then
			if type(objvalue) == "table" then
				local out_dddd = dddd:new_fromtable(self, objvalue)
				out_dddd:output(1)
			else
				self:outlet(i, "list", { objvalue })
			end
		else
			if objvalue then
				if type(objvalue) == "table" then
					local is_list = true
					local count = 0
					for k, _ in pairs(objvalue) do
						count = count + 1
						if type(k) ~= "number" or k ~= count then
							is_list = false
							break
						end
					end
					if is_list then
						self:outlet(i, "list", objvalue)
					else
						local out_dddd = dddd:new_fromtable(self, objvalue)
						out_dddd:output(1)
					end
				else
					self:outlet(i, "list", { objvalue })
				end
			else
				self:error(string.format("[u.attrget] No attribute '%s' found!", self.attr))
			end
		end
	end
end

-- ─────────────────────────────────────
function attrGet:in_1_reload()
	self:dofilex(self._scriptname)
end
