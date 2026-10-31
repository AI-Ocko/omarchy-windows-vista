-- Windows Vista (Aero (Default)) -- Hyprland colours only (geometry is
-- omarchy/vista/hypr/late.lua, which loads after looknfeel.lua).
-- Aero: the frame stands in for the ~8 px glass frame (a border cannot be
-- blurred, so it is the glass colour, mostly opaque). Basic: the CAPTION
-- image's bottom row, so the frame continues the caption.
local active_border_color = "rgba(a6c8ecd9)"
local inactive_border_color = "rgba(c4d6eaa6)"

hl.config({
	general = {
		col = {
			active_border = active_border_color,
			inactive_border = inactive_border_color,
		},
	},
})
