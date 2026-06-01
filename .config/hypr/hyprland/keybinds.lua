-- See https://wiki.hypr.land/Configuring/Keywords/
local mainMod = "SUPER" -- Sets "Windows" key as main modifier

-- https://wiki.hypr.land/Configuring/Basics/Binds/

hl.bind(mainMod .. " + Return",     hl.dsp.exec_cmd("kitty --class custom_hover"))
hl.bind(mainMod .. " + ALT + Return", hl.dsp.exec_cmd("kitty"))
hl.bind(mainMod .. " + C",          hl.dsp.window.close())
hl.bind(mainMod .. " + E",          hl.dsp.exec_cmd(fileManager))
hl.bind(mainMod .. " + H",          hl.dsp.window.float({ action = "toggle" }))
hl.bind(mainMod .. " + R",          hl.dsp.exec_cmd("wofi --show drun -n || pkill wofi"))
hl.bind(mainMod .. " + P",          hl.dsp.window.pseudo())
hl.bind(mainMod .. " + J",          hl.dsp.layout("togglesplit")) -- dwindle
hl.bind(mainMod .. " + F",          hl.dsp.window.fullscreen())
hl.bind(mainMod .. " + G",          hl.dsp.window.fullscreen({ mode = 1 }))

-- Custom Keybinds
hl.bind(mainMod .. " + Escape",     hl.dsp.exec_cmd("wlogout"),                                                     { description = "Logout screen" })
hl.bind(mainMod .. " + L",          hl.dsp.exec_cmd("bash ~/.config/hypr/hyprlock/hyprlock.sh"),                     { description = "Lock screen" })
hl.bind(mainMod .. " + Z",          hl.dsp.exec_cmd(browser),                                                       { description = "Open Browser" })
hl.bind(mainMod .. " + SHIFT + T",  hl.dsp.exec_cmd("quicksnip"),                                                   { description = "Screenshot OCR scan" })
--hl.bind(mainMod .. " + SHIFT + S",  hl.dsp.exec_cmd("hyprquickframe"),                                              { description = "Screenshot into clipboard" })
hl.bind(mainMod .. " + SHIFT + S", hl.dsp.exec_cmd("hyprshot -m region output --clipboard-only"),               { description = "Screenshot into clipboard backup" })
hl.bind("Print",                    hl.dsp.exec_cmd("hyprshot -m window -m active --clipboard-only"),               { description = "Screenshot hyprshot with print key" })
hl.bind(mainMod .. " + V",          hl.dsp.exec_cmd("cliphist list | wofi -S dmenu -n | cliphist decode | wl-copy"), { description = "Clipboard history" })
hl.bind(mainMod .. " + W",          hl.dsp.exec_cmd("bash ~/.config/hypr/wallpapers/select_wallpaper.sh"))
hl.bind(mainMod .. " + B",          hl.dsp.exec_cmd("better-control"))
hl.bind(mainMod .. " + TAB",        hl.dsp.exec_cmd("swaync-client -t -sw"))
hl.bind(mainMod .. " + ALT + T",    hl.dsp.exec_cmd("bash ~/.config/custom/scripts/tailscale-toggle.sh"))
hl.bind(mainMod .. " + X",          hl.dsp.exec_cmd("hyprctl kill"))
hl.bind(mainMod .. " + Space",      hl.dsp.exec_cmd("qs ipc -p ~/.config/quickshell/Overview call overview toggle"))

----------------------
-- Submaps
----------------------

-- Enter the passthrough submap with SUPER + .
hl.bind(mainMod .. " + period", hl.dsp.submap("passthrough"))

-- Define the passthrough submap (only binding inside is the exit)
hl.define_submap("passthrough", function()
    hl.bind(mainMod .. " + period", hl.dsp.submap("reset"))
end)

----------------------
-- Windows
----------------------

-- Move focus with mainMod + arrow keys
hl.bind(mainMod .. " + left",  hl.dsp.focus({ direction = "left" }))
hl.bind(mainMod .. " + right", hl.dsp.focus({ direction = "right" }))
hl.bind(mainMod .. " + up",    hl.dsp.focus({ direction = "up" }))
hl.bind(mainMod .. " + down",  hl.dsp.focus({ direction = "down" }))

-- Switch workspaces with mainMod + [0-9]
-- Move active window to a workspace with mainMod + SHIFT + [0-9]
-- Move active window silently with mainMod + CTRL + [0-9]
for i = 1, 10 do
    local key = i % 10 -- key 0 maps to workspace 10
    hl.bind(mainMod .. " + " .. key,          hl.dsp.focus({ workspace = i }))
    hl.bind(mainMod .. " + SHIFT + " .. key,  hl.dsp.window.move({ workspace = i }))
    hl.bind(mainMod .. " + CTRL + " .. key,   hl.dsp.window.move({ workspace = i, follow = false }))
end

-- Switch / move to next empty workspace with section key
hl.bind(mainMod .. " + section",          hl.dsp.focus({ workspace = "emptyn" }))
hl.bind(mainMod .. " + SHIFT + section",  hl.dsp.window.move({ workspace = "emptyn" }))
hl.bind(mainMod .. " + CTRL + section",   hl.dsp.window.move({ workspace = "emptyn", silent = true }))

-- Example special workspace (scratchpad)


-- Scroll through existing workspaces with mainMod + scroll
hl.bind(mainMod .. " + mouse_down", hl.dsp.focus({ workspace = "e+1" }))
hl.bind(mainMod .. " + mouse_up",   hl.dsp.focus({ workspace = "e-1" }))

-- Move/resize windows with mainMod + LMB/RMB and dragging
hl.bind(mainMod .. " + mouse:272", hl.dsp.window.drag(),   { mouse = true })
hl.bind(mainMod .. " + mouse:273", hl.dsp.window.resize(), { mouse = true })

-- Laptop multimedia keys for volume and LCD brightness
hl.bind("XF86AudioRaiseVolume",  hl.dsp.exec_cmd("wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%+"),    { locked = true, repeating = true })
hl.bind("XF86AudioLowerVolume",  hl.dsp.exec_cmd("wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-"),    { locked = true, repeating = true })
hl.bind("XF86AudioMute",         hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"),   { locked = true })
hl.bind("XF86AudioMicMute",      hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle"), { locked = true })
hl.bind("XF86MonBrightnessUp",   hl.dsp.exec_cmd("brightnessctl s 10%+"),                         { locked = true, repeating = true })
hl.bind("XF86MonBrightnessDown", hl.dsp.exec_cmd("brightnessctl s 10%-"),                         { locked = true, repeating = true })

-- Requires playerctl
hl.bind("XF86AudioNext",  hl.dsp.exec_cmd("playerctl next"),        { locked = true })
hl.bind("XF86AudioPause", hl.dsp.exec_cmd("playerctl play-pause"),  { locked = true })
hl.bind("XF86AudioPlay",  hl.dsp.exec_cmd("playerctl play-pause"),  { locked = true })
hl.bind("XF86AudioPrev",  hl.dsp.exec_cmd("playerctl previous"),    { locked = true })


-- Custom Desktop
hl.bind(mainMod .. " + D",          hl.dsp.focus({ workspace = "name:default" }))
hl.bind(mainMod .. " + SHIFT + D",  hl.dsp.window.move({ workspace = "name:default" }))
hl.bind(mainMod .. " + CTRL + D",   hl.dsp.window.move({ workspace = "name:default", silent = true }))