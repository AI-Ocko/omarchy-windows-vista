// ocko.vista-tray: omarchy.tray for the Vista notification area (Windows Vista theme
// only; see omarchy/vista/bin/vista-mode). Copied from
// /usr/share/omarchy/shell/plugins/bar/widgets/Tray.qml, Omarchy 4.5.0,
// sha256 bb0a6d360d885df58ac8ab44ff1a3668a3d913c36257a15e6282c4720dba8d2f.
// Every change is a line marked "Vista:" or one of the two pop-ups, each
// replaced whole under an "Vista:" comment: Customize Notifications and the
// cascading app menu. Re-diff against a newer Omarchy:
// diff <(tail -n +10 Tray.qml) /usr/share/omarchy/shell/plugins/bar/widgets/Tray.qml

import Quickshell
import QtQuick
import QtQuick.Controls
import QtQuick.Effects
import Quickshell.Services.SystemTray
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "TrayModel.js" as TrayModel
import Quickshell.Hyprland  // Vista
import "../../vista/qml"  // Vista

BarWidget {
  id: root
  moduleName: "omarchy.tray"

  property bool expanded: false
  // Vista: Omarchy indicators on this monitor, which hide behind the chevron
  // (set by ocko.vista-taskbar). The drawer must exist while there are any,
  // tray apps or not, or they would be unreachable.
  property int vistaHiddenIndicators: 0
  property bool managePopupOpen: false
  property bool trayMenuOpen: false
  property var activeTrayItem: null
  property var activeTrayAnchor: null
  readonly property color foreground: bar ? bar.foreground : Commons.Color.foreground
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property var pinnedIds: settings.pinned instanceof Array ? settings.pinned : []
  readonly property var hiddenIds: settings.hidden instanceof Array ? settings.hidden : []
  readonly property var pinnedItems: bucket("pinned")
  readonly property var drawerItems: bucket("drawer")
  readonly property var allItems: bucket("all")
  readonly property int drawerCount: drawerItems.length
  readonly property int trayItemExtent: Style.bar.iconSlot
  readonly property int trayItemGap: 0
  readonly property int trayJoinGap: 0
  // Bar widgets dragged into the tray section sit in the drawer after the
  // app icons. The bar draws them into sectionHost, and outlines it while a
  // widget is dragged, as it does the center box.
  property Item sectionHost: null
  // The part of the tray section the drawer shows, in the tray ({ x, y,
  // width, height }), or null while it shows none of it. It moves with the
  // drawer's contents as they slide in and out, and is cut to the drawer as
  // they are, so the bar's outline of it never reaches past the tray.
  readonly property var sectionShown: trayContent.item ? trayContent.item.sectionShown : null
  readonly property int sectionCount: bar && bar.layoutConfig && Array.isArray(bar.layoutConfig.tray) ? bar.layoutConfig.tray.length : 0
  readonly property real sectionExtent: sectionHost ? (vertical ? sectionHost.implicitHeight : sectionHost.implicitWidth) : 0
  readonly property bool hasDrawer: allItems.length > 0 || sectionCount > 0 || barDragging || vistaHiddenIndicators > 0  // Vista: was allItems.length > 0 || sectionCount > 0 || barDragging
  readonly property int drawerExtent: drawerCount * trayItemExtent + Math.max(0, drawerCount - 1) * trayItemGap + sectionExtent
  // A widget being dragged along the bar opens the drawer, to show where it
  // can go, and so does any panel open from the tray or the tray section.
  readonly property bool barDragging: !!bar && bar.traySectionDragActive === true
  readonly property bool holdOpen: trayMenuOpen || managePopupOpen || barDragging || (!!bar && bar.traySectionPopoutOpen === true)
  // The mark under the bar sits under the icon whose menu is open.
  readonly property Item openPanelIndicatorItem: trayMenuOpen ? activeTrayAnchor : null
  // Match Waybar's group/tray-expander drawer transition-duration.
  readonly property int animationDuration: 600
  property real revealProgress: expanded || holdOpen ? 1 : 0
  readonly property real revealExtent: drawerExtent * revealProgress
  // The pinned icons sit against the tray's fixed edge with the chevron past
  // them. Opening, the drawer grows the tray between the two and pushes the
  // chevron out of the way, while the pointer that opened it stays over the
  // drawer. A centered tray keeps the end-fixed arrangement.
  readonly property bool fixedAtStart: fixedEdge === "start"
  // The edge the tray section's widgets grow from: the one the pinned icons
  // keep to, beside which the section opens.
  readonly property string sectionEdge: fixedAtStart ? "start" : "end"

  // Submenu drill-down state. QsMenuEntry.display() renders a *platform* menu,
  // which Quickshell refuses unless the shell root sets `//@ pragma
  // UseQApplication` - omarchy's shell.qml does not, so every submenu click was
  // a silent no-op ("Cannot display PlatformMenuEntry as quickshell was not
  // started in QApplication mode" in the shell log) and apps whose whole UI is
  // submenus, e.g. radiotray-ng's station list, were unusable. QsMenuEntry
  // inherits QsMenuHandle, so a child entry can feed a nested QsMenuOpener and
  // render inside this popup instead of going through the platform. Each level
  // keeps its own live opener: a child entry is owned by its parent opener's
  // model, so collapsing the stack to a single opener would destroy the very
  // entry being displayed (submenu turns up empty).
  property var submenuStack: []
  readonly property int submenuDepth: submenuStack.length
  readonly property string currentTitle: submenuDepth > 0 ? submenuStack[submenuDepth - 1].title : ""
  readonly property var currentChildren: submenuDepth > 0
    ? submenuStack[submenuDepth - 1].opener.children
    : trayMenuOpener.children

  // Changing level rebuilds the row delegates synchronously, so the next
  // row lands under a cursor that hasn't moved. Submenu clicks used to be
  // silent no-ops, which trained users to click them twice, and that second
  // click would now fire whatever entry took the spot. Ignore row clicks for
  // a beat after each level change; a deliberate follow-up click is slower.
  property bool menuLevelSettling: false

  Component {
    id: submenuOpenerComponent
    QsMenuOpener {}
  }

  Timer {
    id: menuLevelSettleTimer
    interval: 250
    onTriggered: root.menuLevelSettling = false
  }

  function settleMenuLevel() {
    menuLevelSettling = true
    menuLevelSettleTimer.restart()
  }

  function resetTrayMenu() {
    menuLevelSettling = false
    menuLevelSettleTimer.stop()
    // Flickable keeps its offset across a model swap whenever the new content
    // is still tall enough to hold it, so a menu dismissed while scrolled
    // would otherwise reopen part-way down with its first entries off screen.
    // Vista: no Flickable; each menu level is its own popup.
    // Clear the reactive stack before tearing anything down, so no binding can
    // read a partially-destroyed opener while this runs. Then destroy deepest
    // first: an inner opener's menu entry is owned by its parent's children
    // model, so destroying a parent first would invalidate an entry a still-
    // live child opener references.
    var openers = submenuStack
    submenuStack = []
    for (var i = openers.length - 1; i >= 0; i--) openers[i].opener.destroy()
  }

  function enterSubmenu(entry, title) {
    var opener = submenuOpenerComponent.createObject(root, { menu: entry })
    if (!opener) return
    var stack = submenuStack.slice()
    stack.push({ opener: opener, title: title })
    submenuStack = stack
    settleMenuLevel()
  }

  function leaveSubmenu() {
    if (submenuStack.length === 0) return
    var stack = submenuStack.slice()
    var top = stack.pop()
    submenuStack = stack
    top.opener.destroy()
    settleMenuLevel()
  }

  function close() {
    managePopupOpen = false
    trayMenuOpen = false
  }

  function openTrayMenu(item, anchorItem, mouse) {
    if (!item || !item.menu) {
      var point = anchorItem.QsWindow.contentItem.mapFromItem(anchorItem, mouse.x, mouse.y)
      item.display(anchorItem.QsWindow.window, point.x, point.y)
      return
    }

    // Reset before switching items: trayMenuOpener.menu binds to
    // activeTrayItem.menu, so assigning a new item invalidates the old root's
    // children immediately, before any nested opener referencing them would
    // otherwise get torn down.
    resetTrayMenu()
    activeTrayItem = item
    activeTrayAnchor = anchorItem
    trayMenuOpen = true
  }

  function trayIconSource(icon) {
    // Quickshell already resolves the tray icon into a ready-to-use image://
    // URL, including a "?path=" fallback search dir for apps that ship their
    // tray icon outside a standard theme (e.g. Steam's flat public/ dir). Hand
    // it straight to IconImage; guessing a theme sub-directory here only broke
    // apps whose layout didn't match the guess.
    return String(icon || "")
  }

  // Symbolic icons ship a fixed fill (light or dark) that the host is meant
  // to recolor to its foreground; detect them by the freedesktop "-symbolic"
  // name suffix so they can be tinted instead of rendered as-is.
  function iconIsSymbolic(icon) {
    var name = String(icon || "").split("?")[0]
    return name.slice(-9) === "-symbolic"
  }

  function trayTooltip(item) {
    return item.tooltipTitle || item.title || item.id || ""
  }

  function classifyItem(item) {
    var iid = String(item.id || "")
    if (hiddenIds.indexOf(iid) !== -1) return "hidden"
    if (pinnedIds.indexOf(iid) !== -1) return "pinned"
    return "drawer"
  }

  function ownedByOmarchy(item) {
    var layout = root.bar && root.bar.layoutConfig ? root.bar.layoutConfig : null
    return TrayModel.ownedByOmarchy(item, layout)
  }

  function bucket(category) {
    var values = SystemTray.items.values
    var result = []
    for (var i = 0; i < values.length; i++) {
      var item = values[i]
      if (item.status === Status.Passive) continue
      if (ownedByOmarchy(item)) continue
      if (category === "all") {
        result.push(item)
        continue
      }
      if (classifyItem(item) === category) result.push(item)
    }
    return result
  }

  function persistTrayState(pinned, hidden) {
    if (!root.bar || !root.bar.shell || typeof root.bar.shell.updateEntryInline !== "function") return
    var id = root.moduleName || "omarchy.tray"
    root.bar.shell.updateEntryInline(id, { id: id, pinned: pinned, hidden: hidden })
  }

  function togglePin(iid) {
    var p = pinnedIds.slice(), h = hiddenIds.slice()
    var idx = p.indexOf(iid)
    if (idx !== -1) p.splice(idx, 1)
    else {
      p.push(iid)
      var hi = h.indexOf(iid)
      if (hi !== -1) h.splice(hi, 1)
    }
    persistTrayState(p, h)
  }

  function toggleHide(iid) {
    var p = pinnedIds.slice(), h = hiddenIds.slice()
    var idx = h.indexOf(iid)
    if (idx !== -1) h.splice(idx, 1)
    else {
      h.push(iid)
      var pi = p.indexOf(iid)
      if (pi !== -1) p.splice(pi, 1)
    }
    persistTrayState(p, h)
  }

  visible: pinnedItems.length > 0 || hasDrawer
  clip: false
  implicitWidth: root.vertical ? root.barSize : trayContent.implicitWidth
  implicitHeight: root.vertical ? trayContent.implicitHeight : root.barSize

  Behavior on revealProgress {
    NumberAnimation { duration: Style.duration(root.animationDuration); easing.type: Easing.OutCubic }
  }

  // The section from `start`, `length` long along the bar, as far as the
  // drawer's clip from `clipStart`, `clipLength` long, shows it
  // (TrayModel.shownSpan).
  function shownSection(clipStart, clipLength, start, length) {
    var span = TrayModel.shownSpan(clipStart, clipLength, start, length)
    if (!span) return null
    return vertical
      ? { x: 0, y: span.start, width: barSize, height: span.length }
      : { x: span.start, y: 0, width: span.length, height: barSize }
  }

  Loader {
    id: trayContent
    anchors.fill: parent
    sourceComponent: root.vertical ? verticalTray : horizontalTray
  }

  Component {
    id: horizontalTray

    Item {
      id: horizontalTrayRoot

      readonly property int chevronWidth: root.hasDrawer ? expandIcon.implicitWidth : 0
      readonly property var sectionShown: root.shownSection(drawerArea.x + trayClip.x, trayClip.width, drawerArea.x + trayClip.x + drawerContent.x + section.x, section.width)

      implicitWidth: pinnedRow.implicitWidth + chevronWidth + root.revealExtent
      implicitHeight: root.barSize

      Item {
        id: drawerArea
        x: root.fixedAtStart ? pinnedRow.implicitWidth : 0
        width: horizontalTrayRoot.chevronWidth + root.revealExtent
        height: root.barSize
        visible: root.hasDrawer

        HoverHandler {
          onHoveredChanged: root.expanded = hovered
        }

        BarIconButton {
          id: expandIcon
          bar: root.bar
          width: implicitWidth
          height: implicitHeight
          x: root.fixedAtStart ? root.revealExtent : 0
          text: root.fixedAtStart ? "\uf054" : "\uf053"
          onPressed: function(button) {
            if (button === Qt.RightButton) root.managePopupOpen = !root.managePopupOpen
          }
        }

        // The icons and the tray section travel out with the chevron from
        // beside the pinned icons, the section nearest them.
        Item {
          id: trayClip
          x: root.fixedAtStart ? 0 : expandIcon.width
          anchors.verticalCenter: parent.verticalCenter
          width: root.revealExtent
          height: root.barSize
          clip: true

          Item {
            id: drawerContent
            x: root.fixedAtStart ? root.revealExtent - root.drawerExtent : 0
            width: root.drawerExtent
            height: root.barSize

            Row {
              id: trayIcons
              x: root.fixedAtStart ? root.sectionExtent : 0
              anchors.verticalCenter: parent.verticalCenter
              spacing: root.trayItemGap
              layer.enabled: true

              Repeater {
                model: root.drawerItems
                TrayItem {}
              }
            }

            // Placed by hand: a Row leaves a child with no width where it
            // was, and an empty section has none.
            SectionArea {
              id: section
              x: root.fixedAtStart ? 0 : trayIcons.width
              anchors.verticalCenter: parent.verticalCenter
            }
          }
        }
      }

      Row {
        id: pinnedRow
        x: root.fixedAtStart ? 0 : drawerArea.width
        anchors.verticalCenter: parent.verticalCenter
        spacing: root.trayItemGap
        leftPadding: !root.fixedAtStart && root.pinnedItems.length > 0 && root.allItems.length > 0 ? root.trayJoinGap : 0
        rightPadding: root.fixedAtStart && root.pinnedItems.length > 0 && root.allItems.length > 0 ? root.trayJoinGap : 0
        Repeater {
          model: root.pinnedItems
          TrayItem {}
        }
      }
    }
  }

  Component {
    id: verticalTray

    Item {
      id: verticalTrayRoot

      readonly property int chevronHeight: root.hasDrawer ? expandIcon.implicitHeight : 0
      readonly property var sectionShown: root.shownSection(drawerArea.y + trayClip.y, trayClip.height, drawerArea.y + trayClip.y + drawerContent.y + section.y, section.height)

      implicitWidth: root.barSize
      implicitHeight: pinnedCol.implicitHeight + chevronHeight + root.revealExtent

      Item {
        id: drawerArea
        y: root.fixedAtStart ? pinnedCol.implicitHeight : 0
        width: root.barSize
        height: verticalTrayRoot.chevronHeight + root.revealExtent
        visible: root.hasDrawer

        HoverHandler {
          onHoveredChanged: root.expanded = hovered
        }

        BarIconButton {
          id: expandIcon
          bar: root.bar
          width: implicitWidth
          height: implicitHeight
          y: root.fixedAtStart ? root.revealExtent : 0
          text: root.fixedAtStart ? "\uf054" : "\uf053"
          textRotation: 90
          onPressed: function(button) {
            if (button === Qt.RightButton) root.managePopupOpen = !root.managePopupOpen
          }
        }

        // The icons and the tray section travel out with the chevron from
        // beside the pinned icons, the section nearest them.
        Item {
          id: trayClip
          y: root.fixedAtStart ? 0 : expandIcon.height
          anchors.horizontalCenter: parent.horizontalCenter
          width: root.barSize
          height: root.revealExtent
          clip: true

          Item {
            id: drawerContent
            y: root.fixedAtStart ? root.revealExtent - root.drawerExtent : 0
            width: root.barSize
            height: root.drawerExtent

            Column {
              id: trayIcons
              y: root.fixedAtStart ? root.sectionExtent : 0
              anchors.horizontalCenter: parent.horizontalCenter
              spacing: root.trayItemGap
              layer.enabled: true

              Repeater {
                model: root.drawerItems
                TrayItem {}
              }
            }

            // Placed by hand: a Column leaves a child with no height where it
            // was, and an empty section has none.
            SectionArea {
              id: section
              y: root.fixedAtStart ? 0 : trayIcons.height
              anchors.horizontalCenter: parent.horizontalCenter
            }
          }
        }
      }

      Column {
        id: pinnedCol
        y: root.fixedAtStart ? 0 : drawerArea.height
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: root.trayItemGap
        topPadding: !root.fixedAtStart && root.pinnedItems.length > 0 && root.allItems.length > 0 ? root.trayJoinGap : 0
        bottomPadding: root.fixedAtStart && root.pinnedItems.length > 0 && root.allItems.length > 0 ? root.trayJoinGap : 0
        Repeater {
          model: root.pinnedItems
          TrayItem {}
        }
      }
    }
  }

  // Vista: the pin/hide manager is explorer.exe's "Customize Notifications"
  // (dialog 7, 232x240 DLU; the strings are explorer's own). Behaviours map
  // onto stock's two lists: Always show = pinned, Always hide = hidden, Hide
  // when inactive = neither (the drawer). As in Vista, choices are staged and
  // written on OK, through stock's persistTrayState. Past Items are ids still
  // in shell.json whose app is not reporting now.
  readonly property var vistaBehaviors: ["Hide when inactive", "Always hide", "Always show"]
  property var vistaPinned: []
  property var vistaHidden: []
  property int vistaRow: -1
  onManagePopupOpenChanged: {
    vistaPinned = pinnedIds.slice()
    vistaHidden = hiddenIds.slice()
    vistaRow = -1
  }
  function vistaDu(x) { return Style.space(Math.round(x * 1.5)) }
  function vistaDv(y) { return Style.space(Math.round(y * 13 / 8)) }
  function vistaTail(id) {
    var slash = id.lastIndexOf("/")
    return slash !== -1 ? id.substring(slash + 1) : (id || "Unknown")
  }
  // Stock's row label, from its manage-popup delegate.
  function vistaName(item) {
    var t = String(item.title || "").trim()
    if (t) return t
    var tt = String(item.tooltipTitle || "").trim()
    if (tt) return tt
    return vistaTail(String(item.id || ""))
  }
  readonly property var vistaEntries: {
    var out = [{ group: "Current Items" }]
    var seen = ({})
    for (var i = 0; i < allItems.length; i++) {
      var id = String(allItems[i].id || "")
      seen[id] = true
      out.push({ id: id, name: vistaName(allItems[i]), icon: allItems[i].icon })
    }
    var past = pinnedIds.concat(hiddenIds).filter(function(x, k, a) { return !seen[x] && a.indexOf(x) === k })
    if (past.length) out.push({ group: "Past Items" })
    for (var j = 0; j < past.length; j++) out.push({ id: past[j], name: vistaTail(past[j]), icon: "" })
    return out
  }
  function vistaBehavior(id) {
    return vistaHidden.indexOf(id) !== -1 ? 1 : vistaPinned.indexOf(id) !== -1 ? 2 : 0
  }
  function vistaSetBehavior(id, b) {
    var p = vistaPinned.filter(function(x) { return x !== id })
    var h = vistaHidden.filter(function(x) { return x !== id })
    if (b === 2) p.push(id)
    else if (b === 1) h.push(id)
    vistaPinned = p
    vistaHidden = h
  }

  PopupCard {
    id: managePopup
    anchorItem: root
    owner: root
    bar: root.bar
    open: root.managePopupOpen
    padding: 0
    borderSpec: Border.none()
    contentWidth: vistaCustomize.width
    contentHeight: vistaCustomize.height

    VistaWindow {
      id: vistaCustomize
      width: root.vistaDu(232) + Style.space(6)
      height: root.vistaDv(240) + Style.space(29 + 3)
      title: "Customize Notifications"
      buttons: ["help", "close"]
      disabledButtons: ["help"]
      onCloseClicked: root.managePopupOpen = false
      // Drop the stock card behind the Vista window.
      Component.onCompleted: {
        var card = parent ? parent.parent : null
        if (card && "radius" in card) { card.color = "transparent"; card.radius = 0 }
      }

      VistaLabel {
        x: root.vistaDu(6); y: root.vistaDv(6); width: root.vistaDu(220)
        wrapMode: Text.WordWrap
        text: "Windows displays icons for active and urgent notifications, and hides inactive ones. You can change this behavior for items in the list below."
      }
      VistaLabel {
        x: root.vistaDu(6); y: root.vistaDv(40)
        text: "Select an item, then choose its notification behavior:"
      }
      VistaListView {
        id: vistaList
        x: root.vistaDu(6); y: root.vistaDv(50); width: root.vistaDu(220); height: root.vistaDv(128)
        // The Behavior column starts where the template puts its combo
        // (x 103 DLU), so the in-place combo covers the cell exactly.
        columns: [{ title: "Name", width: 144 }, { title: "Behavior", width: 80 }]
        rows: root.vistaEntries.map(function(e) { return e.group !== undefined ? e : [e.name, root.vistaBehaviors[root.vistaBehavior(e.id)]] })
        currentIndex: root.vistaRow
        focused: true
        leading: Component {
          TrayIcon {
            readonly property var entry: root.vistaEntries[parent ? parent.rowIndex : -1] || ({})
            icon: entry.icon || ""
            tint: "#000000"
          }
        }
        onClicked: function(i) { root.vistaRow = i }
      }
      // Vista turns the selected row's Behavior cell into a drop-down.
      VistaComboBox {
        readonly property var entry: root.vistaEntries[root.vistaRow] || ({})
        readonly property real rowTop: vistaList.headerHeight + 1 + root.vistaRow * vistaList.rowHeight - vistaList.contentY
        visible: root.vistaRow > 0 && entry.group === undefined && rowTop >= vistaList.headerHeight && rowTop + vistaList.rowHeight <= vistaList.height - 1
        z: 5
        x: vistaList.x + 1 + Style.space(144)
        y: vistaList.y + rowTop + (vistaList.rowHeight - height) / 2
        width: vistaList.width - 2 - Style.space(144)
        height: vistaList.rowHeight + Style.space(2)
        model: root.vistaBehaviors
        currentIndex: visible ? root.vistaBehavior(entry.id) : -1
        onActivated: function(i) { root.vistaSetBehavior(entry.id, i) }
      }
      VistaButton {
        x: root.vistaDu(164); y: root.vistaDv(188); width: root.vistaDu(62); height: root.vistaDv(14)
        text: "<u>R</u>estore Defaults"
        onClicked: { root.vistaPinned = []; root.vistaHidden = [] }
      }
      VistaButton {
        x: root.vistaDu(122); y: root.vistaDv(220); width: root.vistaDu(50); height: root.vistaDv(14)
        text: "OK"
        isDefault: true
        onClicked: {
          root.persistTrayState(root.vistaPinned, root.vistaHidden)
          root.managePopupOpen = false
        }
      }
      VistaButton {
        x: root.vistaDu(176); y: root.vistaDv(220); width: root.vistaDu(50); height: root.vistaDv(14)
        text: "Cancel"
        onClicked: root.managePopupOpen = false
      }
    }
  }

  // Vista: the app's menu as Vista's cascading context menu, one popup per level,
  // placed by the compositor the way Vista places menus: the root opens at the
  // pointer and flips up/left at the screen edges; a submenu opens beside
  // its row and flips left when it would not fit. Stock's drill-down stack
  // holds the open levels (level k + 1 is submenuStack[k]), so stock's
  // opener lifetime rules are untouched; vistaOpenRows remembers which row of
  // each level a submenu came from. A submenu opens on click or after Vista's
  // 400 ms hover delay (SPI_GETMENUSHOWDELAY).
  property real vistaMenuX: 0
  property real vistaMenuY: 0
  property var vistaOpenRows: []

  onTrayMenuOpenChanged: {
    if (root.bar) {
      if (trayMenuOpen) root.bar.requestPopout(root)
      else if (root.bar.activePopout === root) root.bar.releasePopout(root)
      // Vista drops the icon's tip when its menu opens.
      if (trayMenuOpen && root.activeTrayAnchor) root.bar.hideTooltip(root.activeTrayAnchor)
    }
    if (!trayMenuOpen) {
      vistaHoverTimer.stop()
      vistaOpenRows = []
      resetTrayMenu()
    }
  }

  // A level's rows, minus the two root rows stock's delegate hides: the
  // app's own title entry and a leading separator.
  function vistaRows(level) {
    var model = level === 0 ? trayMenuOpener.children
      : level <= submenuStack.length ? submenuStack[level - 1].opener.children : null
    var vals = model ? model.values : []
    var title = activeTrayItem ? String(activeTrayItem.title || activeTrayItem.id || "").toLowerCase() : ""
    var out = []
    for (var i = 0; i < vals.length; i++) {
      var e = vals[i]
      if (level === 0 && i === 0 && e.hasChildren && String(e.text || "").toLowerCase() === title) continue
      if (level === 0 && e.isSeparator && i <= 1) continue
      out.push(e)
    }
    return out
  }
  function vistaItem(e) {
    if (e.isSeparator) return { separator: true }
    var checkable = e.buttonType !== QsMenuButtonType.None
    return {
      text: String(e.text || "").replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;"),
      enabled: e.enabled,
      submenu: e.hasChildren,
      checked: checkable && e.checkState === Qt.Checked,
      radio: e.buttonType === QsMenuButtonType.RadioButton,
      icon: String(e.icon || "")
    }
  }
  // Open row i's submenu at `level` (closing anything deeper), or, for a
  // plain row, just close the deeper levels.
  function vistaOpenSubmenu(level, i) {
    if (submenuDepth > level && vistaOpenRows[level] === i) {
      while (submenuDepth > level + 1) leaveSubmenu()
      vistaOpenRows = vistaOpenRows.slice(0, level + 1)
      return
    }
    while (submenuDepth > level) leaveSubmenu()
    var open = vistaOpenRows.slice(0, level)
    var e = vistaRows(level)[i]
    if (e && e.hasChildren && e.enabled) {
      open.push(i)
      vistaOpenRows = open
      enterSubmenu(e, String(e.text || ""))
    } else {
      vistaOpenRows = open
    }
  }
  function vistaActivate(level, i) {
    if (menuLevelSettling) return
    var e = vistaRows(level)[i]
    if (!e || e.isSeparator || !e.enabled) return
    if (e.hasChildren) {
      vistaOpenSubmenu(level, i)
      return
    }
    e.triggered()
    root.close()
  }

  Timer {
    id: vistaHoverTimer
    interval: 400
    property int level: -1
    property int row: -1
    onTriggered: root.vistaOpenSubmenu(level, row)
  }

  QsMenuOpener {
    id: trayMenuOpener
    menu: root.activeTrayItem ? root.activeTrayItem.menu : null
  }

  // Outside-click dismissal over every level, as PopupCard does for one.
  HyprlandFocusGrab {
    active: root.trayMenuOpen && vistaLevels.instances.length > 0
    windows: {
      var w = []
      for (var i = 0; i < vistaLevels.instances.length; i++) w.push(vistaLevels.instances[i])
      var bar = root.activeTrayAnchor ? root.activeTrayAnchor.QsWindow.window : null
      if (bar) w.push(bar)
      return w
    }
    onCleared: root.close()
  }

  Variants {
    id: vistaLevels
    model: {
      var n = root.trayMenuOpen && root.activeTrayItem ? root.submenuDepth + 1 : 0
      var levels = []
      for (var i = 0; i < n; i++) levels.push(i)
      return levels
    }

    PopupWindow {
      id: vistaLevel
      required property var modelData
      readonly property int depth: modelData
      readonly property var rows: root.vistaRows(depth)
      readonly property var parentLevel: depth > 0 ? vistaLevels.instances[depth - 1] : null
      readonly property Item menuItem: levelMenu
      readonly property real overlap: Style.space(3)

      visible: true
      color: "transparent"
      implicitWidth: levelMenu.implicitWidth
      implicitHeight: levelMenu.implicitHeight

      anchor.item: depth === 0 ? root.activeTrayAnchor : (parentLevel ? parentLevel.menuItem : null)
      anchor.rect.x: depth === 0 ? root.vistaMenuX : overlap
      anchor.rect.y: depth === 0 ? root.vistaMenuY : (parentLevel ? parentLevel.menuItem.rowY(root.vistaOpenRows[depth - 1] || 0) - Style.space(3) : 0)
      anchor.rect.width: depth === 0 || !parentLevel ? 1 : parentLevel.menuItem.width - parentLevel.menuItem.shadow - 2 * overlap
      anchor.rect.height: 1
      anchor.edges: depth === 0 ? Edges.Top | Edges.Left : Edges.Top | Edges.Right
      anchor.gravity: depth === 0 ? Edges.Top | Edges.Right : Edges.Bottom | Edges.Right
      anchor.adjustment: PopupAdjustment.Flip | PopupAdjustment.Slide

      VistaMenu {
        id: levelMenu
        width: implicitWidth
        height: implicitHeight
        items: vistaLevel.rows.map(root.vistaItem)
        onCurrentIndexChanged: {
          if (currentIndex < 0) return
          vistaHoverTimer.level = vistaLevel.depth
          vistaHoverTimer.row = currentIndex
          vistaHoverTimer.restart()
        }
        onTriggered: function(i) {
          vistaHoverTimer.stop()
          root.vistaActivate(vistaLevel.depth, i)
        }
      }
    }
  }

  // Renders a tray icon, recoloring symbolic icons to the bar foreground so
  // they stay visible on any theme (a raw symbolic icon keeps its baked-in
  // fill and disappears against a matching background).
  component TrayIcon: Item {
    id: trayIconRoot
    required property var icon
    property color tint: root.foreground  // Vista: black on the white list
    readonly property bool symbolic: root.iconIsSymbolic(icon)

    Image {
      id: trayIconImage
      anchors.fill: parent
      fillMode: Image.PreserveAspectFit
      // Decode at physical pixels: IconImage uses the logical size,
      // which leaves PNG icons upscaled and blurry on HiDPI displays.
      sourceSize.width: Math.round(Math.min(width, height) * Screen.devicePixelRatio)
      sourceSize.height: Math.round(Math.min(width, height) * Screen.devicePixelRatio)
      source: root.trayIconSource(trayIconRoot.icon)
      // Kept as a hidden layer so the effect can sample it as a texture.
      visible: !trayIconRoot.symbolic
      layer.enabled: trayIconRoot.symbolic
    }

    // Paint the foreground through the icon's alpha. MultiEffect's colorization
    // keeps the source's lightness, so a dark fill stayed dark on a dark bar.
    Rectangle {
      anchors.fill: trayIconImage
      color: trayIconRoot.tint  // Vista: was root.foreground
      visible: trayIconRoot.symbolic
      layer.enabled: trayIconRoot.symbolic
      layer.effect: MultiEffect {
        maskEnabled: true
        maskSource: trayIconImage
        maskThresholdMin: 0.5
        maskSpreadAtMin: 1.0
      }
    }
  }

  // The tray section's place in the drawer: the bar parents its widgets here.
  // Empty, it takes no room.
  component SectionArea: Item {
    id: sectionArea
    implicitWidth: childrenRect.width
    implicitHeight: childrenRect.height

    Component.onCompleted: root.sectionHost = sectionArea
    // The bar can tear this area down after the widget itself is gone
    // (a plugin rescan destroys them in its own order), so unregister
    // only while the widget is still there to unregister from.
    Component.onDestruction: if (root && root.sectionHost === sectionArea) root.sectionHost = null
  }

  component TrayItem: Item {
    id: trayItemRoot

    required property var modelData

    visible: modelData.status !== Status.Passive
    implicitWidth: visible ? root.trayItemExtent : 0
    implicitHeight: visible ? root.trayItemExtent : 0

    function displayMenu(mouse) {
      root.vistaMenuX = mouse.x  // Vista: Vista menus open at the pointer
      root.vistaMenuY = mouse.y  // Vista
      root.openTrayMenu(trayItemRoot.modelData, trayItemRoot, mouse)
    }

    TrayIcon {
      x: Math.round((parent.width - width) / 2)
      y: Math.round((parent.height - height) / 2)
      width: Style.bar.iconSize
      height: Style.bar.iconSize
      icon: trayItemRoot.modelData.icon
    }

    MouseArea {
      id: mouseArea
      anchors.fill: parent
      acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onEntered: if (root.bar) root.bar.showTooltip(trayItemRoot, root.trayTooltip(modelData))
      onExited: if (root.bar) root.bar.hideTooltip(trayItemRoot)
      onPressed: function(mouse) {
        if (mouse.button === Qt.RightButton) {
          trayItemRoot.displayMenu(mouse)
          mouse.accepted = true
        }
      }
      onClicked: function(mouse) {
        if (mouse.button === Qt.RightButton) {
          mouse.accepted = true
        } else if (mouse.button === Qt.MiddleButton) {
          trayItemRoot.modelData.secondaryActivate()
        } else if (trayItemRoot.modelData.onlyMenu) {
          trayItemRoot.displayMenu(mouse)
        } else {
          trayItemRoot.modelData.activate()
        }
      }
      onWheel: function(wheel) {
        trayItemRoot.modelData.scroll(wheel.angleDelta.y, false)
      }
    }

    readonly property bool tooltipHovered: visible && opacity > 0 && mouseArea.containsMouse
  }
}
