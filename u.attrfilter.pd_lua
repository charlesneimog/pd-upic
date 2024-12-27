local function script_path()
	local str = debug.getinfo(2, "S").source:sub(2)
	return str:match("(.*[/\\])") or "./"
end
local mypd = require(script_path() .. "/libs/mypd")

--╭─────────────────────────────────────╮
--│          Object Definition          │
--╰─────────────────────────────────────╯

local attrFilter = pd.Class:new():register("u.attrfilter")

-- ─────────────────────────────────────
function attrFilter:initialize(_, argv)
	self.inlets = 1
	self.outlets = 1
	self.objects = {}
	self.outletId = tostring(self._object):match("userdata: (0x[%x]+)")
	self.attr = argv[1]
	self.value = argv[2]
	if self.attr == nil or self.value == nil then
		self:error("[u.attrfilter] No filter provided!")
		return false
	end

	return true
end

-- ─────────────────────────────────────
function attrFilter:in_1_SvgObj(x)
	local obj = pd[x[1]]
	if not obj then
		self:error("[u.attrfilter] No object found!")
		return
	end

	if obj[self.attr] == self.value then
		self:SvgObjOutlet(1, self.outletId, obj)
	end

	local objvalue = obj.attr[self.attr]
	if objvalue == self.value then
		self:SvgObjOutlet(1, self.outletId, obj)
	end
end
