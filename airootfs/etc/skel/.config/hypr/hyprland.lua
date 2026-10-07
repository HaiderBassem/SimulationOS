-- ┌──────────────────────────────────────────────────────────────────────────┐
-- │ SimulationOS - Hyprland configuration                                    │
-- │                                                                          │
-- │ Hyprland >= 0.55 is configured in Lua (~/.config/hypr/hyprland.lua).     │
-- │ Deliberately small and flat so it can be debugged. Every command         │
-- │ referenced here is provided by a package in packages.x86_64:             │
-- │   kitty wofi thunar waybar mako swaybg hyprlock hyprpolkitagent          │
-- │   grim slurp wl-clipboard cliphist brightnessctl pavucontrol             │
-- │   nm-connection-editor network-manager-applet blueman                    │
-- │   simos-* helpers (airootfs/usr/local/bin)                               │
-- │                                                                          │
-- │ Put personal settings in ~/.config/hypr/user.lua (loaded last).          │
-- │ Check this file with:  Hyprland --verify-config                          │
-- └──────────────────────────────────────────────────────────────────────────┘

local mainMod     = "SUPER"
local terminal    = "kitty"
local launcher    = "wofi --show drun"
local fileManager = "thunar"

-- ─────────────────────────────────────────────────────────────────── monitors
-- Let Hyprland pick the preferred mode for every output.
hl.monitor({
    output   = "",
    mode     = "preferred",
    position = "auto",
    scale    = 1,
})

-- ──────────────────────────────────────────────────────────────── environment
hl.env("XDG_CURRENT_DESKTOP", "Hyprland")
hl.env("XDG_SESSION_TYPE", "wayland")
hl.env("XDG_SESSION_DESKTOP", "Hyprland")
hl.env("QT_QPA_PLATFORM", "wayland;xcb")
hl.env("QT_WAYLAND_DISABLE_WINDOWDECORATION", "1")
hl.env("QT_AUTO_SCREEN_SCALE_FACTOR", "1")
hl.env("GDK_BACKEND", "wayland,x11")
hl.env("SDL_VIDEODRIVER", "wayland")
hl.env("CLUTTER_BACKEND", "wayland")
hl.env("MOZ_ENABLE_WAYLAND", "1")
hl.env("ELECTRON_OZONE_PLATFORM_HINT", "auto")
hl.env("XCURSOR_SIZE", "24")
hl.env("HYPRCURSOR_SIZE", "24")

-- ────────────────────────────────────────────────────────────────── autostart
-- One ordered script instead of a list of exec commands: Hyprland runs
-- separate commands concurrently, and the session environment must reach
-- D-Bus/systemd BEFORE anything that depends on it starts. See simos-session.
hl.on("hyprland.start", function()
    hl.exec_cmd("simos-session")
end)

-- ─────────────────────────────────────────────────────────────────── keyboard
-- Use the keyboard chosen in the installer. Calamares records it in
-- /etc/default/keyboard (XKBLAYOUT="de" ...); without this the session would
-- always be "us" no matter what was selected. Falls back to "us" when the
-- file does not exist (the live medium).
local keyboard = { layout = "us", variant = "", model = "", options = "" }
do
    local file = io.open("/etc/default/keyboard", "r")
    if file then
        for line in file:lines() do
            local key, value = line:match('^XKB(%u+)="?([^"]*)"?')
            if key and value ~= "" then
                keyboard[key:lower()] = value
            end
        end
        file:close()
    end
end

-- ────────────────────────────────────────────────────────────────── appearance
hl.config({
    general = {
        gaps_in     = 4,
        gaps_out    = 8,
        border_size = 2,
        col = {
            active_border   = { colors = { "rgba(1793d1ee)", "rgba(33ccffee)" }, angle = 45 },
            inactive_border = "rgba(2a2a2aaa)",
        },
        layout           = "dwindle",
        resize_on_border = true,
    },

    decoration = {
        rounding = 8,
        blur = {
            enabled = true,
            size    = 3,
            passes  = 1,
        },
        shadow = {
            enabled      = true,
            range        = 12,
            render_power = 3,
            color        = "rgba(00000055)",
        },
    },

    animations = {
        enabled = true,
    },

    dwindle = {
        preserve_split = true,
    },

    -- No upstream "what's new" / donation pop-ups on first start.
    ecosystem = {
        no_update_news  = true,
        no_donation_nag = true,
    },

    misc = {
        -- SimulationOS ships its own wallpapers; no upstream mascot/logo.
        disable_hyprland_logo    = true,
        disable_splash_rendering = true,
        force_default_wallpaper  = 0,
        font_family              = "Fira Sans",
    },

    -- Software cursors keep the pointer visible in VMs and on drivers with
    -- broken hardware cursor planes.
    cursor = {
        no_hardware_cursors = 1,
    },

    input = {
        kb_layout    = keyboard.layout,
        kb_variant   = keyboard.variant,
        kb_model     = keyboard.model,
        kb_options   = keyboard.options,
        follow_mouse = 1,
        sensitivity  = 0,
        touchpad = {
            natural_scroll       = true,
            tap_to_click         = true,
            disable_while_typing = true,
        },
    },
})

hl.curve("easeOutQuint", { type = "bezier", points = { { 0.23, 1 }, { 0.32, 1 } } })
hl.animation({ leaf = "windows",    enabled = true, speed = 4, bezier = "easeOutQuint", style = "popin 90%" })
hl.animation({ leaf = "fade",       enabled = true, speed = 4, bezier = "easeOutQuint" })
hl.animation({ leaf = "workspaces", enabled = true, speed = 5, bezier = "easeOutQuint", style = "slide" })
hl.animation({ leaf = "border",     enabled = true, speed = 6, bezier = "easeOutQuint" })

hl.gesture({
    fingers   = 3,
    direction = "horizontal",
    action    = "workspace",
})

-- ─────────────────────────────────────────────────────────────────── keybinds
hl.bind(mainMod .. " + Return",    hl.dsp.exec_cmd(terminal))
hl.bind(mainMod .. " + D",         hl.dsp.exec_cmd(launcher))
hl.bind(mainMod .. " + E",         hl.dsp.exec_cmd(fileManager))
hl.bind(mainMod .. " + Q",         hl.dsp.window.close())
hl.bind(mainMod .. " + SHIFT + E", hl.dsp.exit())
hl.bind(mainMod .. " + V",         hl.dsp.window.float({ action = "toggle" }))
hl.bind(mainMod .. " + P",         hl.dsp.window.pseudo())
hl.bind(mainMod .. " + J",         hl.dsp.layout("togglesplit"))
hl.bind(mainMod .. " + F",         hl.dsp.window.fullscreen({ mode = "fullscreen" }))
hl.bind(mainMod .. " + R",         hl.dsp.exec_cmd("hyprctl reload"))
hl.bind(mainMod .. " + X",         hl.dsp.exec_cmd("simos-powermenu"))
hl.bind(mainMod .. " + L",         hl.dsp.exec_cmd("hyprlock"))
hl.bind(mainMod .. " + C",         hl.dsp.exec_cmd("simos-clipboard"))
hl.bind(mainMod .. " + W",         hl.dsp.exec_cmd("simos-wallpaper next"))
hl.bind(mainMod .. " + SHIFT + N", hl.dsp.exec_cmd("nm-connection-editor"))

-- Screenshots
hl.bind("Print",             hl.dsp.exec_cmd("simos-screenshot full"))
hl.bind("SHIFT + Print",     hl.dsp.exec_cmd("simos-screenshot area"))
hl.bind(mainMod .. " + Print", hl.dsp.exec_cmd("simos-screenshot window"))

-- Focus and move
for _, dir in ipairs({ "left", "right", "up", "down" }) do
    hl.bind(mainMod .. " + " .. dir,         hl.dsp.focus({ direction = dir }))
    hl.bind(mainMod .. " + SHIFT + " .. dir, hl.dsp.window.move({ direction = dir }))
end

-- Workspaces 1-10 (key 0 is workspace 10)
for i = 1, 10 do
    local key = i % 10
    hl.bind(mainMod .. " + " .. key,         hl.dsp.focus({ workspace = i }))
    hl.bind(mainMod .. " + SHIFT + " .. key, hl.dsp.window.move({ workspace = i }))
end

hl.bind(mainMod .. " + mouse_down", hl.dsp.focus({ workspace = "e+1" }))
hl.bind(mainMod .. " + mouse_up",   hl.dsp.focus({ workspace = "e-1" }))
hl.bind(mainMod .. " + mouse:272",  hl.dsp.window.drag(),   { mouse = true })
hl.bind(mainMod .. " + mouse:273",  hl.dsp.window.resize(), { mouse = true })

-- Media / hardware keys
hl.bind("XF86AudioRaiseVolume",  hl.dsp.exec_cmd("wpctl set-volume -l 1 @DEFAULT_AUDIO_SINK@ 5%+"), { locked = true, repeating = true })
hl.bind("XF86AudioLowerVolume",  hl.dsp.exec_cmd("wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-"),      { locked = true, repeating = true })
hl.bind("XF86AudioMute",         hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"),     { locked = true })
hl.bind("XF86AudioMicMute",      hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle"),   { locked = true })
hl.bind("XF86MonBrightnessUp",   hl.dsp.exec_cmd("brightnessctl set 5%+"),                          { locked = true, repeating = true })
hl.bind("XF86MonBrightnessDown", hl.dsp.exec_cmd("brightnessctl set 5%-"),                          { locked = true, repeating = true })

-- ──────────────────────────────────────────────────────────────── window rules
hl.window_rule({
    name  = "suppress-maximize-events",
    match = { class = ".*" },
    suppress_event = "maximize",
})

for _, class in ipairs({ "pavucontrol", "org.pulseaudio.pavucontrol", "nm-connection-editor", "blueman-manager" }) do
    hl.window_rule({
        name  = "float-" .. class,
        match = { class = "^(" .. class .. ")$" },
        float = true,
    })
end

-- The installer is a dialog-sized window: float it, centred, at a size where
-- every Calamares page fits without scrolling.
hl.window_rule({
    name   = "installer",
    match  = { class = "^(calamares|io.calamares.calamares)$" },
    float  = true,
    center = true,
    size   = { 1100, 720 },
})

-- ───────────────────────────────────────────────────────── user overrides last
-- pcall: a missing or broken user.lua must never take the session down.
pcall(require, "user")
