import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import QtQuick.Layouts
import qs.Commons
import "../../vista/qml"
import qs.Commons as Commons
import qs.Ui
import "BarModel.js" as BarModel

Item {
  id: root

  // The omarchy-shell host injects omarchyPath from OMARCHY_PATH.
  property string omarchyPath: Quickshell.env("OMARCHY_PATH")
  // Injected by the host shell so bar slots can resolve enabled widgets.
  property var barWidgetRegistry: fallbackBarWidgetRegistry
  // Read-only registry view for third-party full bars; the built-in bar does
  // not otherwise need it, but declaring it keeps clone construction atomic.
  property var pluginRegistry: null
  // Injected by the host shell every time shell.json is reloaded. Holds the
  // `bar:` subtree: position, centerAnchor, layout. The host owns file IO;
  // the bar just renders whatever it's handed. The bar font follows the
  // OS-level fontconfig monospace binding — it is not stored in shell.json.
  property var barConfig: ({})
  // Injected by the host shell. Used for shell-wide actions such as opening
  // settings and persisting inline widget state.
  property var shell: null
  // Manifest for the active bar option. Present for custom bars and useful for
  // diagnostics; the built-in bar does not otherwise need it.
  property var manifest: null

  // ================================================================ Vista
  // ocko.vista-taskbar: a copy of /usr/share/omarchy/shell/plugins/bar/Bar.qml
  // (omarchy 4.0.6) with every host-facing function kept, and the layout
  // replaced by the Windows Vista taskbar. Vista-specific code is in this block,
  // applyBarConfig (layout transform), the `horizontalBar` component, and
  // the Xp*.qml files beside this one. Selected only while an Vista theme is
  // active (omarchy/vista/bin/vista-mode, step "shell").

  // Per-scheme values from aero.msstyles (assets/graphics/aero/props.json):
  // clock = TrayNotify::Clock TextColor, task = TaskBand::Toolbar TextColor
  // (white in both states); margins are SizingMargins (left, right, top,
  // bottom) of TaskBar::BACKGROUNDBOTTOM, TrayNotifyHoriz::TrayNotify
  // BACKGROUND and TaskBand::Toolbar BUTTON. art = the glass (Composited,
  // Aero) or basic (Vista Basic) set in assets/graphics/taskbar/.
  readonly property var vistaSchemes: ({
    "windows-vista":          { art: "glass", clock: "#FFFFFF", task: "#FFFFFF", taskChecked: "#FFFFFF",
                                taskbar: [0, 0, 15, 14], tray: [1, 1, 14, 15], button: [5, 5, 15, 13] },
    "windows-vista-graphite": { art: "glass", clock: "#FFFFFF", task: "#FFFFFF", taskChecked: "#FFFFFF",
                                taskbar: [0, 0, 15, 14], tray: [1, 1, 14, 15], button: [5, 5, 15, 13] },
    "windows-vista-frost":    { art: "glass", clock: "#FFFFFF", task: "#FFFFFF", taskChecked: "#FFFFFF",
                                taskbar: [0, 0, 15, 14], tray: [1, 1, 14, 15], button: [5, 5, 15, 13] },
    "windows-vista-basic":    { art: "basic", clock: "#FFFFFF", task: "#FFFFFF", taskChecked: "#FFFFFF",
                                taskbar: [0, 0, 15, 14], tray: [1, 1, 14, 15], button: [5, 5, 15, 13] }
  })
  // theme.name is rewritten in place by omarchy-theme-set, so the watch
  // survives it and switching Vista -> Olive restyles without a restart.
  property string vistaThemeName: ""
  readonly property string vistaTheme: vistaSchemes[vistaThemeName] ? vistaThemeName : "windows-vista"
  readonly property var vistaScheme: vistaSchemes[vistaTheme]
  readonly property string vistaArtRoot: "file://" + omarchyConfigDir + "/vista/assets/graphics/taskbar"
  readonly property string vistaArtDir: vistaArtRoot + "/" + vistaScheme.art
  // The Start orb's 42x40 circle sits 4 px down in its 60x46 frame (96 dpi)
  // and is centred on the 30 px taskbar, so its frame starts 9 px above the
  // bar: the bar window is that much taller, its exclusive zone is not, and
  // the input mask leaves the strip above the bar to the windows under it.
  readonly property int vistaOverhang: vertical || position !== "bottom" ? 0 : Style.space(9)

  FileView {
    path: root.stateHome + "/omarchy/current/theme.name"
    watchChanges: true
    blockLoading: true
    printErrors: false
    onLoaded: root.vistaThemeName = String(text()).trim()
    onFileChanged: reload()
  }

  // ---- Start menu (VistaStartMenu.qml, Task 7) ----
  // Name of the screen whose Start menu is open, "" when closed; the start
  // button on that screen draws pressed. Set by VistaStartMenu.
  property string vistaStartMenuScreen: ""
  function toggleStartMenu(screen) { vistaStartMenu.toggle(screen) }
  VistaStartMenu {
    id: vistaStartMenu
    bar: root
    theme: root.vistaTheme
    artDir: root.vistaArtDir
    artRoot: root.vistaArtRoot
  }
  function vistaFocusedScreen() {
    var name = focusedScreenName()
    var screens = Quickshell.screens
    for (var i = 0; i < screens.length; i++) if (screens[i].name === name) return screens[i]
    return screens.length ? screens[0] : null
  }
  IpcHandler {
    target: "vistastart"
    function toggle(): void { root.toggleStartMenu(root.vistaFocusedScreen()) }
    // Vista's "Shut Down Windows" dialog (the Vista menu's system route).
    function shutdown(): void { vistaStartMenu.showShutdown(root.vistaFocusedScreen()) }
    // Vista's Run dialog (All Programs > Accessories > Run...).
    function run(): void { vistaStartMenu.showRun(root.vistaFocusedScreen()) }
    function closeDialogs(): void { vistaStartMenu.closeDialogs() }
  }
  // The hyprbars minimise button (omarchy/vista/hypr/late.lua) calls this, so a
  // title-bar minimise records its origin like a taskbar click does.
  IpcHandler {
    target: "vistatask"
    function minimizeActive(): void { var w = vistaStartMenu.activeWindow(); if (w) root.vistaMinimise(w) }
  }

  // ---- Minimise (Hermes decision: Hyprland has none) ----
  // Minimised = moved silently to this special workspace. The origin
  // (workspace id, monitor) is kept here, keyed by toplevel address, so the
  // button stays on its own monitor's taskbar and restores to where it was.
  // In memory only: after a shell restart a minimised window restores to the
  // clicked monitor's current workspace and lists under the special
  // workspace's monitor.
  readonly property string vistaMinimizedWorkspace: "special:minimized"
  property var vistaOrigins: ({})
  // monitor name -> addresses Show Desktop minimised there.
  property var vistaDesktopHidden: ({})

  function vistaSelector(win) {
    var a = String(win.address)
    return "address:" + (a.indexOf("0x") === 0 ? a : "0x" + a)
  }
  function vistaDispatch(lua) { Hyprland.dispatch(lua) }
  function vistaIsMinimised(win) {
    return !!win.workspace && win.workspace.name === vistaMinimizedWorkspace
  }
  function vistaMonitorWorkspace(monitorName) {
    var mons = Hyprland.monitors.values
    for (var i = 0; i < mons.length; i++)
      if (mons[i].name === monitorName && mons[i].activeWorkspace) return String(mons[i].activeWorkspace.id)
    return ""
  }
  function vistaMinimise(win) {
    if (!win.workspace || vistaIsMinimised(win)) return
    var next = Object.assign({}, vistaOrigins)
    next[String(win.address)] = { workspace: String(win.workspace.id), monitor: win.monitor ? String(win.monitor.name) : "" }
    vistaOrigins = next
    vistaDispatch('hl.dsp.window.move({ workspace = "' + vistaMinimizedWorkspace + '", follow = false, window = "' + vistaSelector(win) + '" })')
  }
  function vistaRestore(win, monitorName, focus) {
    var key = String(win.address)
    var origin = vistaOrigins[key]
    var ws = origin ? origin.workspace : vistaMonitorWorkspace(monitorName)
    if (ws) vistaDispatch('hl.dsp.window.move({ workspace = "' + ws + '", follow = false, window = "' + vistaSelector(win) + '" })')
    if (focus) vistaDispatch('hl.dsp.focus({ window = "' + vistaSelector(win) + '" })')
    var next = Object.assign({}, vistaOrigins)
    delete next[key]
    vistaOrigins = next
  }
  // Task button click, as Vista: minimised -> restore and focus; focused ->
  // minimise; anything else -> focus (Hyprland switches workspace).
  function vistaActivate(win, monitorName) {
    if (vistaIsMinimised(win)) vistaRestore(win, monitorName, true)
    else if (win.activated) vistaMinimise(win)
    else vistaDispatch('hl.dsp.focus({ window = "' + vistaSelector(win) + '" })')
  }
  // Quick Launch "Show Desktop": minimise every window on the monitor's
  // current workspace; a second click restores the ones it hid.
  function vistaToggleDesktop(monitorName) {
    var next = Object.assign({}, vistaDesktopHidden)
    var hidden = next[monitorName] || []
    var list = Hyprland.toplevels.values
    var i
    if (hidden.length) {
      for (i = 0; i < list.length; i++)
        if (hidden.indexOf(String(list[i].address)) !== -1 && vistaIsMinimised(list[i])) vistaRestore(list[i], monitorName, false)
      delete next[monitorName]
    } else {
      var ws = vistaMonitorWorkspace(monitorName)
      var addrs = []
      for (i = 0; i < list.length; i++) {
        if (!list[i].workspace || String(list[i].workspace.id) !== ws) continue
        addrs.push(String(list[i].address))
        vistaMinimise(list[i])
      }
      if (addrs.length) next[monitorName] = addrs
    }
    vistaDesktopHidden = next
  }

  // The four entries the taskbar itself replaces, plus spacers. Everything
  // else in bar.layout, in shell.json order, goes to the notification area.
  readonly property var vistaReplaced: ["omarchy.menu", "omarchy.workspaces", "omarchy.active-window", "omarchy.clock", "omarchy.spacer"]
  // The configured clock entry; rendered invisibly under the Vista clock label
  // only to host its calendar panel.
  property var vistaClockEntry: ({ id: "omarchy.clock" })

  function vistaLayout(layout) {
    var tray = []
    var regions = ["left", "center", "right"]
    for (var r = 0; r < regions.length; r++) {
      var entries = layout[regions[r]] || []
      for (var i = 0; i < entries.length; i++) {
        var id = entryId(entries[i])
        if (id === "omarchy.clock") vistaClockEntry = vistaCloneEntry(entries[i], id)
        if (vistaReplaced.indexOf(id) === -1) tray.push(entries[i])
      }
    }
    // Pin before swapping in clone ids: pinTrayToInner looks for
    // "omarchy.tray", which the ocko.vista-tray entry no longer is. The chevron
    // then leads the notification area with the indicators right after it,
    // so hidden indicators reveal in one run with the drawer's icons.
    var pinned = pinTrayToInner(tray, "right")
    return { left: [], center: [], right: pinned.map(function(e) { return vistaCloneEntry(e, entryId(e)) }) }
  }

  // Omarchy's indicators hide behind the chevron, on or off (ocko: "hidden
  // until the arrow icon is clicked, like the other icons that are hidden").
  // Each monitor's tray drawer drives that monitor's stock indicators widget:
  // the widget shows only while the drawer is open, and its own
  // setIndicatorAreaHovered() reveals the inactive ones with it. The widget's
  // area HoverHandlers are switched off so the pointer can't fight the latch
  // (its buttons keep their hover). The tray is told how many indicators hide
  // behind it, so its chevron exists even with no tray apps. Not
  // centerSectionRevealHeld: that lives on this root, which every monitor's
  // bar shares.
  property var vistaIndicatorLinks: []
  function vistaLinkIndicators() {
    var wins = []
    for (var i = 0; i < moduleSlots.length; i++) {
      var slot = moduleSlots[i]
      var id = vistaStockIdOf(slot.moduleName)
      if (!slot.activeItem || (id !== "omarchy.tray" && id !== "omarchy.indicators")) continue
      var win = slot.QsWindow.window
      var rec = null
      for (var j = 0; j < wins.length; j++) if (wins[j].win === win) rec = wins[j]
      if (!rec) { rec = { win: win }; wins.push(rec) }
      rec[id === "omarchy.tray" ? "tray" : "inds"] = slot.activeItem
    }
    var links = []
    for (var k = 0; k < wins.length; k++) {
      var w = wins[k]
      if (!w.tray || !w.inds || !("vistaHiddenIndicators" in w.tray) || !("setIndicatorAreaHovered" in w.inds)) continue
      var kept = null
      for (var l = 0; l < vistaIndicatorLinks.length; l++)
        if (vistaIndicatorLinks[l].tray === w.tray && vistaIndicatorLinks[l].inds === w.inds) kept = vistaIndicatorLinks[l]
      links.push(kept || vistaLink(w.tray, w.inds))
    }
    vistaIndicatorLinks = links
  }
  function vistaLink(tray, inds) {
    vistaQuietIndicatorHover(inds)
    tray.vistaHiddenIndicators = Qt.binding(function() { return inds.indicatorEntries.length })
    inds.visible = Qt.binding(function() { return tray.expanded })
    var follow = function() { inds.setIndicatorAreaHovered(tray.expanded) }
    tray.expandedChanged.connect(follow)
    follow()
    return { tray: tray, inds: inds }
  }
  // Indicators.qml's area HoverHandlers sit on its root, the loaded tree,
  // its Row and the inactive area; the indicator blocks (indicatorsModule)
  // are left alone.
  function vistaQuietIndicatorHover(inds) {
    var walk = function(o, depth) {
      var kids = o && o.data ? o.data : []
      for (var i = 0; i < kids.length; i++) {
        var c = kids[i]
        if (!c || "indicatorsModule" in c) continue
        if ("acceptedDevices" in c && "hovered" in c) c.enabled = false
        else if (depth < 6) walk(c, depth + 1)
      }
    }
    walk(inds, 0)
  }

  // Vista copies of first-party bar widgets, stock id -> clone id. vista-mode
  // (VISTA_WIDGET_CLONES) enables them without disabling the stock widget, so
  // bar.layout keeps the stock id and every other bar still loads the stock
  // widget; here an enabled clone takes the stock entry's place. Settings
  // stay on the entry, and `omarchy-shell shell toggle omarchy.<id>` reaches
  // the clone through the shell's resolveEnabledId() (manifest
  // omarchy.clonedFrom). The registry view a plugin bar gets says neither
  // what is enabled nor what is a clone, hence this list: a clone counts
  // only while it is registered, which is only while it is enabled.
  readonly property var vistaWidgetClones: ({
    "omarchy.monitor": "ocko.vista-monitor",
    "omarchy.audio": "ocko.vista-audio",
    "omarchy.network": "ocko.vista-network",
    "omarchy.clock": "ocko.vista-clock",
    "omarchy.tray": "ocko.vista-tray",
    "omarchy.power": "ocko.vista-power",
    "omarchy.weather": "ocko.vista-weather",
    "omarchy.bluetooth": "ocko.vista-bluetooth",
    "omarchy.agents": "ocko.vista-agents"
  })
  // Plugins register after the first layout pass, so rebuild the layout when
  // the set of live clones changes.
  readonly property string vistaLiveClones: {
    var w = barWidgetRegistry.widgets
    var live = []
    for (var stock in vistaWidgetClones) if (w[vistaWidgetClones[stock]]) live.push(vistaWidgetClones[stock])
    return live.join(" ")
  }
  onVistaLiveClonesChanged: Qt.callLater(applyBarConfig)

  // A layout entry may name the user's own clone of a stock widget
  // (you.power, cloned from omarchy.power): Vista's clone replaces that
  // too. vista-mode writes every installed plugin's omarchy.clonedFrom to
  // clones.json, because the registry view a plugin bar gets does not show
  // other manifests.
  property var vistaClonedFrom: ({})
  FileView {
    path: root.stateHome + "/omarchy/vista/clones.json"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: {
      try { root.vistaClonedFrom = JSON.parse(text()) || {} } catch (e) { root.vistaClonedFrom = {} }
    }
  }

  function vistaCloneId(id) {
    var clone = vistaWidgetClones[id] || vistaWidgetClones[vistaClonedFrom[id] || ""]
    return clone && barWidgetRegistry.widgets[clone] ? clone : id
  }

  function vistaIsClone(id) {
    return vistaStockIdOf(id) !== id
  }

  // The stock id a clone stands in for; any other id unchanged.
  function vistaStockIdOf(id) {
    for (var stock in vistaWidgetClones) if (vistaWidgetClones[stock] === id) return stock
    return id
  }

  function vistaCloneEntry(entry, id) {
    var clone = vistaCloneId(id)
    if (clone === id) return entry
    var copy = entry !== null && typeof entry === "object" ? JSON.parse(JSON.stringify(entry)) : {}
    copy.id = clone
    return copy
  }

  // Notification-area art. Every hosted stock widget draws its glyph through
  // a qs.Ui BarIconButton; vistaSkinTray() gives each one an iconComponent that
  // picks Vista art from the glyph the widget is showing right now, so state
  // (muted, disconnected, ...) follows the widget for free. Glyphs not listed
  // keep the stock rendering. "<lib>/<id>" = an icon group of that Vista file
  // at 32 (else 16) px, from bin/vista-art: sndvolsso = SndVolSSO.dll (volume),
  // pnidui = pnidui.dll (network), bthprops = bthprops.cpl (Bluetooth),
  // imageres = imageres.dll; "battery/<n>" = a batmeter.dll frame (ASSETS.md).
  readonly property string vistaGraphics: "file://" + omarchyConfigDir + "/vista/assets/graphics/"
  readonly property var vistaTrayArt: ({
    "\uf028": "sndvolsso/124",         // audio: volume high
    "\uf027": "sndvolsso/123",         //        medium
    "\uf026": "sndvolsso/122",         //        low
    "\u{F02CB}": "sndvolsso/124",      //        headphones
    "\ueee8": "sndvolsso/120",         //        muted, or no output
    "\u{F0200}": "pnidui/3048",        // network: wired, Internet access
    "\u{F092E}": "pnidui/3020",        //          disconnected
    "\u{F092F}": "pnidui/3021",        //          wireless, by strength
    "\u{F091F}": "pnidui/3022",
    "\u{F0922}": "pnidui/3024",
    "\u{F0925}": "pnidui/3025",
    "\u{F0928}": "pnidui/3026",
    "\u{F00AF}": "bthprops/151",       // bluetooth on
    "\u{F00B1}": "bthprops/151",       //           connected
    "\u{F00B2}": "bthprops/151",       //           off (drawn dimmed)
    "\uf021": "imageres/104",          // system update: the Windows Update shield
    "\u{F009B}": "imageres/105",       // do not disturb: the red shield
    // Battery (stock power/Model.js batteryIcon): batmeter frames by charge;
    // ocko.vista-power's vistaBatteryFrame, when there, overrides these.
    "\u{F007A}": "battery/0", "\u{F007B}": "battery/1", "\u{F007C}": "battery/2",
    "\u{F007D}": "battery/3", "\u{F007E}": "battery/4", "\u{F007F}": "battery/5",
    "\u{F0080}": "battery/6", "\u{F0081}": "battery/7", "\u{F0082}": "battery/8",
    "\u{F0079}": "battery/9",
    "\u{F089C}": "battery/19", "\u{F0086}": "battery/20", "\u{F0087}": "battery/21",
    "\u{F0088}": "battery/22", "\u{F089D}": "battery/23", "\u{F0089}": "battery/24",
    "\u{F089E}": "battery/25", "\u{F008A}": "battery/26", "\u{F008B}": "battery/27",
    "\u{F0085}": "battery/42",         // fully charged
    "\uf053": "chevron"                 // tray drawer
  })
  // Drawn at half opacity, as Vista draws a disabled tray icon.
  readonly property var vistaTrayArtDim: ["\u{F00B2}"]

  // The art key of a tray button's text: the token after its last space.
  // The power widget shows "58% <glyph>" while the percentage is on.
  function vistaTrayKey(text) {
    var t = String(text || "")
    return t.slice(t.lastIndexOf(" ") + 1)
  }
  // The "58% " in front of the glyph, or "".
  function vistaTrayPrefix(text) {
    var t = String(text || "")
    return t.slice(0, t.lastIndexOf(" ") + 1).trim()
  }

  function vistaTrayArtUrl(glyph, hovered, muted, trayOpen, size, battery) {
    var art = vistaTrayArt[String(glyph || "")]
    if (!art) return ""
    if (art === "chevron") return vistaArtDir + (trayOpen ? "/chevron-open-" : "/chevron-") + (hovered ? 1 : 0) + ".png"
    if (muted && art.indexOf("sndvolsso/") === 0) art = "sndvolsso/120"
    if (art.indexOf("battery/") === 0) {
      if (battery >= 0) art = "battery/" + battery
      return vistaGraphics + "taskbar/" + art + ".png"
    }
    var slash = art.indexOf("/")
    return vistaGraphics + art.slice(0, slash) + "/" + size + art.slice(slash) + ".png"
  }

  function vistaSkinTray(item) {
    if (!item) return
    if ("iconComponent" in item && "opticalSize" in item) {
      item.iconComponent = Qt.binding(function() { return root.vistaTrayArt[root.vistaTrayKey(item.text)] ? vistaTrayIcon : null })
      if (item.text === "\uf053") vistaLatchChevron(item)
      return
    }
    var kids = item.children || []
    for (var i = 0; i < kids.length; i++) vistaSkinTray(kids[i])
  }

  // Vista's chevron latches: a click opens the drawer, another closes it, and
  // the pointer leaving does not. Stock Tray sets `expanded` from a
  // HoverHandler on the chevron's parent (Tray.qml:264, :346); switch that
  // off and toggle from the chevron's left press instead. A still-enabled
  // handler means "not latched yet", so re-skinning stays idempotent. The
  // stock bar never runs this and keeps hover reveal.
  function vistaLatchChevron(button) {
    var area = button.parent
    var objs = area ? area.data : []
    for (var i = 0; i < objs.length; i++) {
      var h = objs[i]
      if (!h || !("acceptedDevices" in h) || !("hovered" in h) || !h.enabled) continue
      h.enabled = false
      var tray = area
      while (tray && !("trayItemExtent" in tray)) tray = tray.parent
      if (tray) button.pressed.connect(function(b) { if (b === Qt.LeftButton) tray.expanded = !tray.expanded })
    }
  }

  // Loaded into BarIconButton's optical canvas: Loader > canvas > button.
  Component {
    id: vistaTrayIcon

    Item {
      readonly property var button: parent && parent.parent ? parent.parent.parent : null
      readonly property bool chevron: !!button && button.text === "\uf053"
      // The stock Tray widget that owns the chevron, for its drawer state.
      readonly property var tray: {
        var p = chevron ? button.parent : null
        while (p && !("trayItemExtent" in p)) p = p.parent
        return p
      }

      // 32, then 16 when the 32 px export is missing, then the glyph below.
      property int artSize: 32
      readonly property string glyph: button ? root.vistaTrayKey(button.text) : ""
      readonly property string prefix: button ? root.vistaTrayPrefix(button.text) : ""
      // ocko.vista-power's battery state, -1 elsewhere.
      readonly property int battery: button && button.parent && typeof button.parent.vistaBatteryFrame === "number"
        ? button.parent.vistaBatteryFrame : -1
      onGlyphChanged: artSize = 32

      Image {
        id: vistaTrayImage
        anchors.centerIn: parent
        // With a "58%" label the button is two slots wide (stock doubles
        // slotSize); the canvas stays centred, so the icon moves right.
        anchors.horizontalCenterOffset: parent.prefix !== "" && parent.button ? parent.button.slotSize / 4 : 0
        width: Style.space(parent.chevron ? 19 : 16)
        height: Style.space(parent.chevron ? 20 : 16)
        // The chevron is cut at its drawn size; the icons are decoded at full
        // size and mipmapped down, so 32 px art lands sharp at ~21 px.
        sourceSize: parent.chevron ? Qt.size(width, height) : undefined
        smooth: true
        mipmap: !parent.chevron
        opacity: root.vistaTrayArtDim.indexOf(parent.glyph) !== -1 ? 0.5 : 1
        source: parent.button ? root.vistaTrayArtUrl(parent.glyph, parent.button.tooltipHovered,
                                                  !!parent.button.parent && parent.button.parent.outputMuted === true,
                                                  !!parent.tray && parent.tray.expanded === true, parent.artSize,
                                                  parent.battery) : ""
        onStatusChanged: if (status === Image.Error && parent.artSize === 32) parent.artSize = 16
      }

      // "58%" left of the battery, in the clock's font and colour.
      Text {
        visible: parent.prefix !== "" && vistaTrayImage.status !== Image.Error
        anchors.right: vistaTrayImage.left
        anchors.rightMargin: Style.space(3)
        anchors.verticalCenter: vistaTrayImage.verticalCenter
        text: parent.prefix
        color: root.vistaScheme.clock
        font.family: "Segoe UI"
        font.pixelSize: Style.font.bodySmall
      }

      // Art missing on disk (assets are git-ignored): draw the stock glyph.
      Text {
        anchors.centerIn: parent
        visible: vistaTrayImage.status === Image.Error && !!parent.button
        text: parent.button ? parent.button.text : ""
        font.family: parent.button ? parent.button.fontFamily : ""
        font.pixelSize: parent.button ? parent.button.fontSize : Style.bar.iconFont
        color: parent.button ? parent.button.foreground : "black"
      }
    }
  }
  // ============================================================== /Vista

  QtObject {
    id: fallbackBarWidgetRegistry
    property var widgets: ({})
    property int revision: 0
    function metadataFor(id) { return null }
  }
  // Mirrors the on-disk `bar-off` flag so the user can hide the bar without
  // killing the entire shell. Hidden panels stay mapped but park off-screen
  // without an exclusion zone; updated by the FileView watcher further down.
  property bool barHidden: false
  property string home: Quickshell.env("HOME")
  property string stateHome: home + "/.local/state"
  property string omarchyConfigDir: home + "/.config/omarchy"
  property var fallbackBarConfig: ({
    position: "top",
    transparent: false,
    centerAnchor: "omarchy.clock",
    layout: { left: [], center: [], right: [] }
  })
  property var layoutConfig: fallbackBarConfig.layout
  property string centerAnchor: ""
  property bool requestedTransparent: false
  property bool useTransparentForeground: false
  property bool transparent: false
  property bool centerSectionHovered: false
  // One bar surface exists per monitor and each reports into this count, so a
  // pointer crossing from one monitor's bar to another's stays counted however
  // the enter and leave interleave. A single shared bool would be left false by
  // whichever event landed last.
  property int barHoverCount: 0
  // True while the pointer is over any bar, widgets included.
  readonly property bool barHovered: barHoverCount > 0
  property bool centerSectionRevealHeld: false
  property bool centerHoverRevealSuppressed: false
  property int barConfigSerial: 0
  property string position: "top"
  // Resolves through fontconfig at paint time (Style.font.family defaults
  // to "monospace"), so changing the system font (via `omarchy-font-set`)
  // updates the bar without a reload.
  // Vista: notification-area text is Segoe UI, like TrayNotify::Clock; Nerd
  // glyphs fall back per glyph through fontconfig.

  property string fontFamily: "Segoe UI"
  // Bound to the central Color singleton so the bar tracks shell.toml's
  // [bar] section. Property names kept for the rest of this file's bindings.
  // Vista: tray widgets draw in the scheme's clock colour (dark on the light
  // Olive/Silver/Royale notification areas, white on Blue/Zune).
  property color themeForeground: vistaScheme.clock
  property color themeContrastForeground: Commons.Color.background
  property color transparentForeground: themeForeground
  property color foreground: themeForeground
  property color barForeground: useTransparentForeground ? transparentForeground : themeForeground
  property bool foregroundAnimationEnabled: true
  property color background: Commons.Color.bar.background
  property color urgent: Commons.Color.bar.active

  Behavior on barForeground { enabled: root.foregroundAnimationEnabled; ColorAnimation { duration: 420; easing.type: Easing.InOutCubic } }
  Behavior on background { ColorAnimation { duration: 420; easing.type: Easing.InOutCubic } }
  Behavior on urgent { ColorAnimation { duration: 420; easing.type: Easing.InOutCubic } }
  property var tooltipTarget: null
  property var pendingTooltipTarget: null
  property string tooltipText: ""
  property string pendingTooltipText: ""
  property bool tooltipShown: false
  property int tooltipRequest: 0
  property var activePopout: null
  property var barDragSource: null
  property var barDragTarget: null
  property var barDragTargetGeometry: null
  property bool barDragAfter: false
  property var barDragWindow: null
  property var barDragScreen: null
  property url barDragImageUrl: ""
  property real barDragSceneX: 0
  property real barDragSceneY: 0
  property real barDragScreenX: 0
  property real barDragScreenY: 0
  property real barDragOffsetX: 0
  property real barDragOffsetY: 0
  property bool barMoveActive: false
  property string barMoveCandidate: ""
  property var barMoveWindow: null
  property var barMoveScreen: null
  property var clickTargets: []
  property var moduleSlots: []
  property var pluginBarApis: ({})
  // target -> { target, pluginId, clickTarget, popout }. Keyed by object so a
  // registration edits one entry in place instead of copying and rescanning an
  // array in QML; Qt's Map still finds a key by a native linear scan.
  readonly property var pluginObjectOwners: new Map()
  property bool pluginBarApiSyncQueued: false

  Component {
    id: pluginBarApiComponent
    PluginBarApi { }
  }

  function publicLayoutConfig() {
    return JSON.parse(JSON.stringify(root.layoutConfig || {}))
  }

  function bindPluginBarApi(api) {
    if (!api) return
    api.foreground = Qt.binding(function() { return root.foreground })
    api.barForeground = Qt.binding(function() { return root.barForeground })
    api.background = Qt.binding(function() { return root.background })
    api.urgent = Qt.binding(function() { return root.urgent })
    api.fontFamily = Qt.binding(function() { return root.fontFamily })
    api.position = Qt.binding(function() { return root.position })
    api.vertical = Qt.binding(function() { return root.vertical })
    api.barSize = Qt.binding(function() { return root.barSize })
    api.transparent = Qt.binding(function() { return root.transparent })
    api.foregroundAnimationEnabled = Qt.binding(function() { return root.foregroundAnimationEnabled })
    api.centerSectionRevealHeld = Qt.binding(function() { return root.centerSectionRevealHeld })
    api._centerHoverRevealSuppressed = Qt.binding(function() { return root.centerHoverRevealSuppressed })
    root.syncPluginBarApiObjects(api)
  }

  // Each api keeps its own detached copy of the layout. A flush serialises
  // the layout once and passes the string in so it is not re-serialised for
  // every plugin.
  function syncPluginBarApiObjects(api, layoutSnapshot) {
    if (!api) return
    api.activePopout = root.pluginOwnsBarObject(api.pluginId, root.activePopout)
      ? root.activePopout : (root.activePopout ? api.foreignPopoutMarker : null)
    api.clickTargets = root.pluginClickTargets(api.pluginId)
    api.layoutConfig = layoutSnapshot !== undefined
      ? JSON.parse(layoutSnapshot) : root.publicLayoutConfig()
  }

  function pluginObjectRecord(target) {
    return target ? (pluginObjectOwners.get(target) || null) : null
  }

  function markPluginObject(pluginId, target, role) {
    var key = String(pluginId || "")
    if (!key || !target) return false
    var record = root.pluginObjectRecord(target)
    if (record && record.pluginId !== key) return false
    if (!record) {
      record = { target: target, pluginId: key, clickTarget: false, popout: false }
      pluginObjectOwners.set(target, record)
    }
    record[role] = true
    return true
  }

  function unmarkPluginObject(pluginId, target, role) {
    var key = String(pluginId || "")
    var record = root.pluginObjectRecord(target)
    if (!record || record.pluginId !== key) return
    record[role] = false
    if (!record.clickTarget && !record.popout) pluginObjectOwners.delete(target)
  }

  function pluginOwnsBarObject(pluginId, target) {
    var record = target ? root.pluginObjectRecord(target) : null
    return !!record && record.pluginId === String(pluginId || "")
  }

  function pluginClickTargets(pluginId) {
    var out = []
    for (var i = 0; i < root.clickTargets.length; i++) {
      var target = root.clickTargets[i]
      if (root.pluginOwnsBarObject(pluginId, target)) out.push(target)
    }
    return out
  }

  // Every click target registration, popout change and layout change used to
  // resync every plugin api synchronously. Startup alone is hundreds of
  // registrations, each walking every api and every target, so coalesce them
  // into one resync per event-loop turn (as onModuleSlotsChanged already does
  // for prunePluginBarApis). bindPluginBarApi still syncs a brand-new api
  // directly so a widget never sees an empty api on its first read.
  function schedulePluginBarApiSync() {
    if (pluginBarApiSyncQueued) return
    pluginBarApiSyncQueued = true
    Qt.callLater(root.syncAllPluginBarApiObjects)
  }

  function syncAllPluginBarApiObjects() {
    pluginBarApiSyncQueued = false
    var layoutSnapshot = JSON.stringify(root.layoutConfig || {})
    for (var id in pluginBarApis) {
      var api = pluginBarApis[id]
      if (api) root.syncPluginBarApiObjects(api, layoutSnapshot)
    }
  }

  function registerPluginClickTarget(pluginId, target) {
    if (!root.markPluginObject(pluginId, target, "clickTarget")) return
    root.registerClickTarget(target)
  }

  function unregisterPluginClickTarget(pluginId, target) {
    if (!root.pluginOwnsBarObject(pluginId, target)) return
    root.unregisterClickTarget(target)
    root.unmarkPluginObject(pluginId, target, "clickTarget")
  }

  // A plugin may read api.activePopout right after asking for its popout, so
  // its own api is brought up to date inline; everyone else waits for the
  // coalesced resync.
  function requestPluginPopout(pluginId, owner) {
    if (!root.markPluginObject(pluginId, owner, "popout")) return
    root.requestPopout(owner)
    root.syncPluginBarApiObjects(pluginBarApis[String(pluginId || "")])
  }

  function releasePluginPopout(pluginId, owner) {
    if (!root.pluginOwnsBarObject(pluginId, owner)) return
    root.releasePopout(owner)
    root.unmarkPluginObject(pluginId, owner, "popout")
    root.syncPluginBarApiObjects(pluginBarApis[String(pluginId || "")])
  }

  function pluginBarApiFor(pluginId, moduleName, registered) {
    var key = String(pluginId || "")
    if (!key) return null

    var pluginShell = null
    if (registered && root.shell && typeof root.shell.pluginShellForId === "function") {
      // Only the trusted built-in bar receives ShellRoot and can request a
      // service-capable facade for the widget it is instantiating.
      pluginShell = root.shell.pluginShellForId(moduleName)
    } else if (root.shell && typeof root.shell.pluginShellForBarEntry === "function") {
      // Replacement bars receive a service-less entry facade. Giving an
      // untrusted bar a generic facade factory would let it retrieve another
      // third-party plugin's live service object.
      pluginShell = root.shell.pluginShellForBarEntry(key, moduleName)
    }

    if (pluginBarApis[key]) {
      pluginBarApis[key].shell = pluginShell
      return pluginBarApis[key]
    }

    var api = pluginBarApiComponent.createObject(null, {
      pluginId: key,
      moduleName: String(moduleName || ""),
      shell: pluginShell,
      _showTooltip: function(target, text) { root.showTooltip(target, text) },
      _hideTooltip: function(target) { root.hideTooltip(target) },
      _registerClickTarget: function(target) { root.registerPluginClickTarget(key, target) },
      _unregisterClickTarget: function(target) { root.unregisterPluginClickTarget(key, target) },
      _requestPopout: function(owner) { root.requestPluginPopout(key, owner) },
      _releasePopout: function(owner) { root.releasePluginPopout(key, owner) },
      _switchPanelFrom: function(owner, direction) { return root.switchPanelFrom(owner, direction) },
      _targetBelongsToWindow: function(target, window) { return root.targetBelongsToWindow(target, window) },
      _moduleWidgets: function(requestedId) {
        return String(requestedId || "") === String(moduleName || "")
          ? root.moduleWidgets(moduleName) : []
      },
      _run: function(command) { root.run(command) },
      _setCenterHoverRevealSuppressed: function(value) {
        root.centerHoverRevealSuppressed = !!value
      }
    })
    if (!api) return null
    root.bindPluginBarApi(api)

    var next = ({})
    for (var id in pluginBarApis) next[id] = pluginBarApis[id]
    next[key] = api
    pluginBarApis = next
    return api
  }

  function pluginBarApiUsed(pluginId) {
    for (var i = 0; i < moduleSlots.length; i++) {
      var slot = moduleSlots[i]
      if (slot && slot.pluginApiId === pluginId) return true
    }
    return false
  }

  function releasePluginObjects(pluginId) {
    var owned = Array.from(pluginObjectOwners.values())
    for (var i = 0; i < owned.length; i++) {
      var record = owned[i]
      if (!record || record.pluginId !== pluginId) continue
      if (record.clickTarget) root.unregisterClickTarget(record.target)
      if (record.popout && root.activePopout === record.target) root.releasePopout(record.target)
      pluginObjectOwners.delete(record.target)
    }
  }

  function prunePluginBarApis() {
    var next = ({})
    for (var id in pluginBarApis) {
      var api = pluginBarApis[id]
      if (root.pluginBarApiUsed(id)) {
        next[id] = api
        continue
      }
      root.releasePluginObjects(id)
      if (api && typeof api.destroy === "function") api.destroy()
    }
    pluginBarApis = next
  }

  onActivePopoutChanged: schedulePluginBarApiSync()
  onClickTargetsChanged: schedulePluginBarApiSync()
  onLayoutConfigChanged: schedulePluginBarApiSync()
  onModuleSlotsChanged: Qt.callLater(prunePluginBarApis)

  Component.onDestruction: {
    for (var id in pluginBarApis) {
      root.releasePluginObjects(id)
      if (pluginBarApis[id] && typeof pluginBarApis[id].destroy === "function")
        pluginBarApis[id].destroy()
    }
    pluginBarApis = ({})
  }

  function registerClickTarget(target) {
    if (!target || clickTargets.indexOf(target) !== -1) return
    var next = clickTargets.slice()
    next.push(target)
    clickTargets = next
  }

  function unregisterClickTarget(target) {
    var next = clickTargets.filter(function(item) { return item !== target })
    clickTargets = next
  }

  function registerModuleSlot(slot) {
    if (!slot || moduleSlots.indexOf(slot) !== -1) return
    var next = moduleSlots.slice()
    next.push(slot)
    moduleSlots = next
  }

  function unregisterModuleSlot(slot) {
    var next = moduleSlots.filter(function(item) { return item !== slot })
    moduleSlots = next
  }

  function debugBarGeometry() {
    var out = []
    for (var i = 0; i < moduleSlots.length; i++) {
      var slot = moduleSlots[i]
      if (!slot || !slot.activeItem) continue
      var point = { x: slot.x, y: slot.y }
      try {
        point = slot.mapToItem(null, 0, 0)
      } catch (e) {
      }
      out.push({
        id: slot.moduleName,
        section: slot.region,
        x: Math.round(point.x),
        y: Math.round(point.y),
        width: Math.round(slot.width),
        height: Math.round(slot.height),
        visible: slot.visible === true && slot.width > 0 && slot.height > 0,
        itemVisible: slot.activeItem.visible === true,
        itemWidth: Math.round(slot.activeItem.implicitWidth || 0),
        itemHeight: Math.round(slot.activeItem.implicitHeight || 0)
      })
    }
    return out
  }

  function targetWindow(target) {
    return target && target.QsWindow ? target.QsWindow.window : null
  }

  function targetBelongsToWindow(target, window) {
    return !!target && !!window && targetWindow(target) === window
  }

  function slotWindow(slot) {
    if (!slot) return null
    return targetWindow(slot.activeItem) || targetWindow(slot)
  }

  function sameWindow(left, right) {
    if (!left || !right) return false
    if (left === right) return true
    return !!left.screen && !!right.screen && !!left.screen.name && !!right.screen.name && left.screen.name === right.screen.name
  }

  function targetTooltipHovered(target) {
    return !!target && target.visible !== false && target.opacity !== 0 && target.tooltipHovered === true
  }

  function clearTooltip() {
    tooltipTimer.stop()
    pendingTooltipTarget = null
    pendingTooltipText = ""
    tooltipTarget = null
    tooltipText = ""
    tooltipShown = false
  }

  function clearBarDrag() {
    barDragSource = null
    barDragWindow = null
    barDragScreen = null
    barDragImageUrl = ""
    barDragTarget = null
    barDragTargetGeometry = null
    barDragAfter = false
    barDragSceneX = 0
    barDragSceneY = 0
    barDragScreenX = 0
    barDragScreenY = 0
    barDragOffsetX = 0
    barDragOffsetY = 0
  }

  function windowScreenPoint(scenePoint, window) {
    var x = scenePoint ? scenePoint.x : 0
    var y = scenePoint ? scenePoint.y : 0
    if (!window || !window.screen) return { x: x, y: y }

    if (root.position === "bottom")
      y += Math.max(0, window.screen.height - window.height)
    else if (root.position === "right")
      x += Math.max(0, window.screen.width - window.width)

    return { x: x, y: y }
  }

  function barDragScreenPoint(scenePoint) {
    return windowScreenPoint(scenePoint, barDragWindow)
  }

  function dropMarkerRect(slot, after) {
    if (!slot) return null

    try {
      var slotPoint = slot.mapToItem(null, 0, 0)
      var screenPoint = barDragScreenPoint(slotPoint)
      var thickness = Style.spacing.xs
      if (vertical) {
        return {
          x: screenPoint.x,
          y: screenPoint.y + (after ? slot.height : 0) - thickness / 2,
          width: slot.width,
          height: thickness
        }
      }

      return {
        x: screenPoint.x + (after ? slot.width : 0) - thickness / 2,
        y: screenPoint.y,
        width: thickness,
        height: slot.height
      }
    } catch (e) {
      return null
    }
  }

  // Split the screen along its diagonals (in normalized space, so widescreens
  // don't bias toward left/right): whichever triangle holds the cursor names
  // the candidate edge.
  function nearestScreenEdge(point, screen) {
    var nx = screen.width > 0 ? Util.clamp(point.x / screen.width, 0, 1) : 0.5
    var ny = screen.height > 0 ? Util.clamp(point.y / screen.height, 0, 1) : 0.5

    var edge = "top"
    var best = ny
    if (1 - ny < best) { edge = "bottom"; best = 1 - ny }
    if (nx < best) { edge = "left"; best = nx }
    if (1 - nx < best) { edge = "right"; best = 1 - nx }
    return edge
  }

  function beginBarMove(window) {
    barMoveWindow = window
    barMoveScreen = window ? window.screen : null
    barMoveCandidate = position
    barMoveActive = true
  }

  function updateBarMove(screenPoint) {
    if (!barMoveActive || !barMoveScreen) return
    barMoveCandidate = nearestScreenEdge(screenPoint, barMoveScreen)
  }

  function clearBarMove() {
    barMoveActive = false
    barMoveCandidate = ""
    barMoveWindow = null
    barMoveScreen = null
  }

  function finishBarMove() {
    var edge = barMoveCandidate
    if (!barMoveActive || !edge || edge === position) {
      clearBarMove()
      return
    }

    clearBarMove()
    setBarPosition(edge)
  }

  function setBarPosition(value) {
    var next = normalizePosition(value)
    if (root.shell && typeof root.shell.mutateShellConfig === "function") {
      root.shell.mutateShellConfig(function(config) {
        if (!Util.isPlainObject(config.bar)) config.bar = {}
        config.bar.position = next
      })
    } else {
      root.position = next
    }
  }

  function captureBarDragGhost(slot) {
    var item = slot && slot.activeItem ? slot.activeItem : null
    barDragImageUrl = ""
    if (!item || typeof item.grabToImage !== "function") return

    var grabWidth = Math.max(1, Math.ceil(item.width || item.implicitWidth || slot.width || 1))
    var grabHeight = Math.max(1, Math.ceil(item.height || item.implicitHeight || slot.height || 1))
    item.grabToImage(function(result) {
      if (root.barDragSource !== slot || !result || !result.url) return
      root.barDragImageUrl = result.url
    }, Qt.size(grabWidth, grabHeight))
  }

  function requestPopout(owner) {
    if (activePopout === owner) return
    if (activePopout) {
      if ("closeForPopoutSwitch" in activePopout) activePopout.closeForPopoutSwitch()
      else if ("close" in activePopout) activePopout.close()
    }
    activePopout = owner
  }

  function releasePopout(owner) {
    if (activePopout === owner) activePopout = null
  }

  readonly property bool vertical: position === "left" || position === "right"
  // Vista: the taskbar is 30 px at 96 dpi.
  readonly property int barSize: Style.space(30)

  function normalizePosition(value) {
    return BarModel.normalizePosition(value)
  }

  // Apply tray-pinning on top of the shared layout normalization so the
  // bar host and scriptable config helpers can't drift on entry shape.
  function normalizeLayout(layout) {
    var normalized = Util.normalizeLayout(Util.isPlainObject(layout) ? layout : fallbackBarConfig.layout)
    return {
      left:   pinTrayToInner(normalized.left,   "left"),
      center: pinTrayToInner(normalized.center, "center"),
      right:  pinTrayToInner(normalized.right,  "right")
    }
  }

  // The tray drawer reveals inward (away from the bar edge). Place it at the
  // section's inner edge: start of the right section, end of the left/center
  // sections. The drawer's reserved space then sits next to the bar center,
  // not stranded mid-section.
  function pinTrayToInner(entries, section) {
    return BarModel.pinTrayToInner(entries, section)
  }

  function applyBarConfig() {
    var config = Util.isPlainObject(barConfig) ? barConfig : fallbackBarConfig

    // Vista: always an opaque bottom taskbar; no center anchor.
    position = "bottom"
    setRequestedTransparency(false)
    centerAnchor = ""

    // layoutEntries feeds plain JS arrays to the module Repeaters, and QML
    // cannot diff those: reassigning layoutConfig rebuilds every widget on
    // every monitor. When a shell.json write only changed inline widget
    // settings, patch the live layout and running widgets in place instead.
    var next = vistaLayout(normalizeLayout(config.layout))
    var delta = BarModel.inlineSettingsDelta(layoutConfig, next)
    if (delta) {
      applySettingsDelta(delta)
      return
    }
    layoutConfig = next
    barConfigSerial++
  }

  function applySettingsDelta(delta) {
    for (var i = 0; i < delta.length; i++) {
      var change = delta[i]
      layoutConfig[change.region][change.index] = change.entry
      var settings = entrySettings(change.entry)
      for (var s = 0; s < moduleSlots.length; s++) {
        var slot = moduleSlots[s]
        if (!slot || slot.region !== change.region || slot.moduleName !== entryId(change.entry)) continue
        var item = slot.activeItem
        if (item && "settings" in item) item.settings = settings
      }
    }
  }

  onBarConfigChanged: applyBarConfig()

  function layoutEntries(region) {
    var serial = barConfigSerial
    var entries = layoutConfig ? layoutConfig[region] : null
    return Array.isArray(entries) ? entries : []
  }

  // Tab order for the panels in one bar region. Scoped to a single bar surface
  // so tabbing walks the bar the open panel belongs to instead of hopping the
  // panel to another monitor's copy of the same widget.
  function panelNavigationSlots(region, window) {
    var entries = layoutEntries(region)
    var slots = []
    for (var i = 0; i < entries.length; i++) {
      var id = entryId(entries[i])
      for (var j = 0; j < moduleSlots.length; j++) {
        var slot = moduleSlots[j]
        if (!slot || slot.region !== region || slot.moduleName !== id) continue
        if (window && !sameWindow(slotWindow(slot), window)) continue
        var item = slot.activeItem
        if (!item || item.visible !== true || slot.visible !== true || slot.width <= 0 || slot.height <= 0) continue
        if (typeof item.open !== "function" || typeof item.close !== "function" || item.opened === undefined) continue
        slots.push(slot)
        break
      }
    }
    return slots
  }

  // The Nth panel in a bar region, counted the way the bar reads: layout order,
  // and only the panels actually on screen. A widget with no panel (the tray)
  // and one that is hiding itself are passed over, so the number lands on the
  // Nth panel icon the user can see rather than the Nth layout entry.
  // One-based, because it exists for hotkeys; anything else lands on no slot.
  //
  // Counting any bar surface is enough: every monitor lays its bar out from the
  // one layout, and summoning the id routes through pickPanelSlot, which opens
  // the focused monitor's copy whichever surface was counted.
  function panelWidgetIdAt(region, index) {
    var slots = panelNavigationSlots(String(region || ""), null)
    var slot = slots[Math.round(Number(index)) - 1]
    return slot ? String(slot.moduleName || "") : ""
  }

  function switchPanelFrom(owner, direction) {
    if (!owner) return false

    var currentSlot = null
    for (var i = 0; i < moduleSlots.length; i++) {
      var slot = moduleSlots[i]
      if (slot && slot.activeItem === owner) {
        currentSlot = slot
        break
      }
    }
    if (!currentSlot) return false

    var slots = panelNavigationSlots(currentSlot.region, slotWindow(currentSlot))
    if (slots.length < 2) return false

    var currentIndex = -1
    for (var j = 0; j < slots.length; j++) {
      if (slots[j] === currentSlot) {
        currentIndex = j
        break
      }
    }
    if (currentIndex < 0) return false

    var step = direction < 0 ? -1 : 1
    var nextSlot = slots[(currentIndex + step + slots.length) % slots.length]
    if (!nextSlot || !nextSlot.activeItem || nextSlot.activeItem === owner) return false

    nextSlot.activeItem.open()
    return true
  }

  // Every live instance of a widget id. A bar surface is built per monitor, so
  // a widget that appears once in the layout is still live once per screen.
  function moduleWidgets(pluginId) {
    var id = String(pluginId || "")
    var items = []
    if (!id) return items
    for (var i = 0; i < moduleSlots.length; i++) {
      var slot = moduleSlots[i]
      if (!slot || !slot.activeItem || slot.moduleName !== id) continue
      items.push(slot.activeItem)
    }
    return items
  }

  function slotScreenName(slot) {
    var window = slotWindow(slot)
    return window && window.screen ? String(window.screen.name || "") : ""
  }

  // The output Hyprland has focused, which is where a keyboard-summoned panel
  // belongs. Empty until Hyprland reports one, which leaves panel routing on
  // its per-monitor fallback rather than guessing at an output.
  function focusedScreenName() {
    var monitor = Hyprland.focusedMonitor
    return monitor ? String(monitor.name || "") : ""
  }

  // Resolve the live bar-widget instance for a plugin id (e.g. "omarchy.bluetooth").
  // Only widgets that expose popup open/close methods count; plain indicators
  // (clock, workspaces, tray) return null. Used by shell.summon/toggle so
  // panel hotkeys route through the bar instead of a per-target IPC handler
  // that only reaches whichever per-monitor instance claimed the target.
  function findPanelWidget(pluginId) {
    var id = String(pluginId || "")
    if (!id) return null
    var candidates = []
    for (var i = 0; i < moduleSlots.length; i++) {
      var slot = moduleSlots[i]
      if (!slot || !slot.activeItem) continue
      if (slot.moduleName !== id) continue
      var item = slot.activeItem
      if (typeof item.open !== "function" || typeof item.close !== "function" || item.opened === undefined) continue
      candidates.push({ slot: slot, screenName: slotScreenName(slot), opened: item.opened === true })
    }
    // One copy per monitor, plus a zero-size placeholder for anchored center
    // modules. See BarModel.pickPanelSlot for which one a hotkey acts on.
    var chosen = BarModel.pickPanelSlot(candidates, focusedScreenName())
    return chosen ? chosen.activeItem : null
  }

  function summonBarWidget(pluginId) {
    var item = findPanelWidget(pluginId)
    if (!item || typeof item.open !== "function") return false
    item.open()
    return true
  }

  function hideBarWidget(pluginId) {
    var item = findPanelWidget(pluginId)
    if (!item || typeof item.close !== "function") return false
    item.close()
    return true
  }

  function isBarWidgetOpen(pluginId) {
    var item = findPanelWidget(pluginId)
    return !!item && item.opened === true
  }

  function entrySettings(entry) {
    return BarModel.entrySettings(entry)
  }

  function entryId(entry) {
    return BarModel.entryId(entry)
  }

  function moduleString(entry, key, fallback) {
    return BarModel.moduleString(entry, key, fallback)
  }

  function entryIndex(entries, name) {
    return BarModel.entryIndex(entries, name)
  }

  function entriesBefore(entries, name) {
    return BarModel.entriesBefore(entries, name)
  }

  function entriesAfter(entries, name) {
    return BarModel.entriesAfter(entries, name)
  }

  function canonicalWidgetId(name) {
    return Util.canonicalWidgetId(name)
  }

  function expandPath(path) {
    return BarModel.expandPath(path, home)
  }

  function customModuleSafeName(name) {
    return BarModel.customModuleSafeName(name)
  }

  function customModuleType(entry) {
    return BarModel.customModuleType(entry)
  }

  function customModuleSource(entry) {
    var source = BarModel.customModulePath(entry, home, omarchyConfigDir)
    return source ? Util.fileUrl(source) : ""
  }

  Component.onCompleted: applyBarConfig()

  // Revealing the indicators widens their section, which can slide a neighbour
  // under a stationary pointer. Collapsing on that un-hover would move it back
  // out and re-open the peek, so hold until the pointer leaves the bar.
  function setCenterSectionHovered(hovered) {
    centerSectionHovered = hovered
    if (hovered) {
      centerSectionRevealTimer.stop()
      centerSectionRevealHeld = true
    } else {
      centerSectionRevealTimer.restart()
    }
  }

  function setBarHovered(hovered) {
    barHoverCount = Math.max(0, barHoverCount + (hovered ? 1 : -1))
    if (barHoverCount === 0) centerSectionRevealTimer.restart()
  }

  function setCenterHoverRevealSuppressed(value) {
    centerHoverRevealSuppressed = !!value
  }

  Timer {
    id: centerSectionRevealTimer
    interval: 120
    // Collapse only. Opening the peek is the center section's own gesture, done
    // in setCenterSectionHovered, so a timer left pending by a pointer that dipped
    // off the bar and came back cannot reveal indicators it never pointed at.
    onTriggered: if (!root.centerSectionHovered && !root.barHovered) root.centerSectionRevealHeld = false
  }

  function run(command) {
    if (!command) return

    Util.execDetached(command)
  }

  // Vista: host-called (keybind). The taskbar is always opaque, so flipping
  // bar.transparent in shell.json here would only change ocko's stock bar
  // behind his back; do nothing.
  function toggleTransparency() {}

  function rawLayoutSection(config, region) {
    if (!Util.isPlainObject(config.bar)) config.bar = {}
    if (!Util.isPlainObject(config.bar.layout)) config.bar.layout = {}
    if (!Array.isArray(config.bar.layout[region])) config.bar.layout[region] = []

    return config.bar.layout[region]
  }

  function rawEntryIndex(entries, name) {
    for (var i = 0; i < entries.length; i++) {
      if (root.entryId(entries[i]) === name) return i
    }

    return -1
  }

  function moveModuleInConfig(config, fromRegion, fromName, toRegion, beforeName) {
    var fromEntries = rawLayoutSection(config, fromRegion)
    var toEntries = rawLayoutSection(config, toRegion)
    var fromIndex = rawEntryIndex(fromEntries, fromName)
    if (fromIndex < 0) return false

    var toIndex = beforeName ? rawEntryIndex(toEntries, beforeName) : toEntries.length
    if (toIndex < 0) toIndex = toEntries.length

    if (fromRegion === toRegion && fromIndex === toIndex) return false

    var movedEntry = fromEntries[fromIndex]
    fromEntries.splice(fromIndex, 1)

    if (fromRegion === toRegion && fromIndex < toIndex) toIndex -= 1
    if (toIndex < 0) toIndex = 0
    if (toIndex > toEntries.length) toIndex = toEntries.length
    if (fromRegion === toRegion && fromIndex === toIndex) {
      fromEntries.splice(fromIndex, 0, movedEntry)
      return false
    }

    toEntries.splice(toIndex, 0, movedEntry)
    return true
  }

  function dropBarModule(source, toRegion, beforeName) {
    if (!source || !source.region || !source.moduleName || !toRegion) return false
    if (source.region === toRegion && source.moduleName === beforeName) return false
    if (!root.shell || typeof root.shell.mutateShellConfig !== "function") return false

    var changed = false
    root.shell.mutateShellConfig(function(config) {
      changed = moveModuleInConfig(config, source.region, source.moduleName, toRegion, beforeName)
    })
    return changed
  }

  function moduleDropAtScene(scenePoint, sourceSlot) {
    var sourceWindow = root.slotWindow(sourceSlot) || root.barDragWindow
    if (sourceWindow && sourceWindow.contentItem) {
      var barPoint = sourceWindow.contentItem.mapFromItem(null, scenePoint.x, scenePoint.y)
      if (barPoint.x < 0 || barPoint.x > sourceWindow.contentItem.width ||
          barPoint.y < 0 || barPoint.y > sourceWindow.contentItem.height)
        return null
    }

    var candidates = []
    for (var i = 0; i < moduleSlots.length; i++) {
      var slot = moduleSlots[i]
      if (!slot || slot === sourceSlot || !slot.visible || slot.width <= 0 || slot.height <= 0) continue
      if (sourceWindow && !root.sameWindow(root.slotWindow(slot), sourceWindow)) continue

      var slotPoint = { x: slot.x, y: slot.y }
      try {
        slotPoint = slot.mapToItem(null, 0, 0)
      } catch (e) {
      }

      candidates.push({
        slot: slot,
        x: slotPoint.x,
        y: slotPoint.y,
        width: slot.width,
        height: slot.height
      })
    }

    return BarModel.nearestDropTarget(candidates, scenePoint, root.vertical)
  }

  function visibleModuleSlot(region, name, sourceSlot) {
    var sourceWindow = root.slotWindow(sourceSlot) || root.barDragWindow
    for (var i = 0; i < moduleSlots.length; i++) {
      var slot = moduleSlots[i]
      if (!slot || slot === sourceSlot || slot.region !== region || slot.moduleName !== name ||
          !slot.visible || slot.width <= 0 || slot.height <= 0) continue
      if (sourceWindow && !root.sameWindow(root.slotWindow(slot), sourceWindow)) continue
      return slot
    }

    return null
  }

  function nextVisibleModuleName(region, afterName, sourceSlot) {
    var entries = layoutEntries(region)
    var found = false
    for (var i = 0; i < entries.length; i++) {
      var name = entryId(entries[i])
      if (!found) {
        found = name === afterName
        continue
      }

      if (visibleModuleSlot(region, name, sourceSlot)) return name
    }

    return ""
  }

  function dropBarModuleAtTarget(sourceSlot, targetSlot, afterTarget) {
    if (!sourceSlot || !targetSlot) return false

    var beforeName = afterTarget ? nextVisibleModuleName(targetSlot.region, targetSlot.moduleName, sourceSlot) : targetSlot.moduleName
    return dropBarModule(sourceSlot, targetSlot.region, beforeName)
  }

  function moduleTargetClickable(target) {
    return target
      && target.visible !== false
      && target.opacity !== 0
      && target.interactive !== false
      && target.pressable !== false
      && target.concealed !== true
      && typeof target.triggerPress === "function"
  }

  function moduleClickTargetAt(slot, localX, localY) {
    for (var i = clickTargets.length - 1; i >= 0; i--) {
      var target = clickTargets[i]
      if (!moduleTargetClickable(target)) continue

      var targetPoint = { x: localX, y: localY }
      try {
        targetPoint = slot.mapToItem(target, localX, localY)
      } catch (e) {
        continue
      }

      if (targetPoint.x >= 0 && targetPoint.x <= target.width &&
          targetPoint.y >= 0 && targetPoint.y <= target.height) {
        return target
      }
    }

    if (moduleTargetClickable(slot.activeItem)) return slot.activeItem
    return null
  }

  function pressModuleClickTarget(slot, button, localX, localY) {
    var target = moduleClickTargetAt(slot, localX, localY)
    if (!target) return false

    target.triggerPress(button)
    return true
  }

  function colorHex(colorValue) {
    var c = colorValue
    if (typeof c === "string") c = Qt.color(c)
    function hexChannel(value) {
      var s = Math.round(Util.clamp(value, 0, 1) * 255).toString(16)
      return s.length < 2 ? "0" + s : s
    }
    return "#" + hexChannel(c.r) + hexChannel(c.g) + hexChannel(c.b)
  }

  function setRequestedTransparency(value) {
    var nextTransparent = value === true
    requestedTransparent = nextTransparent
    if (!nextTransparent) {
      foregroundAnimationEnabled = false
      useTransparentForeground = false
      transparent = false
      transparentForeground = themeForeground
      restoreForegroundAnimation()
      return
    }
    scheduleTransparentForegroundRefresh()
  }

  function restoreForegroundAnimation() {
    Qt.callLater(function() {
      Qt.callLater(function() { root.foregroundAnimationEnabled = true })
    })
  }

  function scheduleTransparentForegroundRefresh() {
    if (!requestedTransparent) {
      transparentForeground = themeForeground
      return
    }
    transparentForegroundTimer.restart()
  }

  function refreshTransparentForeground() {
    if (!requestedTransparent || transparentForegroundProc.running) return

    transparentForegroundProc.command = [
      "omarchy-bar-text-color",
      root.position,
      String(root.barSize),
      colorHex(root.themeForeground),
      colorHex(root.themeContrastForeground)
    ]
    transparentForegroundProc.running = true
  }

  onRequestedTransparentChanged: scheduleTransparentForegroundRefresh()
  onPositionChanged: scheduleTransparentForegroundRefresh()
  onThemeForegroundChanged: scheduleTransparentForegroundRefresh()
  onThemeContrastForegroundChanged: scheduleTransparentForegroundRefresh()

  Timer {
    id: transparentForegroundTimer
    interval: 120
    repeat: false
    onTriggered: root.refreshTransparentForeground()
  }

  Process {
    id: transparentForegroundProc
    stdout: SplitParser {
      onRead: function(line) {
        var value = String(line || "").trim()
        if (!/^#[0-9A-Fa-f]{6}$/.test(value)) return

        root.foregroundAnimationEnabled = false
        root.transparentForeground = value
        if (root.requestedTransparent) {
          root.useTransparentForeground = true
          root.transparent = true
        }
        root.restoreForegroundAnimation()
      }
    }
  }

  FileView {
    path: root.stateHome + "/omarchy/current"
    watchChanges: true
    printErrors: false
    onFileChanged: root.scheduleTransparentForegroundRefresh()
  }

  function runProcess(process) {
    if (!process.running)
      process.running = true
  }

  function showTooltip(target, text) {
    clearTooltip()

    if (!targetTooltipHovered(target) || !text) {
      tooltipRequest += 1
      return
    }

    var request = tooltipRequest + 1
    tooltipRequest = request
    pendingTooltipTarget = target
    pendingTooltipText = text

    Qt.callLater(function() {
      if (request !== tooltipRequest) return
      if (!targetTooltipHovered(pendingTooltipTarget)) {
        clearTooltip()
        return
      }
      tooltipTarget = pendingTooltipTarget
      tooltipText = pendingTooltipText
      pendingTooltipTarget = null
      pendingTooltipText = ""
      tooltipTimer.restart()
    })
  }

  function hideTooltip(target) {
    if (tooltipTarget !== target && pendingTooltipTarget !== target) return

    tooltipRequest += 1
    clearTooltip()
  }

  Timer {
    id: tooltipTimer
    interval: 400
    onTriggered: {
      if (root.targetTooltipHovered(root.tooltipTarget)) root.tooltipShown = true
      else root.clearTooltip()
    }
  }

  Timer {
    interval: 100
    running: root.tooltipShown
    repeat: true
    onTriggered: if (!root.targetTooltipHovered(root.tooltipTarget)) root.hideTooltip(root.tooltipTarget)
  }

  // Presence of the `bar-off` flag = bar hidden. Watching the parent toggles
  // directory because FileView can't observe a file that doesn't exist yet,
  // and the flag is created/removed by `omarchy-toggle-bar`.
  Process {
    id: barHiddenProbe
    running: true
    command: ["bash", "-c", "[[ -f $HOME/.local/state/omarchy/toggles/bar-off ]] && echo yes || echo no"]
    stdout: SplitParser { onRead: function(line) { root.barHidden = String(line).trim() === "yes" } }
  }
  FileView {
    path: root.home + "/.local/state/omarchy/toggles"
    watchChanges: true
    printErrors: false
    onFileChanged: barHiddenProbe.running = true
  }

  // The directory watch can permanently stop delivering events after flag
  // changes land in quick succession, stranding the bar off screen until the
  // shell restarts. `omarchy-toggle-bar` nudges this after flipping the flag
  // so the probe re-reads it even when the watch has gone quiet.
  IpcHandler {
    target: "omarchy.bar"

    // Start rather than restart: a probe already in flight was launched by the
    // directory watch after the flag flipped, so its answer is current, and
    // killing it here can swallow the result entirely.
    function syncHidden(): void {
      barHiddenProbe.running = true
    }
  }

  Variants {
    model: Quickshell.screens

    delegate: Component {
      BarPanel {
        required property var modelData

        screen: modelData
      }
    }
  }

  Variants {
    model: Quickshell.screens

    delegate: Component {
      DragGhostPanel {
        required property var modelData

        screen: modelData
        ghostScreen: modelData
      }
    }
  }

  Variants {
    model: Quickshell.screens

    delegate: Component {
      BarMoveGhostPanel {
        required property var modelData

        screen: modelData
        ghostScreen: modelData
      }
    }
  }

  component BarPanel: PanelWindow {
    id: barWindow

    // Hiding parks the bar just past its screen edge instead of unmapping it.
    // Unmapping frees the layer surface and the whole scene graph, so every
    // reveal has to rebuild them — new surface, re-shaped glyphs, re-uploaded
    // textures — which measures ~150ms against ~20ms to tear down. Parking
    // keeps the surface alive, so showing is only a margin change.
    visible: !remapGuard.remapping
    exclusionMode: root.barHidden ? ExclusionMode.Ignore : ExclusionMode.Normal

    ScreenMoveRemap {
      id: remapGuard
      window: barWindow
    }

    margins {
      top: root.barHidden && root.position === "top" ? -root.barSize : 0
      bottom: root.barHidden && root.position === "bottom" ? -root.barSize : 0
      left: root.barHidden && root.position === "left" ? -root.barSize : 0
      right: root.barHidden && root.position === "right" ? -root.barSize : 0
    }

    anchors {
      top: root.position === "top" || root.vertical
      bottom: root.position === "bottom" || root.vertical
      left: root.position === "left" || !root.vertical
      right: root.position === "right" || !root.vertical
    }

    implicitWidth: root.vertical ? root.barSize : 0
    implicitHeight: root.vertical ? 0 : root.barSize + root.vistaOverhang
    exclusiveZone: root.barHidden ? 0 : root.barSize
    // Vista: the taskbar art draws the bar (glass is see-through).
    color: "transparent"
    mask: Region {
      y: root.vistaOverhang
      width: barWindow.width
      height: barWindow.height - root.vistaOverhang
      Region { item: barWindow.vistaOrbHit; shape: RegionShape.Ellipse }
    }
    property Item vistaOrbHit: null
    surfaceFormat.opaque: false
    WlrLayershell.namespace: "omarchy-bar"
    WlrLayershell.layer: WlrLayer.Top

    Loader {
      anchors.fill: parent
      sourceComponent: root.vertical ? verticalBar : horizontalBar

      // A child of the loader, not a sibling of the sections: an ancestor stays
      // hovered while the pointer is over a widget, where a sibling would lose
      // hover to the section the pointer entered.
      HoverHandler {
        onHoveredChanged: root.setBarHovered(hovered)
        // Unplugging a monitor destroys its bar without a leave event, which
        // would strand this surface's tally and hold the peek open for good.
        Component.onDestruction: if (hovered) root.setBarHovered(false)
      }
    }

    PopupWindow {
      id: tooltipWindow

      visible: root.tooltipShown && root.tooltipTarget !== null && root.tooltipText !== "" && root.targetBelongsToWindow(root.tooltipTarget, barWindow)
      color: "transparent"
      implicitWidth: Math.ceil(tooltipBubble.implicitWidth)
      implicitHeight: Math.ceil(tooltipBubble.implicitHeight)

      anchor {
        id: tooltipAnchor
        window: barWindow
        adjustment: PopupAdjustment.Slide
        edges: Edges.Top | Edges.Left
        gravity: Edges.Bottom | Edges.Right
        rect.width: 1
        rect.height: 1

        onAnchoring: {
          var target = root.tooltipTarget
          if (!root.targetBelongsToWindow(target, barWindow)) return

          var popupWidth = tooltipWindow.implicitWidth
          var popupHeight = tooltipWindow.implicitHeight
          var localX = target.width / 2 - popupWidth / 2
          var localY = target.height + 6

          if (root.position === "bottom") {
            localY = -popupHeight - 6
          } else if (root.position === "left") {
            localX = target.width + 6
            localY = target.height / 2 - popupHeight / 2
          } else if (root.position === "right") {
            localX = -popupWidth - 6
            localY = target.height / 2 - popupHeight / 2
          }

          var point = barWindow.contentItem.mapFromItem(target, localX, localY)
          tooltipAnchor.rect.x = Math.round(point.x)
          tooltipAnchor.rect.y = Math.round(point.y)
        }
      }

      BorderSurface {
        id: tooltipBubble
        implicitWidth: tooltipLabel.implicitWidth + 20
        implicitHeight: tooltipLabel.implicitHeight + 14
        color: Commons.Color.tooltip.background
        borderSpec: Border.surfaceSpec("tooltip", "border", Commons.Color.tooltip.border, 1)
        radius: Style.cornerRadius

        Text {
          id: tooltipLabel
          textFormat: Text.PlainText
          anchors.centerIn: parent
          text: root.tooltipText
          color: Commons.Color.tooltip.text
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          horizontalAlignment: Text.AlignHCenter
          verticalAlignment: Text.AlignVCenter
        }
      }
    }

    // Vista: start button | Quick Launch | window buttons | notification area.
    Component {
      id: horizontalBar

      Item {
        id: vistaBar
        anchors.fill: parent
        anchors.topMargin: root.vistaOverhang

        readonly property string monitorName: barWindow.screen ? String(barWindow.screen.name || "") : ""

        VistaArt {
          anchors.fill: parent
          source: root.vistaArtDir + "/taskbar.png"
          margins: root.vistaScheme.taskbar
          tile: true
        }

        VistaStartButton {
          id: startButton
          anchors.left: parent.left
          anchors.leftMargin: -Style.space(2)
          anchors.verticalCenter: parent.verticalCenter
          orbRoot: root.vistaArtRoot + "/orb"
          menuOpen: root.vistaStartMenuScreen !== "" && root.vistaStartMenuScreen === vistaBar.monitorName
          onActivated: root.toggleStartMenu(barWindow.screen)
          Component.onCompleted: barWindow.vistaOrbHit = startButton.hit
        }

        VistaQuickLaunch {
          id: quickLaunch
          anchors.left: startButton.right
          anchors.leftMargin: Style.space(2)
          anchors.top: parent.top
          anchors.bottom: parent.bottom
          bar: root
          monitorName: vistaBar.monitorName
          artDir: root.vistaArtDir
        }

        VistaTaskButtons {
          anchors.left: quickLaunch.right
          anchors.leftMargin: Style.space(8)
          anchors.right: tray.left
          anchors.rightMargin: Style.space(4)
          anchors.top: parent.top
          anchors.bottom: parent.bottom
          bar: root
          monitorName: vistaBar.monitorName
          artDir: root.vistaArtDir
          scheme: root.vistaScheme
        }

        // Notification area: [TrayNotifyHoriz::TrayNotify.Background] behind
        // every remaining bar.layout entry, then the clock.
        Item {
          id: tray
          anchors.right: parent.right
          anchors.top: parent.top
          anchors.bottom: parent.bottom
          width: trayRow.width + Style.space(14) + Style.space(10)

          VistaArt {
            anchors.fill: parent
            source: root.vistaArtDir + "/tray.png"
            margins: root.vistaScheme.tray
          }

          Row {
            id: trayRow
            x: Style.space(14)
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(2)

            RightModules { anchors.verticalCenter: parent.verticalCenter }

            Item {
              id: clock
              readonly property bool tooltipHovered: clockMouse.containsMouse
              anchors.verticalCenter: parent.verticalCenter
              width: clockLabel.implicitWidth + Style.space(8)
              height: root.barSize
              // The hidden stock clock below is as wide as ocko's own format;
              // without the clip it would sit over the neighbouring widgets.
              clip: true

              // The stock clock, invisible, only so its calendar panel has an
              // anchor here (and `omarchy-shell shell toggle omarchy.clock`
              // finds it). The label above it takes every click; its
              // right-click opens the Vista clock menu below instead.
              ModuleSlot {
                id: clockSlot
                entry: root.vistaClockEntry
                region: "vista-clock"
                anchors.centerIn: parent
                opacity: 0
                enabled: false
              }

              Text {
                id: clockLabel
                anchors.centerIn: parent
                text: Qt.formatDateTime(clockSource.date, "h:mm AP")
                color: root.vistaScheme.clock
                font.family: "Segoe UI"
                font.pixelSize: Style.font.bodySmall
              }

              SystemClock {
                id: clockSource
                precision: SystemClock.Minutes
              }

              MouseArea {
                id: clockMouse
                anchors.fill: parent
                hoverEnabled: true
                acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
                onClicked: function(mouse) {
                  var item = clockSlot.activeItem
                  if (mouse.button === Qt.LeftButton && item && typeof item.togglePanel === "function") item.togglePanel()
                  // Middle-click picks the time zone, as on the stock clock.
                  else if (mouse.button === Qt.MiddleButton) root.run("omarchy-menu-timezone")
                  else if (mouse.button === Qt.RightButton) clock.menuOpen = !clock.menuOpen
                }
                onEntered: root.showTooltip(clock, Qt.formatDateTime(clockSource.date, "dddd, MMMM d, yyyy"))
                onExited: root.hideTooltip(clock)
              }

              // Vista's notification-area clock menu, cut to the items with a
              // real action here (Toolbars, Cascade/Tile, Lock the Taskbar and
              // Properties have none). Format cycling was the stock clock's
              // right-click; it writes the stock entry via vistaStockIdOf.
              property bool menuOpen: false
              QtObject {
                id: clockMenuOwner
                function close() { clock.menuOpen = false }
              }
              KeyboardPanel {
                anchorItem: clock
                owner: clockMenuOwner
                bar: root
                open: clock.menuOpen
                focusTarget: clockMenuKeys
                gap: 0
                padding: 0
                borderSpec: Border.none()
                contentWidth: clockMenu.implicitWidth
                contentHeight: clockMenu.implicitHeight
                onOpenChanged: clockMenu.currentIndex = -1

                PanelKeyCatcher {
                  id: clockMenuKeys
                  anchors.fill: parent
                  // Drop the stock card behind the Vista menu face.
                  Component.onCompleted: {
                    var card = parent ? parent.parent : null
                    if (card && "radius" in card) { card.color = "transparent"; card.radius = 0 }
                  }
                  onMoveRequested: function(dx, dy) { if (dy !== 0) clockMenu.moveBy(dy) }
                  onActivateRequested: clockMenu.activateCurrent()
                  onCloseRequested: clock.menuOpen = false

                  VistaMenu {
                    id: clockMenu
                    anchors.fill: parent
                    items: [
                      { text: "Adjust Date/Time", bold: true },
                      { separator: true },
                      { text: "Show the Desktop" },
                      { separator: true },
                      { text: "Task Manager" },
                      { separator: true },
                      { text: "Change clock format" }
                    ]
                    onTriggered: function(i) {
                      clock.menuOpen = false
                      var item = clockSlot.activeItem
                      if (i === 0) { if (item && typeof item.togglePanel === "function") item.togglePanel() }
                      else if (i === 2) root.vistaToggleDesktop(vistaBar.monitorName)
                      // Omarchy's own "Activity" binding (SUPER+CTRL+T).
                      else if (i === 4) root.run("omarchy-launch-or-focus-tui btop")
                      else if (i === 6) { if (item && typeof item.cycleFormat === "function") item.cycleFormat() }
                    }
                  }
                }
              }
            }
          }
        }
      }
    }

    Component {
      id: verticalBar

      Item {
        anchors.fill: parent

        CenterModules { anchors.fill: parent }

        LeftModules {
          anchors.top: parent.top
          anchors.topMargin: Style.space(8)
          anchors.horizontalCenter: parent.horizontalCenter
        }

        RightModules {
          anchors.bottom: parent.bottom
          anchors.bottomMargin: Style.space(8)
          anchors.horizontalCenter: parent.horizontalCenter
        }
      }
    }
  }

  Component { id: emptyModuleComponent; Item { implicitWidth: 0; implicitHeight: 0; visible: false } }

  component DragGhostPanel: PanelWindow {
    id: ghostWindow

    required property var ghostScreen
    readonly property bool screenMatches: root.barDragScreen === ghostScreen ||
      (root.barDragScreen && ghostScreen && root.barDragScreen.name && ghostScreen.name && root.barDragScreen.name === ghostScreen.name)
    readonly property bool active: root.barDragSource && root.barDragScreen && screenMatches
    readonly property var sourceItem: root.barDragSource ? root.barDragSource.activeItem : null
    readonly property int ghostPadding: Style.space(1)
    readonly property int ghostWidth: sourceItem ? Math.max(1, Math.ceil(sourceItem.width)) : 1
    readonly property int ghostHeight: sourceItem ? Math.max(1, Math.ceil(sourceItem.height)) : 1

    visible: active && sourceItem !== null
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "omarchy-bar-drag-ghost"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    anchors {
      top: true
      bottom: true
      left: true
      right: true
    }

    // Visual-only drag feedback. Keep the input region empty so the ghost can
    // sit under the cursor without stealing the MouseArea's active pointer grab.
    mask: Region {}

    Item {
      visible: ghostWindow.visible
      x: Math.round(root.barDragScreenX - root.barDragOffsetX - ghostWindow.ghostPadding)
      y: Math.round(root.barDragScreenY - root.barDragOffsetY - ghostWindow.ghostPadding)
      width: ghostWindow.ghostWidth + ghostWindow.ghostPadding * 2
      height: ghostWindow.ghostHeight + ghostWindow.ghostPadding * 2

      BorderSurface {
        anchors.fill: parent
        color: root.transparent ? "transparent" : root.background
        borderSpec: Border.flat(root.barForeground, 1)
        radius: Math.min(Style.cornerRadius, height / 2)
        opacity: root.transparent ? 0.45 : 0.94
      }

      Image {
        anchors.fill: parent
        anchors.margins: ghostWindow.ghostPadding
        source: root.barDragImageUrl
        fillMode: Image.Stretch
        smooth: true
        opacity: 0.84
      }
    }

    Rectangle {
      readonly property var targetRect: root.barDragTargetGeometry

      visible: ghostWindow.active && targetRect !== null
      x: targetRect ? Math.round(targetRect.x) : 0
      y: targetRect ? Math.round(targetRect.y) : 0
      width: targetRect ? targetRect.width : 0
      height: targetRect ? targetRect.height : 0
      color: Commons.Color.accent
      radius: Math.min(width, height) / 2
    }
  }

  component BarMoveGhostPanel: PanelWindow {
    id: moveGhostWindow

    required property var ghostScreen
    readonly property bool screenMatches: root.barMoveScreen === ghostScreen ||
      (root.barMoveScreen && ghostScreen && root.barMoveScreen.name && ghostScreen.name && root.barMoveScreen.name === ghostScreen.name)
    visible: root.barMoveActive && screenMatches
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "omarchy-bar-move-ghost"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    anchors {
      top: true
      bottom: true
      left: true
      right: true
    }

    // Visual-only preview of the candidate edge. Keep the input region empty
    // so the overlay never steals the gesture area's active pointer grab.
    mask: Region {}

    // One fixed-geometry slab per edge, crossfaded on candidate changes.
    // Resizing a single slab between edges repaints mid-transition and
    // flickers; fading between static ones does not.
    Repeater {
      model: ["top", "bottom", "left", "right"]

      BorderSurface {
        id: edgeSlab

        required property string modelData
        readonly property bool edgeVertical: modelData === "left" || modelData === "right"
        readonly property int edgeSize: edgeVertical ? Style.bar.sizeVertical : Style.bar.sizeHorizontal

        x: modelData === "right" ? parent.width - edgeSize : 0
        y: modelData === "bottom" ? parent.height - edgeSize : 0
        width: edgeVertical ? edgeSize : parent.width
        height: edgeVertical ? parent.height : edgeSize
        color: root.transparent ? "transparent" : root.background
        borderSpec: Border.flat(root.barForeground, 1)
        visible: opacity > 0
        opacity: root.barMoveCandidate === modelData ? (root.transparent ? 0.45 : 0.7) : 0

        Behavior on opacity {
          NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
        }
      }
    }
  }

  function findCenterAnchorEntry() {
    var entries = root.layoutEntries("center")
    var idx = root.entryIndex(entries, root.centerAnchor)
    return idx === -1 ? null : entries[idx]
  }

  component LeftModules: ModuleList {
    entries: root.layoutEntries("left")
    region: "left"
  }

  component RightModules: ModuleList {
    entries: root.layoutEntries("right")
    region: "right"
  }

  component CenterModules: Item {
    id: centerRoot

    property var entries: root.layoutEntries("center")
    readonly property bool hasAnchor: root.entryIndex(entries, root.centerAnchor) !== -1
    readonly property var anchorEntry: root.findCenterAnchorEntry()

    Loader {
      anchors.fill: parent
      sourceComponent: root.vertical ? verticalCenterModules : horizontalCenterModules
    }

    Component {
      id: horizontalCenterModules

      Item {
        anchors.fill: parent

        CenterGestureArea { anchors.fill: parent }

        HoverHandler {
          onHoveredChanged: root.setCenterSectionHovered(hovered)
        }

        ModuleList {
          visible: !centerRoot.hasAnchor
          entries: centerRoot.entries
          region: "center"
          anchors.centerIn: parent
        }

        ModuleList {
          visible: centerRoot.hasAnchor
          entries: root.entriesBefore(centerRoot.entries, root.centerAnchor)
          region: "center"
          anchors.right: centerAnchorModule.left
          anchors.verticalCenter: centerAnchorModule.verticalCenter
        }

        ModuleSlot {
          id: centerAnchorModule
          visible: centerRoot.hasAnchor
          entry: centerRoot.anchorEntry
          region: "center"
          anchors.centerIn: parent
        }

        ModuleList {
          visible: centerRoot.hasAnchor
          entries: root.entriesAfter(centerRoot.entries, root.centerAnchor)
          region: "center"
          anchors.left: centerAnchorModule.right
          anchors.verticalCenter: centerAnchorModule.verticalCenter
        }
      }
    }

    Component {
      id: verticalCenterModules

      Item {
        anchors.fill: parent

        CenterGestureArea { anchors.fill: parent }

        HoverHandler {
          onHoveredChanged: root.setCenterSectionHovered(hovered)
        }

        ModuleList {
          visible: !centerRoot.hasAnchor
          entries: centerRoot.entries
          region: "center"
          anchors.centerIn: parent
        }

        ModuleList {
          visible: centerRoot.hasAnchor
          entries: root.entriesBefore(centerRoot.entries, root.centerAnchor)
          region: "center"
          anchors.bottom: centerAnchorModule.top
          anchors.horizontalCenter: centerAnchorModule.horizontalCenter
        }

        ModuleSlot {
          id: centerAnchorModule
          visible: centerRoot.hasAnchor
          entry: centerRoot.anchorEntry
          region: "center"
          anchors.centerIn: parent
        }

        ModuleList {
          visible: centerRoot.hasAnchor
          entries: root.entriesAfter(centerRoot.entries, root.centerAnchor)
          region: "center"
          anchors.top: centerAnchorModule.bottom
          anchors.horizontalCenter: centerAnchorModule.horizontalCenter
        }
      }
    }
  }

  component CenterGestureArea: MouseArea {
    id: gestureArea

    property bool dragging: false
    property bool suppressClick: false
    property real pressedX: 0
    property real pressedY: 0
    readonly property real dragThreshold: Style.space(4)

    acceptedButtons: Qt.LeftButton
    cursorShape: dragging ? Qt.ClosedHandCursor : Qt.ArrowCursor
    pressAndHoldInterval: 200

    function startDrag(x, y) {
      if (dragging) return
      dragging = true
      root.beginBarMove(root.targetWindow(gestureArea))
      var scenePoint = gestureArea.mapToItem(null, x, y)
      root.updateBarMove(root.windowScreenPoint(scenePoint, root.barMoveWindow))
    }

    onPressed: function(mouse) {
      dragging = false
      suppressClick = false
      pressedX = mouse.x
      pressedY = mouse.y
    }

    onPressAndHold: function(mouse) {
      // A widget above us propagates its composed press-and-hold down here without
      // ever handing over the grab, so we'd get no release or cancel to end the move.
      if (!gestureArea.pressed) return
      startDrag(mouse.x, mouse.y)
    }

    onPositionChanged: function(mouse) {
      if (!(mouse.buttons & Qt.LeftButton)) return

      if (!dragging) {
        var distance = Math.abs(mouse.x - pressedX) + Math.abs(mouse.y - pressedY)
        if (distance < dragThreshold) return
        startDrag(mouse.x, mouse.y)
        return
      }

      var scenePoint = gestureArea.mapToItem(null, mouse.x, mouse.y)
      root.updateBarMove(root.windowScreenPoint(scenePoint, root.barMoveWindow))
    }

    onReleased: function(mouse) {
      if (!dragging) return
      dragging = false
      suppressClick = true
      root.finishBarMove()
      mouse.accepted = true
    }

    onCanceled: {
      dragging = false
      suppressClick = false
      root.clearBarMove()
    }

    onClicked: function(mouse) {
      if (suppressClick) {
        suppressClick = false
        mouse.accepted = true
      }
    }

    onDoubleClicked: function(mouse) {
      if (suppressClick) {
        suppressClick = false
        return
      }
      if (mouse.button === Qt.LeftButton) {
        root.toggleTransparency()
        mouse.accepted = true
      }
    }
  }

  component ModuleList: Loader {
    id: moduleListRoot

    property var entries: []
    property string region: ""

    visible: entries.length > 0
    // A hidden list must not build its modules. The center section declares
    // both an anchored and an unanchored arrangement and shows whichever
    // fits, so leaving the other one loaded mounts every center module
    // twice — two IPC handlers registered for the same target, two clocks
    // ticking, two of every timer and fetch behind them.
    active: visible && entries.length > 0
    sourceComponent: root.vertical ? verticalModuleList : horizontalModuleList
    width: item ? item.implicitWidth : 0
    height: item ? item.implicitHeight : 0

    Component {
      id: horizontalModuleList

      Row {
        spacing: 0

        Repeater {
          model: moduleListRoot.entries

          ModuleSlot {
            required property var modelData
            entry: modelData
            region: moduleListRoot.region
          }
        }
      }
    }

    Component {
      id: verticalModuleList

      Column {
        spacing: 0

        Repeater {
          model: moduleListRoot.entries

          ModuleSlot {
            required property var modelData
            entry: modelData
            region: moduleListRoot.region
          }
        }
      }
    }
  }

  component ModuleSlot: Item {
    id: slot

    required property var entry
    property string region: ""
    readonly property string moduleName: root.entryId(entry)
    readonly property var moduleSettings: root.entrySettings(entry)
    readonly property string customType: root.customModuleType(entry)
    readonly property var registryMetadata: root.barWidgetRegistry.metadataFor(root.canonicalWidgetId(moduleName))
    // An Vista clone is a copy of a first-party widget and gets the same bar
    // object the stock one would, so the copy behaves exactly like it.
    readonly property bool firstParty: (registryMetadata && registryMetadata.firstParty === true) || root.vistaIsClone(moduleName)
    readonly property string pluginApiId: registered ? root.canonicalWidgetId(moduleName) : "bar-entry:" + moduleName
    // Re-evaluate when the registry mutates (Component reference changes,
    // plugin enabled/disabled, etc.). Reading the `widgets` property creates
    // the binding dependency — the wrapped function call alone wouldn't.
    readonly property var registryComponent: {
      var w = root.barWidgetRegistry.widgets
      if (customType) return null
      var registryName = root.canonicalWidgetId(moduleName)
      return w[registryName] ? w[registryName].component : null
    }
    readonly property bool qmlCustom: customType === "qml"
    readonly property bool commandCustom: customType === "command"
    readonly property bool registered: registryComponent !== null
    readonly property var activeItem: {
      if (registered) return registryLoader.item
      if (qmlCustom) return qmlLoader.item
      return componentLoader.item
    }
    readonly property bool hovered: moduleHover.hovered
    readonly property bool dragSource: root.barDragSource === slot
    readonly property bool panelOpen: root.activePopout === slot.activeItem
    // Modules bigger than the mark they want (a text label in a padded slot,
    // a multi-line stack on a vertical bar) can say how long the open-panel
    // dot should be along the bar, so it tracks what the module paints
    // instead of a fraction of whatever slot it happens to fill.
    readonly property real panelIndicatorExtent: {
      var key = root.vertical ? "openPanelIndicatorHeight" : "openPanelIndicatorWidth"
      var hint = activeItem && key in activeItem ? activeItem[key] : undefined
      if (hint !== undefined && hint !== null && hint > 0) return Math.round(hint)
      return Math.max(Style.space(10), Math.round((root.vertical ? slot.height : slot.width) * 0.55))
    }
    implicitWidth: activeItem && activeItem.visible ? (root.vertical ? root.barSize : activeItem.implicitWidth) : 0
    implicitHeight: activeItem && activeItem.visible ? activeItem.implicitHeight : 0
    width: implicitWidth
    height: implicitHeight
    z: modulePointer.dragging ? 100 : 0

    // Vista: notification-area art (vistaSkinTray). Indicator loaders fill in after
    // the slot does, and a width change means buttons came or went, so look
    // again once things settle. Re-skinning a button is idempotent.
    onImplicitWidthChanged: if (region === "right") vistaSkinSettle.restart()
    Timer {
      id: vistaSkinSettle
      interval: 250
      onTriggered: {
        root.vistaSkinTray(slot.activeItem)
        root.vistaLinkIndicators()
      }
    }

    Component.onCompleted: root.registerModuleSlot(slot)
    Component.onDestruction: {
      if (root.barDragSource === slot) root.clearBarDrag()
      root.unregisterModuleSlot(slot)
    }

    HoverHandler { id: moduleHover }

    BorderSurface {
      visible: slot.dragSource
      anchors.fill: parent
      anchors.margins: Style.space(1)
      color: root.transparent ? "transparent" : root.background
      borderSpec: Border.flat(root.barForeground, 1)
      radius: Math.min(Style.cornerRadius, height / 2)
      opacity: root.transparent ? 0.22 : 0.32
    }

    Loader {
      id: componentLoader
      active: !slot.qmlCustom && !slot.registered
      sourceComponent: slot.commandCustom ? customCommandModuleComponent : emptyModuleComponent
      anchors.fill: parent
      opacity: slot.dragSource ? 0.22 : 1.0
      onLoaded: {
        slot.injectProps()
        Qt.callLater(slot.injectProps)
      }
    }

    Loader {
      id: registryLoader
      active: slot.registered
      sourceComponent: slot.registered ? slot.registryComponent : null
      anchors.fill: parent
      opacity: slot.dragSource ? 0.22 : 1.0
      onLoaded: {
        slot.injectProps()
        Qt.callLater(slot.injectProps)
      }
    }

    // The stock keyboard-layout widget drawn as Vista's blue "EN" box. A child
    // of the widget, so it shows only when the widget does (two or more
    // layouts); it takes no input, so the widget's own click still cycles
    // the layout.
    Loader {
      active: slot.moduleName === "omarchy.keyboard-layout" && !!registryLoader.item
      parent: registryLoader.item
      anchors.centerIn: parent
      z: 1
      sourceComponent: VistaLanguageBox {
        code: registryLoader.item ? String(registryLoader.item.layoutLabel || "") : ""
      }
    }

    Loader {
      id: qmlLoader
      active: slot.qmlCustom
      source: slot.qmlCustom ? root.customModuleSource(slot.entry) : ""
      anchors.fill: parent
      opacity: slot.dragSource ? 0.22 : 1.0
      onLoaded: {
        slot.injectProps()
        Qt.callLater(slot.injectProps)
      }
    }

    Rectangle {
      id: openPanelIndicator

      readonly property int inset: Style.space(2)

      visible: opacity > 0
      opacity: slot.panelOpen && !slot.dragSource ? 0.9 : 0
      color: Commons.Color.accent
      radius: Math.min(width, height) / 2
      width: root.vertical ? Style.space(2) : slot.panelIndicatorExtent
      height: root.vertical ? slot.panelIndicatorExtent : Style.space(2)
      // The mark sits on the module's inner edge — the one facing the
      // desktop — so it underlines a top bar, overlines a bottom one, and
      // points inward from a left or right one. It reads as pointing at the
      // panel that opens on that side.
      // Snap toward the start of the slot, matching native glyph rendering.
      x: root.vertical
        ? (root.position === "left" ? parent.width - width - inset : inset)
        : Math.floor((parent.width - width) / 2)
      y: root.vertical
        ? Math.floor((parent.height - height) / 2)
        : (root.position === "top" ? parent.height - height - inset : inset)
      z: 50

      Behavior on opacity {
        NumberAnimation { duration: 120; easing.type: Easing.OutCubic }
      }
    }

    MouseArea {
      id: modulePointer

      property bool dragging: false
      property bool suppressClick: false
      property real pressedX: 0
      property real pressedY: 0
      // Vista: the notification area is a flattened view of bar.layout, so a
      // drag here has no faithful mapping back to shell.json. Disabled.
      readonly property bool canReorder: false
      readonly property real dragThreshold: Style.space(4)

      anchors.fill: parent
      acceptedButtons: Qt.LeftButton
      enabled: slot.visible && slot.width > 0 && slot.height > 0
      propagateComposedEvents: true
      // Only the hovered slot needs the hit test; without the guard every
      // slot on every monitor re-ran it on each click target change.
      cursorShape: moduleHover.hovered && root.moduleClickTargetAt(slot, mouseX, mouseY) ? Qt.PointingHandCursor : Qt.ArrowCursor
      // Do not assign drag.target here: ModuleSlot is owned by Row/Column
      // positioners, and mutating slot.x/slot.y can leave stale offsets that
      // make neighboring modules overlap after a small aborted drag.

      onPressed: function(mouse) {
        dragging = false
        suppressClick = false
        pressedX = mouse.x
        pressedY = mouse.y
        root.clearBarDrag()
      }

      onPositionChanged: function(mouse) {
        if (!canReorder || !(mouse.buttons & Qt.LeftButton)) return

        var distance = Math.abs(mouse.x - pressedX) + Math.abs(mouse.y - pressedY)
        if (distance >= dragThreshold) {
          if (!dragging) {
            root.barDragWindow = root.targetWindow(slot.activeItem) || root.targetWindow(slot)
            root.barDragScreen = root.barDragWindow ? root.barDragWindow.screen : null
            root.barDragOffsetX = pressedX
            root.barDragOffsetY = pressedY
            root.captureBarDragGhost(slot)
            root.barDragSource = slot
          }
          dragging = true
          root.hideTooltip(slot.activeItem)
        }

        if (dragging) {
          var scenePoint = slot.mapToItem(null, mouse.x, mouse.y)
          var screenPoint = root.barDragScreenPoint(scenePoint)
          root.barDragSceneX = scenePoint.x
          root.barDragSceneY = scenePoint.y
          root.barDragScreenX = screenPoint.x
          root.barDragScreenY = screenPoint.y

          var drop = root.moduleDropAtScene(scenePoint, slot)
          root.barDragTarget = drop ? drop.slot : null
          root.barDragAfter = drop ? drop.after : false
          root.barDragTargetGeometry = drop ? root.dropMarkerRect(drop.slot, drop.after) : null
        }
      }

      onReleased: function(mouse) {
        var wasDragging = dragging
        var targetSlot = root.barDragTarget
        var afterTarget = root.barDragAfter

        if (wasDragging) suppressClick = true

        dragging = false
        root.clearBarDrag()

        if (wasDragging && targetSlot) {
          root.dropBarModuleAtTarget(slot, targetSlot, afterTarget)
          mouse.accepted = true
        } else if (!wasDragging) {
          mouse.accepted = false
        }
      }

      onCanceled: {
        dragging = false
        suppressClick = false
        root.clearBarDrag()
      }

      onClicked: function(mouse) {
        if (suppressClick) {
          suppressClick = false
          mouse.accepted = true
          return
        }

        if (!root.pressModuleClickTarget(slot, mouse.button, mouse.x, mouse.y)) mouse.accepted = false
      }
    }

    onActiveItemChanged: {
      Qt.callLater(injectProps)
      if (region === "right") vistaSkinSettle.restart()
    }
    onModuleSettingsChanged: injectProps()

    function injectProps() {
      var target = activeItem
      // Qt.callLater can land after the slot is torn down (theme switch,
      // shell restart), when root no longer resolves.
      if (!target || !root) return
      if ("bar" in target) target.bar = firstParty
        ? root : root.pluginBarApiFor(pluginApiId, moduleName, registered)
      // A clone keeps its stock name: its settings writes (updateEntryInline)
      // must land on the stock entry, the only one in bar.layout.
      if ("moduleName" in target) target.moduleName = root.vistaStockIdOf(moduleName)
      if ("settings" in target) target.settings = moduleSettings
    }

    Component {
      id: customCommandModuleComponent
      CustomCommandModule { entry: slot.entry }
    }
  }

  component CustomCommandModule: WidgetButton {
    id: customRoot

    required property var entry
    readonly property string moduleName: root.entryId(entry)
    readonly property var settings: root.entrySettings(entry)
    property string outputText: ""
    property string outputTooltip: ""
    property bool outputActive: false

    function setting(name, fallback) {
      var value = settings ? settings[name] : undefined
      return value === undefined || value === null ? fallback : value
    }

    function update(raw) {
      var data = Util.parseModuleJson(raw)
      var klass = data.class || data.alt || ""

      outputText = data.text || String(raw || "").trim()
      outputTooltip = data.tooltip || String(setting("tooltip", ""))
      outputActive = klass === "active" || (Array.isArray(klass) && klass.indexOf("active") !== -1)
    }

    bar: root
    text: outputText || String(setting("text", ""))
    tooltipText: outputTooltip || String(setting("tooltip", ""))
    active: outputActive
    keepSpace: setting("keepSpace", false) === true
    horizontalMargin: Number(setting("horizontalMargin", 7.5))
    verticalPadding: Number(setting("verticalPadding", 6))
    fontSize: Number(setting("fontSize", 12))

    onPressed: function(button) {
      var command = ""
      if (button === Qt.RightButton)
        command = String(setting("onRightClick", ""))
      else if (button === Qt.MiddleButton)
        command = String(setting("onMiddleClick", ""))
      else
        command = String(setting("onClick", ""))

      if (command) root.run(command)
    }

    Process {
      id: customProc
      command: ["bash", "-lc", String(customRoot.setting("exec", ""))]
      stdout: StdioCollector {
        waitForEnd: true
        onStreamFinished: customRoot.update(text)
      }
    }

    Timer {
      interval: Math.max(1, Number(customRoot.setting("interval", 5))) * 1000
      running: String(customRoot.setting("exec", "")) !== ""
      repeat: true
      triggeredOnStart: true
      onTriggered: root.runProcess(customProc)
    }
  }
}
