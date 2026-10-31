import QtQuick
import Quickshell
import qs.Commons
import "../../vista/qml"

// Quick Launch toolbar: 16 px icons in 22 px hot-tracked buttons beside the
// orb, in Vista's own order and with Vista's own icons (explorer.exe and
// imageres.dll groups, assets/graphics/<lib>/32): Show Desktop (explorer 100),
// Switch between windows (explorer 258, Flip 3D: here Hyprland's window
// cycle), Internet (explorer 260), Command Prompt (imageres 15).
Row {
  id: ql

  required property var bar          // the Vista Bar root
  required property string monitorName
  required property string artDir

  readonly property string g: "file://" + Quickshell.env("HOME") + "/.config/omarchy/vista/assets/graphics/"
  readonly property var items: [
    { tip: "Show Desktop", icon: g + "explorer/32/100.png", cmd: "" },
    { tip: "Switch between windows", icon: g + "explorer/32/258.png", cmd: "hyprctl dispatch 'hl.dsp.window.cycle_next()'" },
    { tip: "Launch Internet Browser", icon: g + "explorer/32/260.png", cmd: "omarchy-launch-browser" },
    { tip: "Command Prompt", icon: g + "imageres/32/15.png", cmd: "omarchy-launch-terminal" }
  ]

  spacing: 0

  Repeater {
    model: ql.items.length

    Item {
      id: btn
      required property int index
      readonly property var item: ql.items[index]
      readonly property bool tooltipHovered: mouse.containsMouse

      width: Style.space(23)
      height: ql.height

      VistaArt {
        anchors.centerIn: parent
        width: Style.space(22)
        height: Style.space(22)
        visible: mouse.containsMouse
        source: ql.artDir + "/ql-" + (mouse.pressed ? 2 : 1) + ".png"
        margins: [6, 6, 15, 13]
      }

      Image {
        anchors.centerIn: parent
        anchors.verticalCenterOffset: mouse.pressed ? Style.space(1) : 0
        width: Style.space(16)
        height: Style.space(16)
        smooth: true
        mipmap: true
        source: btn.item.icon
      }

      MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        onClicked: {
          if (btn.item.cmd) ql.bar.run(btn.item.cmd)
          else ql.bar.vistaToggleDesktop(ql.monitorName)
        }
        onEntered: ql.bar.showTooltip(btn, btn.item.tip)
        onExited: ql.bar.hideTooltip(btn)
      }
    }
  }
}
