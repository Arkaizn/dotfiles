------ PROGRAMS ------

terminal = "kitty"
fileManager = "nautilus"
menu = "wofi --show drun -n"
browser = "zen-browser"

------ General ------

-- https://wiki.hypr.land/Configuring/Basics/Variables/

hl.config({
    general = {
        gaps_in = 5,
        gaps_out = 10,
        border_size = 2,

        col = {
            active_border = { colors = {color1, color2}, angle = 45},
            inactive_border = backgroundCol,
            },

        -- Set to true enable resizing windows by clicking and dragging on borders and gaps
        resize_on_border = false,

        -- Please see https://wiki.hypr.land/Configuring/Advanced-and-Cool/Tearing/ before you turn this on
        allow_tearing = false,

        layout = "dwindle",
    },

    -- https://wiki.hypr.land/Configuring/Basics/Variables/

    decoration = {
        rounding = 10,
        active_opacity = 1.0,
        inactive_opacity = 0.9,
        fullscreen_opacity = 1.0,

        -- https://wiki.hypr.land/Configuring/Basics/Variables/#blur

        blur = {
            enabled = true,
            size = 3,
            passes = 5,
            new_optimizations = true,
            ignore_opacity = true,
            xray = true,
            popups = true,

        },

        shadow = {
            enabled = true,
            range = 10,
            render_power = 4,
            sharp = false,
            color = "0xff000000",
            scale = 10.0,
        },
    },

    animations = {
        enabled = true,
    },
})

-- See https://wiki.hypr.land/Configuring/Layouts/Dwindle-Layout/ for more
hl.config({ 
    dwindle = {
        preserve_split = true,
    }
})

-- https://wiki.hypr.land/Configuring/Layouts/Master-Layout/
hl.config({ 
    master = {
        new_status = master,
    }
})

-- https://wiki.hypr.land/Configuring/Basics/Variables/#misc
hl.config({
    misc = {
        force_default_wallpaper = -1,    -- Set to 0 or 1 to disable the anime mascot wallpapers
        disable_hyprland_logo   = true, -- If true disables the random hyprland logo / anime girl background. :(
    },
})