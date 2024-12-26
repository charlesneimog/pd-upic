local function script_path()
	local str = debug.getinfo(2, "S").source:sub(2)
	return str:match("(.*[/\\])") or "./"
end

local slaxml = require(script_path() .. "libs/slaxdom")
local mypd = require(script_path() .. "libs/mypd")

--╭─────────────────────────────────────╮
--│          Object Definition          │
--╰─────────────────────────────────────╯

local readSvg = pd.Class:new():register("u.readsvg")

function readSvg:initialize(_, _)
	self.inlets = 1
	self.outlets = 1
	self.objects = {}
	self.clock = pd.Clock:new():register(self, "player")
	self.outletId = tostring(self._object):match("userdata: (0x[%x]+)")
	self.lastonset = 0
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
local function parseStyle(node, styleString)
	for pair in string.gmatch(styleString, "([^;]+)") do
		local key, value = string.match(pair, "([^:]+):(.+)")
		if key and value then
			node[key] = value
		end
	end
end

-- ─────────────────────────────────────
local function getObjectCoords(object)
	if object.name == "rect" then
		local objWidth = tonumber(object.attr.width) or 0
		local objHeight = tonumber(object.attr.height) or 0
		local objX = tonumber(object.attr.x) or 0
		local objY = tonumber(object.attr.y) or 0
		return objWidth, objHeight, objX, objY
	elseif object.name == "ellipse" then
		local objWidth = tonumber(object.attr.rx) or 0
		local objHeight = tonumber(object.attr.ry) or 0
		local objX = tonumber(object.attr.cx) or 0
		local objY = tonumber(object.attr.cy) or 0
		object.attr.width = objWidth
		object.attr.height = objHeight
		object.attr.x = objX
		object.attr.y = objY
		return objWidth, objHeight, objX, objY
	end
end

-- ─────────────────────────────────────
local function objIsInside(system, object)
	local sysWidth = tonumber(system.attr.width) or 0
	local sysHeight = tonumber(system.attr.height) or 0
	local sysX = tonumber(system.attr.x) or 0
	local sysY = tonumber(system.attr.y) or 0
	local objWidth, objHeight, objX, objY = getObjectCoords(object)

	if object.name == "rect" then
		if
			objX >= sysX
			and objX + objWidth <= sysX + sysWidth
			and objY >= sysY
			and objY + objHeight <= sysY + sysHeight
		then
			return true
		else
			return false
		end
	elseif object.name == "ellipse" then
		-- Check if ellipse is fully inside the system
		if
			objX - objWidth >= sysX
			and objX + objWidth <= sysX + sysWidth
			and objY - objHeight >= sysY
			and objY + objHeight <= sysY + sysHeight
		then
			return true
		else
			return false
		end
	end
end

-- ─────────────────────────────────────
local function getObjDuration(system, obj)
	local duration = obj.attr.width * system.attr.duration / system.attr.width
	obj.duration = duration
	return duration
end

-- ─────────────────────────────────────
local function getObjOnset(system, obj)
	local onset = system.attr.start + (system.attr.duration * obj.attr.x / system.attr.width)
	obj.onset = onset
	return onset
end

-- ─────────────────────────────────────
local function cubicBezier(start, control1, control2, endPoint, numPoints)
	numPoints = numPoints or 100
	local points = {}

	for i = 0, numPoints do
		local t = i / numPoints
		local x = (1 - t) ^ 3 * start[1]
			+ 3 * (1 - t) ^ 2 * t * control1[1]
			+ 3 * (1 - t) * t ^ 2 * control2[1]
			+ t ^ 3 * endPoint[1]
		local y = (1 - t) ^ 3 * start[2]
			+ 3 * (1 - t) ^ 2 * t * control1[2]
			+ 3 * (1 - t) * t ^ 2 * control2[2]
			+ t ^ 3 * endPoint[2]
		table.insert(points, { tonumber(x), tonumber(y) })
	end

	return points
end

-- ─────────────────────────────────────
local function parseSvgPath(svgPath)
	local commands = {}
	local currentPosition = { 0, 0 }

	-- Split the path into commands and parameters
	for cmd, params in svgPath:gmatch("([mc])%s*([^mc]+)") do
		local points = {}
		for x, y in params:gmatch("([%d%.%-]+),([%d%.%-]+)") do
			table.insert(points, { tonumber(x), tonumber(y) })
		end
		table.insert(commands, { cmd = cmd, points = points })
	end

	-- Generate Bézier points
	local generatedPoints = {}
	for _, command in ipairs(commands) do
		if command.cmd == "m" then
			-- Update current position (move command)
			currentPosition[1] = currentPosition[1] + command.points[1][1]
			currentPosition[2] = currentPosition[2] + command.points[1][2]
		elseif command.cmd == "c" then
			for i = 1, #command.points, 3 do
				local control1 = {
					currentPosition[1] + command.points[i][1],
					currentPosition[2] + command.points[i][2],
				}
				local control2 = {
					currentPosition[1] + command.points[i + 1][1],
					currentPosition[2] + command.points[i + 1][2],
				}
				local endPoint = {
					currentPosition[1] + command.points[i + 2][1],
					currentPosition[2] + command.points[i + 2][2],
				}

				-- Generate Bézier curve points
				local bezierPoints = cubicBezier(currentPosition, control1, control2, endPoint, 50)
				for _, point in ipairs(bezierPoints) do
					table.insert(generatedPoints, point)
				end

				-- Update current position
				currentPosition = endPoint
			end
		end
	end

	return generatedPoints
end

-- ─────────────────────────────────────
local function getPathOnset(system, obj)
	assert(obj.name == "path")
	local d = obj.attr.d
	local points = parseSvgPath(d)
	obj.points = points
	local onset = system.attr.start + (system.attr.duration * points[1][1] / system.attr.width)
	return onset
end

-- ─────────────────────────────────────
local function pathIsInside(system, obj)
	local points = obj.points
	for _, point in ipairs(points) do
		if point[1] < tonumber(system.attr.x) or point[1] > tonumber(system.attr.x) + tonumber(system.attr.width) then
			return false
		end
		if point[2] < tonumber(system.attr.y) or point[2] > tonumber(system.attr.y) + tonumber(system.attr.height) then
			return false
		end
	end
	return true
end

-- ─────────────────────────────────────
local function getSystemDesc(system)
	local function parseToTable(input)
		for key, value in input:gmatch("(%w+)%s+([^,]+)") do
			if value:find("%s") then
				local values = {}
				for num in value:gmatch("%S+") do
					table.insert(values, tonumber(num) or num)
				end
				system.attr[key] = values
			else
				system.attr[key] = tonumber(value) or value
			end
		end
	end

	for _, node in ipairs(system.kids) do
		if node.type == "element" and node.name == "desc" then
			return parseToTable(node.kids[1].value)
		end
	end
end

--╭─────────────────────────────────────╮
--│               Methods               │
--╰─────────────────────────────────────╯
function readSvg:in_1_read(x)
	self.objects = {}
	self.lastonset = 0
	local svgfile = x[1]

	local f = io.open(svgfile, "r")
	if f == nil then
		svgfile = self._canvaspath .. svgfile
	end
	f = io.open(svgfile, "r")
	if f == nil then
		self:error("[readsvg] File not found!")
		return
	end
	local file = io.open(svgfile, "r")
	if file == nil then
		self:error("[readsvg] Error opening file!")
		return
	end

	-- read
	local xml = file:read("*all")
	local ok = file:close()
	if not ok then
		self:error("[readsvg] Error closing file!")
		return
	end

	-- parse
	local doc = slaxml:dom(xml)
	local goodelem = { rect = true, ellipse = true, path = true }
	local objs = {}

	local function traverse(node)
		if node.type == "element" then
			if goodelem[node.name] then
				table.insert(objs, node)
			end
		end

		if node.kids then
			for _, child in ipairs(node.kids) do
				traverse(child)
			end
		end
	end
	traverse(doc.root)

	for _, node in ipairs(objs) do
		parseStyle(node, node.attr.style)
	end

	local systems = {}
	local objects = {}

	for _, node in ipairs(objs) do
		if node.name == "rect" and node.stroke == "#000000" and node.fill == "none" then
			table.insert(systems, node)
		else
			table.insert(objects, node)
		end
	end

	for _, system in ipairs(systems) do
		getSystemDesc(system)
		if not system.attr.start or not system.attr.duration then
			self:error("[readsvg] System description is missing!")
			return
		end

		system.objs = {}
		for _, object in ipairs(objects) do
			if objIsInside(system, object) then
				object.attr.duration = getObjDuration(system, object)
				object.attr.onset = getObjOnset(system, object)
				object.attr.system = system
				local onset = round(object.attr.onset)
				if onset > self.lastonset then
					self.lastonset = onset
				end
				if self.objects[onset] == nil then
					self.objects[onset] = {}
				end

				table.insert(system.objs, object)
				table.insert(self.objects[onset], object)
			elseif object.name == "path" then
				local onset = round(getPathOnset(system, object))
				if pathIsInside(system, object) then
					if self.objects[onset] == nil then
						self.objects[onset] = {}
					end
					if onset > self.lastonset then
						self.lastonset = onset
					end
					object.attr.system = system
					object.attr.onset = onset
					table.insert(system.objs, object)
					table.insert(self.objects[onset], object)
				end
			end
		end
	end
end

-- ─────────────────────────────────────
function readSvg:in_1_play(args)
	local start = 0
	if type(args[1]) == "number" then
		start = round(args[1])
	end
	self.start = start
	self:player()
end

-- ─────────────────────────────────────
function readSvg:in_1_pause()
	self.clock:unset()
end

-- ─────────────────────────────────────
function readSvg:player()
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
	else
		self.start = self.start + 1
		self.clock:delay(1)
	end
end

-- ─────────────────────────────────────
function readSvg:in_1_reload()
	self:dofilex(self._scriptname)
end

-- ─────────────────────────────────────
function readSvg:finalize()
	pd[self.outletId] = nil
end
