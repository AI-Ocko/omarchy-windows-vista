import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import "../../vista/qml"

// VistaPower: Vista's battery meter flyout for ocko.vista-power: the battery
// (batmeter.dll art, as in the notification area) with its status line,
// "Select a power plan:" with one radio button per power profile (stock
// applies a plan the moment it is picked, as Vista's flyout did), then the
// link area with "Adjust screen brightness" (the monitor flyout) and "More
// power options" (Omarchy's system menu). White Flyout window, #F0F0F0
// link area, FlyoutStyle text (Segoe UI 9 pt; links #0066CC).
// `host` is duck-typed (Panel.qml, or the harness's mock): discharging,
// profiles, activeProfile, vistaBatteryFrame, vistaTooltip,
// setProfile(), close().
Rectangle {
  id: flyout

  property var host
  property real statusOpacity: 1
  // Panel.qml's key handling asks after a combo box; the flyout has none.
  readonly property bool comboOpen: false
  function closeCombo() {}

  function s(n) { return Style.space(n) }

  // power-profiles-daemon's names as Vista's plans.
  function profileLabel(p) {
    var names = { "balanced": "Balanced", "power-saver": "Power saver", "performance": "High performance" }
    var t = String(p || "")
    return names[t] || (t.charAt(0).toUpperCase() + t.slice(1))
  }

  width: s(260)
  height: body.height + links.height + 2
  color: "#FFFFFF"
  border.color: "#7A7A7A"
  radius: s(3)

  Process { id: brightness; command: ["omarchy-shell", "shell", "toggle", "omarchy.monitor"] }
  Process { id: moreOptions; command: ["omarchy", "menu", "summon", "system"] }

  component Link: Text {
    id: link
    signal clicked()
    color: "#0066CC"
    font.family: "Segoe UI"
    font.pixelSize: flyout.s(12)
    font.underline: linkMouse.containsMouse
    MouseArea {
      id: linkMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: link.clicked()
    }
  }

  Column {
    id: body
    x: 1; y: 1
    width: parent.width - 2
    topPadding: flyout.s(14)
    bottomPadding: flyout.s(12)
    spacing: flyout.s(10)

    // The battery and its status.
    Row {
      x: flyout.s(14)
      spacing: flyout.s(10)
      Image {
        width: flyout.s(32); height: flyout.s(32)
        source: VistaScheme.graphics + "/taskbar/battery/" + flyout.host.vistaBatteryFrame + ".png"
        smooth: true; mipmap: true
      }
      Text {
        anchors.verticalCenter: parent.verticalCenter
        width: body.width - flyout.s(14 + 32 + 10 + 14)
        text: flyout.host.vistaTooltip !== "" ? flyout.host.vistaTooltip : "No battery is detected"
        wrapMode: Text.Wrap
        color: "#000000"
        font.family: "Segoe UI"
        font.pixelSize: flyout.s(12)
      }
    }

    Rectangle { x: flyout.s(14); width: body.width - flyout.s(28); height: 1; color: "#E3E3E3" }

    Text {
      x: flyout.s(14)
      text: "Select a power plan:"
      color: "#000000"
      font.family: "Segoe UI"
      font.pixelSize: flyout.s(12)
    }

    Column {
      x: flyout.s(22)
      spacing: flyout.s(6)
      Repeater {
        model: flyout.host.profiles
        Item {
          id: plan
          required property var modelData
          readonly property bool chosen: modelData === flyout.host.activeProfile
          width: planRow.width; height: planRow.height
          Row {
            id: planRow
            spacing: flyout.s(6)
            Image {
              anchors.verticalCenter: parent.verticalCenter
              width: flyout.s(13); height: flyout.s(13)
              source: VistaScheme.art("radio-" + (plan.chosen ? (planMouse.containsMouse ? 5 : 4) : (planMouse.containsMouse ? 1 : 0)))
            }
            Text {
              text: flyout.profileLabel(plan.modelData)
              color: "#000000"
              font.family: "Segoe UI"
              font.pixelSize: flyout.s(12)
            }
          }
          MouseArea {
            id: planMouse
            anchors.fill: parent
            hoverEnabled: true
            onClicked: flyout.host.setProfile(plan.modelData)
          }
        }
      }
    }
  }

  // Link area.
  Rectangle {
    id: links
    x: 1; y: body.height + 1
    width: parent.width - 2
    height: linkCol.height + flyout.s(24)
    color: "#F0F0F0"
    Rectangle { width: parent.width; height: 1; color: "#DCDCDC" }
    Column {
      id: linkCol
      anchors.centerIn: parent
      spacing: flyout.s(6)
      Link {
        anchors.horizontalCenter: parent.horizontalCenter
        text: "Adjust screen brightness"
        onClicked: { flyout.host.close(); brightness.running = true }
      }
      Link {
        anchors.horizontalCenter: parent.horizontalCenter
        text: "More power options"
        onClicked: { flyout.host.close(); moreOptions.running = true }
      }
    }
  }
}
