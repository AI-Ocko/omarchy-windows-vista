import QtQuick
import qs.Commons

// VistaWindow: a Vista window frame for the layer-shell dialogs that stand in
// for windows (Run, Run As, properties ...), drawn in the Vista Basic look
// (aero.msstyles Window class, the frame Vista gives windows it cannot
// compose): caption 29 px (SizingMargins 28,35,9,17), caption buttons 26x18
// hung from y 1 like the title bars (late.lua), frame 4 px. Caption text is
// Segoe UI 9 in black.
//
// Put the client area's content inside: it fills the face-coloured client
// rectangle (`client`). Buttons are listed left to right in `buttons`:
// "min", "max", "help", "close"; each emits its own signal.
Item {
  id: win

  property string title: ""
  property url titleIcon: ""
  property var buttons: ["close"]
  property bool sizable: false
  property bool active: true
  property bool closeEnabled: true
  // Buttons drawn in their disabled frame (sndvol32's Maximize, say).
  property var disabledButtons: []
  property color face: VistaScheme.sc.face
  default property alias content: client.data
  readonly property alias client: client
  readonly property int frameWidth: Style.space(4)
  readonly property int captionHeight: Style.space(29)

  signal closeClicked()
  signal minimizeClicked()
  signal maximizeClicked()
  signal helpClicked()

  function s(n) { return Style.space(n) }
  readonly property int frame: active ? 0 : 1

  // A caption button: CloseButton or CaptionButton bitmap (8 frames: normal,
  // hot, pressed, disabled, then the same inactive) with its 13 px glyph.
  component CaptionButton: Item {
    id: cbtn
    property string kind: "close"
    property bool enabledState: true
    signal clicked()
    width: win.s(26)
    height: win.s(18)
    readonly property int state4: !enabledState ? 3 : m.pressed ? 2 : m.containsMouse ? 1 : 0
    readonly property int cell: state4 + (win.active ? 0 : 4)
    VistaArt {
      anchors.fill: parent
      source: VistaScheme.art((cbtn.kind === "close" ? "win-close-" : "win-help-") + cbtn.cell)
      margins: [2, 2, 7, 7]
    }
    Image {
      anchors.centerIn: parent
      width: win.s(13)
      height: win.s(13)
      source: VistaScheme.art({ close: "win-closeg-", help: "win-helpg-", min: "win-ming-", max: "win-maxg-" }[cbtn.kind] + cbtn.cell)
      smooth: true
    }
    MouseArea { id: m; anchors.fill: parent; hoverEnabled: true; enabled: cbtn.enabledState; onClicked: cbtn.clicked() }
  }

  VistaArt {
    id: cap
    width: parent.width
    height: win.captionHeight
    source: VistaScheme.art("win-cap-" + win.frame)
    margins: [28, 35, 9, 17]
  }
  VistaArt {
    y: cap.height
    width: win.frameWidth
    height: parent.height - cap.height
    source: VistaScheme.art("win-left-" + win.frame)
    margins: VistaScheme.sc.frameL
  }
  VistaArt {
    x: parent.width - width
    y: cap.height
    width: win.frameWidth
    height: parent.height - cap.height
    source: VistaScheme.art("win-right-" + win.frame)
    margins: VistaScheme.sc.frameL
  }
  VistaArt {
    y: parent.height - height
    width: parent.width
    height: win.frameWidth
    source: VistaScheme.art("win-bottom-" + win.frame)
    margins: VistaScheme.sc.frameB
  }

  Image {
    id: capIcon
    visible: win.titleIcon.toString() !== ""
    x: win.s(6)
    y: (cap.height - height) / 2 + win.s(1)
    width: win.s(16)
    height: win.s(16)
    source: win.titleIcon
    smooth: true
  }
  Text {
    x: capText.x + win.s(1)
    y: capText.y + win.s(1)
    width: capText.width
    text: capText.text
    elide: Text.ElideRight
    color: VistaScheme.sc.capShadow
    font: capText.font
  }
  Text {
    id: capText
    x: capIcon.visible ? capIcon.x + capIcon.width + win.s(4) : win.s(7)
    y: (cap.height - height) / 2 + win.s(1)
    width: btnRow.x - x - win.s(4)
    text: win.title
    elide: Text.ElideRight
    color: VistaScheme.sc.capText
    font.family: "Segoe UI"
    font.pixelSize: Style.space(12)
  }

  // Right-aligned, joined, hung from the top edge as Basic's are.
  Row {
    id: btnRow
    x: parent.width - win.s(6) - width
    y: win.s(1)
    spacing: 0
    Repeater {
      model: win.buttons
      CaptionButton {
        required property string modelData
        kind: modelData
        enabledState: (modelData !== "close" || win.closeEnabled) && win.disabledButtons.indexOf(modelData) === -1
        onClicked: {
          if (kind === "close") win.closeClicked()
          else if (kind === "min") win.minimizeClicked()
          else if (kind === "max") win.maximizeClicked()
          else win.helpClicked()
        }
      }
    }
  }

  Rectangle {
    id: client
    x: win.frameWidth
    y: cap.height
    width: parent.width - 2 * win.frameWidth
    height: parent.height - cap.height - win.frameWidth
    color: win.face
  }
}
