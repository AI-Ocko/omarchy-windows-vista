import QtQuick
import qs.Commons

// VistaWindow: an Vista top-level window drawn from the active scheme's msstyles
// art, for the layer-shell dialogs that stand in for windows (Run, the
// Control Panel / Search Results menu, Run As, ...). Geometry is Vista's own at
// 96 dpi through Style.space(): Window.Caption 29 px tall (SizingMargins
// 28,35,9,17), caption buttons 21x21 at y 5 and Offset -25 / -49 / -73 from
// the right ([Window.CloseButton/MaxButton/MinButton]), frame 3 px on a fixed
// dialog and 4 px on a sizable window (measured on a 1:1 Vista dialog capture,
// reference/dialog-automatic-updates.png). Caption text is Trebuchet MS 10
// bold (Style.font.subtitle) with the scheme's 1,1 TextShadowColor.
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
  readonly property int frameWidth: Style.space(sizable ? 4 : 3)
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
    width: win.s(21)
    height: win.s(21)
    readonly property int state4: !enabledState ? 3 : m.pressed ? 2 : m.containsMouse ? 1 : 0
    readonly property int cell: state4 + (win.active ? 0 : 4)
    VistaArt {
      anchors.fill: parent
      source: VistaScheme.art((cbtn.kind === "close" ? "win-close-" : "win-help-") + cbtn.cell)
      margins: [5, 5, 5, 5]
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
    font.family: "Trebuchet MS"
    font.bold: true
    font.pixelSize: Style.font.subtitle
  }

  // Right-aligned so the last button sits at Offset -25; neighbours 3 px apart.
  Row {
    id: btnRow
    x: parent.width - win.s(4) - width
    y: win.s(5)
    spacing: win.s(3)
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
