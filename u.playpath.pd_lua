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

local playPath = pd.Class:new():register("u.playpath")

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

	local obj = pd[x[1]]
	if not obj then
		self:error("[u.attrfilter] No object found!")
		return
	end

	local system = obj.attr.system
	local points = obj.points
	local mainOnset = obj.attr.onset

	self.points = {}
	for i = 1, #points do
		local this_onset = system.attr.start + (system.attr.duration * points[i][1] / system.attr.width) - mainOnset
		if this_onset > self.lastonset then
			self.lastonset = this_onset
		end

		if self.objects[round(this_onset)] == nil then
			local child = {}
			child.x = points[i][1] - system.attr.x
			child.y = points[i][2] - system.attr.y
			child.maxwidth = tonumber(system.attr.width)
			child.maxheight = tonumber(system.attr.height)
			child.attr = obj.attr
			self.objects[round(this_onset)] = { child }
		end
	end

	self.isplaying = true
	self.start = 0
	self:player()
end

-- ─────────────────────────────────────
function playPath:player()
	local object = self.objects[self.start]
	if object ~= nil then
		if #object == 1 then
			self:SvgObjOutlet(1, self.outletId, object[1])
		else
			for i = 1, #object do
				self:SvgObjOutlet(1, self.outletId, object[i])
			end
		end
	end

	if self.start > self.lastonset then
		self.clock:unset()
		self.start = 0
		self.isplaying = false
	else
		self.start = self.start + 1
		self.clock:delay(1)
	end
end
