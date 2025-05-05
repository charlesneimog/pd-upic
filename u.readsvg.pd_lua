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
	self.objects_count = 0
	self.clock = pd.Clock:new():register(self, "player")
	self.outletId = tostring(self._object):match("userdata: (0x[%x]+)")
	self.lastonset = 0
	return true
end

--╭─────────────────────────────────────╮
--│               Helpers               │
--╰─────────────────────────────────────╯
function readSvg:round(num)
	if num % 1 >= 0.5 then
		return math.ceil(num)
	else
		return math.floor(num)
	end
end

-- ─────────────────────────────────────
function readSvg:parseStyle(node, styleString)
	for pair in string.gmatch(styleString, "([^;]+)") do
		local key, value = string.match(pair, "([^:]+):(.+)")
		if key and value then
			node.attr[key] = value
		end
	end
end

-- ─────────────────────────────────────
function readSvg:extractMatrix(transformString)
	local a, b, c, d, e, f = transformString:match(
		"matrix%((%-?%d+%.?%d*),%s*(%-?%d+%.?%d*),%s*(%-?%d+%.?%d*),%s*(%-?%d+%.?%d*),%s*(%-?%d+%.?%d*),%s*(%-?%d+%.?%d*)%)"
	)
	return tonumber(a), tonumber(b), tonumber(c), tonumber(d), tonumber(e), tonumber(f)
end

-- ─────────────────────────────────────
function readSvg:applyTransformation(object)
	-- Get the center and radius/size values of the object
	local objX = tonumber(object.attr.cx) or 0
	local objY = tonumber(object.attr.cy) or 0
	local objHeight, objWidth

	-- Default to using `r` or `ry`, `rx` to calculate width and height
	object.attr.x = objX
	object.attr.y = objY

	-- Check if the object has a radius `r` or semi-major (`rx`) and semi-minor (`ry`) axes
	if object.attr.r ~= nil then
		objHeight = object.attr.r * 2
		objWidth = object.attr.r * 2
	else
		objHeight = object.attr.ry * 2
		objWidth = object.attr.rx * 2
	end

	-- Check if there is a matrix transform in the object
	if object.attr.transform then
		-- Extract matrix values if transformation exists
		local a, b, c, d, e, f = self:extractMatrix(object.attr.transform)

		-- If a matrix is present, apply the transformation to `objX` and `objY`
		if a and b and c and d and e and f then
			-- Apply the matrix transformation to the object's position (cx, cy)
			-- Matrix transformation: new_x = a * x + c * y + e, new_y = b * x + d * y + f
			objX = a * objX + c * objY + e
			objY = b * objX + d * objY + f
		end
	end

	-- Return the transformed width, height, and position
	return objWidth, objHeight, objX, objY
end

-- ─────────────────────────────────────
local function print_table(tbl)
	local result = "{ "
	for k, v in pairs(tbl) do
		result = result .. "[" .. tostring(k) .. "] = " .. tostring(v) .. ", "
	end
	result = result .. "}"
	return result
end

-- ─────────────────────────────────────
function readSvg:get_path_width(path)
	local d = path.d
	if not d then
		self:error("[u.readsvg] Path" .. " not valid")
		return nil
	end

	local min_x, max_x = nil, nil

	for x_str, y_str in string.gmatch(d, "([%-%.%d]+),([%-%.%d]+)") do
		local x = tonumber(x_str)
		if x then
			if not min_x or x < min_x then
				min_x = x
			end
			if not max_x or x > max_x then
				max_x = x
			end
		end
	end

	if min_x and max_x then
		return max_x - min_x
	else
		self:error("[u.readsvg] Path" .. " not valid")
	end
end

-- ─────────────────────────────────────
function readSvg:getObjectCoords(object)
	if object.name == "rect" then
		local objWidth = tonumber(object.attr.width) or 0
		local objHeight = tonumber(object.attr.height) or 0
		local objX = tonumber(object.attr.x) or 0
		local objY = tonumber(object.attr.y) or 0
		return objWidth, objHeight, objX, objY
	elseif object.name == "ellipse" then
		local objWidth, objHeight, objX, objY = self:applyTransformation(object)
		object.attr.x = objX
		object.attr.y = objY
		object.attr.width = objWidth
		object.attr.height = objHeight
		return objWidth, objHeight, objX, objY
	elseif object.name == "path" then
		local d = object.attr.d
		if d then
			local x, y = string.match(d, "m%s*([%-%.%d]+),([%-%.%d]+)")
			x = tonumber(x)
			y = tonumber(y)
			object.attr.x = x
			object.attr.y = y
			object.attr.width = self:get_path_width(object.attr)
			-- object.points = self:
			return 0, 0, x, y
		end
		pd.post("Not valid path")
	else
		pd.post(object.name .. " not implemented")
	end
end

-- ─────────────────────────────────────
function readSvg:objIsInside(system, object)
	local sysWidth = tonumber(system.attr.width) or 0
	local sysHeight = tonumber(system.attr.height) or 0
	local sysX = tonumber(system.attr.x) or 0
	local sysY = tonumber(system.attr.y) or 0
	local _, _, objX, objY = self:getObjectCoords(object)
	local inside = objX >= sysX and objX <= sysX + sysWidth and objY >= sysY and objY <= sysY + sysHeight
	return inside
end

-- ─────────────────────────────────────
function readSvg:getObjDuration(system, obj)
	local duration = obj.attr.width * system.attr.duration / system.attr.width
	obj.attr.duration = duration
	return duration
end

-- ─────────────────────────────────────
function readSvg:getObjOnset(system, obj)
	local onset = system.attr.start + (system.attr.duration * obj.attr.x / system.attr.width)
	obj.attr.onset = onset
	return onset
end

-- ─────────────────────────────────────
function readSvg:cubicBezier(start, control1, control2, endPoint, numPoints)
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
function readSvg:parseSvgPath(svgPath)
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
				local bezierPoints = self:cubicBezier(currentPosition, control1, control2, endPoint, 50)
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
function readSvg:getPathOnset(system, obj)
	assert(obj.name == "path")
	local d = obj.attr.d
	local points = self:parseSvgPath(d)
	obj.points = points
	local onset = system.attr.start + (system.attr.duration * points[1][1] / system.attr.width)
	return onset
end

-- ─────────────────────────────────────
function readSvg:pathIsInside(system, obj)
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
function readSvg:getSystemDesc(system)
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
	self.objects_count = 0
	self.lastonset = 0
	local svgfile = x[1]

	local f = io.open(svgfile, "r")
	if f == nil then
		svgfile = self._canvaspath .. svgfile
	end

	pd.post("[readsvg] Reading SVG file: " .. svgfile)

	-- open svg file
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

	-- read svg file
	local xml = file:read("*all")
	local ok = file:close()
	if not ok then
		self:error("[readsvg] Error closing file!")
		return
	end

	-- parse svg file
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
		self:parseStyle(node, node.attr.style)
	end

	local systems = {}
	local objects = {}

	local systemCount = 0
	for _, node in ipairs(objs) do
		if node.name == "rect" and node.attr.stroke == "#000000" and node.attr.fill == "none" then
			table.insert(systems, node)
			systemCount = systemCount + 1
		else
			table.insert(objects, node)
		end
	end

	for _, system in ipairs(systems) do
		self:getSystemDesc(system)
		if not system.attr.start or not system.attr.duration then
			self:error("[readsvg] System description is missing!")
			return
		end

		for key, value in pairs(system.attr) do
			local num = tonumber(value)
			if num then
				system.attr[key] = num
			end
		end

		system.objs = {}
		for _, object in ipairs(objects) do
			if self:objIsInside(system, object) and object.name ~= "path" then
				object.attr.duration = self:getObjDuration(system, object)
				object.attr.onset = self:getObjOnset(system, object)
				object.attr.rely = 1 - ((object.attr.y - system.attr.y) / system.attr.height)
				object.attr.relx = (object.attr.x - system.attr.x) / system.attr.width

				object.attr.system = system

				local onset = self:round(object.attr.onset)
				if onset > self.lastonset then
					self.lastonset = onset
				end
				if self.objects[onset] == nil then
					self.objects[onset] = {}
				end

				table.insert(system.objs, object)
				table.insert(self.objects[onset], object)
				self.objects_count = self.objects_count + 1
			end

			if object.name == "path" then
				local onset = self:round(self:getPathOnset(system, object))
				if self:pathIsInside(system, object) then
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
					self.objects_count = self.objects_count + 1
				end
			end
		end
	end

	if self.objects_count == 0 then
		self:error("[readsvg] No objects found!")
		return
	end
	pd.post("[readsvg] There are " .. self.objects_count .. " objects found")
end

-- ─────────────────────────────────────
function readSvg:in_1_play(args)
	local start = 0
	if type(args[1]) == "number" then
		start = self:round(args[1])
	end
	self.start = start
	if self.objects_count == 0 then
		self:error("[readsvg] No objects found!")
		return
	end

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
