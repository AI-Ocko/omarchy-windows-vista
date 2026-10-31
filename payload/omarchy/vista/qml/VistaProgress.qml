import QtQuick
import qs.Commons

// VistaProgress: [Progress] ProgressTrack (SizingMargins 4,4,3,3) with
// ProgressChunk art, 6 px chunks and 2 px gaps; a Repeater on an int.
// value is 0..1.
VistaArt {
  id: prog
  property real value: 0
  readonly property real inner: width - Style.space(6)
  source: VistaScheme.art("progress-track")
  margins: [4, 4, 3, 3]
  Row {
    x: Style.space(3)
    y: Style.space(2)
    spacing: Style.space(2)
    Repeater {
      // inner is negative until the item is laid out (width 0).
      model: Math.max(0, Math.floor(Math.max(0, Math.min(1, prog.value)) * prog.inner / Style.space(8)))
      VistaArt {
        width: Style.space(6)
        height: prog.height - Style.space(4)
        source: VistaScheme.art("progress-chunk")
        margins: [0, 0, 6, 5]
      }
    }
  }
}
