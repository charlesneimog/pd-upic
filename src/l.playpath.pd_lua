--╭─────────────────────────────────────╮
--│          Object Definition          │
--╰─────────────────────────────────────╯
local playPath = pd.Class:new():register("l.playpath")
local dddd = require("dddd")

-- ─────────────────────────────────────
function playPath:initialize(_, _)
	self.inlets = 1
	self.outlets = 1
	self.objects = {}
	self.clock = pd.Clock:new():register(self, "player")
	self.outletId = tostring(self._object):match("userdata: (0x[%x]+)")
	self.lastonset = 0
	self.isplaying = false
	return true
end

--╭─────────────────────────────────────╮
--│               Helpers               │
--╰─────────────────────────────────────╯
local function round(num)
	if num % 1 >= 0.5 then
		return math.ceil(num)
	else
		return math.floor(num)
	end
end

-- ─────────────────────────────────────
function playPath:in_1_dddd(x)
	if self.isplaying then
		self:error("[u.playpath] Already playing!")
		return
	end
	self.objects = {}

	local id = x[1]
	local obj = dddd:new_fromid(self, id):get_table()

	if not obj then
		self:error("[u.attrfilter] No object found!")
		return
	end

	local mainsystem = obj.attr.mainsystem
	local system = obj.attr.system
	local points = obj.points
	self.points = {}
	local first_onset = ((points[1][1] - system.attr.x) / system.attr.width) * system.attr.duration
	for i = 1, #points do
		local this_onset = ((points[i][1] - system.attr.x) / system.attr.width) * system.attr.duration
		this_onset = round(this_onset - first_onset)

		if this_onset < 0 then
			this_onset = 0
		end

		if this_onset > self.lastonset then
			self.lastonset = this_onset
		end

		if self.objects[round(this_onset)] == nil then
			local child = {}
			child.attr = {}
			if obj.attr then
				for k, v in pairs(obj.attr) do
					child.attr[k] = v
				end
			end
			child.attr.mainsystem = mainsystem
			child.attr.system = system

			child.attr.onset = this_onset
			child.attr.x = tonumber(points[i][1])
			child.attr.y = tonumber(points[i][2])
			child.attr.rely = 1 - ((child.attr.y - system.attr.y) / system.attr.height)
			child.attr.relx = (child.attr.x - system.attr.x) / system.attr.width
			child.attr.maxwidth = tonumber(mainsystem.attr.width)
			child.attr.maxheight = tonumber(mainsystem.attr.height)
			self.objects[round(this_onset)] = { child }
		end
	end

	self.isplaying = true
	self.onset = 0
	self:player()
end

-- ─────────────────────────────────────
function playPath:player()
	local object = self.objects[self.onset]

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
		self.onset = 0
		self.isplaying = false
	else
		self.onset = self.onset + 1
		self.clock:delay(1)
	end
end
