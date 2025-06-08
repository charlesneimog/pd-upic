local function script_path()
	local str = debug.getinfo(2, "S").source:sub(2)
	return str:match("(.*[/\\])") or "./"
end
local mypd = require(script_path() .. "/libs/mypd")

--╭─────────────────────────────────────╮
--│          Object Definition          │
--╰─────────────────────────────────────╯

local playChilds = pd.Class:new():register("l.playchilds")

-- ─────────────────────────────────────
function playChilds:initialize(_, argv)
	self.inlets = 1
	self.outlets = 1
	self.outletId = tostring(self._object):match("userdata: (0x[%x]+)")
	self.clock = pd.Clock:new():register(self, "player")
	self.playing = false
	self.onset = 0
	self.lastonset = 0
	self.objects = {}
	return true
end

-- ─────────────────────────────────────
function playChilds:in_1_SvgObj(x)
	self.playing = true
	self.onset = 0
	self.lastonset = 0

	local id = x[1]
	local obj = pd[id]
	if obj == nil then
		self:error("[u.playchilds] No object found!")
		return
	end
	self.objects = {}

	if obj.attr.childs ~= nil then
		for _, child in pairs(obj.attr.childs) do
			local onset = child.attr.onset
			if onset > self.lastonset then
				self.lastonset = onset
			end
			local key = "ms" .. onset
			if self.objects[key] == nil then
				self.objects[key] = {}
			end
			table.insert(self.objects[key], child)
		end
	end
	self.clock:delay(0)
end

-- ─────────────────────────────────────
function playChilds:player()
	local key = "ms" .. self.onset
	local object = self.objects[key]
	if object ~= nil then
		if #object == 1 then
			self:SvgObjOutlet(1, self.outletId, object[1])
		else
			for i = 1, #object do
				self:SvgObjOutlet(1, self.outletId, object[i])
			end
		end
	end

	if self.onset > self.lastonset then
		self.clock:unset()
		self.onset = 0
	else
		self.onset = self.onset + 1
		self.clock:delay(1)
	end
end
