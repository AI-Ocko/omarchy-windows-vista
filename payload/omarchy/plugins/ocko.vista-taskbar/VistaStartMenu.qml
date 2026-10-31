import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import "../../vista/qml"
import "MenuModel.js" as MenuModel
import qs.Ui

// The Windows Vista Start menu (Task 7). One instance on the Vista Bar root, so it
// exists once per shell, not once per monitor: the usage log it writes needs
// no cross-instance dedupe. Bar.toggleStartMenu(screen) opens it on that
// screen; nothing is mapped while it is closed (LazyLoader).
//
// Geometry is Vista's own 96-dpi layout ([StartPanel] DefaultPaneSize 380 wide,
// header 64, footer 40, two 190 px columns) passed through Style.space(), so
// it grows with base-size like the taskbar. Art and colours are the active
// scheme's msstyles parts (cut by omarchy/vista/bin/vista-taskbar-art) and INI
// values. Every destructive action goes through systemAction(), which honours
// VISTA_DRY_RUN=1 and ~/.local/state/omarchy/vista/dry-run.
Scope {
  id: sm

  required property var bar          // the Vista Bar root
  required property string theme     // active scheme slug
  required property string artDir    // file://…/taskbar/<slug>
  required property string artRoot   // file://…/taskbar

  // [StartPanel.*] / [StartMenu::Toolbar*] / [SysMetrics] per scheme.
  // shadow = UserPane textshadowcolor; prog/progHot/caption = ProgList
  // TextColor/HotTracking/CaptionText; places/placesHot = PlacesList;
  // logoff = Logoff TextColor; groupHot = StartMenu::Toolbar(Hot) TextColor;
  // user/logoffM/more = SizingMargins (l, r, t, b); face = Btnface;
  // capText = CaptionText; frameL/frameB = Window.FrameLeft/Bottom margins.
  readonly property var schemes: ({
    "windows-vista":        { shadow: "#09428B", prog: "#373738", progHot: "#3070D0", caption: "#808080", places: "#0A246A", placesHot: "#5096F8",
                           logoff: "#FFFFFF", groupHot: "#FFFFFF", user: [59, 60, 62, 0], logoffM: [49, 47, 0, 38], more: [3, 0, 0, 1],
                           face: "#ECE9D8", capText: "#FFFFFF", frameL: [2, 2, 0, 0], frameB: [5, 5, 2, 2] },
    "windows-vista-olive":  { shadow: "#183802", prog: "#373738", progHot: "#859066", caption: "#808080", places: "#545F38", placesHot: "#5096F8",
                           logoff: "#41400A", groupHot: "#FFFFFF", user: [59, 60, 62, 0], logoffM: [49, 47, 0, 38], more: [3, 0, 0, 1],
                           face: "#ECE9D8", capText: "#FFFFFF", frameL: [2, 2, 0, 0], frameB: [5, 5, 2, 2] },
    "windows-vista-silver": { shadow: "#1F2226", prog: "#373738", progHot: "#3070D0", caption: "#808080", places: "#0A246A", placesHot: "#5096F8",
                           logoff: "#000000", groupHot: "#FFFFFF", user: [59, 60, 62, 0], logoffM: [49, 47, 0, 38], more: [3, 0, 0, 1],
                           face: "#E0DFE3", capText: "#0E1010", frameL: [1, 1, 0, 0], frameB: [5, 5, 1, 2] },
    "windows-vista-royale": { shadow: "#09428B", prog: "#FFFFFF", progHot: "#3070D0", caption: "#8FB6E3", places: "#FFFFFF", placesHot: "#5096F8",
                           logoff: "#FFFFFF", groupHot: "#FFFFFF", user: [83, 36, 30, 32], logoffM: [49, 47, 18, 20], more: [2, 2, 0, 0],
                           face: "#EBE9ED", capText: "#FFFFFF", frameL: [2, 1, 0, 0], frameB: [5, 5, 1, 2] },
    "windows-vista-zune":   { shadow: "#231814", prog: "#FFFFFF", progHot: "#3070D0", caption: "#B2BCC0", places: "#FFFFFF", placesHot: "#5096F8",
                           logoff: "#FFFFFF", groupHot: "#000000", user: [59, 60, 62, 0], logoffM: [49, 47, 0, 38], more: [2, 2, 0, 1],
                           face: "#E2E2E2", capText: "#FFFFFF", frameL: [2, 1, 0, 0], frameB: [5, 5, 2, 2] }
  })
  readonly property var sc: schemes[theme] || schemes["windows-vista"]

  readonly property string home: Quickshell.env("HOME")
  readonly property string stateDir: home + "/.local/state/omarchy/vista"
  readonly property string usagePath: stateDir + "/start-usage.json"
  readonly property string dryRunFlag: stateDir + "/dry-run"
  readonly property string picturesDir: home + "/.config/omarchy/vista/assets/graphics/account-pictures"  // vista-art: User Account Pictures as PNG
  readonly property string userLogin: Quickshell.env("USER") || "user"
  property string userName: userLogin
  property string pictureUrl: "file://" + picturesDir + "/usertile7.png"  // the chess picture

  function s(n) { return Style.space(n) }

  // ---------------------------------------------------------------- state
  property var screenObj: null
  readonly property bool isOpen: screenObj !== null
  // The window that was active before the menu took focus; target of
  // "Move active window to".
  property var prevWindow: null
  property var mainLists: [[], [], []]   // 0 left, 1 right (places), 2 footer
  // Open cascades, outermost first: { items, parent, parentIndex, x, y, w, h, cellW, rows }
  property var flyouts: []
  property var curs: ({})                // list id -> current row index
  property int focusList: 0              // 0..2 main lists, 3 + n = flyouts[n]
  property bool focusPrimed: false
  property var rowItems: ({})            // "list:index" -> delegate, for anchoring
  property var usage: ({ apps: {}, run: [] })

  function toggle(screen) {
    if (isOpen) close()
    else open(screen)
  }

  function open(screen) {
    if (!screen) return
    runDialog.hide()
    prevWindow = activeWindow()
    Hyprland.refreshWorkspaces()
    mainLists = [buildLeft(), buildRight(), buildFooter()]
    flyouts = []
    curs = ({})
    focusList = 0
    focusPrimed = false
    query = ""
    searchIndex = null
    evaluateGuards()
    screenObj = screen
    bar.vistaStartMenuScreen = String(screen.name || "")
    primeTimer.restart()
  }

  // Hyprland.activeToplevel is null until the first focus event after a
  // shell start; fall back to the most recently focused toplevel from the
  // last toplevel refresh (focusHistoryID 0). Layer surfaces such as this
  // menu never enter the focus history, so this is the window behind it.
  function activeWindow() {
    if (Hyprland.activeToplevel) return Hyprland.activeToplevel
    var list = Hyprland.toplevels.values
    for (var i = 0; i < list.length; i++) {
      var o = list[i].lastIpcObject
      if (o && o.focusHistoryID === 0) return list[i]
    }
    return null
  }
  Component.onCompleted: Hyprland.refreshToplevels()

  function close() {
    hoverTimer.stop()
    screenObj = null
    flyouts = []
    bar.vistaStartMenuScreen = ""
  }

  Timer {
    id: primeTimer
    interval: 75   // KeyboardPanel's Exclusive-then-OnDemand prime
    onTriggered: sm.focusPrimed = true
  }

  // ---------------------------------------------------------------- data
  FileView {
    path: "/etc/passwd"
    blockLoading: true
    printErrors: false
    onLoaded: {
      var lines = String(text()).split("\n")
      for (var i = 0; i < lines.length; i++) {
        var f = lines[i].split(":")
        if (f[0] !== sm.userLogin) continue
        var gecos = String(f[4] || "").split(",")[0].trim()
        if (gecos) sm.userName = gecos
      }
    }
  }

  // omarchy/vista/start-menu.json: { "picture": "<account picture name or absolute path>" }
  FileView {
    path: sm.home + "/.config/omarchy/vista/start-menu.json"
    watchChanges: true
    blockLoading: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: {
      try {
        var p = String(JSON.parse(text()).picture || "usertile7")
        sm.pictureUrl = "file://" + (p.charAt(0) === "/" ? p : sm.picturesDir + "/" + p + ".png")
      } catch (e) {
        console.warn("ocko.vista-taskbar: start-menu.json: " + e)
      }
    }
  }

  // Launch counts and the Run history. Written only by this (single) menu.
  FileView {
    id: usageFile
    path: sm.usagePath
    blockLoading: true
    printErrors: false
    onLoaded: {
      try {
        var u = JSON.parse(text())
        sm.usage = { apps: u.apps || {}, run: u.run || [] }
      } catch (e) {
        console.warn("ocko.vista-taskbar: start-usage.json unreadable, starting fresh: " + e)
      }
    }
  }

  function saveUsage() { usageFile.setText(JSON.stringify(usage, null, 1) + "\n") }

  function recordLaunch(id) {
    var apps = Object.assign({}, usage.apps)
    var rec = apps[id] || { count: 0, last: 0 }
    apps[id] = { count: rec.count + 1, last: Math.floor(Date.now() / 1000) }
    usage = { apps: apps, run: usage.run }
    saveUsage()
  }

  function recordRun(cmd) {
    var run = [cmd].concat(usage.run.filter(function(c) { return c !== cmd })).slice(0, 26)
    usage = { apps: usage.apps, run: run }
    saveUsage()
  }

  function iconUrl(name, fallback) {
    var v = String(name || "")
    if (v.charAt(0) === "/") return "file://" + v
    if (v.indexOf("file://") === 0 || v.indexOf("image://") === 0) return v
    var p = v ? Quickshell.iconPath(v, true) : ""
    return p ? p : Quickshell.iconPath(fallback || "application-x-executable", true)
  }

  function visibleEntries() {
    var all = DesktopEntries.applications.values || []
    return all.filter(function(e) { return e && !e.noDisplay })
  }

  function launchEntry(entry) {
    var id = String(entry.id || "")
    if (!id) return
    // As AppLibrary.launch: a scope under app-graphical.slice via uwsm-app.
    Util.execArgv(["uwsm-app", "--", "gtk-launch", id + ".desktop"])
    recordLaunch(id)
  }

  function run(cmd) { bar.run(cmd) }

  function entryItem(e, kind) {
    return { kind: kind, label: String(e.name || e.id), icon: iconUrl(e.icon),
             run: function() { sm.launchEntry(e) } }
  }

  // ---- left column: pinned, separator, most used, All Programs
  // Left column, Vista's order: the pinned Internet and E-mail entries
  // (bold, with the program underneath), a separator, the most-used
  // programs, and All Programs, which turns the column into the program
  // list in place (allMode) and back.
  property bool allMode: false
  property string openFolder: ""
  function buildLeft() {
    if (allMode) return allList()
    var items = [
      { kind: "big", label: "Internet", sub: "Zen Browser", bold: true, icon: iconUrl("zen-browser", "web-browser"),
        run: function() { sm.run("omarchy-launch-browser") } }
    ]
    var entries = visibleEntries()
    var mail = entries.filter(function(e) { return (e.categories || []).indexOf("Email") !== -1 })[0]
    if (mail) items.push({ kind: "big", label: "E-mail", sub: String(mail.name), bold: true, icon: iconUrl(mail.icon, "internet-mail"),
                           run: function() { sm.launchEntry(mail) } })
    items.push({ kind: "sep" })

    var byId = {}
    for (var i = 0; i < entries.length; i++) byId[String(entries[i].id)] = entries[i]
    var apps = usage.apps
    var ids = Object.keys(apps).filter(function(id) { return !!byId[id] })
    ids.sort(function(a, b) { return (apps[b].count - apps[a].count) || (apps[b].last - apps[a].last) })
    if (ids.length === 0) items.push({ kind: "big", label: "Command Prompt", icon: iconUrl("foot", "utilities-terminal"), run: function() { sm.run("omarchy-launch-terminal") } })
    for (var j = 0; j < Math.min(8, ids.length); j++) items.push(entryItem(byId[ids[j]], "big"))

    items.push({ kind: "more", label: "All Programs", stay: true, run: function() { sm.setAllMode(true) } })
    return items
  }

  function setAllMode(on) {
    allMode = on
    openFolder = ""
    refreshLeft()
    setCur(0, firstSelectable(0, 0, 1))
  }

  function refreshLeft() {
    mainLists = [searching ? searchList() : buildLeft(), mainLists[1], mainLists[2]]
  }

  // All Programs, in place: the loose programs, then the folders, each
  // expanding under itself (Vista's tree), then Back.
  function allList() {
    var all = allPrograms()
    var out = []
    for (var i = 0; i < all.length; i++) {
      var it = all[i]
      if (it.flyout) {
        var name = it.label
        var open = openFolder === name
        out.push({ kind: "folder", label: name, open: open, icon: iconUrl("folder", "inode-directory"), stay: true,
                   run: function() { sm.openFolder = sm.openFolder === this.label ? "" : this.label; sm.refreshLeft() } })
        if (open) {
          var kids = it.flyout()
          for (var k = 0; k < kids.length; k++) out.push(Object.assign({}, kids[k], { kind: "small", indent: true }))
        }
      } else {
        out.push(Object.assign({}, it, { kind: "small" }))
      }
    }
    out.push({ kind: "more", label: "Back", back: true, stay: true, run: function() { sm.setAllMode(false) } })
    return out
  }

  // freedesktop main category -> Vista-style Programs folder (first match wins)
  readonly property var folders: [
    ["Utility", "Accessories"], ["Development", "Development"], ["Education", "Education"],
    ["Game", "Games"], ["Graphics", "Graphics"], ["Network", "Internet"],
    ["AudioVideo", "Multimedia"], ["Audio", "Multimedia"], ["Video", "Multimedia"],
    ["Office", "Office"], ["Science", "Science"], ["Settings", "Settings"], ["System", "System Tools"]
  ]

  function byLabel(a, b) { return a.label.toLowerCase().localeCompare(b.label.toLowerCase()) }

  function allPrograms() {
    var groups = {}
    var loose = []
    var entries = visibleEntries()
    for (var i = 0; i < entries.length; i++) {
      var cats = entries[i].categories || []
      var folder = ""
      for (var f = 0; f < folders.length && !folder; f++) if (cats.indexOf(folders[f][0]) !== -1) folder = folders[f][1]
      var it = entryItem(entries[i], "fly")
      if (folder) (groups[folder] = groups[folder] || []).push(it)
      else loose.push(it)
    }
    var out = Object.keys(groups).map(function(name) {
      var list = groups[name].sort(sm.byLabel)
      return { kind: "fly", label: name, icon: iconUrl("folder", "inode-directory"), flyout: function() { return list } }
    }).sort(byLabel)
    // Vista listed Windows Sidebar at the top level of All Programs.
    loose.push({ kind: "fly", label: "Windows Sidebar",
                 icon: "file://" + sm.home + "/.config/omarchy/vista/assets/graphics/sidebar/RCDATA/5004.png",
                 run: function() { Quickshell.execDetached(["omarchy-shell", "vistasidebar", "toggle"]) } })
    return loose.sort(byLabel).concat(out)
  }

  // ---- right column
  function folderCmd(xdg) {
    return "nautilus --new-window \"$(xdg-user-dir " + xdg + ")\""
  }

  // Right column, Vista's places; the user tile above shows the hovered
  // item's icon (`tile`), the account picture otherwise.
  function ir(id) { return VistaScheme.imageres(id, 48) }
  function buildRight() {
    return [
      { kind: "user", label: sm.userName, tile: "", run: function() { sm.run("omarchy-menu toggle") } },
      { kind: "place", label: "Documents", tile: ir(112), run: function() { sm.run(sm.folderCmd("DOCUMENTS")) } },
      { kind: "place", label: "Pictures", tile: ir(113), run: function() { sm.run(sm.folderCmd("PICTURES")) } },
      { kind: "place", label: "Music", tile: ir(108), run: function() { sm.run(sm.folderCmd("MUSIC")) } },
      { kind: "place", label: "Games", tile: ir(24), stay: true, run: function() { sm.setQuery("game") } },
      { kind: "psep" },
      { kind: "place", label: "Search", tile: ir(177), stay: true, run: function() { sm.focusSearch() } },
      { kind: "place", label: "Recent Items", tile: ir(117), run: function() { sm.run("nautilus --new-window recent:///") } },
      { kind: "place", label: "Computer", tile: ir(109), run: function() { sm.run("nautilus --new-window /") } },
      { kind: "place", label: "Network", tile: ir(120), run: function() { sm.run("nautilus --new-window network:///") } },
      { kind: "place", label: "Connect To", tile: ir(25), run: function() { sm.run("omarchy-launch-wifi") } },
      { kind: "psep" },
      // Control Panel = the Omarchy menu root in its Vista clone (ocko.vista-menu).
      { kind: "place", label: "Control Panel", tile: ir(27),
        run: function() { sm.run("omarchy-shell shell summon omarchy.menu '{\"menu\":\"root\",\"vista\":\"control-panel\"}'") } },
      { kind: "place", label: "Default Programs", tile: ir(87), run: function() { sm.run("omarchy-launch-tui xdg-mime-browser 2>/dev/null || omarchy-menu toggle") } },
      { kind: "place", label: "Help and Support", tile: ir(99), run: function() { sm.run("omarchy-launch-webapp 'https://omarchy.org/manual/'") } }
    ]
  }

  // Footer: the power button (Vista's default: Sleep), the lock button and
  // the arrow with the full list. Every item runs through systemAction.
  function powerItems() {
    function act(label, what, cmd) { return { kind: "fly", icon: "", label: label, run: function() { sm.systemAction(what, cmd) } } }
    return [
      act("Switch User", "lock", "omarchy-system-lock"),
      act("Log Off", "logout", "omarchy-system-logout"),
      act("Lock", "lock", "omarchy-system-lock"),
      { kind: "sep" },
      act("Restart", "reboot", "omarchy-system-reboot"),
      act("Sleep", "suspend", "systemctl suspend"),
      act("Hibernate", "hibernate", "systemctl hibernate"),
      act("Shut Down", "shutdown", "omarchy-system-shutdown")
    ]
  }
  function buildFooter() {
    return [
      { kind: "power", label: "Sleep", frame: 2, run: function() { sm.systemAction("suspend", "systemctl suspend") } },
      { kind: "lock", label: "Lock this computer", frame: 1, run: function() { sm.systemAction("lock", "omarchy-system-lock") } },
      { kind: "arrow", label: "", flyout: powerItems }
    ]
  }

  property var tileItem: null
  function focusSearch() { if (searchBoxRef) searchBoxRef.input.forceActiveFocus() }
  property var searchBoxRef: null

  // ---- Start Search box: while it holds a query the left column lists the
  // matching apps and Omarchy menu features, ranked and run as the Vista
  // Control Panel does (ocko.vista-menu/MenuModel.js). Keyboard, hover and
  // activation are the left column's own.
  property string query: ""
  readonly property bool searching: query.trim() !== ""
  readonly property string menuPath: (Quickshell.env("OMARCHY_PATH") || "/usr/share/omarchy") + "/default/omarchy/omarchy-menu.jsonc"
  property var defaultMenu: []
  property var userMenu: []
  property var searchWhen: ({})
  property var searchChecked: ({})
  property var searchIndex: null         // menu + app rows, built on first query per open

  FileView {
    path: sm.menuPath
    watchChanges: true
    printErrors: false
    onLoaded: sm.defaultMenu = MenuModel.parseMenuJsonc(text())
    onFileChanged: reload()
  }
  FileView {
    path: sm.home + "/.config/omarchy/extensions/omarchy-menu.jsonc"
    watchChanges: true
    printErrors: false
    onLoaded: sm.userMenu = MenuModel.parseMenuJsonc(text())
    onLoadFailed: sm.userMenu = []
    onFileChanged: reload()
  }

  // `when:` / `checked:` guards: one bash per open, as the menu does.
  function evaluateGuards() {
    if (guardProc.running) return
    var script = MenuModel.guardScript(MenuModel.mergeMenuSources(defaultMenu, userMenu).items)
    if (!script) return
    guardProc.collected = ""
    guardProc.command = ["bash", "-lc", script]
    guardProc.running = true
  }
  Process {
    id: guardProc
    property string collected: ""
    stdout: SplitParser { onRead: function(data) { guardProc.collected += data + "\n" } }
    onExited: function(exitCode, exitStatus) {
      if (exitCode !== 0 || exitStatus !== 0) return
      var guards = MenuModel.parseGuardOutput(guardProc.collected)
      sm.searchWhen = guards.when
      sm.searchChecked = guards.checked
      if (sm.searching) sm.setQuery(sm.query)
    }
  }

  function setQuery(text) {
    query = String(text || "")
    closeFlyoutsFrom(0)
    focusList = 0
    var left = searching ? searchList() : buildLeft()
    mainLists = [left, mainLists[1], mainLists[2]]
    curs = ({})
    if (searching) setCur(0, firstSelectable(0, 0, 1))
  }

  function searchList() {
    if (!searchIndex) {
      var entries = visibleEntries()
      var byApp = {}
      var rows = []
      for (var i = 0; i < entries.length; i++) {
        var e = entries[i]
        byApp[String(e.id)] = e
        rows.push(MenuModel.appRow(e, String(e.name || e.id), String(e.genericName || "")))
      }
      var menu = MenuModel.mergeMenuSources(defaultMenu, userMenu)
      var merged = MenuModel.mergeAppRows(menu.items, menu.itemOrder, rows)
      searchIndex = { items: merged.items, order: merged.itemOrder, apps: byApp }
    }
    var ix = searchIndex
    var hits = MenuModel.searchRows(ix.items, ix.order, searchWhen, query).slice(0, 8)
    var list = hits.map(function(entry) { return searchItem(entry, ix) })
    if (!list.length)
      list.push({ kind: "big", label: "No items match your search.", icon: VistaScheme.icon(23, 32), disabled: true })
    list.push({ kind: "more", label: "All Programs", stay: true, run: function() { sm.setQuery(""); sm.setAllMode(true) } })
    return list
  }

  function searchItem(entry, ix) {
    if (entry.kind === "app") {
      var app = ix.apps[entry.appId]
      return { kind: "big", label: entry.label, icon: iconUrl(entry.appIcon), run: function() { sm.launchEntry(app) } }
    }
    var where = MenuModel.parentPathFor(ix.items, entry.id)
    var item = { kind: "big", label: MenuModel.labelFor(entry, searchChecked), sub: "In: " + (where || "Control Panel"),
                 icon: VistaScheme.icon(MenuModel.vistaIconId(entry.id, entry.kind, entry.action), 32) }
    if (entry.kind === "menu" || entry.kind === "link") {
      // A submenu opens the Vista Control Panel there ("vista" keeps it from
      // bouncing back to this Start menu).
      var route = JSON.stringify({ menu: entry.kind === "link" ? entry.target : entry.id, vista: "control-panel" })
      item.run = function() { Util.execArgv(["omarchy-shell", "shell", "summon", "omarchy.menu", route]) }
    } else {
      var command = MenuModel.vistaCommand(entry.action, sm.home)
      item.run = function() { Util.execDetached(command) }
    }
    return item
  }

  // ---- workspaces (live: labels are functions so titles/counts update)
  function workspaceList() {
    var list = (Hyprland.workspaces.values || []).filter(function(w) { return w.id > 0 })
    return list.sort(function(a, b) { return a.id - b.id })
  }

  function workspaceTitle(ws) {
    var t = ws.lastIpcObject ? String(ws.lastIpcObject.lastwindowtitle || "") : ""
    var tl = ws.toplevels ? ws.toplevels.values : []
    if (!t && tl.length) t = String(tl[0].title || "")
    if (!tl.length) return "(empty)"
    return t.length > 48 ? t.slice(0, 47) + "…" : t
  }

  function workspaceItems() {
    return workspaceList().map(function(ws) {
      return {
        kind: "fly", icon: "",
        label: function() {
          var n = ws.toplevels ? ws.toplevels.values.length : 0
          return ws.id + "   " + sm.workspaceTitle(ws) + "   (" + n + (n === 1 ? " window)" : " windows)")
        },
        check: function() { return !!ws.focused },
        run: function() { Hyprland.dispatch("hl.dsp.focus({ workspace = " + ws.id + " })") }
      }
    })
  }

  function moveItems() {
    var win = prevWindow
    var here = win && win.workspace ? win.workspace.id : 0
    var ids = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]
    workspaceList().forEach(function(w) { if (ids.indexOf(w.id) === -1) ids.push(w.id) })
    return ids.map(function(id) {
      return {
        kind: "fly", icon: "", disabled: !win || id === here,
        label: "Workspace " + id,
        check: function() { return id === here },
        run: function() {
          if (!sm.prevWindow) return
          Hyprland.dispatch('hl.dsp.window.move({ workspace = "' + id + '", follow = false, window = "' + sm.bar.vistaSelector(sm.prevWindow) + '" })')
        }
      }
    })
  }

  // ---------------------------------------------------------------- actions
  // Remembered for the dialogs, which open after the menu has closed.
  property var lastScreen: null

  // Every destructive command (lock, logout, suspend, shutdown, reboot)
  // passes through here. Dry run: VISTA_DRY_RUN=1 in the shell's environment,
  // or the flag file, logs the command instead of running it.
  //
  // Vista sound first: Log Off plays "logoff", Turn Off and Restart "shutdown"
  // (Vista made no sound for Switch User/lock or Stand By). vista-sound blocks
  // until the sound ends, so the action follows it; `timeout` caps the wait
  // and guarantees onExited even if the script is missing. Dry run still
  // plays the sound.
  property var pendingAction: null
  readonly property string vistaSound: home + "/.config/omarchy/vista/bin/vista-sound"
  function systemAction(what, command) {
    pendingAction = { what: what, command: command }
    if (soundProc.running) return
    var sound = what === "logout" ? "logoff" : (what === "shutdown" || what === "reboot" ? "shutdown" : "")
    if (sound === "") { proceedAction(); return }
    soundProc.command = ["timeout", "7", vistaSound, sound]
    soundProc.running = true
  }

  function proceedAction() {
    var a = pendingAction
    if (!a) return
    if (Quickshell.env("VISTA_DRY_RUN") === "1") {
      pendingAction = null
      console.info("ocko.vista-taskbar: DRY RUN (VISTA_DRY_RUN=1) " + a.what + ": would run `" + a.command + "`")
      return
    }
    dryCheck.running = true
  }

  Process {
    id: soundProc
    onExited: sm.proceedAction()
  }

  Process {
    id: dryCheck
    command: ["test", "-e", sm.dryRunFlag]
    onExited: function(code) {
      var a = sm.pendingAction
      if (!a) return
      sm.pendingAction = null
      if (code === 0) console.info("ocko.vista-taskbar: DRY RUN (" + sm.dryRunFlag + ") " + a.what + ": would run `" + a.command + "`")
      else sm.run(a.command)
    }
  }

  function listAt(id) { return id < 3 ? (mainLists[id] || []) : ((flyouts[id - 3] || {}).items || []) }

  function labelOf(item) { return typeof item.label === "function" ? item.label() : String(item.label || "") }

  function selectable(item) { return item && item.kind !== "sep" && item.kind !== "psep" }

  function setCur(id, index) {
    var c = Object.assign({}, curs)
    c[id] = index
    curs = c
  }

  function hasChild(id, index) {
    for (var i = 0; i < flyouts.length; i++)
      if (flyouts[i].parent === id && flyouts[i].parentIndex === index) return true
    return false
  }

  function closeFlyoutsFrom(level) {
    if (flyouts.length > level) flyouts = flyouts.slice(0, level)
    var c = Object.assign({}, curs)
    for (var k in c) if (Number(k) >= 3 + level) delete c[k]
    curs = c
  }

  function levelFor(id) { return id < 3 ? 0 : id - 3 + 1 }

  function registerRow(id, index, item) { var r = rowItems; r[id + ":" + index] = item }
  function unregisterRow(id, index, item) { if (rowItems[id + ":" + index] === item) delete rowItems[id + ":" + index] }

  function openFlyout(id, index) {
    var item = listAt(id)[index]
    var anchor = rowItems[id + ":" + index]
    if (!item || !item.flyout || item.disabled || !anchor || !screenObj) return false
    var level = levelFor(id)
    if (hasChild(id, index)) return true
    var items = item.flyout()
    var rowH = s(22)
    var maxW = 0
    for (var i = 0; i < items.length; i++) {
      measure.text = labelOf(items[i])
      maxW = Math.max(maxW, measure.advanceWidth)
    }
    var cellW = Math.min(s(420), Math.max(s(140), Math.ceil(maxW) + s(10 + 16 + 8 + 26)))
    var availH = screenObj.height - bar.barSize
    var rows = Math.max(1, Math.floor((availH - s(4)) / rowH))
    var cols = Math.max(1, Math.ceil(items.length / rows))
    rows = Math.min(rows, Math.max(1, items.length))
    var w = cols * cellW
    var h = rows * rowH + s(4)
    var p = anchor.mapToItem(null, 0, 0)
    var x = p.x + anchor.width
    if (x + w > screenObj.width) x = Math.max(0, p.x - w)
    var y = p.y
    if (y + h > availH) y = p.y + anchor.height - h
    if (y < 0) y = Math.max(0, availH - h)
    var next = flyouts.slice(0, level)
    next.push({ items: items, parent: id, parentIndex: index, x: x, y: y, w: w, h: h, cellW: cellW, rows: rows })
    closeFlyoutsFrom(level)
    flyouts = next
    return true
  }

  function activate(id, index) {
    var item = listAt(id)[index]
    if (!selectable(item) || item.disabled) return
    if (item.flyout) {
      hoverTimer.stop()
      if (openFlyout(id, index)) {
        focusList = 3 + levelFor(id)
        setCur(focusList, firstSelectable(focusList, 0, 1))
      }
      return
    }
    lastScreen = screenObj
    // Rows that change the menu itself (All Programs, folders, Back, Games,
    // Search) keep it open.
    if (item.stay) { if (item.run) item.run(); return }
    close()
    if (item.run) item.run()
  }

  function firstSelectable(id, from, dir) {
    var list = listAt(id)
    for (var n = 0, i = from; n < list.length; n++, i = (i + dir + list.length) % list.length)
      if (selectable(list[i]) && !list[i].disabled) return i
    return -1
  }

  // Keyboard, through PanelKeyCatcher.
  function keyMove(dx, dy) {
    hoverTimer.stop()
    var id = focusList
    var cur = curs[id] === undefined ? -1 : curs[id]
    var list = listAt(id)
    if (dy !== 0) {
      var start = cur < 0 ? (dy > 0 ? 0 : list.length - 1) : (cur + dy + list.length) % list.length
      setCur(id, firstSelectable(id, start, dy))
      if (id < 3) closeFlyoutsFrom(0)
      else closeFlyoutsFrom(levelFor(id))
      return
    }
    if (dx > 0) {
      var item = list[cur]
      if (item && item.flyout && !item.disabled) activate(id, cur)
      else if (id === 0) focusMain(1)
    } else if (dx < 0) {
      if (id >= 3) {
        var parent = flyouts[id - 3].parent
        closeFlyoutsFrom(id - 3)
        focusList = parent
      } else if (id === 1) {
        focusMain(0)
      }
    }
  }

  function focusMain(id) {
    closeFlyoutsFrom(0)
    curs = ({})
    focusList = id
    setCur(id, firstSelectable(id, 0, 1))
  }

  function keyActivate() {
    var cur = curs[focusList]
    if (cur !== undefined && cur >= 0) activate(focusList, cur)
    else if (searching) activate(0, firstSelectable(0, 0, 1))
  }

  function keyEscape() {
    if (searching && !flyouts.length) {
      setQuery("")
    } else if (flyouts.length) {
      var parent = flyouts[flyouts.length - 1].parent
      closeFlyoutsFrom(flyouts.length - 1)
      focusList = parent
    } else {
      close()
    }
  }

  // Mouse hover: Vista opens a cascade after a short hover and closes deeper
  // ones when the pointer settles on a sibling. One shared timer, so the
  // latest hover wins and a diagonal sweep into a cascade does not close it.
  property int hoverList: -1
  property int hoverIndex: -1
  function hover(id, index) {
    focusList = id
    var c = Object.assign({}, curs)
    // Vista: only the column under the pointer (and the parents of open
    // cascades) stays highlighted.
    if (id < 3) for (var j = 0; j < 3; j++) if (j !== id && !flyouts.some(function(f) { return f.parent === j })) delete c[j]
    c[id] = index
    curs = c
    hoverList = id
    hoverIndex = index
    hoverTimer.restart()
  }

  Timer {
    id: hoverTimer
    interval: 350
    onTriggered: {
      var item = sm.listAt(sm.hoverList)[sm.hoverIndex]
      if (!item) return
      if (item.flyout && !item.disabled) sm.openFlyout(sm.hoverList, sm.hoverIndex)
      else sm.closeFlyoutsFrom(sm.levelFor(sm.hoverList))
    }
  }

  TextMetrics {
    id: measure
    font.family: "Segoe UI"
    font.pixelSize: Style.font.bodySmall
  }

  // ---------------------------------------------------------------- view
  // Vista's Start menu (aero.msstyles StartPanel parts, assets/graphics/
  // startmenu/<glass|basic>/ from bin/vista-art): a glass frame; the white
  // program list (PROGLIST) with All Programs (MOREPROGRAMS) and the Start
  // Search box (OPENBOX) under it; the dark places list (PLACESLIST) on the
  // right with the user picture (USERPICTURE) over its top edge; power, lock
  // and the arrow under it. Rows: big/small (programs), folder (All
  // Programs, expands in place), more (All Programs / Back), sep/psep,
  // user/place (right column), power/lock/arrow (footer), fly (the arrow's
  // menu). Text is Segoe UI 9 pt.
  readonly property string smArt: "file://" + home + "/.config/omarchy/vista/assets/graphics/startmenu/" + (theme === "windows-vista-basic" ? "basic" : "glass")
  readonly property color glassTint: ({ "windows-vista": "#B8233A5C", "windows-vista-graphite": "#D0161616",
                                        "windows-vista-frost": "#B09AB4C8", "windows-vista-basic": "#FF1E2C40" })[theme] || "#B8233A5C"

  component MenuRow: Item {
    id: row
    required property int listId
    required property int index
    readonly property var item: sm.listAt(listId)[index] || ({ kind: "sep" })
    readonly property string kind: item.kind
    readonly property bool hot: sm.curs[listId] === index && !item.disabled
    readonly property bool isSep: kind === "sep" || kind === "psep"
    readonly property string label: sm.labelOf(item)
    readonly property bool dark: kind === "place" || kind === "user"
    readonly property color textColor: item.disabled ? "#8D8D8D" : dark ? "#FFFFFF" : "#000000"

    implicitHeight: isSep ? sm.s(9)
      : kind === "big" ? sm.s(item.sub ? 40 : 36) : kind === "small" || kind === "folder" ? sm.s(22)
      : kind === "place" ? sm.s(24) : kind === "user" ? sm.s(28) : kind === "more" ? sm.s(28)
      : kind === "power" || kind === "lock" || kind === "arrow" ? sm.s(24) : sm.s(22)
    implicitWidth: kind === "power" || kind === "lock" ? sm.s(36) : kind === "arrow" ? sm.s(22) : 0

    Component.onCompleted: sm.registerRow(listId, index, row)
    Component.onDestruction: sm.unregisterRow(listId, index, row)

    // separators: PROGLISTSEPARATOR / PLACESLISTSEPARATOR at their own size
    Image {
      visible: row.isSep && row.listId < 3
      anchors.centerIn: parent
      source: sm.smArt + (row.kind === "sep" ? "/progsep.png" : "/placesep.png")
      width: Math.min(row.width, sourceSize.width * Style.spaceReal(1))
      height: Math.max(1, sourceSize.height * Style.spaceReal(1))
    }
    Rectangle {
      visible: row.isSep && row.listId >= 3
      anchors.centerIn: parent
      width: row.width - sm.s(30)
      height: 1
      color: "#D7D7D7"
    }

    // hot tracking: StartMenuHover::TreeView (programs), the places list's
    // LISTITEM hot (right column), Vista's menu highlight in the arrow menu
    VistaArt {
      visible: row.hot && (row.kind === "big" || row.kind === "small" || row.kind === "folder" || row.kind === "more")
      anchors.fill: parent
      source: sm.smArt + "/prog-hot.png"
      margins: [3, 3, 3, 3]
    }
    VistaArt {
      visible: row.hot && (row.kind === "place" || row.kind === "user")
      anchors.fill: parent
      source: sm.smArt + "/places-hot.png"
      margins: [36, 36, 4, 4]
    }
    Rectangle {
      visible: row.hot && row.kind === "fly"
      anchors.fill: parent
      anchors.margins: sm.s(2)
      radius: sm.s(3)
      color: "#E8F2FB"
      border.color: "#A8D8F6"
    }

    // icon (programs only; the right column is text, as in Vista)
    Image {
      id: icon
      visible: row.kind === "big" || row.kind === "small" || row.kind === "folder"
      x: sm.s(row.item.indent ? 22 : 4)
      anchors.verticalCenter: parent.verticalCenter
      width: sm.s(row.kind === "big" ? 32 : 16)
      height: width
      sourceSize.width: width * 2
      sourceSize.height: height * 2
      source: visible ? row.item.icon : ""
      opacity: row.item.disabled ? 0.5 : 1
      asynchronous: true
    }

    Column {
      visible: !row.isSep && row.kind !== "more" && row.kind !== "power" && row.kind !== "lock" && row.kind !== "arrow"
      x: icon.visible ? icon.x + icon.width + sm.s(6) : sm.s(row.kind === "fly" ? 26 : 10)
      width: row.width - x - sm.s(6)
      anchors.verticalCenter: parent.verticalCenter
      spacing: 0

      Text {
        width: parent.width
        text: row.label
        elide: Text.ElideRight
        wrapMode: row.item.disabled ? Text.WordWrap : Text.NoWrap
        maximumLineCount: 2
        color: row.textColor
        font.family: "Segoe UI"
        font.pixelSize: Style.font.bodySmall
        font.bold: !!row.item.bold || row.kind === "user"
      }
      Text {
        visible: !!row.item.sub
        width: parent.width
        text: row.item.sub || ""
        elide: Text.ElideRight
        color: "#5A5A5A"
        font.family: "Segoe UI"
        font.pixelSize: Style.font.bodySmall
      }
    }

    // All Programs / Back: MOREPROGRAMSARROW(BACK), then the label
    Row {
      visible: row.kind === "more"
      x: sm.s(8)
      anchors.verticalCenter: parent.verticalCenter
      spacing: sm.s(6)
      Image {
        anchors.verticalCenter: parent.verticalCenter
        source: sm.smArt + (row.item.back ? "/back-arrow-" : "/more-arrow-") + (row.hot ? 1 : 0) + ".png"
        width: sourceSize.width * Style.spaceReal(1)
        height: sourceSize.height * Style.spaceReal(1)
      }
      Text {
        anchors.verticalCenter: parent.verticalCenter
        text: row.label
        color: row.textColor
        font.family: "Segoe UI"
        font.pixelSize: Style.font.bodySmall
      }
    }

    // footer: one 24 px cell of LOGOFFBUTTONS (normal / hot), or the
    // LOGOFFSPLITBUTTONDROPDOWN arrow
    Image {
      visible: row.kind === "power" || row.kind === "lock"
      anchors.centerIn: parent
      width: sm.s(24)
      height: sm.s(24)
      source: visible ? sm.smArt + "/footer-" + (row.hot ? 1 : 0) + "-" + row.item.frame + ".png" : ""
    }
    Item {
      visible: row.kind === "arrow"
      anchors.fill: parent
      Image {
        anchors.fill: parent
        source: sm.smArt + "/split-" + (row.hot ? 1 : 0) + ".png"
      }
      Image {
        anchors.centerIn: parent
        width: sm.s(7)
        height: sm.s(9)
        sourceClipRect: Qt.rect(0, 0, 7, 9)
        source: sm.smArt + "/split-glyph.png"
      }
    }

    // folder triangle (expanded / collapsed)
    Text {
      visible: row.kind === "folder"
      anchors.right: parent.right
      anchors.rightMargin: sm.s(8)
      anchors.verticalCenter: parent.verticalCenter
      text: row.item.open ? "▾" : "▸"
      color: "#555555"
      font.pixelSize: Style.font.bodySmall
    }

    MouseArea {
      enabled: !row.isSep
      anchors.fill: parent
      hoverEnabled: true
      onEntered: {
        sm.hover(row.listId, row.index)
        if (row.listId === 1) sm.tileItem = row.item
      }
      onExited: {
        if (sm.curs[row.listId] === row.index && !sm.hasChild(row.listId, row.index) && !row.item.flyout) sm.setCur(row.listId, -1)
        if (row.listId === 1 && sm.tileItem === row.item) sm.tileItem = null
      }
      onClicked: sm.activate(row.listId, row.index)
    }
  }

  LazyLoader {
    active: sm.isOpen

    PanelWindow {
      id: win
      screen: sm.screenObj
      visible: true
      color: "transparent"
      exclusionMode: ExclusionMode.Ignore
      anchors { top: true; bottom: true; left: true; right: true }

      WlrLayershell.namespace: "vista-start-menu"
      WlrLayershell.layer: WlrLayer.Overlay
      WlrLayershell.keyboardFocus: sm.focusPrimed ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.Exclusive

      // A click anywhere off the menu (the taskbar included, so the orb
      // toggles it shut) closes it.
      MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.AllButtons
        onPressed: sm.close()
      }

      // The search box holds focus, so printable keys type into it; only what
      // a TextInput ignores (Up/Down, Enter, Esc, Tab) drives the menu.
      PanelKeyCatcher {
        id: keys
        anchors.fill: parent
        Component.onCompleted: Qt.callLater(function() { searchBox.input.forceActiveFocus() })
        onMoveRequested: function(dx, dy) { sm.keyMove(dx, dy) }
        onActivateRequested: sm.keyActivate()
        onCloseRequested: sm.keyEscape()
        onTabRequested: function(dir) { sm.focusMain(((sm.focusList < 3 ? sm.focusList : 0) + dir + 3) % 3) }

        Item {
          id: menu
          // Vista at 96 dpi: a 7 px glass frame, the 250 px program list, the
          // 150 px places column; the user picture rides over the top edge.
          readonly property int pad: sm.s(7)
          readonly property int leftW: sm.s(250)
          readonly property int rightW: sm.s(150)
          readonly property int tileOver: sm.s(18)
          x: sm.s(2)
          y: win.height - sm.bar.barSize - height
          width: pad + leftW + rightW + pad
          height: sm.s(510)

          MouseArea { anchors.fill: parent; acceptedButtons: Qt.AllButtons }

          // glass frame (blurred by the layer rule in omarchy/vista/hypr/late.lua)
          Rectangle {
            anchors.fill: parent
            anchors.topMargin: menu.tileOver
            radius: sm.s(6)
            color: sm.glassTint
            border.color: "#B0000000"
            border.width: 1
            Rectangle {
              anchors.fill: parent
              anchors.margins: 1
              radius: sm.s(5)
              color: "transparent"
              border.color: "#50FFFFFF"
            }
          }

          // ---- left: program list, All Programs, Start Search
          VistaArt {
            id: progBg
            x: menu.pad
            y: menu.tileOver + menu.pad
            width: menu.leftW
            height: menu.height - y - searchArea.height - menu.pad
            source: sm.smArt + "/proglist.png"
            margins: [13, 6, 13, 0]
            smooth: false
          }
          Flickable {
            id: leftFlick
            x: progBg.x + sm.s(3)
            y: progBg.y + sm.s(6)
            width: progBg.width - sm.s(6)
            height: progBg.height - moreRow.height - sm.s(6 + 6)
            contentHeight: leftCol.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            Column {
              id: leftCol
              width: leftFlick.width
              Repeater {
                model: Math.max(0, sm.mainLists[0].length - 1)
                MenuRow { listId: 0; width: leftCol.width }
              }
            }
          }
          Image {
            x: progBg.x + (progBg.width - width) / 2
            y: moreRow.y - sm.s(4)
            source: sm.smArt + "/progsep.png"
            width: Math.min(progBg.width - sm.s(12), sourceSize.width * Style.spaceReal(1))
            height: Math.max(1, sourceSize.height * Style.spaceReal(1))
          }
          MenuRow {
            id: moreRow
            listId: 0
            index: Math.max(0, sm.mainLists[0].length - 1)
            x: progBg.x + sm.s(3)
            y: progBg.y + progBg.height - height - sm.s(4)
            width: progBg.width - sm.s(6)
          }
          // Start Search: OPENBOX
          Item {
            id: searchArea
            x: menu.pad
            y: menu.height - height - menu.pad
            width: menu.leftW
            height: sm.s(32)
            VistaArt {
              anchors.fill: parent
              anchors.topMargin: sm.s(4)
              source: sm.smArt + "/openbox.png"
              margins: [10, 3, 8, 11]
            }
            VistaTextField {
              id: searchBox
              x: sm.s(8)
              anchors.verticalCenter: parent.verticalCenter
              anchors.verticalCenterOffset: sm.s(2)
              width: parent.width - sm.s(16)
              placeholder: "Start Search"
              Component.onCompleted: sm.searchBoxRef = searchBox
              input.onTextChanged: if (input.text !== sm.query) sm.setQuery(input.text)
              Connections {
                target: sm
                function onQueryChanged() { if (searchBox.text !== sm.query) searchBox.text = sm.query }
              }
            }
          }

          // ---- right: PLACESLIST with the user picture over its top
          VistaArt {
            id: placesBg
            x: menu.pad + menu.leftW
            y: menu.tileOver + menu.pad
            width: menu.rightW
            height: progBg.height
            source: sm.smArt + "/placeslist.png"
            margins: [0, 7, 7, 2]
            smooth: false
          }
          Item {
            id: tile
            x: placesBg.x + (placesBg.width - width) / 2
            y: 0
            width: sm.s(55)
            height: sm.s(55)
            Image {
              x: sm.s(9)
              y: sm.s(8)
              width: sm.s(39)
              height: sm.s(40)
              fillMode: Image.PreserveAspectCrop
              smooth: true
              source: sm.tileItem && sm.tileItem.tile ? sm.tileItem.tile : sm.pictureUrl
            }
            VistaArt {
              anchors.fill: parent
              source: sm.smArt + "/userpic.png"
              margins: [10, 10, 12, 12]
            }
          }
          Column {
            id: rightCol
            x: placesBg.x + sm.s(4)
            y: tile.y + tile.height + sm.s(6)
            width: placesBg.width - sm.s(8)
            Repeater {
              model: sm.mainLists[1].length
              MenuRow { listId: 1; width: rightCol.width }
            }
          }
          // power, lock, arrow
          Row {
            x: placesBg.x + sm.s(8)
            anchors.verticalCenter: searchArea.verticalCenter
            anchors.verticalCenterOffset: sm.s(2)
            spacing: sm.s(2)
            Repeater {
              model: sm.mainLists[2].length
              MenuRow { listId: 2; width: implicitWidth }
            }
          }
        }

        // ---- the arrow's menu (Vista's popup menu: white, grey border)
        Repeater {
          model: sm.flyouts.length
          Rectangle {
            id: fly
            required property int index
            readonly property var f: sm.flyouts[index] || ({ items: [], rows: 1, cellW: 0 })
            x: f.x
            y: f.y
            width: f.w
            height: f.h
            color: "#F0F0F0"
            border.color: "#979797"
            MouseArea { anchors.fill: parent; acceptedButtons: Qt.AllButtons; hoverEnabled: true }
            Grid {
              y: sm.s(2)
              flow: Grid.TopToBottom
              rows: fly.f.rows
              Repeater {
                model: fly.f.items.length
                MenuRow { listId: 3 + fly.index; width: fly.f.cellW }
              }
            }
          }
        }
      }
    }
  }

  // Other monitors: a transparent catcher, so a click there closes the menu.
  Variants {
    model: sm.isOpen ? Quickshell.screens : []
    PanelWindow {
      required property var modelData
      screen: modelData
      visible: sm.isOpen && !!sm.screenObj && modelData.name !== sm.screenObj.name
      color: "transparent"
      exclusionMode: ExclusionMode.Ignore
      anchors { top: true; bottom: true; left: true; right: true }
      WlrLayershell.namespace: "vista-start-menu-dismiss"
      WlrLayershell.layer: WlrLayer.Overlay
      WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
      MouseArea { anchors.fill: parent; acceptedButtons: Qt.AllButtons; onPressed: sm.close() }
    }
  }

  VistaExitDialog { id: exitDialog; menu: sm }
  VistaRunDialog { id: runDialog; menu: sm }
}
