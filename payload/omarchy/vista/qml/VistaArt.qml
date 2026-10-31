import QtQuick
import qs.Commons

// One msstyles bitmap drawn as a 9-slice at Vista's own 96-dpi geometry, then
// scaled by the shell's rem factor (Style.spaceReal(1) = base-size / 12), so
// the INI's SizingMargins apply in source pixels exactly as uxtheme applied
// them, and the result grows with base-size like every stock widget.
// Margins are Vista's order: left, right, top, bottom.
Item {
  id: art

  property url source
  property var margins: [0, 0, 0, 0]
  property bool tile: false
  // Off for art whose stretched middle is a 1-2 px row next to a differently
  // coloured edge (start-panel columns): linear filtering bleeds the edge
  // across the whole stretch.
  property bool smooth: true
  readonly property real k: Style.spaceReal(1)

  BorderImage {
    width: art.width / art.k
    height: art.height / art.k
    scale: art.k
    transformOrigin: Item.TopLeft
    source: art.source
    smooth: art.smooth
    border.left: art.margins[0]
    border.right: art.margins[1]
    border.top: art.margins[2]
    border.bottom: art.margins[3]
    horizontalTileMode: art.tile ? BorderImage.Repeat : BorderImage.Stretch
    verticalTileMode: BorderImage.Stretch
  }
}
