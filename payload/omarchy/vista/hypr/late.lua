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

-- Vista frames: a 4 px resizable border around 8 px-rounded windows that sit
-- a little apart. Title bars (hyprbars with the Aero caption buttons) and the
-- per-scheme glass come with the Vista look; until then this is geometry only.
hl.config({
	general = {
		gaps_in = 3,
		gaps_out = 6,
		border_size = 4,
	},
	decoration = {
		rounding = 6,
		rounding_power = 2.0,
		dim_inactive = false,
		active_opacity = 1.0,
	},
})
