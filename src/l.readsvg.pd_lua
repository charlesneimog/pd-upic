local function script_path()
	local str = debug.getinfo(2, "S").source:sub(2)
	return str:match("(.*[/\\])") or "./"
end

local slaxml = require(script_path() .. "SLAXML/slaxdom")
local mypd = require(script_path() .. "SLAXML/mypd")

--╭─────────────────────────────────────╮
--│          Object Definition          │
--╰─────────────────────────────────────╯

local readSvg = pd.Class:new():register("l.readsvg")

function readSvg:initialize(name, sel)
	self.inlets = 1
	self.outlets = 1
	self.objects = {}
	self.objects_count = 0
	self.clock = pd.Clock:new():register(self, "player")
	self.outletId = mypd.random_string(8)
	self.lastonset = 0
	self.onset = 0
	self.span = 5000
	-- self:set_size(400, 100)

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
function readSvg:get_path_width(path)
	local d = path.d
	if not d then
		self:error("[u.readsvg] Path" .. " not valid")
		return nil
	end

	local min_x, max_x = nil, nil

	for x_str, _ in string.gmatch(d, "([%-%.%d]+),([%-%.%d]+)") do
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
		object.attr.x = objX
		object.attr.y = objY
		object.attr.width = objWidth
		object.attr.height = objHeight
		return objWidth, objHeight, objX, objY
	elseif object.name == "ellipse" or object.name == "circle" then
		-- NOTE: me parece que em circulos o x e y fica no meio, aqui corrigimos para ser o inicio
		local objWidth, objHeight, objX, objY = self:applyTransformation(object)
		object.attr.x = objX
		object.attr.y = objY
		object.attr.startx = objX - objWidth / 2
		object.attr.starty = objY - objHeight / 2
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
			object.attr.height = 0
			return 0, 0, x, y
		end
		self:error("[u.readsvg] not valid path")
	else
		self:error("[u.readsvg] " .. object.name .. " not implemented")
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
	local onset = system.attr.onset + ((obj.attr.x - system.attr.x) / system.attr.width) * system.attr.duration
	obj.attr.onset = onset
	if obj.attr.name == "ellipse" or obj.attr.name == "circle" then
		local startonset = system.attr.onset
			+ ((obj.attr.startx - system.attr.x) / system.attr.width) * system.attr.duration
		obj.attr.startonset = startonset
	end

	return onset
end

-- ─────────────────────────────────────
function readSvg:cubicBezier(onset, control1, control2, endPoint, numPoints)
	numPoints = numPoints or 100
	local points = {}

	if numPoints > 10000 then
		self:error("[u.readsvg] Very long path, avoid this please! I will try to process the path...")
	end

	for i = 0, numPoints do
		local t = i / numPoints
		local x = (1 - t) ^ 3 * onset[1]
			+ 3 * (1 - t) ^ 2 * t * control1[1]
			+ 3 * (1 - t) * t ^ 2 * control2[1]
			+ t ^ 3 * endPoint[1]
		local y = (1 - t) ^ 3 * onset[2]
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
	local onset = system.attr.onset + ((points[1][1] - system.attr.x) / system.attr.width) * system.attr.duration
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
function readSvg:getObjDesc(system)
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

-- ─────────────────────────────────────
function readSvg:nestedObjects(objects, mainsystem)
	local function nest(parentList)
		for i = #parentList, 1, -1 do -- reverse loop for safe removal
			local parent = parentList[i]
			if parent ~= nil then
				parent.attr.childs = {}
				for j = #objects, 1, -1 do
					local child = objects[j]
					if child ~= parent and child.name ~= "path" and self:objIsInside(parent, child) then
						child.attr.name = child.name
						child.attr.mainsystem = mainsystem
						child.attr.system = parent
						child.attr.onset = child.attr.onset - parent.attr.onset
						child.attr.duration = self:getObjDuration(mainsystem, child)
						child.attr.rely = 1 - ((child.attr.y - parent.attr.y) / parent.attr.height)
						child.attr.relx = (child.attr.x - parent.attr.x) / parent.attr.width
						child.attr.relwidth = child.attr.width / parent.attr.width
						child.attr.relheight = child.attr.height / parent.attr.height
						table.insert(parent.attr.childs, child)
						table.remove(objects, j)
					elseif child ~= parent and child.name == "path" and self:pathIsInside(parent, child) then
						child.attr.size = child["stroke-width"]
						child.attr.name = "path"
						child.attr.mainsystem = mainsystem
						child.attr.system = parent
						child.attr.onset = child.attr.onset - parent.attr.onset
						child.attr.duration = self:getObjDuration(mainsystem, child)
						child.attr.rely = 1 - ((child.attr.y - parent.attr.y) / parent.attr.height)
						child.attr.relx = (child.attr.x - parent.attr.x) / parent.attr.width
						table.insert(parent.attr.childs, child)
						table.remove(objects, j)
					end
				end
				if #parent.attr.childs > 0 then
					nest(parent.attr.childs) -- recurse
				else
					parent.attr.childs = nil -- remove empty table
				end
			end
		end
	end
	nest(objects)
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

	pd.post("[u.readsvg] Reading SVG file: " .. svgfile)

	-- open svg file
	f = io.open(svgfile, "r")
	if f == nil then
		self:error("[u.readsvg] File not found!")
		return
	end
	local file = io.open(svgfile, "r")
	if file == nil then
		self:error("[u.readsvg] Error opening file!")
		return
	end

	--╭─────────────────────────────────────╮
	--│            read svg file            │
	--╰─────────────────────────────────────╯
	local xml = file:read("*all")
	local ok = file:close()
	if not ok then
		self:error("[u.readsvg] Error closing file!")
		return
	end
	local doc = slaxml:dom(xml)
	local goodelem = { rect = true, circle = true, ellipse = true, path = true }
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

	-- parse itens style
	for _, node in ipairs(objs) do
		self:parseStyle(node, node.attr.style)
	end

	local systems = {}
	local objects = {}

	-- get all systems
	local systemCount = 0
	for _, node in ipairs(objs) do
		if node.name == "rect" and node.attr.stroke == "#000000" and node.attr.fill == "none" then
			for key, value in pairs(node.attr) do
				local num = tonumber(value)
				if num then
					node.attr[key] = num
				end
			end
			table.insert(systems, node)
			systemCount = systemCount + 1
		else
			table.insert(objects, node)
		end
	end

	-- get all systems
	for _, system in ipairs(systems) do
		self:getObjDesc(system)
		if not system.attr.onset or not system.attr.duration then
			self:error("[u.readsvg] System description parameters onset or duration is missing!")
			return
		end

		system.objs = {}
		local remaining = {}

		for _, object in ipairs(objects) do
			if self:objIsInside(system, object) and object.name ~= "path" then
				object.attr.name = object.name
				object.attr.duration = self:getObjDuration(system, object)
				object.attr.onset = self:getObjOnset(system, object)
				object.attr.rely = 1 - ((object.attr.y - system.attr.y) / system.attr.height)
				object.attr.relx = (object.attr.x - system.attr.x) / system.attr.width
				object.attr.system = system
				pd.post(object.attr.rely)
				local onset = self:round(object.attr.onset)
				if onset > self.lastonset then
					self.lastonset = onset
				end
				self:getObjDesc(object)
				table.insert(remaining, object)
			end

			if object.name == "path" then
				self:getObjDesc(object)
				local onset = self:round(self:getPathOnset(system, object))
				if self:pathIsInside(system, object) then
					if onset > self.lastonset then
						self.lastonset = onset
					end
					object.attr.system = system
					object.attr.onset = onset
					table.insert(remaining, object)
				end
			end
		end

		self:nestedObjects(remaining, system)
		for _, v in ipairs(remaining) do
			local onset = self:round(v.attr.onset)
			if self.objects[onset] == nil then
				self.objects[onset] = {}
			end
			table.insert(self.objects[onset], v)
			self.objects_count = self.objects_count + 1
		end
	end

	if self.objects_count == 0 then
		self:error("[u.readsvg] No objects found!")
		return
	end
	pd.post("[u.readsvg] Found " .. self.objects_count .. " objects\n")
	self:repaint()
end

-- ─────────────────────────────────────
function readSvg:in_1_play(args)
	local onset = 0
	if type(args[1]) == "number" then
		onset = self:round(args[1])
	end
	self.onset = onset
	if self.objects_count == 0 then
		self:error("[u.readsvg] No objects found!")
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
	else
		self.onset = self.onset + 1
		self.clock:delay(1)
		if self.onset % 30 == 0 then
			self:repaint(2)
		end
	end
end

-- ─────────────────────────────────────
function readSvg:in_1_reload()
	self:dofilex(self._scriptname)
	self:initialize()
end

-- ─────────────────────────────────────
function readSvg:finalize()
	pd[self.outletId] = nil
end

--╭─────────────────────────────────────╮
--│                PAINT                │
--╰─────────────────────────────────────╯
local function hex_to_rgba(hex)
	if not hex or type(hex) ~= "string" then
		return 0, 0, 0, 1
	end

	hex = hex:gsub("#", "")

	if #hex == 3 then
		local r = tonumber(hex:sub(1, 1) .. hex:sub(1, 1), 16)
		local g = tonumber(hex:sub(2, 2) .. hex:sub(2, 2), 16)
		local b = tonumber(hex:sub(3, 3) .. hex:sub(3, 3), 16)
		return r, g, b, 255
	elseif #hex == 6 then
		local r = tonumber(hex:sub(1, 2), 16)
		local g = tonumber(hex:sub(3, 4), 16)
		local b = tonumber(hex:sub(5, 6), 16)
		return r, g, b, 255
	elseif #hex == 8 then
		local r = tonumber(hex:sub(1, 2), 16)
		local g = tonumber(hex:sub(3, 4), 16)
		local b = tonumber(hex:sub(5, 6), 16)
		local a = tonumber(hex:sub(7, 8), 16)
		return r, g, b, a
	end

	return 0, 0, 0, 1
end

-- ─────────────────────────────────────
local function set_style_color(g, color)
	if type(color) == "string" and color:sub(1, 1) == "#" then
		local r, g_, b, a = hex_to_rgba(color)
		g:set_color(r, g_, b, a or 1)
	else
		g:set_color(0, 0, 0, 1)
	end
end

-- ─────────────────────────────────────
-- function readSvg:paint(g)
-- 	local w, h = self:get_size()
--
-- 	local t0 = self.onset
-- 	local t1 = self.onset + self.span
-- 	local time_span = t1 - t0
--
-- 	for onset, objs in pairs(self.objects) do
-- 		if onset >= t0 and onset <= t1 then
-- 			local x = ((onset - t0) / time_span) * w
--
-- 			for _, obj in ipairs(objs) do
-- 				if obj.name == "ellipse" or obj.name == "circle" then
-- 					local y = h * (1 - obj.attr.rely)
-- 					local rx = obj.attr.relx * w
-- 					local ry = obj.attr.rely * h
-- 					set_style_color(g, obj.attr.fill)
-- 					g:fill_ellipse(x - rx, y, rx, ry)
-- 				elseif obj.name == "rect" then
-- 					local sw = obj.attr.system.attr.width
-- 					local sh = obj.attr.system.attr.height
--
-- 					local sx = obj.attr.system.attr.x
-- 					local sy = obj.attr.system.attr.y
-- 					local propw = w / sw
-- 					local proph = h / sh
-- 					local y = h * (1 - obj.attr.rely)
-- 					if obj.attr.fill ~= "none" then
-- 						set_style_color(g, obj.attr.fill)
-- 						g:fill_rect(x, y, obj.attr.width * propw, obj.attr.height * proph)
-- 					elseif obj.attr.stroke ~= "none" then
-- 						set_style_color(g, obj.attr.stroke)
-- 						g:stroke_rect(x, y, obj.attr.width * propw, obj.attr.height * proph, 1)
-- 					end
-- 				elseif obj.name == "path" then
-- 					pd.post("path not implemented")
-- 				end
-- 			end
-- 		end
-- 	end
--
-- 	g:set_color(0, 0, 0)
-- 	g:stroke_rect(0, 0, w, h, 2)
-- end
--
-- -- ─────────────────────────────────────
-- function readSvg:paint_layer_2(g)
-- 	local w, h = self:get_size()
-- 	local pos = self.onset / self.span * w
--
-- 	g:set_color(0, 0, 0)
-- 	g:draw_line(pos, 2, pos, h - 2, 1)
-- end
