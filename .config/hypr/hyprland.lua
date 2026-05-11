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
dofile(home .. "/.config/custom/hyprland/custom.lua")