local home = os.getenv("HOME")
local dots = home .. "/.config/hypr/hyprland/"

-- Pywal
dofile( home .. "/.cache/wal/colors.lua")

-- Hyprland
dofile(dots .. "general.lua")
dofile(dots .. "monitors.lua")
dofile(dots .. "execs.lua")
dofile(dots .. "env.lua")
dofile(dots .. "animations.lua")
dofile(dots .. "input.lua")
dofile(dots .. "plugins.lua")
dofile(dots .. "extra.lua")
dofile(dots .. "keybinds.lua")
dofile(dots .. "rules.lua")



-- Custom
-- per-device extras, only if the file exists (errors inside it are still reported)
local custom = home .. "/.config/custom/hyprland/custom.lua"
local cf = io.open(custom)
if cf then cf:close(); dofile(custom) end

-- Quickshell settings app: its settings, monitor setup and binds (loaded last, so they win)
pcall(dofile, os.getenv("HOME") .. "/.config/hypr/quickshell.lua")
