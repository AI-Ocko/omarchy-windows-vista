import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "MenuModel.js" as MenuModel
// Vista: the shared Vista chrome, and the shell's AppLibrary for the fallback below.
import "../../vista/qml"
import qs.services as VistaServices

Item {
  id: root

  // Injected by omarchy-shell when this plugin is summoned.
  property string omarchyPath: Quickshell.env("OMARCHY_PATH")
  property var shell: null
  property var manifest: null

  // Plugin lifecycle hooks. The host calls open(payloadJson) after
  // `omarchy-shell shell summon omarchy.menu ...` and close() when hidden.
  property string pendingInitialMenu: "root"

  function open(payloadJson) {
    var payload = ({})
    try { payload = JSON.parse(payloadJson || "{}") } catch (e) { payload = ({}) }

    if (payload.fontFamily) root.fontFamily = payload.fontFamily
    // A shell that started mid-update may never have read the shipped menu
    // whole; reading it again here keeps the menu from opening empty.
    if (root.defaultMenuItems.length === 0) defaultMenuFile.reload()

    if (payload.mode === "select" || payload.mode === "input") {
      root.openDmenu(payload)
    } else {
      var route = String(payload.initialMenu || payload.menu || "root")
      // Vista: a bare root request (SUPER+SPACE, `omarchy-menu`) opens the Start
      // menu. The Start menu's Control Panel adds "vista", which opens the root
      // here instead, so the two never bounce off each other.
      if (route === "root" && !payload.vista) root.vistaOpenStartMenu()
      // Vista: the system (power) menu is Vista's "Shut Down Windows" dialog.
      else if (route === "system" && !payload.vista) root.vistaOpenShutdown()
      // Vista: the app launcher (`omarchy-menu toggle apps`, stock's dock app
      // grid, which is off under Vista) is the Start menu and its search box.
      else if (["apps", "app", "applications"].indexOf(route) !== -1 && !payload.vista) root.vistaOpenStartMenu()
      else root.openRoute(route)
    }
  }

  function close() {
    root.cancel()
  }

  function refresh() {
    defaultMenuFile.reload()
    userMenuFile.reload()
    languageFile.reload()
    menuCatalogFile.reload()
    return "ok"
  }

  function ping() { return "ok" }

  property string fontFamily: Style.font.menuFamily
  // JSONC menu definitions. The shell parses both at startup and merges
  // the user file on top of the defaults, so the keybind → IPC → visible
  // path doesn't have to shell out to bash + jq on every open.
  property string defaultMenuPath: omarchyPath + "/default/omarchy/omarchy-menu.jsonc"
  property string userMenuPath: Quickshell.env("HOME") + "/.config/omarchy/extensions/omarchy-menu.jsonc"
  // Display language for the shipped rows. The code lives in
  // ~/.config/omarchy/language (omarchy-language owns it); a missing file
  // means English. The catalog at default/i18n/<code>/menu.json is applied
  // to the default items before the user extension merges on top, so a
  // user's own rows and retitles always win.
  property string language: "en"
  property var menuCatalog: ({})
  readonly property string languagePath: Quickshell.env("OMARCHY_LANGUAGE_FILE") || ((Quickshell.env("XDG_CONFIG_HOME") || (Quickshell.env("HOME") + "/.config")) + "/omarchy/language")
  property var defaultMenuItems: []
  property var userMenuItems: []
  // Whether each file has answered once, loaded or (the user's) missing. At
  // startup both arrive separately, and evaluating guards for the first alone
  // would run the whole batch twice; an open before then evaluates anyway.
  property bool defaultMenuSettled: false
  property bool userMenuSettled: false
  property bool opened: false
  property string mode: "menu"
  readonly property bool dmenuActive: mode === "select" || mode === "input"
  property string dmenuPrompt: ""
  property var dmenuOptions: []
  property bool dmenuMultiple: false
  property var dmenuSelected: []
  // What the last confirmed change applied; a failed change returns the checks here.
  property var dmenuSaved: []
  property string dmenuChangeKey: ""
  property var dmenuOnChange: []
  property string selectionFile: ""
  property string doneFile: ""
  property int dmenuWidth: 300
  property int dmenuMaxHeight: 0
  property bool requestActive: false
  property bool rowsLoaded: false
  property string activeMenu: "root"
  property string filterText: ""
  // Resets of filterText reach the search line; its edits come back through setFilter.
  onFilterTextChanged: if (filterInput.text !== filterText) filterInput.text = filterText
  property int selectedIndex: 0
  property bool cursorActive: false
  property int requestSerial: 0
  property int applySerial: 0
  property var items: ({})
  property var itemOrder: []
  property var navStack: []
  property var providersLoaded: ({})
  property var providerQueue: []
  property int providerRevision: 0

  // Shared application engine (entries, hidden filters, icons, launch,
  // removal), owned by the shell and also used by the standalone launcher.
  // Vista: Omarchy 4.0.6 handed this third-party menu a PluginShellApi whose
  // appLibrary was null, which left the launcher empty. 4.5 passes it to every
  // `menu` plugin; the fallback stays as a guard and is created only when the
  // shell's own is missing.
  readonly property var appLibrary: (root.shell && root.shell.appLibrary) || vistaAppLibraryLoader.item
  Loader {
    id: vistaAppLibraryLoader
    active: !!root.shell && !root.shell.appLibrary
    sourceComponent: VistaServices.AppLibrary { }
  }
  property bool deleteConfirmOpen: false
  property var deleteTarget: null
  onOpenedChanged: if (!opened) { deleteConfirmOpen = false; deleteTarget = null }
  // Bound to the central [menu] section in shell.toml via Commons.Color.qml.
  // Each color already includes its alpha companion (composed in the
  // singleton), so consumers can drop them straight into a Rectangle.
  property color background: Commons.Color.menu.background
  property color foreground: Commons.Color.menu.text
  property color border: Commons.Color.menu.border
  property var borderSpec: Border.surfaceSpec("menu", "border", border, Math.max(1, Style.space(2)))
  property color scrim: Commons.Color.menu.scrim
  property color selectedBackground: Commons.Color.menu.selectedBackground
  property color selectedText: Commons.Color.menu.selectedText
  property color selectedBorder: Commons.Color.menu.selectedBorder
  property var selectedBorderSpec: Border.surfaceSpec("menu", "selected-border", selectedBorder, 0)
  readonly property real rowReservedBorderLeft: Border.left(selectedBorderSpec)
  readonly property real rowReservedBorderRight: Border.right(selectedBorderSpec)
  readonly property int cornerRadius: Style.cornerRadius
  property int contentMargin: Style.spacing.panelPadding
  property int headerHeight: Math.max(Style.space(34), Style.font.title + Style.spacing.controlPaddingY * 2)
  property int contentSpacing: Style.spacing.md
  // Vista: details-view rows (Tahoma 8 on a 16 px icon), one line each.
  property int baseRowHeight: Style.space(19)
  property int detailRowHeight: baseRowHeight
  // How much of the first hidden row stays visible at the fold — enough to
  // read as a cut-off row rather than a bottom border.
  property int rowPeek: Math.round(baseRowHeight * 0.55)
  property int rowSpacing: 0 // Vista: details rows touch
  property int dividerHeight: Style.space(17)
  property bool searchDivider: false
  property int layoutSerial: 0
  property int cardWidth: Math.min(root.dmenuActive ? Style.space(root.dmenuWidth) : ((root.activeMenu === "trigger.capture.screenrecord" || root.activeMenu === "appearance.font" || root.activeMenu === "update.kernel") ? Style.space(520) : Style.space(300)), panel.width - Style.gapsOut * 2)
  property int visibleRowsHeight: root.dmenuActive ? dmenuRowListHeight(layoutSerial, displayModel.count, filterText) : rowListHeight(layoutSerial, displayModel.count, filterText, searchDivider)
  property int cardHeight: root.dmenuActive
    ? Math.min(contentMargin * 2 + headerHeight + (mode === "input" ? 0 : contentSpacing + visibleRowsHeight), panel.height - Style.gapsOut * 2)
    : Math.min(contentMargin * 2 + headerHeight + contentSpacing + visibleRowsHeight, panel.height - Style.gapsOut * 2)

  function finishRequest(selection) {
    if (!root.requestActive || !root.doneFile) {
      root.opened = false
      return
    }

    var activeSelectionFile = root.selectionFile
    var activeDoneFile = root.doneFile
    root.requestActive = false
    root.selectionFile = ""
    root.doneFile = ""

    if (selection === null || selection === undefined) {
      resultProc.command = ["bash", "-c", ": > " + Util.shellQuote(activeDoneFile)]
    } else {
      resultProc.command = ["bash", "-c", "printf '%s\\n' " + Util.shellQuote(selection) + " > " + Util.shellQuote(activeSelectionFile) + "; : > " + Util.shellQuote(activeDoneFile)]
    }
    resultProc.running = true
  }

  function runAction(action) {
    // Vista: the screensaver row runs Vista's 3D Pipes (MenuModel.vistaCommand).
    var command = MenuModel.vistaCommand(action, Quickshell.env("HOME"))
    if (!command) return

    var summon = MenuModel.summonAction(command)
    if (summon && root.shell && root.shell.summon(summon.id, summon.payload)) return

    Util.execDetached(command)
  }

  // Menu rows only surface their detail while a search is narrowing them;
  // dmenu rows carry caller-supplied subtext that must always be visible.
  function rowHeightForDetail(detail) {
    return (root.filterText || root.dmenuActive) && detail ? root.detailRowHeight : root.baseRowHeight
  }

  // Height the card can devote to rows before running off the screen — or
  // past the frozen top edge once a search has pinned the card in place.
  // Uses panel.cardTop rather than effectiveCardTop: the centered top is
  // derived from the card height, which this value feeds.
  function availableRowsHeight() {
    var top = panel.cardTop >= 0 ? panel.cardTop : Style.gapsOut
    var available = panel.height - top - Style.gapsOut - root.contentMargin * 2 - root.headerHeight - root.contentSpacing
    // The starting menu sets the ceiling along with the offset: drilling into
    // a longer submenu scrolls behind the fold instead of growing the card.
    if (panel.maxRowsHeight >= 0) available = Math.min(available, panel.maxRowsHeight)
    // A card that swallows the whole screen reads as a page, not a menu.
    return Math.min(available, Math.round(panel.height * 0.7))
  }

  // When every row fits, the list gets its full height. When they don't,
  // the card must end mid-row: a clipped row is what tells the eye there is
  // more below the fold, so never come out even on a row boundary.
  function foldedListHeight(totals, available) {
    var count = totals.length
    if (count === 0) return root.baseRowHeight
    if (totals[count - 1] <= available) return totals[count - 1]

    var peek = root.rowPeek
    var full = 0
    while (full < count && totals[full] <= available) full++
    while (full > 1 && totals[full - 1] + root.rowSpacing + peek > available) full--
    if (full < 1) return Math.max(available, root.baseRowHeight)

    return totals[full - 1] + root.rowSpacing + peek
  }

  function rowListHeight(_serial, _count, _filter, _divider) {
    if (displayModel.count === 0) return root.baseRowHeight

    var totals = []
    var total = 0
    var previousSection = ""

    for (var i = 0; i < displayModel.count; i++) {
      var row = displayModel.get(i)
      if (i > 0) total += root.rowSpacing
      if (row.section === "drilldown" && previousSection !== "drilldown") total += root.dividerHeight
      total += root.rowHeightForDetail(row.detail)
      previousSection = row.section
      totals.push(total)
    }

    return foldedListHeight(totals, availableRowsHeight())
  }

  function dmenuRowListHeight(_serial, _count, _filter) {
    if (root.mode === "input") return 0
    if (displayModel.count === 0) return root.baseRowHeight

    var available = availableRowsHeight()
    if (root.dmenuMaxHeight > 0) available = Math.min(available, Style.space(root.dmenuMaxHeight))

    var totals = []
    var total = 0
    for (var i = 0; i < displayModel.count; i++) {
      if (i > 0) total += root.rowSpacing
      total += root.rowHeightForDetail(displayModel.get(i).detail)
      totals.push(total)
    }

    return foldedListHeight(totals, available)
  }

  function item(id) {
    return root.items[id] || null
  }

  // ------------------------------------------------------------------
  // JSONC → normalized item array. Mirrors the bash bin's jq pipeline so
  // the on-disk authoring format stays untouched.
  // ------------------------------------------------------------------

  function stripJsonc(raw) {
    return MenuModel.stripJsonc(raw)
  }

  function normalizeAliases(value) {
    return MenuModel.normalizeAliases(value)
  }

  function normalizeItem(id, raw) {
    return MenuModel.normalizeItem(id, raw)
  }

  function parseMenuJsonc(raw) {
    return MenuModel.parseMenuJsonc(raw)
  }

  function parseCatalog(raw) {
    try {
      var parsed = JSON.parse(raw || "{}")
      return (parsed && typeof parsed === "object" && !Array.isArray(parsed)) ? parsed : ({})
    } catch (e) {
      return ({})
    }
  }

  function setLanguage(raw) {
    var code = String(raw || "").trim()
    if (!/^[a-z]{2,3}(-[A-Za-z]{2})?$/.test(code)) code = "en"
    if (root.language === code) return
    root.language = code
    menuCatalogFile.reload()
  }

  // Merge defaults + user extension. Later entries override earlier ones
  // on a per-key basis (so the user can tweak label/icon/action without
  // re-declaring the whole row).
  // Catalog-only rebuilds pass skipGuards: retitling rows cannot change any
  // when/checked answer, so re-running the guard batch would be pure waste.
  function rebuildItemsFromSources(skipGuards) {
    var translatedDefaults = MenuModel.applyTranslations(root.defaultMenuItems, root.menuCatalog)
    // The root row is injected by the merge (it has no JSONC entry), so its
    // "Go" label comes from the catalog's root entry; the merge only uses
    // it for the injected row, never over a user-supplied heading.
    var rootCatalog = root.menuCatalog.root
    var mergedMenu = MenuModel.mergeMenuSources(translatedDefaults, root.userMenuItems, rootCatalog && rootCatalog.label)
    root.providerRevision += 1
    root.providersLoaded = ({})
    root.providerQueue = []
    root.items = mergedMenu.items
    root.itemOrder = mergedMenu.itemOrder
    root.rowsLoaded = true
    if (!skipGuards && root.defaultMenuSettled && root.userMenuSettled) root.evaluateGuards()
    if (root.opened) {
      root.rebuildDisplay()
      if (!root.dmenuActive) {
        if (root.filterText.trim()) root.loadProvidersForSearch()
        else root.loadProviderForMenu(root.activeMenu)
      }
    }
  }

  // Each known provider is a tiny bash one-liner that enumerates a list and
  // emits one tab-delimited row per item: `label\tvalue\tcurrent`. The shell
  // turns those into menu items children of `menuId`. A `volatile` provider
  // re-runs every time its submenu is entered, so a font installed since the
  // shell started shows up without restarting it.
  readonly property var providers: ({
    "fonts": {
      script: "current=$(omarchy-font-current 2>/dev/null); omarchy-font-list 2>/dev/null | while read -r f; do [[ -z $f ]] && continue; printf '%s\\t%s\\t%s\\n' \"$f\" \"$f\" \"$current\"; done",
      icon: "",
      volatile: true,
      actionFor: function(value) { return "omarchy-font-set " + Util.shellQuote(value) }
    },
    "power-profiles": {
      script: "current=$(powerprofilesctl get 2>/dev/null); omarchy-powerprofiles-list 2>/dev/null | while read -r p; do [[ -z $p ]] && continue; printf '%s\\t%s\\t%s\\n' \"$p\" \"$p\" \"$current\"; done",
      icon: "\udb81\udc0b",
      // Profile names are powerprofilesctl ids; only the label is translated,
      // and the id stays searchable through searchTerms.
      labelFor: function(value) {
        if (value === "power-saver") return Commons.I18n.t("menu.powerProfilePowerSaver")
        if (value === "balanced") return Commons.I18n.t("menu.powerProfileBalanced")
        if (value === "performance") return Commons.I18n.t("menu.powerProfilePerformance")
        return value
      },
      actionFor: function(value) { return "omarchy-powerprofiles-set autodetect " + Util.shellQuote(value) }
    },
    // Kernel names are package names, the same in every language.
    "kernels": {
      script: "current=$(omarchy-kernel get 2>/dev/null); omarchy-kernel list 2>/dev/null | while read -r k; do [[ -z $k ]] && continue; printf '%s\\t%s\\t%s\\n' \"$k\" \"$k\" \"$current\"; done",
      icon: "\uf17c",
      volatile: true,
      actionFor: function(value) { return "omarchy-kernel set " + Util.shellQuote(value) }
    },
    // Rows carry a fourth field (the English name) so searching "danish"
    // finds the row labeled with its native name; mergeProviderRows turns
    // it into an alias.
    "languages": {
      script: "current=$(omarchy-language 2>/dev/null); omarchy-language list 2>/dev/null | while IFS=$'\\t' read -r name code english; do [[ -z $code ]] && continue; printf '%s\\t%s\\t%s\\t%s\\n' \"$name\" \"$code\" \"$current\" \"$english\"; done",
      icon: "\uf1ab",
      volatile: true,
      actionFor: function(value) { return "omarchy-language " + Util.shellQuote(value) }
    }
  })

  function slugify(value) {
    return MenuModel.slugify(value)
  }

  // The apps provider is QML-native: rows come from the shared AppLibrary
  // (DesktopEntries) instead of a bash enumeration, so they carry image
  // icons, launch feedback, and uninstall support like the launcher.
  function mergeAppRows() {
    if (!root.appLibrary) return

    var rows = root.appLibrary.sortedEntries("")
    var appRows = []
    for (var j = 0; j < rows.length; j++) {
      var entry = rows[j].entry
      var appId = String(entry.id || "")
      if (!appId) continue
      var subtext = root.appLibrary.entrySubtext(entry)
      var aliases = subtext ? [subtext] : []
      try {
        if (entry.keywords && typeof entry.keywords.join === "function") aliases = aliases.concat(entry.keywords)
      } catch (e) { }
      appRows.push({
        id: "apps." + appId,
        parent: "apps",
        kind: "app",
        icon: "",
        appIcon: String(entry.icon || ""),
        appId: appId,
        label: root.appLibrary.entryName(entry),
        title: "",
        target: "",
        description: subtext,
        action: "",
        provider: "",
        aliases: aliases,
        searchTerms: [],
        when: "",
        checked: "",
        disabled: "",
        order: 0
      })
    }

    var merged = MenuModel.mergeAppRows(root.items, root.itemOrder, appRows)
    root.items = merged.items
    root.itemOrder = merged.itemOrder
    if (root.opened) root.rebuildDisplay()
  }

  function startProviderForMenu(id) {
    var entry = root.item(id)
    if (!entry || !entry.provider || root.providersLoaded[id]) return
    if (entry.provider === "apps") {
      root.providersLoaded[id] = true
      root.mergeAppRows()
      return
    }
    var spec = root.providers[entry.provider]
    if (!spec) return

    root.providersLoaded[id] = true
    providerProc.menuId = id
    providerProc.providerKey = entry.provider
    providerProc.revision = root.providerRevision
    providerProc.collected = ""
    providerProc.command = ["bash", "-lc", spec.script]
    providerProc.running = true
  }

  function mergeProviderRows(rows, menuId, providerKey) {
    var spec = root.providers[providerKey]
    if (!spec) return
    var lines = String(rows || "").split("\n")
    var providerRows = []
    var takenIds = ({})
    for (var i = 0; i < lines.length; i++) {
      var line = lines[i].trim()
      if (!line) continue
      var parts = line.split("\t")
      var rawLabel = parts[0] || ""
      var label = spec.labelFor ? spec.labelFor(rawLabel) : rawLabel
      var value = parts[1] || parts[0] || ""
      var current = parts[2] || ""
      if (!label) continue
      // Distinct values can slugify alike — Fira Code and Fira-Code both give
      // fira-code — and a repeated id is dropped, which would silently lose a
      // row from the list. Nudge it until it is the row's own.
      var rowId = menuId + "." + root.slugify(value)
      while (takenIds[rowId]) rowId += "-"
      takenIds[rowId] = true

      providerRows.push({
        id: rowId,
        parent: menuId,
        kind: "action",
        icon: (value === current) ? "✓" : (spec.icon || ""),
        label: label,
        title: "",
        target: "",
        description: "",
        action: spec.actionFor(value),
        provider: "",
        aliases: [],
        searchTerms: (parts[3] ? [parts[3]] : []).concat(label !== rawLabel ? [rawLabel] : []),
        when: "",
        checked: "",
        disabled: "",
        order: 0
      })
    }
    var merged = MenuModel.swapProviderRows(root.items, root.itemOrder, menuId, providerRows)
    root.items = merged.items
    root.itemOrder = merged.itemOrder
    if (root.opened) root.rebuildDisplay()
  }

  function startNextProvider() {
    if (providerProc.running) return

    while (root.providerQueue.length > 0) {
      var id = root.providerQueue.shift()
      var entry = root.item(id)
      if (!entry || !entry.provider || root.providersLoaded[id]) continue

      root.startProviderForMenu(id)
      return
    }
  }

  // Entering a submenu is the one moment a volatile list is worth paying for
  // again: it may have been reshaped by the last pick from it. Search doesn't
  // invalidate, or every keystroke would restart the same enumeration.
  function invalidateVolatileProvider(id) {
    var entry = root.item(id)
    var spec = entry && entry.provider ? root.providers[entry.provider] : null
    if (spec && spec.volatile) root.providersLoaded[id] = false
  }

  function loadProviderForMenu(id) {
    var entry = root.item(id)
    if (!entry || !entry.provider || root.providersLoaded[id]) return

    // Native providers don't touch providerProc, so they never need to queue.
    if (entry.provider === "apps") {
      root.startProviderForMenu(id)
      return
    }

    if (providerProc.running) {
      if (root.providerQueue.indexOf(id) < 0) root.providerQueue = root.providerQueue.concat([id])
      return
    }

    root.startProviderForMenu(id)
  }

  function loadProvidersForSearch() {
    var active = root.item(root.activeMenu) ? root.activeMenu : "root"

    for (var i = 0; i < root.itemOrder.length; i++) {
      var entry = root.item(root.itemOrder[i])
      if (!entry || !entry.provider || root.providersLoaded[entry.id]) continue
      if (active !== "root" && entry.id !== active && !root.isDescendantOf(entry.id, active)) continue

      root.loadProviderForMenu(entry.id)
    }
  }

  function depthFor(id) {
    return MenuModel.depthFor(root.items, id)
  }

  function pathFor(id) {
    return MenuModel.pathFor(root.items, id)
  }

  function parentPathFor(id) {
    return MenuModel.parentPathFor(root.items, id)
  }

  function isDescendantOf(id, ancestorId) {
    return MenuModel.isDescendantOf(root.items, id, ancestorId)
  }

  function childCount(id) {
    return MenuModel.childCount(root.items, root.itemOrder, id)
  }

  // Guarded items are hidden when their `when:` evaluates false. Static
  // submenus are also hidden when none of their descendants are visible;
  // provider-backed menus stay visible because their rows load on demand.
  function isVisible(entry) {
    return MenuModel.isVisible(root.items, root.itemOrder, root.whenResults, entry)
  }

  // Label with the ✓ marker baked in when `checked:` or `disabled:` evaluated
  // truthy.
  function labelFor(entry) {
    return MenuModel.labelFor(entry, root.checkedResults, root.disabledResults)
  }

  function searchableToken(value) {
    return MenuModel.searchableToken(value)
  }

  function leafIdFor(id) {
    return MenuModel.leafIdFor(id)
  }

  function nameSearchText(entry) {
    return MenuModel.nameSearchText(entry)
  }

  function termInSearchWords(term, text) {
    return MenuModel.termInSearchWords(term, text)
  }

  function descriptionTextMatches(query, text) {
    return MenuModel.descriptionTextMatches(query, text)
  }

  // Rows whose `disabled:` evaluated truthy stay listed but dimmed, and the
  // cursor steps over them.
  function isDisabled(entry) {
    return MenuModel.isDisabled(root.disabledResults, entry)
  }

  // A disabled row earns its place in the submenu it belongs to, where the
  // list around it is the point. Search is a list of what you can do, so it
  // leaves them out.
  function matchesQuery(entry, query) {
    return MenuModel.matchesQuery(entry, query, root.isVisible(entry) && !root.isDisabled(entry))
  }

  function searchScore(entry, query) {
    return MenuModel.searchScore(root.items, entry, query)
  }

  function displayRow(entry, detail, score, section) {
    return MenuModel.displayRow(root.items, root.itemOrder, root.checkedResults, root.disabledResults, entry, detail, score, section)
  }

  function rowSelectable(index) {
    if (index < 0 || index >= displayModel.count) return false
    return !displayModel.get(index).disabled
  }

  // First selectable row at or past `from`, continuing in the direction of
  // travel and wrapping. -1 when every row is disabled, which leaves the menu
  // with no cursor at all rather than one parked on a row Enter won't run.
  function nextSelectable(from, direction) {
    var count = displayModel.count
    if (count === 0) return -1

    var step = direction < 0 ? -1 : 1
    var index = ((from % count) + count) % count
    for (var i = 0; i < count; i++) {
      if (root.rowSelectable(index)) return index
      index = (index + step + count) % count
    }

    return -1
  }

  // Park the cursor on a selectable row after the rows underneath it changed.
  // A menu with nothing selectable in it -- every app in it already installed
  // -- shows no cursor at all, and grows one the moment a row can take it.
  function settleCursor() {
    var target = root.nextSelectable(root.selectedIndex, 1)
    root.selectedIndex = target >= 0 ? target : 0
    root.cursorActive = target >= 0
  }

  function rebuildDmenuDisplay() {
    displayModel.clear()
    root.searchDivider = false

    if (root.mode === "input") {
      layoutSerial += 1
      return
    }

    if (root.dmenuMultiple && root.dmenuOnChange.length === 0) {
      displayModel.append({
        itemId: "dmenu.apply", disabled: false, kind: "dmenu", icon: "", iconFont: "",
        appIcon: "", appId: "", label: Commons.I18n.t("common.apply"), target: "",
        detail: Commons.I18n.tn("menu.selectedCount", root.dmenuSelected.length).arg(Commons.I18n.formatNumber(root.dmenuSelected.length)), path: "", childCount: 0,
        action: "", provider: "", score: -1, section: ""
      })
    }
    var query = root.filterText.trim().toLowerCase()
    for (var i = 0; i < root.dmenuOptions.length; i++) {
      // An option is "<label>", "<glyph>\t<label>", or
      // "<glyph>\t<label>\t<subtext>". The glyph never comes back with the
      // selection; the subtext renders under the label, filters alongside it,
      // and returns with the selection as a stable key for same-named rows.
      var parts = String(root.dmenuOptions[i] || "").split("\t")
      var icon = parts.length > 1 ? parts.shift() : ""
      var label = parts.shift() || ""
      var detail = parts.join("\t")
      if (query && label.toLowerCase().indexOf(query) < 0
          && detail.toLowerCase().indexOf(query) < 0) continue
      displayModel.append({
        itemId: "dmenu." + i,
        disabled: false,
        kind: "dmenu",
        icon: root.dmenuMultiple ? (root.dmenuSelected.indexOf(MenuModel.dmenuValue(root.dmenuOptions[i])) !== -1 ? "✓" : "○") : icon,
        iconFont: "",
        appIcon: "",
        appId: "",
        label: label,
        target: "",
        detail: detail,
        path: "",
        childCount: 0,
        action: "",
        provider: "",
        score: i,
        section: ""
      })
    }

    layoutSerial += 1

    if (displayModel.count === 0) selectedIndex = 0
    else if (selectedIndex >= displayModel.count) selectedIndex = displayModel.count - 1
    else if (selectedIndex < 0) selectedIndex = 0

    Qt.callLater(function() {
      if (displayModel.count > 0) root.revealCursor()
    })
  }

  function updateDmenuChecks() {
    for (var i = 0; i < displayModel.count; i++) {
      var row = displayModel.get(i)
      if (row.itemId === "dmenu.apply") {
        displayModel.setProperty(i, "detail", Commons.I18n.tn("menu.selectedCount", root.dmenuSelected.length).arg(Commons.I18n.formatNumber(root.dmenuSelected.length)))
      } else if (row.kind === "dmenu") {
        var value = MenuModel.dmenuValue(root.dmenuOptions[Number(row.itemId.substring(6))])
        displayModel.setProperty(i, "icon", root.dmenuSelected.indexOf(value) !== -1 ? "✓" : "○")
      }
    }
  }

  function rebuildDisplay() {
    if (root.dmenuActive) {
      root.rebuildDmenuDisplay()
      return
    }

    displayModel.clear()

    if (!root.rowsLoaded) return

    var active = root.item(root.activeMenu) ? root.activeMenu : "root"
    root.activeMenu = active
    var rows = []
    var query = root.filterText.trim()
    root.searchDivider = false

    if (query) {
      var currentRows = []
      var drilldownRows = []

      for (var i = 0; i < root.itemOrder.length; i++) {
        var entry = root.item(root.itemOrder[i])
        if (!entry || entry.id === "root") continue
        if (!root.isDescendantOf(entry.id, active)) continue
        if (!root.matchesQuery(entry, query)) continue

        var detail = root.parentPathFor(entry.id)
        var row = root.displayRow(entry, detail, root.searchScore(entry, query))
        if (entry.parent === active) currentRows.push(row)
        else drilldownRows.push(row)
      }

      var searchSort = function(a, b) {
        if (a.score !== b.score) return a.score - b.score
        return a.path.localeCompare(b.path)
      }

      currentRows.sort(searchSort)
      drilldownRows.sort(searchSort)
      root.searchDivider = currentRows.length > 0 && drilldownRows.length > 0
      if (root.searchDivider) {
        for (var d = 0; d < drilldownRows.length; d++) drilldownRows[d].section = "drilldown"
      }
      rows = currentRows.concat(drilldownRows)
    } else {
      for (var j = 0; j < root.itemOrder.length; j++) {
        var child = root.item(root.itemOrder[j])
        if (!child || child.parent !== active) continue
        if (!root.isVisible(child)) continue
        rows.push(root.displayRow(child, child.description, child.order))
      }

      // DesktopEntries can reorder its values when an application starts.
      // Keep the Apps menu alphabetical independently of provider refreshes.
      if (active === "apps") {
        rows.sort(function(a, b) {
          var aLabel = String(a.label || "").toLowerCase()
          var bLabel = String(b.label || "").toLowerCase()
          if (aLabel < bLabel) return -1
          if (aLabel > bLabel) return 1
          var aId = String(a.itemId || "")
          var bId = String(b.itemId || "")
          if (aId < bId) return -1
          if (aId > bId) return 1
          return 0
        })
      }
    }

    for (var k = 0; k < rows.length; k++) displayModel.append(rows[k])
    layoutSerial += 1

    root.settleCursor()

    Qt.callLater(function() {
      if (displayModel.count > 0) root.revealCursor()
    })
  }

  // Contain alone parks the cursor row flush with the viewport edge, hiding
  // the neighbor entirely and losing the fold affordance. Keep the next
  // hidden row peeking past the cursor in the direction of travel.
  function revealCursor() {
    if (displayModel.count === 0) return
    resultList.positionViewAtIndex(root.selectedIndex, ListView.Contain)

    var item = resultList.itemAtIndex(root.selectedIndex)
    if (!item) return

    var reach = root.rowPeek + root.rowSpacing
    if (root.selectedIndex < displayModel.count - 1) {
      var maxY = Math.max(resultList.originY, resultList.originY + resultList.contentHeight - resultList.height)
      var overhang = item.y + item.height + reach - (resultList.contentY + resultList.height)
      if (overhang > 0) resultList.contentY = Math.min(resultList.contentY + overhang, maxY)
    }
    if (root.selectedIndex > 0) {
      var underhang = resultList.contentY - (item.y - reach)
      if (underhang > 0) resultList.contentY = Math.max(resultList.contentY - underhang, resultList.originY)
    }
  }

  function select(delta) {
    if (displayModel.count === 0) return

    root.disarmPointer()
    var from = cursorActive ? selectedIndex + delta : (delta < 0 ? displayModel.count - 1 : 0)
    var target = root.nextSelectable(from, delta)
    if (target < 0) return

    cursorActive = true
    selectedIndex = target
    revealCursor()
  }

  function setFilter(nextFilter) {
    panel.freezeCardTop()
    root.filterText = nextFilter
    root.selectedIndex = 0
    root.cursorActive = root.mode !== "input"
    root.disarmPointer()
    if (!root.dmenuActive && root.filterText.trim()) root.loadProvidersForSearch()
    root.rebuildDisplay()
  }

  function setActiveMenu(id, pushHistory, fromPointer) {
    panel.freezeCardTop()
    if (!root.item(id)) id = "root"
    if (pushHistory && id !== root.activeMenu) root.navStack = root.navStack.concat([root.activeMenu])
    root.activeMenu = id
    root.filterText = ""
    root.selectedIndex = 0
    root.cursorActive = true
    if (fromPointer) pointerGate.allowInitialSample()
    else root.disarmPointer()
    root.rebuildDisplay()
    root.invalidateVolatileProvider(id)
    root.loadProviderForMenu(id)
  }

  function goBack() {
    if (root.activeMenu === "root") return false

    if (root.navStack.length > 0) {
      var previous = root.navStack[root.navStack.length - 1]
      root.navStack = root.navStack.slice(0, root.navStack.length - 1)
      root.setActiveMenu(previous, false)
      return true
    }

    var active = root.item(root.activeMenu)
    root.setActiveMenu((active && active.parent) ? active.parent : "root", false)
    return true
  }

  function activateIndex(index, fromPointer) {
    if (root.deleteConfirmOpen) return
    if (root.dmenuActive) {
      if (root.mode === "input") {
        root.applyDmenuSelection(root.filterText)
        return
      }
      if (index < 0 || index >= displayModel.count) return
      var picked = displayModel.get(index)
      if (root.dmenuMultiple) {
        if (picked.itemId === "dmenu.apply") {
          root.applyDmenuSelection(JSON.stringify(MenuModel.dmenuSelections(root.dmenuOptions, root.dmenuSelected)))
        } else {
          var value = MenuModel.dmenuValue(root.dmenuOptions[Number(picked.itemId.substring(6))])
          var selected = MenuModel.toggleDmenuSelection(selectionProc.requestedSelection(), value)
          if (root.dmenuOnChange.length > 0) {
            selectionProc.enqueue(selected)
          } else {
            root.dmenuSelected = selected
            root.updateDmenuChecks()
          }
        }
      } else {
        root.applyDmenuSelection(picked.detail ? picked.label + "\t" + picked.detail : picked.label)
      }
      return
    }

    if (!root.rowSelectable(index)) return

    var row = displayModel.get(index)
    if (row.kind === "menu" || row.kind === "link") {
      root.setActiveMenu(row.target || row.itemId, true, fromPointer)
    } else if (row.itemId === "apps") {
      // Vista: the Apps row lists the programs here, as Search Results (the
      // Vista launcher), rather than running its 4.5 action (the dock's apps view).
      root.setActiveMenu("apps", true, fromPointer)
    } else if (row.kind === "app") {
      var appId = row.appId
      var label = row.label
      applySerial = requestSerial
      opened = false
      filterText = ""
      if (root.appLibrary) root.appLibrary.launch(appId, label)
    } else {
      root.applySelected(row.itemId, row.action)
    }
  }

  function requestDeleteSelected() {
    if (!root.cursorActive || root.selectedIndex < 0 || root.selectedIndex >= displayModel.count) return
    var row = displayModel.get(root.selectedIndex)
    if (!row || row.kind !== "app") return
    root.deleteTarget = { appId: row.appId, label: row.label }
    deleteConfirm.selectedIndex = 1
    root.deleteConfirmOpen = true
  }

  function cancelDelete() {
    root.deleteConfirmOpen = false
    root.deleteTarget = null
    deleteConfirm.selectedIndex = 1
    root.disarmPointer()
    Qt.callLater(function() { filterInput.forceActiveFocus() })
  }

  function confirmDelete() {
    var target = root.deleteTarget
    root.deleteConfirmOpen = false
    root.deleteTarget = null
    if (!target) return
    root.cancel()
    if (root.appLibrary) root.appLibrary.remove(target.appId, target.label)
  }

  function applyDmenuSelection(value) {
    applySerial = requestSerial
    opened = false
    filterText = ""
    root.finishRequest(value)
  }

  function applySelected(id, action) {
    if (!id) { cancel(); return }

    applySerial = requestSerial
    opened = false
    filterText = ""
    root.runAction(action)
  }

  function cancel() {
    if (root.dmenuActive) root.finishRequest(null)
    opened = false
    filterText = ""
  }

  function openExistingMenu(initialMenu) {
    requestSerial += 1
    mode = "menu"
    requestActive = false
    selectionFile = ""
    doneFile = ""
    activeMenu = root.item(initialMenu) ? initialMenu : "root"
    navStack = []
    filterText = ""
    selectedIndex = 0
    cursorActive = true
    root.disarmPointer()
    root.evaluateGuards()
    opened = true
    rebuildDisplay()
    invalidateVolatileProvider(activeMenu)
    loadProviderForMenu(activeMenu)
    // The shell may start before first-install packages have finished placing
    // their icons. Refresh here even when the desktop entry list did not change.
    if (root.appLibrary) root.appLibrary.refreshIcons()

    Qt.callLater(function() { filterInput.forceActiveFocus() })
  }

  function openDmenu(payload) {
    requestSerial += 1
    mode = payload.mode === "input" ? "input" : "select"
    dmenuPrompt = String(payload.prompt || (mode === "input" ? Commons.I18n.t("menu.inputPrompt") : Commons.I18n.t("menu.selectPrompt")))
    dmenuOptions = Array.isArray(payload.options) ? payload.options : []
    dmenuMultiple = mode === "select" && payload.multiple === true
    dmenuOnChange = dmenuMultiple && Array.isArray(payload.onChange)
      && payload.onChange.every(function(arg) { return typeof arg === "string" }) ? payload.onChange : []
    dmenuChangeKey = String(payload.changeKey || JSON.stringify(dmenuOnChange))
    dmenuSelected = MenuModel.dmenuSelections(dmenuOptions, Array.isArray(payload.selected) ? payload.selected : [], dmenuOnChange.length > 0)
    dmenuSaved = dmenuSelected
    if (dmenuOnChange.length > 0)
      dmenuSelected = MenuModel.dmenuSelections(dmenuOptions, selectionProc.requestedSelection(), true)
    selectionFile = String(payload.selectionFile || "")
    doneFile = String(payload.doneFile || "")
    requestActive = !!doneFile
    dmenuWidth = Math.max(1, Number(payload.width || 300))
    dmenuMaxHeight = Math.max(0, Number(payload.maxHeight || 0))
    activeMenu = "root"
    navStack = []
    filterText = ""
    selectedIndex = 0
    cursorActive = mode !== "input"
    root.disarmPointer()
    opened = true
    rebuildDisplay()

    Qt.callLater(function() { filterInput.forceActiveFocus() })
  }
  ListModel { id: displayModel }

  // ----------------------------------------------------------- route surface
  //
  // The menu is opened through the standard plugin lifecycle:
  // `omarchy-shell shell summon omarchy.menu '{"menu":"system"}'`.
  // Callers may pass a real id (`system`, `setup.power`) or an alias declared
  // in JSONC (`power`, `reminder-set`). Unknown strings fall through to the
  // id-as-route behavior so misspellings still attempt to open the literal id.
  function resolveRoute(input) {
    return MenuModel.resolveRoute(root.items, root.itemOrder, input)
  }

  function openRoute(initialMenu) {
    var id = root.resolveRoute(initialMenu)
    var entry = root.items[id]
    // If the resolved id is an action (i.e. the user invoked an alias for
    // a leaf, e.g. `omarchy menu summon screenrecord-stop`), run it directly
    // instead of opening an action with no children.
    if (entry && entry.kind === "action" && entry.action) {
      root.cancel()
      root.runAction(entry.action)
      return "ok"
    }
    // If it's a link (a redirect to another menu), follow the link.
    if (entry && entry.kind === "link" && entry.target) id = entry.target
    root.pendingInitialMenu = id
    root.openExistingMenu(id)
    return "ok"
  }

  function disarmPointer() {
    pointerGate.reset()
  }

  function selectFromPointer(index, item, mouse) {
    if (!pointerGate.moved(item, mouse)) return
    if (!root.rowSelectable(index)) return
    root.cursorActive = true
    root.selectedIndex = index
  }

  Process {
    id: providerProc
    property string menuId: ""
    property string providerKey: ""
    property string collected: ""
    property int revision: 0
    stdout: SplitParser {
      onRead: function(data) { providerProc.collected += data + "\n" }
    }
    onExited: {
      if (providerProc.revision === root.providerRevision) {
        root.mergeProviderRows(providerProc.collected, providerProc.menuId, providerProc.providerKey)
        if (root.filterText.trim()) root.loadProvidersForSearch()
      }
      root.startNextProvider()
    }
  }

  Process {
    id: selectionProc
    property int serial: 0
    property string changeKey: ""
    property var selected: []
    property var queue: []
    property string collected: ""

    function requestedSelection() {
      for (var i = queue.length - 1; i >= 0; i--) {
        if (queue[i].key === root.dmenuChangeKey) return queue[i].selected
      }
      if (running && changeKey === root.dmenuChangeKey) return selected
      return root.dmenuSelected
    }

    function enqueue(values) {
      var selected = MenuModel.dmenuSelections(root.dmenuOptions, values, true)
      queue = queue.concat([{
        serial: root.requestSerial, key: root.dmenuChangeKey, selected: selected,
        command: root.dmenuOnChange.concat([JSON.stringify(selected)])
      }])
      if (!running) startNext()
    }

    function startNext() {
      if (queue.length === 0) return
      var change = queue[0]
      queue = queue.slice(1)
      serial = change.serial
      changeKey = change.key
      selected = change.selected
      collected = ""
      command = change.command
      running = true
    }

    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: selectionProc.collected = text
    }
    onExited: function(exitCode) {
      if (changeKey === root.dmenuChangeKey && root.dmenuActive && root.dmenuOnChange.length > 0) {
        if (exitCode === 0) {
          var applied = selected
          if (collected.trim()) {
            try { applied = JSON.parse(collected) } catch (error) { applied = root.dmenuSelected }
          }
          if (Array.isArray(applied))
            root.dmenuSelected = MenuModel.dmenuSelections(root.dmenuOptions, applied, true)
          root.dmenuSaved = root.dmenuSelected
        } else {
          root.dmenuSelected = root.dmenuSaved
        }
        root.updateDmenuChecks()
      }
      startNext()
    }
  }

  Process {
    id: resultProc
    onExited: {
      if (root.applySerial === root.requestSerial)
        root.opened = false
    }
  }

  PointerMoveGate {
    id: pointerGate
    referenceItem: card
  }

  Connections {
    target: root.appLibrary
    function onAppsChanged() {
      if (root.providersLoaded["apps"]) root.mergeAppRows()
    }
  }

  // The JSONC sources are watched so live edits to the default file (or the
  // user extension at ~/.config/omarchy/extensions/omarchy-menu.jsonc) take
  // effect without restarting the shell.
  FileView {
    id: defaultMenuFile
    path: root.defaultMenuPath
    watchChanges: true
    printErrors: false
    onLoaded: { root.defaultMenuItems = MenuModel.keepMenuRows(root.defaultMenuItems, text(), true); root.defaultMenuSettled = true; root.rebuildItemsFromSources() }
    // A user file that loaded first held its evaluation for this one.
    onLoadFailed: { root.defaultMenuSettled = true; if (root.userMenuSettled) root.evaluateGuards() }
    onFileChanged: reload()
  }

  FileView {
    id: userMenuFile
    path: root.userMenuPath
    watchChanges: true
    printErrors: false
    onLoaded: { root.userMenuItems = MenuModel.keepMenuRows(root.userMenuItems, text(), false); root.userMenuSettled = true; root.rebuildItemsFromSources() }
    onLoadFailed: { root.userMenuItems = []; root.userMenuSettled = true; root.rebuildItemsFromSources() }
    onFileChanged: reload()
  }

  // The language choice and its catalog are watched the same way, so
  // picking a language under Setup retitles the menu with no shell restart.
  FileView {
    id: languageFile
    path: root.languagePath
    watchChanges: true
    printErrors: false
    onLoaded: root.setLanguage(text())
    onLoadFailed: root.setLanguage("")
    onFileChanged: reload()
  }

  FileView {
    id: menuCatalogFile
    path: root.omarchyPath + "/default/i18n/" + root.language + "/menu.json"
    watchChanges: true
    printErrors: false
    onLoaded: { root.menuCatalog = root.parseCatalog(text()); root.rebuildItemsFromSources(true) }
    onLoadFailed: { root.menuCatalog = ({}); root.rebuildItemsFromSources(true) }
    onFileChanged: reload()
  }

  // ---------------------------------------------------------------- guards
  //
  // `when:` (visibility) and `checked:` (✓ marker) are bash expressions the
  // shell wasn't allowed to evaluate before the perf rewrite. Now the shell
  // batches them into one bash subprocess per (re)load so the open path
  // never has to wait on them.

  property var whenResults: ({})       // id → true|false (allow visibility)
  property var checkedResults: ({})    // id → true|false (show ✓)
  property var disabledResults: ({})   // id → true|false (dim, skip cursor)
  property bool guardsPending: false

  function evaluateGuards() {
    // Process ignores a command change while it is running, and `collected`
    // belongs to the run in flight, so a second evaluation cannot overwrite
    // the first: it would throw away the lines already read and never start.
    // The surviving tail then lands as the whole answer, and every id lost
    // with it goes back to showing, since a `when:` only hides on an explicit
    // false. Wait for the run in flight and evaluate once it lands instead.
    if (guardProc.running) {
      root.guardsPending = true
      return
    }
    root.guardsPending = false

    var script = MenuModel.guardScript(root.items)
    if (!script) {
      root.whenResults = ({})
      root.checkedResults = ({})
      root.disabledResults = ({})
      return
    }
    guardProc.collected = ""
    guardProc.command = ["bash", "-lc", script]
    guardProc.running = true
  }

  Process {
    id: guardProc
    property string collected: ""
    stdout: SplitParser {
      onRead: function(data) { guardProc.collected += data + "\n" }
    }
    onExited: function(exitCode, exitStatus) {
      // A batch that was killed rather than finished has only told us about
      // the rows it reached, and a row whose `when:` went unanswered shows.
      // Keep the last complete set rather than let a half-read one through.
      // A signal leaves the exit code at 0, so the status is what tells us.
      if (exitCode !== 0 || exitStatus !== 0) {
        if (root.guardsPending) Qt.callLater(function() { root.evaluateGuards() })
        return
      }

      var nextWhen = ({})
      var nextChecked = ({})
      var nextDisabled = ({})
      var lines = guardProc.collected.split("\n")
      for (var i = 0; i < lines.length; i++) {
        var line = lines[i].trim()
        if (!line) continue
        var colon = line.lastIndexOf(":")
        if (colon < 0) continue
        var value = line.substring(colon + 1) === "1"
        var rest = line.substring(0, colon)
        var tagAt = rest.lastIndexOf(":")
        if (tagAt < 0) continue
        var id = rest.substring(0, tagAt)
        var tag = rest.substring(tagAt + 1)
        if (tag === "w") nextWhen[id] = value
        else if (tag === "c") nextChecked[id] = value
        else if (tag === "d") nextDisabled[id] = value
      }
      root.whenResults = nextWhen
      root.checkedResults = nextChecked
      root.disabledResults = nextDisabled
      if (root.opened) root.rebuildDisplay()
      // Run the evaluation that had to stand aside. Deferred by a turn so the
      // process is settled before its command is set again.
      if (root.guardsPending) Qt.callLater(function() { root.evaluateGuards() })
    }
  }
  // ================================================================ Vista
  // ocko.vista-menu: the logic above is omarchy.menu 4.5.0 (routes, JSONC
  // merge, translations, providers, guards, dmenu, launch, uninstall), changed
  // only in the blocks marked "Vista:" (open() routes, appLibrary fallback, row
  // heights, runAction's screensaver, the Apps row).
  // The window below replaces the card with Vista's own windows, drawn with the
  // shared chrome in omarchy/vista/qml:
  //   - Omarchy menu and power menu: Control Panel, category view. Task pane
  //     on the left (ExplorerBar), categories as 32 px shell32 icons in two
  //     columns; typing filters into a details list, like Search.
  //   - Launcher (apps): Search Results, a details list (Name | In Folder)
  //     with the apps' own icons, the filter in the Search Companion pane.
  //   - dmenu prompts (select / input): an Vista dialog with a list box.
  // The data model, keyboard handling and actions are the stock ones.
  readonly property string vistaView: root.dmenuActive ? "dmenu"
    : ((root.activeMenu === "apps" || root.isDescendantOf(root.activeMenu, "apps")) ? "search" : "panel")
  readonly property bool vistaGrid: vistaView === "panel" && !root.filterText
  // dmenu callers that pad columns with spaces (keybindings) were laid out
  // for the stock monospace menu font: give those Vista's fixed-width font.
  readonly property bool vistaDmenuMono: root.dmenuActive && root.dmenuOptions.some(function(o) { return /\S {2,}\S/.test(String(o)) })
  property bool vistaMaximized: false

  // shell32.dll icon per menu id / action: MenuModel.vistaIconId.
  function vistaIconFor(itemId, kind, action) {
    return VistaScheme.icon(MenuModel.vistaIconId(itemId, kind, action), 32)
  }

  function vistaTitle() {
    if (root.vistaView === "dmenu") return root.dmenuPrompt
    if (root.vistaView === "search") return "Search Results"
    if (root.activeMenu === "root") return "Control Panel"
    var entry = root.item(root.activeMenu)
    return entry ? String(entry.title || entry.label) : "Control Panel"
  }

  function vistaAddress() {
    if (root.vistaView === "search") return "Search Results"
    var parts = ["Control Panel"]
    var p = root.pathFor(root.activeMenu)
    if (p && root.activeMenu !== "root") parts.push(String(p).replace(/\s*[›>\/]\s*/g, "\\"))
    return parts.join("\\")
  }

  // Bare root route (SUPER+SPACE, `omarchy-menu`) -> the Vista Start menu, via
  // the taskbar's IPC. If the Vista bar is not running the call fails and the
  // root menu opens instead, so the key never does nothing.
  function vistaOpenShutdown() {
    root.cancel()
    Quickshell.execDetached(["omarchy-shell", "vistastart", "shutdown"])
  }

  function vistaOpenStartMenu() {
    if (!vistaStartProc.running) vistaStartProc.running = true
  }

  Process {
    id: vistaStartProc
    command: ["omarchy-shell", "vistastart", "toggle"]
    stderr: SplitParser { onRead: function(line) { if (line) console.warn("ocko.vista-menu: vistastart: " + line) } }
    onExited: function(exitCode) {
      if (exitCode !== 0) {
        console.warn("ocko.vista-menu: Start menu unavailable (exit " + exitCode + "), opening the root menu")
        root.openRoute("root")
      }
    }
  }

  // Vista: the stock OverlayWindow (focused monitor, sharp first frame) hosting
  // a Vista window instead of the stock card.
  OverlayWindow {
    id: panel
    shown: root.opened && root.rowsLoaded
    WlrLayershell.namespace: "omarchy-menu"

    function s(n) { return Style.space(n) }

    // Kept for the stock sizing helpers (availableRowsHeight, setFilter,
    // setActiveMenu); the Vista window itself is a fixed size, as Vista's were.
    property int cardTop: -1
    property int maxRowsHeight: -1
    readonly property int effectiveCardTop: cardTop >= 0 ? cardTop : Math.round((height - card.height) / 2)
    function freezeCardTop() {
      if (shown && cardTop < 0) {
        cardTop = effectiveCardTop
        maxRowsHeight = root.visibleRowsHeight
      }
    }
    onShownChanged: if (!shown) { cardTop = -1; maxRowsHeight = -1 }
    onTargetScreenChanged: { cardTop = -1; maxRowsHeight = -1 }

    readonly property int dmenuListHeight: root.mode === "input" ? 0 : Math.max(root.baseRowHeight * 3, root.visibleRowsHeight)

    Rectangle {
      anchors.fill: parent
      color: root.scrim
    }

    MouseArea {
      anchors.fill: parent
      onClicked: root.cancel()
    }

    VistaWindow {
      id: card
      readonly property bool full: root.vistaMaximized && root.vistaView !== "dmenu"
      width: full ? panel.width
        : root.vistaView === "dmenu" ? Math.min(panel.s(Math.max(root.dmenuWidth, 280)) + 2 * frameWidth, panel.width - Style.gapsOut * 2)
        : Math.min(panel.s(660), panel.width - Style.gapsOut * 2)
      height: full ? panel.height - panel.s(30)
        : root.vistaView === "dmenu"
          ? Math.min(captionHeight + frameWidth + panel.s(12 + 21 + 8 + 12 + 23 + 12) + panel.dmenuListHeight + (panel.dmenuListHeight > 0 ? panel.s(8) : 0), panel.height - Style.gapsOut * 2)
          : Math.min(panel.s(470), panel.height - Style.gapsOut * 2)
      x: full ? 0 : Math.round((panel.width - width) / 2)
      y: full ? 0 : Math.round((panel.height - height) / 2)
      title: root.vistaTitle()
      titleIcon: root.vistaView === "dmenu" ? "" : VistaScheme.icon(root.vistaView === "search" ? 23 : 36, 16)
      sizable: root.vistaView !== "dmenu"
      buttons: root.vistaView === "dmenu" ? ["close"] : ["min", "max", "close"]
      onCloseClicked: root.cancel()
      onMinimizeClicked: root.cancel()
      onMaximizeClicked: root.vistaMaximized = !root.vistaMaximized

      MouseArea { anchors.fill: parent; onClicked: {} }

      // The stock 4.5 key handler. Focus is on filterInput, which forwards
      // every key here first and takes whatever is left as typed text.
      Item {
        id: keyCatcher
        anchors.fill: parent
        z: root.deleteConfirmOpen ? 20 : 0

        Keys.onPressed: function(event) {
          if (root.deleteConfirmOpen) {
            // Swallow the rest too, or it would type into the search line behind the dialog.
            deleteConfirm.handleKey(event)
            event.accepted = true
            return
          }

          if (event.key === Qt.Key_Delete) {
            root.requestDeleteSelected()
            event.accepted = true
          } else if (event.key === Qt.Key_Escape) {
            if (root.filterText) root.setFilter("")
            else root.cancel()
            event.accepted = true
          } else if (Util.editsFilter(event, root.filterText)) {
            root.setFilter(Util.editedFilter(event, root.filterText))
            event.accepted = true
          } else if ((event.key === Qt.Key_Backspace || Util.readingKey(event) === Qt.Key_Left) && !root.filterText) {
            root.goBack()
            event.accepted = true
          } else if (event.key === Qt.Key_Up) {
            root.select(-1)
            event.accepted = true
          } else if (event.key === Qt.Key_Down) {
            root.select(1)
            event.accepted = true
          } else if (event.key === Qt.Key_PageUp) {
            root.select(-6)
            event.accepted = true
          } else if (event.key === Qt.Key_PageDown) {
            root.select(6)
            event.accepted = true
          } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || Util.readingKey(event) === Qt.Key_Right) {
            if (root.dmenuActive) {
              if (root.mode === "input") root.applyDmenuSelection(root.filterText)
              else if (displayModel.count > 0) root.activateIndex(root.cursorActive ? root.selectedIndex : 0)
            } else if (root.cursorActive) root.activateIndex(root.selectedIndex)
            else root.settleCursor()
            event.accepted = true
          }
        }

        ConfirmDialog {
          id: deleteConfirm

          anchors.fill: parent
          opened: root.deleteConfirmOpen
          z: 10
          message: Commons.I18n.t("common.uninstallConfirm").arg((root.deleteTarget && root.deleteTarget.label) || "")
          confirmText: Commons.I18n.t("common.uninstall")
          background: root.background
          foreground: root.foreground
          scrim: root.scrim
          selectedBackground: root.selectedBackground
          selectedText: root.selectedText
          fontFamily: root.fontFamily
          cornerRadius: root.cornerRadius
          onCanceled: root.cancelDelete()
          onConfirmed: root.confirmDelete()
        }
      }

      // Vista: the stock search line, kept as the focus holder and text sink
      // (input methods commit only into a TextInput) but not drawn: the Vista
      // text fields below show root.filterText.
      FilterInput {
        id: filterInput
        width: 1
        height: 1
        opacity: 0
        keyHandler: keyCatcher
        // Input-method commits bypass key handling, so the dialog has to refuse them here.
        readOnly: root.deleteConfirmOpen
        onTextChanged: if (text !== root.filterText) root.setFilter(text)
      }

      // ---- Address bar (Control Panel / Search Results), filter box (dmenu)
      Row {
        id: addressRow
        x: panel.s(root.vistaView === "dmenu" ? 12 : 6)
        y: panel.s(root.vistaView === "dmenu" ? 12 : 5)
        spacing: panel.s(6)
        Text {
          visible: root.vistaView !== "dmenu"
          anchors.verticalCenter: parent.verticalCenter
          text: "Address"
          color: VistaScheme.sc.gray
          font.family: "Segoe UI"
          font.pixelSize: Style.font.bodySmall
        }
        VistaTextField {
          width: card.client.width - addressRow.x * 2 - (root.vistaView !== "dmenu" ? panel.s(50) : 0)
          height: panel.s(21)
          interactive: false
          caret: root.vistaView === "dmenu" || root.filterText !== ""
          text: root.vistaView === "dmenu" || root.filterText ? root.filterText : root.vistaAddress()
          placeholder: root.vistaView === "dmenu" && root.mode !== "input" ? "Type to search" : ""
        }
      }

      // ---- Task pane (Control Panel) / Search Companion (Search Results)
      Rectangle {
        id: pane
        visible: root.vistaView !== "dmenu"
        x: 0
        y: addressRow.y * 2 + panel.s(21)
        width: panel.s(206)
        height: card.client.height - y
        gradient: Gradient {
          GradientStop { position: 0; color: VistaScheme.sc.paneTop }
          GradientStop { position: 1; color: VistaScheme.sc.paneBottom }
        }

        Column {
          x: panel.s(12)
          y: panel.s(12)
          width: parent.width - panel.s(24)
          spacing: panel.s(15)

          VistaPaneGroup {
            visible: root.vistaView === "panel"
            title: "Control Panel"
            special: true
            VistaPaneLink {
              text: root.activeMenu === "root" ? "Search Control Panel" : "Back"
              iconSource: VistaScheme.icon(root.activeMenu === "root" ? 23 : 5, 16)
              onActivated: if (root.activeMenu !== "root") root.goBack()
            }
          }
          VistaPaneGroup {
            visible: root.vistaView === "panel"
            title: "See Also"
            VistaPaneLink { text: "Windows Update"; iconSource: VistaScheme.icon(47, 16); onActivated: root.setActiveMenu("update", true, true) }
            VistaPaneLink { text: "Help and Support"; iconSource: VistaScheme.icon(24, 16); onActivated: root.setActiveMenu("learn", true, true) }
            VistaPaneLink { text: "Turn Off Computer"; iconSource: VistaScheme.icon(28, 16); onActivated: root.setActiveMenu("system", true, true) }
          }

          // Search Companion: the panel Vista put above Rover.
          Rectangle {
            visible: root.vistaView === "search"
            width: parent.width
            height: companion.implicitHeight + panel.s(20)
            radius: panel.s(6)
            color: "#FFFFFF"
            border.width: Math.max(1, panel.s(1))
            border.color: VistaScheme.sc.edit
            Column {
              id: companion
              x: panel.s(10)
              y: panel.s(10)
              width: parent.width - panel.s(20)
              spacing: panel.s(6)
              Text {
                width: parent.width
                wrapMode: Text.Wrap
                text: "Search for all programs whose name contains:"
                color: "#000000"
                font.family: "Segoe UI"
                font.bold: true
                font.pixelSize: Style.font.bodySmall
              }
              VistaTextField {
                width: parent.width
                interactive: false
                caret: true
                text: root.filterText
              }
              Text {
                width: parent.width
                wrapMode: Text.Wrap
                text: "Enter opens the selected program. Delete uninstalls it."
                color: "#404040"
                font.family: "Segoe UI"
                font.pixelSize: Style.font.bodySmall
              }
            }
          }
        }
      }

      // ---- Content: category grid or details list
      Rectangle {
        id: content
        readonly property bool dmenu: root.vistaView === "dmenu"
        x: dmenu ? panel.s(12) : pane.width
        y: dmenu ? addressRow.y + panel.s(21 + 8) : pane.y
        width: card.client.width - x - (dmenu ? panel.s(12) : 0)
        height: dmenu ? panel.dmenuListHeight : card.client.height - y
        visible: height > 0
        color: "#FFFFFF"
        border.width: dmenu ? Math.max(1, panel.s(1)) : 0
        border.color: VistaScheme.sc.edit
        clip: true

        Text {
          id: pickHeader
          visible: root.vistaGrid
          x: panel.s(26)
          y: panel.s(18)
          text: root.activeMenu === "root" ? "Pick a category" : "Pick a task..."
          color: VistaScheme.sc.normalHead
          font.family: "Trebuchet MS"
          font.bold: true
          font.pixelSize: Style.font.heading
        }

        // List view column headers (Search Results / filtered results).
        Row {
          id: listHeader
          visible: !root.vistaGrid && !content.dmenu
          height: visible ? panel.s(17) : 0
          VistaArt {
            width: resultList.width * 0.45
            height: listHeader.height
            source: VistaScheme.art("header-0")
            margins: [8, 8, 3, 4]
            Text { x: panel.s(6); anchors.verticalCenter: parent.verticalCenter; text: "Name"; font.family: "Segoe UI"; font.pixelSize: Style.font.bodySmall; color: "#000000" }
          }
          VistaArt {
            width: resultList.width * 0.55 + scroll.width
            height: listHeader.height
            source: VistaScheme.art("header-0")
            margins: [8, 8, 3, 4]
            Text { x: panel.s(6); anchors.verticalCenter: parent.verticalCenter; text: root.filterText ? "In Folder" : "Type"; font.family: "Segoe UI"; font.pixelSize: Style.font.bodySmall; color: "#000000" }
          }
        }

        GridView {
          id: resultList
          readonly property int listInset: content.dmenu ? Math.max(1, panel.s(1)) : 0
          x: root.vistaGrid ? panel.s(26) : listInset
          y: root.vistaGrid ? pickHeader.y + pickHeader.height + panel.s(18) : listHeader.height + listInset
          width: content.width - x - (root.vistaGrid ? panel.s(20) : scroll.width + listInset)
          height: content.height - y - listInset
          model: displayModel
          clip: true
          boundsBehavior: Flickable.StopAtBounds
          cellWidth: root.vistaGrid ? Math.floor(width / 2) : width
          cellHeight: root.vistaGrid ? panel.s(52) : root.baseRowHeight

          delegate: Item {
            id: row
            required property int index
            required property string itemId
            required property string kind
            required property string appIcon
            required property string label
            required property string detail
            required property string action
            required property string icon
            required property bool disabled

            // Vista: a multi-select dmenu option draws its ✓/○ as a check box.
            readonly property bool isCheck: row.kind === "dmenu" && root.dmenuMultiple && row.itemId !== "dmenu.apply"
            readonly property bool hasCursor: root.cursorActive && row.index === root.selectedIndex
            readonly property bool isApp: row.kind === "app"
            readonly property url iconUrl: row.isApp && root.appLibrary ? root.appLibrary.iconSource(row.appIcon)
              : row.kind === "dmenu" ? "" : root.vistaIconFor(row.itemId, row.kind, row.action)

            width: resultList.cellWidth
            height: resultList.cellHeight
            // Vista: 4.5 `disabled:` rows (software already installed) are GrayText.
            readonly property color textColor: row.disabled ? VistaScheme.sc.gray
              : row.hasCursor ? VistaScheme.sc.highlightText : "#000000"

            // Category view: a 32 px icon and a link, dotted focus rectangle
            // for the keyboard cursor, underline on hover.
            Item {
              visible: root.vistaGrid
              anchors.fill: parent
              Image {
                id: bigIcon
                width: panel.s(32)
                height: panel.s(32)
                anchors.verticalCenter: parent.verticalCenter
                source: root.vistaGrid ? row.iconUrl : ""
                sourceSize.width: width
                sourceSize.height: height
              }
              Text {
                id: bigLabel
                anchors.left: bigIcon.right
                anchors.leftMargin: panel.s(8)
                anchors.right: parent.right
                anchors.rightMargin: panel.s(8)
                anchors.verticalCenter: parent.verticalCenter
                text: row.label
                wrapMode: Text.Wrap
                maximumLineCount: 2
                elide: Text.ElideRight
                color: row.disabled ? VistaScheme.sc.gray : VistaScheme.sc.normalText
                font.family: "Segoe UI"
                font.pixelSize: Style.font.bodySmall
                font.underline: mouseArea.containsMouse && !row.disabled
              }
              Rectangle {
                visible: row.hasCursor
                x: bigLabel.x - panel.s(2)
                y: bigLabel.y + (bigLabel.height - bigLabel.contentHeight) / 2 - panel.s(1)
                width: Math.min(bigLabel.contentWidth, bigLabel.width) + panel.s(4)
                height: bigLabel.contentHeight + panel.s(2)
                color: "transparent"
                border.width: 1
                border.color: "#000000"
                opacity: 0.6
              }
            }

            // Details view: Highlight on the selected row.
            Rectangle {
              visible: !root.vistaGrid
              anchors.fill: parent
              color: row.hasCursor ? VistaScheme.sc.highlight : "transparent"
              VistaCheckBox {
                id: checkBox
                visible: row.isCheck
                x: panel.s(4)
                anchors.verticalCenter: parent.verticalCenter
                checked: row.icon === "✓"
              }
              Image {
                id: smallIcon
                visible: row.kind !== "dmenu"
                x: panel.s(4)
                width: panel.s(16)
                height: panel.s(16)
                anchors.verticalCenter: parent.verticalCenter
                source: !root.vistaGrid && visible ? row.iconUrl : ""
                sourceSize.width: width * Screen.devicePixelRatio
                sourceSize.height: height * Screen.devicePixelRatio
                asynchronous: true
              }
              Text {
                id: nameText
                x: smallIcon.visible ? smallIcon.x + smallIcon.width + panel.s(5)
                  : checkBox.visible ? checkBox.x + checkBox.width + panel.s(5) : panel.s(5)
                width: (row.detail ? resultList.width * 0.45 : resultList.width) - x - panel.s(4)
                anchors.verticalCenter: parent.verticalCenter
                textFormat: Text.PlainText
                text: row.label
                elide: Text.ElideRight
                color: row.textColor
                font.family: root.vistaDmenuMono ? "Lucida Console" : "Segoe UI"
                font.pixelSize: Style.font.bodySmall
              }
              Text {
                visible: row.detail.length > 0
                x: resultList.width * 0.45 + panel.s(5)
                width: resultList.width * 0.55 - panel.s(10)
                anchors.verticalCenter: parent.verticalCenter
                textFormat: Text.PlainText
                text: row.detail
                elide: Text.ElideRight
                color: row.disabled ? VistaScheme.sc.gray : row.hasCursor ? VistaScheme.sc.highlightText : "#404040"
                font.family: "Segoe UI"
                font.pixelSize: Style.font.bodySmall
              }
            }

            MouseArea {
              id: mouseArea
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: root.vistaGrid && !row.disabled ? Qt.PointingHandCursor : Qt.ArrowCursor
              onEntered: root.selectFromPointer(row.index, row, { x: mouseArea.mouseX, y: mouseArea.mouseY })
              onPositionChanged: function(mouse) { root.selectFromPointer(row.index, row, mouse) }
              onClicked: {
                if (row.disabled) return
                root.cursorActive = true
                root.selectedIndex = row.index
                root.activateIndex(row.index, true)
              }
            }
          }
        }

        VistaScrollBar {
          id: scroll
          target: resultList
          x: content.width - width - resultList.listInset
          y: resultList.y
          height: resultList.height
          width: root.vistaGrid ? 0 : implicitWidth
        }

        Text {
          visible: displayModel.count === 0 && root.mode !== "input"
          anchors.centerIn: parent
          width: parent.width - panel.s(40)
          horizontalAlignment: Text.AlignHCenter
          wrapMode: Text.Wrap
          text: root.filterText
            ? "Search is complete. There are no results to display for “" + root.filterText + "”."
            : "There are no items to show in this view."
          color: "#000000"
          font.family: "Segoe UI"
          font.pixelSize: Style.font.bodySmall
        }
      }

      // ---- dmenu buttons
      Row {
        visible: root.vistaView === "dmenu"
        anchors.right: parent.right
        anchors.rightMargin: panel.s(12)
        anchors.bottom: parent.bottom
        anchors.bottomMargin: panel.s(12)
        spacing: panel.s(6)
        VistaButton {
          text: "OK"
          isDefault: true
          onClicked: {
            if (root.mode === "input") root.applyDmenuSelection(root.filterText)
            // Vista: multi-select OK = the 4.5 Apply row (index 0); a live
            // (onChange) selection has applied already, so OK just closes.
            else if (root.dmenuMultiple) {
              if (root.dmenuOnChange.length > 0) root.cancel()
              else root.activateIndex(0)
            }
            else if (displayModel.count > 0) root.activateIndex(root.cursorActive ? root.selectedIndex : 0)
          }
        }
        VistaButton { text: "Cancel"; onClicked: root.cancel() }
      }
    }
  }
}
