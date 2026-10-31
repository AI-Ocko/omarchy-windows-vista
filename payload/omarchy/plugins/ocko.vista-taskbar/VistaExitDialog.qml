import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons

// Vista's "Turn off computer" and "Log Off Windows" dialogs (msgina's fancy
// dialogs: bitmap 20142 background, 20143 flag, 20150 buttons). Every screen
// is covered and fades to greyscale behind it, as Vista desaturated the desktop;
// the dialog itself sits centred on the screen the Start menu was opened on.
// Actions go through menu.systemAction(), which owns the dry-run switch.
Scope {
  id: dlg

  required property var menu       // VistaStartMenu

  property string mode: ""          // "logoff" | "turnoff" | ""
  property string pendingMode: ""
  property var screenObj: null
  property int sel: 1               // keyboard selection; buttons.length = Cancel
  property bool standByOk: true

  function s(n) { return Style.space(n) }

  // frames: 20150 cells [normal, hot, pressed]; 9 is Stand By disabled.
  // Commands are the stock power menu's (default/omarchy/omarchy-menu.jsonc
  // system.*); Switch User locks, as the spec decided.
  readonly property var buttons: mode === "turnoff" ? [
    { label: "<u>S</u>tand By", key: Qt.Key_S, frames: [3, 5, 4], what: "suspend", cmd: "systemctl suspend" },
    { label: "T<u>u</u>rn Off", key: Qt.Key_U, frames: [0, 2, 1], what: "shutdown", cmd: "omarchy-system-shutdown" },
    { label: "<u>R</u>estart", key: Qt.Key_R, frames: [6, 8, 7], what: "reboot", cmd: "omarchy-system-reboot" }
  ] : [
    { label: "<u>S</u>witch User", key: Qt.Key_S, icon: "switch", what: "lock", cmd: "omarchy-system-lock" },
    { label: "<u>L</u>og Off", key: Qt.Key_L, icon: "key", what: "logout", cmd: "omarchy-system-logout" }
  ]

  function show(m, screen) {
    if (!screen) return
    screenObj = screen
    pendingMode = m
    sel = 1
    if (m === "turnoff") suspendCheck.running = true
    // Let the Start menu's surface unmap before the screen is captured.
    openTimer.restart()
  }

  function hide() {
    mode = ""
    pendingMode = ""
  }

  function enabledAt(i) {
    return !(mode === "turnoff" && i === 0 && !standByOk)
  }

  function choose(i) {
    if (i >= buttons.length) { hide(); return }
    if (!enabledAt(i)) return
    var b = buttons[i]
    hide()
    menu.systemAction(b.what, b.cmd)
  }

  Timer {
    id: openTimer
    interval: 120
    onTriggered: dlg.mode = dlg.pendingMode
  }

  // The stock menu hides Suspend when the suspend-off toggle is on; Vista
  // greys Stand By instead (20150 cell 9).
  Process {
    id: suspendCheck
    command: ["omarchy-toggle-enabled", "suspend-off"]
    onExited: function(code) { dlg.standByOk = code !== 0 }
  }

  // Classic 3D push button, as in reference/turn-off-computer-dialog.png
  // (msgina draws its Cancel unthemed).
  component ClassicButton: Item {
    id: cb
    property string text: ""
    property bool focused: false
    signal clicked()
    width: dlg.s(60)
    height: dlg.s(20)
    Rectangle { anchors.fill: parent; color: area.pressed ? "#000000" : "#FFFFFF" }
    Rectangle { x: dlg.s(1); y: dlg.s(1); width: parent.width - x; height: parent.height - y; color: area.pressed ? "#FFFFFF" : "#000000" }
    Rectangle { x: dlg.s(1); y: dlg.s(1); width: parent.width - dlg.s(2); height: parent.height - dlg.s(2); color: area.pressed ? "#808080" : "#C0C0C0" }
    Rectangle { x: dlg.s(1); y: dlg.s(1); width: parent.width - dlg.s(3); height: parent.height - dlg.s(3); color: "#C0C0C0" }
    Text {
      anchors.centerIn: parent
      anchors.horizontalCenterOffset: area.pressed ? dlg.s(1) : 0
      anchors.verticalCenterOffset: area.pressed ? dlg.s(1) : 0
      text: cb.text
      color: "#000000"
      font.family: "Tahoma"
      font.pixelSize: Style.font.bodySmall
    }
    Rectangle {
      visible: cb.focused
      anchors.fill: parent
      anchors.margins: dlg.s(4)
      color: "transparent"
      border.width: 1
      border.color: "#000000"
      opacity: 0.5
    }
    MouseArea { id: area; anchors.fill: parent; onClicked: cb.clicked() }
  }

  Variants {
    model: dlg.mode !== "" ? Quickshell.screens : []

    PanelWindow {
      id: win
      required property var modelData
      readonly property bool primary: !!dlg.screenObj && modelData.name === dlg.screenObj.name

      screen: modelData
      color: "transparent"
      exclusionMode: ExclusionMode.Ignore
      anchors { top: true; bottom: true; left: true; right: true }
      WlrLayershell.namespace: "vista-exit-dialog"
      WlrLayershell.layer: WlrLayer.Overlay
      WlrLayershell.keyboardFocus: primary ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

      // One still frame of this output, then the same frame in greyscale
      // fading in over it. live: false, so it costs one capture, not a stream.
      ScreencopyView {
        id: shot
        anchors.fill: parent
        captureSource: win.modelData
        live: false
      }
      MultiEffect {
        anchors.fill: parent
        source: shot
        saturation: -1.0
        opacity: 0
        NumberAnimation on opacity { running: shot.hasContent; from: 0; to: 1; duration: 1500; easing.type: Easing.InOutQuad }
      }

      // Modal: swallow every click outside the dialog.
      MouseArea { anchors.fill: parent; acceptedButtons: Qt.AllButtons }

      Item {
        id: box
        visible: win.primary
        anchors.centerIn: parent
        width: dlg.s(313)
        height: dlg.s(198)
        focus: win.primary
        Component.onCompleted: if (win.primary) Qt.callLater(function() { box.forceActiveFocus() })

        Keys.onPressed: function(event) {
          var n = dlg.buttons.length
          if (event.key === Qt.Key_Escape) dlg.hide()
          else if (event.key === Qt.Key_Left || (event.key === Qt.Key_Tab && (event.modifiers & Qt.ShiftModifier)) || event.key === Qt.Key_Backtab)
            dlg.sel = (dlg.sel + n) % (n + 1)
          else if (event.key === Qt.Key_Right || event.key === Qt.Key_Tab)
            dlg.sel = (dlg.sel + 1) % (n + 1)
          else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space)
            dlg.choose(dlg.sel)
          else {
            for (var i = 0; i < n; i++) if (event.key === dlg.buttons[i].key) dlg.choose(i)
            if (event.key === Qt.Key_C) dlg.hide()
          }
          event.accepted = true
        }

        Image {
          anchors.fill: parent
          source: dlg.menu.artRoot + "/dlg-bg.png"
          smooth: true
        }

        Text {
          x: dlg.s(12)
          y: dlg.s(9)
          text: dlg.mode === "turnoff" ? "Turn off computer" : "Log Off Windows"
          color: "#FFFFFF"
          font.family: "Arial"
          font.pixelSize: Style.font.iconLarge
        }

        Image {
          x: parent.width - width
          y: dlg.s(1)
          width: dlg.s(48)
          height: dlg.s(40)
          source: dlg.menu.artRoot + "/dlg-flag.png"
          smooth: true
        }

        Row {
          anchors.horizontalCenter: parent.horizontalCenter
          y: dlg.s(80)
          spacing: dlg.s(86 - 32)
          Repeater {
            model: dlg.buttons.length
            Item {
              id: cell
              required property int index
              readonly property var b: dlg.buttons[index]
              readonly property bool ok: dlg.enabledAt(index)
              readonly property bool hot: ok && (area.containsMouse || dlg.sel === index)
              width: dlg.s(32)
              height: dlg.s(32)

              // Turn Off dialog: a 32 px cell of msgina 20150.
              Image {
                visible: !!cell.b.frames
                anchors.fill: parent
                source: cell.b.frames
                  ? dlg.menu.artRoot + "/dlg-btn-" + (!cell.ok ? 9 : area.pressed ? cell.b.frames[2] : cell.hot ? cell.b.frames[1] : cell.b.frames[0]) + ".png"
                  : ""
                smooth: true
              }
              // Log Off dialog: shell32.dll bitmap 14356, the real Switch User
              // and Log Off buttons (normal 0 / pressed 1 / hot 2), cut by
              // vista-taskbar-art into dlg-switch-* and dlg-logoff-*.
              Image {
                visible: cell.b.icon === "switch" || cell.b.icon === "key"
                anchors.fill: parent
                source: visible ? dlg.menu.artRoot + (cell.b.icon === "switch" ? "/dlg-switch-" : "/dlg-logoff-")
                  + (area.pressed ? 1 : cell.hot ? 2 : 0) + ".png" : ""
                smooth: true
              }

              Text {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.top: parent.bottom
                anchors.topMargin: dlg.s(6)
                text: cell.b.label
                textFormat: Text.StyledText
                color: cell.ok ? "#FFFFFF" : "#A6B8E8"
                font.family: "Tahoma"
                font.pixelSize: Style.font.bodySmall
              }

              MouseArea {
                id: area
                anchors.fill: parent
                hoverEnabled: true
                onEntered: dlg.sel = cell.index
                onClicked: dlg.choose(cell.index)
              }
            }
          }
        }

        ClassicButton {
          anchors.right: parent.right
          anchors.rightMargin: dlg.s(9)
          anchors.bottom: parent.bottom
          anchors.bottomMargin: dlg.s(11)
          text: "Cancel"
          focused: dlg.sel === dlg.buttons.length
          onClicked: dlg.hide()
        }
      }
    }
  }
}
