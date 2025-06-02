local function script_path()
	local str = debug.getinfo(2, "S").source:sub(2)
	return str:match("(.*[/\\])") or "./"
end
local mypd = require(script_path() .. "/libs/mypd")

--╭─────────────────────────────────────╮
--│          Object Definition          │
--╰─────────────────────────────────────╯

local attrPrint = pd.Class:new():register("l.attrprint")

-- ─────────────────────────────────────
function attrPrint:initialize(_, argv)
	self.inlets = 1
	return true
end

-- ─────────────────────────────────────
local function attrprint(k, v)
    -- check if v is table
    if type(v) == "table" then
        for index, value in ipairs(v) do
            attrprint(index, value)
        end
    else
        pd.post(k .. ": " .. v)
    end

end
-- ─────────────────────────────────────
function attrPrint:in_1_SvgObj(x)
	local obj = pd[x[1]]
    pd.post("-----")
    for k, v in pairs(obj.attr) do
        attrprint(k,v)
    end
end
