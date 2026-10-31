import QtQuick
import QtQuick.Shapes
import qs.Commons

// VistaBalloon: the Vista notification-area balloon tip. InfoWindow yellow
// (#FFFFE1) with a 1 px black edge, rounded corners and a pointer tail. The
// outline is one ShapePath (scene-graph geometry, not a Canvas), so it only
// re-tessellates when the balloon's size changes.
//
// The tail hangs off the bottom edge (tailDown) or the top; its tip sits at
// `tailX` from the balloon's left with a vertical edge on the tip's side, as
// Vista drew it. Put content inside: it fills the body inside `padding`. A
// whole-balloon click area belongs on the balloon itself (parent: <balloon id>,
// z: -1), not in the content.
Item {
  id: balloon

  property real tailX: width - Style.space(40)
  property bool tailDown: true
  property bool showTail: true
  property int padding: Style.space(10)
  readonly property int tailHeight: showTail ? Style.space(18) : 0
  readonly property int tailBase: Style.space(18)
  readonly property int radius: Style.space(7)
  readonly property real bodyHeight: height - tailHeight
  default property alias content: inner.data
  readonly property alias contentArea: inner
  // Height of the content; set it when the content holds anchors.fill items.
  property real contentHeight: inner.childrenRect.height

  implicitHeight: contentHeight + 2 * padding + tailHeight

  Shape {
    anchors.fill: parent
    preferredRendererType: Shape.CurveRenderer

    ShapePath {
      id: sp
      readonly property real e: Math.max(1, Style.space(1))
      readonly property real o: e / 2                      // stroke on pixel centres
      readonly property real w: balloon.width - o
      readonly property real top: balloon.tailDown ? o : balloon.tailHeight + o
      readonly property real bot: balloon.tailDown ? balloon.bodyHeight - o : balloon.height - o
      readonly property real r: balloon.radius
      readonly property real tip: Math.max(r + balloon.tailBase, Math.min(w - r, balloon.tailX))
      readonly property real tl: balloon.showTail ? balloon.tailHeight : 0

      strokeWidth: e
      strokeColor: "#000000"
      fillColor: VistaScheme.infoWindow
      joinStyle: ShapePath.MiterJoin
      startX: o + r
      startY: top

      // Top edge (tail on top when !tailDown: base left -> tip -> base right).
      PathLine { x: balloon.tailDown ? sp.w - sp.r : sp.tip - balloon.tailBase; y: sp.top }
      PathLine { x: balloon.tailDown ? sp.w - sp.r : sp.tip; y: balloon.tailDown ? sp.top : sp.top - sp.tl }
      PathLine { x: balloon.tailDown ? sp.w - sp.r : sp.tip; y: sp.top }
      PathLine { x: sp.w - sp.r; y: sp.top }
      PathArc { x: sp.w; y: sp.top + sp.r; radiusX: sp.r; radiusY: sp.r }
      PathLine { x: sp.w; y: sp.bot - sp.r }
      PathArc { x: sp.w - sp.r; y: sp.bot; radiusX: sp.r; radiusY: sp.r }
      // Bottom edge, right to left, with the tail: vertical edge at the tip.
      PathLine { x: balloon.tailDown ? sp.tip : sp.o + sp.r; y: sp.bot }
      PathLine { x: balloon.tailDown ? sp.tip : sp.o + sp.r; y: balloon.tailDown ? sp.bot + sp.tl : sp.bot }
      PathLine { x: balloon.tailDown ? sp.tip - balloon.tailBase : sp.o + sp.r; y: sp.bot }
      PathLine { x: sp.o + sp.r; y: sp.bot }
      PathArc { x: sp.o; y: sp.bot - sp.r; radiusX: sp.r; radiusY: sp.r }
      PathLine { x: sp.o; y: sp.top + sp.r }
      PathArc { x: sp.o + sp.r; y: sp.top; radiusX: sp.r; radiusY: sp.r }
    }
  }

  Item {
    id: inner
    x: balloon.padding
    y: (balloon.tailDown ? 0 : balloon.tailHeight) + balloon.padding
    width: balloon.width - 2 * balloon.padding
    height: balloon.bodyHeight - 2 * balloon.padding
  }
}
