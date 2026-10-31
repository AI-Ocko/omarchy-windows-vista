-- Windows Vista (Aero (Graphite)) -- Hyprland colours only (geometry is
-- omarchy/vista/hypr/late.lua, which loads after looknfeel.lua).
-- PLACEHOLDER colours until the Vista look.
local active_border_color = "rgb(4b4b4b)"
local inactive_border_color = "rgb(9a9a9a)"

hl.config({
	general = {
		col = {
			active_border = active_border_color,
			inactive_border = inactive_border_color,
		},
	},
})
