--╭─────────────────────────────────────╮
--│          Object Definition          │
--╰─────────────────────────────────────╯
local attrFilter = pd.Class:new():register("l.attrfilter")
local dddd = require("dddd")

-- ─────────────────────────────────────
function attrFilter:initialize(_, argv)
	self.inlets = 1
	self.outlets = 1
	self.objects = {}
	self.outletId = tostring(self._object):match("userdata: (0x[%x]+)")
	self.attr = argv[1]
	self.value = argv[2]
	if self.attr == nil then
		self:error("[u.attrfilter] No filter attribute provided! Examples are: 'fill', 'stroke', 'id' and others")
		return false
	end
	if self.value == nil then
		self:error(
			"[u.attrfilter] No filter attribute value provided! Examples are: '#ff0000' for stroke or fill, 'path12' for id and others"
		)
		return false
	end

	return true
end

-- ─────────────────────────────────────
function attrFilter:in_1_dddd(x)
	local id = x[1]
	local in_dddd = dddd:new_fromid(self, id)
	local obj = in_dddd:get_table()

	if not obj then
		self:error("[u.attrfilter] No object found!")
		return
	end

	if obj[self.attr] == self.value then
		local out_dddd = dddd:new_fromtable(self, obj)
		out_dddd:output(1)
		return
	end

	local objvalue = obj.attr[self.attr]
	if objvalue == self.value then
		local out_dddd = dddd:new_fromtable(self, obj)
		out_dddd:output(1)
	end
end
