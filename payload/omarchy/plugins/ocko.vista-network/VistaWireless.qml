import QtQuick
import qs.Commons
import "../../vista/qml"

// Vista SP2's "Wireless Network Connection" window ("Choose a wireless
// network") and its network-key dialog, over the stock network panel's
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

  VistaWindow {
    id: frame
    anchors.fill: parent
    title: "Wireless Network Connection"
    titleIcon: VistaScheme.graphics + "/netshell/16/1913.png"
    buttons: ["min", "max", "close"]
    disabledButtons: ["max"]
    active: !wl.keyNet
    onMinimizeClicked: wl.closeRequested()
    onCloseClicked: wl.closeRequested()

    // ---- left: the Explorer task pane ------------------------------------
    Rectangle {
      id: pane
      width: wl.s(214)
      height: parent.height
      gradient: Gradient {
        GradientStop { position: 0; color: VistaScheme.sc.paneTop }
        GradientStop { position: 1; color: VistaScheme.sc.paneBottom }
      }
      Column {
        x: wl.s(12)
        y: wl.s(12)
        width: parent.width - wl.s(24)
        spacing: wl.s(12)

        VistaPaneGroup {
          title: "Network Tasks"
          VistaPaneLink {
            text: "Refresh network list"
            enabled: wl.host.vistaWifiOn
            onActivated: wl.host.refresh(true)
          }
          VistaPaneLink {
            visible: wl.host.canToggleWifi
            text: wl.host.vistaWifiOn ? "Turn off wireless" : "Turn on wireless"
            onActivated: wl.host.toggleNetwork()
          }
          VistaPaneLink {
            text: "Forget this network"
            enabled: !!wl.selected && wl.host.canForgetNetwork(wl.selected) && !wl.host.busy
            onActivated: wl.host.forget(wl.selected)
          }
          VistaPaneLink {
            visible: wl.host.canShareWifi
            text: "Show key as QR code"
            onActivated: wl.host.summonWifiQr()
          }
          // Band: one link per choice; the one in force reads "Using ...".
          Repeater {
            model: wl.host.canSelectBand ? ["auto"].concat(wl.host.bandAvailable || []) : []
            VistaPaneLink {
              required property var modelData
              readonly property bool current: wl.host.bandEffective === modelData
              readonly property string name: modelData === "auto" ? "automatic band" : wl.host.bandLabel(modelData) + " band"
              text: (current ? "Using " : "Use ") + name
              enabled: !current
              onActivated: modelData === "auto" ? wl.host.toggleBandAuto() : wl.host.setBand(modelData)
            }
          }
        }

        VistaPaneGroup {
          title: "Related Tasks"
          VistaPaneLink {
            text: "Change advanced settings"
            onActivated: wl.host.vistaOpenAdvanced()
          }
        }
      }
    }

    // ---- right: Choose a wireless network ---------------------------------
    Item {
      x: pane.width
      width: parent.width - pane.width
      height: parent.height

      Text {
        id: heading
        x: wl.s(14)
        y: wl.s(12)
        text: "Choose a wireless network"
        color: "#000000"
        font.family: "Segoe UI"
        font.bold: true
        font.pixelSize: Style.font.subtitle
      }
      VistaLabel {
        id: intro
        x: heading.x
        y: heading.y + heading.height + wl.s(6)
        width: parent.width - 2 * heading.x
        wrapMode: Text.WordWrap
        text: "Click an item in the list below to connect to a wireless network in range or to get more information."
      }

      Rectangle {
        id: list
        x: heading.x
        y: intro.y + intro.height + wl.s(10)
        width: parent.width - 2 * heading.x
        height: parent.height - y - wl.s(12 + 23 + 10)
        color: "#FFFFFF"
        border.width: 1
        border.color: VistaScheme.sc.edit
        clip: true

        VistaLabel {
          anchors.centerIn: parent
          visible: wl.nets.length === 0
          text: !wl.host.vistaWifiOn ? "Wireless networking is turned off."
                : wl.host.scanning ? "Scanning for wireless networks..."
                : "No wireless networks were found in range."
        }

        ListView {
          id: rows
          anchors.fill: parent
          anchors.margins: 1
          clip: true
          boundsBehavior: Flickable.StopAtBounds
          model: wl.nets.length
          currentIndex: wl.host.selectedIndex
          onCurrentIndexChanged: if (currentIndex >= 0) positionViewAtIndex(currentIndex, ListView.Contain)
          delegate: Rectangle {
            id: row
            required property int index
            readonly property var net: wl.nets[index] || ({})
            readonly property bool sel: index === wl.host.selectedIndex
            readonly property bool failed: wl.host.failureReason !== "" && wl.host.failureSsid === net.ssid
            readonly property color fg: sel ? VistaScheme.sc.highlightText : "#000000"
            width: rows.width
            height: wl.s(58)
            color: sel ? VistaScheme.sc.highlight : "#FFFFFF"

            Image {
              x: wl.s(8)
              y: wl.s(8)
              width: wl.s(32)
              height: wl.s(32)
              source: VistaScheme.graphics + "/netshell/32/1913.png"
              mipmap: true
            }
            Text {
              id: ssid
              x: wl.s(50)
              y: wl.s(7)
              width: parent.width - x - status.width - wl.s(16)
              elide: Text.ElideRight
              text: row.net.ssid || "(hidden network)"
              color: row.fg
              font.family: "Segoe UI"
              font.bold: true
              font.pixelSize: Style.font.bodySmall
            }
            Text {
              id: status
              anchors.right: parent.right
              anchors.rightMargin: wl.s(10)
              y: ssid.y
              text: wl.rowStatus(row.net) + (row.net.connected ? "  ★" : row.net.known ? "  ☆" : "")
              color: row.fg
              font.family: "Segoe UI"
              font.bold: row.net.connected === true
              font.pixelSize: Style.font.bodySmall
            }
            Text {
              x: ssid.x
              y: ssid.y + ssid.height + wl.s(4)
              width: parent.width - x - bars.width - wl.s(20)
              elide: Text.ElideRight
              text: row.failed ? wl.host.failureReason : wl.host.vistaSecurityLabel(row.net.security)
              color: row.fg
              font.family: "Segoe UI"
              font.pixelSize: Style.font.bodySmall
            }
            SignalBars {
              id: bars
              anchors.right: parent.right
              anchors.rightMargin: wl.s(12)
              anchors.bottom: parent.bottom
              anchors.bottomMargin: wl.s(10)
              strength: row.net.signal || 0
            }
            Rectangle {
              anchors.bottom: parent.bottom
              width: parent.width
              height: 1
              color: "#ECE9D8"
            }
            MouseArea {
              anchors.fill: parent
              onClicked: wl.host.selectedIndex = row.index
              onDoubleClicked: { wl.host.selectedIndex = row.index; wl.host.activateSelected() }
            }
          }
        }
      }

      VistaButton {
        anchors.right: list.right
        anchors.bottom: parent.bottom
        anchors.bottomMargin: wl.s(12)
        text: wl.selected && wl.selected.connected ? "<u>D</u>isconnect" : "<u>C</u>onnect"
        isDefault: true
        enabled: !!wl.selected && !wl.host.busy
        onClicked: wl.host.activateSelected()
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
