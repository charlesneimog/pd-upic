local function script_path()
	local str = debug.getinfo(2, "S").source:sub(2)
	return str:match("(.*[/\\])") or "./"
end

local mypd = require(script_path() .. "libs/mypd")

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

--╭─────────────────────────────────────╮
--│          Object Definition          │
--╰─────────────────────────────────────╯

local playPath = pd.Class:new():register("l.playpath")

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
-- ─────────────────────────────────────
function playPath:in_1_reload()
	self:dofilex(self._scriptname)
end

-- ─────────────────────────────────────
function playPath:in_1_SvgObj(x)
	if self.isplaying then
		self:error("[u.playpath] Already playing!")
		return
	end
	self.objects = {}

	local obj = pd[x[1]] -- defined inside mypd
	if not obj then
		self:error("[u.attrfilter] No object found!")
		return
	end

	local system = obj.attr.mainsystem
	local parent = obj.attr.system
	local points = obj.points
	self.points = {}
	for i = 1, #points do
		local this_onset = ((points[i][1] - system.attr.x) / system.attr.width) * system.attr.duration
		this_onset = round(this_onset - parent.attr.onset)
		if this_onset < 0 then
			this_onset = 0
		end

		if this_onset > self.lastonset then
			self.lastonset = this_onset
		end

		if self.objects[round(this_onset)] == nil then
			local child = {}
			child.attr = {}
			child.attr.fill = obj.attr.fill
			child.attr.stroke = obj.attr.stroke
			child.attr["stroke-width"] = obj.attr["stroke-width"]

			child.attr.onset = this_onset
			child.attr.x = tonumber(points[i][1]) - system.attr.x
			child.attr.y = tonumber(points[i][2]) - system.attr.y
			child.attr.rely = 1 - (child.attr.y / system.attr.height)
			child.attr.relx = child.attr.x / system.attr.width
			child.attr.maxwidth = tonumber(system.attr.width)
			child.attr.maxheight = tonumber(system.attr.height)
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
		self.isplaying = false
	else
		self.onset = self.onset + 1
		self.clock:delay(1)
	end
end
