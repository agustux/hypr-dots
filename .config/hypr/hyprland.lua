-- === VARIABLES ===

local var_mainMod = "SUPER"
local var_terminal = "ghostty"
local var_terminal_flags = "--gtk-single-instance=true"
local var_fileManager = "nautilus"
local var_browser = "brave-origin"

-- === HELPER FUNCTIONS ===

local function detect_igpu_card()
    local h = io.popen([[
        for f in /sys/bus/pci/devices/*/class; do
            read -r c < "$f"
            case "$c" in
                0x030000|0x030200)
                    basename "$(dirname "$f")"
                    ;;
            esac
        done
    ]])

    if not h then
        return nil
    end

    local gpus = {}
    for line in h:lines() do
        gpus[#gpus + 1] = line
    end
    h:close()

    local igpu, dgpu

    for _, pci in ipairs(gpus) do
        local bus = pci:match("^[^:]+:(%x+):")

        if bus == "00" and not igpu then
            igpu = pci
        elseif bus ~= "00" and not dgpu then
            dgpu = pci
        end
    end

    -- Same fallback as the Bash version
    if not igpu then
        igpu = dgpu
        dgpu = nil
    end

    -- [ -n "$IGPU_PCI" ] && [ -n "$DGPU_PCI" ] &&
    -- [ -e "/dev/dri/by-path/pci-${IGPU_PCI}-card" ]
    if igpu and dgpu then
        local path = "/dev/dri/by-path/pci-" .. igpu .. "-card"
        local f = io.open(path, "r")

        if f then
            f:close()
            local rh = io.popen("readlink -f " .. path)
            local real = nil
            if rh then
                real = rh:read("*l")
                rh:close()
            end
            return real
        end
    end

    return nil
end

-- Libva detection helper (sysfs, prefers iGPU on bus 00, falls back to any GPU)
local function detect_libva_driver()
	local h = io.popen([[
		for d in /sys/bus/pci/devices/0000:00:*/; do
			c=$(cat "$d/class" 2>/dev/null)
			[ "${c:0:6}" = "0x0300" ] && cat "$d/vendor" 2>/dev/null
		done
	]])
	local vendor = h:read("*a")
	h:close()
	if vendor == "" then
		h = io.popen([[
			for d in /sys/bus/pci/devices/*/; do
				c=$(cat "$d/class" 2>/dev/null)
				[ "${c:0:6}" = "0x0300" ] && cat "$d/vendor" 2>/dev/null
			done
		]])
		vendor = h:read("*a")
		h:close()
	end
	if vendor:match("0x8086") then
		return "iHD"
	elseif vendor:match("0x1002") then
		return "radeonsi"
	elseif vendor:match("0x10de") then
		return "nvidia"
	end
	return "iHD"
end

local function detect_primary_output()
	local h = io.popen([[
		for f in /sys/class/drm/card*-*; do
			[ "$(cat "$f/status" 2>/dev/null)" = connected ] || continue
			basename "$f" | sed 's/^card[0-9]*-//'
		done
	]])
	local names = {}
	for line in h:lines() do table.insert(names, line) end
	h:close()
	for _, n in ipairs(names) do
		if n:match("^eDP") or n:match("^LVDS") then return n end
	end
	return names[1] or "eDP-1"
end

local function detect_capped_mode(output)
	local h = io.popen(string.format([[
		f=$(ls -d /sys/class/drm/card*-%s 2>/dev/null | head -n1)
		[ -n "$f" ] && cat "$f/modes"
	]], output))
	local native, best
	for line in h:lines() do
		local w, hgt = line:match("(%d+)x(%d+)")
		w, hgt = tonumber(w), tonumber(hgt)
		if not native then native = line end
		if w and hgt and hgt <= 1080 and not best then best = line end
	end
	h:close()
	return best or native or "preferred"
end

-- === MONITORS ===

hl.monitor({
    output = "",
    disabled = false,
    mode = detect_capped_mode(detect_primary_output()),
    position = "auto",
    scale = 1,
})

-- Mirror any new displays connected:
hl.monitor({
    output = "",
    disabled = false,
    mode = "preferred",
    position = "auto",
    scale = 1,
    mirror = detect_primary_output(),
})

-- === AUTOSTART ===

local igpu_card = detect_igpu_card()

if igpu_card then
    hl.env("AQ_DRM_DEVICES", igpu_card)
end

hl.on("hyprland.start", function()
    hl.exec_cmd(var_terminal .. " " .. var_terminal_flags)
    hl.exec_cmd("hyprpaper")
    hl.exec_cmd("waybar")
    hl.exec_cmd("dunst")
    hl.exec_cmd("hypridle")

    hl.exec_cmd("dbus-update-activation-environment --systemd WAYLAND_DISPLAY XDG_CURRENT_DESKTOP PATH")
    hl.exec_cmd("/usr/lib/hyprpolkitagent/hyprpolkitagent")
    hl.exec_cmd("gsettings set org.gnome.desktop.interface color-scheme \"prefer-dark\"")
    hl.exec_cmd("gsettings set org.gnome.desktop.interface gtk-theme \"adw-gtk3\"")
    hl.exec_cmd("/usr/lib/xdg-desktop-portal-hyprland")
    hl.exec_cmd("/usr/lib/xdg-desktop-portal")
    hl.exec_cmd("xhost +SI:localuser:root")
end)

-- === ENVIRONMENT VARIABLES ===

hl.env("XCURSOR_SIZE", "24")
hl.env("HYPRCURSOR_SIZE", "24")


hl.env("LIBVA_DRIVER_NAME", detect_libva_driver())
hl.env("XDG_SESSION_TYPE", "wayland")
-- hl.env("GBM_BACKEND", "nvidia-drm")
hl.env("NVD_BACKEND", "direct")

-- QT Theming
hl.env("QT_QPA_PLATFORMTHEME", "hyprqt6engine")
hl.env("QT_QPA_PLATFORM", "wayland")

-- Hyprlock and suspend
hl.bind("switch:on:Lid Switch", hl.dsp.exec_cmd("loginctl lock-session"), {
    locked = true,
})
hl.bind("switch:on:Lid Switch", hl.dsp.exec_cmd("hyprlock"), {
    locked = true,
})
hl.bind("switch:on:Lid Switch", hl.dsp.exec_cmd("systemctl suspend"), {
    locked = true,
})

-- === LOOK AND FEEL ===

hl.config({
    general = {
        gaps_in = 3,
        gaps_out = 6,
        border_size = 2,
    },
})

hl.config({
    general = {
        col = {
            active_border = "rgba(74c7ecee)",
            inactive_border = "rgba(585b70aa)",
        },
    },
})

-- Set to true enable resizing windows by clicking and dragging on borders and gaps
hl.config({
    general = {
        resize_on_border = true,
    },
})

hl.config({
    general = {
        allow_tearing = false,
        layout = "dwindle",
    },
})

hl.config({
    decoration = {
        rounding = 10,
        rounding_power = 2,
    },
})

hl.config({
    decoration = {
        shadow = {
            enabled = false,
        },
    },
})

hl.config({
    decoration = {
        blur = {
            enabled = false,
        },
    },
})

hl.config({
    animations = {
        enabled = false,
    },
})

hl.config({
    dwindle = {
        preserve_split = true,
    },
})

hl.config({
    master = {
        new_status = "master",
    },
})

hl.config({
    misc = {
        force_default_wallpaper = 0,
        disable_hyprland_logo = true,
        disable_splash_rendering = true,
	--force_default_wallpaper = 2,
	--disable_hyprland_logo = false,
    },
})

hl.config({
    cursor = {
        no_hardware_cursors = true,
    },
})

-- === INPUT ===

hl.config({
    input = {
        kb_layout = "us",
        kb_variant = "",
        kb_model = "",
        kb_options = "",
        kb_rules = "",
        follow_mouse = 1,
        sensitivity = 0,
        touchpad = {
            natural_scroll = true,
        },
    },
})

hl.gesture({
    fingers = 3,
    direction = "horizontal",
    action = "workspace",
})

-- === KEYBINDINGS ===

hl.bind(var_mainMod .. " + Q", hl.dsp.exec_cmd(var_terminal .. " " .. var_terminal_flags))
hl.bind(var_mainMod .. " + E", hl.dsp.exec_cmd(var_fileManager))
hl.bind(var_mainMod .. " + B", hl.dsp.exec_cmd(var_browser))
hl.bind(var_mainMod .. " + R", hl.dsp.exec_cmd("rofi -show drun"))
hl.bind(var_mainMod .. " + W", hl.dsp.exec_cmd("killall waybar || waybar"))
hl.bind(var_mainMod .. " + SHIFT + Q", hl.dsp.exec_cmd("loginctl lock-session"))
hl.bind(var_mainMod .. " + M", hl.dsp.exec_cmd("command -v hyprshutdown >/dev/null 2>&1 && hyprshutdown || hyprctl dispatch exit"))

-- Hyprshot w/ PrtSc key
hl.bind("PRINT", hl.dsp.exec_cmd("hyprshot -m region -o $HOME/Pictures/Screenshots/"))
hl.bind("ALT + PRINT", hl.dsp.exec_cmd("hyprshot -m window -o $HOME/Pictures/Screenshots/"))
hl.bind(var_mainMod .. " + PRINT", hl.dsp.exec_cmd("hyprshot -m output -m " .. detect_primary_output() .. " -o $HOME/Pictures/Screenshots/"))

-- Screenshots for keyboards without PrtSc
hl.bind(var_mainMod .. " + SHIFT + P", hl.dsp.exec_cmd("hyprshot -m region -o $HOME/Pictures/Screenshots/"))
hl.bind(var_mainMod .. " + ALT + P", hl.dsp.exec_cmd("hyprshot -m window -o $HOME/Pictures/Screenshots/"))
hl.bind(var_mainMod .. " + CTRL + P", hl.dsp.exec_cmd("hyprshot -m output -m " .. detect_primary_output() .. " -o $HOME/Pictures/Screenshots/"))

hl.bind(var_mainMod .. " + C", hl.dsp.window.close())
hl.bind(var_mainMod .. " + P", hl.dsp.window.pseudo())
hl.bind(var_mainMod .. " + T", hl.dsp.layout("togglesplit"))
hl.bind(var_mainMod .. " + V", hl.dsp.window.float({ action = "toggle" }))
hl.bind(var_mainMod .. " + F", hl.dsp.window.fullscreen({ mode = "fullscreen", action = "toggle" }))

-- Move focus with mainMod + arrow keys
hl.bind(var_mainMod .. " + H", hl.dsp.focus({ direction = "left" }))
hl.bind(var_mainMod .. " + L", hl.dsp.focus({ direction = "right" }))
hl.bind(var_mainMod .. " + K", hl.dsp.focus({ direction = "up" }))
hl.bind(var_mainMod .. " + J", hl.dsp.focus({ direction = "down" }))

-- Switch workspaces with mainMod + [0-9]
hl.bind(var_mainMod .. " + 1", hl.dsp.focus({ workspace = 1 }))
hl.bind(var_mainMod .. " + 2", hl.dsp.focus({ workspace = 2 }))
hl.bind(var_mainMod .. " + 3", hl.dsp.focus({ workspace = 3 }))
hl.bind(var_mainMod .. " + 4", hl.dsp.focus({ workspace = 4 }))
hl.bind(var_mainMod .. " + 5", hl.dsp.focus({ workspace = 5 }))
hl.bind(var_mainMod .. " + 6", hl.dsp.focus({ workspace = 6 }))
hl.bind(var_mainMod .. " + 7", hl.dsp.focus({ workspace = 7 }))
hl.bind(var_mainMod .. " + 8", hl.dsp.focus({ workspace = 8 }))
hl.bind(var_mainMod .. " + 9", hl.dsp.focus({ workspace = 9 }))
hl.bind(var_mainMod .. " + 0", hl.dsp.focus({ workspace = 10 }))

-- Move active window to a workspace with mainMod + SHIFT + [0-9]
hl.bind(var_mainMod .. " + SHIFT + 1", hl.dsp.window.move({ workspace = 1 }))
hl.bind(var_mainMod .. " + SHIFT + 2", hl.dsp.window.move({ workspace = 2 }))
hl.bind(var_mainMod .. " + SHIFT + 3", hl.dsp.window.move({ workspace = 3 }))
hl.bind(var_mainMod .. " + SHIFT + 4", hl.dsp.window.move({ workspace = 4 }))
hl.bind(var_mainMod .. " + SHIFT + 5", hl.dsp.window.move({ workspace = 5 }))
hl.bind(var_mainMod .. " + SHIFT + 6", hl.dsp.window.move({ workspace = 6 }))
hl.bind(var_mainMod .. " + SHIFT + 7", hl.dsp.window.move({ workspace = 7 }))
hl.bind(var_mainMod .. " + SHIFT + 8", hl.dsp.window.move({ workspace = 8 }))
hl.bind(var_mainMod .. " + SHIFT + 9", hl.dsp.window.move({ workspace = 9 }))
hl.bind(var_mainMod .. " + SHIFT + 0", hl.dsp.window.move({ workspace = 10 }))

-- Switch window position in direction
hl.bind(var_mainMod .. " + SHIFT + H", hl.dsp.window.swap({ direction = "left" }))
hl.bind(var_mainMod .. " + SHIFT + L", hl.dsp.window.swap({ direction = "right" }))
hl.bind(var_mainMod .. " + SHIFT + K", hl.dsp.window.swap({ direction = "up" }))
hl.bind(var_mainMod .. " + SHIFT + J", hl.dsp.window.swap({ direction = "down" }))

-- Ghostty's ghoulag special workspace (scratchpad)
hl.bind(var_mainMod .. " + S", hl.dsp.workspace.toggle_special("ghoulag"))
hl.bind(var_mainMod .. " + SHIFT + S", hl.dsp.window.move({ workspace = "special:ghoulag" }))


-- Scroll through existing workspaces with mainMod + scroll
hl.bind(var_mainMod .. " + mouse_down", hl.dsp.focus({ workspace = "e+1" }))
hl.bind(var_mainMod .. " + mouse_up", hl.dsp.focus({ workspace = "e-1" }))

-- Move/resize windows with mainMod + LMB/RMB and dragging
hl.bind(var_mainMod .. " + mouse:272", hl.dsp.window.drag(), {
    mouse = true,
})
hl.bind(var_mainMod .. " + mouse:273", hl.dsp.window.resize(), {
    mouse = true,
})

-- Laptop multimedia keys for volume and LCD brightness
hl.bind("XF86AudioRaiseVolume", hl.dsp.exec_cmd("wpctl set-volume -l 1 @DEFAULT_AUDIO_SINK@ 5%+"), {
    repeating = true,
    locked = true,
})
hl.bind("XF86AudioLowerVolume", hl.dsp.exec_cmd("wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-"), {
    repeating = true,
    locked = true,
})
hl.bind("XF86AudioMute", hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"), {
    repeating = true,
    locked = true,
})
hl.bind("XF86AudioMicMute", hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle"), {
    repeating = true,
    locked = true,
})
hl.bind("XF86MonBrightnessUp", hl.dsp.exec_cmd("brightnessctl -e4 -n2 set 5%+"), {
    repeating = true,
    locked = true,
})
hl.bind("XF86MonBrightnessDown", hl.dsp.exec_cmd("brightnessctl -e4 -n2 set 5%-"), {
    repeating = true,
    locked = true,
})
hl.bind("XF86KbdBrightnessUp", hl.dsp.exec_cmd("brightnessctl -d '*kbd_backlight' set 10%+"), {
    repeating = true,
    locked = true,
})
hl.bind("XF86KbdBrightnessDown", hl.dsp.exec_cmd("brightnessctl -d '*kbd_backlight' set 10%-"), {
    repeating = true,
    locked = true,
})

-- Requires playerctl
hl.bind("XF86AudioNext", hl.dsp.exec_cmd("playerctl next"), {
    locked = true,
})
hl.bind("XF86AudioPause", hl.dsp.exec_cmd("playerctl play-pause"), {
    locked = true,
})
hl.bind("XF86AudioPlay", hl.dsp.exec_cmd("playerctl play-pause"), {
    locked = true,
})
hl.bind("XF86AudioPrev", hl.dsp.exec_cmd("playerctl previous"), {
    locked = true,
})

-- === WINDOWS AND WORKSPACES ===

-- Example windowrules that are useful
hl.window_rule({
    name = "suppress-maximize-events",
    match = {
        class = ".*",
    },
    suppress_event = "maximize",
})
hl.window_rule({
    name = "fix-xwayland-drags",
    match = {
        class = "^$",
        title = "^$",
        xwayland = true,
        float = true,
        fullscreen = false,
        pin = false,
    },
    no_focus = true,
})

-- Hyprland-run windowrule
hl.window_rule({
    name = "move-hyprland-run",
    match = {
        class = "hyprland-run",
    },
    move = "20 monitor_h-120",
    float = true,
})

-- Ghoulag rule
hl.workspace_rule({
    workspace = "special:ghoulag",
    gaps_in = 20,
    gaps_out = 80
})
