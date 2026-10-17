-- Prints Hyprland's keybinds (and login autostart commands) as JSON, for the
-- keybind cheatsheet and the settings app (services/Keybinds.qml).
--
--   lua hypr-binds.lua ~/.config/hypr/hyprland.lua
--
-- With the Lua config, `hyprctl binds` can't say what a bind does (every
-- action is an opaque Lua function), so this runs the config itself against
-- a stand-in `hl` table that only records hl.bind calls. Loops, variables and
-- dofile work exactly like in Hyprland; everything else hl.* does nothing.
-- Commands are never run: os.execute / io.popen / hl.exec_cmd are disabled.
--
-- Output: { "binds": [{ "keys": "SUPER + C", "dsp": "window.close", "args": [...],
--             "description": "...", "submap": "", "mouse": false,
--             "opts": { locked = … }, "file": "/path/of/the/file.lua" }, ...],
--           "autostart": [{ "cmd": "...", "file": "...", "line": n }],
--           "rules": [{ "kind": "window rule", "file": "...", "line": n }] }
-- hl.unbind removes earlier binds with the same keys, like in Hyprland.

local binds = {}
local autostart = {}
local submap = ""
local inStart = false            -- inside an hl.on("hyprland.start", …) handler

-- "SUPER + SHIFT + c" and "super+shift+C" are the same bind
local function norm(keys) return (tostring(keys):gsub("%s", ""):upper()) end
local function caller() local i = debug.getinfo(3, "S"); return i and i.source:gsub("^@", "") or "" end
local function callerLine() local i = debug.getinfo(3, "l"); return i and i.currentline or 0 end
local rules = {}                 -- window / workspace / layer rules: { kind, file, line } (import page)
local function rule(kind) return function() rules[#rules + 1] = { kind = kind, file = caller(), line = callerLine() }; return noop end end

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
        local rest = {}
        for k, v in pairs(opts) do if k ~= "description" and type(v) ~= "function" then rest[k] = v end end
        local entry = { keys = tostring(keys), submap = submap, mouse = opts.mouse == true,
                        description = opts.description, opts = rest, file = caller(), line = callerLine() }
        if type(action) == "table" and action.dsp then
            entry.dsp, entry.args = action.dsp, action.args
        else
            entry.dsp, entry.args = "lua", {}
        end
        binds[#binds + 1] = entry
        return noop
    end,
    unbind = function(keys)
        local n = norm(keys)
        for i = #binds, 1, -1 do if norm(binds[i].keys) == n and binds[i].submap == submap then table.remove(binds, i) end end
    end,
    on = function(event, fn)
        if event == "hyprland.start" and type(fn) == "function" then
            inStart = true
            pcall(fn)
            inStart = false
        end
        return noop
    end,
    exec_cmd = function(cmd)
        if inStart then autostart[#autostart + 1] = { cmd = tostring(cmd), file = caller(), line = callerLine() } end
    end,
    window_rule = rule("window rule"),
    workspace_rule = rule("workspace rule"),
    layer_rule = rule("layer rule"),
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
io.write("{\"binds\":", json(binds), ",\"autostart\":", json(autostart), ",\"rules\":", json(rules), "}\n")
os.exit(ok and 0 or 2)
