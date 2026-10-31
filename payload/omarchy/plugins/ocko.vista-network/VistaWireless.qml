import QtQuick
import qs.Commons
import "../../vista/qml"

// Vista's "Connect to a network" window (VAN.dll) and its network-key
// dialog, over the stock network panel's
// Wi-Fi model. `host` is the panel (ocko.vista-network Panel.qml) or, for the
// screenshot harness, a mock with the same members; nothing here touches
// Quickshell.Networking directly, so the mock never needs a real radio.
//
// host reads:  wifiNetworks (stock primitive rows: ssid, signal, known,
//   connected, security), selectedIndex, busy, actionKind, actionSsid,
//   failureSsid, failureReason, passwordSsid, scanning, vistaWifiOn,
//   canToggleWifi, canShareWifi, canSelectBand, bandEffective, bandAvailable
// host calls: activateSelected, forget, canForgetNetwork, vistaIsEnterprise,
//   vistaSecurityLabel, refresh, toggleNetwork, summonWifiQr, setBand,
//   toggleBandAuto, bandLabel, connectWithPassphrase, connectEnterprise,
//   cancelPasswordPrompt, vistaOpenAdvanced
Item {
  id: wl

  required property var host
  signal closeRequested()

  readonly property var nets: host.wifiNetworks || []
  readonly property var selected: host.selectedIndex >= 0 && host.selectedIndex < nets.length ? nets[host.selectedIndex] : null
  readonly property var keyNet: {
    if (!host.passwordSsid) return null
    for (var i = 0; i < nets.length; i++) if (nets[i].ssid === host.passwordSsid) return nets[i]
    return { ssid: host.passwordSsid, security: -1 }
  }
  readonly property bool keyEnterprise: !!keyNet && host.vistaIsEnterprise(keyNet.security)
  // The key fields, for the owner's key handler (it must stand aside while
  // one of them has focus, or h/j/k/l/x never reach the field).
  readonly property bool typing: keyA.input.activeFocus || keyB.input.activeFocus

  function s(n) { return Style.space(n) }

  function rowStatus(net) {
    if (host.busy && host.actionSsid === net.ssid)
      return host.actionKind === "connect" ? "Connecting..." : host.actionKind === "disconnect" ? "Disconnecting..." : "Forgetting..."
    if (net.connected) return "Connected"
    if (net.known) return "Automatic"
    return ""
  }

  function submitKey() {
    if (!keyNet) return
    if (keyEnterprise) host.connectEnterprise(keyNet.ssid, keyA.text, keyB.text)
    else if (keyA.text !== "" && keyA.text === keyB.text) host.connectWithPassphrase(keyNet.ssid, keyA.text)
  }

  function handleKey(e) {
    if (e.key === Qt.Key_Escape) { host.cancelPasswordPrompt(); e.accepted = true }
    else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) { submitKey(); e.accepted = true }
    else if (e.key === Qt.Key_Tab) { (keyA.input.activeFocus ? keyB : keyA).input.forceActiveFocus(); e.accepted = true }
  }

  // Five rising bars, lit by signal in 20 % steps (Vista's signal meter).
  component SignalBars: Row {
    id: bars
    property int strength: 0
    spacing: 1
    Repeater {
      model: 5
      Rectangle {
        required property int index
        anchors.bottom: parent.bottom
        width: wl.s(3)
        height: wl.s(4 + index * 3)
        color: bars.strength > index * 20 ? "#2CC12C" : "#FFFFFF"
        border.width: 1
        border.color: bars.strength > index * 20 ? "#1C8A1C" : "#ACA899"
      }
    }
  }

  // VAN.dll's "Connect to a network" (DIALOG 7111, Segoe UI 9 pt: 1 DLU =
  // 1.75 x 1.875 px) in its wizard frame: the white page with the main
  // instruction, the Show filter and Refresh, the network list, the three
  // links, and the grey button bar (Connect, Cancel). Stock's extra Wi-Fi
  // actions (radio, forget, QR code, band) have no slot in VAN; they sit in a
  // small link row under the list.
  function vu(x) { return Style.space(Math.round(x * 1.75)) }
  function vv(y) { return Style.space(Math.round(y * 1.875)) }
  function barsIcon(sig) {
    var n = Math.max(1, Math.min(6, Math.ceil((sig || 0) / 100 * 6)))
    return VistaScheme.graphics + "/pnidui/32/" + (3020 + n) + ".png"
  }

  VistaWindow {
    id: frame
    anchors.fill: parent
    nested: true
    title: "Connect to a network"
    titleIcon: VistaScheme.graphics + "/pnidui/16/3026.png"
    buttons: ["close"]
    active: !wl.keyNet
    onCloseClicked: wl.closeRequested()
    face: "#FFFFFF"

    Text {
      id: heading
      x: wl.s(20); y: wl.s(14)
      text: "Select a network to connect to"
      color: "#003399"
      font.family: "Segoe UI"
      font.pixelSize: wl.s(16)
    }

    Item {
      id: page
      x: wl.s(20); y: heading.y + heading.height + wl.s(14)
      width: parent.width - wl.s(40)
      height: wl.vv(143)

      VistaLabel { x: 0; y: wl.vv(2); text: "Show" }
      VistaComboBox {
        x: wl.vu(40) - wl.vu(20); y: 0; z: 5
        width: wl.vu(110)
        model: ["All", "Wireless"]
        currentIndex: 0
        onActivated: function(i) { open = false }
      }
      Rectangle {
        anchors.right: parent.right; y: 0
        width: wl.vu(20); height: wl.s(23)
        radius: wl.s(2)
        color: refMouse.containsMouse ? "#E5F3FB" : "transparent"
        border.color: refMouse.containsMouse ? "#70C0E7" : "transparent"
        Text { anchors.centerIn: parent; text: "↻"; color: "#1E5EB0"; font.pixelSize: wl.s(15) }
        MouseArea { id: refMouse; anchors.fill: parent; hoverEnabled: true; enabled: wl.host.vistaWifiOn; onClicked: wl.host.refresh(true) }
      }

      Rectangle {
        id: list
        y: wl.vv(14)
        width: parent.width
        height: wl.vv(104)
        color: "#FFFFFF"
        border.width: 1
        border.color: "#828790"
        clip: true

        VistaLabel {
          anchors.centerIn: parent
          visible: wl.nets.length === 0
          text: !wl.host.vistaWifiOn ? "Wireless networking is turned off."
                : wl.host.scanning ? "Searching for networks..."
                : "Windows cannot find any networks"
        }

        ListView {
          id: rows
          anchors.fill: parent
          anchors.margins: 2
          clip: true
          boundsBehavior: Flickable.StopAtBounds
          model: wl.nets.length
          currentIndex: wl.host.selectedIndex
          onCurrentIndexChanged: if (currentIndex >= 0) positionViewAtIndex(currentIndex, ListView.Contain)
          delegate: Item {
            id: row
            required property int index
            readonly property var net: wl.nets[index] || ({})
            readonly property bool sel: index === wl.host.selectedIndex
            readonly property bool failed: wl.host.failureReason !== "" && wl.host.failureSsid === net.ssid
            width: rows.width
            height: wl.s(42)

            Rectangle {
              anchors.fill: parent
              anchors.margins: 1
              visible: row.sel || rowMouse.containsMouse
              radius: wl.s(2)
              border.color: row.sel ? "#7DA2CE" : "#B8D6FB"
              gradient: Gradient {
                GradientStop { position: 0; color: row.sel ? "#DCEBFC" : "#FAFBFD" }
                GradientStop { position: 1; color: row.sel ? "#C1DBFC" : "#EBF3FD" }
              }
            }
            Image {
              x: wl.s(6); anchors.verticalCenter: parent.verticalCenter
              width: wl.s(32); height: wl.s(32)
              source: wl.barsIcon(row.net.signal)
              mipmap: true
            }
            Text {
              id: ssid
              x: wl.s(46); y: wl.s(5)
              width: parent.width - x - status.width - wl.s(16)
              elide: Text.ElideRight
              text: row.net.ssid || "(hidden network)"
              color: "#000000"
              font.family: "Segoe UI"
              font.pixelSize: wl.s(12)
            }
            Text {
              id: status
              anchors.right: parent.right; anchors.rightMargin: wl.s(10)
              y: ssid.y
              text: row.net.connected ? "Connected" : wl.rowStatus(row.net)
              color: "#000000"
              font.family: "Segoe UI"
              font.pixelSize: wl.s(12)
            }
            Text {
              x: ssid.x
              y: ssid.y + ssid.height + wl.s(1)
              width: parent.width - x - wl.s(16)
              elide: Text.ElideRight
              text: row.failed ? wl.host.failureReason : wl.host.vistaSecurityLabel(row.net.security).replace(" wireless", "")
              color: row.failed ? "#CC0000" : "#575757"
              font.family: "Segoe UI"
              font.pixelSize: wl.s(12)
            }
            MouseArea {
              id: rowMouse
              anchors.fill: parent
              hoverEnabled: true
              onClicked: wl.host.selectedIndex = row.index
              onDoubleClicked: { wl.host.selectedIndex = row.index; wl.host.activateSelected() }
            }
          }
        }
      }

      component Link: Text {
        id: lk
        signal activated()
        color: enabled ? "#0066CC" : "#6D6D6D"
        font.family: "Segoe UI"
        font.pixelSize: wl.s(12)
        font.underline: lkMouse.containsMouse
        MouseArea { id: lkMouse; anchors.fill: parent; hoverEnabled: true; enabled: lk.enabled; cursorShape: Qt.PointingHandCursor; onClicked: lk.activated() }
      }

      // Stock's extras, under the list on the right.
      Row {
        anchors.right: parent.right
        y: wl.vv(118)
        spacing: wl.s(12)
        Link {
          visible: wl.host.canToggleWifi
          text: wl.host.vistaWifiOn ? "Turn off wireless" : "Turn on wireless"
          onActivated: wl.host.toggleNetwork()
        }
        Link {
          text: "Forget"
          enabled: !!wl.selected && wl.host.canForgetNetwork(wl.selected) && !wl.host.busy
          onActivated: wl.host.forget(wl.selected)
        }
        Link {
          visible: wl.host.canShareWifi
          text: "QR code"
          onActivated: wl.host.summonWifiQr()
        }
        Repeater {
          model: wl.host.canSelectBand ? ["auto"].concat(wl.host.bandAvailable || []) : []
          Link {
            required property var modelData
            readonly property bool current: wl.host.bandEffective === modelData
            text: modelData === "auto" ? "Auto band" : wl.host.bandLabel(modelData)
            font.bold: current
            enabled: !current
            onActivated: modelData === "auto" ? wl.host.toggleBandAuto() : wl.host.setBand(modelData)
          }
        }
      }

      Column {
        y: wl.vv(118)
        spacing: wl.vv(0.5)
        Link { text: "Diagnose connection problems"; onActivated: wl.host.refresh(true) }
        Link { text: "Set up a connection or network"; enabled: false }
        Link { text: "Open Network and Sharing Center"; onActivated: wl.host.vistaOpenAdvanced() }
      }
    }

    // The wizard's button bar.
    Rectangle {
      anchors.bottom: parent.bottom
      width: parent.width
      height: wl.s(46)
      color: "#F0F0F0"
      Rectangle { width: parent.width; height: 1; color: "#DFDFDF" }
      Row {
        anchors.right: parent.right; anchors.rightMargin: wl.s(12)
        anchors.verticalCenter: parent.verticalCenter
        spacing: wl.s(8)
        VistaButton {
          text: wl.selected && wl.selected.connected ? "<u>D</u>isconnect" : "C<u>o</u>nnect"
          isDefault: true
          enabled: !!wl.selected && !wl.host.busy
          onClicked: wl.host.activateSelected()
        }
        VistaButton { text: "Cancel"; onClicked: wl.closeRequested() }
      }
    }
  }

  // ---- the network-key dialog, over the window ---------------------------
  MouseArea {
    anchors.fill: parent
    visible: !!wl.keyNet
    z: 10
  }
  VistaWindow {
    id: keyWin
    nested: true
    visible: !!wl.keyNet
    z: 11
    width: wl.s(392)
    height: wl.s(29 + 3) + wl.s(wl.keyEnterprise ? 190 : 222)
    x: (parent.width - width) / 2
    y: (parent.height - height) / 2
    title: "Wireless Network Connection"
    buttons: ["close"]
    onCloseClicked: wl.host.cancelPasswordPrompt()
    onVisibleChanged: {
      keyA.text = ""
      keyB.text = ""
      if (visible) Qt.callLater(function() { keyA.input.forceActiveFocus() })
    }

    VistaLabel {
      id: keyText
      x: wl.s(12)
      y: wl.s(12)
      width: parent.width - 2 * x
      wrapMode: Text.WordWrap
      textFormat: Text.PlainText
      text: wl.keyEnterprise
        ? "The network '" + (wl.keyNet ? wl.keyNet.ssid : "") + "' requires a user name and password (802.1X). Type them, and then click Connect."
        : "The network '" + (wl.keyNet ? wl.keyNet.ssid : "") + "' requires a network key (also called a WEP key or WPA key). A network key helps prevent unknown intruders from connecting to this network.\n\nType the key, and then click Connect."
    }
    Grid {
      x: keyText.x
      y: keyText.y + keyText.height + wl.s(14)
      columns: 2
      columnSpacing: wl.s(8)
      rowSpacing: wl.s(8)
      verticalItemAlignment: Grid.AlignVCenter
      VistaLabel { width: wl.s(118); text: wl.keyEnterprise ? "<u>U</u>ser name:" : "Net<u>w</u>ork key:" }
      VistaTextField {
        id: keyA
        width: wl.s(236)
        height: wl.s(21)
        echoMode: wl.keyEnterprise ? TextInput.Normal : TextInput.Password
        input.Keys.onPressed: function(e) { wl.handleKey(e) }
      }
      VistaLabel { width: wl.s(118); text: wl.keyEnterprise ? "<u>P</u>assword:" : "Con<u>f</u>irm network key:" }
      VistaTextField {
        id: keyB
        width: wl.s(236)
        height: wl.s(21)
        echoMode: TextInput.Password
        input.Keys.onPressed: function(e) { wl.handleKey(e) }
      }
    }
    VistaLabel {
      x: keyText.x
      y: parent.height - wl.s(12 + 23) + wl.s(4)
      visible: !wl.keyEnterprise && keyB.text !== "" && keyA.text !== keyB.text
      text: "The keys do not match."
    }
    VistaButton {
      x: parent.width - wl.s(12 + 75 + 6 + 75)
      y: parent.height - wl.s(12 + 23)
      text: "Co<u>n</u>nect"
      isDefault: true
      enabled: wl.keyEnterprise ? keyA.text !== "" && keyB.text !== "" : keyA.text !== "" && keyA.text === keyB.text
      onClicked: wl.submitKey()
    }
    VistaButton {
      x: parent.width - wl.s(12 + 75)
      y: parent.height - wl.s(12 + 23)
      text: "Cancel"
      onClicked: wl.host.cancelPasswordPrompt()
    }
  }
}
