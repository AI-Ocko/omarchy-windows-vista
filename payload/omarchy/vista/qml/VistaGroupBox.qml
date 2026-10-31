import QtQuick
import qs.Commons

// VistaGroupBox: [button.groupbox] -- GroupBox.bmp drawn border-only
// (SizingMargins 4,4,4,4) with the caption in Tahoma 8 and the scheme's
// group TextColor. Vista clips the frame behind the caption rather than
// painting over it, so the box sits right on any face, a white tab page
// included: the frame is drawn in three clipped pieces around the gap.
// Children go in the content area under the caption.
Item {
  id: box

  property string caption: ""
  default property alias content: inner.data
  readonly property int inset: Style.space(9)
  readonly property real frameY: Math.round(label.height / 2)
  readonly property real gapX: caption !== "" ? Style.space(6) : 0
  readonly property real gapWidth: caption !== "" ? label.implicitWidth + Style.space(4) : 0

  component FramePiece: Item {
    clip: true
    VistaArt {
      x: -parent.x
      y: box.frameY - parent.y
      width: box.width
      height: box.height - box.frameY
      source: VistaScheme.art("groupbox")
      margins: [4, 4, 4, 4]
    }
  }

  FramePiece { width: box.gapX; height: box.height }
  FramePiece { x: box.gapX + box.gapWidth; width: box.width - x; height: box.height }
  FramePiece { x: box.gapX; y: box.frameY + Style.space(3); width: box.gapWidth; height: box.height - y }
  Text {
    id: label
    visible: box.caption !== ""
    x: box.gapX + Style.space(2)
    text: box.caption
    color: VistaScheme.sc.groupText
    font.family: "Tahoma"
    font.pixelSize: Style.font.bodySmall
  }
  Item {
    id: inner
    x: box.inset
    y: label.height + Style.space(6)
    width: parent.width - 2 * box.inset
    height: parent.height - y - box.inset
  }
}
