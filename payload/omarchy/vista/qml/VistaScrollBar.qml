import QtQuick
import qs.Commons

// VistaScrollBar: a vertical Vista scrollbar for a Flickable/ListView (`target`),
// from the scheme's ScrollBar parts: arrows (16 frames: up n/h/p/d, down,
// left, right), arrow glyphs, thumb (4 frames) and shaft. 17 px wide at
// 96 dpi ([SysMetrics] ScrollbarWidth). Hidden when everything fits.
Item {
  id: bar

  property Flickable target: null
  readonly property real ratio: target && target.contentHeight > 0 ? Math.min(1, target.height / target.contentHeight) : 1
  readonly property bool needed: ratio < 1
  readonly property int arrowH: Style.space(17)
  readonly property real track: height - 2 * arrowH
  readonly property real thumbH: Math.max(Style.space(8), track * ratio)

  function scrollBy(dy) {
    if (!target) return
    var maxY = Math.max(0, target.contentHeight - target.height) + target.originY
    target.contentY = Math.max(target.originY, Math.min(maxY, target.contentY + dy))
  }

  implicitWidth: Style.space(17)
  visible: needed

  VistaArt {
    anchors.fill: parent
    source: VistaScheme.art("scroll-shaft-0")
    margins: [0, 0, 0, 0]
  }

  component Arrow: Item {
    id: arr
    property int base: 0
    property int dir: 1
    width: bar.width
    height: bar.arrowH
    readonly property int cell: base + (am.pressed ? 2 : am.containsMouse ? 1 : 0)
    VistaArt { anchors.fill: parent; source: VistaScheme.art("scroll-arrow-" + arr.cell); margins: [5, 5, 5, 5] }
    Image {
      anchors.centerIn: parent
      width: Style.space(9)
      height: Style.space(9)
      source: VistaScheme.art("scroll-glyph-" + arr.cell)
      smooth: false
    }
    MouseArea {
      id: am
      anchors.fill: parent
      hoverEnabled: true
      onPressed: bar.scrollBy(arr.dir * Style.space(48))
    }
  }

  Arrow { base: 0; dir: -1 }
  Arrow { y: bar.height - height; base: 4; dir: 1 }

  Item {
    id: thumb
    x: Style.space(1)
    width: bar.width - Style.space(2)
    height: bar.thumbH
    y: bar.arrowH + (bar.target && bar.target.contentHeight > bar.target.height
      ? (bar.target.contentY - bar.target.originY) / (bar.target.contentHeight - bar.target.height) * (bar.track - bar.thumbH)
      : 0)
    VistaArt {
      anchors.fill: parent
      source: VistaScheme.art("scroll-thumb-" + (tm.pressed ? 2 : tm.containsMouse ? 1 : 0))
      margins: [3, 3, 3, 3]
    }
    MouseArea {
      id: tm
      anchors.fill: parent
      hoverEnabled: true
      // Measured in the bar's coordinates: the thumb itself moves under the drag.
      property real grabY: 0
      property real grabContentY: 0
      onPressed: function(mouse) { grabY = mapToItem(bar, mouse.x, mouse.y).y; grabContentY = bar.target ? bar.target.contentY : 0 }
      onPositionChanged: function(mouse) {
        if (!pressed || !bar.target || bar.track <= bar.thumbH) return
        var dy = (mapToItem(bar, mouse.x, mouse.y).y - grabY) / (bar.track - bar.thumbH) * (bar.target.contentHeight - bar.target.height)
        bar.target.contentY = grabContentY
        bar.scrollBy(dy)
      }
    }
  }
}
