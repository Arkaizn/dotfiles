--- Window Rules --------
-- https://wiki.hypr.land/Configuring/Window-Rules/

--- Important Fixes ---

-- Ignore maximize requests from all apps
hl.window_rule({
    name  = "suppress-maximize-events",
    match = { class = ".*" },
    suppress_event = "maximize",
})

-- Fix dragging issues with XWayland
hl.window_rule({
    name  = "fix-xwayland-drags",
    match = { class = "^$", title = "^$", xwayland = true, float = true },
    no_focus = true,
})

--- Apps ---

-- Stay focused: app menus
hl.window_rule({ match = { class = "(rofi|wofi|Vncviewer)" }, stay_focused = true })
hl.window_rule({ match = { class = "Vncviewer" }, center = true })

-- pavucontrol - audio
hl.window_rule({
    match   = { class = "^(org.pulseaudio.pavucontrol)$" },
    float   = true,
    center  = true,
    size    = { 1200, 700 },
})

-- blueman-manager
hl.window_rule({
    match   = { class = "^(blueman-manager)$" },
    float   = true,
    center  = true,
    size    = { 800, 500 },
})

-- Calculator
hl.window_rule({
    match   = { class = "^(org.gnome.Calculator)$" },
    float   = true,
    center  = true,
    size    = { 385, 616 },
})

-- IW GTK
hl.window_rule({
    match   = { class = "^(org.twosheds.iwgtk)$" },
    float   = true,
    center  = true,
    size    = { 1200, 700 },
})

-- xdg-desktop-portal-gtk
hl.window_rule({
    match     = { class = "^(xdg-desktop-portal-gtk)$" },
    float     = true,
    center    = true,
    size      = { 1200, 700 },
    animation = "slide bottom",
})

-- satty (com.gabm.satty)
hl.window_rule({
    match     = { class = "^(com.gabm.satty)$" },
    float     = true,
    center    = true,
    size      = { 1200, 700 },
    animation = "slide bottom",
})

--- Custom rules ---

-- custom_hover (floating terminal / hover window)
hl.window_rule({
    match     = { class = "custom_hover" },
    float     = true,
    center    = true,
    size      = { 1200, 650 },
    animation = "slide bottom",
    rounding  = 10,
})

--- Workspace Rules ----
-- https://wiki.hypr.land/Configuring/Workspace-Rules/

-- Custom default workspace on laptop display
hl.workspace_rule({ workspace = "name:default", monitor = "eDP-1", default = true })

-- Special exposed workspace with custom gaps/borders
hl.workspace_rule({
    workspace   = "special:exposed",
    gaps_out    = 60,
    gaps_in     = 30,
    border_size = 5,
    decorate    = true,
})

-- Persistent workspaces 1-5
for i = 1, 5 do
    hl.workspace_rule({ workspace = tostring(i), persistent = true })
end

--- Layer Rules --------
-- https://wiki.hypr.land/Configuring/Window-Rules/#layer-rules

-- quickshell
hl.layer_rule({ match = { namespace = "quickshell" }, blur = true, xray = true, no_anim = true, ignore_alpha = 0.1 })

-- waybar
hl.layer_rule({ match = { namespace = "waybar" }, blur = true, ignore_alpha = 0.5 })

-- wofi
hl.layer_rule({ match = { namespace = "wofi" }, blur = true, ignore_alpha = 0.5 })

-- swaync
hl.layer_rule({ match = { namespace = "swaync-control-center" },       blur = true, ignore_alpha = 0.5 })
hl.layer_rule({ match = { namespace = "swaync-notification-window" },  blur = true, ignore_alpha = 0.5 })

-- logout dialog
hl.layer_rule({ match = { namespace = "logout_dialog" }, no_anim = true })