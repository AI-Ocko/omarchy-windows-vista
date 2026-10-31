import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Commons
import "../../vista/qml"

// Vista's "Shut Down Windows" dialog (Alt+F4 on the desktop): the basebrd.dll
// banner (BITMAP 101, 413x72) over its orange rule (111), the power icon,
// "What do you want the computer to do?" with a drop-down of the Start menu
// power arrow's actions (same commands: VistaStartMenu.powerItems), the
// chosen action's description, and OK / Cancel / Help. Opened by
// `omarchy-shell vistastart shutdown` (the Vista menu's system route). No
// template of it survives in the pinned files, so the layout is reconstructed
// at Vista's proportions. Actions go through menu.systemAction(), which owns
// the sounds and the dry-run switch.
Scope {
  id: dlg

  required property var menu       // VistaStartMenu

  property var screenObj: null
  property int sel: 0

  function s(n) { return Style.space(n) }

  readonly property var actions: menu.powerItems().filter(function(it) { return it.kind !== "sep" })
  readonly property var descriptions: ({
    "Switch User": "Lets another person log on while your programs and files stay open.",
    "Log Off": "Closes your programs and ends your session.",
    "Lock": "Locks the computer. Your programs and files stay open.",
    "Restart": "Ends your session, shuts down Windows, and then starts Windows again.",
    "Sleep": "Keeps your session in memory and puts the computer in a low-power state so that you can quickly resume working.",
    "Hibernate": "Saves your session and turns off the computer. When you turn on the computer, your session is restored.",
    "Shut Down": "Ends your session and shuts down Windows so that you can safely turn off the power."
  })

  function show(screen) {
    if (!screen) return
    var i = 0
    for (; i < actions.length; i++) if (actions[i].label === "Shut Down") break
    sel = i < actions.length ? i : 0
    screenObj = screen
  }

  function hide() { screenObj = null; combo.open = false }

  function choose() {
    var a = actions[sel]
    hide()
    if (a) a.run()
  }

  LazyLoader {
    active: dlg.screenObj !== null

    PanelWindow {
      screen: dlg.screenObj
      color: "transparent"
      exclusionMode: ExclusionMode.Ignore
      implicitWidth: win.width
      implicitHeight: win.height
      WlrLayershell.namespace: "vista-exit-dialog"
      WlrLayershell.layer: WlrLayer.Overlay
      WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

      VistaWindow {
        id: win
        readonly property int frameW: dlg.s(VistaScheme.glass ? 8 : 4)
        width: dlg.s(413) + 2 * frameW
        height: captionHeight + body.height + frameW
        title: "Shut Down Windows"
        buttons: ["close"]
        onCloseClicked: dlg.hide()

        Item {
          id: body
          width: parent.width
          height: dlg.s(72 + 5 + 150)
          focus: true
          Keys.onPressed: function(event) {
            if (event.key === Qt.Key_Escape) { dlg.hide(); event.accepted = true }
            else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) { dlg.choose(); event.accepted = true }
            else if (event.key === Qt.Key_Down) { dlg.sel = Math.min(dlg.actions.length - 1, dlg.sel + 1); event.accepted = true }
            else if (event.key === Qt.Key_Up) { dlg.sel = Math.max(0, dlg.sel - 1); event.accepted = true }
          }

          Image {
            id: banner
            width: dlg.s(413); height: dlg.s(72)
            source: VistaScheme.graphics + "/basebrd/BITMAP/101.bmp"
          }
          Image {
            y: banner.height
            width: dlg.s(413); height: dlg.s(5)
            source: VistaScheme.graphics + "/basebrd/BITMAP/111.bmp"
          }

          Image {
            x: dlg.s(16); y: dlg.s(72 + 5 + 18)
            width: dlg.s(32); height: dlg.s(32)
            source: VistaScheme.icon(28, 32)
            smooth: true
          }
          Text {
            x: dlg.s(60); y: dlg.s(72 + 5 + 16)
            text: "What do you want the computer to do?"
            color: "#000000"
            font.family: "Segoe UI"
            font.pixelSize: dlg.s(12)
          }
          VistaComboBox {
            id: combo
            z: 5
            x: dlg.s(60); y: dlg.s(72 + 5 + 38)
            width: dlg.s(240)
            model: dlg.actions.map(function(a) { return a.label })
            currentIndex: dlg.sel
            visibleRows: 7
            focused: true
            onActivated: function(i) { dlg.sel = i; open = false }
          }
          Text {
            x: dlg.s(60); y: dlg.s(72 + 5 + 68)
            width: dlg.s(330)
            wrapMode: Text.WordWrap
            text: dlg.descriptions[(dlg.actions[dlg.sel] || {}).label] || ""
            color: "#000000"
            font.family: "Segoe UI"
            font.pixelSize: dlg.s(12)
          }

          Row {
            anchors.right: parent.right
            anchors.rightMargin: dlg.s(12)
            y: body.height - dlg.s(12 + 23)
            spacing: dlg.s(8)
            VistaButton { text: "OK"; isDefault: true; onClicked: dlg.choose() }
            VistaButton { text: "Cancel"; onClicked: dlg.hide() }
            VistaButton { text: "<u>H</u>elp"; enabled: false }
          }
        }
      }
    }
  }
}
