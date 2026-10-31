import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import "../../vista/qml"

// Vista's Run dialog (Start > Run…), bottom-left above the taskbar where Vista put
// it. Window chrome is the scheme's own Window.Caption / Frame* / CloseButton
// / HelpButton art; buttons are Button.Pushbutton; the Open box is an
// editable combo whose drop list is the Run history (newest first, 26 kept,
// like RunMRU a–z) stored in start-usage.json. The command runs detached
// through bash -lc, as every Omarchy launcher does.
Scope {
  id: run

  required property var menu        // VistaStartMenu

  property var screenObj: null
  property bool listOpen: false
  property int listIndex: -1
  property int histIndex: -1
  property bool focusPrimed: false
  property int focusButton: 0        // 0 OK, 1 Cancel, 2 Browse… (dotted ring)

  function s(n) { return Style.space(n) }

  function show(screen) {
    if (!screen) return
    focusPrimed = false
    listOpen = false
    histIndex = -1
    screenObj = screen
    primeTimer.restart()
  }

  function hide() {
    screenObj = null
    listOpen = false
  }

  function submit(text) {
    var cmd = String(text || "").trim()
    if (!cmd) return
    menu.recordRun(cmd)
    menu.run(cmd)
    hide()
  }

  Timer {
    id: primeTimer
    interval: 75
    onTriggered: run.focusPrimed = true
  }

  // Browse…: GTK file chooser via zenity (installed); the chosen path lands
  // in the Open box, quoted, as Vista's Browse did.
  property var browseTarget: null
  Process {
    id: browse
    command: ["zenity", "--file-selection", "--title=Browse"]
    stdout: StdioCollector {
      onStreamFinished: {
        var p = String(text || "").trim()
        if (p && run.browseTarget) run.browseTarget.text = p.indexOf(" ") !== -1 ? "\"" + p + "\"" : p
      }
    }
    stderr: SplitParser { onRead: function(line) { if (line) console.warn("ocko.vista-taskbar: zenity: " + line) } }
  }

  LazyLoader {
    active: run.screenObj !== null

    PanelWindow {
      id: win
      screen: run.screenObj
      color: "transparent"
      exclusionMode: ExclusionMode.Ignore
      anchors { bottom: true; left: true }
      margins.bottom: run.menu.bar.barSize
      implicitWidth: run.s(347)
      implicitHeight: run.s(179)
      WlrLayershell.namespace: "vista-run-dialog"
      WlrLayershell.layer: WlrLayer.Top
      WlrLayershell.keyboardFocus: run.focusPrimed ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.Exclusive

      // ---- frame: the shared Vista window chrome (omarchy/vista/qml/VistaWindow.qml)
      VistaWindow {
        anchors.fill: parent
        title: "Run"
        buttons: ["help", "close"]
        onHelpClicked: run.menu.run("omarchy-launch-webapp 'https://omarchy.org/manual/'")
        onCloseClicked: run.hide()

      // ---- client area
      Item {
        id: client
        anchors.fill: parent

        // Called first by the Open box (its own Keys handler runs before
        // TextInput swallows Return).
        function handleKey(event) {
          if (event.key === Qt.Key_Escape) { if (run.listOpen) run.listOpen = false; else run.hide(); event.accepted = true }
          else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            if (run.listOpen && run.listIndex >= 0) { field.text = run.menu.usage.run[run.listIndex]; run.listOpen = false }
            else if (run.focusButton === 1) run.hide()
            else if (run.focusButton === 2) { run.browseTarget = field; browse.running = true }
            else run.submit(field.text)
            event.accepted = true
          }
          else if (event.key === Qt.Key_Tab) { run.focusButton = (run.focusButton + 1) % 3; event.accepted = true }
        }

        Image {
          x: run.s(12)
          y: run.s(15)
          width: run.s(32)
          height: run.s(32)
          sourceSize.width: width
          sourceSize.height: height
          source: VistaScheme.icon(25, 32)
        }
        Text {
          x: run.s(55)
          y: run.s(14)
          width: run.s(270)
          wrapMode: Text.WordWrap
          text: "Type the name of a program, folder, document, or Internet resource, and Windows will open it for you."
          color: "#000000"
          font.family: "Segoe UI"
          font.pixelSize: Style.font.bodySmall
        }
        Text {
          x: run.s(12)
          y: combo.y + (combo.height - height) / 2
          text: "<u>O</u>pen:"
          textFormat: Text.StyledText
          color: "#000000"
          font.family: "Segoe UI"
          font.pixelSize: Style.font.bodySmall
        }

        // Open: [Combobox] white, 1 px #7F9DB9, DropDownButton art on the right
        Rectangle {
          id: combo
          x: run.s(55)
          y: run.s(53)
          width: run.s(270)
          height: run.s(21)
          color: "#FFFFFF"
          border.width: Math.max(1, run.s(1))
          border.color: "#7F9DB9"

          TextInput {
            id: field
            x: run.s(3)
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width - dropBtn.width - run.s(6)
            clip: true
            focus: true
            selectByMouse: true
            color: "#000000"
            selectionColor: "#316AC5"
            selectedTextColor: "#FFFFFF"
            font.family: "Segoe UI"
            font.pixelSize: Style.font.bodySmall
            // Vista pre-fills the most recent command, selected.
            Component.onCompleted: {
              text = run.menu.usage.run.length ? run.menu.usage.run[0] : ""
              selectAll()
              Qt.callLater(function() { field.forceActiveFocus() })
            }
            Keys.onPressed: function(event) {
              var h = run.menu.usage.run
              if (event.key === Qt.Key_Down && (event.modifiers & Qt.AltModifier)) { run.listOpen = !run.listOpen; event.accepted = true }
              else if (run.listOpen && (event.key === Qt.Key_Down || event.key === Qt.Key_Up)) {
                run.listIndex = Math.max(0, Math.min(h.length - 1, run.listIndex + (event.key === Qt.Key_Down ? 1 : -1)))
                event.accepted = true
              } else if (event.key === Qt.Key_Down || event.key === Qt.Key_Up) {
                if (!h.length) return
                run.histIndex = Math.max(0, Math.min(h.length - 1, run.histIndex + (event.key === Qt.Key_Down ? 1 : -1)))
                text = h[run.histIndex]
                selectAll()
                event.accepted = true
              } else {
                client.handleKey(event)
              }
            }
          }

          Item {
            id: dropBtn
            anchors.right: parent.right
            anchors.rightMargin: Math.max(1, run.s(1))
            anchors.verticalCenter: parent.verticalCenter
            width: run.s(17)
            height: parent.height - 2 * Math.max(1, run.s(1))
            readonly property int frame: run.menu.usage.run.length === 0 ? 3 : dropMouse.pressed || run.listOpen ? 2 : dropMouse.containsMouse ? 1 : 0
            VistaArt {
              anchors.fill: parent
              source: run.menu.artDir + "/combo-" + dropBtn.frame + ".png"
              margins: [3, 3, 3, 3]
            }
            Image {
              anchors.centerIn: parent
              width: run.s(10)
              height: run.s(7)
              source: run.menu.artDir + "/combog-" + dropBtn.frame + ".png"
              smooth: true
            }
            MouseArea {
              id: dropMouse
              anchors.fill: parent
              hoverEnabled: true
              onClicked: if (run.menu.usage.run.length) { run.listOpen = !run.listOpen; run.listIndex = -1 }
            }
          }
        }

        VistaButton {
          x: client.width - run.s(12 + 75 + 6 + 75 + 6 + 75)
          y: client.height - run.s(12 + 23)
          artDir: run.menu.artDir
          text: "OK"
          isDefault: true
          focused: run.focusButton === 0
          onClicked: run.submit(field.text)
        }
        VistaButton {
          x: client.width - run.s(12 + 75 + 6 + 75)
          y: client.height - run.s(12 + 23)
          artDir: run.menu.artDir
          text: "Cancel"
          focused: run.focusButton === 1
          onClicked: run.hide()
        }
        VistaButton {
          x: client.width - run.s(12 + 75)
          y: client.height - run.s(12 + 23)
          artDir: run.menu.artDir
          text: "<u>B</u>rowse..."
          focused: run.focusButton === 2
          onClicked: { run.browseTarget = field; browse.running = true }
        }

        // Drop list: the Run history, under the combo (inside the dialog;
        // Vista flipped it above when there was no room below the screen edge).
        Rectangle {
          visible: run.listOpen
          x: combo.x
          y: combo.y + combo.height
          width: combo.width
          height: Math.min(client.height - y - run.s(2), list.contentHeight + 2 * border.width)
          color: "#FFFFFF"
          border.width: Math.max(1, run.s(1))
          border.color: "#000000"
          ListView {
            id: list
            anchors.fill: parent
            anchors.margins: parent.border.width
            clip: true
            model: run.listOpen ? run.menu.usage.run.length : 0
            delegate: Rectangle {
              required property int index
              width: list.width
              height: run.s(16)
              color: run.listIndex === index ? "#316AC5" : "#FFFFFF"
              Text {
                x: run.s(3)
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width - run.s(6)
                elide: Text.ElideRight
                text: run.menu.usage.run[index] || ""
                color: run.listIndex === index ? "#FFFFFF" : "#000000"
                font.family: "Segoe UI"
                font.pixelSize: Style.font.bodySmall
              }
              MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                onEntered: run.listIndex = index
                onClicked: { field.text = run.menu.usage.run[index]; run.listOpen = false; field.forceActiveFocus() }
              }
            }
          }
        }
      }
      }
    }
  }
}
