import QtQuick
import QtQuick.Effects
import qs.Commons

// VistaWindow: a Vista window frame for the layer-shell dialogs that stand in
// for windows (Run, properties, ...). In the Aero schemes it is the glass
// frame the title bars draw (late.lua): the scheme's colorization over the
// compositor's blur (the dialog layer is blurred; the client area is opaque),
// the DWM reflection across the caption, the joined DWM caption buttons hung
// from the top edge, black caption text with a white glow, 8 px frame, 6 px
// corners. In Vista Basic it is aero.msstyles' Window class: caption 29 px
// (SizingMargins 28,35,9,17), separate 26x18 buttons, 4 px frame. Caption
// text is Segoe UI 9.
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
  readonly property bool glass: VistaScheme.glass
  readonly property int frameWidth: Style.space(glass ? 8 : 4)
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
    width: win.glass ? win.s(kind === "close" ? 46 : 28) : win.s(26)
    height: win.glass ? win.s(20) : win.s(18)
    readonly property int state4: !enabledState ? 3 : m.pressed ? 2 : m.containsMouse ? 1 : 0
    readonly property int cell: state4 + (win.active ? 0 : 4)
    VistaArt {
      visible: !win.glass
      anchors.fill: parent
      source: VistaScheme.art((cbtn.kind === "close" ? "win-close-" : "win-help-") + cbtn.cell)
      margins: [2, 2, 7, 7]
    }
    Image {
      visible: !win.glass
      anchors.centerIn: parent
      width: win.s(13)
      height: win.s(13)
      source: VistaScheme.art({ close: "win-closeg-", help: "win-helpg-", min: "win-ming-", max: "win-maxg-" }[cbtn.kind] + cbtn.cell)
      smooth: true
    }
    // Glass: the DWM button (close red only while active) and its glyph.
    readonly property string gk: cbtn.kind === "close" ? "close" : cbtn.kind === "min" ? "min" : "max"
    Image {
      visible: win.glass
      anchors.fill: parent
      source: VistaScheme.captionArt + cbtn.gk + "-bg-" + cbtn.cell + ".png"
      smooth: true
    }
    Image {
      visible: win.glass
      anchors.centerIn: parent
      source: VistaScheme.captionArt + cbtn.gk + "-g-" + cbtn.cell + ".png"
      width: win.s(sourceSize.width); height: win.s(sourceSize.height)
      smooth: true
    }
    MouseArea { id: m; anchors.fill: parent; hoverEnabled: true; enabled: cbtn.enabledState; onClicked: cbtn.clicked() }
  }

  // ---- glass frame (drawn under everything else)
  Rectangle {
    visible: win.glass
    anchors.fill: parent
    radius: win.s(6)
    color: VistaScheme.tint
    border.width: 1
    border.color: "#99000000"
    Rectangle {
      anchors.fill: parent
      anchors.margins: 1
      radius: win.s(5)
      color: "transparent"
      border.width: 1
      border.color: "#66FFFFFF"
    }
    Image {
      anchors.fill: parent
      anchors.margins: 1
      source: VistaScheme.graphics + "/aero/parts/DWMWindow/40.0.ATLAS.png"
      fillMode: Image.Stretch
      opacity: 0.8
    }
  }

  VistaArt {
    id: cap
    visible: !win.glass
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
    visible: !win.glass
    margins: VistaScheme.sc.frameL
  }
  VistaArt {
    x: parent.width - width
    y: cap.height
    width: win.frameWidth
    height: parent.height - cap.height
    source: VistaScheme.art("win-right-" + win.frame)
    visible: !win.glass
    margins: VistaScheme.sc.frameL
  }
  VistaArt {
    y: parent.height - height
    width: parent.width
    height: win.frameWidth
    source: VistaScheme.art("win-bottom-" + win.frame)
    visible: !win.glass
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
    visible: !win.glass
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
    color: win.glass && !win.active ? "#333333" : VistaScheme.sc.capText
    font.family: "Segoe UI"
    layer.enabled: win.glass
    layer.effect: MultiEffect {
      shadowEnabled: true
      shadowColor: "#FFFFFF"
      shadowBlur: 0.6
      shadowOpacity: 0.85
      shadowHorizontalOffset: 0
      shadowVerticalOffset: 0
      blurMax: 12
    }
    font.pixelSize: Style.space(12)
  }

  // Right-aligned, joined, hung from the top edge as Basic's are.
  Row {
    id: btnRow
    x: parent.width - win.s(6) - width
    y: win.glass ? 0 : win.s(1)
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
    // Aero: the darker 1 px client edge inside the glass frame.
    border.width: win.glass ? 1 : 0
    border.color: "#80000000"
  }
}
