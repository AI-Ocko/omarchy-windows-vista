-- Windows Vista -- Hyprland geometry overrides that must load AFTER
-- hypr/looknfeel.lua.
--
-- A theme's hyprland.lua runs inside the Omarchy defaults, before the user's
-- hypr/*.lua, so gaps/border/rounding set there lose to looknfeel.lua.
-- `vista-mode on` copies this file to
-- ~/.local/state/omarchy/toggles/hypr/windows-vista.lua, which
-- default.hypr.toggles loads last, and `vista-mode off` removes it. It also
-- guards itself: outside a Vista theme it does nothing, so a stale copy left
-- behind cannot leak Vista geometry. (A copy, not a symlink:
-- default/hypr/require_all.lua lists that directory with `find -type f`.)

local paths = require("default.hypr.paths")

local function theme_name()
	local f = io.open(paths.state_home .. "/omarchy/current/theme.name", "r")
	if not f then
		return ""
	end
	local name = f:read("*l") or ""
	f:close()
	return name
end

local name = theme_name()
if name ~= "windows-vista" and name:sub(1, 14) ~= "windows-vista-" then
	return
end

o.window({ tag = "default-opacity" }, { opacity = "1 1" })

-- Title bars: hyprbars with Vista's caption art (omarchy/vista/hyprbars/
-- build, ABI-locked: used only while its stamp matches the running Hyprland;
-- without it there are no title bars, never stock ones under Vista).
-- Aero: a translucent colorization tint over blur, the glass reflection
-- (DWMWindow atlas part 40) and DWM's caption glow (white, TEXTGLOWSIZE 10 at
-- 96 dpi, drawn here at 5). The buttons are DWM's joined group, hung from the
-- top: minimize/maximize 28 x 20 (SIZINGMARGINS 12 12 6 8), close 46 x 20
-- (20 20 6 8). Basic: the opaque Window CAPTION image (9-slice 28 35 9 17)
-- and its separate buttons. Tints: omarchy/vista/palette.md.
-- Tints are the colorizations themselves (alpha 0x45; Default from aero.theme,
-- Graphite/Frost calibrated, palette.md); unfocused windows get 45/80 of
-- that, DWM's inactive/active caption OPACITY (DWMWindow part 39).
local schemes = {
	["windows-vista"] = { glass = true, tint = "rgba(409efe45)", idle = "rgba(409efe27)" },
	["windows-vista-graphite"] = { glass = true, tint = "rgba(00000045)", idle = "rgba(00000027)" },
	["windows-vista-frost"] = { glass = true, tint = "rgba(9abfc845)", idle = "rgba(9abfc827)" },
	["windows-vista-basic"] = { glass = false },
}
local c = schemes[name] or schemes["windows-vista"]

-- Vista frames: Aero's glass frame is ~8 px on the sides and bottom; a 6 px
-- translucent border in the glass colour stands in for it (the border colour
-- is the scheme's hyprland.lua). Basic keeps its thin opaque frame.
hl.config({
	general = {
		gaps_in = 3,
		gaps_out = 6,
		border_size = c.glass and 6 or 4,
	},
	decoration = {
		rounding = 6,
		rounding_power = 2.0,
		dim_inactive = false,
		active_opacity = 1.0,
	},
})

-- Aero glass behind the taskbar, the Start menu and the shell's dialogs and
-- flyouts (omarchy-keyboard-panel: VistaWindow's glass frame; their client
-- areas are opaque, so only the frame shows it): blur what is under their
-- translucent pixels (fully transparent ones, e.g. the strip above the
-- taskbar the orb overhangs into, stay clear). Vista Basic has no glass.
if c.glass then
	hl.layer_rule({ match = { namespace = "^(omarchy-bar|vista-start-menu|omarchy-keyboard-panel|vista-run-dialog|vista-exit-dialog)$" }, blur = true, ignore_alpha = 0.05 })
end

local home = os.getenv("HOME")
local bars = home .. "/.local/lib/hyprbars-vista"
local function read_line(path)
	local f = io.open(path, "r")
	if not f then
		return nil
	end
	local line = f:read("*l")
	f:close()
	return line
end
local ready = read_line(bars .. "/hyprland-version") == hl.version() and io.open(bars .. "/libhyprbars.so", "r") ~= nil
if not ready then
	return
end
hl.plugin.load(bars .. "/libhyprbars.so")
if hl.plugin.hyprbars == nil then
	return
end

local g = home .. "/.config/omarchy/vista/assets/graphics/"
local function dispatch(lua)
	return "hyprctl dispatch '" .. lua .. "'"
end
local maximize = dispatch('hl.dsp.window.fullscreen({ mode = "maximized" })')

local common = {
	bar_text_font = "Segoe UI",
	bar_text_size = 12,
	bar_text_weight = "normal",
	bar_text_align = "left",
	bar_buttons_alignment = "right",
	bar_padding = 6,
	on_double_click = maximize,
}
local cfg
if c.glass then
	cfg = {
		bar_height = 25,
		bar_color = c.tint,
		-- the bar sits over the top border, so the buttons hang flush from
		-- the frame's top edge as DWM's do
		bar_precedence_over_border = true,
		bar_blur = true,
		["col.text"] = "rgb(000000)",
		["col.text_glow"] = "rgba(ffffffe6)",
		bar_text_glow_size = 5,
		bar_overlay_image = g .. "aero/parts/DWMWindow/40.0.ATLAS.png",
		bar_overlay_opacity = 100,
		bar_button_padding = 0,
		bar_button_top = 0,
	}
else
	cfg = {
		bar_height = 26,
		bar_color = "rgba(00000000)",
		bar_blur = false,
		["col.text"] = "rgb(000000)",
		bar_bg_image = g .. "captions/basic/caption-%d.png",
		bar_bg_margins = "28 35 9 17",
		bar_button_padding = 2,
		bar_button_top = 3,
	}
end
for k, v in pairs(common) do
	cfg[k] = v
end
hl.config({ plugin = { hyprbars = cfg } })

-- First added is rightmost. bg_color/fg_color/icon are what stock hyprbars
-- would draw if the art failed to load.
local set = c.glass and "glass" or "basic"
local function art(n)
	return g .. "captions/" .. set .. "/" .. n .. "-%d.png"
end
local glyph_alt = art("restore-g")
if c.glass then
	hl.plugin.hyprbars.add_button({ bg_color = "rgb(c8463c)", fg_color = "rgb(ffffff)", icon = "✕", size = 20, width = 46, height = 20, margins = { 20, 20, 6, 8 }, action = dispatch("hl.dsp.window.close()"), bg_image = art("close-bg"), fg_image = art("close-g") })
	hl.plugin.hyprbars.add_button({ bg_color = "rgb(dce8f4)", fg_color = "rgb(000000)", icon = "□", size = 20, width = 28, height = 20, margins = { 12, 12, 6, 8 }, action = maximize, bg_image = art("max-bg"), fg_image = art("max-g"), fg_image_alt = glyph_alt })
	hl.plugin.hyprbars.add_button({ bg_color = "rgb(dce8f4)", fg_color = "rgb(000000)", icon = "_", size = 20, width = 28, height = 20, margins = { 12, 12, 6, 8 }, action = "omarchy-shell vistatask minimizeActive", bg_image = art("min-bg"), fg_image = art("min-g") })
else
	for _, b in ipairs({ { "close", dispatch("hl.dsp.window.close()") }, { "max", maximize }, { "min", "omarchy-shell vistatask minimizeActive" } }) do
		hl.plugin.hyprbars.add_button({ bg_color = "rgb(dce8f4)", fg_color = "rgb(000000)", icon = " ", size = 18, width = 26, height = 18, margins = { 2, 2, 7, 7 }, action = b[2], bg_image = art(b[1] .. "-bg"), fg_image = art(b[1] .. "-g"), fg_image_alt = b[1] == "max" and glyph_alt or nil })
	end
end

if c.glass then
	o.window({ focus = false }, { ["hyprbars:bar_color"] = c.idle, ["hyprbars:title_color"] = "rgb(333333)" })
else
	o.window({ focus = false }, { ["hyprbars:title_color"] = "rgb(4c4c4c)" })
end
o.window("^(com\\.rice\\.(btop|logs)|org\\.omarchy\\.screensaver)$", { ["hyprbars:no_bar"] = true })
o.window({ tag = "floating-window" }, { ["hyprbars:no_bar"] = true })

-- Win+R: Vista's Run dialog (ocko.vista-taskbar). Bound here, so it exists
-- only while a Vista theme is active (plain SUPER+R is unbound in Omarchy).
o.bind("SUPER + R", "Run", "omarchy-shell vistastart run")
