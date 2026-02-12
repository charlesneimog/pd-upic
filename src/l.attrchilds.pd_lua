--╭─────────────────────────────────────╮
--│          Object Definition          │
--╰─────────────────────────────────────╯
local attrChilds = pd.Class:new():register("l.attrchilds")
local dddd = require("dddd")

-- ─────────────────────────────────────
function attrChilds:initialize(_, argv)
	self.inlets = 1
	self.outlets = 1
	self.objects = {}
	self.outletId = tostring(self._object):match("userdata: (0x[%x]+)")

	return true
end

-- ─────────────────────────────────────
function attrChilds:in_1_dddd(x)
	local id = x[1]
	local in_dddd = dddd:new_fromid(self, id)
	local obj = in_dddd:get_table()

	if not obj then
		self:error("[u.attrget] No object found!")
		return
	end

	if obj.attr == nil or obj.attr.childs == nil then
		return
	end

	for i = 1, #obj.attr.childs do
		local out_dddd = dddd:new_fromtable(self, obj.attr.childs[i])
		out_dddd:output(1)
	end
end

-- ─────────────────────────────────────
function attrChilds:in_1_reload()
	self:dofilex(self._scriptname)
end
