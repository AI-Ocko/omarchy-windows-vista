import QtQuick
import qs.Commons
import "../../vista/qml"

// Vista SP2's "Bluetooth Devices" control panel over the stock Bluetooth
// panel's model. `host` is the panel (ocko.vista-bluetooth Panel.qml) or, for
// the screenshot harness, a mock with the same members; nothing here touches
// Quickshell.Bluetooth, so the mock never needs an adapter.
//
// Geometry is xpsp2res.dll's own dialog templates (Vista SP2), from dialog units
// at Tahoma 8 / 96 dpi (1 DLU = 1.5 px across, 13/8 px down):
//   107  Devices, 135 Options, 132 COM Ports (pages 227 x 215)
//   136  Select Bluetooth Device (Add...), 325 x 195
//   138  <device> Properties > General, 227 x 215
// The Hardware tab is the generic Device Manager page (134 is only its
// error text), laid out from memory; see the report.
//
// host reads:  adapter (enabled, discovering, discoverable, pairable, name,
//   adapterId; or null), connectedRows, scrollRows, cursorActive,
//   focusSection, selectedIndex, headerHasCursor, toggleHint,
//   heroStatusText, phraseIndex, phraseOpacity, vistaTab, vistaAddOpen,
//   vistaPropsOpen, vistaPropsAddress, vistaMenuOpen, vistaMinX
// host calls: deviceLabel, pendingAction, deviceFor, connectDevice,
//   disconnectDevice, forgetDevice, toggleBluetooth, vistaSelect, vistaTypeOf,
//   vistaSearchAgain, close
Item {
  id: bt

  required property var host
  readonly property alias sheet: sheet
  readonly property alias menu: ctxMenu

  width: sheet.width
  height: sheet.height

  function s(n) { return Style.space(n) }
  function du(x) { return Style.space(Math.round(x * 1.5)) }
  function dv(y) { return Style.space(Math.round(y * 13 / 8)) }
  function icon(id, size) { return VistaScheme.graphics + "/xpsp2res/" + size + "/" + id + ".png" }

  readonly property var adapter: host.adapter
  readonly property bool radioOn: !!adapter && adapter.enabled === true

  // Devices list: connected, then stock's scroll rows (paired, and what the
  // scan turned up while it runs), each tagged with its stock section.
  readonly property var rows: {
    var out = []
    var c = host.connectedRows || []
    for (var i = 0; i < c.length; i++) out.push({ dev: c[i], section: "connected", indexInSection: i })
    var r = host.scrollRows || []
    for (var j = 0; j < r.length; j++) out.push(r[j])
    return out
  }
  readonly property var foundRows: rows.filter(function(r) { return r.section === "discovered" })
  readonly property var selectedRow: {
    if (!host.cursorActive) return null
    for (var i = 0; i < rows.length; i++)
      if (rows[i].section === host.focusSection && rows[i].indexInSection === host.selectedIndex) return rows[i]
    return null
  }
  readonly property var propsRow: {
    for (var i = 0; i < rows.length; i++) if (rows[i].dev.address === host.vistaPropsAddress) return rows[i]
    return null
  }

  function groupTitle(section) {
    return section === "connected" ? "Connected" : section === "known" ? "Paired" : "Available devices"
  }

  // Stock DeviceRow.statusText, with Vista wording where stock leaves it blank.
  function statusText(row) {
    var dev = row.dev
    var action = host.pendingAction(dev.address)
    if (action === "forgetting") return "Removing..."
    if (action === "disconnecting" || dev.state === 2) return "Disconnecting..."
    if (dev.connected) return dev.batteryAvailable ? "Connected, battery " + Math.round(dev.battery * 100) + "%" : "Connected"
    if (action === "connecting" || dev.state === 3 || dev.pairing === true) return "Connecting..."
    return row.section === "discovered" ? "Not paired" : "Paired"
  }

  function activate(row) {
    var d = host.deviceFor(row)
    if (!d) return
    if (row.dev.connected) host.disconnectDevice(d)
    else host.connectDevice(d)
  }

  function forget(row) {
    var d = host.deviceFor(row)
    if (d) host.forgetDevice(d)
  }

  function canForget(row) {
    return !!row && (row.section === "known" || row.section === "connected")
  }

  // The context menu's actions, for the owner's Enter key and for clicks.
  function menuTrigger(i) {
    var row = selectedRow
    host.vistaMenuOpen = false
    if (!row) return
    if (i === 0) activate(row)
    else if (i === 1) forget(row)
    else if (i === 3) { host.vistaPropsAddress = row.dev.address; host.vistaPropsOpen = true }
  }

  // A device tile: 32 px icon, the name, and a grey status line, as Vista's
  // tile view drew Bluetooth devices. Selection is the label block only.
  component Tile: Item {
    id: tile
    required property var row
    property bool picked: false
    signal chosen()
    signal opened()
    signal menuAt(real x, real y)
    height: bt.s(44)

    Image {
      id: tileIcon
      x: bt.s(6)
      anchors.verticalCenter: parent.verticalCenter
      width: bt.s(32)
      height: bt.s(32)
      source: bt.icon(300, 32)
      mipmap: true
      opacity: tile.row.section === "discovered" && !tile.picked ? 0.75 : 1
    }
    Rectangle {
      x: label.x - bt.s(2)
      y: label.y - bt.s(1)
      width: Math.max(name.implicitWidth, status.implicitWidth) + bt.s(4)
      height: label.height + bt.s(2)
      visible: tile.picked
      color: VistaScheme.sc.highlight
    }
    Column {
      id: label
      x: tileIcon.x + tileIcon.width + bt.s(6)
      anchors.verticalCenter: parent.verticalCenter
      width: parent.width - x - bt.s(4)
      Text {
        id: name
        width: parent.width
        elide: Text.ElideRight
        textFormat: Text.PlainText
        text: bt.host.deviceLabel(tile.row.dev) || "Device"
        color: tile.picked ? VistaScheme.sc.highlightText : "#000000"
        font.family: "Segoe UI"
        font.pixelSize: Style.font.bodySmall
      }
      Text {
        id: status
        width: parent.width
        elide: Text.ElideRight
        textFormat: Text.PlainText
        text: bt.statusText(tile.row)
        color: tile.picked ? VistaScheme.sc.highlightText : "#6D6D6D"
        font.family: "Segoe UI"
        font.pixelSize: Style.font.bodySmall
      }
    }
    MouseArea {
      id: tileMouse
      anchors.fill: parent
      hoverEnabled: true
      acceptedButtons: Qt.LeftButton | Qt.RightButton
      onPressed: function(mouse) {
        tile.chosen()
        if (mouse.button === Qt.RightButton) tile.menuAt(mouse.x, mouse.y)
      }
      onDoubleClicked: function(mouse) { if (mouse.button === Qt.LeftButton) tile.opened() }
    }
    // Stock's row tooltip ("Pair" / "Connect" / "Disconnect").
    VistaToolTip {
      visible: tileMouse.containsMouse && !bt.host.vistaMenuOpen
      x: label.x
      y: parent.height
      z: 20
      text: "Double-click to " + (tile.row.dev.connected ? "disconnect" : tile.row.section === "discovered" ? "pair" : "connect")
    }
  }

  // A white list box (SysListView32's client edge) holding a ListView.
  component ListBox: Rectangle {
    color: "#FFFFFF"
    border.width: 1
    border.color: VistaScheme.sc.edit
    clip: true
  }

  // ---- Bluetooth Devices ---------------------------------------------------
  VistaPropertySheet {
    id: sheet
    title: "Bluetooth Devices"
    titleIcon: bt.icon(300, 16)
    buttons: ["help", "close"]
    disabledButtons: ["help"]
    active: !bt.host.vistaAddOpen && !bt.host.vistaPropsOpen
    onCloseClicked: bt.host.close()
    titles: ["Devices", "Options", "COM Ports", "Hardware"]
    tab: bt.host.vistaTab
    onTabClicked: function(i) { bt.host.vistaTab = i }
    pageWidth: bt.du(227)
    pageHeight: bt.dv(215)
    buttonLabels: ["OK", "Cancel", "<u>A</u>pply"]
    disabledButtonIndices: [2]
    onButtonClicked: bt.host.close()

    // -- Devices (107) --
    Item {
      parent: sheet.page
      anchors.fill: parent
      visible: bt.host.vistaTab === 0

      ListBox {
        id: devBox
        x: bt.du(7); y: bt.dv(7); width: bt.du(213); height: bt.dv(183)

        VistaLabel {
          anchors.centerIn: parent
          width: parent.width - bt.s(24)
          horizontalAlignment: Text.AlignHCenter
          wrapMode: Text.WordWrap
          visible: bt.rows.length === 0
          color: "#6D6D6D"
          text: !bt.adapter ? "No Bluetooth adapter"
              : !bt.radioOn ? "Turn Bluetooth on to scan"
              : "Scanning for devices..."
        }

        ListView {
          id: devList
          anchors.fill: parent
          anchors.margins: 1
          anchors.rightMargin: devScroll.needed ? devScroll.width + 1 : 1
          clip: true
          boundsBehavior: Flickable.StopAtBounds
          model: bt.rows.length
          currentIndex: bt.selectedRow ? bt.rows.indexOf(bt.selectedRow) : -1
          // Deferred: the rows are rebuilt on every discovery report (stock).
          onCurrentIndexChanged: if (currentIndex >= 0) Qt.callLater(function() { devList.positionViewAtIndex(devList.currentIndex, ListView.Contain) })
          delegate: Column {
            id: cell
            required property int index
            readonly property var row: bt.rows[index] || ({ dev: {}, section: "" })
            readonly property bool opensGroup: index === 0 || bt.rows[index - 1].section !== row.section
            width: devList.width

            // Group header: blue caption over a rule, as Vista's grouped views.
            Item {
              visible: cell.opensGroup
              width: parent.width
              height: visible ? bt.s(24) : 0
              Text {
                x: bt.s(6)
                y: bt.s(6)
                text: bt.groupTitle(cell.row.section)
                color: VistaScheme.sc.groupText
                font.family: "Segoe UI"
                font.bold: true
                font.pixelSize: Style.font.bodySmall
              }
              Rectangle {
                x: bt.s(6)
                anchors.bottom: parent.bottom
                anchors.bottomMargin: bt.s(2)
                width: parent.width - bt.s(12)
                height: 1
                gradient: Gradient {
                  orientation: Gradient.Horizontal
                  GradientStop { position: 0; color: VistaScheme.sc.groupText }
                  GradientStop { position: 1; color: "#FFFFFF" }
                }
              }
            }
            Tile {
              width: parent.width
              row: cell.row
              picked: bt.selectedRow === cell.row
              onChosen: bt.host.vistaSelect(cell.row.section, cell.row.indexInSection)
              onOpened: bt.activate(cell.row)
              onMenuAt: function(mx, my) {
                var p = mapToItem(bt, mx, my)
                ctxMenu.x = p.x
                ctxMenu.y = p.y
                ctxMenu.currentIndex = -1
                bt.host.vistaMenuOpen = true
              }
            }
          }
        }
        VistaScrollBar {
          id: devScroll
          target: devList
          anchors.right: parent.right
          anchors.top: parent.top
          anchors.bottom: parent.bottom
          anchors.margins: 1
        }
      }

      VistaButton {
        x: bt.du(7); y: bt.dv(194); width: bt.du(50); height: bt.dv(14)
        text: "A<u>d</u>d..."
        enabled: bt.radioOn
        onClicked: bt.host.vistaAddOpen = true
      }
      VistaButton {
        x: bt.du(61); y: bt.dv(194); width: bt.du(50); height: bt.dv(14)
        text: "<u>R</u>emove"
        enabled: bt.canForget(bt.selectedRow) && bt.host.pendingAction(bt.selectedRow.dev.address) === ""
        onClicked: bt.forget(bt.selectedRow)
      }
      // No Vista original: stock's click-to-(dis)connect, in the template's gap.
      VistaButton {
        x: bt.du(115); y: bt.dv(194); width: bt.du(50); height: bt.dv(14)
        text: bt.selectedRow && bt.selectedRow.dev.connected ? "Dis<u>c</u>onnect" : "<u>C</u>onnect"
        enabled: !!bt.selectedRow && bt.host.pendingAction(bt.selectedRow.dev.address) === ""
        onClicked: bt.activate(bt.selectedRow)
      }
      VistaButton {
        x: bt.du(169); y: bt.dv(194); width: bt.du(50); height: bt.dv(14)
        text: "<u>P</u>roperties"
        enabled: !!bt.selectedRow
        onClicked: { bt.host.vistaPropsAddress = bt.selectedRow.dev.address; bt.host.vistaPropsOpen = true }
      }
    }

    // -- Options (135) --
    Item {
      parent: sheet.page
      anchors.fill: parent
      visible: bt.host.vistaTab === 1

      VistaGroupBox { x: bt.du(7); y: bt.dv(7); width: bt.du(213); height: bt.dv(68); caption: "Discovery" }
      VistaLabel {
        x: bt.du(15); y: bt.dv(17); width: bt.du(195)
        wrapMode: Text.WordWrap
        text: "To allow Bluetooth devices to find this computer, select the following check box."
      }
      // Stock never changes discoverability: shown, read-only.
      VistaCheckBox {
        x: bt.du(15); y: bt.dv(37); width: bt.du(190); height: bt.dv(10)
        text: "<u>T</u>urn discovery on"
        enabled: false
        checked: !!bt.adapter && bt.adapter.discoverable === true
      }
      Image {
        x: bt.du(9); y: bt.dv(54)
        width: bt.s(32); height: bt.s(32)
        source: bt.icon(101, 32)
      }
      VistaLabel {
        x: bt.du(33); y: bt.dv(54); width: bt.du(180)
        wrapMode: Text.WordWrap
        text: "To protect your privacy, turn on discovery only when you want a Bluetooth device to find this computer."
      }

      VistaGroupBox { x: bt.du(7); y: bt.dv(78); width: bt.du(213); height: bt.dv(58); caption: "Connections" }
      VistaLabel {
        x: bt.du(15); y: bt.dv(89); width: bt.du(171)
        wrapMode: Text.WordWrap
        text: "Use these settings to control whether a Bluetooth device can connect to this computer."
      }
      VistaCheckBox {
        x: bt.du(15); y: bt.dv(109); width: bt.du(190); height: bt.dv(10)
        text: "Allow Bluetooth devices to <u>c</u>onnect to this computer"
        enabled: false
        checked: !!bt.adapter && bt.adapter.pairable === true
      }
      VistaCheckBox {
        x: bt.du(15); y: bt.dv(121); width: bt.du(190); height: bt.dv(10)
        text: "Alert me when a new Bluetooth device <u>w</u>ants to connect"
        enabled: false
      }
      VistaCheckBox {
        x: bt.du(7); y: bt.dv(140); width: bt.du(213); height: bt.dv(10)
        text: "Show the Bluetooth icon in the <u>n</u>otification area"
        enabled: false
        checked: true
      }
      // Stock's power switch: omarchy-bluetooth-power (rfkill), b, and the
      // tray icon's right-click. The keyboard's "header" stop lands here.
      VistaCheckBox {
        id: radioBox
        x: bt.du(7); y: bt.dv(152); width: bt.du(213); height: bt.dv(10)
        text: "Turn off the <u>B</u>luetooth radio"
        enabled: !!bt.adapter
        checked: !!bt.adapter && !bt.radioOn
        focused: bt.host.headerHasCursor
        onToggled: bt.host.toggleBluetooth()
        HoverHandler { id: radioHover }
        VistaToolTip {
          visible: radioHover.hovered
          y: parent.height + bt.s(4)
          z: 20
          text: bt.host.toggleHint
        }
      }
      VistaButton {
        x: bt.du(150); y: bt.dv(196); width: bt.du(65); height: bt.dv(14)
        text: "<u>R</u>estore Defaults"
        enabled: false
      }
    }

    // -- COM Ports (132) --
    Item {
      parent: sheet.page
      anchors.fill: parent
      visible: bt.host.vistaTab === 2

      VistaLabel {
        x: bt.du(7); y: bt.dv(7); width: bt.du(213)
        wrapMode: Text.WordWrap
        text: "This computer is using the COM (serial) ports listed below. To determine whether you need a COM port, read the documentation that came with your Bluetooth device."
      }
      VistaListView {
        x: bt.du(7); y: bt.dv(39); width: bt.du(213); height: bt.dv(139)
        columns: [{ title: "Port", width: 60 }, { title: "Direction", width: 80 }, { title: "Name" }]
        rows: []
      }
      VistaButton { x: bt.du(114); y: bt.dv(180); width: bt.du(50); height: bt.dv(14); text: "A<u>d</u>d..."; enabled: false }
      VistaButton { x: bt.du(169); y: bt.dv(180); width: bt.du(50); height: bt.dv(14); text: "<u>R</u>emove"; enabled: false }
    }

    // -- Hardware (Device Manager's page) --
    Item {
      parent: sheet.page
      anchors.fill: parent
      visible: bt.host.vistaTab === 3

      VistaLabel { x: bt.du(7); y: bt.dv(7); text: "Devices:" }
      VistaListView {
        x: bt.du(7); y: bt.dv(18); width: bt.du(213); height: bt.dv(70)
        columns: [{ title: "Name", width: 200 }, { title: "Type" }]
        rows: bt.adapter ? [[bt.adapter.name || "Bluetooth Radio", "Bluetooth Radios"]] : []
        currentIndex: bt.adapter ? 0 : -1
      }
      VistaGroupBox { x: bt.du(7); y: bt.dv(95); width: bt.du(213); height: bt.dv(92); caption: "Device Properties" }
      Image {
        x: bt.du(15); y: bt.dv(107)
        width: bt.s(32); height: bt.s(32)
        source: bt.icon(2026, 32)
        visible: !!bt.adapter
      }
      VistaLabel { x: bt.du(45); y: bt.dv(107); text: "Manufacturer:" }
      VistaLabel { x: bt.du(105); y: bt.dv(107); text: "Unavailable"; enabled: false }
      VistaLabel { x: bt.du(45); y: bt.dv(119); text: "Location:" }
      VistaLabel { x: bt.du(105); y: bt.dv(119); text: bt.adapter ? (bt.adapter.adapterId || "--") : "--" }
      VistaLabel { x: bt.du(45); y: bt.dv(131); text: "Device status:" }
      // Stock's hero status: "No adapter", "Turned Off", or the rotating
      // phrase (stock's swap animation fades it through phraseOpacity).
      VistaLabel {
        x: bt.du(105); y: bt.dv(131); width: bt.du(108)
        wrapMode: Text.WordWrap
        textFormat: Text.PlainText
        opacity: bt.host.phraseOpacity
        text: bt.radioOn ? "This device is working properly. " + bt.host.heroStatusText + "..." : bt.host.heroStatusText + "."
      }
      VistaButton { x: bt.du(105); y: bt.dv(166); width: bt.du(50); height: bt.dv(14); text: "<u>T</u>roubleshoot..."; enabled: false }
      VistaButton { x: bt.du(162); y: bt.dv(166); width: bt.du(50); height: bt.dv(14); text: "P<u>r</u>operties"; enabled: false }
    }
  }

  // ---- the device context menu ----------------------------------------------
  MouseArea {
    anchors.fill: parent
    visible: bt.host.vistaMenuOpen
    z: 40
    acceptedButtons: Qt.LeftButton | Qt.RightButton
    onPressed: bt.host.vistaMenuOpen = false
  }
  VistaMenu {
    id: ctxMenu
    visible: bt.host.vistaMenuOpen
    z: 41
    width: implicitWidth
    height: implicitHeight
    items: [
      { text: bt.selectedRow && bt.selectedRow.dev.connected ? "Disconnect" : bt.selectedRow && bt.selectedRow.section === "discovered" ? "Pair" : "Connect", bold: true,
        enabled: !!bt.selectedRow && bt.host.pendingAction(bt.selectedRow.dev.address) === "" },
      { text: "Remove", enabled: bt.canForget(bt.selectedRow) },
      { separator: true },
      { text: "Properties", enabled: !!bt.selectedRow }
    ]
    onTriggered: function(i) { bt.menuTrigger(i) }
  }

  // ---- modal shade for the dialogs below ------------------------------------
  MouseArea {
    anchors.fill: parent
    visible: bt.host.vistaAddOpen || bt.host.vistaPropsOpen
    z: 30
  }

  // ---- Select Bluetooth Device (136): Add... --------------------------------
  // Lists what stock's open-panel scan has found; OK pairs, as stock's click
  // on an available device does.
  VistaWindow {
    id: addWin
    visible: bt.host.vistaAddOpen
    z: 31
    width: bt.du(325) + 2 * frameWidth
    height: captionHeight + bt.dv(195) + frameWidth
    x: Math.max(bt.host.vistaMinX, bt.width - width)
    y: Math.max(0, (bt.height - height) / 2)
    title: "Select Bluetooth Device"
    titleIcon: bt.icon(300, 16)
    buttons: ["close"]
    onCloseClicked: bt.host.vistaAddOpen = false

    readonly property var picked: bt.selectedRow && bt.selectedRow.section === "discovered" ? bt.selectedRow : null

    VistaLabel { x: bt.du(7); y: bt.dv(10); text: "Device <u>T</u>ype:" }
    VistaComboBox {
      x: bt.du(70); y: bt.dv(7); width: bt.du(192)
      model: ["All Devices"]
      currentIndex: 0
      enabled: false
    }
    VistaProgress {
      x: bt.du(268); y: bt.dv(7); width: bt.du(50); height: bt.dv(14)
      visible: !!bt.adapter && bt.adapter.discovering === true
      // Paced by stock's phrase timer: no timer of its own.
      value: ((bt.host.phraseIndex % 8) + 1) / 8
    }
    ListBox {
      x: bt.du(7); y: bt.dv(25); width: bt.du(311); height: bt.dv(110)
      VistaLabel {
        anchors.centerIn: parent
        visible: bt.foundRows.length === 0
        color: "#6D6D6D"
        textFormat: Text.PlainText
        text: !bt.radioOn ? "Turn Bluetooth on to scan"
            : bt.adapter.discovering ? "Searching for Bluetooth devices... " + bt.host.heroStatusText + "..."
            : "No Bluetooth devices were found."
      }
      ListView {
        id: foundList
        anchors.fill: parent
        anchors.margins: 1
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        model: bt.foundRows.length
        delegate: Tile {
          required property int index
          width: foundList.width
          row: bt.foundRows[index] || ({ dev: {}, section: "" })
          picked: bt.selectedRow === row
          onChosen: bt.host.vistaSelect("discovered", row.indexInSection)
          onOpened: { bt.activate(row); bt.host.vistaAddOpen = false }
        }
      }
    }
    Image {
      x: bt.du(7); y: bt.dv(143)
      width: bt.s(16); height: bt.s(16)
      source: bt.icon(144, 16)
    }
    VistaLabel {
      x: bt.du(22); y: bt.dv(143); width: bt.du(296)
      wrapMode: Text.WordWrap
      text: "If you don't see the device that you want to add, make sure that it is turned on. Follow the setup instructions that came with the device, and then click Search Again."
    }
    VistaButton {
      x: bt.du(7); y: bt.dv(174); width: bt.du(60); height: bt.dv(14)
      text: "<u>S</u>earch Again"
      enabled: bt.radioOn && !bt.adapter.discovering
      onClicked: bt.host.vistaSearchAgain()
    }
    VistaButton {
      x: bt.du(214); y: bt.dv(174); width: bt.du(50); height: bt.dv(14)
      text: "OK"
      isDefault: true
      enabled: !!addWin.picked && bt.host.pendingAction(addWin.picked.dev.address) === ""
      onClicked: { bt.activate(addWin.picked); bt.host.vistaAddOpen = false }
    }
    VistaButton {
      x: bt.du(268); y: bt.dv(174); width: bt.du(50); height: bt.dv(14)
      text: "Cancel"
      onClicked: bt.host.vistaAddOpen = false
    }
  }

  // ---- <device> Properties > General (138) ----------------------------------
  VistaPropertySheet {
    id: propsWin
    visible: bt.host.vistaPropsOpen && !!bt.propsRow
    z: 31
    x: (bt.width - width) / 2 + bt.s(12)
    y: Math.max(0, (bt.height - height) / 2)
    readonly property var dev: bt.propsRow ? bt.propsRow.dev : ({})
    title: (bt.host.deviceLabel(dev) || "Device") + " Properties"
    titleIcon: bt.icon(300, 16)
    buttons: ["help", "close"]
    disabledButtons: ["help"]
    onCloseClicked: bt.host.vistaPropsOpen = false
    titles: ["General"]
    tab: 0
    pageWidth: bt.du(227)
    pageHeight: bt.dv(215)
    buttonLabels: ["OK", "Cancel", "<u>A</u>pply"]
    disabledButtonIndices: [2]
    onButtonClicked: bt.host.vistaPropsOpen = false

    Item {
      parent: propsWin.page
      anchors.fill: parent

      Image {
        x: bt.du(22); y: bt.dv(7)
        width: bt.s(32); height: bt.s(32)
        source: bt.icon(300, 32)
      }
      // Renaming is not a stock feature: read-only.
      VistaTextField {
        x: bt.du(70); y: bt.dv(7); width: bt.du(150); height: bt.dv(14)
        readOnly: true
        interactive: false
        text: bt.host.deviceLabel(propsWin.dev)
      }
      VistaLabel { x: bt.du(7); y: bt.dv(32) + bt.s(4); text: "Type of device:" }
      VistaLabel { x: bt.du(70) + bt.s(3); y: bt.dv(32) + bt.s(4); text: bt.host.vistaTypeOf(propsWin.dev.address) }
      VistaLabel { x: bt.du(7); y: bt.dv(47) + bt.s(4); text: "Address:" }
      VistaLabel { x: bt.du(70) + bt.s(3); y: bt.dv(47) + bt.s(4); text: String(propsWin.dev.address || "").toLowerCase() }
      VistaLabel { x: bt.du(7); y: bt.dv(61) + bt.s(4); text: "Connection:" }
      VistaLabel {
        x: bt.du(70) + bt.s(3); y: bt.dv(61) + bt.s(4)
        text: bt.propsRow ? bt.statusText(bt.propsRow) : ""
      }
      // No Vista original: stock's battery readout, where Vista had "Last connected".
      VistaLabel {
        visible: propsWin.dev.batteryAvailable === true
        x: bt.du(7); y: bt.dv(75) + bt.s(4)
        text: "Battery:"
      }
      VistaLabel {
        visible: propsWin.dev.batteryAvailable === true
        x: bt.du(70) + bt.s(3); y: bt.dv(75) + bt.s(4)
        text: Math.round((propsWin.dev.battery || 0) * 100) + "%"
      }
    }
  }
}
