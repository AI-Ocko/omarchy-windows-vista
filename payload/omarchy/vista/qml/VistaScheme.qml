pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// The active Windows Vista colour scheme, shared by every Vista surface in the shell
// (the taskbar plugin and the ocko.vista-* clones of the menu, polkit,
// notifications and OSD). One watched FileView on theme.name for the whole
// shell; an Vista -> Vista scheme switch restyles live.
//
// Values are the scheme's own msstyles INI ([SysMetrics], [Window],
// [button.groupbox], [ExplorerBar.*], [edit]); InfoWindow (tooltip/balloon
// yellow) is hivedef.inf's. Art is cut by omarchy/vista/bin/vista-taskbar-art into
// assets/graphics/taskbar/<slug>/; icons are shell32/user32 groups at
// assets/graphics/{shell32,user32}/<size>/<id>.png.
Singleton {
  id: vista

  readonly property string home: Quickshell.env("HOME")
  readonly property string stateHome: Quickshell.env("XDG_STATE_HOME") || (home + "/.local/state")
  readonly property string graphics: "file://" + home + "/.config/omarchy/vista/assets/graphics"

  property string themeName: ""
  readonly property bool vistaActive: themeName === "windows-vista" || themeName.indexOf("windows-vista-") === 0
  readonly property string slug: schemes[themeName] ? themeName : "windows-vista"
  readonly property var sc: schemes[slug]
  readonly property string artRoot: graphics + "/taskbar"
  // Control art is the same in every scheme (vista-art: taskbar/widgets).
  readonly property string artDir: artRoot + "/widgets"

  // InfoWindow / InfoText (hivedef.inf); the same in every scheme.
  readonly property color infoWindow: "#FFFFE1"
  readonly property color infoText: "#000000"

  // Aero glass (all but Basic) and its colorization (late.lua's tints, as
  // QML #AARRGGBB), for VistaWindow's frame on the blurred dialog layer.
  readonly property bool glass: slug !== "windows-vista-basic"
  readonly property color tint: ({ "windows-vista": "#45409EFE", "windows-vista-graphite": "#45000000",
    "windows-vista-frost": "#459ABFC8" })[slug] || "#45409EFE"
  readonly property string captionArt: graphics + "/captions/glass/"

  function art(name) { return artDir + "/" + name + ".png" }
  // shell32.dll icon group <id> at 16, 32 or 48 px.
  // imageres.dll icon group <id> at 16, 32, 48 or 256 px (Vista's own icons).
  function imageres(id, size) { return graphics + "/imageres/" + (size || 32) + "/" + id + ".png" }
  function icon(id, size) { return graphics + "/shell32/" + (size || 32) + "/" + id + ".png" }
  // user32.dll message-box icons: information, warning, error, question.
  function sysIcon(kind, size) {
    var ids = { warning: 101, question: 102, error: 103, info: 104 }
    return graphics + "/user32/" + (size || 32) + "/" + (ids[kind] || 104) + ".png"
  }

  // Vista's system colours (the same in all four schemes; only the glass and
  // the taskbar differ): face = ButtonFace, highlight(Text) = Highlight(Text),
  // gray = GrayText, capText = the Basic caption text (black, no shadow:
  // capShadow transparent), frameL/frameB = Window.FrameLeft/FrameBottom
  // SizingMargins, groupText = Button.GroupBox TextColor, paneTop/paneBottom
  // and special*/normal* = the task pane (Vista has none: Control Panel's
  // light blue left pane), edit = Edit BorderColor, accent = Highlight,
  // instruction = TaskDialog main-instruction text.
  readonly property var vistaColours: ({
    face: "#F0F0F0", highlight: "#3399FF", highlightText: "#FFFFFF", gray: "#6D6D6D",
    capText: "#000000", capShadow: "#00000000", frameL: [2, 1, 91, 0], frameB: [2, 2, 0, 2],
    groupText: "#000000", paneTop: "#EEF3FA", paneBottom: "#D8E6F5",
    specialHead: "#1E395B", specialText: "#1E395B", normalHead: "#1E395B", normalText: "#0066CC",
    normalFill: "#FFFFFF", edit: "#ABADB3", accent: "#3399FF", instruction: "#003399"
  })
  readonly property var schemes: ({
    "windows-vista": vistaColours,
    "windows-vista-graphite": vistaColours,
    "windows-vista-frost": vistaColours,
    "windows-vista-basic": vistaColours
  })

  FileView {
    path: vista.stateHome + "/omarchy/current/theme.name"
    watchChanges: true
    blockLoading: true
    printErrors: false
    onLoaded: vista.themeName = String(text()).trim()
    onFileChanged: reload()
  }
}
