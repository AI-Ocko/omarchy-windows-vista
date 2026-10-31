import QtQuick
import Quickshell
import Quickshell.Hyprland
import qs.Commons
import "../../vista/qml"

// The task band: one button per window on this monitor, across its
// workspaces, plus the ones minimised from it. Event-driven from
// Quickshell.Hyprland; nothing polls. Buttons share the width evenly up to
// Vista's 160 px maximum; Vista's grouping is not implemented (they just shrink).
//
// Button art is [TaskBand::Toolbar.Button]: frames normal, hot, pressed,
// disabled, checked (= the focused window), hot+checked.
Item {
  id: band

  required property var bar          // the Vista Bar root
  required property string monitorName
  required property string artDir
  required property var scheme

  // Reading each toplevel's workspace/monitor inside the binding makes it
  // re-run when one moves; ScriptModel diffs by identity, so a move or a new
  // window does not rebuild the other buttons.
  readonly property var windows: {
    var out = []
    var list = Hyprland.toplevels.values
    var origins = band.bar.vistaOrigins
    for (var i = 0; i < list.length; i++) {
      var t = list[i]
      var ws = t.workspace
      if (!ws) continue
      var name = String(ws.name || "")
      var mon = t.monitor ? String(t.monitor.name || "") : ""
      if (name === band.bar.vistaMinimizedWorkspace) {
        var origin = origins[String(t.address)]
        if (origin) mon = origin.monitor
      } else if (name.indexOf("special:") === 0) {
        continue
      }
      if (mon === band.monitorName) out.push(t)
    }
    return out
  }

  readonly property int gap: Style.space(2)
  readonly property real buttonWidth: windows.length === 0 ? 0
    : Math.min(Style.space(160), Math.floor((width - gap * (windows.length - 1)) / windows.length))

  Row {
    anchors.verticalCenter: parent.verticalCenter
    spacing: band.gap

    Repeater {
      model: ScriptModel { values: band.windows }

      Item {
        id: button

        required property var modelData
        readonly property var win: modelData
        readonly property bool minimised: win.workspace && win.workspace.name === band.bar.vistaMinimizedWorkspace
        readonly property bool focused: win.activated && !minimised
        readonly property bool tooltipHovered: mouse.containsMouse
        readonly property string appId: win.wayland ? String(win.wayland.appId || "") : ""
        readonly property var entry: appId ? DesktopEntries.heuristicLookup(appId) : null

        width: band.buttonWidth
        // TaskBand::Toolbar BUTTON art is 29 rows inside the 30-row taskbar.
        height: Style.space(29)

        VistaArt {
          anchors.fill: parent
          source: band.artDir + "/task-" + (mouse.pressed ? 2
            : button.focused ? (mouse.containsMouse ? 5 : 4)
            : mouse.containsMouse ? 1 : 0) + ".png"
          margins: band.scheme.button
        }

        Row {
          // Vista dims nothing; minimised windows are told apart here by a
          // faded icon and title (a Hermes decision, not Vista's look).
          opacity: button.minimised ? 0.6 : 1
          x: Style.space(6)
          width: parent.width - x - Style.space(4)
          anchors.verticalCenter: parent.verticalCenter
          anchors.verticalCenterOffset: mouse.pressed || button.focused ? Style.space(1) : 0
          spacing: Style.space(4)

          Image {
            anchors.verticalCenter: parent.verticalCenter
            width: Style.space(16)
            height: Style.space(16)
            sourceSize.width: width
            sourceSize.height: height
            source: Quickshell.iconPath(button.entry && button.entry.icon ? button.entry.icon : button.appId,
              "application-x-executable")
          }

          Text {
            anchors.verticalCenter: parent.verticalCenter
            width: Math.max(0, parent.width - Style.space(20))
            text: button.win.title || button.appId
            elide: Text.ElideRight
            color: button.focused || mouse.pressed ? band.scheme.taskChecked : band.scheme.task
            font.family: "Segoe UI"
            font.pixelSize: Style.font.bodySmall
          }
        }

        MouseArea {
          id: mouse
          anchors.fill: parent
          hoverEnabled: true
          onClicked: band.bar.vistaActivate(button.win, band.monitorName)
          onEntered: band.bar.showTooltip(button, button.win.title || button.appId)
          onExited: band.bar.hideTooltip(button)
        }
      }
    }
  }
}
