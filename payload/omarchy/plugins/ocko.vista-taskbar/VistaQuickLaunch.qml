import QtQuick
import Quickshell
import qs.Commons
import "../../vista/qml"

// Quick Launch toolbar: 16 px icons in 22 px hot-tracked buttons, as Vista drew
// them beside the start button. Icons come from the apps' desktop entries
// until an Vista icon theme exists (Task 9).
Row {
  id: ql

  required property var bar          // the Vista Bar root
  required property string monitorName
  required property string artDir

  readonly property var items: [
    { tip: "Internet", icon: "zen-browser", cmd: "omarchy-launch-browser" },
    { tip: "Command Prompt", icon: "foot", cmd: "omarchy-launch-terminal" },
    { tip: "My Computer", icon: "org.gnome.Nautilus", cmd: "nautilus --new-window /" },
    { tip: "Show Desktop", icon: "user-desktop", cmd: "" }
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
        sourceSize.width: width
        sourceSize.height: height
        source: Quickshell.iconPath(btn.item.icon, "application-x-executable")
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
