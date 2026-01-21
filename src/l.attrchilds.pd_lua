local function script_path()
	local str = debug.getinfo(2, "S").source:sub(2)
	return str:match("(.*[/\\])") or "./"
end
local mypd = require(script_path() .. "/SLAXML/mypd")

--╭─────────────────────────────────────╮
--│          Object Definition          │
--╰─────────────────────────────────────╯

local attrChilds = pd.Class:new():register("l.attrchilds")

-- ─────────────────────────────────────
function attrChilds:initialize(_, argv)
	self.inlets = 1
	self.outlets = 1
	self.objects = {}
	self.outletId = tostring(self._object):match("userdata: (0x[%x]+)")

	return true
end

-- ─────────────────────────────────────
function attrChilds:in_1_SvgObj(x)
	local id = x[1]
	local obj = pd[id]

	if not obj then
		self:error("[u.attrget] No object found!")
		return
	end

	for i = 1, #obj.child do
		self:SvgObjOutlet(1, self.outletId, obj.child[i])
	end
end

-- ─────────────────────────────────────
function attrChilds:in_1_reload()
	self:dofilex(self._scriptname)
end
