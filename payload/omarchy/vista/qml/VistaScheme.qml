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
  readonly property string artDir: artRoot + "/" + slug

  // InfoWindow / InfoText (hivedef.inf); the same in every scheme.
  readonly property color infoWindow: "#FFFFE1"
  readonly property color infoText: "#000000"

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

  // face = Btnface, highlight/highlightText = Highlight(Text), gray = GrayText,
  // capText/capShadow = CaptionText / [Window] TextShadowColor, frameL/frameB =
  // Window.FrameLeft/FrameBottom SizingMargins (l, r, t, b), groupText =
  // button.groupbox TextColor, paneTop/paneBottom = ExplorerBar gradient,
  // special*/normal* = ExplorerBar.{Special,Normal}Group{Head,Background}
  // TextColor (and the normal group's FillColor), edit = edit BorderColor,
  // accent = ActiveCaption.
  readonly property var schemes: ({
    "windows-vista":        { face: "#ECE9D8", highlight: "#316AC5", highlightText: "#FFFFFF", gray: "#ACA899",
                           capText: "#FFFFFF", capShadow: "#0A1883", frameL: [2, 2, 0, 0], frameB: [5, 5, 2, 2],
                           groupText: "#0046D5", paneTop: "#8CAAE6", paneBottom: "#6487DC",
                           specialHead: "#FFFFFF", specialText: "#265CC0", normalHead: "#215DC6", normalText: "#265CC0",
                           normalFill: "#D6DFF7", edit: "#7F9DB9", accent: "#0054E3" },
    "windows-vista-olive":  { face: "#ECE9D8", highlight: "#93A070", highlightText: "#FFFFFF", gray: "#ACA899",
                           capText: "#FFFFFF", capShadow: "#41400A", frameL: [2, 2, 0, 0], frameB: [5, 5, 2, 2],
                           groupText: "#99540A", paneTop: "#D3D9BC", paneBottom: "#AFB988",
                           specialHead: "#FFFFFF", specialText: "#265CC0", normalHead: "#294600", normalText: "#345800",
                           normalFill: "#EEF6E4", edit: "#A4B97F", accent: "#8BA169" },
    "windows-vista-silver": { face: "#E0DFE3", highlight: "#B2B4BF", highlightText: "#000000", gray: "#ACA899",
                           capText: "#0E1010", capShadow: "#C7C2D1", frameL: [1, 1, 0, 0], frameB: [5, 5, 1, 2],
                           groupText: "#0046D5", paneTop: "#E0E0DF", paneBottom: "#A6A4BA",
                           specialHead: "#FFFFFF", specialText: "#265CC0", normalHead: "#3E3C52", normalText: "#555367",
                           normalFill: "#F2F0FF", edit: "#A5ACB2", accent: "#C0C0C0" },
    "windows-vista-royale": { face: "#EBE9ED", highlight: "#335EA8", highlightText: "#FFFFFF", gray: "#A7A6AA",
                           capText: "#FFFFFF", capShadow: "#0A1883", frameL: [2, 1, 0, 0], frameB: [5, 5, 1, 2],
                           groupText: "#335EA8", paneTop: "#62A0E8", paneBottom: "#5372BE",
                           specialHead: "#FFFFFF", specialText: "#265CC0", normalHead: "#215DC6", normalText: "#265CC0",
                           normalFill: "#D6DFF7", edit: "#A7A6AA", accent: "#335EA8" },
    "windows-vista-zune":   { face: "#E2E2E2", highlight: "#BEBEBE", highlightText: "#000000", gray: "#646464",
                           capText: "#FFFFFF", capShadow: "#231814", frameL: [2, 1, 0, 0], frameB: [5, 5, 2, 2],
                           groupText: "#0046D5", paneTop: "#B4B4B4", paneBottom: "#969696",
                           specialHead: "#FFFFFF", specialText: "#6B6B6B", normalHead: "#6B6B6B", normalText: "#6B6B6B",
                           normalFill: "#E3E3E3", edit: "#969696", accent: "#343434" }
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
