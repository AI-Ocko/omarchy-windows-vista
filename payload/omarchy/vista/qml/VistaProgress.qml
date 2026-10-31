import QtQuick
import qs.Commons

// VistaProgress: Aero's continuous bar: [Progress] BAR (SizingMargins
// 9,9,7,6) with FILL (25,25,7,6) stretched to the value, as Vista drew a
// determinate progress bar. value is 0..1.
VistaArt {
  id: prog
  property real value: 0
  source: VistaScheme.art("progress-track")
  margins: [9, 9, 7, 6]
  VistaArt {
    x: Style.space(1)
    y: Style.space(1)
    height: prog.height - Style.space(2)
    width: Math.round(Math.max(0, Math.min(1, prog.value)) * (prog.width - Style.space(2)))
    visible: width >= Style.space(4)
    source: VistaScheme.art("progress-chunk")
    margins: [25, 25, 7, 6]
  }
}
