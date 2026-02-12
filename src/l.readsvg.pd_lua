--╭─────────────────────────────────────╮
--│          Object Definition          │
--╰─────────────────────────────────────╯
local readSvg = pd.Class:new():register("l.readsvg")

local slaxml = require("SLAXML/slaxdom")
local dddd = require("dddd")

-- ─────────────────────────────────────
function readSvg:initialize(name, sel)
	self.inlets = 1
	self.outlets = 1
	self.objects = {}
	self.objects_count = 0
	self.clock = pd.Clock:new():register(self, "player")
	self.lastonset = 0
	self.onset = 0
	self.span = 5000
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
	if not styleString or type(styleString) ~= "string" then
		return
	end
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
			local x0, y0 = objX, objY
			-- Apply the matrix transformation to the object's position (cx, cy)
			-- Matrix transformation: new_x = a * x + c * y + e, new_y = b * x + d * y + f
			objX = a * x0 + c * y0 + e
			objY = b * x0 + d * y0 + f
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

	local points = self:parseSvgPath(d)
	if not points or #points == 0 then
		self:error("[u.readsvg] Path not valid")
		return nil
	end

	local min_x, max_x = points[1][1], points[1][1]
	for i = 2, #points do
		local x = points[i][1]
		if x < min_x then
			min_x = x
		elseif x > max_x then
			max_x = x
		end
	end
	return max_x - min_x
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
			local points = object.points or self:parseSvgPath(d)
			object.points = points
			if points and #points > 0 then
				local min_x, max_x = points[1][1], points[1][1]
				local min_y, max_y = points[1][2], points[1][2]
				for i = 2, #points do
					local px, py = points[i][1], points[i][2]
					if px < min_x then
						min_x = px
					elseif px > max_x then
						max_x = px
					end
					if py < min_y then
						min_y = py
					elseif py > max_y then
						max_y = py
					end
				end

				object.attr.x = points[1][1]
				object.attr.y = points[1][2]
				object.attr.width = max_x - min_x
				object.attr.height = max_y - min_y
				return object.attr.width, object.attr.height, object.attr.x, object.attr.y
			end
		end
		self:error("[u.readsvg] not valid path")
	else
		self:error("[u.readsvg] " .. object.name .. " not implemented")
	end
end

-- ─────────────────────────────────────
-- SVG path parsing (minimal, practical subset)
-- Supports: M/m, L/l, H/h, V/v, C/c, S/s, Q/q, T/t, Z/z
function readSvg:tokenizeSvgPath(d)
	local tokens = {}
	if not d or type(d) ~= "string" then
		return tokens
	end

	local i = 1
	local n = #d
	while i <= n do
		local ch = d:sub(i, i)
		if ch:match("%s") or ch == "," then
			i = i + 1
		elseif ch:match("[A-Za-z]") then
			table.insert(tokens, ch)
			i = i + 1
		elseif ch == "-" or ch == "+" or ch == "." or ch:match("%d") then
			local start_i = i
			local s = ""

			if ch == "-" or ch == "+" then
				s = s .. ch
				i = i + 1
				ch = d:sub(i, i)
			end

			while i <= n and d:sub(i, i):match("%d") do
				s = s .. d:sub(i, i)
				i = i + 1
			end

			if i <= n and d:sub(i, i) == "." then
				s = s .. "."
				i = i + 1
				while i <= n and d:sub(i, i):match("%d") do
					s = s .. d:sub(i, i)
					i = i + 1
				end
			end

			if i <= n and (d:sub(i, i) == "e" or d:sub(i, i) == "E") then
				local exp_mark = d:sub(i, i)
				i = i + 1
				local exp_sign = ""
				if i <= n and (d:sub(i, i) == "-" or d:sub(i, i) == "+") then
					exp_sign = d:sub(i, i)
					i = i + 1
				end
				local exp_digits = ""
				while i <= n and d:sub(i, i):match("%d") do
					exp_digits = exp_digits .. d:sub(i, i)
					i = i + 1
				end
				if exp_digits ~= "" then
					s = s .. exp_mark .. exp_sign .. exp_digits
				end
			end

			local num = tonumber(s)
			if num ~= nil then
				table.insert(tokens, num)
			else
				-- fail-safe: avoid infinite loop
				i = start_i + 1
			end
		else
			i = i + 1
		end
	end

	return tokens
end

-- ─────────────────────────────────────
function readSvg:quadraticBezier(p0, p1, p2, numPoints)
	numPoints = numPoints or 50
	local points = {}
	for i = 0, numPoints do
		local t = i / numPoints
		local mt = 1 - t
		local x = mt * mt * p0[1] + 2 * mt * t * p1[1] + t * t * p2[1]
		local y = mt * mt * p0[2] + 2 * mt * t * p1[2] + t * t * p2[2]
		table.insert(points, { tonumber(x), tonumber(y) })
	end
	return points
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
	local tokens = self:tokenizeSvgPath(svgPath)
	if #tokens == 0 then
		return {}
	end

	local points = {}
	local i = 1
	local cmd = nil
	local cx, cy = 0, 0
	local sx, sy = 0, 0
	local last_c2x, last_c2y = nil, nil
	local last_qcx, last_qcy = nil, nil

	local function add_point(x, y)
		table.insert(points, { x, y })
	end

	local function is_cmd(tok)
		return type(tok) == "string" and tok:match("^[A-Za-z]$") ~= nil
	end

	local function peek()
		return tokens[i]
	end

	local function next_number()
		local tok = tokens[i]
		if type(tok) ~= "number" then
			return nil
		end
		i = i + 1
		return tok
	end

	local function line_to(x, y)
		cx, cy = x, y
		add_point(cx, cy)
		last_c2x, last_c2y = nil, nil
		last_qcx, last_qcy = nil, nil
	end

	local function cubic_to(x1, y1, x2, y2, x, y)
		local bez = self:cubicBezier({ cx, cy }, { x1, y1 }, { x2, y2 }, { x, y }, 50)
		for j = 2, #bez do
			add_point(bez[j][1], bez[j][2])
		end
		cx, cy = x, y
		last_c2x, last_c2y = x2, y2
		last_qcx, last_qcy = nil, nil
	end

	local function quad_to(x1, y1, x, y)
		local bez = self:quadraticBezier({ cx, cy }, { x1, y1 }, { x, y }, 50)
		for j = 2, #bez do
			add_point(bez[j][1], bez[j][2])
		end
		cx, cy = x, y
		last_qcx, last_qcy = x1, y1
		last_c2x, last_c2y = nil, nil
	end

	while i <= #tokens do
		if is_cmd(peek()) then
			cmd = peek()
			i = i + 1
		elseif cmd == nil then
			-- invalid path
			break
		end

		local lower = cmd:lower()
		local rel = (cmd == lower)

		if lower == "m" then
			local x = next_number()
			local y = next_number()
			if x == nil or y == nil then
				break
			end
			if rel then
				x, y = cx + x, cy + y
			end
			cx, cy = x, y
			sx, sy = x, y
			add_point(cx, cy)
			last_c2x, last_c2y = nil, nil
			last_qcx, last_qcy = nil, nil

			-- Subsequent pairs are treated as implicit lineto
			while type(peek()) == "number" do
				local lx = next_number()
				local ly = next_number()
				if lx == nil or ly == nil then
					break
				end
				if rel then
					lx, ly = cx + lx, cy + ly
				end
				line_to(lx, ly)
			end
		elseif lower == "l" then
			while true do
				local x = next_number()
				local y = next_number()
				if x == nil or y == nil then
					break
				end
				if rel then
					x, y = cx + x, cy + y
				end
				line_to(x, y)
			end
		elseif lower == "h" then
			while true do
				local x = next_number()
				if x == nil then
					break
				end
				if rel then
					x = cx + x
				end
				line_to(x, cy)
			end
		elseif lower == "v" then
			while true do
				local y = next_number()
				if y == nil then
					break
				end
				if rel then
					y = cy + y
				end
				line_to(cx, y)
			end
		elseif lower == "c" then
			while true do
				local x1 = next_number()
				local y1 = next_number()
				local x2 = next_number()
				local y2 = next_number()
				local x = next_number()
				local y = next_number()
				if x1 == nil or y1 == nil or x2 == nil or y2 == nil or x == nil or y == nil then
					break
				end
				if rel then
					x1, y1 = cx + x1, cy + y1
					x2, y2 = cx + x2, cy + y2
					x, y = cx + x, cy + y
				end
				cubic_to(x1, y1, x2, y2, x, y)
			end
		elseif lower == "s" then
			while true do
				local x2 = next_number()
				local y2 = next_number()
				local x = next_number()
				local y = next_number()
				if x2 == nil or y2 == nil or x == nil or y == nil then
					break
				end
				local x1, y1
				if last_c2x ~= nil and last_c2y ~= nil then
					x1 = 2 * cx - last_c2x
					y1 = 2 * cy - last_c2y
				else
					x1, y1 = cx, cy
				end
				if rel then
					x2, y2 = cx + x2, cy + y2
					x, y = cx + x, cy + y
				end
				cubic_to(x1, y1, x2, y2, x, y)
			end
		elseif lower == "q" then
			while true do
				local x1 = next_number()
				local y1 = next_number()
				local x = next_number()
				local y = next_number()
				if x1 == nil or y1 == nil or x == nil or y == nil then
					break
				end
				if rel then
					x1, y1 = cx + x1, cy + y1
					x, y = cx + x, cy + y
				end
				quad_to(x1, y1, x, y)
			end
		elseif lower == "t" then
			while true do
				local x = next_number()
				local y = next_number()
				if x == nil or y == nil then
					break
				end
				local x1, y1
				if last_qcx ~= nil and last_qcy ~= nil then
					x1 = 2 * cx - last_qcx
					y1 = 2 * cy - last_qcy
				else
					x1, y1 = cx, cy
				end
				if rel then
					x, y = cx + x, cy + y
				end
				quad_to(x1, y1, x, y)
			end
		elseif lower == "z" then
			line_to(sx, sy)
		else
			-- Unsupported command (A/a etc). Skip numbers until next command.
			while type(peek()) == "number" do
				i = i + 1
			end
		end
	end

	return points
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
						child.attr.size = child.attr["stroke-width"]
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
				-- pd.post(object.attr.rely)
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
            if object[1].attr == nil then
                error("Invalid objects")
            end
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
