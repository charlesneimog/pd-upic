local function script_path()
	local str = debug.getinfo(2, "S").source:sub(2)
	return str:match("(.*[/\\])") or "./"
end
local mypd = require(script_path() .. "/SLAXML/mypd")

--╭─────────────────────────────────────╮
--│          Object Definition          │
--╰─────────────────────────────────────╯

local attrGet = pd.Class:new():register("l.attrget")

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
	pd.post(argv[1])
	self.outlets = #argv
	return true
end

-- ─────────────────────────────────────
function attrGet:in_1_SvgObj(x)
	local id = x[1]
	local obj = pd[id]

	if obj == nil then
		self:error("[l.attrget] No object found!")
		return
	end

	for k, v in pairs(obj.attr) do
		pd.post(k)
	end

	for i = #self.attr, 1, -1 do
		local objvalue = obj.attr[self.attr[i]]
		if self.attr[i] == "childs" then
			for _, v in pairs(obj.attr.childs) do
				self:SvgObjOutlet(i, self.outletId, v)
			end
			return
		end

		if objvalue then
			if type(objvalue) == "table" then
				self:SvgObjOutlet(i, self.outletId, objvalue)
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
						self:SvgObjOutlet(i, self.outletId, objvalue)
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
