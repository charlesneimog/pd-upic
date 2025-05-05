local function script_path()
	local str = debug.getinfo(2, "S").source:sub(2)
	return str:match("(.*[/\\])") or "./"
end
local mypd = require(script_path() .. "/libs/mypd")

--╭─────────────────────────────────────╮
--│          Object Definition          │
--╰─────────────────────────────────────╯

local attrGet = pd.Class:new():register("u.attrget")

-- ─────────────────────────────────────
function attrGet:initialize(_, argv)
	self.inlets = 1
	self.outlets = 1
	self.objects = {}
	self.outletId = tostring(self._object):match("userdata: (0x[%x]+)")
	self.attr = argv[1]
	if self.attr == nil then
		self:error("[u.attrfilter] No filter provided!")
		return false
	end
	return true
end

-- ─────────────────────────────────────
function attrGet:in_1_SvgObj(x)
	local id = x[1]
	local obj = pd[id]

	if not obj then
		self:error("[u.attrget] No object found!")
		return
	end
	--
	local objvalue = obj[self.attr]

	if objvalue then
		-- check if the value has table inside
		if type(objvalue) == "table" then
			self:SvgObjOutlet(1, self.outletId, objvalue)
		else
			self:outlet(1, "list", { objvalue })
		end
	else
		objvalue = obj.attr[self.attr]
		if objvalue then
			if type(objvalue) == "table" then
				self:SvgObjOutlet(1, self.outletId, objvalue)
			else
				self:outlet(1, "list", { objvalue })
			end
		else
			self:error(string.format("[u.attrget] No attribute '%s' found!", self.attr))
		end
	end
end

-- ─────────────────────────────────────
function attrGet:in_1_reload()
	self:dofilex(self._scriptname)
end
