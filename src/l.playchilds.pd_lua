--╭─────────────────────────────────────╮
--│          Object Definition          │
--╰─────────────────────────────────────╯
local playChilds = pd.Class:new():register("l.playchilds")
local dddd = require("dddd")

-- ─────────────────────────────────────
function playChilds:initialize(_, argv)
	self.inlets = 1
	self.outlets = 1
	self.clock = pd.Clock:new():register(self, "player")
	self.playing = false
	self.onset = 0
	self.lastonset = 0
	self.objects = {}
	return true
end

-- ─────────────────────────────────────
function playChilds:in_1_dddd(x)
	local id = x[1]
	local obj = dddd:new_fromid(self, id):get_table()

	self.playing = true
	self.onset = 0
	self.lastonset = 0

	if obj == nil then
		self:error("[u.playchilds] No object found!")
		return
	end
	self.objects = {}

	if obj.attr.childs ~= nil then
		for _, child in pairs(obj.attr.childs) do
			local onset = child.attr.onset
			if obj.attr.name == "ellipse" or obj.attr.name == "circle" then
				onset = child.attr.startonset
			end
			if onset > self.lastonset then
				self.lastonset = onset
			end
			local key = "ms" .. math.floor(onset)
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
	local key = "ms" .. math.floor(self.onset)
	local object = self.objects[key]
	if object ~= nil then
		if #object == 1 then
			local out_dddd = dddd:new_fromtable(self, object[1])
			out_dddd:output(1)
		else
			for i = 1, #object do
				local out_dddd = dddd:new_fromtable(self, object[i])
				out_dddd:output(1)
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
