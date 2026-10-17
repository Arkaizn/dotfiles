-- Prints Hyprland's keybinds as JSON, for the keybind cheatsheet
-- (services/Keybinds.qml).
--
--   lua hypr-binds.lua ~/.config/hypr/hyprland.lua
--
-- With the Lua config, `hyprctl binds` can't say what a bind does (every
-- action is an opaque Lua function), so this runs the config itself against
-- a stand-in `hl` table that only records hl.bind calls. Loops, variables and
-- dofile work exactly like in Hyprland; everything else hl.* does nothing.
-- Commands are never run: os.execute / io.popen / hl.exec_cmd are disabled.
--
-- Output: [{ "keys": "SUPER + C", "dsp": "window.close", "args": [...],
--            "description": "...", "submap": "", "mouse": false }, ...]

local binds = {}
local submap = ""

-- hl.dsp.window.close({ ... }) → { dsp = "window.close", args = { ... } }
local function dispatcherTable(path)
    return setmetatable({}, {
        __index = function(_, k) return dispatcherTable(path == "" and k or path .. "." .. k) end,
        __call = function(_, ...) return { dsp = path, args = { ... } } end,
    })
end

-- anything else: a callable no-op that also allows indexing (hl.foo.bar())
local noop
noop = setmetatable({}, {
    __index = function() return noop end,
    __call = function() return nil end,
})

hl = setmetatable({
    dsp = dispatcherTable(""),
    bind = function(keys, action, opts)
        opts = type(opts) == "table" and opts or {}
        local entry = { keys = tostring(keys), submap = submap, mouse = opts.mouse == true,
                        description = opts.description }
        if type(action) == "table" and action.dsp then
            entry.dsp, entry.args = action.dsp, action.args
        else
            entry.dsp, entry.args = "lua", {}
        end
        binds[#binds + 1] = entry
        return noop
    end,
    define_submap = function(name, fn)
        local prev = submap
        submap = name
        if type(fn) == "function" then pcall(fn) end
        submap = prev
    end,
}, { __index = function() return noop end })

os.execute = function() return nil end
io.popen = function() return nil end

-- ── JSON ─────────────────────────────────────────────────────────────────────
local function esc(s)
    return '"' .. tostring(s):gsub('[%c"\\]', function(c)
        if c == '"' then return '\\"' elseif c == "\\" then return "\\\\"
        elseif c == "\n" then return "\\n" elseif c == "\t" then return "\\t"
        else return string.format("\\u%04x", c:byte()) end
    end) .. '"'
end

local function json(v)
    local t = type(v)
    if t == "nil" then return "null"
    elseif t == "boolean" then return tostring(v)
    elseif t == "number" then
        if v ~= v or v == math.huge or v == -math.huge then return "null" end
        return math.type and math.type(v) == "integer" and string.format("%d", v) or tostring(v)
    elseif t == "string" then return esc(v)
    elseif t == "table" then
        if #v > 0 or next(v) == nil then
            local out = {}
            for i = 1, #v do out[i] = json(v[i]) end
            return "[" .. table.concat(out, ",") .. "]"
        end
        local out = {}
        for k, x in pairs(v) do out[#out + 1] = esc(k) .. ":" .. json(x) end
        table.sort(out)
        return "{" .. table.concat(out, ",") .. "}"
    else return esc(tostring(v)) end
end

-- ── Run ──────────────────────────────────────────────────────────────────────
local ok, err = pcall(dofile, arg[1])
if not ok then io.stderr:write(tostring(err), "\n") end
io.write(json(binds), "\n")
os.exit(ok and 0 or 2)
