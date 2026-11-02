-- Windows Vista: nvim in the cmd.exe console palette, through aether.nvim the
-- way Omarchy's generated themes do it (same spec shape as Omarchy's
-- default/themed/neovim.lua.tpl, so theme hot-reload keeps working).
--
-- Why this file exists: without it Omarchy generates one from colors.toml, and
-- aether's derivation breaks on the cmd.exe palette. Selection #C0C0C0 equals
-- the text colour (Visual, LSP references and DiffText vanish), and navy
-- #000080 on black is 1.3:1 (functions, keywords, directories, titles, info
-- diagnostics, every float border).
--
-- Rule: black, #C0C0C0 text, the 16 console colours. The six that are too dark
-- on black (below 4.5:1) keep their hue, lifted to 5:1, the same as in foot.ini:
--   red #800000 -> #F90000, green #008000 -> #009100, cyan #008080 -> #008A8A,
--   blue #000080 -> #6868FF, magenta #800080 -> #DB00DB, bright blue #0000FF -> #8080FF.
-- Visual stays cmd.exe Mark: a #C0C0C0 block with black text.
--
-- The four Vista schemes ship this file byte-identical (windows-vista,
-- -basic, -frost, -graphite). Edit one, copy it to the other three, and run
-- omarchy/vista/bin/vista-nvim-check.

local BLACK, GREY, WHITE = "#000000", "#C0C0C0", "#FFFFFF"
local NAVY, MAROON = "#000080", "#800000" -- console colours, used only as backgrounds

local MARK = { fg = BLACK, bg = GREY } -- cmd.exe Mark selection
local NAVY_BAR = { fg = WHITE, bg = NAVY } -- references, DiffText, menu selection

return {
  {
    "bjarneo/aether.nvim",
    branch = "v3",
    name = "aether",
    priority = 1000,
    opts = {
      colors = {
        bg = BLACK,
        dark_bg = BLACK,
        darker_bg = BLACK,
        lighter_bg = NAVY,

        fg = GREY,
        dark_fg = "#808080",
        light_fg = GREY,
        bright_fg = WHITE,
        muted = "#808080",

        red = "#F90000", -- console #800000, lifted
        yellow = "#808000",
        orange = "#808000",
        green = "#009100", -- console #008000, lifted
        cyan = "#008A8A", -- console #008080, lifted
        blue = "#6868FF", -- console #000080, lifted
        magenta = "#DB00DB", -- console #800080, lifted
        brown = "#808000",

        bright_red = "#FF0000",
        bright_yellow = "#FFFF00",
        bright_green = "#00FF00",
        bright_cyan = "#00FFFF",
        bright_blue = "#8080FF", -- console #0000FF, lifted
        bright_magenta = "#FF00FF",

        accent = "#409EFE",
        cursor = WHITE,
        foreground = GREY,
        background = BLACK,
        selection = GREY,
        selection_foreground = BLACK,
        selection_background = GREY,
      },

      -- Roles aether derives from the palette after `colors` is applied.
      on_colors = function(c)
        c.border_highlight = c.muted -- float borders and titles: was navy blended to #000066
        c.bg_search = c.yellow -- was #000033, invisible on black
        c.diff.add = "#002000" -- the console-green and -red tints, not the lifted ones
        c.diff.delete = "#200000"
        c.diff.text = NAVY -- was the selection grey
        -- :terminal greys as in foot (aether puts navy in slot 8)
        c.terminal.black_bright = "#808080"
        c.terminal.white = GREY
        c.terminal.white_bright = WHITE
      end,

      -- Groups that need an explicit fg, and single aether blends below 4.5:1.
      on_highlights = function(hl, c)
        hl.Visual = MARK
        hl.VisualNOS = MARK
        hl.WildMenu = MARK
        hl.SnippetTabstop = MARK
        hl.SnippetTabstopActive = MARK
        hl.QuickFixLine = { fg = BLACK, bg = GREY, bold = true }

        hl.LspReferenceText = NAVY_BAR
        hl.LspReferenceRead = NAVY_BAR
        hl.LspReferenceTarget = NAVY_BAR
        hl.LspReferenceWrite = { fg = WHITE, bg = MAROON, bold = true }
        hl.DiffText = NAVY_BAR

        hl.Search = { fg = BLACK, bg = c.yellow }
        hl.IncSearch = { fg = BLACK, bg = c.bright_yellow, bold = true } -- CurSearch links here

        hl.PmenuSel = NAVY_BAR -- PmenuKindSel and PmenuExtraSel link here
        hl.BlinkCmpMenuSelection = NAVY_BAR
        hl.PmenuMatchSel = { fg = c.bright_cyan, bg = NAVY, bold = true }

        -- Text on lighter_bg (navy) needs the bright colours.
        hl["@markup.raw.markdown_inline"] = { fg = WHITE, bg = c.lighter_bg }
        hl.FlashMatch = { fg = c.bright_cyan, bg = c.lighter_bg, bold = true }
        hl.TelescopePreviewMatch = { fg = c.bright_cyan, bg = c.lighter_bg }
        hl.MiniTablineModifiedCurrent = { fg = c.bright_yellow, bg = c.lighter_bg, bold = true }
        hl.MiniStatuslineDevinfo = { fg = GREY, bg = c.lighter_bg }
        hl.MiniStatuslineFileinfo = { fg = GREY, bg = c.lighter_bg }

        -- aether sets these fg the same as, or close to, their bg.
        hl.MiniStatuslineFilename = { fg = BLACK, bg = c.muted }
        hl.TroubleCount = { fg = BLACK, bg = c.muted }
        hl.NvimTreeWinSeparator = { fg = c.border, bg = c.bg_sidebar }

        -- Blends of fg or blue that fall below 4.5:1.
        hl["@punctuation.bracket"] = { fg = c.dark_fg }
        hl["@punctuation.delimiter"] = { fg = c.dark_fg }
        hl["@tag.delimiter.tsx"] = { fg = c.dark_fg }
        hl.diffNewFile = { fg = c.bright_blue, bg = c.diff.add }
        hl.diffOldFile = { fg = c.bright_blue, bg = c.diff.delete }
        hl.diffChanged = { fg = c.bright_yellow, bg = c.diff.change }
        hl.helpCommand = { fg = c.bright_blue, bg = c.subtle_bg }
        hl.debugBreakpoint = { fg = c.bright_blue, bg = c.bg }
      end,
    },
  },
  {
    "LazyVim/LazyVim",
    opts = {
      colorscheme = "aether",
    },
  },
}
