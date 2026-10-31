-- Windows Vista (Aero (Default)) -- Hyprland colours only (geometry is
-- omarchy/vista/hypr/late.lua, which loads after looknfeel.lua).
-- PLACEHOLDER colours until the Vista look.
local active_border_color = "rgb(409efe)"
local inactive_border_color = "rgb(a9c9ec)"

hl.config({
	general = {
		col = {
			active_border = active_border_color,
			inactive_border = inactive_border_color,
		},
	},
})
